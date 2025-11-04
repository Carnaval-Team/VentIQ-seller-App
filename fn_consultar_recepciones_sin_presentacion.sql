-- Función para consultar recepciones que no tienen presentación asignada
-- Solo consulta, no actualiza. Útil para revisar antes de ejecutar la actualización

CREATE OR REPLACE FUNCTION fn_consultar_recepciones_sin_presentacion(
    p_id_tienda BIGINT,
    p_id_producto BIGINT DEFAULT NULL -- Opcional: filtrar por producto específico
)
RETURNS TABLE (
    id_recepcion BIGINT,
    id_operacion BIGINT,
    fecha_recepcion TIMESTAMP WITH TIME ZONE,
    id_producto BIGINT,
    nombre_producto VARCHAR,
    sku_producto VARCHAR,
    cantidad_recibida NUMERIC,
    precio_unitario NUMERIC,
    presentacion_actual BIGINT,
    primera_presentacion_disponible BIGINT,
    nombre_primera_presentacion VARCHAR,
    es_presentacion_base BOOLEAN,
    tiene_presentaciones_disponibles BOOLEAN
) 
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY 
    SELECT 
        rp.id as id_recepcion,
        rp.id_operacion,
        o.created_at as fecha_recepcion,
        p.id as id_producto,
        p.denominacion as nombre_producto,
        p.sku as sku_producto,
        rp.cantidad as cantidad_recibida,
        rp.precio_unitario,
        rp.id_presentacion as presentacion_actual,
        pp_primera.id as primera_presentacion_disponible,
        np.denominacion as nombre_primera_presentacion,
        pp_primera.es_base as es_presentacion_base,
        CASE 
            WHEN pp_primera.id IS NOT NULL THEN true 
            ELSE false 
        END as tiene_presentaciones_disponibles
    FROM app_dat_recepcion_productos rp
    INNER JOIN app_dat_operaciones o ON rp.id_operacion = o.id
    INNER JOIN app_dat_producto p ON rp.id_producto = p.id
    LEFT JOIN LATERAL (
        SELECT pp.id, pp.id_presentacion, pp.es_base
        FROM app_dat_producto_presentacion pp
        WHERE pp.id_producto = p.id
        ORDER BY pp.es_base DESC, pp.id ASC
        LIMIT 1
    ) pp_primera ON true
    LEFT JOIN app_nom_presentacion np ON pp_primera.id_presentacion = np.id
    WHERE o.id_tienda = p_id_tienda
      AND p.deleted_at IS NULL
      AND p.es_comprable = true
      AND rp.id_presentacion IS NULL -- Solo recepciones sin presentación
      AND (p_id_producto IS NULL OR p.id = p_id_producto) -- Filtro opcional por producto
    ORDER BY 
        o.created_at DESC,
        p.denominacion,
        rp.id;
END;
$$;

-- Función adicional para obtener estadísticas de recepciones sin presentación
CREATE OR REPLACE FUNCTION fn_estadisticas_recepciones_sin_presentacion(
    p_id_tienda BIGINT
)
RETURNS TABLE (
    total_recepciones_sin_presentacion BIGINT,
    total_productos_afectados BIGINT,
    productos_con_presentaciones_disponibles BIGINT,
    productos_sin_presentaciones_disponibles BIGINT,
    valor_total_recepciones_afectadas NUMERIC
) 
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY 
    WITH recepciones_sin_presentacion AS (
        SELECT 
            rp.id,
            rp.id_producto,
            rp.cantidad,
            rp.precio_unitario,
            CASE 
                WHEN pp_primera.id IS NOT NULL THEN true 
                ELSE false 
            END as tiene_presentacion_disponible
        FROM app_dat_recepcion_productos rp
        INNER JOIN app_dat_operaciones o ON rp.id_operacion = o.id
        INNER JOIN app_dat_producto p ON rp.id_producto = p.id
        LEFT JOIN LATERAL (
            SELECT pp.id
            FROM app_dat_producto_presentacion pp
            WHERE pp.id_producto = p.id
            LIMIT 1
        ) pp_primera ON true
        WHERE o.id_tienda = p_id_tienda
          AND p.deleted_at IS NULL
          AND p.es_comprable = true
          AND rp.id_presentacion IS NULL
    )
    SELECT 
        COUNT(*)::BIGINT as total_recepciones_sin_presentacion,
        COUNT(DISTINCT id_producto)::BIGINT as total_productos_afectados,
        COUNT(DISTINCT CASE WHEN tiene_presentacion_disponible THEN id_producto END)::BIGINT as productos_con_presentaciones_disponibles,
        COUNT(DISTINCT CASE WHEN NOT tiene_presentacion_disponible THEN id_producto END)::BIGINT as productos_sin_presentaciones_disponibles,
        COALESCE(SUM(cantidad * COALESCE(precio_unitario, 0)), 0) as valor_total_recepciones_afectadas
    FROM recepciones_sin_presentacion;
END;
$$;

-- Comentarios sobre las funciones:

-- fn_consultar_recepciones_sin_presentacion:
-- 1. Muestra todas las recepciones que no tienen presentación asignada
-- 2. Incluye información sobre qué presentación se asignaría si se ejecutara la actualización
-- 3. Permite filtrar por producto específico (opcional)
-- 4. Indica si el producto tiene presentaciones disponibles

-- fn_estadisticas_recepciones_sin_presentacion:
-- 1. Proporciona un resumen estadístico del problema
-- 2. Cuenta total de recepciones y productos afectados
-- 3. Distingue entre productos que tienen presentaciones disponibles y los que no
-- 4. Calcula el valor total de las recepciones afectadas

-- Ejemplos de uso:

-- Ver todas las recepciones sin presentación de la tienda 1:
-- SELECT * FROM fn_consultar_recepciones_sin_presentacion(1);

-- Ver recepciones sin presentación de un producto específico:
-- SELECT * FROM fn_consultar_recepciones_sin_presentacion(1, 123);

-- Ver solo recepciones que SÍ tienen presentaciones disponibles para asignar:
-- SELECT * FROM fn_consultar_recepciones_sin_presentacion(1) WHERE tiene_presentaciones_disponibles = true;

-- Ver estadísticas generales:
-- SELECT * FROM fn_estadisticas_recepciones_sin_presentacion(1);

-- Flujo recomendado:
-- 1. Ejecutar fn_estadisticas_recepciones_sin_presentacion para ver el panorama general
-- 2. Ejecutar fn_consultar_recepciones_sin_presentacion para revisar los detalles
-- 3. Ejecutar fn_actualizar_presentaciones_recepciones para realizar las actualizaciones
