-- =====================================================
-- MODULO DE RECURSOS HUMANOS - SCHEMA SQL
-- Inventtia Admin - HR Module
-- =====================================================

-- =====================================================
-- 1.1 ALTERAR TABLA EXISTENTE
-- =====================================================
ALTER TABLE app_dat_trabajadores
ADD COLUMN IF NOT EXISTS pago_por_resultado NUMERIC DEFAULT 0;

-- =====================================================
-- 1.2 NUEVA TABLA: hr_dat_asistencia
-- =====================================================
CREATE TABLE IF NOT EXISTS hr_dat_asistencia (
    id BIGSERIAL PRIMARY KEY,
    id_tienda BIGINT NOT NULL REFERENCES app_dat_tienda(id),
    id_trabajador BIGINT NOT NULL REFERENCES app_dat_trabajadores(id),
    hora_entrada TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    hora_salida TIMESTAMPTZ,
    horas_trabajadas NUMERIC GENERATED ALWAYS AS (
        CASE
            WHEN hora_salida IS NOT NULL THEN
                LEAST(
                    EXTRACT(EPOCH FROM (hora_salida - hora_entrada)) / 3600.0,
                    8.0
                )
            ELSE NULL
        END
    ) STORED,
    salario_hora NUMERIC NOT NULL DEFAULT 0,
    salario_total NUMERIC GENERATED ALWAYS AS (
        CASE
            WHEN hora_salida IS NOT NULL THEN
                LEAST(
                    EXTRACT(EPOCH FROM (hora_salida - hora_entrada)) / 3600.0,
                    8.0
                ) * salario_hora
            ELSE NULL
        END
    ) STORED,
    pago_por_resultado NUMERIC DEFAULT 0,
    aplica_pago_resultado BOOLEAN DEFAULT FALSE,
    registrado_por UUID REFERENCES auth.users(id),
    cerrado_por UUID REFERENCES auth.users(id),
    observaciones TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indices
CREATE INDEX IF NOT EXISTS idx_hr_asistencia_tienda ON hr_dat_asistencia(id_tienda);
CREATE INDEX IF NOT EXISTS idx_hr_asistencia_trabajador ON hr_dat_asistencia(id_trabajador);
CREATE INDEX IF NOT EXISTS idx_hr_asistencia_entrada ON hr_dat_asistencia(hora_entrada);
CREATE INDEX IF NOT EXISTS idx_hr_asistencia_abiertos ON hr_dat_asistencia(id_tienda, id_trabajador) WHERE hora_salida IS NULL;

-- =====================================================
-- 1.3 NUEVA TABLA: hr_dat_auditoria_salario
-- =====================================================
CREATE TABLE IF NOT EXISTS hr_dat_auditoria_salario (
    id BIGSERIAL PRIMARY KEY,
    id_trabajador BIGINT NOT NULL REFERENCES app_dat_trabajadores(id),
    id_tienda BIGINT NOT NULL REFERENCES app_dat_tienda(id),
    campo_modificado TEXT NOT NULL,
    valor_anterior TEXT,
    valor_nuevo TEXT,
    modificado_por UUID NOT NULL REFERENCES auth.users(id),
    motivo TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_hr_auditoria_trabajador ON hr_dat_auditoria_salario(id_trabajador);
CREATE INDEX IF NOT EXISTS idx_hr_auditoria_tienda ON hr_dat_auditoria_salario(id_tienda);

-- =====================================================
-- 1.4 FUNCIONES RPC
-- =====================================================

-- 1) fn_check_is_hr_user: Verifica si el usuario tiene rol de Recursos Humanos
-- Un usuario es HR si existe en la tabla app_dat_recursos_humanos
CREATE OR REPLACE FUNCTION fn_check_is_hr_user(
    p_user_uuid UUID,
    p_id_tienda INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_is_hr BOOLEAN := FALSE;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM app_dat_recursos_humanos rh
        WHERE rh.id_tienda = p_id_tienda
          AND rh.uuid = p_user_uuid
    ) INTO v_is_hr;

    RETURN jsonb_build_object(
        'success', TRUE,
        'is_hr', v_is_hr
    );
END;
$$;

-- 2) fn_hr_workers_for_checkin: Trabajadores disponibles para fichar entrada
CREATE OR REPLACE FUNCTION fn_hr_workers_for_checkin(
    p_id_tienda INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_workers JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(w), '[]'::jsonb)
    INTO v_workers
    FROM (
        SELECT
            t.id AS trabajador_id,
            t.nombres,
            t.apellidos,
            t.salario_horas,
            COALESCE(t.pago_por_resultado, 0) AS pago_por_resultado,
            r.denominacion AS rol_nombre
        FROM app_dat_trabajadores t
        LEFT JOIN seg_roll r ON r.id = t.id_roll
        WHERE t.id_tienda = p_id_tienda
          AND t.deleted_at IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM hr_dat_asistencia a
              WHERE a.id_trabajador = t.id
                AND a.id_tienda = p_id_tienda
                AND a.hora_salida IS NULL
          )
        ORDER BY t.nombres, t.apellidos
    ) w;

    RETURN jsonb_build_object(
        'success', TRUE,
        'data', v_workers
    );
