-- ============================================================================
-- 11_importadora_bruto_rollback.sql — revierte 11_importadora_bruto.sql
--
-- Solo retira la columna generada y sus comentarios. No toca los importes:
-- `monto_importadora` (neto) y `reembolso_importadora` siguen como estaban.
-- ============================================================================

ALTER TABLE public.fdi_dat_compra_recepcion
    DROP COLUMN IF EXISTS monto_bruto_importadora;

COMMENT ON COLUMN public.fdi_dat_compra_recepcion.monto_importadora IS NULL;
COMMENT ON COLUMN public.fdi_dat_compra_recepcion.reembolso_importadora IS NULL;

NOTIFY pgrst, 'reload schema';
