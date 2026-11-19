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
               public.fn_carnaval_precio_base_vigente(p.id) AS precio_base,
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
       AND COALESCE(cp.proveedor, 0) <> 3;

    GET DIAGNOSTICS v_actualizados = ROW_COUNT;
    RAISE NOTICE '[piso_global] Productos recalculados: %.', v_actualizados;

    -- updated_at del global no se auto-actualiza en UPDATE;
    -- solo tocamos esa columna para no re-disparar este trigger
    -- (esta definido como UPDATE OF porciento_*).
    UPDATE public.precio_global_productos_carnaval
       SET updated_at = NOW()
     WHERE id = NEW.id;

    RETURN NEW;
END;
$function$

