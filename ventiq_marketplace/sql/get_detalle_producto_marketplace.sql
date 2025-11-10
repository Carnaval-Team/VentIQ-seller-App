-- =====================================================
-- FUNCIÓN: get_detalle_producto_marketplace
-- Descripción: Obtiene detalles completos de un producto para el marketplace
-- Autor: VentIQ Development Team
-- Fecha: 2025-11-10
-- =====================================================

CREATE OR REPLACE FUNCTION get_detalle_producto_marketplace(
    id_producto_param bigint
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    resultado jsonb;
    producto_info jsonb;
    inventario_info jsonb;
BEGIN
    -- Obtener información del producto
    SELECT jsonb_build_object(
        'id', p.id,
        'denominacion', p.denominacion,
        'descripcion', p.descripcion,
        'foto', p.foto,
        'precio_actual', p.precio_venta,
        'es_refrigerado', p.es_refrigerado,
        'es_fragil', p.es_fragil,
        'es_peligroso', p.es_peligroso,
        'es_elaborado', p.es_elaborado,
        'es_servicio', p.es_servicio,
        'categoria', jsonb_build_object(
            'id', c.id,
            'denominacion', c.denominacion
        ),
        'multimedias', COALESCE(
            (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', m.id,
                        'url', m.url,
                        'tipo', m.tipo
                    )
                )
                FROM app_dat_multimedia m
                WHERE m.id_producto = p.id
            ),
            '[]'::jsonb
        )
    )
    INTO producto_info
    FROM app_dat_producto p
    LEFT JOIN app_nom_categoria c ON p.id_categoria = c.id
    WHERE p.id = id_producto_param;

    -- Verificar que el producto existe
    IF producto_info IS NULL THEN
        RAISE EXCEPTION 'Producto con ID % no encontrado', id_producto_param;
    END IF;

    -- Obtener inventario con variantes y presentaciones
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id_inventario', inv.id,
                'sku_producto', inv.sku_producto,
                'cantidad_disponible', inv.cantidad_final,
                'precio', inv.precio,
                'variante', CASE 
                    WHEN pv.id IS NOT NULL THEN
                        jsonb_build_object(
                            'id', pv.id,
                            'precio', pv.precio,
                            'atributo', jsonb_build_object(
                                'id', a.id,
                                'label', a.label,
                                'tipo', a.tipo
                            ),
                            'opcion', jsonb_build_object(
                                'id', ov.id,
                                'valor', ov.valor,
                                'precio_adicional', ov.precio_adicional
                            )
                        )
                    ELSE NULL
                END,
                'presentacion', CASE
                    WHEN pp.id IS NOT NULL THEN
                        jsonb_build_object(
                            'id', pp.id,
                            'id_presentacion', pp.id_presentacion,
                            'denominacion', pres.denominacion,
                            'descripcion', pres.descripcion,
                            'cantidad', pp.cantidad,
                            'es_base', pp.es_base,
                            'precio', pp.precio
                        )
                    ELSE NULL
                END,
                'ubicacion', jsonb_build_object(
                    'id', u.id,
                    'denominacion', u.denominacion,
                    'sku_codigo', u.sku_codigo,
                    'almacen', jsonb_build_object(
                        'id', alm.id,
                        'denominacion', alm.denominacion
                    )
                )
            )
        ),
        '[]'::jsonb
    )
    INTO inventario_info
    FROM app_dat_inventario_productos inv
    LEFT JOIN app_dat_producto_variante pv ON inv.id_variante = pv.id
    LEFT JOIN app_nom_atributo a ON pv.id_atributo = a.id
    LEFT JOIN app_nom_opcion_variante ov ON pv.id_opcion = ov.id
    LEFT JOIN app_dat_producto_presentacion pp ON inv.id_presentacion = pp.id
    LEFT JOIN app_nom_presentacion pres ON pp.id_presentacion = pres.id
    LEFT JOIN app_dat_ubicacion u ON inv.id_ubicacion = u.id
    LEFT JOIN app_dat_almacen alm ON u.id_almacen = alm.id
    WHERE inv.id_producto = id_producto_param
      AND inv.cantidad_final > 0  -- Solo productos con stock
    ORDER BY 
        pp.es_base DESC NULLS LAST,  -- Presentaciones base primero
        pres.denominacion ASC NULLS LAST,
        pv.id ASC NULLS LAST;

    -- Construir resultado final
    resultado := jsonb_build_object(
        'producto', producto_info,
        'inventario', inventario_info
    );

    RETURN resultado;
END;
$$;

-- =====================================================
-- Comentarios de la función
-- =====================================================
COMMENT ON FUNCTION get_detalle_producto_marketplace(bigint) IS 
'Obtiene los detalles completos de un producto para el marketplace.
Retorna información del producto junto con su inventario, variantes y presentaciones.
Solo incluye items con stock disponible (cantidad_final > 0).';

-- =====================================================
-- Ejemplos de uso
-- =====================================================

-- Obtener detalles de un producto
-- SELECT get_detalle_producto_marketplace(1);

-- Ver la estructura del resultado
-- SELECT jsonb_pretty(get_detalle_producto_marketplace(1));
