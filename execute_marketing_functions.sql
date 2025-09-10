-- =====================================================
-- SCRIPT PARA EJECUTAR EN SUPABASE SQL EDITOR
-- =====================================================
-- Copia y pega este contenido completo en el SQL Editor de Supabase
-- y ejecuta para crear todas las funciones de marketing

-- =====================================================
-- CREACIÓN DE TABLAS DE AUDITORÍA
-- =====================================================

-- Tabla de auditoría para promociones
CREATE TABLE IF NOT EXISTS app_mkt_promociones_audit (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_promocion BIGINT NOT NULL,
    accion VARCHAR(10) NOT NULL, -- INSERT, UPDATE, DELETE
    usuario_uuid UUID,
    fecha_accion TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    datos_anteriores JSONB,
    datos_nuevos JSONB,
    ip_address INET,
    user_agent TEXT
);

-- Tabla de logs de acceso a funciones
CREATE TABLE IF NOT EXISTS app_mkt_function_logs (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    function_name VARCHAR(100) NOT NULL,
    usuario_uuid UUID,
    id_tienda BIGINT,
    parametros JSONB,
    resultado VARCHAR(20), -- SUCCESS, ERROR
    mensaje_error TEXT,
    tiempo_ejecucion INTERVAL,
    fecha_acceso TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    ip_address INET
);

