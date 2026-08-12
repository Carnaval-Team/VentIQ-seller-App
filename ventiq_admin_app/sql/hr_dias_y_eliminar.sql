-- =============================================================
-- HR: días independientes + historial + eliminar día de trabajo
-- Aplicar en: Supabase > SQL Editor
-- =============================================================


-- -------------------------------------------------------------
-- 1. ELIMINAR UN DÍA DE TRABAJO
--    Borra un registro de hr_dat_asistencia validando que
--    pertenezca a la tienda indicada (seguridad).
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_hr_delete_attendance(
    p_asistencia_id BIGINT,
    p_eliminado_por UUID,
    p_id_tienda     BIGINT
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_exists BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM hr_dat_asistencia
        WHERE id        = p_asistencia_id
          AND id_tienda = p_id_tienda
    ) INTO v_exists;

    IF NOT v_exists THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'message', 'Registro no encontrado o no pertenece a esta tienda'
        );
    END IF;

    DELETE FROM hr_dat_asistencia
    WHERE id        = p_asistencia_id
      AND id_tienda = p_id_tienda;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Día de trabajo eliminado correctamente'
    );
END;
$$;


-- -------------------------------------------------------------
-- 2. HISTORIAL DE ASISTENCIA POR PERÍODO
--    Devuelve todos los registros (abiertos y cerrados) de una
--    tienda en un rango de fechas, ordenados por hora_entrada
--    descendente.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_hr_attendance_history(
    p_id_tienda   INTEGER,
    p_fecha_desde DATE,
    p_fecha_hasta DATE
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_records JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.hora_entrada DESC), '[]'::jsonb)
    INTO v_records
    FROM (
        SELECT
            a.id                                        AS asistencia_id,
            a.id_trabajador                             AS trabajador_id,
            t.nombres,
            t.apellidos,
            a.hora_entrada,
            a.hora_salida,
            a.salario_hora,
            COALESCE(a.horas_trabajadas, 0)             AS horas_trabajadas,
            COALESCE(a.salario_total, 0)                AS salario_total,
            COALESCE(t.pago_por_resultado, 0)           AS pago_por_resultado,
            COALESCE(a.aplica_pago_resultado, FALSE)    AS aplica_pago_resultado,
            ro.denominacion                             AS rol_nombre,
            a.observaciones
        FROM hr_dat_asistencia a
        JOIN app_dat_trabajadores t ON t.id = a.id_trabajador
        LEFT JOIN seg_roll ro        ON ro.id = t.id_roll
        WHERE a.id_tienda   = p_id_tienda
          AND a.hora_entrada >= p_fecha_desde
          AND a.hora_entrada  < (p_fecha_hasta + INTERVAL '1 day')
    ) r;

    RETURN jsonb_build_object(
        'success', TRUE,
        'data',    v_records
    );
END;
$$;


-- -------------------------------------------------------------
-- 3. REPORTE DE SALARIOS — corregir dias_trabajados
--
--    Antes: COUNT(DISTINCT DATE(a.hora_entrada))
--           → contaba fechas calendario distintas.
--
--    Ahora: COUNT(a.id)
--           → cada check-in registrado = 1 día trabajado,
--             independientemente de la fecha o las horas.
--             Nunca se calculan días dividiendo horas / 24.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_hr_salary_report(
    p_id_tienda   INTEGER,
    p_fecha_desde DATE,
    p_fecha_hasta DATE
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_report JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(r), '[]'::jsonb)
    INTO v_report
    FROM (
        SELECT
            t.id                                                                  AS trabajador_id,
            t.nombres,
            t.apellidos,
            r.denominacion                                                        AS rol_nombre,
            t.salario_horas,
            ROUND(COALESCE(SUM(a.horas_trabajadas), 0), 2)                       AS total_horas,
            ROUND(COALESCE(SUM(a.salario_total), 0), 2)                          AS total_salario_base,
            ROUND(COALESCE(SUM(
                CASE WHEN a.aplica_pago_resultado
                     THEN a.pago_por_resultado
                     ELSE 0
                END
            ), 0), 2)                                                             AS total_ppr,
            ROUND(
                COALESCE(SUM(a.salario_total), 0)
                + COALESCE(SUM(
                    CASE WHEN a.aplica_pago_resultado
                         THEN a.pago_por_resultado
                         ELSE 0
                    END
                ), 0),
            2)                                                                    AS total_general,
            -- Cada entrada registrada = 1 día (no por fecha calendario, no por horas/24)
            COUNT(a.id)                                                           AS dias_trabajados
        FROM app_dat_trabajadores t
        LEFT JOIN seg_roll r ON r.id = t.id_roll
        LEFT JOIN hr_dat_asistencia a
            ON  a.id_trabajador  = t.id
            AND a.id_tienda      = p_id_tienda
            AND a.hora_entrada  >= p_fecha_desde
            AND a.hora_entrada   < (p_fecha_hasta + INTERVAL '1 day')
            AND a.hora_salida   IS NOT NULL   -- solo días cerrados (con salida)
        WHERE t.id_tienda   = p_id_tienda
          AND t.deleted_at IS NULL
        GROUP BY t.id, t.nombres, t.apellidos, r.denominacion, t.salario_horas
        HAVING COALESCE(SUM(a.horas_trabajadas), 0) > 0
        ORDER BY total_general DESC
    ) r;

    RETURN jsonb_build_object(
        'success', TRUE,
        'data',    v_report
    );
END;
$$;
