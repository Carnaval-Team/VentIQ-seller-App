-- =============================================================
-- HR: SALARIO Y PPR POR DÍAS (además de por horas)
-- Aplicar en: Supabase > SQL Editor  (ejecutar TODO el archivo)
-- =============================================================
--
-- QUÉ CAMBIA
-- ----------
-- Cada trabajador pasa a tener una MODALIDAD de pago:
--     tipo_salario = 'hora'  ->  se paga  horas_trabajadas * salario_horas
--     tipo_salario = 'dia'   ->  se paga  cantidad_dias    * salario_dia
--
-- Un día NO equivale a 8h ni a 24h: es una unidad independiente con su
-- propia tarifa. Nunca se calculan días dividiendo horas.
--
-- El PPR (pago_por_resultado) NO cambia: sigue siendo un bono FIJO que se
-- suma UNA VEZ por jornada cerrada, en ambas modalidades. Por eso los
-- importes de los trabajadores por hora que ya existen quedan idénticos.
--
-- MIGRACIÓN
-- ---------
-- Todos los trabajadores existentes quedan en 'hora' (su comportamiento
-- actual). RR.HH. va cambiando a 'dia' uno por uno cuando lo necesite.
-- =============================================================


-- -------------------------------------------------------------
-- 1. TRABAJADORES: modalidad + tarifa diaria
--
--    salario_horas -> tarifa por HORA  (ya existía, no se toca)
--    salario_dia   -> tarifa por DÍA   (nueva, independiente)
--
--    Se usan dos columnas separadas a propósito: si RR.HH. alterna la
--    modalidad de un trabajador, la tarifa de la otra modalidad no se
--    pierde ni se reinterpreta silenciosamente.
-- -------------------------------------------------------------
ALTER TABLE app_dat_trabajadores
    ADD COLUMN IF NOT EXISTS tipo_salario TEXT NOT NULL DEFAULT 'hora',
    ADD COLUMN IF NOT EXISTS salario_dia  NUMERIC NOT NULL DEFAULT 0;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'app_dat_trabajadores_tipo_salario_check'
    ) THEN
        ALTER TABLE app_dat_trabajadores
            ADD CONSTRAINT app_dat_trabajadores_tipo_salario_check
            CHECK (tipo_salario IN ('hora', 'dia'));
    END IF;
END $$;

COMMENT ON COLUMN app_dat_trabajadores.tipo_salario IS
    'Modalidad de pago: hora (paga horas_trabajadas * salario_horas) o dia (paga cantidad_dias * salario_dia). Gobierna el salario base; el PPR es fijo por jornada en ambas.';
COMMENT ON COLUMN app_dat_trabajadores.salario_dia IS
    'Tarifa por día trabajado. Independiente de salario_horas: un día no son 8h ni 24h.';


-- -------------------------------------------------------------
-- 2. ASISTENCIA: modalidad + días pagados
--
--    tipo_salario  -> snapshot de la modalidad al fichar la ENTRADA, para
--                     que un cambio de configuración posterior no altere
--                     las jornadas ya registradas.
--    cantidad_dias -> días a pagar de esta jornada (decimal: 0.5 = medio
--                     día). Solo aplica en modalidad 'dia'.
--    salario_hora  -> snapshot de la TARIFA aplicable (por hora o por día
--                     según la modalidad). Conserva su nombre histórico
--                     para no romper el resto del sistema.
-- -------------------------------------------------------------
ALTER TABLE hr_dat_asistencia
    ADD COLUMN IF NOT EXISTS tipo_salario  TEXT NOT NULL DEFAULT 'hora',
    ADD COLUMN IF NOT EXISTS cantidad_dias NUMERIC;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'hr_dat_asistencia_tipo_salario_check'
    ) THEN
        ALTER TABLE hr_dat_asistencia
            ADD CONSTRAINT hr_dat_asistencia_tipo_salario_check
            CHECK (tipo_salario IN ('hora', 'dia'));
    END IF;
END $$;

COMMENT ON COLUMN hr_dat_asistencia.tipo_salario IS
    'Snapshot de la modalidad del trabajador al fichar entrada (hora | dia).';
COMMENT ON COLUMN hr_dat_asistencia.cantidad_dias IS
    'Días a pagar de esta jornada (decimal, 0.5 = medio día). Solo se usa si tipo_salario = dia.';
COMMENT ON COLUMN hr_dat_asistencia.salario_hora IS
    'Snapshot de la tarifa aplicable: $/hora si tipo_salario = hora, $/día si tipo_salario = dia.';


