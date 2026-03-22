-- Function: Syncs stock from app_dat_inventario_productos to carnavalapp.Productos
-- For every local product with id_vendedor_app != null:
--   1. Find relation in relation_products_carnaval to get id_ubicacion
--   2. Get latest cantidad_final from app_dat_inventario_productos (by id DESC)
--   3. Update carnavalapp.Productos.stock

CREATE OR REPLACE FUNCTION public.fn_sync_carnaval_stock()
RETURNS void AS $$
DECLARE
  r RECORD;
  v_ubicacion bigint;
  v_cantidad_final numeric;
BEGIN
  FOR r IN
    SELECT id, id_vendedor_app
    FROM public.app_dat_producto
    WHERE id_vendedor_app IS NOT NULL
      AND deleted_at IS NULL
  LOOP
    -- Get id_ubicacion from relation_products_carnaval
    SELECT rpc.id_ubicacion INTO v_ubicacion
    FROM public.relation_products_carnaval rpc
    WHERE rpc.id_producto = r.id
      AND rpc.id_producto_carnaval = r.id_vendedor_app
    LIMIT 1;

    -- Skip if no relation found
    IF v_ubicacion IS NULL THEN
      CONTINUE;
    END IF;

    -- Get latest cantidad_final from inventario
    SELECT ip.cantidad_final INTO v_cantidad_final
    FROM public.app_dat_inventario_productos ip
    WHERE ip.id_producto = r.id
      AND ip.id_ubicacion = v_ubicacion
    ORDER BY ip.id DESC
    LIMIT 1;

    -- Default to 0 if no inventory found
    IF v_cantidad_final IS NULL THEN
      v_cantidad_final := 0;
    END IF;

    -- Update carnavalapp.Productos stock
    UPDATE carnavalapp."Productos"
    SET stock = v_cantidad_final::bigint
    WHERE id = r.id_vendedor_app;

  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Schedule with pg_cron: run every minute
-- NOTE: pg_cron must be enabled in your Supabase project (Extensions > pg_cron)
SELECT cron.schedule(
  'sync-carnaval-stock',
  '* * * * *',
  $$SELECT public.fn_sync_carnaval_stock()$$
);
