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

    -- Cerrar/reabrir fechas (u otros metadatos) NO debe
    -- reescribir Carnaval con el precio de esa fila.
    IF TG_OP = 'UPDATE'
       AND NEW.precio_venta_cup IS NOT DISTINCT FROM OLD.precio_venta_cup
       AND NEW.precio_venta_usd IS NOT DISTINCT FROM OLD.precio_venta_usd
       AND NEW.precio_descuento IS NOT DISTINCT FROM OLD.precio_descuento
    THEN
        RETURN NEW;
    END IF;

    SELECT p.id_vendedor_app, p.id_tienda
      INTO v_id_vendedor_app, v_id_tienda
      FROM public.app_dat_producto p
     WHERE p.id = NEW.id_producto;

    IF v_id_vendedor_app IS NULL THEN
        RETURN NEW;
    END IF;

    -- Siempre el vigente mas reciente por id (no NEW a ciegas).
    v_base_price := public.fn_carnaval_precio_base_vigente(NEW.id_producto);

    IF v_base_price IS NULL OR v_base_price <= 0 THEN
        RETURN NEW;
    END IF;

    SELECT o_pct_efectivo, o_pct_transferencia
      INTO v_pct_efectivo, v_pct_transferencia
      FROM public.fn_carnaval_porcientos_tienda(v_id_tienda);

    IF v_pct_efectivo IS NULL OR v_pct_transferencia IS NULL THEN
        RETURN NEW;
    END IF;

    v_precio_descuento := ROUND(v_base_price * (1 + v_pct_efectivo      / 100));
    v_precio_oficial   := ROUND(v_base_price * (1 + v_pct_transferencia / 100));

    UPDATE carnavalapp."Productos"
       SET price            = v_precio_oficial,
           precio_descuento = v_precio_descuento,
           updated_at       = NOW()
     WHERE id = v_id_vendedor_app
       AND COALESCE(proveedor, 0) <> 3;

    RETURN NEW;
END;
$function$

