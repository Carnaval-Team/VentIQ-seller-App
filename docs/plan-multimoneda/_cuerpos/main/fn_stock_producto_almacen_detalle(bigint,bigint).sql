CREATE OR REPLACE FUNCTION public.fn_stock_producto_almacen_detalle(p_id_producto bigint, p_id_almacen bigint DEFAULT NULL::bigint)
 RETURNS TABLE(id_ubicacion bigint, id_almacen bigint, id_variante bigint, id_opcion_variante bigint, id_presentacion bigint, cantidad_final numeric, sku_producto character varying, sku_ubicacion character varying)
 LANGUAGE sql
 STABLE
AS $function$
    -- Última fila (mayor id) por variante/opción/presentación/ubicación,
    -- recorriendo idx_inv_prod_combo de combinación en combinación.
    WITH RECURSIVE combos AS (
        (SELECT ip.id,
                COALESCE(ip.id_variante, 0)        AS v,
                COALESCE(ip.id_opcion_variante, 0) AS o,
                COALESCE(ip.id_presentacion, 0)    AS p,
                COALESCE(ip.id_ubicacion, 0)       AS u
           FROM public.app_dat_inventario_productos ip
          WHERE ip.id_producto = p_id_producto
          ORDER BY ip.id_producto,
                   COALESCE(ip.id_variante, 0),
                   COALESCE(ip.id_opcion_variante, 0),
                   COALESCE(ip.id_presentacion, 0),
                   COALESCE(ip.id_ubicacion, 0),
                   ip.id DESC
          LIMIT 1)
        UNION ALL
        SELECT n.id, n.v, n.o, n.p, n.u
          FROM combos c
          CROSS JOIN LATERAL (
              SELECT ip.id,
                     COALESCE(ip.id_variante, 0)        AS v,
                     COALESCE(ip.id_opcion_variante, 0) AS o,
                     COALESCE(ip.id_presentacion, 0)    AS p,
                     COALESCE(ip.id_ubicacion, 0)       AS u
                FROM public.app_dat_inventario_productos ip
               WHERE ip.id_producto = p_id_producto
                 AND (COALESCE(ip.id_variante, 0),
                      COALESCE(ip.id_opcion_variante, 0),
                      COALESCE(ip.id_presentacion, 0),
                      COALESCE(ip.id_ubicacion, 0)) > (c.v, c.o, c.p, c.u)
               ORDER BY ip.id_producto,
                        COALESCE(ip.id_variante, 0),
                        COALESCE(ip.id_opcion_variante, 0),
                        COALESCE(ip.id_presentacion, 0),
                        COALESCE(ip.id_ubicacion, 0),
                        ip.id DESC
               LIMIT 1
          ) n
    )
    SELECT ip.id_ubicacion,
           la.id_almacen,
           ip.id_variante,
           ip.id_opcion_variante,
           ip.id_presentacion,
           ip.cantidad_final,
           ip.sku_producto,
           ip.sku_ubicacion
      FROM combos c
      JOIN public.app_dat_inventario_productos ip ON ip.id = c.id
      JOIN public.app_dat_layout_almacen la      ON la.id = ip.id_ubicacion
     WHERE la.deleted_at IS NULL
       AND (p_id_almacen IS NULL OR la.id_almacen = p_id_almacen)
       AND COALESCE(ip.cantidad_final, 0) > 0
     ORDER BY ip.cantidad_final DESC, ip.id_ubicacion;
$function$