-- -------------------------------------------------------------
-- 3. RECALCULAR salario_total (columna GENERATED)
--
--    Antes:  siempre  (hora_salida - hora_entrada) * salario_hora
--    Ahora:  según la modalidad de la jornada.
--
--    horas_trabajadas NO se toca: sigue siendo el tiempo real transcurrido
--    y sigue siendo información útil también en modalidad 'dia'.
--
--    Postgres no permite ALTER de la expresión de una columna generada,
--    así que hay que soltarla y volver a crearla. Los valores se
--    recalculan solos a partir de las columnas almacenadas: no se pierde
--    ni un dato histórico.
-- -------------------------------------------------------------
ALTER TABLE hr_dat_asistencia DROP COLUMN IF EXISTS salario_total;

ALTER TABLE hr_dat_asistencia
    ADD COLUMN salario_total NUMERIC GENERATED ALWAYS AS (
        CASE
            WHEN hora_salida IS NULL THEN NULL
            WHEN tipo_salario = 'dia'
                THEN COALESCE(cantidad_dias, 1) * salario_hora
            ELSE (EXTRACT(EPOCH FROM (hora_salida - hora_entrada)) / 3600.0) * salario_hora
        END
    ) STORED;

COMMENT ON COLUMN hr_dat_asistencia.salario_total IS
    'Salario base de la jornada. Modalidad hora: horas reales * tarifa. Modalidad dia: cantidad_dias * tarifa. No incluye PPR.';


-- -------------------------------------------------------------
-- 4. CHECK-IN: snapshot de modalidad y tarifa correspondiente
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_hr_register_checkin(
    p_id_tienda      INTEGER,
    p_id_trabajador  INTEGER,
    p_hora_entrada   TIMESTAMPTZ,
    p_registrado_por UUID
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_tipo_salario   TEXT;
    v_tarifa         NUMERIC;
    v_already_working BOOLEAN;
    v_new_id         BIGINT;
BEGIN
    -- Verificar si ya esta trabajando
    SELECT EXISTS (
        SELECT 1 FROM hr_dat_asistencia
        WHERE id_trabajador = p_id_trabajador
          AND id_tienda     = p_id_tienda
          AND hora_salida  IS NULL
    ) INTO v_already_working;

    IF v_already_working THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'message', 'El trabajador ya tiene una entrada abierta'
        );
    END IF;

    -- Obtener modalidad y la tarifa que le corresponde
    SELECT COALESCE(tipo_salario, 'hora'),
           CASE WHEN COALESCE(tipo_salario, 'hora') = 'dia'
                THEN COALESCE(salario_dia, 0)
                ELSE COALESCE(salario_horas, 0)
           END
    INTO v_tipo_salario, v_tarifa
    FROM app_dat_trabajadores
    WHERE id = p_id_trabajador AND id_tienda = p_id_tienda;

    IF v_tipo_salario IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'message', 'Trabajador no encontrado'
        );
    END IF;

    INSERT INTO hr_dat_asistencia (
        id_tienda, id_trabajador, hora_entrada,
        salario_hora, tipo_salario, registrado_por
    ) VALUES (
        p_id_tienda, p_id_trabajador, p_hora_entrada,
        v_tarifa, v_tipo_salario, p_registrado_por
    ) RETURNING id INTO v_new_id;

    RETURN jsonb_build_object(
        'success',      TRUE,
        'message',      'Entrada registrada exitosamente',
        'id',           v_new_id,
        'tipo_salario', v_tipo_salario
    );
END;
$function$;


-- -------------------------------------------------------------
-- 5. CHECKOUT EN LOTE: recibe la cantidad pagada por jornada
--
--    p_cantidad[i] es lo que RR.HH. escribió en pantalla:
--      modalidad hora -> HORAS a pagar  (se ajusta hora_salida para que
--                        las horas reales coincidan, igual que antes)
--      modalidad dia  -> DÍAS a pagar   (se guarda en cantidad_dias y
--                        hora_salida queda como la hora real de salida)
--
--    p_cantidad es opcional: si llega NULL se usa la hora de salida tal
--    cual (modalidad hora) o 1 día completo (modalidad dia).
-- -------------------------------------------------------------
DROP FUNCTION IF EXISTS public.fn_hr_batch_checkout(BIGINT[], TIMESTAMPTZ, BOOLEAN[], UUID);

