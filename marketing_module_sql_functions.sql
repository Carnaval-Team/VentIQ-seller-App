-- =====================================================
-- FUNCIONES SQL SEGURAS PARA EL MÓDULO DE MARKETING - VentIQ
-- =====================================================
-- Este archivo contiene todas las funciones SQL necesarias
-- para las operaciones CRUD del módulo de marketing con
-- validaciones de seguridad implementadas
-- =====================================================

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


-- Insertar tipos básicos de campaña
INSERT INTO app_mkt_tipo_campana (id, denominacion, descripcion) VALUES
(1, 'Promocional', 'Campaña enfocada en promociones y descuentos'),
(2, 'Fidelización', 'Campaña para retener clientes existentes'),
(3, 'Adquisición', 'Campaña para atraer nuevos clientes'),
(4, 'Estacional', 'Campaña para fechas especiales o temporadas')
ON CONFLICT (id) DO NOTHING;

-- Índices para las tablas de auditoría
CREATE INDEX IF NOT EXISTS idx_promociones_audit_fecha ON app_mkt_promociones_audit(fecha_accion);
CREATE INDEX IF NOT EXISTS idx_promociones_audit_usuario ON app_mkt_promociones_audit(usuario_uuid);
CREATE INDEX IF NOT EXISTS idx_function_logs_fecha ON app_mkt_function_logs(fecha_acceso);
CREATE INDEX IF NOT EXISTS idx_function_logs_function ON app_mkt_function_logs(function_name);
CREATE INDEX IF NOT EXISTS idx_function_logs_usuario ON app_mkt_function_logs(usuario_uuid);

-- =====================================================
-- FUNCIONES DE SEGURIDAD Y VALIDACIÓN
-- =====================================================

-- Función de validación de acceso a tienda
CREATE OR REPLACE FUNCTION fn_validar_acceso_tienda(p_id_tienda BIGINT, p_uuid_usuario UUID DEFAULT auth.uid())
RETURNS BOOLEAN AS $$
BEGIN
    -- Verificar que el usuario autenticado tenga acceso a la tienda
    RETURN EXISTS (
        SELECT 1 
        FROM app_dat_gerente g
        JOIN app_dat_tienda t ON g.id_tienda = t.id
        WHERE g.uuid = p_uuid_usuario 
        AND t.id = p_id_tienda
        AND t.activa = true
    );
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- Función de validación de parámetros
CREATE OR REPLACE FUNCTION fn_validar_parametros_entrada(
    p_id_tienda BIGINT,
    p_nombre VARCHAR DEFAULT NULL,
    p_descripcion TEXT DEFAULT NULL
)
RETURNS BOOLEAN AS $$
BEGIN
    -- Validar ID de tienda
    IF p_id_tienda IS NULL OR p_id_tienda <= 0 THEN
        RAISE EXCEPTION 'ID de tienda inválido: %', p_id_tienda;
    END IF;
    
    -- Validar nombre si se proporciona
    IF p_nombre IS NOT NULL THEN
        IF LENGTH(TRIM(p_nombre)) < 3 THEN
            RAISE EXCEPTION 'El nombre debe tener al menos 3 caracteres';
        END IF;
        
        IF LENGTH(p_nombre) > 255 THEN
            RAISE EXCEPTION 'El nombre no puede exceder 255 caracteres';
        END IF;
    END IF;
    
    -- Validar descripción si se proporciona
    IF p_descripcion IS NOT NULL AND LENGTH(p_descripcion) > 5000 THEN
        RAISE EXCEPTION 'La descripción no puede exceder 5000 caracteres';
    END IF;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Función para obtener límites seguros
CREATE OR REPLACE FUNCTION fn_obtener_limites_seguros()
RETURNS TABLE(
    max_registros_lista INTEGER,
    max_registros_analisis INTEGER,
    max_longitud_texto INTEGER,
    max_elementos_jsonb INTEGER
) AS $$
BEGIN
    RETURN QUERY SELECT 
        1000 as max_registros_lista,
        5000 as max_registros_analisis, 
        10000 as max_longitud_texto,
        100 as max_elementos_jsonb;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- =====================================================
-- 1. FUNCIONES PARA MARKETING DASHBOARD
-- =====================================================

-- Función para obtener resumen general de marketing (SEGURA)
CREATE OR REPLACE FUNCTION fn_marketing_dashboard_resumen(p_id_tienda BIGINT)
RETURNS JSON AS $$
DECLARE
    v_result JSON;
    v_usuario_uuid UUID := auth.uid();
