-- =============================================================
-- HR - Edicion de salario por dia (FASE 2 de 2)
--
-- 02_fn_hr_update_attendance_pay
--   Corrige el pago de UNA jornada ya cerrada: cantidad pagada,
--   total del salario base y PPR de ese dia.
--
-- Requiere 01_fn_hr_worker_salary_detail.sql (usa fn_hr_assert_access).
-- Aplicar en: Supabase > SQL Editor
-- Idempotente: CREATE OR REPLACE.
--
-- POR QUE SE AJUSTA LA TARIFA Y NO EL TOTAL
-- -----------------------------------------
-- En hr_dat_asistencia las columnas horas_trabajadas y
-- salario_total son GENERATED ALWAYS:
--   horas_trabajadas = (hora_salida - hora_entrada) en horas
--   salario_total    = 'dia'  -> COALESCE(cantidad_dias,1) * salario_hora
--                      'hora' -> horas_trabajadas * salario_hora
-- No se pueden escribir. Para dejar el total del dia en el
-- importe que RR.HH. indica se recalcula salario_hora, que ya es
-- un snapshot POR JORNADA (no toca la tarifa del trabajador):
--   tarifa = total_deseado / cantidad_pagada
-- En modalidad hora la cantidad se materializa moviendo
-- hora_salida, igual que hace fn_hr_batch_checkout.
-- =============================================================