CREATE OR REPLACE FUNCTION public.fn_hr_batch_checkout(
    p_asistencia_ids BIGINT[],
    p_hora_salida    TIMESTAMPTZ,
    p_aplica_pago    BOOLEAN[],
    p_cerrado_por    UUID,
    p_cantidad       NUMERIC[] DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_count        INTEGER := 0;
    v_id           BIGINT;
    v_aplica       BOOLEAN;
    v_ppr          NUMERIC;
    v_tipo         TEXT;
    v_entrada      TIMESTAMPTZ;
    v_cantidad     NUMERIC;
    v_hora_salida  TIMESTAMPTZ;
    v_dias         NUMERIC;
    i              INTEGER;
BEGIN
    FOR i IN 1..COALESCE(array_length(p_asistencia_ids, 1), 0) LOOP
        v_id     := p_asistencia_ids[i];
        v_aplica := COALESCE(p_aplica_pago[i], FALSE);
        v_cantidad := CASE
                          WHEN p_cantidad IS NULL THEN NULL
                          ELSE p_cantidad[i]
                      END;

        -- PPR del trabajador + modalidad y entrada de la jornada
        SELECT COALESCE(t.pago_por_resultado, 0),
               COALESCE(a.tipo_salario, 'hora'),
               a.hora_entrada
        INTO v_ppr, v_tipo, v_entrada
        FROM hr_dat_asistencia a
        JOIN app_dat_trabajadores t ON t.id = a.id_trabajador
        WHERE a.id = v_id;

        IF NOT FOUND THEN
            CONTINUE;
        END IF;

        IF v_tipo = 'dia' THEN
            -- Días independientes: la hora de salida es la real, lo que se
            -- paga son los días indicados (1 completo si no se indicó nada).
            v_hora_salida := p_hora_salida;
            v_dias        := COALESCE(v_cantidad, 1);
        ELSE
            -- Modalidad hora: se ajusta la salida para que las horas reales
            -- coincidan con las horas que RR.HH. decidió pagar.
            v_dias := NULL;
            IF v_cantidad IS NULL THEN
                v_hora_salida := p_hora_salida;
            ELSE
                v_hora_salida := v_entrada
                                 + (v_cantidad * INTERVAL '1 hour');
            END IF;
        END IF;

        UPDATE hr_dat_asistencia
        SET hora_salida           = v_hora_salida,
            cerrado_por           = p_cerrado_por,
            cantidad_dias         = v_dias,
            aplica_pago_resultado = v_aplica,
            -- PPR: bono FIJO por jornada, no se multiplica por horas ni días
            pago_por_resultado    = CASE WHEN v_aplica THEN v_ppr ELSE 0 END,
            updated_at            = NOW()
        WHERE id = v_id AND hora_salida IS NULL;

        IF FOUND THEN
            v_count := v_count + 1;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', format('%s salida(s) registrada(s)', v_count),
        'count',   v_count
    );
END;
$function$;


-- -------------------------------------------------------------
-- 6. TRABAJADORES PARA CHECK-IN: expone modalidad y ambas tarifas
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_hr_workers_for_checkin(
    p_id_tienda INTEGER
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_workers JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(w), '[]'::jsonb)
    INTO v_workers
    FROM (
        SELECT
            t.id                                AS trabajador_id,
            t.nombres,
            t.apellidos,
            COALESCE(t.tipo_salario, 'hora')    AS tipo_salario,
            COALESCE(t.salario_horas, 0)        AS salario_horas,
            COALESCE(t.salario_dia, 0)          AS salario_dia,
            -- tarifa aplicable según la modalidad
            CASE WHEN COALESCE(t.tipo_salario, 'hora') = 'dia'
                 THEN COALESCE(t.salario_dia, 0)
                 ELSE COALESCE(t.salario_horas, 0)
            END                                 AS salario_hora,
            COALESCE(t.pago_por_resultado, 0)   AS pago_por_resultado,
            r.denominacion                      AS rol_nombre
        FROM app_dat_trabajadores t
        LEFT JOIN seg_roll r ON r.id = t.id_roll
        WHERE t.id_tienda   = p_id_tienda
          AND t.deleted_at IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM hr_dat_asistencia a
              WHERE a.id_trabajador = t.id
                AND a.id_tienda     = p_id_tienda
                AND a.hora_salida  IS NULL
          )
        ORDER BY t.nombres, t.apellidos
    ) w;

    RETURN jsonb_build_object('success', TRUE, 'data', v_workers);
END;
$function$;