END;
$$;

-- 3) fn_hr_workers_currently_working: Trabajadores trabajando actualmente
CREATE OR REPLACE FUNCTION fn_hr_workers_currently_working(
    p_id_tienda INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_workers JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(w), '[]'::jsonb)
    INTO v_workers
    FROM (
        SELECT
            a.id AS asistencia_id,
            a.id_trabajador AS trabajador_id,
            t.nombres,
            t.apellidos,
            a.hora_entrada,
            a.salario_hora,
            COALESCE(t.pago_por_resultado, 0) AS pago_por_resultado,
            r.denominacion AS rol_nombre,
            EXTRACT(EPOCH FROM (NOW() - a.hora_entrada)) / 3600.0 AS horas_transcurridas
        FROM hr_dat_asistencia a
        JOIN app_dat_trabajadores t ON t.id = a.id_trabajador
        LEFT JOIN seg_roll r ON r.id = t.id_roll
        WHERE a.id_tienda = p_id_tienda
          AND a.hora_salida IS NULL
        ORDER BY a.hora_entrada ASC
    ) w;

    RETURN jsonb_build_object(
        'success', TRUE,
        'data', v_workers
    );
END;
$$;

-- 4) fn_hr_register_checkin: Registrar entrada de trabajador
CREATE OR REPLACE FUNCTION fn_hr_register_checkin(
    p_id_tienda INTEGER,
    p_id_trabajador INTEGER,
    p_hora_entrada TIMESTAMPTZ,
    p_registrado_por UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_salario_hora NUMERIC;
    v_already_working BOOLEAN;
    v_new_id BIGINT;
BEGIN
    -- Verificar si ya esta trabajando
    SELECT EXISTS (
        SELECT 1 FROM hr_dat_asistencia
        WHERE id_trabajador = p_id_trabajador
          AND id_tienda = p_id_tienda
          AND hora_salida IS NULL
    ) INTO v_already_working;

    IF v_already_working THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'message', 'El trabajador ya tiene una entrada abierta'
        );
    END IF;

    -- Obtener salario por hora del trabajador
    SELECT COALESCE(salario_horas, 0)
    INTO v_salario_hora
    FROM app_dat_trabajadores
    WHERE id = p_id_trabajador AND id_tienda = p_id_tienda;

    -- Insertar registro
    INSERT INTO hr_dat_asistencia (
        id_tienda, id_trabajador, hora_entrada,
        salario_hora, registrado_por
    ) VALUES (
        p_id_tienda, p_id_trabajador, p_hora_entrada,
        v_salario_hora, p_registrado_por
    ) RETURNING id INTO v_new_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Entrada registrada exitosamente',
        'id', v_new_id
    );
END;
$$;

-- 5) fn_hr_batch_checkout: Firmar salida en lote
CREATE OR REPLACE FUNCTION fn_hr_batch_checkout(
    p_asistencia_ids BIGINT[],
    p_hora_salida TIMESTAMPTZ,
    p_aplica_pago BOOLEAN[],
    p_cerrado_por UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_count INTEGER := 0;
    v_id BIGINT;
    v_aplica BOOLEAN;
    v_ppr NUMERIC;
    i INTEGER;
BEGIN
    FOR i IN 1..array_length(p_asistencia_ids, 1) LOOP
        v_id := p_asistencia_ids[i];
        v_aplica := COALESCE(p_aplica_pago[i], FALSE);

        -- Obtener PPR del trabajador
        SELECT COALESCE(t.pago_por_resultado, 0)
        INTO v_ppr
        FROM hr_dat_asistencia a
        JOIN app_dat_trabajadores t ON t.id = a.id_trabajador
        WHERE a.id = v_id;

        UPDATE hr_dat_asistencia
        SET hora_salida = p_hora_salida,
            cerrado_por = p_cerrado_por,
            aplica_pago_resultado = v_aplica,
            pago_por_resultado = CASE WHEN v_aplica THEN v_ppr ELSE 0 END,
            updated_at = NOW()
        WHERE id = v_id AND hora_salida IS NULL;

        IF FOUND THEN
            v_count := v_count + 1;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', format('%s salida(s) registrada(s)', v_count),
        'count', v_count
    );