CREATE OR REPLACE FUNCTION public.fn_hr_update_attendance_pay(
    p_asistencia_id   BIGINT,
    p_id_tienda       BIGINT,
    p_modificado_por  UUID,
    -- Todos los campos de cambio son opcionales: NULL = no tocar.
    p_salario_total   NUMERIC DEFAULT NULL,  -- salario base del dia
    p_cantidad        NUMERIC DEFAULT NULL,  -- horas o dias a pagar
    p_aplica_ppr      BOOLEAN DEFAULT NULL,  -- FALSE = quitar el PPR del dia
    p_ppr             NUMERIC DEFAULT NULL,  -- monto del PPR de ese dia
    p_motivo          TEXT    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_trabajador     BIGINT;
    v_tipo           TEXT;
    v_entrada        TIMESTAMPTZ;
    v_salida         TIMESTAMPTZ;
    v_tarifa_ant     NUMERIC;
    v_cant_dias_ant  NUMERIC;
    v_horas_ant      NUMERIC;
    v_total_ant      NUMERIC;
    v_ppr_ant        NUMERIC;
    v_aplica_ant     BOOLEAN;

    v_cantidad       NUMERIC;   -- cantidad final a pagar
    v_cant_dias      NUMERIC;   -- valor final de cantidad_dias
    v_salida_nueva   TIMESTAMPTZ;
    v_tarifa         NUMERIC;
    v_ppr            NUMERIC;
    v_aplica         BOOLEAN;

    v_total_nuevo    NUMERIC;
    v_horas_nuevas   NUMERIC;
BEGIN
    PERFORM fn_hr_assert_access(p_id_tienda);

    SELECT a.id_trabajador,
           COALESCE(a.tipo_salario, 'hora'),
           a.hora_entrada,
           a.hora_salida,
           COALESCE(a.salario_hora, 0),
           a.cantidad_dias,
           COALESCE(a.horas_trabajadas, 0),
           COALESCE(a.salario_total, 0),
           COALESCE(a.pago_por_resultado, 0),
           COALESCE(a.aplica_pago_resultado, FALSE)
    INTO v_trabajador, v_tipo, v_entrada, v_salida, v_tarifa_ant,
         v_cant_dias_ant, v_horas_ant, v_total_ant, v_ppr_ant, v_aplica_ant
    FROM hr_dat_asistencia a
    WHERE a.id        = p_asistencia_id
      AND a.id_tienda = p_id_tienda;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'message', 'Jornada no encontrada o no pertenece a esta tienda'
        );
    END IF;

    -- Una jornada abierta todavia no tiene pago: se cierra desde
    -- Firmar salida, no se corrige aqui.
    IF v_salida IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'message', 'La jornada esta abierta: cierrela primero en Firmar salida'
        );
    END IF;

    IF p_salario_total IS NOT NULL AND p_salario_total < 0 THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'message', 'El salario del dia no puede ser negativo'
        );
    END IF;

    IF p_cantidad IS NOT NULL AND p_cantidad <= 0 THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'message', format('La cantidad de %s debe ser mayor que cero',
                              CASE WHEN v_tipo = 'dia' THEN 'dias' ELSE 'horas' END)
        );
    END IF;

    IF p_ppr IS NOT NULL AND p_ppr < 0 THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'message', 'El PPR no puede ser negativo'
        );
    END IF;

    -- ---------------------------------------------------------
    -- 1. Cantidad pagada (dias o horas segun la modalidad)
    -- ---------------------------------------------------------
    IF v_tipo = 'dia' THEN
        v_cantidad     := COALESCE(p_cantidad, COALESCE(v_cant_dias_ant, 1));
        v_cant_dias    := v_cantidad;
        -- La hora de salida real del dia no se toca: en modalidad dia
        -- no define el importe.
        v_salida_nueva := v_salida;
    ELSE
        v_cantidad  := COALESCE(p_cantidad, v_horas_ant);
        v_cant_dias := v_cant_dias_ant;
        IF p_cantidad IS NULL THEN
            v_salida_nueva := v_salida;
        ELSE
            -- Horas pagadas = horas reales: se mueve la salida.
            v_salida_nueva := v_entrada + (v_cantidad * INTERVAL '1 hour');
        END IF;
    END IF;

    IF v_cantidad IS NULL OR v_cantidad <= 0 THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'message', 'La jornada no tiene una cantidad pagada valida'
        );
    END IF;

    -- ---------------------------------------------------------
    -- 2. Tarifa derivada del total deseado
    -- ---------------------------------------------------------
    IF p_salario_total IS NULL THEN
        -- Sin total nuevo se conserva la tarifa: si cambio la cantidad,
        -- el total se recalcula solo (cantidad x tarifa).
        v_tarifa := v_tarifa_ant;
    ELSE
        v_tarifa := ROUND(p_salario_total / v_cantidad, 10);
    END IF;

    -- ---------------------------------------------------------
    -- 3. PPR del dia (bono fijo por jornada)
    -- ---------------------------------------------------------
    v_aplica := COALESCE(p_aplica_ppr, v_aplica_ant);
    IF v_aplica THEN
        -- Si se activa el PPR sin indicar monto y la jornada no tenia,
        -- se toma el PPR configurado al trabajador.
        v_ppr := COALESCE(
            p_ppr,
            NULLIF(v_ppr_ant, 0),
            (SELECT COALESCE(t.pago_por_resultado, 0)
             FROM app_dat_trabajadores t WHERE t.id = v_trabajador),
            0
        );
    ELSE
        -- Quitar el PPR del dia: se apaga y se deja en cero para que
        -- ningun reporte lo sume por error.
        v_ppr := 0;
    END IF;

    -- ---------------------------------------------------------
    -- 4. Aplicar
    -- ---------------------------------------------------------
    UPDATE hr_dat_asistencia
    SET hora_salida           = v_salida_nueva,
        cantidad_dias         = v_cant_dias,
        salario_hora          = v_tarifa,
        pago_por_resultado    = v_ppr,
        aplica_pago_resultado = v_aplica,
        updated_at            = NOW()
    WHERE id        = p_asistencia_id
      AND id_tienda = p_id_tienda;

    SELECT COALESCE(a.salario_total, 0), COALESCE(a.horas_trabajadas, 0)
    INTO v_total_nuevo, v_horas_nuevas
    FROM hr_dat_asistencia a
    WHERE a.id = p_asistencia_id;

    -- ---------------------------------------------------------
    -- 5. Auditoria (una fila por campo que realmente cambio)
    -- ---------------------------------------------------------
    IF ROUND(v_total_nuevo, 2) <> ROUND(v_total_ant, 2) THEN
        INSERT INTO hr_dat_auditoria_salario (
            id_trabajador, id_tienda, campo_modificado,
            valor_anterior, valor_nuevo, modificado_por, motivo
        ) VALUES (
            v_trabajador, p_id_tienda,
            format('asistencia[%s].salario_total', p_asistencia_id),
            ROUND(v_total_ant, 2)::TEXT, ROUND(v_total_nuevo, 2)::TEXT,
            p_modificado_por, p_motivo
        );
    END IF;

    IF v_aplica <> v_aplica_ant OR ROUND(v_ppr, 2) <> ROUND(v_ppr_ant, 2) THEN
        INSERT INTO hr_dat_auditoria_salario (
            id_trabajador, id_tienda, campo_modificado,
            valor_anterior, valor_nuevo, modificado_por, motivo
        ) VALUES (
            v_trabajador, p_id_tienda,
            format('asistencia[%s].pago_por_resultado', p_asistencia_id),
            format('%s (aplica: %s)', ROUND(v_ppr_ant, 2), v_aplica_ant),
            format('%s (aplica: %s)', ROUND(v_ppr, 2), v_aplica),
            p_modificado_por, p_motivo
        );
    END IF;

    IF p_cantidad IS NOT NULL THEN
        INSERT INTO hr_dat_auditoria_salario (
            id_trabajador, id_tienda, campo_modificado,
            valor_anterior, valor_nuevo, modificado_por, motivo
        ) VALUES (
            v_trabajador, p_id_tienda,
            format('asistencia[%s].cantidad_%s', p_asistencia_id,
                   CASE WHEN v_tipo = 'dia' THEN 'dias' ELSE 'horas' END),
            ROUND(CASE WHEN v_tipo = 'dia'
                       THEN COALESCE(v_cant_dias_ant, 1)
                       ELSE v_horas_ant END, 2)::TEXT,
            ROUND(v_cantidad, 2)::TEXT,
            p_modificado_por, p_motivo
        );
    END IF;

    RETURN jsonb_build_object(
        'success',          TRUE,
        'message',          'Pago del dia actualizado correctamente',
        'asistencia_id',    p_asistencia_id,
        'tipo_salario',     v_tipo,
        'cantidad_pagada',  ROUND(v_cantidad, 2),
        'horas_trabajadas', ROUND(v_horas_nuevas, 2),
        'tarifa',           v_tarifa,
        'salario_total',    ROUND(v_total_nuevo, 2),
        'pago_por_resultado', ROUND(v_ppr, 2),
        'aplica_pago_resultado', v_aplica,
        'total_dia',        ROUND(v_total_nuevo + CASE WHEN v_aplica THEN v_ppr ELSE 0 END, 2)
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_hr_update_attendance_pay(
    BIGINT, BIGINT, UUID, NUMERIC, NUMERIC, BOOLEAN, NUMERIC, TEXT
) TO anon, authenticated, service_role;


-- =============================================================
-- VERIFICACION
-- =============================================================

-- 1) Firma y modo de seguridad
SELECT p.proname,
       pg_get_function_identity_arguments(p.oid) AS args,
       p.prosecdef                               AS security_definer
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_hr_update_attendance_pay';