-- -------------------------------------------------------------
-- 7. TRABAJANDO AHORA: modalidad + días por defecto
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_hr_workers_currently_working(
    p_id_tienda INTEGER
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_workers JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(w), '[]'::jsonb)
    INTO v_workers
    FROM (
        SELECT
            a.id                                AS asistencia_id,
            a.id_trabajador                     AS trabajador_id,
            t.nombres,
            t.apellidos,
            a.hora_entrada,
            a.salario_hora,
            COALESCE(a.tipo_salario, 'hora')    AS tipo_salario,
            COALESCE(t.pago_por_resultado, 0)   AS pago_por_resultado,
            r.denominacion                      AS rol_nombre,
            EXTRACT(EPOCH FROM (NOW() - a.hora_entrada)) / 3600.0 AS horas_transcurridas
        FROM hr_dat_asistencia a
        JOIN app_dat_trabajadores t ON t.id = a.id_trabajador
        LEFT JOIN seg_roll r ON r.id = t.id_roll
        WHERE a.id_tienda  = p_id_tienda
          AND a.hora_salida IS NULL
        ORDER BY a.hora_entrada ASC
    ) w;

    RETURN jsonb_build_object('success', TRUE, 'data', v_workers);
END;
$function$;


-- -------------------------------------------------------------
-- 8. HISTORIAL DE ASISTENCIA: modalidad + días pagados
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_hr_attendance_history(
    p_id_tienda   INTEGER,
    p_fecha_desde DATE,
    p_fecha_hasta DATE
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_records JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.hora_entrada DESC), '[]'::jsonb)
    INTO v_records
    FROM (
        SELECT
            a.id                                     AS asistencia_id,
            a.id_trabajador                          AS trabajador_id,
            t.nombres,
            t.apellidos,
            a.hora_entrada,
            a.hora_salida,
            a.salario_hora,
            COALESCE(a.tipo_salario, 'hora')         AS tipo_salario,
            a.cantidad_dias,
            COALESCE(a.horas_trabajadas, 0)          AS horas_trabajadas,
            COALESCE(a.salario_total, 0)             AS salario_total,
            COALESCE(t.pago_por_resultado, 0)        AS pago_por_resultado,
            COALESCE(a.aplica_pago_resultado, FALSE) AS aplica_pago_resultado,
            ro.denominacion                          AS rol_nombre,
            a.observaciones
        FROM hr_dat_asistencia a
        JOIN app_dat_trabajadores t ON t.id = a.id_trabajador
        LEFT JOIN seg_roll ro       ON ro.id = t.id_roll
        WHERE a.id_tienda    = p_id_tienda
          AND a.hora_entrada >= p_fecha_desde
          AND a.hora_entrada  < (p_fecha_hasta + INTERVAL '1 day')
    ) r;

    RETURN jsonb_build_object('success', TRUE, 'data', v_records);
END;
$function$;