END;
$$;

-- 6) fn_hr_dashboard_summary: Resumen del dashboard HR
CREATE OR REPLACE FUNCTION fn_hr_dashboard_summary(
    p_id_tienda INTEGER,
    p_fecha_desde DATE,
    p_fecha_hasta DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_total_horas NUMERIC;
    v_total_salario_base NUMERIC;
    v_total_ppr NUMERIC;
    v_total_general NUMERIC;
    v_registros INTEGER;
    v_daily_data JSONB;
BEGIN
    -- Totales del periodo
    SELECT
        COALESCE(SUM(horas_trabajadas), 0),
        COALESCE(SUM(salario_total), 0),
        COALESCE(SUM(CASE WHEN aplica_pago_resultado THEN pago_por_resultado ELSE 0 END), 0),
        COUNT(*)
    INTO v_total_horas, v_total_salario_base, v_total_ppr, v_registros
    FROM hr_dat_asistencia
    WHERE id_tienda = p_id_tienda
      AND hora_entrada >= p_fecha_desde
      AND hora_entrada < (p_fecha_hasta + INTERVAL '1 day')
      AND hora_salida IS NOT NULL;

    v_total_general := v_total_salario_base + v_total_ppr;

    -- Datos diarios para grafico
    SELECT COALESCE(jsonb_agg(d ORDER BY d->>'fecha'), '[]'::jsonb)
    INTO v_daily_data
    FROM (
        SELECT jsonb_build_object(
            'fecha', DATE(hora_entrada)::TEXT,
            'horas', COALESCE(SUM(horas_trabajadas), 0),
            'salario', COALESCE(SUM(salario_total), 0),
            'ppr', COALESCE(SUM(CASE WHEN aplica_pago_resultado THEN pago_por_resultado ELSE 0 END), 0)
        ) AS d
        FROM hr_dat_asistencia
        WHERE id_tienda = p_id_tienda
          AND hora_entrada >= p_fecha_desde
          AND hora_entrada < (p_fecha_hasta + INTERVAL '1 day')
          AND hora_salida IS NOT NULL
        GROUP BY DATE(hora_entrada)
    ) sub;

    RETURN jsonb_build_object(
        'success', TRUE,
        'data', jsonb_build_object(
            'total_horas', ROUND(v_total_horas, 2),
            'total_salario_base', ROUND(v_total_salario_base, 2),
            'total_ppr', ROUND(v_total_ppr, 2),
            'total_general', ROUND(v_total_general, 2),
            'total_registros', v_registros,
            'daily_data', v_daily_data
        )
    );
END;
$$;

-- 7) fn_hr_top_workers_by_pay: Top trabajadores por pago total
CREATE OR REPLACE FUNCTION fn_hr_top_workers_by_pay(
    p_id_tienda INTEGER,
    p_fecha_desde DATE,
    p_fecha_hasta DATE,
    p_limit INTEGER DEFAULT 10
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_workers JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(w), '[]'::jsonb)
    INTO v_workers
    FROM (
        SELECT
            t.id AS trabajador_id,
            t.nombres,
            t.apellidos,
            r.denominacion AS rol_nombre,
            ROUND(COALESCE(SUM(a.horas_trabajadas), 0), 2) AS total_horas,
            ROUND(COALESCE(SUM(a.salario_total), 0), 2) AS total_salario_base,
            ROUND(COALESCE(SUM(CASE WHEN a.aplica_pago_resultado THEN a.pago_por_resultado ELSE 0 END), 0), 2) AS total_ppr,
            ROUND(COALESCE(SUM(a.salario_total), 0) + COALESCE(SUM(CASE WHEN a.aplica_pago_resultado THEN a.pago_por_resultado ELSE 0 END), 0), 2) AS total_general,
            BOOL_OR(a.aplica_pago_resultado) AS tiene_ppr
        FROM hr_dat_asistencia a
        JOIN app_dat_trabajadores t ON t.id = a.id_trabajador
        LEFT JOIN seg_roll r ON r.id = t.id_roll
        WHERE a.id_tienda = p_id_tienda
          AND a.hora_entrada >= p_fecha_desde
          AND a.hora_entrada < (p_fecha_hasta + INTERVAL '1 day')
          AND a.hora_salida IS NOT NULL
        GROUP BY t.id, t.nombres, t.apellidos, r.denominacion
        ORDER BY total_general DESC
        LIMIT p_limit
    ) w;

    RETURN jsonb_build_object(
        'success', TRUE,
        'data', v_workers
    );