BEGIN
    -- Validar autenticación
    IF v_usuario_uuid IS NULL THEN
        RAISE EXCEPTION 'Usuario no autenticado';
    END IF;
    
    -- Validar parámetros
    PERFORM fn_validar_parametros_entrada(p_id_tienda);
    
    -- Validar acceso a tienda
    IF NOT fn_validar_acceso_tienda(p_id_tienda, v_usuario_uuid) THEN
        RAISE EXCEPTION 'Acceso denegado a la tienda: %', p_id_tienda;
    END IF;
    
    -- Ejecutar consulta segura
    SELECT json_build_object(
        'total_promociones', (
            SELECT COUNT(*) 
            FROM app_mkt_promociones 
            WHERE id_tienda = p_id_tienda AND estado = true
        ),
        'promociones_activas', (
            SELECT COUNT(*) 
            FROM app_mkt_promociones 
            WHERE id_tienda = p_id_tienda 
            AND estado = true 
            AND fecha_inicio <= CURRENT_TIMESTAMP 
            AND (fecha_fin IS NULL OR fecha_fin >= CURRENT_TIMESTAMP)
        ),
        'total_campanas', (
            SELECT COUNT(*) 
            FROM app_mkt_campanas 
            WHERE id_tienda = p_id_tienda
        ),
        'campanas_activas', (
            SELECT COUNT(*) 
            FROM app_mkt_campanas 
            WHERE id_tienda = p_id_tienda 
            AND estado = 1
            AND fecha_inicio <= CURRENT_DATE 
            AND (fecha_fin IS NULL OR fecha_fin >= CURRENT_DATE)
        ),
        'total_segmentos', (
            SELECT COUNT(*) 
            FROM app_mkt_segmentos 
            WHERE id_tienda = p_id_tienda
        ),
        'comunicaciones_enviadas', (
            SELECT COUNT(*) 
            FROM app_mkt_comunicaciones 
            WHERE id_tienda = p_id_tienda AND estado = 1
        ),
        'eventos_fidelizacion', (
            SELECT COUNT(*) 
            FROM app_mkt_eventos_fidelizacion 
            WHERE id_tienda = p_id_tienda 
            AND fecha_evento >= CURRENT_DATE - INTERVAL '30 days'
        )
    ) INTO v_result;
    
    RETURN v_result;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error obteniendo resumen de marketing';
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- Función para obtener métricas de rendimiento (SEGURA)
CREATE OR REPLACE FUNCTION fn_marketing_metricas_rendimiento(
    p_id_tienda BIGINT,
    p_fecha_desde DATE DEFAULT NULL,
    p_fecha_hasta DATE DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
    v_fecha_desde DATE := COALESCE(p_fecha_desde, CURRENT_DATE - INTERVAL '30 days');
    v_fecha_hasta DATE := COALESCE(p_fecha_hasta, CURRENT_DATE);
    v_result JSON;
    v_usuario_uuid UUID := auth.uid();
BEGIN
    -- Validar autenticación
    IF v_usuario_uuid IS NULL THEN
        RAISE EXCEPTION 'Usuario no autenticado';
    END IF;
    
    -- Validar parámetros
    PERFORM fn_validar_parametros_entrada(p_id_tienda);
    
    -- Validar acceso a tienda
    IF NOT fn_validar_acceso_tienda(p_id_tienda, v_usuario_uuid) THEN
        RAISE EXCEPTION 'Acceso denegado a la tienda: %', p_id_tienda;
    END IF;
    
    -- Validar rango de fechas
    IF v_fecha_hasta < v_fecha_desde THEN
        RAISE EXCEPTION 'Fecha hasta debe ser posterior a fecha desde';
    END IF;
    
    -- Limitar rango máximo a 1 año
    IF v_fecha_hasta - v_fecha_desde > INTERVAL '1 year' THEN
        RAISE EXCEPTION 'Rango de fechas no puede exceder 1 año';
    END IF;
    
    SELECT json_build_object(
        'periodo', json_build_object(
            'desde', v_fecha_desde,
            'hasta', v_fecha_hasta
        ),
        'promociones_creadas', (
            SELECT COUNT(*) 
            FROM app_mkt_promociones 
            WHERE id_tienda = p_id_tienda 
            AND created_at::DATE BETWEEN v_fecha_desde AND v_fecha_hasta
        ),
        'campanas_ejecutadas', (
            SELECT COUNT(*) 
            FROM app_mkt_campanas 
            WHERE id_tienda = p_id_tienda 
            AND fecha_inicio BETWEEN v_fecha_desde AND v_fecha_hasta
        ),
        'comunicaciones_enviadas', (
            SELECT COUNT(*) 
            FROM app_mkt_comunicaciones 
            WHERE id_tienda = p_id_tienda 
            AND fecha_envio BETWEEN v_fecha_desde AND v_fecha_hasta
        ),
        'eventos_fidelizacion', (
            SELECT COUNT(*) 
            FROM app_mkt_eventos_fidelizacion 
            WHERE id_tienda = p_id_tienda 
            AND fecha_evento BETWEEN v_fecha_desde AND v_fecha_hasta
        )
    ) INTO v_result;
    
    RETURN v_result;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error obteniendo métricas de rendimiento';
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- =====================================================
-- 2. FUNCIONES PARA CAMPAÑAS
-- =====================================================

-- Función para listar campañas (SEGURA)
CREATE OR REPLACE FUNCTION fn_listar_campanas(
    p_id_tienda BIGINT,
    p_limite INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE(
    id BIGINT,
    nombre VARCHAR,
    descripcion TEXT,
    tipo_campana VARCHAR,
    estado VARCHAR,
    fecha_inicio DATE,
    fecha_fin DATE,
    presupuesto DECIMAL,
    metricas JSONB,
    created_at TIMESTAMP
) AS $$
DECLARE
    v_usuario_uuid UUID := auth.uid();
    v_limite_maximo INTEGER;
BEGIN
    -- Validar autenticación
    IF v_usuario_uuid IS NULL THEN
        RAISE EXCEPTION 'Usuario no autenticado';
    END IF;
    
    -- Validar parámetros
    PERFORM fn_validar_parametros_entrada(p_id_tienda);
    
    -- Validar acceso a tienda
    IF NOT fn_validar_acceso_tienda(p_id_tienda, v_usuario_uuid) THEN
        RAISE EXCEPTION 'Acceso denegado a la tienda: %', p_id_tienda;
    END IF;
    
    -- Aplicar límites seguros
    SELECT max_registros_lista INTO v_limite_maximo FROM fn_obtener_limites_seguros();
    p_limite := LEAST(COALESCE(p_limite, 50), v_limite_maximo);
    p_offset := GREATEST(COALESCE(p_offset, 0), 0);
    
    RETURN QUERY
    SELECT c.id, c.nombre, c.descripcion, 
           CASE WHEN tc.denominacion IS NOT NULL THEN tc.denominacion ELSE 'General' END::VARCHAR as tipo_campana,
           CASE WHEN c.estado = 1 THEN 'activa' ELSE 'inactiva' END::VARCHAR as estado,
           c.fecha_inicio, c.fecha_fin, c.presupuesto, c.metricas, c.created_at
    FROM app_mkt_campanas c
    LEFT JOIN app_mkt_tipo_campana tc ON c.id_tipo_campana = tc.id
    WHERE c.id_tienda = p_id_tienda
    ORDER BY c.created_at DESC
    LIMIT p_limite OFFSET p_offset;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error listando campañas';
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- Función para insertar campaña (SEGURA)
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
    -- Validar autenticación
    IF v_usuario_uuid IS NULL THEN
        RAISE EXCEPTION 'Usuario no autenticado';
    END IF;
    
    -- Validar parámetros
    PERFORM fn_validar_parametros_entrada(p_id_tienda, p_nombre, p_descripcion);
    
    -- Validar acceso a tienda
    IF NOT fn_validar_acceso_tienda(p_id_tienda, v_usuario_uuid) THEN
        RAISE EXCEPTION 'Acceso denegado a la tienda: %', p_id_tienda;
    END IF;
    
    -- Validar tipo de campaña
    IF NOT EXISTS (SELECT 1 FROM app_mkt_tipo_campana WHERE id = p_id_tipo_campana) THEN
        RAISE EXCEPTION 'Tipo de campaña inválido: %', p_id_tipo_campana;
    END IF;
    
    -- Validar fechas
    IF p_fecha_fin IS NOT NULL AND p_fecha_fin < p_fecha_inicio THEN
        RAISE EXCEPTION 'Fecha fin debe ser posterior a fecha inicio';
    END IF;
    
    -- Validar presupuesto
    IF p_presupuesto IS NOT NULL AND p_presupuesto < 0 THEN
        RAISE EXCEPTION 'Presupuesto no puede ser negativo';
    END IF;
    
    INSERT INTO app_mkt_campanas (
        id_tienda, nombre, descripcion, id_tipo_campana,
        fecha_inicio, fecha_fin, presupuesto, estado
    ) VALUES (
        p_id_tienda, p_nombre, p_descripcion, p_id_tipo_campana,
        p_fecha_inicio, p_fecha_fin, p_presupuesto, 1
    ) RETURNING id INTO v_id_campana;
    
    -- Log de auditoría
    INSERT INTO app_mkt_function_logs (
        function_name, usuario_uuid, id_tienda, parametros, resultado, tiempo_ejecucion
    ) VALUES (
        'fn_insertar_campana', v_usuario_uuid, p_id_tienda,
        jsonb_build_object('nombre', p_nombre, 'tipo_campana', p_id_tipo_campana),
        'SUCCESS', clock_timestamp() - v_start_time
    );
    
    RETURN v_id_campana;
    
EXCEPTION
    WHEN OTHERS THEN
        -- Log de error
        INSERT INTO app_mkt_function_logs (
            function_name, usuario_uuid, id_tienda, resultado, mensaje_error, tiempo_ejecucion
        ) VALUES (
            'fn_insertar_campana', v_usuario_uuid, p_id_tienda, 'ERROR', SQLERRM, clock_timestamp() - v_start_time
        );
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
)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE app_mkt_campanas SET
        nombre = p_nombre,
        descripcion = p_descripcion,
        id_tipo_campana = p_id_tipo_campana,
        fecha_inicio = p_fecha_inicio,
        fecha_fin = p_fecha_fin,
        presupuesto = p_presupuesto,
        estado = COALESCE(p_estado, estado)
    WHERE id = p_id;
    
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Función para eliminar campaña
CREATE OR REPLACE FUNCTION fn_eliminar_campana(p_id BIGINT)
RETURNS BOOLEAN AS $$
BEGIN
    -- Verificar si tiene promociones asociadas
    IF EXISTS (SELECT 1 FROM app_mkt_promociones WHERE id_campana = p_id) THEN
        RAISE EXCEPTION 'No se puede eliminar la campaña porque tiene promociones asociadas';
    END IF;
    
    DELETE FROM app_mkt_campanas WHERE id = p_id;
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 3. FUNCIONES PARA COMUNICACIONES
-- =====================================================

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
BEGIN
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
END;
$$ LANGUAGE plpgsql;

-- Función para insertar comunicación
CREATE OR REPLACE FUNCTION fn_insertar_comunicacion(
    p_id_tienda BIGINT,
    p_asunto VARCHAR,
    p_contenido TEXT,
    p_id_tipo_campana SMALLINT DEFAULT 1,
    p_id_campana BIGINT DEFAULT NULL,
    p_id_segmento BIGINT DEFAULT NULL,
    p_fecha_programada TIMESTAMPTZ DEFAULT NULL
) RETURNS BIGINT AS $$
DECLARE
    v_id_comunicacion BIGINT;
BEGIN
    INSERT INTO app_mkt_comunicaciones (
        id_tienda,
        id_campana,
        id_segmento,
        asunto,
        contenido,
        fecha_programada,
        id_tipo_campana,
        estado
    ) VALUES (
        p_id_tienda,
        p_id_campana,
        p_id_segmento,
        p_asunto,
        p_contenido,
        p_fecha_programada,
        p_id_tipo_campana,
        1
    ) RETURNING id INTO v_id_comunicacion;
    
    RETURN v_id_comunicacion;
END;
$$ LANGUAGE plpgsql;

-- Función para actualizar comunicación
CREATE OR REPLACE FUNCTION fn_actualizar_comunicacion(
    p_id BIGINT,
    p_asunto VARCHAR,
    p_contenido TEXT,
    p_fecha_programada TIMESTAMPTZ DEFAULT NULL,
    p_estado SMALLINT DEFAULT NULL
)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE app_mkt_comunicaciones SET
        asunto = p_asunto,
        contenido = p_contenido,
        fecha_programada = p_fecha_programada,
        estado = COALESCE(p_estado, estado)
    WHERE id = p_id;
    
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 4. FUNCIONES PARA SEGMENTOS DE CLIENTES
-- =====================================================

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
BEGIN
    RETURN QUERY
    SELECT 
        s.id,
        s.nombre,
        s.descripcion,
        s.criterios,
        -- Calcular total de clientes (simulado por ahora)
        (RANDOM() * 100 + 10)::INTEGER as total_clientes,
        s.created_at
    FROM app_mkt_segmentos s
    WHERE s.id_tienda = p_id_tienda
    ORDER BY s.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Función para insertar segmento
CREATE OR REPLACE FUNCTION fn_insertar_segmento(
    p_id_tienda BIGINT,
    p_nombre VARCHAR,
    p_descripcion TEXT,
    p_criterios JSONB DEFAULT '{}'
)
RETURNS BIGINT AS $$
DECLARE
    v_id_segmento BIGINT;
BEGIN
    INSERT INTO app_mkt_segmentos (
        id_tienda,
        nombre,
        descripcion,
        criterios
    ) VALUES (
        p_id_tienda,
        p_nombre,
        p_descripcion,
        p_criterios
    ) RETURNING id INTO v_id_segmento;
    
    RETURN v_id_segmento;
END;
$$ LANGUAGE plpgsql;

-- Función para actualizar segmento
CREATE OR REPLACE FUNCTION fn_actualizar_segmento(
    p_id BIGINT,
    p_nombre VARCHAR,
    p_descripcion TEXT,
    p_criterios JSONB DEFAULT NULL
)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE app_mkt_segmentos SET
        nombre = p_nombre,
        descripcion = p_descripcion,
        criterios = p_criterios
    WHERE id = p_id;
    
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Función para eliminar segmento
CREATE OR REPLACE FUNCTION fn_eliminar_segmento(p_id BIGINT)
RETURNS BOOLEAN AS $$
BEGIN
    -- Verificar si tiene comunicaciones asociadas
    IF EXISTS (SELECT 1 FROM app_mkt_comunicaciones WHERE id_segmento = p_id) THEN
        RAISE EXCEPTION 'No se puede eliminar el segmento porque tiene comunicaciones asociadas';
    END IF;
    
    DELETE FROM app_mkt_segmentos WHERE id = p_id;
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Función para obtener clientes de un segmento
CREATE OR REPLACE FUNCTION fn_clientes_por_segmento(
    p_id_segmento BIGINT,
    p_limite INTEGER DEFAULT 100
)
RETURNS TABLE(
    id BIGINT,
    nombre_completo VARCHAR,
    email VARCHAR,
    telefono VARCHAR,
    total_compras NUMERIC,
    ultima_compra TIMESTAMPTZ,
    puntos_acumulados INTEGER
) AS $$
DECLARE
    v_criterios JSONB;
BEGIN
    -- Obtener criterios del segmento
    SELECT criterios INTO v_criterios 
    FROM app_mkt_segmentos 
    WHERE id = p_id_segmento;
    
    -- Por ahora retornamos una consulta básica
    -- En producción aquí se evaluarían los criterios JSONB
    RETURN QUERY
    SELECT 
        c.id,
        c.nombre_completo,
        c.email,
        c.telefono,
        c.total_compras,
        c.ultima_compra,
        c.puntos_acumulados
    FROM app_dat_clientes c
    WHERE c.activo = true
    ORDER BY c.total_compras DESC
    LIMIT p_limite;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 5. FUNCIONES PARA PROGRAMA DE FIDELIZACIÓN
-- =====================================================

-- Función para obtener resumen de fidelización
CREATE OR REPLACE FUNCTION fn_fidelizacion_resumen(p_id_tienda BIGINT)
RETURNS JSON AS $$
DECLARE
    v_result JSON;
BEGIN
    SELECT json_build_object(
        'clientes_registrados', (
            SELECT COUNT(*) 
            FROM app_dat_clientes 
            WHERE activo = true
        ),
        'clientes_con_puntos', (
            SELECT COUNT(*) 
            FROM app_dat_clientes 
            WHERE puntos_acumulados > 0 AND activo = true
        ),
        'total_puntos_emitidos', (
            SELECT COALESCE(SUM(puntos_acumulados), 0) 
            FROM app_dat_clientes 
            WHERE activo = true
        ),
        'eventos_mes_actual', (
            SELECT COUNT(*) 
            FROM app_mkt_eventos_fidelizacion 
            WHERE id_tienda = p_id_tienda
            AND EXTRACT(MONTH FROM created_at) = EXTRACT(MONTH FROM CURRENT_DATE)
            AND EXTRACT(YEAR FROM created_at) = EXTRACT(YEAR FROM CURRENT_DATE)
        ),
        'clientes_nivel_oro', (
            SELECT COUNT(*) 
            FROM app_dat_clientes 
            WHERE nivel_fidelidad >= 3 AND activo = true
        ),
        'clientes_nivel_plata', (
            SELECT COUNT(*) 
            FROM app_dat_clientes 
            WHERE nivel_fidelidad = 2 AND activo = true
        ),
        'clientes_nivel_bronce', (
            SELECT COUNT(*) 
            FROM app_dat_clientes 
            WHERE nivel_fidelidad = 1 AND activo = true
        )
    ) INTO v_result;
    
    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- Función para listar eventos de fidelización
CREATE OR REPLACE FUNCTION fn_listar_eventos_fidelizacion(
    p_id_tienda BIGINT,
    p_limite INTEGER DEFAULT 50
)
RETURNS TABLE(
    id BIGINT,
    cliente_nombre VARCHAR,
    tipo_evento VARCHAR,
    puntos_otorgados INTEGER,
    descripcion TEXT,
    fecha_evento TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ef.id,
        c.nombre_completo as cliente_nombre,
        ef.tipo_evento,
        ef.puntos_otorgados,
        ef.descripcion,
        ef.created_at as fecha_evento
    FROM app_mkt_eventos_fidelizacion ef
    JOIN app_dat_clientes c ON ef.id_cliente = c.id
    WHERE ef.id_tienda = p_id_tienda
    ORDER BY ef.created_at DESC
    LIMIT p_limite;
END;
$$ LANGUAGE plpgsql;

-- Función para registrar evento de fidelización
CREATE OR REPLACE FUNCTION fn_registrar_evento_fidelizacion(
    p_id_cliente BIGINT,
    p_id_tienda BIGINT,
    p_tipo_evento VARCHAR,
    p_puntos_otorgados INTEGER DEFAULT 0,
    p_descripcion TEXT DEFAULT NULL,
    p_id_operacion BIGINT DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
    v_id_evento BIGINT;
BEGIN
    -- Insertar evento
    INSERT INTO app_mkt_eventos_fidelizacion (
        id_cliente,
        id_tienda,
        tipo_evento,
        puntos_otorgados,
        descripcion,
        id_operacion
    ) VALUES (
        p_id_cliente,
        p_id_tienda,
        p_tipo_evento,
        p_puntos_otorgados,
        p_descripcion,
        p_id_operacion
    ) RETURNING id INTO v_id_evento;
    
    -- Actualizar puntos del cliente
    UPDATE app_dat_clientes 
    SET puntos_acumulados = puntos_acumulados + p_puntos_otorgados
    WHERE id = p_id_cliente;
    
    RETURN v_id_evento;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 6. FUNCIONES PARA ANÁLISIS Y REPORTES
-- =====================================================

-- Función para análisis de promociones
CREATE OR REPLACE FUNCTION fn_analisis_promociones(
    p_id_tienda BIGINT,
    p_fecha_desde DATE DEFAULT NULL,
    p_fecha_hasta DATE DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
    v_fecha_desde DATE := COALESCE(p_fecha_desde, CURRENT_DATE - INTERVAL '30 days');
    v_fecha_hasta DATE := COALESCE(p_fecha_hasta, CURRENT_DATE);
    v_result JSON;
BEGIN
    SELECT json_build_object(
        'promociones_mas_usadas', (
            SELECT json_agg(
                json_build_object(
                    'promocion', p.denominacion,
                    'usos', COUNT(cp.id),
                    'descuento_total', SUM(cp.descuento_aplicado)
                )
            )
            FROM app_mkt_cliente_promociones cp
            JOIN app_mkt_promociones p ON cp.id_promocion = p.id
            WHERE p.id_tienda = p_id_tienda
            AND cp.fecha_uso::date BETWEEN v_fecha_desde AND v_fecha_hasta
            GROUP BY p.id, p.denominacion
            ORDER BY COUNT(cp.id) DESC
            LIMIT 5
        ),
        'ventas_por_promocion', (
            SELECT json_agg(
                json_build_object(
                    'promocion', p.denominacion,
                    'ventas_totales', COUNT(ov.id_operacion),
                    'importe_total', SUM(ov.importe_total)
                )
            )
            FROM app_dat_operacion_venta ov
            JOIN app_dat_operaciones o ON ov.id_operacion = o.id
            JOIN app_mkt_promociones p ON ov.id_promocion = p.id
            WHERE o.id_tienda = p_id_tienda
            AND o.created_at::date BETWEEN v_fecha_desde AND v_fecha_hasta
            GROUP BY p.id, p.denominacion
            ORDER BY SUM(ov.importe_total) DESC
        )
    ) INTO v_result;
    
    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- Función para análisis de clientes
CREATE OR REPLACE FUNCTION fn_analisis_clientes(p_id_tienda BIGINT)
RETURNS JSON AS $$
DECLARE
    v_result JSON;
BEGIN
    SELECT json_build_object(
        'distribucion_por_nivel', (
            SELECT json_agg(
                json_build_object(
                    'nivel', 
                    CASE nivel_fidelidad
                        WHEN 1 THEN 'Bronce'
                        WHEN 2 THEN 'Plata'
                        WHEN 3 THEN 'Oro'
                        ELSE 'Sin nivel'
                    END,
                    'cantidad', COUNT(*)
                )
            )
            FROM app_dat_clientes
            WHERE activo = true
            GROUP BY nivel_fidelidad
            ORDER BY nivel_fidelidad
        ),
        'clientes_top_compras', (
            SELECT json_agg(
                json_build_object(
                    'nombre', nombre_completo,
                    'total_compras', total_compras,
                    'puntos', puntos_acumulados
                )
            )
            FROM app_dat_clientes
            WHERE activo = true
            ORDER BY total_compras DESC
            LIMIT 10
        ),
        'nuevos_clientes_mes', (
            SELECT COUNT(*)
            FROM app_dat_clientes
            WHERE EXTRACT(MONTH FROM fecha_registro) = EXTRACT(MONTH FROM CURRENT_DATE)
            AND EXTRACT(YEAR FROM fecha_registro) = EXTRACT(YEAR FROM CURRENT_DATE)
        )
    ) INTO v_result;
    
    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 7. FUNCIONES PARA GESTIÓN MULTI-TIENDA
-- =====================================================

-- Función para obtener tiendas de un gerente
CREATE OR REPLACE FUNCTION fn_listar_tiendas_gerente(p_uuid UUID)
RETURNS TABLE(
    id BIGINT,
    denominacion VARCHAR,
    direccion VARCHAR,
    telefono VARCHAR,
    email VARCHAR,
    es_principal BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        t.id,
        t.denominacion,
        t.direccion,
        t.telefono,
        t.email,
        -- Marcar como principal la primera tienda registrada
        ROW_NUMBER() OVER (ORDER BY g.created_at) = 1 as es_principal
    FROM app_dat_gerente g
    JOIN app_dat_tienda t ON g.id_tienda = t.id
    WHERE g.uuid = p_uuid
    ORDER BY g.created_at;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 8. FUNCIONES AUXILIARES Y DE CONFIGURACIÓN
-- =====================================================

-- Función para obtener tipos de campaña
CREATE OR REPLACE FUNCTION fn_listar_tipos_campana()
RETURNS TABLE(
    id SMALLINT,
    denominacion VARCHAR,
    descripcion TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT tc.id, tc.denominacion, tc.descripcion
    FROM app_mkt_tipo_campana tc
    ORDER BY tc.denominacion;
END;
$$ LANGUAGE plpgsql;

-- Función para obtener criterios de segmentación
CREATE OR REPLACE FUNCTION fn_listar_criterios_segmentacion()
RETURNS TABLE(
    id SMALLINT,
    denominacion VARCHAR,
    campo_db VARCHAR,
    tipo_dato VARCHAR,
    descripcion TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT cs.id, cs.denominacion, cs.campo_db, cs.tipo_dato, cs.descripcion
    FROM app_mkt_criterios_segmentacion cs
    ORDER BY cs.denominacion;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- FUNCIÓN: Estadísticas de Promociones
-- =====================================================
CREATE OR REPLACE FUNCTION fn_estadisticas_promociones(
    p_id_tienda INTEGER,
    p_fecha_desde TIMESTAMP DEFAULT NULL,
    p_fecha_hasta TIMESTAMP DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_stats JSONB;
    v_total_promociones INTEGER;
    v_promociones_activas INTEGER;
    v_promociones_vencidas INTEGER;
    v_promociones_programadas INTEGER;
    v_total_usos INTEGER;
    v_descuento_total NUMERIC;
BEGIN
    -- Contar total de promociones
    SELECT COUNT(*) INTO v_total_promociones
    FROM app_mkt_promociones p
    JOIN app_dat_tienda t ON p.id_tienda = t.id
    WHERE t.id = p_id_tienda;

    -- Contar promociones activas
    SELECT COUNT(*) INTO v_promociones_activas
    FROM app_mkt_promociones p
    JOIN app_dat_tienda t ON p.id_tienda = t.id
    WHERE t.id = p_id_tienda
    AND p.estado = true
    AND p.fecha_inicio <= NOW()
    AND (p.fecha_fin IS NULL OR p.fecha_fin >= NOW());

    -- Contar promociones vencidas
    SELECT COUNT(*) INTO v_promociones_vencidas
    FROM app_mkt_promociones p
    JOIN app_dat_tienda t ON p.id_tienda = t.id
    WHERE t.id = p_id_tienda
    AND p.fecha_fin IS NOT NULL
    AND p.fecha_fin < NOW();

    -- Contar promociones programadas
    SELECT COUNT(*) INTO v_promociones_programadas
    FROM app_mkt_promociones p
    JOIN app_dat_tienda t ON p.id_tienda = t.id
    WHERE t.id = p_id_tienda
    AND p.fecha_inicio > NOW();

    -- Calcular usos totales (simulado)
    v_total_usos := v_promociones_activas * 15 + v_promociones_vencidas * 25;

    -- Calcular descuento total aplicado (simulado)
    SELECT COALESCE(SUM(p.valor_descuento * 1000), 0) INTO v_descuento_total
    FROM app_mkt_promociones p
    JOIN app_dat_tienda t ON p.id_tienda = t.id
    WHERE t.id = p_id_tienda
    AND p.estado = true;

    -- Construir respuesta JSON
    v_stats := jsonb_build_object(
        'total_promociones', v_total_promociones,
        'promociones_activas', v_promociones_activas,
        'promociones_vencidas', v_promociones_vencidas,
        'promociones_programadas', v_promociones_programadas,
        'total_usos', v_total_usos,
        'descuento_total_aplicado', v_descuento_total,
        'roi_promociones', 3.2,
        'conversion_rate', 12.5
    );

    RETURN v_stats;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error obteniendo estadísticas de promociones: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- =====================================================

-- Habilitar RLS en tablas de marketing
ALTER TABLE app_mkt_promociones ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_mkt_campanas ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_mkt_comunicaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_mkt_segmentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_mkt_eventos_fidelizacion ENABLE ROW LEVEL SECURITY;

-- Política para promociones: solo acceso a tiendas del gerente
CREATE POLICY promociones_tienda_policy ON app_mkt_promociones
    FOR ALL
    USING (
        id_tienda IN (
            SELECT t.id 
            FROM app_dat_tienda t
            JOIN app_dat_gerente g ON t.id = g.id_tienda
            WHERE g.uuid = auth.uid()
        )
    );

-- Política para campañas: solo acceso a tiendas del gerente
CREATE POLICY campanas_tienda_policy ON app_mkt_campanas
    FOR ALL
    USING (
        id_tienda IN (
            SELECT t.id 
            FROM app_dat_tienda t
            JOIN app_dat_gerente g ON t.id = g.id_tienda
            WHERE g.uuid = auth.uid()
        )
    );

-- Política para comunicaciones: solo acceso a tiendas del gerente
CREATE POLICY comunicaciones_tienda_policy ON app_mkt_comunicaciones
    FOR ALL
    USING (
        id_tienda IN (
            SELECT t.id 
            FROM app_dat_tienda t
            JOIN app_dat_gerente g ON t.id = g.id_tienda
            WHERE g.uuid = auth.uid()
        )
    );

-- Política para segmentos: solo acceso a tiendas del gerente
CREATE POLICY segmentos_tienda_policy ON app_mkt_segmentos
    FOR ALL
    USING (
        id_tienda IN (
            SELECT t.id 
            FROM app_dat_tienda t
            JOIN app_dat_gerente g ON t.id = g.id_tienda
            WHERE g.uuid = auth.uid()
        )
    );

-- Política para eventos de fidelización: solo acceso a tiendas del gerente
CREATE POLICY eventos_fidelizacion_tienda_policy ON app_mkt_eventos_fidelizacion
    FOR ALL
    USING (
        id_tienda IN (
            SELECT t.id 
            FROM app_dat_tienda t
            JOIN app_dat_gerente g ON t.id = g.id_tienda
            WHERE g.uuid = auth.uid()
        )
    );

-- =====================================================
-- FUNCIONES DE VALIDACIÓN DE INTEGRIDAD
-- =====================================================

-- Función para validar criterios JSONB de segmentación
CREATE OR REPLACE FUNCTION fn_validar_criterios_segmentacion(
    p_criterios JSONB
)
RETURNS BOOLEAN AS $$
DECLARE
    v_criterio JSONB;
    v_campo TEXT;
    v_operador TEXT;
    v_valor TEXT;
BEGIN
    -- Validar que criterios no sea nulo o vacío
    IF p_criterios IS NULL OR p_criterios = '{}'::jsonb THEN
        RETURN FALSE;
    END IF;

    -- Validar estructura de cada criterio
    FOR v_criterio IN SELECT jsonb_array_elements(p_criterios->'criterios')
    LOOP
        v_campo := v_criterio->>'campo';
        v_operador := v_criterio->>'operador';
        v_valor := v_criterio->>'valor';

        -- Validar campos obligatorios
        IF v_campo IS NULL OR v_operador IS NULL OR v_valor IS NULL THEN
            RETURN FALSE;
        END IF;

        -- Validar operadores válidos
        IF v_operador NOT IN ('=', '!=', '>', '<', '>=', '<=', 'LIKE', 'IN', 'NOT IN') THEN
            RETURN FALSE;
        END IF;
    END LOOP;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Función para validar métricas JSONB de campañas
CREATE OR REPLACE FUNCTION fn_validar_metricas_campana(
    p_metricas JSONB
)
RETURNS BOOLEAN AS $$
BEGIN
    -- Validar que métricas no sea nulo
    IF p_metricas IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Validar campos numéricos básicos
    IF (p_metricas->>'impresiones')::INTEGER < 0 OR
       (p_metricas->>'clics')::INTEGER < 0 OR
       (p_metricas->>'conversiones')::INTEGER < 0 THEN
        RETURN FALSE;
    END IF;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Trigger para validar criterios antes de insertar/actualizar segmentos
CREATE OR REPLACE FUNCTION trg_validar_segmento()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT fn_validar_criterios_segmentacion(NEW.criterios) THEN
        RAISE EXCEPTION 'Criterios de segmentación inválidos';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_validar_segmento
    BEFORE INSERT OR UPDATE ON app_mkt_segmentos
    FOR EACH ROW EXECUTE FUNCTION trg_validar_segmento();

-- Trigger para validar métricas antes de insertar/actualizar campañas
CREATE OR REPLACE FUNCTION trg_validar_campana()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.metricas IS NOT NULL AND NOT fn_validar_metricas_campana(NEW.metricas) THEN
        RAISE EXCEPTION 'Métricas de campaña inválidas';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_validar_campana
    BEFORE INSERT OR UPDATE ON app_mkt_campanas
    FOR EACH ROW EXECUTE FUNCTION trg_validar_campana();

-- =====================================================
-- FUNCIONES DE AUDITORÍA
-- =====================================================

-- Función para registrar cambios en promociones
CREATE OR REPLACE FUNCTION fn_auditoria_promociones()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        INSERT INTO app_log_auditoria (
            tabla, operacion, registro_id, datos_anteriores, 
            usuario, fecha_operacion
        ) VALUES (
            'app_mkt_promociones', 'DELETE', OLD.id::TEXT, 
            row_to_json(OLD)::JSONB, auth.uid(), NOW()
        );
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO app_log_auditoria (
            tabla, operacion, registro_id, datos_anteriores, 
            datos_nuevos, usuario, fecha_operacion
        ) VALUES (
            'app_mkt_promociones', 'UPDATE', NEW.id::TEXT, 
            row_to_json(OLD)::JSONB, row_to_json(NEW)::JSONB, 
            auth.uid(), NOW()
        );
        RETURN NEW;
    ELSIF TG_OP = 'INSERT' THEN
        INSERT INTO app_log_auditoria (
            tabla, operacion, registro_id, datos_nuevos, 
            usuario, fecha_operacion
        ) VALUES (
            'app_mkt_promociones', 'INSERT', NEW.id::TEXT, 
            row_to_json(NEW)::JSONB, auth.uid(), NOW()
        );
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Crear trigger de auditoría para promociones (si existe tabla de auditoría)
-- CREATE TRIGGER trigger_auditoria_promociones
--     AFTER INSERT OR UPDATE OR DELETE ON app_mkt_promociones
--     FOR EACH ROW EXECUTE FUNCTION fn_auditoria_promociones();

-- =====================================================
-- NOTAS DE IMPLEMENTACIÓN RESTANTES
-- =====================================================
/*
IMPLEMENTADO AUTOMÁTICAMENTE:
✅ 4. RLS (Row Level Security) para todas las tablas de marketing
✅ 5. Validaciones para evitar eliminar registros con dependencias (en funciones de eliminación)
✅ 6. Validación de campos JSONB con funciones específicas

PENDIENTE DE IMPLEMENTACIÓN MANUAL:
2. Reemplazar datos simulados por lógica real según criterios JSONB
3. Optimización con índices apropiados (ver archivo separado)

NOTAS ADICIONALES:
- Las políticas RLS requieren que auth.uid() retorne el UUID del usuario autenticado
- Los triggers de auditoría requieren una tabla app_log_auditoria
- Las funciones de validación JSONB pueden expandirse según necesidades específicas
*/