-- -------------------------------------------------------------
-- 9. DASHBOARD: totales de horas Y de días, en paralelo
--
--    total_dias unifica ambas modalidades:
--      modalidad dia  -> los días pagados (cantidad_dias)
--      modalidad hora -> 1 por jornada cerrada
--    Así el KPI de días es sumable con plantilla mixta.
--
--    total_horas solo acumula jornadas por HORA: sumar las horas reales de
--    un trabajador por día induciría a pensar que su pago sale de ahí.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_hr_dashboard_summary(
    p_id_tienda   INTEGER,
    p_fecha_desde DATE,
    p_fecha_hasta DATE
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_total_horas        NUMERIC;
    v_total_dias         NUMERIC;
    v_total_salario_base NUMERIC;
    v_total_ppr          NUMERIC;
    v_total_general      NUMERIC;
    v_registros          INTEGER;
    v_reg_hora           INTEGER;
    v_reg_dia            INTEGER;
    v_daily_data         JSONB;
BEGIN
    SELECT
        COALESCE(SUM(CASE WHEN COALESCE(tipo_salario, 'hora') = 'hora'
                          THEN horas_trabajadas ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN COALESCE(tipo_salario, 'hora') = 'dia'
                          THEN COALESCE(cantidad_dias, 1) ELSE 1 END), 0),
        COALESCE(SUM(salario_total), 0),
        COALESCE(SUM(CASE WHEN aplica_pago_resultado THEN pago_por_resultado ELSE 0 END), 0),
        COUNT(*),
        COUNT(*) FILTER (WHERE COALESCE(tipo_salario, 'hora') = 'hora'),
        COUNT(*) FILTER (WHERE COALESCE(tipo_salario, 'hora') = 'dia')
    INTO v_total_horas, v_total_dias, v_total_salario_base, v_total_ppr,
         v_registros, v_reg_hora, v_reg_dia
    FROM hr_dat_asistencia
    WHERE id_tienda    = p_id_tienda
      AND hora_entrada >= p_fecha_desde
      AND hora_entrada  < (p_fecha_hasta + INTERVAL '1 day')
      AND hora_salida  IS NOT NULL;

    v_total_general := v_total_salario_base + v_total_ppr;

    SELECT COALESCE(jsonb_agg(d ORDER BY d->>'fecha'), '[]'::jsonb)
    INTO v_daily_data
    FROM (
        SELECT jsonb_build_object(
            'fecha',   DATE(hora_entrada)::TEXT,
            'horas',   COALESCE(SUM(CASE WHEN COALESCE(tipo_salario, 'hora') = 'hora'
                                         THEN horas_trabajadas ELSE 0 END), 0),
            'dias',    COALESCE(SUM(CASE WHEN COALESCE(tipo_salario, 'hora') = 'dia'
                                         THEN COALESCE(cantidad_dias, 1) ELSE 1 END), 0),
            'salario', COALESCE(SUM(salario_total), 0),
            'ppr',     COALESCE(SUM(CASE WHEN aplica_pago_resultado THEN pago_por_resultado ELSE 0 END), 0)
        ) AS d
        FROM hr_dat_asistencia
        WHERE id_tienda    = p_id_tienda
          AND hora_entrada >= p_fecha_desde
          AND hora_entrada  < (p_fecha_hasta + INTERVAL '1 day')
          AND hora_salida  IS NOT NULL
        GROUP BY DATE(hora_entrada)
    ) sub;

    RETURN jsonb_build_object(
        'success', TRUE,
        'data', jsonb_build_object(
            'total_horas',        ROUND(v_total_horas, 2),
            'total_dias',         ROUND(v_total_dias, 2),
            'total_salario_base', ROUND(v_total_salario_base, 2),
            'total_ppr',          ROUND(v_total_ppr, 2),
            'total_general',      ROUND(v_total_general, 2),
            'total_registros',    v_registros,
            'registros_hora',     v_reg_hora,
            'registros_dia',      v_reg_dia,
            'daily_data',         v_daily_data
        )
    );
END;
$function$;


-- -------------------------------------------------------------
-- 10. TOP TRABAJADORES: modalidad, tarifa y días
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_hr_top_workers_by_pay(
    p_id_tienda   INTEGER,
    p_fecha_desde DATE,
    p_fecha_hasta DATE,
    p_limit       INTEGER DEFAULT 10
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_workers JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(w), '[]'::jsonb)
    INTO v_workers
    FROM (
        SELECT
            t.id                             AS trabajador_id,
            t.nombres,
            t.apellidos,
            r.denominacion                   AS rol_nombre,
            COALESCE(t.tipo_salario, 'hora') AS tipo_salario,
            -- tarifa configurada actualmente para su modalidad
            CASE WHEN COALESCE(t.tipo_salario, 'hora') = 'dia'
                 THEN COALESCE(t.salario_dia, 0)
                 ELSE COALESCE(t.salario_horas, 0)
            END                              AS tarifa,
            ROUND(COALESCE(SUM(CASE WHEN COALESCE(a.tipo_salario, 'hora') = 'hora'
                                    THEN a.horas_trabajadas ELSE 0 END), 0), 2) AS total_horas,
            ROUND(COALESCE(SUM(CASE WHEN COALESCE(a.tipo_salario, 'hora') = 'dia'
                                    THEN COALESCE(a.cantidad_dias, 1) ELSE 1 END), 0), 2) AS total_dias,
            ROUND(COALESCE(SUM(a.salario_total), 0), 2) AS total_salario_base,
            ROUND(COALESCE(SUM(CASE WHEN a.aplica_pago_resultado THEN a.pago_por_resultado ELSE 0 END), 0), 2) AS total_ppr,
            ROUND(COALESCE(SUM(a.salario_total), 0)
                  + COALESCE(SUM(CASE WHEN a.aplica_pago_resultado THEN a.pago_por_resultado ELSE 0 END), 0), 2) AS total_general,
            BOOL_OR(a.aplica_pago_resultado) AS tiene_ppr
        FROM hr_dat_asistencia a
        JOIN app_dat_trabajadores t ON t.id = a.id_trabajador
        LEFT JOIN seg_roll r ON r.id = t.id_roll
        WHERE a.id_tienda    = p_id_tienda
          AND a.hora_entrada >= p_fecha_desde
          AND a.hora_entrada  < (p_fecha_hasta + INTERVAL '1 day')
          AND a.hora_salida  IS NOT NULL
        GROUP BY t.id, t.nombres, t.apellidos, r.denominacion,
                 t.tipo_salario, t.salario_horas, t.salario_dia
        ORDER BY total_general DESC
        LIMIT p_limit
    ) w;

    RETURN jsonb_build_object('success', TRUE, 'data', v_workers);
END;
$function$;


-- -------------------------------------------------------------
-- 11. REPORTE DE SALARIOS: modalidad, tarifa, horas y días
--
--    dias_trabajados mantiene su significado ya corregido (cada jornada
--    registrada cuenta como un día, nunca horas/24) y en modalidad 'dia'
--    pasa a reflejar los días efectivamente pagados.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_hr_salary_report(
    p_id_tienda   INTEGER,
    p_fecha_desde DATE,
    p_fecha_hasta DATE
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_report JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(r), '[]'::jsonb)
    INTO v_report
    FROM (
        SELECT
            t.id                              AS trabajador_id,
            t.nombres,
            t.apellidos,
            rol.denominacion                  AS rol_nombre,
            COALESCE(t.tipo_salario, 'hora')   AS tipo_salario,
            COALESCE(t.salario_horas, 0)       AS salario_horas,
            COALESCE(t.salario_dia, 0)         AS salario_dia,
            -- tarifa aplicable a su modalidad (para la columna "Tarifa")
            CASE WHEN COALESCE(t.tipo_salario, 'hora') = 'dia'
                 THEN COALESCE(t.salario_dia, 0)
                 ELSE COALESCE(t.salario_horas, 0)
            END                               AS tarifa,
            -- horas solo de jornadas pagadas por hora
            ROUND(COALESCE(SUM(CASE WHEN COALESCE(a.tipo_salario, 'hora') = 'hora'
                                    THEN a.horas_trabajadas ELSE 0 END), 0), 2) AS total_horas,
            ROUND(COALESCE(SUM(a.salario_total), 0), 2) AS total_salario_base,
            ROUND(COALESCE(SUM(
                CASE WHEN a.aplica_pago_resultado
                     THEN a.pago_por_resultado ELSE 0 END
            ), 0), 2)                          AS total_ppr,
            ROUND(
                COALESCE(SUM(a.salario_total), 0)
                + COALESCE(SUM(CASE WHEN a.aplica_pago_resultado
                                    THEN a.pago_por_resultado ELSE 0 END), 0),
            2)                                 AS total_general,
            -- Modalidad dia -> días pagados. Modalidad hora -> 1 por jornada.
            -- Nunca se derivan de horas/24.
            ROUND(COALESCE(SUM(CASE WHEN COALESCE(a.tipo_salario, 'hora') = 'dia'
                                    THEN COALESCE(a.cantidad_dias, 1)
                                    ELSE 1 END), 0), 2) AS dias_trabajados
        FROM app_dat_trabajadores t
        LEFT JOIN seg_roll rol ON rol.id = t.id_roll
        LEFT JOIN hr_dat_asistencia a
            ON  a.id_trabajador  = t.id
            AND a.id_tienda      = p_id_tienda
            AND a.hora_entrada  >= p_fecha_desde
            AND a.hora_entrada   < (p_fecha_hasta + INTERVAL '1 day')
            AND a.hora_salida   IS NOT NULL   -- solo días cerrados (con salida)
        WHERE t.id_tienda   = p_id_tienda
          AND t.deleted_at IS NULL
        GROUP BY t.id, t.nombres, t.apellidos, rol.denominacion,
                 t.tipo_salario, t.salario_horas, t.salario_dia
        -- Antes filtraba por horas > 0, lo que ocultaba a los trabajadores
        -- por día. Ahora entra quien tenga alguna jornada cerrada.
        HAVING COUNT(a.id) > 0
        ORDER BY total_general DESC
    ) r;

    RETURN jsonb_build_object('success', TRUE, 'data', v_report);
END;
$function$;


-- -------------------------------------------------------------
-- 12. ACTUALIZAR SALARIO: modalidad + tarifa diaria, con auditoría
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_hr_update_worker_salary(
    p_id_trabajador      INTEGER,
    p_id_tienda          INTEGER,
    p_salario_horas      NUMERIC,
    p_pago_por_resultado NUMERIC,
    p_modificado_por     UUID,
    p_motivo             TEXT DEFAULT NULL,
    p_tipo_salario       TEXT DEFAULT NULL,
    p_salario_dia        NUMERIC DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_old_salario NUMERIC;
    v_old_ppr     NUMERIC;
    v_old_tipo    TEXT;
    v_old_dia     NUMERIC;
    v_new_tipo    TEXT;
    v_new_dia     NUMERIC;
BEGIN
    SELECT COALESCE(salario_horas, 0), COALESCE(pago_por_resultado, 0),
           COALESCE(tipo_salario, 'hora'), COALESCE(salario_dia, 0)
    INTO v_old_salario, v_old_ppr, v_old_tipo, v_old_dia
    FROM app_dat_trabajadores
    WHERE id = p_id_trabajador AND id_tienda = p_id_tienda;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'message', 'Trabajador no encontrado'
        );
    END IF;

    -- Parámetros nuevos opcionales: si no llegan, se conserva lo actual
    v_new_tipo := COALESCE(p_tipo_salario, v_old_tipo);
    v_new_dia  := COALESCE(p_salario_dia,  v_old_dia);

    IF v_new_tipo NOT IN ('hora', 'dia') THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'message', format('Modalidad de salario inválida: %s', v_new_tipo)
        );
    END IF;

    IF v_old_salario IS DISTINCT FROM p_salario_horas THEN
        INSERT INTO hr_dat_auditoria_salario (
            id_trabajador, id_tienda, campo_modificado,
            valor_anterior, valor_nuevo, modificado_por, motivo
        ) VALUES (
            p_id_trabajador, p_id_tienda, 'salario_horas',
            v_old_salario::TEXT, p_salario_horas::TEXT, p_modificado_por, p_motivo
        );
    END IF;

    IF v_old_dia IS DISTINCT FROM v_new_dia THEN
        INSERT INTO hr_dat_auditoria_salario (
            id_trabajador, id_tienda, campo_modificado,
            valor_anterior, valor_nuevo, modificado_por, motivo
        ) VALUES (
            p_id_trabajador, p_id_tienda, 'salario_dia',
            v_old_dia::TEXT, v_new_dia::TEXT, p_modificado_por, p_motivo
        );
    END IF;

    IF v_old_tipo IS DISTINCT FROM v_new_tipo THEN
        INSERT INTO hr_dat_auditoria_salario (
            id_trabajador, id_tienda, campo_modificado,
            valor_anterior, valor_nuevo, modificado_por, motivo
        ) VALUES (
            p_id_trabajador, p_id_tienda, 'tipo_salario',
            v_old_tipo, v_new_tipo, p_modificado_por, p_motivo
        );
    END IF;

    IF v_old_ppr IS DISTINCT FROM p_pago_por_resultado THEN
        INSERT INTO hr_dat_auditoria_salario (
            id_trabajador, id_tienda, campo_modificado,
            valor_anterior, valor_nuevo, modificado_por, motivo
        ) VALUES (
            p_id_trabajador, p_id_tienda, 'pago_por_resultado',
            v_old_ppr::TEXT, p_pago_por_resultado::TEXT, p_modificado_por, p_motivo
        );
    END IF;

    UPDATE app_dat_trabajadores
    SET salario_horas      = p_salario_horas,
        salario_dia        = v_new_dia,
        tipo_salario       = v_new_tipo,
        pago_por_resultado = p_pago_por_resultado
    WHERE id = p_id_trabajador AND id_tienda = p_id_tienda;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Salario actualizado exitosamente'
    );
