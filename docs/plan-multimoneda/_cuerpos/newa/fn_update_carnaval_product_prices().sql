CREATE OR REPLACE FUNCTION public.fn_update_carnaval_product_prices()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_actualizados INTEGER := 0;
BEGIN
    WITH productos AS (
        SELECT p.id_vendedor_app,
               -- Mismo criterio que sync_price_to_carnaval:
               -- el precio mas reciente por created_at.
               (SELECT pv.precio_venta_cup
                  FROM public.app_dat_precio_venta pv
                 WHERE pv.id_producto = p.id
                 ORDER BY pv.created_at DESC
                 LIMIT 1)                       AS precio_base,
               -- El porciento de la tienda no puede bajar del
               -- global que se acaba de guardar (NEW).
               GREATEST(COALESCE(pg.precio_venta_carnaval,
                                 NEW.porciento_efectivo),
                        NEW.porciento_efectivo)  AS pct_efectivo,
               GREATEST(COALESCE(pg.precio_venta_carnaval_transferencia,
                                 NEW.porciento_transferencia),
                        NEW.porciento_transferencia) AS pct_transferencia
        FROM public.app_dat_producto p
        LEFT JOIN public.app_dat_precio_general_tienda pg
               ON pg.id_tienda = p.id_tienda
        WHERE p.id_vendedor_app IS NOT NULL
          AND p.deleted_at IS NULL
    )
    UPDATE carnavalapp."Productos" cp
       SET price            = ROUND(pr.precio_base * (1 + pr.pct_transferencia / 100)),
           precio_descuento = ROUND(pr.precio_base * (1 + pr.pct_efectivo      / 100)),
           updated_at       = NOW()
      FROM productos pr
     WHERE cp.id = pr.id_vendedor_app
       AND pr.precio_base IS NOT NULL
       AND pr.precio_base > 0
       -- proveedor = 3 esta bloqueado por
       -- carnavalapp.productos_block_proveedor_3 (RAISE EXCEPTION):
       -- incluirlo abortaria toda la operacion.
       AND COALESCE(cp.proveedor, 0) <> 3;

    GET DIAGNOSTICS v_actualizados = ROW_COUNT;
    RAISE NOTICE '[piso_global] Productos recalculados: %.', v_actualizados;

    RETURN NEW;
END;
$function$