-- Crear tabla de tipos de promoción si no existe
CREATE TABLE IF NOT EXISTS app_mkt_tipo_promocion (
    id SMALLINT NOT NULL PRIMARY KEY,
    denominacion VARCHAR NOT NULL,
    descripcion TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Crear tabla de tipos de campaña si no existe  
CREATE TABLE IF NOT EXISTS app_mkt_tipo_campana (
    id SMALLINT NOT NULL PRIMARY KEY,
    denominacion VARCHAR NOT NULL,
    descripcion TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Insertar datos por defecto en tipos de promoción
INSERT INTO app_mkt_tipo_promocion (id, denominacion, descripcion) VALUES
(1, 'Descuento Porcentual', 'Descuento aplicado como porcentaje'),
(2, 'Descuento Fijo', 'Descuento de cantidad fija'),
(3, '2x1', 'Lleva dos productos por el precio de uno'),
(4, 'Envío Gratis', 'Sin costo de envío'),
(5, 'Puntos Extra', 'Bonificación de puntos en programa de fidelización')
ON CONFLICT (id) DO NOTHING;

-- Insertar datos por defecto en tipos de campaña
INSERT INTO app_mkt_tipo_campana (id, denominacion, descripcion) VALUES
(1, 'Promocional', 'Campaña de promociones y descuentos'),
(2, 'Lanzamiento', 'Campaña de lanzamiento de productos'),
(3, 'Fidelización', 'Campaña para retener clientes'),
(4, 'Estacional', 'Campaña por temporadas especiales')
ON CONFLICT (id) DO NOTHING;

-- =====================================================
-- FUNCIONES DE VALIDACIÓN Y UTILIDAD
-- =====================================================

-- Función para validar parámetros de entrada
CREATE OR REPLACE FUNCTION fn_validar_parametros_entrada(p_id_tienda BIGINT)
RETURNS BOOLEAN AS $$
BEGIN
    IF p_id_tienda IS NULL OR p_id_tienda <= 0 THEN
        RAISE EXCEPTION 'ID de tienda inválido: %', p_id_tienda;
    END IF;
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- Función para obtener límites seguros de consulta
CREATE OR REPLACE FUNCTION fn_obtener_limites_seguros(p_limite INTEGER DEFAULT 50)
RETURNS INTEGER AS $$
BEGIN
    IF p_limite IS NULL OR p_limite <= 0 THEN
        RETURN 50;
    END IF;
    IF p_limite > 1000 THEN
        RETURN 1000;
    END IF;
    RETURN p_limite;
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- =====================================================
-- FUNCIONES PRINCIPALES DE MARKETING
-- =====================================================

-- Función para obtener resumen del dashboard de marketing
CREATE OR REPLACE FUNCTION fn_marketing_dashboard_resumen(p_id_tienda BIGINT)
RETURNS JSON AS $$
DECLARE
    v_result JSON;
    v_usuario_uuid UUID := auth.uid();
    v_start_time TIMESTAMP := clock_timestamp();
BEGIN
    -- Validar usuario autenticado
    IF v_usuario_uuid IS NULL THEN
        RAISE EXCEPTION 'Usuario no autenticado';
    END IF;

    -- Validar parámetros
    PERFORM fn_validar_parametros_entrada(p_id_tienda);

    -- Validar acceso a la tienda
    IF NOT fn_validar_acceso_tienda(p_id_tienda, v_usuario_uuid) THEN
        RAISE EXCEPTION 'Acceso denegado a la tienda: %', p_id_tienda;
    END IF;

    -- Construir resumen
    SELECT json_build_object(
        'total_promociones', COALESCE((SELECT COUNT(*) FROM app_mkt_promociones WHERE id_tienda = p_id_tienda), 0),
        'promociones_activas', COALESCE((SELECT COUNT(*) FROM app_mkt_promociones WHERE id_tienda = p_id_tienda AND estado = true), 0),
        'total_campanas', COALESCE((SELECT COUNT(*) FROM app_mkt_campanas WHERE id_tienda = p_id_tienda), 0),
        'campanas_activas', COALESCE((SELECT COUNT(*) FROM app_mkt_campanas WHERE id_tienda = p_id_tienda AND estado = 1), 0),
        'total_segmentos', COALESCE((SELECT COUNT(*) FROM app_mkt_segmentos WHERE id_tienda = p_id_tienda), 0),
        'comunicaciones_enviadas', COALESCE((SELECT COUNT(*) FROM app_mkt_comunicaciones WHERE id_tienda = p_id_tienda AND estado = 2), 0),
        'eventos_fidelizacion', COALESCE((SELECT COUNT(*) FROM app_mkt_eventos_fidelizacion WHERE id_tienda = p_id_tienda), 0)
    ) INTO v_result;

    -- Log de auditoría exitoso
    INSERT INTO app_mkt_function_logs (function_name, usuario_uuid, id_tienda, parametros, resultado, tiempo_ejecucion)
    VALUES ('fn_marketing_dashboard_resumen', v_usuario_uuid, p_id_tienda, 
            json_build_object('p_id_tienda', p_id_tienda), 'SUCCESS', clock_timestamp() - v_start_time);

    RETURN v_result;

EXCEPTION
    WHEN OTHERS THEN
        -- Log de auditoría de error
        INSERT INTO app_mkt_function_logs (function_name, usuario_uuid, id_tienda, parametros, resultado, mensaje_error, tiempo_ejecucion)
        VALUES ('fn_marketing_dashboard_resumen', v_usuario_uuid, p_id_tienda, 
                json_build_object('p_id_tienda', p_id_tienda), 'ERROR', SQLERRM, clock_timestamp() - v_start_time);
        RAISE EXCEPTION 'Error obteniendo resumen de marketing: %', SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- Función para listar campañas
CREATE OR REPLACE FUNCTION fn_listar_campanas(
    p_id_tienda BIGINT,
    p_limite INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE(
    id BIGINT,
    nombre VARCHAR,
    descripcion TEXT,
    fecha_inicio DATE,
    fecha_fin DATE,
    presupuesto NUMERIC,
    presupuesto_usado NUMERIC,
    estado SMALLINT,
    tipo_campana VARCHAR,
    created_at TIMESTAMPTZ
) AS $$
DECLARE
    v_usuario_uuid UUID := auth.uid();
    v_limite_seguro INTEGER;
BEGIN
    -- Validar usuario autenticado
    IF v_usuario_uuid IS NULL THEN
        RAISE EXCEPTION 'Usuario no autenticado';
    END IF;

    -- Validar parámetros
    PERFORM fn_validar_parametros_entrada(p_id_tienda);
    v_limite_seguro := fn_obtener_limites_seguros(p_limite);

    -- Validar acceso a la tienda
    IF NOT fn_validar_acceso_tienda(p_id_tienda, v_usuario_uuid) THEN
        RAISE EXCEPTION 'Acceso denegado a la tienda: %', p_id_tienda;
    END IF;

    -- Retornar campañas
    RETURN QUERY
    SELECT 
        c.id,
        c.nombre,
        c.descripcion,
        c.fecha_inicio,
        c.fecha_fin,
        c.presupuesto,
        COALESCE(c.presupuesto_usado, 0.0) as presupuesto_usado,
        c.estado,
        tc.denominacion as tipo_campana,
        c.created_at
    FROM app_mkt_campanas c
    LEFT JOIN app_mkt_tipo_campana tc ON c.id_tipo_campana = tc.id
    WHERE c.id_tienda = p_id_tienda
    ORDER BY c.created_at DESC
    LIMIT v_limite_seguro OFFSET p_offset;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error listando campañas: %', SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- Función para insertar campaña
CREATE OR REPLACE FUNCTION fn_insertar_campana(
    p_id_tienda BIGINT,
    p_nombre VARCHAR,
    p_descripcion TEXT,
    p_id_tipo_campana SMALLINT,
    p_fecha_inicio DATE,
    p_fecha_fin DATE DEFAULT NULL,
    p_presupuesto NUMERIC DEFAULT NULL
) RETURNS BIGINT AS $$
DECLARE
    v_id_campana BIGINT;
    v_usuario_uuid UUID := auth.uid();
    v_start_time TIMESTAMP := clock_timestamp();
BEGIN
    -- Validar usuario autenticado
    IF v_usuario_uuid IS NULL THEN
        RAISE EXCEPTION 'Usuario no autenticado';
    END IF;

    -- Validar parámetros
    PERFORM fn_validar_parametros_entrada(p_id_tienda);
    
    IF p_nombre IS NULL OR LENGTH(TRIM(p_nombre)) = 0 THEN
        RAISE EXCEPTION 'Nombre de campaña es requerido';
    END IF;

    -- Validar acceso a la tienda
    IF NOT fn_validar_acceso_tienda(p_id_tienda, v_usuario_uuid) THEN
        RAISE EXCEPTION 'Acceso denegado a la tienda: %', p_id_tienda;
    END IF;

    -- Insertar campaña
    INSERT INTO app_mkt_campanas (
        id_tienda, nombre, descripcion, id_tipo_campana, 
        fecha_inicio, fecha_fin, presupuesto, estado, created_at
    ) VALUES (
        p_id_tienda, p_nombre, p_descripcion, p_id_tipo_campana,
        p_fecha_inicio, p_fecha_fin, p_presupuesto, 1, NOW()
    ) RETURNING id INTO v_id_campana;

    -- Log de auditoría exitoso
    INSERT INTO app_mkt_function_logs (function_name, usuario_uuid, id_tienda, parametros, resultado, tiempo_ejecucion)
    VALUES ('fn_insertar_campana', v_usuario_uuid, p_id_tienda, 
            json_build_object('nombre', p_nombre, 'id_tipo_campana', p_id_tipo_campana), 
            'SUCCESS', clock_timestamp() - v_start_time);

    RETURN v_id_campana;

EXCEPTION
    WHEN OTHERS THEN
        -- Log de auditoría de error
        INSERT INTO app_mkt_function_logs (function_name, usuario_uuid, id_tienda, parametros, resultado, mensaje_error, tiempo_ejecucion)
        VALUES ('fn_insertar_campana', v_usuario_uuid, p_id_tienda, 
                json_build_object('nombre', p_nombre), 'ERROR', SQLERRM, clock_timestamp() - v_start_time);
        RAISE;
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- Función para actualizar campaña
CREATE OR REPLACE FUNCTION fn_actualizar_campana(
    p_id BIGINT,
    p_nombre VARCHAR,
    p_descripcion TEXT,
    p_id_tipo_campana SMALLINT,
    p_fecha_inicio DATE,
    p_fecha_fin DATE DEFAULT NULL,
    p_presupuesto NUMERIC DEFAULT NULL,
    p_estado SMALLINT DEFAULT NULL
) RETURNS BOOLEAN AS $$
DECLARE
    v_usuario_uuid UUID := auth.uid();
    v_id_tienda BIGINT;
    v_found BOOLEAN := FALSE;
BEGIN
    -- Validar usuario autenticado
    IF v_usuario_uuid IS NULL THEN
        RAISE EXCEPTION 'Usuario no autenticado';
    END IF;

    -- Obtener ID de tienda de la campaña
    SELECT id_tienda INTO v_id_tienda 
    FROM app_mkt_campanas 
    WHERE id = p_id;

    IF v_id_tienda IS NULL THEN
        RAISE EXCEPTION 'Campaña no encontrada';
    END IF;

    -- Validar acceso a la tienda
    IF NOT fn_validar_acceso_tienda(v_id_tienda, v_usuario_uuid) THEN
        RAISE EXCEPTION 'Acceso denegado a la tienda: %', v_id_tienda;
    END IF;

    -- Actualizar campaña
    UPDATE app_mkt_campanas SET
        nombre = COALESCE(p_nombre, nombre),
        descripcion = COALESCE(p_descripcion, descripcion),
        id_tipo_campana = COALESCE(p_id_tipo_campana, id_tipo_campana),
        fecha_inicio = COALESCE(p_fecha_inicio, fecha_inicio),
        fecha_fin = COALESCE(p_fecha_fin, fecha_fin),
        presupuesto = COALESCE(p_presupuesto, presupuesto),
        estado = COALESCE(p_estado, estado),
        updated_at = NOW()
    WHERE id = p_id;

    GET DIAGNOSTICS v_found = FOUND;
    RETURN v_found;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error actualizando campaña: %', SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- Función para eliminar campaña
CREATE OR REPLACE FUNCTION fn_eliminar_campana(p_id BIGINT)
RETURNS BOOLEAN AS $$
DECLARE
    v_usuario_uuid UUID := auth.uid();
    v_id_tienda BIGINT;
    v_found BOOLEAN := FALSE;
BEGIN
    -- Validar usuario autenticado
    IF v_usuario_uuid IS NULL THEN
        RAISE EXCEPTION 'Usuario no autenticado';
    END IF;

    -- Obtener ID de tienda de la campaña
    SELECT id_tienda INTO v_id_tienda 
    FROM app_mkt_campanas 
    WHERE id = p_id;

    IF v_id_tienda IS NULL THEN
        RAISE EXCEPTION 'Campaña no encontrada';
    END IF;

    -- Validar acceso a la tienda
    IF NOT fn_validar_acceso_tienda(v_id_tienda, v_usuario_uuid) THEN
        RAISE EXCEPTION 'Acceso denegado a la tienda: %', v_id_tienda;
    END IF;

    -- Eliminar campaña (soft delete)
    UPDATE app_mkt_campanas SET
        estado = 0,
        updated_at = NOW()
    WHERE id = p_id;

    GET DIAGNOSTICS v_found = FOUND;
    RETURN v_found;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error eliminando campaña: %', SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- Función para listar comunicaciones
CREATE OR REPLACE FUNCTION fn_listar_comunicaciones(p_id_tienda BIGINT)
RETURNS TABLE(
    id BIGINT,
    asunto VARCHAR,
    contenido TEXT,
    tipo_campana VARCHAR,
    fecha_programada TIMESTAMPTZ,
    fecha_envio TIMESTAMPTZ,
    estado SMALLINT,
    estado_nombre VARCHAR,
    destinatarios_total INTEGER,
    destinatarios_enviados INTEGER,
    created_at TIMESTAMPTZ
) AS $$
DECLARE
    v_usuario_uuid UUID := auth.uid();
BEGIN
    -- Validar usuario autenticado
    IF v_usuario_uuid IS NULL THEN
        RAISE EXCEPTION 'Usuario no autenticado';
    END IF;

    -- Validar parámetros
    PERFORM fn_validar_parametros_entrada(p_id_tienda);

    -- Validar acceso a la tienda
    IF NOT fn_validar_acceso_tienda(p_id_tienda, v_usuario_uuid) THEN
        RAISE EXCEPTION 'Acceso denegado a la tienda: %', p_id_tienda;
    END IF;

    -- Retornar comunicaciones
    RETURN QUERY
    SELECT 
        c.id,
        c.asunto,
        c.contenido,
        tc.denominacion as tipo_campana,
        c.fecha_programada,
        c.fecha_envio,
        c.estado,
        CASE c.estado
            WHEN 1 THEN 'Borrador'
            WHEN 2 THEN 'Enviado'
            WHEN 3 THEN 'Programado'
            WHEN 4 THEN 'Cancelado'
            ELSE 'Desconocido'
        END as estado_nombre,
        COALESCE((c.metricas->>'destinatarios_total')::INTEGER, 0) as destinatarios_total,
        COALESCE((c.metricas->>'destinatarios_enviados')::INTEGER, 0) as destinatarios_enviados,
        c.created_at
    FROM app_mkt_comunicaciones c
    LEFT JOIN app_mkt_tipo_campana tc ON c.id_tipo_campana = tc.id
    WHERE c.id_tienda = p_id_tienda
    ORDER BY c.created_at DESC;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error listando comunicaciones: %', SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- Función para listar segmentos
CREATE OR REPLACE FUNCTION fn_listar_segmentos(p_id_tienda BIGINT)
RETURNS TABLE(
    id BIGINT,
    nombre VARCHAR,
    descripcion TEXT,
    criterios JSONB,
    total_clientes INTEGER,
    created_at TIMESTAMPTZ
) AS $$
DECLARE
    v_usuario_uuid UUID := auth.uid();
BEGIN
    -- Validar usuario autenticado
    IF v_usuario_uuid IS NULL THEN
        RAISE EXCEPTION 'Usuario no autenticado';
    END IF;

    -- Validar parámetros
    PERFORM fn_validar_parametros_entrada(p_id_tienda);

    -- Validar acceso a la tienda
    IF NOT fn_validar_acceso_tienda(p_id_tienda, v_usuario_uuid) THEN
        RAISE EXCEPTION 'Acceso denegado a la tienda: %', p_id_tienda;
    END IF;

    -- Retornar segmentos
    RETURN QUERY
    SELECT 
        s.id,
        s.nombre,
        s.descripcion,
        s.criterios,
        COALESCE(s.total_clientes, 0) as total_clientes,
        s.created_at
    FROM app_mkt_segmentos s
    WHERE s.id_tienda = p_id_tienda
    ORDER BY s.created_at DESC;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error listando segmentos: %', SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- Función para obtener resumen de fidelización
CREATE OR REPLACE FUNCTION fn_fidelizacion_resumen(p_id_tienda BIGINT)
RETURNS JSON AS $$
DECLARE
    v_result JSON;
    v_usuario_uuid UUID := auth.uid();
BEGIN
    -- Validar usuario autenticado
    IF v_usuario_uuid IS NULL THEN
        RAISE EXCEPTION 'Usuario no autenticado';
    END IF;

    -- Validar parámetros
    PERFORM fn_validar_parametros_entrada(p_id_tienda);

    -- Validar acceso a la tienda
    IF NOT fn_validar_acceso_tienda(p_id_tienda, v_usuario_uuid) THEN
        RAISE EXCEPTION 'Acceso denegado a la tienda: %', p_id_tienda;
    END IF;

    -- Construir resumen de fidelización
    SELECT json_build_object(
        'clientes_registrados', COALESCE((SELECT COUNT(DISTINCT id_cliente) FROM app_mkt_eventos_fidelizacion WHERE id_tienda = p_id_tienda), 0),
        'clientes_con_puntos', COALESCE((SELECT COUNT(DISTINCT id_cliente) FROM app_mkt_eventos_fidelizacion WHERE id_tienda = p_id_tienda AND puntos_otorgados > 0), 0),
        'total_puntos_emitidos', COALESCE((SELECT SUM(puntos_otorgados) FROM app_mkt_eventos_fidelizacion WHERE id_tienda = p_id_tienda), 0),
        'eventos_mes_actual', COALESCE((SELECT COUNT(*) FROM app_mkt_eventos_fidelizacion WHERE id_tienda = p_id_tienda AND DATE_TRUNC('month', created_at) = DATE_TRUNC('month', NOW())), 0)
    ) INTO v_result;

    RETURN v_result;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error obteniendo resumen de fidelización: %', SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- Función para listar tipos de campaña
CREATE OR REPLACE FUNCTION fn_listar_tipos_campana()
RETURNS TABLE(
    id SMALLINT,
    denominacion VARCHAR,
    descripcion TEXT,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        tc.id,
        tc.denominacion,
        tc.descripcion,
        tc.created_at
    FROM app_mkt_tipo_campana tc
    ORDER BY tc.denominacion;
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- =====================================================
-- CONCEDER PERMISOS
-- =====================================================

-- Conceder permisos de ejecución en las funciones a usuarios autenticados
GRANT EXECUTE ON FUNCTION fn_validar_parametros_entrada(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_obtener_limites_seguros(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_marketing_dashboard_resumen(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_listar_campanas(BIGINT, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_insertar_campana(BIGINT, VARCHAR, TEXT, SMALLINT, DATE, DATE, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_actualizar_campana(BIGINT, VARCHAR, TEXT, SMALLINT, DATE, DATE, NUMERIC, SMALLINT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_eliminar_campana(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_listar_comunicaciones(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_listar_segmentos(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_fidelizacion_resumen(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_listar_tipos_campana() TO authenticated;

-- Conceder permisos en las tablas de auditoría
GRANT INSERT ON app_mkt_promociones_audit TO authenticated;
GRANT INSERT ON app_mkt_function_logs TO authenticated;
GRANT SELECT ON app_mkt_tipo_promocion TO authenticated;
GRANT SELECT ON app_mkt_tipo_campana TO authenticated;

-- =====================================================
-- SCRIPT COMPLETADO
-- =====================================================
-- Todas las funciones de marketing han sido creadas exitosamente
-- La aplicación Flutter ahora puede conectarse a datos reales
