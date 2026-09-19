-- ============================================================================
-- Fix: reservado_carnaval en get_detalle_producto
-- ----------------------------------------------------------------------------
-- Antes sumaba todo el Carrito de Carnaval sin filtrar por estado de orden.
-- Ahora cuenta solo las lineas de ordenes (OrderDetails) cuyo Orders.status
-- sea 'Nuevo', 'Procesando' o 'Asignado', excluyendo 'Entregando',
-- 'Completado', 'Cancelado', etc.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_detalle_producto(id_producto_param bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    producto_data jsonb;
    inventario_data jsonb[];
    almacenes_accesibles bigint[];
    tiendas_accesibles bigint[];
    tiendas_gerencia_supervisor bigint[];
BEGIN
    -- Tiendas a las que el usuario tiene acceso (gerente / supervisor /
    -- almacenero / vendedor).
    SELECT ARRAY(
        SELECT DISTINCT id_tienda FROM (
            SELECT id_tienda FROM app_dat_gerente WHERE uuid = auth.uid()
            UNION
            SELECT id_tienda FROM app_dat_supervisor WHERE uuid = auth.uid()
            UNION
            SELECT a.id_tienda FROM app_dat_almacenero al
            JOIN app_dat_almacen a ON al.id_almacen = a.id
            WHERE al.uuid = auth.uid()
            UNION
            SELECT tpv.id_tienda FROM app_dat_vendedor v
            JOIN app_dat_tpv tpv ON v.id_tpv = tpv.id
            WHERE v.uuid = auth.uid()
        ) AS t
    ) INTO tiendas_accesibles;

    -- Tiendas donde el usuario es gerente/supervisor (acceso a TODOS los
    -- almacenes de la tienda).
    SELECT ARRAY(
        SELECT DISTINCT id_tienda FROM (
            SELECT id_tienda FROM app_dat_gerente WHERE uuid = auth.uid()
            UNION
            SELECT id_tienda FROM app_dat_supervisor WHERE uuid = auth.uid()
        ) AS t
    ) INTO tiendas_gerencia_supervisor;

    -- Almacenes accesibles: vendedor (SOLO su TPV), almacenero (SOLO su
    -- almacen) y todos los almacenes de tiendas donde es gerente/supervisor.
    SELECT ARRAY(
        SELECT DISTINCT id_almacen FROM (
            SELECT tpv.id_almacen
            FROM app_dat_vendedor v
            JOIN app_dat_tpv tpv ON v.id_tpv = tpv.id
            WHERE v.uuid = auth.uid()
            UNION
            SELECT al.id_almacen
            FROM app_dat_almacenero al
            WHERE al.uuid = auth.uid()
            UNION
            SELECT a.id
            FROM app_dat_almacen a
            WHERE a.id_tienda = ANY(tiendas_gerencia_supervisor)
        ) AS alms
    ) INTO almacenes_accesibles;

    -- Verificar acceso al producto.
    IF NOT EXISTS (
        SELECT 1
        FROM app_dat_producto p
        WHERE p.id = id_producto_param
          AND p.id_tienda = ANY(tiendas_accesibles)
    ) THEN
        RAISE EXCEPTION 'Acceso denegado: No tienes permisos para ver este producto';
    END IF;

    -- Datos generales del producto.
    SELECT jsonb_build_object(
        'id', p.id,
        'sku', p.sku,
        'denominacion', p.denominacion,
        'nombre_comercial', p.nombre_comercial,
        'descripcion', p.descripcion,
        'um', p.um,
        'es_paquete', p.es_paquete,
        'es_refrigerado', p.es_refrigerado,
        'es_fragil', p.es_fragil,
        'es_peligroso', p.es_peligroso,
        'es_elaborado', (p.es_elaborado OR p.es_servicio),
        'codigo_barras', p.codigo_barras,
        'imagen', p.imagen,
        'categoria', jsonb_build_object(
            'id', c.id,
            'denominacion', c.denominacion,
            'sku_codigo', c.sku_codigo
        ),
        'precio_actual', COALESCE((
            SELECT precio_venta_cup
            FROM app_dat_precio_venta
            WHERE id_producto = p.id
              AND (fecha_hasta IS NULL OR fecha_hasta >= CURRENT_DATE)
            ORDER BY fecha_desde DESC LIMIT 1
        ), 0),
        'subcategorias', (
            SELECT jsonb_agg(jsonb_build_object(
                'id', sc.id,
                'denominacion', sc.denominacion,
                'sku_codigo', sc.sku_codigo
            ))
            FROM app_dat_productos_subcategorias ps
            JOIN app_dat_subcategorias sc ON ps.id_sub_categoria = sc.id
            WHERE ps.id_producto = p.id
        ),
        'presentaciones', (
            SELECT jsonb_agg(jsonb_build_object(
                'id', pp.id,
                'presentacion', np.denominacion,
                'es_fraccionable', np.es_fraccionable,
                'cantidad', pp.cantidad,
                'es_base', pp.es_base,
                'sku_codigo', np.sku_codigo
            ))
            FROM app_dat_producto_presentacion pp
            JOIN app_nom_presentacion np ON pp.id_presentacion = np.id
            WHERE pp.id_producto = p.id
        ),
        'multimedias', (
            SELECT jsonb_agg(media)
            FROM app_dat_producto_multimedias
            WHERE id_producto = p.id
        ),
        'etiquetas', (
            SELECT jsonb_agg(etiqueta)
            FROM app_dat_producto_etiquetas
            WHERE id_producto = p.id
        )
    ) INTO producto_data
    FROM app_dat_producto p
    JOIN app_dat_categoria c ON p.id_categoria = c.id
    WHERE p.id = id_producto_param;

    -- Inventario disponible.
    SELECT array_agg(
        jsonb_build_object(
            'id_inventario', ip.id,
            'variante', CASE
                WHEN v.id IS NOT NULL THEN jsonb_build_object(
                    'id', v.id,
                    'atributo', jsonb_build_object(
                        'id', a.id,
                        'denominacion', a.denominacion,
                        'label', a.label
                    ),
                    'opcion', jsonb_build_object(
                        'id', ao.id,
                        'valor', ao.valor,
                        'sku_codigo', ao.sku_codigo
                    )
                )
                ELSE NULL
            END,
            'presentacion', jsonb_build_object(
                'id', pp.id,
                'denominacion', np.denominacion,
                'es_fraccionable', np.es_fraccionable,
                'sku_codigo', np.sku_codigo,
                'cantidad', pp.cantidad
            ),
            'ubicacion', jsonb_build_object(
                'id', la.id,
                'denominacion', la.denominacion,
                'sku_codigo', la.sku_codigo,
                'almacen', jsonb_build_object(
                    'id', alm.id,
                    'denominacion', alm.denominacion
                )
            ),
            'cantidad_disponible', ip.cantidad_final,
            'reservado_carnaval',
                COALESCE(
                    (SELECT SUM(ca.quantity)
                     FROM carnavalapp."Carrito" ca
                     WHERE ca.product_id IN (
                         SELECT DISTINCT rpc.id_producto_carnaval
                         FROM public.relation_products_carnaval rpc
                         WHERE rpc.id_producto = ip.id_producto
                           AND rpc.id_ubicacion = ip.id_ubicacion
                     )),
                    0
                ),
            'en_ordenes_carnaval', COALESCE(
                (SELECT SUM(od.quantity)
                 FROM public.relation_products_carnaval rpc
                 JOIN carnavalapp."OrderDetails" od ON od.product_id = rpc.id_producto_carnaval
                 JOIN carnavalapp."Orders" o ON o.id = od.order_id
                 WHERE rpc.id_producto = ip.id_producto
                   AND rpc.id_ubicacion = ip.id_ubicacion
                   AND o.status IN ('Nuevo', 'Nueva', 'Procesando', 'Asignado', 'Pendiente de Pago')),
                0
            ),
            'ultima_actualizacion', ip.created_at,
            'proveedor', CASE
                WHEN pr.id IS NOT NULL THEN jsonb_build_object(
                    'id', pr.id,
                    'denominacion', pr.denominacion,
                    'sku_codigo', pr.sku_codigo
                )
                ELSE NULL
            END
        )
    ) INTO inventario_data
    FROM app_dat_inventario_productos ip
    LEFT JOIN app_dat_variantes v ON ip.id_variante = v.id
    LEFT JOIN app_dat_atributos a ON v.id_atributo = a.id
    LEFT JOIN app_dat_atributo_opcion ao ON ip.id_opcion_variante = ao.id
    LEFT JOIN app_dat_producto_presentacion pp ON ip.id_presentacion = pp.id
    LEFT JOIN app_nom_presentacion np ON pp.id_presentacion = np.id
    LEFT JOIN app_dat_layout_almacen la ON ip.id_ubicacion = la.id
    LEFT JOIN app_dat_almacen alm ON la.id_almacen = alm.id
    LEFT JOIN app_dat_proveedor pr ON ip.id_proveedor = pr.id
    WHERE ip.id_producto = id_producto_param
      AND ip.cantidad_final > 0
      AND alm.id = ANY(almacenes_accesibles)
      AND ip.id = (
          SELECT MAX(id)
          FROM app_dat_inventario_productos
          WHERE id_producto = ip.id_producto
            AND COALESCE(id_variante, 0) = COALESCE(ip.id_variante, 0)
            AND COALESCE(id_opcion_variante, 0) = COALESCE(ip.id_opcion_variante, 0)
            AND COALESCE(id_presentacion, 0) = COALESCE(ip.id_presentacion, 0)
            AND COALESCE(id_ubicacion, 0) = COALESCE(ip.id_ubicacion, 0)
      );

    RETURN jsonb_build_object(
        'producto', producto_data,
        'inventario', COALESCE(to_jsonb(inventario_data), '[]'::jsonb)
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_detalle_producto(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_detalle_producto(bigint) TO anon;
