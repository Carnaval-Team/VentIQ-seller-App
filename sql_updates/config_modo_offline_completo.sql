-- ============================================================================
-- Configuración para modo offline completo de ventiq_app
-- ============================================================================

BEGIN;

-- 1. Permitir que el vendedor de esta tienda trabaje completamente offline
ALTER TABLE public.app_dat_configuracion_tienda
  ADD COLUMN IF NOT EXISTS permitir_modo_offline_completo boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.app_dat_configuracion_tienda.permitir_modo_offline_completo
  IS 'Si true, los vendedores de esta tienda pueden usar ventiq_app en modo completamente offline con licencia activa.';

-- 2. Días máximos sin validar licencia antes de bloquear la app
ALTER TABLE public.app_dat_configuracion_tienda
  ADD COLUMN IF NOT EXISTS dias_max_sin_validar_licencia integer NOT NULL DEFAULT 7;

COMMENT ON COLUMN public.app_dat_configuracion_tienda.dias_max_sin_validar_licencia
  IS 'Número máximo de días que un dispositivo puede operar offline sin reconectarse para validar la licencia.';

COMMIT;
