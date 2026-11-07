WITH precios(id, id_producto, id_variante, precio_venta_cup, fecha_desde, fecha_hasta) AS (
    VALUES
        (1::bigint, 10::bigint, NULL::bigint, 100::numeric, CURRENT_DATE - 10, NULL::date),
        (2, 10, NULL, 120, CURRENT_DATE - 5, NULL),
        (3, 10, NULL, 900, CURRENT_DATE + 1, NULL),
        (4, 10, NULL, 800, CURRENT_DATE - 10, CURRENT_DATE - 1),
        (5, 10, 7, 80, CURRENT_DATE - 3, NULL),
        (6, 10, 8, 700, CURRENT_DATE + 1, NULL),
        (20, 10, 0, 180, CURRENT_DATE - 8, NULL),
        (21, 11, NULL, 500, CURRENT_DATE + 1, NULL),
        (30, 13, NULL, 300, CURRENT_DATE - 2, CURRENT_DATE),
        (40, 14, NULL, 400, CURRENT_DATE, NULL),
        (50, 15, 9, 500, CURRENT_DATE, NULL)
), vigentes AS (
    SELECT DISTINCT ON (id_producto, COALESCE(id_variante, 0)) *
    FROM precios
    WHERE fecha_desde <= CURRENT_DATE
      AND (fecha_hasta IS NULL OR fecha_hasta >= CURRENT_DATE)
    ORDER BY id_producto, COALESCE(id_variante, 0), id DESC
), casos(nombre, producto, variante, esperado) AS (
    VALUES
        ('base NULL y cero comparten última versión', 10::bigint, NULL::bigint, 20::bigint),
        ('variante cero solicita precio base', 10, 0, 20),
        ('variante específica prevalece sobre base con ID mayor', 10, 7, 5),
        ('variante futura usa base vigente', 10, 8, 20),
        ('variante sin precio usa base vigente', 10, 99, 20),
        ('producto con solo precio futuro no tiene precio vigente', 11, NULL, NULL),
        ('producto sin precio no toma el de otro producto', 12, NULL, NULL),
        ('fecha de fin incluye el día actual', 13, NULL, 30),
        ('fecha de inicio incluye el día actual', 14, NULL, 40),
        ('precio de variante no se filtra al precio base', 15, NULL, NULL),
        ('producto sin base mantiene precio específico', 15, 9, 50)
)
SELECT c.nombre, c.esperado, elegido.id AS obtenido,
       elegido.id IS NOT DISTINCT FROM c.esperado AS correcto
FROM casos c
LEFT JOIN LATERAL (
    SELECT v.id FROM vigentes v
    WHERE v.id_producto = c.producto
      AND (COALESCE(v.id_variante, 0) = 0
           OR v.id_variante = NULLIF(c.variante, 0))
    ORDER BY (COALESCE(v.id_variante, 0) <> 0) DESC, v.id DESC
    LIMIT 1
) elegido ON true;

SELECT p.id, p.denominacion, v.id AS precio_id,
       v.precio_venta_cup, v.precio_venta_usd
FROM public.app_dat_producto p
LEFT JOIN public.app_v_precio_venta_base_vigente v ON v.id_producto = p.id
WHERE p.id_tienda = 4 AND p.deleted_at IS NULL
ORDER BY p.id;

SELECT p.proname,
       position('app_v_precio_venta_' IN pg_get_functiondef(p.oid)) > 0 AS usa_fuente_vigente
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname IN (
    'get_detalle_producto', 'get_detalles_productos_batch',
    'get_productos_by_categoria_tpv_search_meta_v3',
    'get_productos_completos_by_tienda_optimized_v2',
    'rpc_get_products_last_price2', 'get_precios_productos_tienda',
    'fn_productos_cocina_tpv', 'fn_reporte_ventas_con_proveedor_precios_actuales',
    'rpc_apply_global_price_change', 'rpc_apply_selected_price_change'
)
ORDER BY p.proname;