END;
$$;

-- 8) fn_hr_salary_report: Reporte completo de salarios
CREATE OR REPLACE FUNCTION fn_hr_salary_report(
    p_id_tienda INTEGER,
    p_fecha_desde DATE,
    p_fecha_hasta DATE
)
RETURNS JSONB
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
            t.id AS trabajador_id,
            t.nombres,
            t.apellidos,
            r.denominacion AS rol_nombre,
            t.salario_horas,
            ROUND(COALESCE(SUM(a.horas_trabajadas), 0), 2) AS total_horas,
            ROUND(COALESCE(SUM(a.salario_total), 0), 2) AS total_salario_base,
            ROUND(COALESCE(SUM(CASE WHEN a.aplica_pago_resultado THEN a.pago_por_resultado ELSE 0 END), 0), 2) AS total_ppr,
            ROUND(COALESCE(SUM(a.salario_total), 0) + COALESCE(SUM(CASE WHEN a.aplica_pago_resultado THEN a.pago_por_resultado ELSE 0 END), 0), 2) AS total_general,
            COUNT(DISTINCT DATE(a.hora_entrada)) AS dias_trabajados
        FROM app_dat_trabajadores t
        LEFT JOIN seg_roll r ON r.id = t.id_roll
        LEFT JOIN hr_dat_asistencia a
            ON a.id_trabajador = t.id
            AND a.id_tienda = p_id_tienda
            AND a.hora_entrada >= p_fecha_desde
            AND a.hora_entrada < (p_fecha_hasta + INTERVAL '1 day')
            AND a.hora_salida IS NOT NULL
        WHERE t.id_tienda = p_id_tienda
          AND t.deleted_at IS NULL
        GROUP BY t.id, t.nombres, t.apellidos, r.denominacion, t.salario_horas
        HAVING COALESCE(SUM(a.horas_trabajadas), 0) > 0
        ORDER BY total_general DESC
    ) r;

    RETURN jsonb_build_object(
        'success', TRUE,
        'data', v_report
    );
END;
$$;

-- 9) fn_hr_update_worker_salary: Actualizar salario con auditoria
CREATE OR REPLACE FUNCTION fn_hr_update_worker_salary(
    p_id_trabajador INTEGER,
    p_id_tienda INTEGER,
    p_salario_horas NUMERIC,
    p_pago_por_resultado NUMERIC,
    p_modificado_por UUID,
    p_motivo TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_old_salario NUMERIC;
    v_old_ppr NUMERIC;
BEGIN
    -- Obtener valores actuales
    SELECT salario_horas, COALESCE(pago_por_resultado, 0)
    INTO v_old_salario, v_old_ppr
    FROM app_dat_trabajadores
    WHERE id = p_id_trabajador AND id_tienda = p_id_tienda;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'message', 'Trabajador no encontrado'
        );
    END IF;

    -- Registrar auditoria si cambio salario
    IF v_old_salario IS DISTINCT FROM p_salario_horas THEN
        INSERT INTO hr_dat_auditoria_salario (
            id_trabajador, id_tienda, campo_modificado,
            valor_anterior, valor_nuevo, modificado_por, motivo
        ) VALUES (
            p_id_trabajador, p_id_tienda, 'salario_horas',
            v_old_salario::TEXT, p_salario_horas::TEXT, p_modificado_por, p_motivo
        );
    END IF;

    -- Registrar auditoria si cambio PPR
    IF v_old_ppr IS DISTINCT FROM p_pago_por_resultado THEN
        INSERT INTO hr_dat_auditoria_salario (
            id_trabajador, id_tienda, campo_modificado,
            valor_anterior, valor_nuevo, modificado_por, motivo
        ) VALUES (
            p_id_trabajador, p_id_tienda, 'pago_por_resultado',
            v_old_ppr::TEXT, p_pago_por_resultado::TEXT, p_modificado_por, p_motivo
        );
    END IF;

    -- Actualizar trabajador
    UPDATE app_dat_trabajadores
    SET salario_horas = p_salario_horas,
        pago_por_resultado = p_pago_por_resultado
    WHERE id = p_id_trabajador AND id_tienda = p_id_tienda;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Salario actualizado exitosamente'
    );
END;
$$;
