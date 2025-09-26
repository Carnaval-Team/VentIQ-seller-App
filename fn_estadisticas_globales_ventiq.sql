-- Función para obtener estadísticas globales de VentIQ
-- Devuelve: total de tiendas creadas, total de ventas, y tiempo promedio activo

CREATE OR REPLACE FUNCTION fn_estadisticas_globales_ventiq()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    total_tiendas bigint;
    total_ventas numeric;
    tiempo_activo_promedio interval;
    tiempo_activo_dias numeric;
    resultado jsonb;
BEGIN
    -- 1. Contar total de tiendas creadas
    SELECT COUNT(*) 
    INTO total_tiendas
    FROM app_dat_tienda;
    
    -- 2. Calcular total de ventas (suma de todos los importes de ventas)
    SELECT COALESCE(SUM(ov.importe_total), 0)
    INTO total_ventas
    FROM app_dat_operacion_venta ov
    WHERE ov.es_pagada = true;
    
    -- 3. Calcular tiempo activo promedio (desde la creación de la primera tienda hasta ahora)
    SELECT 
        CASE 
            WHEN COUNT(*) > 0 THEN 
                (EXTRACT(EPOCH FROM (NOW() - MIN(created_at))) / 86400)::numeric
            ELSE 0 
        END
    INTO tiempo_activo_dias
    FROM app_dat_tienda;
    
    -- Convertir días a interval para mejor legibilidad
    tiempo_activo_promedio := MAKE_INTERVAL(days => tiempo_activo_dias::integer);
    
    -- Construir respuesta JSON
    resultado := jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'total_tiendas_creadas', total_tiendas,
            'total_ventas', total_ventas,
            'tiempo_activo_dias', tiempo_activo_dias,
            'tiempo_activo_promedio', tiempo_activo_promedio::text,
            'fecha_primera_tienda', (
                SELECT MIN(created_at)::date 
                FROM app_dat_tienda
            ),
            'fecha_consulta', NOW()::date
        ),
        'message', 'Estadísticas globales obtenidas exitosamente'
    );
    
    RETURN resultado;
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', SQLERRM,
            'error_code', SQLSTATE,
            'message', 'Error al obtener estadísticas globales'
        );
END;
$$;

-- Comentarios sobre la función:
-- 
-- TOTAL DE TIENDAS CREADAS:
-- - Cuenta todas las filas en app_dat_tienda
-- - Incluye tiendas activas e inactivas
--
-- TOTAL DE VENTAS:
-- - Suma todos los importes de app_dat_operacion_venta
-- - Solo incluye ventas pagadas (es_pagada = true)
-- - Usa COALESCE para manejar casos sin ventas
--
-- TIEMPO ACTIVO:
-- - Calcula días desde la primera tienda creada hasta ahora
-- - Proporciona tanto días numéricos como interval legible
-- - Incluye fecha de la primera tienda para referencia
--
-- EJEMPLO DE USO:
-- SELECT * FROM fn_estadisticas_globales_ventiq();
--
-- EJEMPLO DE RESPUESTA:
-- {
--   "data": {
--     "total_tiendas_creadas": 25,
--     "total_ventas": 150000.50,
--     "tiempo_activo_dias": 365.5,
--     "tiempo_activo_promedio": "365 days 12:00:00",
--     "fecha_primera_tienda": "2023-01-15",
--     "fecha_consulta": "2024-01-15"
--   },
--   "success": true,
--   "message": "Estadísticas globales obtenidas exitosamente"
-- }
