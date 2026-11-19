CREATE OR REPLACE FUNCTION public.fn_stock_producto_almacen_detalle(p_id_producto bigint, p_id_almacen bigint DEFAULT NULL::bigint)
 RETURNS TABLE(id_ubicacion bigint, id_almacen bigint, id_variante bigint, id_opcion_variante bigint, id_presentacion bigint, cantidad_final numeric, sku_producto character varying, sku_ubicacion character varying)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT
        v.id_ubicacion,
        v.id_almacen,
        v.id_variante,
        v.id_opcion_variante,
        v.id_presentacion,
        v.cantidad_final,
        v.sku_producto,
        v.sku_ubicacion
    FROM (
        SELECT DISTINCT ON (
                   ip.id_ubicacion,
                   COALESCE(ip.id_variante, 0),
                   COALESCE(ip.id_opcion_variante, 0),
                   COALESCE(ip.id_presentacion, 0)
               )
               ip.id_ubicacion,
               la.id_almacen,
               ip.id_variante,
               ip.id_opcion_variante,
               ip.id_presentacion,
               ip.cantidad_final,
               ip.sku_producto,
               ip.sku_ubicacion
          FROM public.app_dat_inventario_productos ip
          JOIN public.app_dat_layout_almacen la ON la.id = ip.id_ubicacion
         WHERE ip.id_producto = p_id_producto
           AND la.deleted_at IS NULL
           AND (p_id_almacen IS NULL OR la.id_almacen = p_id_almacen)
         ORDER BY
               ip.id_ubicacion,
               COALESCE(ip.id_variante, 0),
               COALESCE(ip.id_opcion_variante, 0),
               COALESCE(ip.id_presentacion, 0),
               ip.id DESC
    ) v
    WHERE COALESCE(v.cantidad_final, 0) > 0
    ORDER BY v.cantidad_final DESC, v.id_ubicacion;
$function$

