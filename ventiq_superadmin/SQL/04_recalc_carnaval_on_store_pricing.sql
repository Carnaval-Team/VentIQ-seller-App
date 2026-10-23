-- ============================================================================
-- 04 · Al cambiar % de tienda, recalcular precios en carnavalapp
-- ============================================================================
-- Problema: app_dat_precio_general_tienda se actualizaba desde
-- carnaval_store_pricing_screen / updateStorePricing, pero NO había
-- trigger ni RPC que reescribiera carnavalapp."Productos".
-- Solo el piso global (precio_global_productos_carnaval) disparaba
-- fn_update_carnaval_product_prices.
--
-- Solución:
--   1) rpc_recalc_carnaval_prices_for_store(p_store_id)
--      Recalcula price / precio_descuento de los productos de esa
--      tienda publicados en Carnaval (excluye proveedor 3).
--   2) Trigger AFTER INSERT/UPDATE de los % carnaval en
--      app_dat_precio_general_tienda → llama a esa RPC.
--
-- Fórmula (igual que sync_price_to_carnaval / piso global):
--   base = fn_carnaval_precio_base_vigente(producto)
--   pct  = fn_carnaval_porcientos_tienda(tienda)  -- GREATEST(tienda, piso)
--   precio_descuento = ROUND(base * (1 + pct_efectivo / 100))
--   price            = ROUND(base * (1 + pct_transferencia / 100))
--
-- Aplicar en: Supabase SQL Editor (main). Idempotente.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.rpc_recalc_carnaval_prices_for_store(
    p_store_id bigint
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_pct_efectivo      numeric;
    v_pct_transferencia numeric;
    v_actualizados      integer := 0;
BEGIN
    IF p_store_id IS NULL THEN
        RETURN 0;
    END IF;

    SELECT o_pct_efectivo, o_pct_transferencia
      INTO v_pct_efectivo, v_pct_transferencia
      FROM public.fn_carnaval_porcientos_tienda(p_store_id);

    IF v_pct_efectivo IS NULL OR v_pct_transferencia IS NULL THEN
        RAISE NOTICE
          '[recalc_store %] sin porcientos aplicables, no se toca nada',
          p_store_id;
        RETURN 0;
    END IF;

    WITH productos AS (
        SELECT p.id_vendedor_app,
               public.fn_carnaval_precio_base_vigente(p.id) AS precio_base
          FROM public.app_dat_producto p
         WHERE p.id_tienda = p_store_id
           AND p.id_vendedor_app IS NOT NULL
           AND p.deleted_at IS NULL
    )
    UPDATE carnavalapp."Productos" cp
       SET price            = ROUND(pr.precio_base * (1 + v_pct_transferencia / 100)),
           precio_descuento = ROUND(pr.precio_base * (1 + v_pct_efectivo      / 100)),
           updated_at       = NOW()
      FROM productos pr
     WHERE cp.id = pr.id_vendedor_app
       AND pr.precio_base IS NOT NULL
       AND pr.precio_base > 0
       AND COALESCE(cp.proveedor, 0) <> 3;

    GET DIAGNOSTICS v_actualizados = ROW_COUNT;
    RAISE NOTICE
      '[recalc_store %] productos carnaval actualizados: % (ef=%, tr=%)',
      p_store_id, v_actualizados, v_pct_efectivo, v_pct_transferencia;

    RETURN v_actualizados;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_recalc_carnaval_prices_for_store(bigint)
    TO authenticated, service_role;


CREATE OR REPLACE FUNCTION public.fn_trg_recalc_carnaval_on_store_pricing()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    -- Solo cuando cambian los % de carnaval (no precio_regular).
    IF TG_OP = 'UPDATE'
       AND NEW.precio_venta_carnaval IS NOT DISTINCT FROM OLD.precio_venta_carnaval
       AND NEW.precio_venta_carnaval_transferencia
           IS NOT DISTINCT FROM OLD.precio_venta_carnaval_transferencia
    THEN
        RETURN NEW;
    END IF;

    PERFORM public.rpc_recalc_carnaval_prices_for_store(NEW.id_tienda);
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_recalc_carnaval_on_store_pricing
    ON public.app_dat_precio_general_tienda;

CREATE TRIGGER trg_recalc_carnaval_on_store_pricing
    AFTER INSERT OR UPDATE OF
        precio_venta_carnaval,
        precio_venta_carnaval_transferencia
    ON public.app_dat_precio_general_tienda
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_trg_recalc_carnaval_on_store_pricing();
