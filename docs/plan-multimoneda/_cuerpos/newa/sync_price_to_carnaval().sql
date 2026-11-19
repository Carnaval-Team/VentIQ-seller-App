CREATE OR REPLACE FUNCTION public.sync_price_to_carnaval()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_id_vendedor_app   BIGINT;
    v_id_tienda         BIGINT;
    v_base_price        NUMERIC;
    v_pct_efectivo      NUMERIC;
    v_pct_transferencia NUMERIC;
    v_precio_descuento  NUMERIC;
    v_precio_oficial    NUMERIC;
BEGIN
    IF TG_OP NOT IN ('INSERT', 'UPDATE') THEN
        RETURN NEW;
    END IF;

    v_base_price := NEW.precio_venta_cup;

    -- Sin precio base no hay nada que sincronizar.
    IF v_base_price IS NULL OR v_base_price <= 0 THEN
        RETURN NEW;
    END IF;

    SELECT p.id_vendedor_app, p.id_tienda
      INTO v_id_vendedor_app, v_id_tienda
      FROM public.app_dat_producto p
     WHERE p.id = NEW.id_producto;

    -- El producto no esta publicado en Carnaval.
    IF v_id_vendedor_app IS NULL THEN
        RETURN NEW;
    END IF;

    -- Porcientos configurados a la tienda (o los historicos).
    SELECT o_pct_efectivo, o_pct_transferencia
      INTO v_pct_efectivo, v_pct_transferencia
      FROM public.fn_carnaval_porcientos_tienda(v_id_tienda);

    -- Cinturon de seguridad: nunca escribir un precio nulo en
    -- Carnaval. Si por lo que sea no hay porcientos, se deja el
    -- precio de Carnaval como estaba.
    IF v_pct_efectivo IS NULL OR v_pct_transferencia IS NULL THEN
        RETURN NEW;
    END IF;

    -- Misma formula que rpc_apply_global_price_change y
    -- rpc_apply_selected_price_change, para que el trigger y el
    -- cambio de precios desde la app coincidan.
    v_precio_descuento := ROUND(v_base_price * (1 + v_pct_efectivo      / 100));
    v_precio_oficial   := ROUND(v_base_price * (1 + v_pct_transferencia / 100));

    -- proveedor = 3 esta bloqueado por
    -- carnavalapp.productos_block_proveedor_3 (RAISE EXCEPTION).
    -- Excluirlo evita abortar la transaccion del precio local.
    UPDATE carnavalapp."Productos"
       SET price            = v_precio_oficial,
           precio_descuento = v_precio_descuento,
           updated_at       = NOW()
     WHERE id = v_id_vendedor_app
       AND COALESCE(proveedor, 0) <> 3;

    RETURN NEW;
END;
$function$

