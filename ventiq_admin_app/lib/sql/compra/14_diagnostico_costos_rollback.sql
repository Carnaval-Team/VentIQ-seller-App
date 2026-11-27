-- ============================================================================
-- 14_diagnostico_costos_rollback.sql — revierte 14_diagnostico_costos.sql
--
-- Solo retira la vista de solo lectura. No toca ningún costo.
-- ============================================================================

DROP VIEW IF EXISTS public.app_v_diagnostico_costo_producto;

NOTIFY pgrst, 'reload schema';
