-- Función para calcular la disponibilidad de productos elaborados basada en sus ingredientes
-- Parámetros:
--   p_id_tienda: ID de la tienda
--   p_id_producto: ID del producto elaborado específico (opcional, NULL para todos)

CREATE OR REPLACE FUNCTION fn_calcular_disponibilidad_productos_elaborados(
    p_id_tienda BIGINT,
    p_id_producto BIGINT DEFAULT NULL
)
RETURNS TABLE (
    id_producto_elaborado BIGINT,
    nombre_producto_elaborado VARCHAR,
    sku_producto_elaborado VARCHAR,
    es_elaborado BOOLEAN,
    cantidad_maxima_elaborable NUMERIC,
    detalle_ingredientes JSONB
) 
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH productos_elaborados AS (
        -- Obtener todos los productos elaborados de la tienda
        SELECT 
            p.id,
            p.denominacion,
            p.sku,
            p.es_elaborado
        FROM app_dat_producto p
        WHERE p.id_tienda = p_id_tienda
          AND p.es_elaborado = true
          AND p.deleted_at IS NULL
          AND (p_id_producto IS NULL OR p.id = p_id_producto)
    ),
    inventario_actual AS (
        -- Obtener el inventario actual de todos los productos en la tienda
        SELECT 
            ip.id_producto,
            ip.id_variante,
            ip.id_opcion_variante,
            ip.id_presentacion,
            ip.id_ubicacion,
            COALESCE(ip.cantidad_final, 0) as stock_disponible,
            p.denominacion as nombre_producto,
            p.sku as sku_producto,
            pp.cantidad as factor_presentacion,
            la.denominacion as ubicacion
        FROM app_dat_inventario_productos ip
        INNER JOIN app_dat_producto p ON ip.id_producto = p.id
        LEFT JOIN app_dat_producto_presentacion pp ON ip.id_presentacion = pp.id
        LEFT JOIN app_dat_layout_almacen la ON ip.id_ubicacion = la.id
        LEFT JOIN app_dat_almacen a ON la.id_almacen = a.id
        WHERE a.id_tienda = p_id_tienda
          AND COALESCE(ip.cantidad_final, 0) > 0
    ),
    stock_consolidado AS (
        -- Consolidar el stock por producto (sumando todas las ubicaciones y presentaciones)
        SELECT 
            ia.id_producto,
            ia.nombre_producto,
            ia.sku_producto,
            SUM(ia.stock_disponible * COALESCE(ia.factor_presentacion, 1)) as stock_total_disponible,
            JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'ubicacion', ia.ubicacion,
                    'stock_ubicacion', ia.stock_disponible,
                    'factor_presentacion', COALESCE(ia.factor_presentacion, 1),
                    'stock_convertido', ia.stock_disponible * COALESCE(ia.factor_presentacion, 1)
                )
            ) as detalle_ubicaciones
        FROM inventario_actual ia
        GROUP BY ia.id_producto, ia.nombre_producto, ia.sku_producto
    ),
    calculo_disponibilidad AS (
        -- Calcular cuántas unidades se pueden elaborar de cada producto
        SELECT 
            pe.id as id_producto_elaborado,
            pe.denominacion as nombre_producto_elaborado,
            pe.sku as sku_producto_elaborado,
            pe.es_elaborado,
            -- Calcular la cantidad máxima que se puede elaborar
            CASE 
                WHEN COUNT(pi.id_ingrediente) = 0 THEN 0 -- No tiene ingredientes definidos
                ELSE COALESCE(MIN(
                    FLOOR(sc.stock_total_disponible / pi.cantidad_necesaria)
                ), 0)
            END as cantidad_maxima_elaborable,
            -- Detalle de cada ingrediente
            JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'id_ingrediente', pi.id_ingrediente,
                    'nombre_ingrediente', sc.nombre_producto,
                    'sku_ingrediente', sc.sku_producto,
                    'cantidad_necesaria', pi.cantidad_necesaria,
                    'unidad_medida', pi.unidad_medida,
                    'stock_disponible', COALESCE(sc.stock_total_disponible, 0),
                    'cantidad_suficiente', COALESCE(sc.stock_total_disponible, 0) >= pi.cantidad_necesaria,
                    'unidades_posibles', CASE 
                        WHEN COALESCE(sc.stock_total_disponible, 0) = 0 OR pi.cantidad_necesaria = 0 
                        THEN 0 
                        ELSE FLOOR(COALESCE(sc.stock_total_disponible, 0) / pi.cantidad_necesaria)
                    END,
                    'detalle_ubicaciones', sc.detalle_ubicaciones,
                    'costo_unitario', pi.costo_unitario
                )
            ) FILTER (WHERE pi.id_ingrediente IS NOT NULL) as detalle_ingredientes
        FROM productos_elaborados pe
        LEFT JOIN app_dat_producto_ingredientes pi ON pe.id = pi.id_producto_elaborado
        LEFT JOIN stock_consolidado sc ON pi.id_ingrediente = sc.id_producto
        GROUP BY pe.id, pe.denominacion, pe.sku, pe.es_elaborado
    )
    SELECT 
        cd.id_producto_elaborado,
        cd.nombre_producto_elaborado,
        cd.sku_producto_elaborado,
        cd.es_elaborado,
        cd.cantidad_maxima_elaborable,
        COALESCE(cd.detalle_ingredientes, '[]'::jsonb) as detalle_ingredientes
    FROM calculo_disponibilidad cd
    ORDER BY cd.nombre_producto_elaborado;
END;
$$;

-- Comentarios sobre el uso:
-- 
-- Ejemplo 1: Obtener disponibilidad de todos los productos elaborados de la tienda 1
-- SELECT * FROM fn_calcular_disponibilidad_productos_elaborados(1);
--
-- Ejemplo 2: Obtener disponibilidad de un producto elaborado específico (ID 123) de la tienda 1  
-- SELECT * FROM fn_calcular_disponibilidad_productos_elaborados(1, 123);
--
-- La función retorna:
-- - id_producto_elaborado: ID del producto elaborado
-- - nombre_producto_elaborado: Nombre del producto elaborado
-- - sku_producto_elaborado: SKU del producto elaborado
-- - es_elaborado: Confirmación de que es un producto elaborado
-- - cantidad_maxima_elaborable: Máxima cantidad que se puede elaborar con el stock actual
-- - detalle_ingredientes: JSON con el detalle de cada ingrediente incluyendo:
--   * Información del ingrediente (ID, nombre, SKU)
--   * Cantidad necesaria y unidad de medida
--   * Stock disponible actual
--   * Si la cantidad es suficiente
--   * Cuántas unidades se pueden hacer con ese ingrediente
--   * Detalle por ubicaciones del stock
--   * Costo unitario del ingrediente
