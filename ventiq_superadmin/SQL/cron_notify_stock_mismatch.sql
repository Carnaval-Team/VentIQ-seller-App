-- Function: Detects stock mismatches between InventTIA and CarnavalApp
-- For every product with id_vendedor_app != null:
--   1. Get InventTIA stock (latest cantidad_final from app_dat_inventario_productos)
--   2. Get CarnavalApp stock (carnavalapp.Productos.stock)
--   3. If different, send notification to all gerentes and supervisores of the product's tienda
--   Uses fn_crear_notificacion RPC for notifications

CREATE OR REPLACE FUNCTION public.fn_notify_stock_mismatch()
RETURNS void AS $$
DECLARE
  r RECORD;
  v_ubicacion bigint;
  v_stock_inventtia numeric;
  v_stock_carnaval bigint;
  v_admin RECORD;
  v_producto_nombre text;
BEGIN
  FOR r IN
    SELECT p.id, p.id_vendedor_app, p.id_tienda, p.denominacion
    FROM public.app_dat_producto p
    WHERE p.id_vendedor_app IS NOT NULL
      AND p.deleted_at IS NULL
  LOOP
    -- Get id_ubicacion from relation_products_carnaval
    SELECT rpc.id_ubicacion INTO v_ubicacion
    FROM public.relation_products_carnaval rpc
    WHERE rpc.id_producto = r.id
      AND rpc.id_producto_carnaval = r.id_vendedor_app
    LIMIT 1;

    IF v_ubicacion IS NULL THEN
      CONTINUE;
    END IF;

    -- Get InventTIA stock (latest cantidad_final)
    SELECT ip.cantidad_final INTO v_stock_inventtia
    FROM public.app_dat_inventario_productos ip
    WHERE ip.id_producto = r.id
      AND ip.id_ubicacion = v_ubicacion
    ORDER BY ip.id DESC
    LIMIT 1;

    -- Default to 0 if no inventory found
    IF v_stock_inventtia IS NULL THEN
      v_stock_inventtia := 0;
    END IF;

    -- Get CarnavalApp stock
    SELECT cp.stock INTO v_stock_carnaval
    FROM carnavalapp."Productos" cp
    WHERE cp.id = r.id_vendedor_app;

    IF v_stock_carnaval IS NULL THEN
      v_stock_carnaval := 0;
    END IF;

    -- Compare stocks
    IF v_stock_inventtia::bigint != v_stock_carnaval THEN
      v_producto_nombre := COALESCE(r.denominacion, 'Producto #' || r.id);

      -- Notify all gerentes of the tienda
      FOR v_admin IN
        SELECT uuid FROM public.app_dat_gerente WHERE id_tienda = r.id_tienda
        UNION
        SELECT uuid FROM public.app_dat_supervisor WHERE id_tienda = r.id_tienda
      LOOP
        INSERT INTO public.app_dat_notificaciones (
          user_id, tipo, titulo, mensaje, prioridad, data
        ) VALUES (
          v_admin.uuid,
          'inventario',
          'Diferencia de stock detectada',
          'El producto "' || v_producto_nombre || '" tiene stock ' || v_stock_inventtia::bigint || ' en InventTIA y ' || v_stock_carnaval || ' en CarnavalApp.',
          'alta',
          jsonb_build_object(
            'id_producto', r.id,
            'id_producto_carnaval', r.id_vendedor_app,
            'stock_inventtia', v_stock_inventtia::bigint,
            'stock_carnaval', v_stock_carnaval,
            'id_tienda', r.id_tienda
          )
        );
      END LOOP;
    END IF;

  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Schedule with pg_cron: run every 5 minutes
-- NOTE: pg_cron must be enabled in your Supabase project (Extensions > pg_cron)
SELECT cron.schedule(
  'notify-stock-mismatch',
  '*/5 * * * *',
  $$SELECT public.fn_notify_stock_mismatch()$$
);
