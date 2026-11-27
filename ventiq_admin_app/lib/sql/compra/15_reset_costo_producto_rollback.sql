-- ============================================================================
-- 15_reset_costo_producto_rollback.sql — revierte 15_reset_costo_producto.sql
--
-- Retira la RPC y la tabla de historial. **Se pierde el rastro** de los
-- reinicios hechos; los precios ya reiniciados no se restauran (no hay copia
-- automática: el reset es deliberado y con motivo).
-- ============================================================================

DROP FUNCTION IF EXISTS public.fn_reset_costo_promedio_producto(bigint, text);
DROP TABLE IF EXISTS public.app_hist_reset_costo;

NOTIFY pgrst, 'reload schema';
