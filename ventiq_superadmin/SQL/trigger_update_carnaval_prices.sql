-- Trigger function: when precio_global_productos_carnaval is updated,
-- recalculate price and precio_descuento for all carnavalapp.Productos
-- that are linked to local products (via app_dat_producto.id_vendedor_app).
--
-- Formula:
--   precio_descuento = precio_venta_cup * (1 + porciento_efectivo / 100)
--   price            = precio_venta_cup * (1 + porciento_transferencia / 100)

CREATE OR REPLACE FUNCTION public.fn_update_carnaval_product_prices()
RETURNS TRIGGER AS $$
DECLARE
  r RECORD;
  v_precio_base numeric;
  v_new_price numeric;
  v_new_precio_descuento numeric;
BEGIN
  -- Loop through all local products that have a carnaval link
  FOR r IN
    SELECT
      p.id AS local_id,
      p.id_vendedor_app AS carnaval_product_id
    FROM public.app_dat_producto p
    WHERE p.id_vendedor_app IS NOT NULL
      AND p.deleted_at IS NULL
  LOOP
    -- Get the current price (most recent active precio_venta_cup)
    SELECT pv.precio_venta_cup INTO v_precio_base
    FROM public.app_dat_precio_venta pv
    WHERE pv.id_producto = r.local_id
      AND pv.fecha_desde <= CURRENT_DATE
    ORDER BY pv.fecha_desde DESC
    LIMIT 1;

    -- Skip if no price found
    IF v_precio_base IS NULL THEN
      CONTINUE;
    END IF;

    -- Calculate new prices
    v_new_precio_descuento := ROUND(v_precio_base * (1 + NEW.porciento_efectivo / 100));
    -- Round transferencia price UP to nearest multiple of 5
    v_new_price := CEIL(v_precio_base * (1 + NEW.porciento_transferencia / 100) / 5.0) * 5;

    -- Update carnavalapp.Productos
    UPDATE carnavalapp."Productos"
    SET
      price = v_new_price,
      precio_descuento = v_new_precio_descuento,
      updated_at = NOW()
    WHERE id = r.carnaval_product_id;
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create the trigger on UPDATE of precio_global_productos_carnaval
DROP TRIGGER IF EXISTS trg_update_carnaval_prices ON public.precio_global_productos_carnaval;

CREATE TRIGGER trg_update_carnaval_prices
  AFTER UPDATE OF porciento_efectivo, porciento_transferencia
  ON public.precio_global_productos_carnaval
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_update_carnaval_product_prices();
