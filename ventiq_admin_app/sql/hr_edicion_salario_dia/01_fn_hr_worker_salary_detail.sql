-- =============================================================
-- HR - Edicion de salario por dia (FASE 1 de 2)
--
-- 01_fn_hr_worker_salary_detail
--   Detalle dia a dia de UN trabajador dentro de un rango, para
--   alimentar el sheet desplegable del reporte de salarios.
--
-- Aplicar en: Supabase > SQL Editor
-- Idempotente: CREATE OR REPLACE.
-- =============================================================


-- -------------------------------------------------------------
-- Guard de acceso del modulo de RR.HH.
--
-- check_user_has_access_to_tienda NO contempla
-- app_dat_recursos_humanos, asi que un usuario de RR.HH. puro
-- (que no es gerente ni supervisor) seria rechazado por el.
-- Este guard acepta:
--   a) usuarios de RR.HH. de esa tienda, o
--   b) cualquiera con acceso clasico a la tienda (gerente,
--      supervisor, auditor, vendedor, almacenero, cocina).
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_hr_assert_access(
    p_id_tienda BIGINT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_es_rh BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM app_dat_recursos_humanos rh
        WHERE rh.id_tienda = p_id_tienda
          AND rh.uuid      = auth.uid()
    ) INTO v_es_rh;

    IF v_es_rh THEN
        RETURN;
    END IF;

    -- Si no es RR.HH., se exige el acceso clasico a la tienda.
    -- Esta funcion lanza excepcion por si misma si no hay acceso.
    PERFORM check_user_has_access_to_tienda(p_id_tienda);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_hr_assert_access(BIGINT)
    TO anon, authenticated, service_role;


-- -------------------------------------------------------------
-- Detalle de jornadas de un trabajador en un rango
--
-- Devuelve una fila por jornada (dia trabajado), con lo que
-- RR.HH. necesita para auditar y corregir:
--   - cantidad pagada en la unidad de su modalidad
--   - tarifa efectiva de ESA jornada (snapshot, no la del
--     trabajador: si se corrigio un dia, aqui se ve)
--   - salario base del dia, PPR del dia y total del dia
--
-- Nota sobre columnas generadas: en hr_dat_asistencia
-- horas_trabajadas y salario_total son GENERATED ALWAYS. No se
-- escriben; se derivan de hora_entrada/hora_salida,
-- cantidad_dias y salario_hora.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_hr_worker_salary_detail(
    p_id_tienda     INTEGER,
    p_id_trabajador INTEGER,
    p_fecha_desde   DATE,
    p_fecha_hasta   DATE
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_trabajador JSONB;
    v_dias       JSONB;
BEGIN
    PERFORM fn_hr_assert_access(p_id_tienda);

    -- Cabecera: datos actuales del trabajador (su configuracion
    -- vigente, que puede diferir de lo pagado en dias pasados).
    SELECT to_jsonb(x)
    INTO v_trabajador
    FROM (
        SELECT
            t.id                             AS trabajador_id,
            t.nombres,
            t.apellidos,
            rol.denominacion                 AS rol_nombre,
            COALESCE(t.tipo_salario, 'hora') AS tipo_salario,
            COALESCE(t.salario_horas, 0)     AS salario_horas,
            COALESCE(t.salario_dia, 0)       AS salario_dia,
            COALESCE(t.pago_por_resultado, 0) AS ppr_configurado
        FROM app_dat_trabajadores t
        LEFT JOIN seg_roll rol ON rol.id = t.id_roll
        WHERE t.id         = p_id_trabajador
          AND t.id_tienda  = p_id_tienda
          AND t.deleted_at IS NULL
    ) x;

    IF v_trabajador IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'message', 'Trabajador no encontrado en esta tienda'
        );
    END IF;

    SELECT COALESCE(jsonb_agg(to_jsonb(d) ORDER BY d.hora_entrada), '[]'::jsonb)
    INTO v_dias
    FROM (
        SELECT
            a.id                                     AS asistencia_id,
            a.hora_entrada,
            a.hora_salida,
            COALESCE(a.tipo_salario, 'hora')         AS tipo_salario,
            -- Tarifa aplicada a ESTA jornada ($/hora o $/dia)
            COALESCE(a.salario_hora, 0)              AS tarifa,
            a.cantidad_dias,
            COALESCE(a.horas_trabajadas, 0)          AS horas_trabajadas,
            -- Cantidad pagada en la unidad de la modalidad de la jornada
            CASE WHEN COALESCE(a.tipo_salario, 'hora') = 'dia'
                 THEN COALESCE(a.cantidad_dias, 1)
                 ELSE COALESCE(a.horas_trabajadas, 0)
            END                                      AS cantidad_pagada,
            ROUND(COALESCE(a.salario_total, 0), 2)   AS salario_total,
            ROUND(COALESCE(a.pago_por_resultado, 0), 2) AS pago_por_resultado,
            COALESCE(a.aplica_pago_resultado, FALSE) AS aplica_pago_resultado,
            ROUND(
                COALESCE(a.salario_total, 0)
                + CASE WHEN COALESCE(a.aplica_pago_resultado, FALSE)
                       THEN COALESCE(a.pago_por_resultado, 0) ELSE 0 END,
            2)                                       AS total_dia,
            (a.hora_salida IS NULL)                  AS abierta,
            a.observaciones
        FROM hr_dat_asistencia a
        WHERE a.id_tienda     = p_id_tienda
          AND a.id_trabajador = p_id_trabajador
          AND a.hora_entrada >= p_fecha_desde
          AND a.hora_entrada  < (p_fecha_hasta + INTERVAL '1 day')
    ) d;

    RETURN jsonb_build_object(
        'success',    TRUE,
        'trabajador', v_trabajador,
        'data',       v_dias
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_hr_worker_salary_detail(INTEGER, INTEGER, DATE, DATE)
    TO anon, authenticated, service_role;


-- =============================================================
-- VERIFICACION
-- =============================================================

-- 1) Las funciones existen con la firma esperada
SELECT p.proname,
       pg_get_function_identity_arguments(p.oid) AS args,
       p.prosecdef                               AS security_definer
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('fn_hr_assert_access', 'fn_hr_worker_salary_detail')
ORDER BY 1;

-- 2) Permisos concedidos (debe listar anon, authenticated, service_role)
SELECT p.proname, p.proacl::text
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('fn_hr_assert_access', 'fn_hr_worker_salary_detail');

-- 3) Prueba de lectura. Sustituir la tienda, el trabajador y las
--    fechas por datos reales de la tienda que se este probando.
--    Ejecutado desde el SQL Editor (rol postgres) auth.uid() es
--    NULL y el guard rechaza: probar desde la app o con un JWT.
-- SELECT jsonb_pretty(
--     public.fn_hr_worker_salary_detail(177, 522, '2026-08-01', '2026-08-31')
-- );
