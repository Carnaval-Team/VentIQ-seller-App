-- Report: Stock comparison between InventTIA and CarnavalApp
-- Shows all linked products with their stock in both systems

SELECT
  p.id AS id_producto,
  p.id_vendedor_app AS id_producto_carnaval,
  p.denominacion AS nombre_producto,
  COALESCE(cp.stock, 0) AS stock_carnaval,
  COALESCE(inv.cantidad_final, 0)::bigint AS stock_inventtia,
  COALESCE(inv.cantidad_final, 0)::bigint - COALESCE(cp.stock, 0) AS diferencia,
  inv.created_at AS ultima_fecha_inventario
FROM public.app_dat_producto p
JOIN public.relation_products_carnaval rpc
  ON rpc.id_producto = p.id
  AND rpc.id_producto_carnaval = p.id_vendedor_app
LEFT JOIN LATERAL (
  SELECT ip.cantidad_final, ip.created_at
  FROM public.app_dat_inventario_productos ip
  WHERE ip.id_producto = p.id
    AND ip.id_ubicacion = rpc.id_ubicacion
  ORDER BY ip.id DESC
  LIMIT 1
) inv ON true
LEFT JOIN carnavalapp."Productos" cp
  ON cp.id = p.id_vendedor_app
WHERE p.id_vendedor_app IS NOT NULL
  AND p.deleted_at IS NULL
ORDER BY ABS(COALESCE(inv.cantidad_final, 0)::bigint - COALESCE(cp.stock, 0)) DESC;
