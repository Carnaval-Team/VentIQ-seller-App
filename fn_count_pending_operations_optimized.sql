-- ============================================================================
-- FUNCIÓN RPC: Conteo Optimizado de Operaciones Pendientes (CON LOGGING)
-- ============================================================================
-- Cuenta operaciones pendientes sin cargar datos completos
-- Incluye validaciones de seguridad Y logging detallado para debug

CREATE OR REPLACE FUNCTION fn_count_pending_operations_optimized(
    p_id_tienda BIGINT,
    p_fecha_inicio DATE DEFAULT NULL,
    p_fecha_fin DATE DEFAULT NULL,
    p_user_uuid UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER -- Ejecuta con privilegios del propietario
SET search_path = public -- Prevenir ataques de path injection
AS $$
DECLARE
    v_recepciones_count INTEGER := 0;
    v_entregas_count INTEGER := 0;
    v_total_count INTEGER := 0;
    v_user_tienda_id BIGINT;
    v_resultado JSON;
    v_debug_info TEXT := '';
BEGIN
    -- LOG: Inicio de función
    v_debug_info := format('INICIO - Tienda: %s, Usuario: %s, Fechas: %s a %s', 
        p_id_tienda, p_user_uuid, p_fecha_inicio, p_fecha_fin);
    RAISE NOTICE 'fn_count_pending_operations_optimized: %', v_debug_info;

    -- VALIDACIÓN DE SEGURIDAD: Verificar que el usuario tiene acceso a la tienda
    IF p_user_uuid IS NOT NULL THEN
        BEGIN
            SELECT t.id INTO v_user_tienda_id
            FROM app_dat_tienda t
            INNER JOIN app_dat_tpv tpv ON tpv.id_tienda = t.id
            INNER JOIN app_dat_vendedor v ON v.id_tpv = tpv.id
            WHERE v.uuid = p_user_uuid
            AND t.id = p_id_tienda
            LIMIT 1;

            RAISE NOTICE 'Validación usuario - Tienda encontrada: %', v_user_tienda_id;

            IF v_user_tienda_id IS NULL THEN
                RAISE NOTICE 'ERROR: Usuario no autorizado para tienda %', p_id_tienda;
                RETURN json_build_object(
                    'success', false,
                    'error', 'Usuario no autorizado para esta tienda',
                    'debug_info', v_debug_info,
                    'total_count', 0,
                    'recepciones_count', 0,
                    'entregas_count', 0
                );
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'ERROR en validación usuario: % %', SQLSTATE, SQLERRM;
                RETURN json_build_object(
                    'success', false,
                    'error', format('Error validación usuario: %s', SQLERRM),
                    'debug_info', v_debug_info,
                    'total_count', 0
                );
        END;
    END IF;

    -- VALIDAR PARÁMETROS DE ENTRADA
    IF p_id_tienda IS NULL OR p_id_tienda <= 0 THEN
        RAISE NOTICE 'ERROR: ID de tienda inválido: %', p_id_tienda;
        RETURN json_build_object(
            'success', false,
            'error', 'ID de tienda inválido',
            'debug_info', v_debug_info,
            'total_count', 0
        );
    END IF;

    -- CONTAR RECEPCIONES PENDIENTES (CON LOGGING)
    BEGIN
        RAISE NOTICE 'Iniciando conteo de recepciones...';
        
        SELECT COUNT(*)
        INTO v_recepciones_count
        FROM app_dat_operacion_recepcion r
        INNER JOIN app_dat_operaciones o ON o.id = r.id_operacion
        WHERE o.id_tienda = p_id_tienda
        AND o.id_tipo_operacion = 1 -- Solo recepciones por compra
        AND (p_fecha_inicio IS NULL OR r.created_at::DATE >= p_fecha_inicio)
        AND (p_fecha_fin IS NULL OR r.created_at::DATE <= p_fecha_fin)
        AND NOT EXISTS (
            SELECT 1 
            FROM app_cont_gastos g 
            WHERE g.tipo_origen IN ('recepcion', 'operacion_recepcion')
            AND g.id_referencia_origen = r.id_operacion
        );

        RAISE NOTICE 'Recepciones pendientes encontradas: %', v_recepciones_count;
        
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'ERROR contando recepciones: % %', SQLSTATE, SQLERRM;
            RETURN json_build_object(
                'success', false,
                'error', format('Error contando recepciones: %s', SQLERRM),
                'debug_info', v_debug_info,
                'sqlstate', SQLSTATE,
                'total_count', 0
            );
    END;

    -- CONTAR ENTREGAS DE EFECTIVO PENDIENTES (CON LOGGING)
    BEGIN
        RAISE NOTICE 'Iniciando conteo de entregas de efectivo...';
        
        SELECT COUNT(*)
        INTO v_entregas_count
        FROM app_dat_entregas_parciales_caja e
        INNER JOIN app_dat_caja_turno ct ON ct.id = e.id_turno
        INNER JOIN app_dat_tpv tpv ON tpv.id = ct.id_tpv
        WHERE tpv.id_tienda = p_id_tienda
        AND (p_fecha_inicio IS NULL OR e.fecha_entrega >= p_fecha_inicio)
        AND (p_fecha_fin IS NULL OR e.fecha_entrega <= p_fecha_fin)
        AND NOT EXISTS (
            SELECT 1 
            FROM app_cont_gastos g 
            WHERE g.tipo_origen IN ('entrega_efectivo', 'egreso_efectivo')
            AND g.id_referencia_origen = e.id
        )
        AND NOT EXISTS (
            SELECT 1 
            FROM app_cont_egresos_procesados ep 
            WHERE ep.id_egreso = e.id 
            AND ep.estado = 'rechazado'
        );

        RAISE NOTICE 'Entregas de efectivo pendientes encontradas: %', v_entregas_count;
        
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'ERROR contando entregas (no crítico): % %', SQLSTATE, SQLERRM;
            -- No es crítico, continuar con v_entregas_count = 0
            v_entregas_count := 0;
    END;

    -- CALCULAR TOTAL
    v_total_count := v_recepciones_count + v_entregas_count;
    RAISE NOTICE 'Total calculado: % (Recepciones: % + Entregas: %)', 
        v_total_count, v_recepciones_count, v_entregas_count;

    -- CONSTRUIR RESULTADO
    v_resultado := json_build_object(
        'success', true,
        'total_count', v_total_count,
        'recepciones_count', v_recepciones_count,
        'entregas_count', v_entregas_count,
        'fecha_calculo', NOW(),
        'tienda_id', p_id_tienda,
        'debug_info', v_debug_info,
        'periodo', CASE 
            WHEN p_fecha_inicio IS NOT NULL AND p_fecha_fin IS NOT NULL THEN
                json_build_object(
                    'inicio', p_fecha_inicio,
                    'fin', p_fecha_fin
                )
            ELSE NULL
        END
    );

    RAISE NOTICE 'Función completada exitosamente: %', v_resultado;
    RETURN v_resultado;

EXCEPTION
    WHEN OTHERS THEN
        -- MANEJO SEGURO DE ERRORES CON LOGGING
        RAISE NOTICE 'ERROR GENERAL: % % - Debug: %', SQLSTATE, SQLERRM, v_debug_info;
        RETURN json_build_object(
            'success', false,
            'error', 'Error interno del servidor',
            'error_detail', SQLERRM,
            'error_code', SQLSTATE,
            'debug_info', v_debug_info,
            'total_count', 0,
            'recepciones_count', 0,
            'entregas_count', 0
        );
END;
$$;

-- ============================================================================
-- PERMISOS Y SEGURIDAD
-- ============================================================================

-- Revocar permisos públicos
REVOKE ALL ON FUNCTION fn_count_pending_operations_optimized FROM PUBLIC;

-- Otorgar permisos solo a roles específicos
GRANT EXECUTE ON FUNCTION fn_count_pending_operations_optimized TO authenticated;
GRANT EXECUTE ON FUNCTION fn_count_pending_operations_optimized TO service_role;

-- Crear índices para optimizar las consultas (si no existen)

CREATE INDEX IF NOT EXISTS idx_entrega_efectivo_fecha 
ON app_dat_entregas_parciales_caja(fecha_entrega);

CREATE INDEX IF NOT EXISTS idx_gastos_tipo_origen_referencia 
ON app_cont_gastos(tipo_origen, id_referencia_origen);

CREATE INDEX IF NOT EXISTS idx_egresos_procesados_egreso_estado 
ON app_cont_egresos_procesados(id_egreso, estado);

-- Comentarios para documentación
COMMENT ON FUNCTION fn_count_pending_operations_optimized IS 
'Función optimizada para contar operaciones pendientes de registro como gastos. Incluye validaciones de seguridad y logging detallado para debug.';