-- 2) Permisos (debe listar anon, authenticated, service_role)
SELECT p.proname, p.proacl::text
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_hr_update_attendance_pay';

-- 3) Estado de una jornada antes / despues de corregirla.
--    Sustituir el id de jornada y la tienda por datos reales.
-- SELECT id, tipo_salario, hora_entrada, hora_salida, salario_hora,
--        cantidad_dias, horas_trabajadas, salario_total,
--        pago_por_resultado, aplica_pago_resultado
-- FROM hr_dat_asistencia WHERE id = 1005;

--    Ejemplo: dejar el dia en 450 de salario base y quitarle el PPR.
--    Desde el SQL Editor auth.uid() es NULL y el guard rechaza:
--    probar desde la app o con un JWT de usuario de RR.HH.
-- SELECT jsonb_pretty(
--     public.fn_hr_update_attendance_pay(
--         p_asistencia_id  => 1005,
--         p_id_tienda      => 177,
--         p_modificado_por => '00000000-0000-0000-0000-000000000000'::uuid,
--         p_salario_total  => 450,
--         p_aplica_ppr     => FALSE,
--         p_motivo         => 'Ajuste manual de RR.HH.'
--     )
-- );

-- 4) Rastro de auditoria del cambio
-- SELECT campo_modificado, valor_anterior, valor_nuevo, motivo, created_at
-- FROM hr_dat_auditoria_salario
-- ORDER BY created_at DESC
-- LIMIT 10;
