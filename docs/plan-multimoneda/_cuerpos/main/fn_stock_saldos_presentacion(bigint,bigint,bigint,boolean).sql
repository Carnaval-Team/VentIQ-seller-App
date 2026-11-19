CREATE OR REPLACE FUNCTION public.fn_stock_saldos_presentacion(p_id_producto bigint, p_id_almacen bigint DEFAULT NULL::bigint, p_id_ubicacion bigint DEFAULT NULL::bigint, p_incluir_cero boolean DEFAULT false)
 RETURNS TABLE(id_ubicacion bigint, id_almacen bigint, id_variante bigint, id_opcion_variante bigint, id_presentacion bigint, presentacion_nombre character varying, sku_codigo character varying, factor_rel numeric, es_base boolean, nivel integer, saldo numeric, equivalente_base numeric, sku_producto character varying, sku_ubicacion character varying)
 LANGUAGE sql
 STABLE
AS $function$
    WITH RECURSIVE
    -- Usa idx_inv_prod_lote_producto (parcial): respuesta inmediata.
    hay_lotes AS (
        SELECT EXISTS (
            SELECT 1
              FROM public.app_dat_inventario_productos x
             WHERE x.id_producto = p_id_producto
               AND x.id_lote IS NOT NULL
        ) AS hay
    ),
    -- Sin lotes: última fila por combinación saltando por idx_inv_prod_combo.
    combos AS (
        (SELECT ip.id,
                COALESCE(ip.id_variante, 0)        AS v,
                COALESCE(ip.id_opcion_variante, 0) AS o,
                COALESCE(ip.id_presentacion, 0)    AS p,
                COALESCE(ip.id_ubicacion, 0)       AS u
           FROM public.app_dat_inventario_productos ip
          WHERE ip.id_producto = p_id_producto
            AND NOT (SELECT hay FROM hay_lotes)
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
    ),
    vigente_lote AS (
        SELECT ip.id_ubicacion,
               la.id_almacen,
               ip.id_variante,
               ip.id_opcion_variante,
               ip.id_presentacion,
               ip.id_lote,
               COALESCE(ip.cantidad_final, 0) AS saldo,
               ip.sku_producto,
               ip.sku_ubicacion
          FROM combos c
          JOIN public.app_dat_inventario_productos ip ON ip.id = c.id
          JOIN public.app_dat_layout_almacen la      ON la.id = ip.id_ubicacion
         WHERE la.deleted_at IS NULL
           AND (p_id_ubicacion IS NULL OR ip.id_ubicacion = p_id_ubicacion)
           AND (p_id_almacen   IS NULL OR la.id_almacen   = p_id_almacen)
        UNION ALL
        -- Con lotes: consulta original, sin cambios.
        SELECT o.*
          FROM (
              SELECT DISTINCT ON (
                         ip.id_ubicacion,
                         COALESCE(ip.id_variante, 0),
                         COALESCE(ip.id_opcion_variante, 0),
                         ip.id_presentacion,
                         COALESCE(ip.id_lote, 0)
                     )
                     ip.id_ubicacion,
                     la.id_almacen,
                     ip.id_variante,
                     ip.id_opcion_variante,
                     ip.id_presentacion,
                     ip.id_lote,
                     COALESCE(ip.cantidad_final, 0) AS saldo,
                     ip.sku_producto,
                     ip.sku_ubicacion
                FROM public.app_dat_inventario_productos ip
                JOIN public.app_dat_layout_almacen la ON la.id = ip.id_ubicacion
               WHERE ip.id_producto = p_id_producto
                 AND la.deleted_at IS NULL
                 AND (p_id_ubicacion IS NULL OR ip.id_ubicacion = p_id_ubicacion)
                 AND (p_id_almacen   IS NULL OR la.id_almacen   = p_id_almacen)
               ORDER BY
                     ip.id_ubicacion,
                     COALESCE(ip.id_variante, 0),
                     COALESCE(ip.id_opcion_variante, 0),
                     ip.id_presentacion,
                     COALESCE(ip.id_lote, 0),
                     ip.id DESC
          ) o
         WHERE (SELECT hay FROM hay_lotes)
    ),
    vigente AS (
        SELECT
               v.id_ubicacion,
               v.id_almacen,
               v.id_variante,
               v.id_opcion_variante,
               v.id_presentacion,
               SUM(v.saldo) AS saldo,
               MIN(v.sku_producto) AS sku_producto,
               MIN(v.sku_ubicacion) AS sku_ubicacion
          FROM vigente_lote v
         GROUP BY
               v.id_ubicacion,
               v.id_almacen,
               v.id_variante,
               v.id_opcion_variante,
               v.id_presentacion
    )
    SELECT
        v.id_ubicacion,
        v.id_almacen,
        v.id_variante,
        v.id_opcion_variante,
        v.id_presentacion,
        c.nombre                        AS presentacion_nombre,
        c.sku_codigo,
        c.factor_rel,
        c.es_base,
        c.nivel,
        v.saldo,
        (v.saldo * COALESCE(c.factor_rel, 1)) AS equivalente_base,
        v.sku_producto,
        v.sku_ubicacion
      FROM vigente v
      LEFT JOIN public.fn_presentaciones_producto(p_id_producto) c
             ON c.id_presentacion = v.id_presentacion
     WHERE p_incluir_cero OR v.saldo <> 0
     ORDER BY v.id_ubicacion, COALESCE(c.nivel, 999), v.id_presentacion;
$function$

