-- ============================================================
-- mostrar_debe_haber_en_conteo_inventario
-- ============================================================
-- Subopción de maneja_inventario: si el vendedor ve el "debe haber"
-- en el conteo de inventario (apertura/cierre de turno).
-- Default FALSE = no se muestra (comportamiento actual).
--
-- APLICAR MANUALMENTE en Supabase (SQL Editor).
-- ============================================================

ALTER TABLE public.app_dat_configuracion_tienda
  ADD COLUMN IF NOT EXISTS mostrar_debe_haber_en_conteo_inventario boolean
  NOT NULL DEFAULT false;

COMMENT ON COLUMN public.app_dat_configuracion_tienda.mostrar_debe_haber_en_conteo_inventario IS
'Si true y maneja_inventario=true, el vendedor ve la cantidad "debe haber" en el conteo de inventario al abrir/cerrar turno.';