END;
$function$;


-- -------------------------------------------------------------
-- 13. LISTADO DE TRABAJADORES: exponer modalidad, tarifa diaria y PPR
--
--     BUG PREEXISTENTE QUE SE CORRIGE AQUÍ:
--     esta función nunca devolvía pago_por_resultado, así que la pantalla
--     de configuración de RR.HH. mostraba siempre "PPR 0.00" y al guardar
--     escribía ese 0 encima del PPR real del trabajador.
--     Ahora se devuelve, junto con tipo_salario y salario_dia.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_listar_trabajadores_tienda(
    p_id_tienda            BIGINT,
    p_usuario_solicitante  UUID
)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
    v_result JSON;
BEGIN
    SELECT json_build_object(
        'success', true,
        'message', 'Trabajadores obtenidos exitosamente',
        'data', COALESCE(json_agg(trabajador_data), '[]'::json)
    ) INTO v_result
    FROM (
        SELECT DISTINCT ON (t.id)
            t.id AS trabajador_id,
            t.nombres,
            t.apellidos,
            t.created_at AS fecha_creacion,
            t.maneja_apertura_control,
            t.salario_horas,
            -- 🆕 modalidad de pago + tarifa diaria + PPR
            COALESCE(t.tipo_salario, 'hora')  AS tipo_salario,
            COALESCE(t.salario_dia, 0)        AS salario_dia,
            COALESCE(t.pago_por_resultado, 0) AS pago_por_resultado,
            COALESCE(t.id_roll, 0) AS rol_id,

            COALESCE(
                (SELECT r.denominacion FROM seg_roll r WHERE r.id = t.id_roll),
                'Sin Rol'
            ) AS rol_nombre,

            CASE
                WHEN EXISTS(SELECT 1 FROM app_dat_gerente WHERE id_trabajador = t.id) THEN 'gerente'
                WHEN EXISTS(SELECT 1 FROM app_dat_supervisor WHERE id_trabajador = t.id) THEN 'supervisor'
                WHEN EXISTS(SELECT 1 FROM auditor WHERE id_trabajador = t.id) THEN 'auditor'
                WHEN EXISTS(SELECT 1 FROM app_dat_recursos_humanos WHERE id_trabajador = t.id) THEN 'recursos_humanos'
                WHEN EXISTS(SELECT 1 FROM app_dat_vendedor WHERE id_trabajador = t.id) THEN 'vendedor'
                WHEN EXISTS(SELECT 1 FROM app_dat_almacenero WHERE id_trabajador = t.id) THEN 'almacenero'
                ELSE 'sin_rol'
            END AS tipo_rol,

            jsonb_build_object(
                'tpv_id', (SELECT v.id_tpv FROM app_dat_vendedor v WHERE v.id_trabajador = t.id LIMIT 1),
                'tpv_denominacion', (SELECT tpv.denominacion FROM app_dat_vendedor v
                                     LEFT JOIN app_dat_tpv tpv ON v.id_tpv = tpv.id
                                     WHERE v.id_trabajador = t.id LIMIT 1),
                'numero_confirmacion', (SELECT v.numero_confirmacion FROM app_dat_vendedor v WHERE v.id_trabajador = t.id LIMIT 1),

                'almacen_id', (SELECT a.id_almacen FROM app_dat_almacenero a WHERE a.id_trabajador = t.id LIMIT 1),
                'almacen_denominacion', (SELECT alm.denominacion FROM app_dat_almacenero a
                                        LEFT JOIN app_dat_almacen alm ON a.id_almacen = alm.id
                                        WHERE a.id_trabajador = t.id LIMIT 1),
                'almacen_direccion', (SELECT alm.direccion FROM app_dat_almacenero a
                                     LEFT JOIN app_dat_almacen alm ON a.id_almacen = alm.id
                                     WHERE a.id_trabajador = t.id LIMIT 1),
                'almacen_ubicacion', (SELECT alm.ubicacion FROM app_dat_almacenero a
                                     LEFT JOIN app_dat_almacen alm ON a.id_almacen = alm.id
                                     WHERE a.id_trabajador = t.id LIMIT 1)
            ) AS datos_especificos,

            t.uuid AS usuario_uuid,

            CASE WHEN t.uuid IS NOT NULL THEN true ELSE false END AS tiene_usuario,

            EXISTS(SELECT 1 FROM app_dat_gerente WHERE id_trabajador = t.id) AS es_gerente,
            EXISTS(SELECT 1 FROM app_dat_supervisor WHERE id_trabajador = t.id) AS es_supervisor,
            EXISTS(SELECT 1 FROM app_dat_vendedor WHERE id_trabajador = t.id) AS es_vendedor,
            EXISTS(SELECT 1 FROM app_dat_almacenero WHERE id_trabajador = t.id) AS es_almacenero,
            EXISTS(SELECT 1 FROM auditor WHERE id_trabajador = t.id) AS es_auditor,
            EXISTS(SELECT 1 FROM app_dat_recursos_humanos WHERE id_trabajador = t.id) AS es_recursos_humanos

        FROM app_dat_trabajadores t
        WHERE t.id_tienda = p_id_tienda
          AND t.deleted_at IS NULL
        ORDER BY t.id, t.created_at DESC
    ) AS trabajador_data;

    RETURN v_result;
END;
$function$;


-- =============================================================
-- 14. VERIFICACIÓN POST-MIGRACIÓN  (ejecutar y comparar)
--
--     Al migrar, TODOS los trabajadores y todas las jornadas quedan en
--     modalidad 'hora', que es su comportamiento actual. Por lo tanto la
--     columna generada salario_total debe recalcularse al MISMO valor.
--
--     Valores esperados (medidos antes de migrar, 2026-08-11):
--         asistencias_totales .... 951
--         cerradas ............... 939
--         abiertas ...............  12
--         suma_salario ........... 2249265.90   <-- debe coincidir EXACTO
--
--     Si suma_salario cambia, algo salió mal: NO continuar y revisar.
-- =============================================================
SELECT
    COUNT(*)                                             AS asistencias_totales,
    COUNT(*) FILTER (WHERE hora_salida IS NOT NULL)      AS cerradas,
    COUNT(*) FILTER (WHERE hora_salida IS NULL)          AS abiertas,
    ROUND(COALESCE(SUM(salario_total), 0), 2)            AS suma_salario,
    COUNT(*) FILTER (WHERE tipo_salario = 'dia')         AS jornadas_por_dia
FROM hr_dat_asistencia;
