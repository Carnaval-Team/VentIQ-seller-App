-- Opción global de tienda: mostrar selector de moneda (CUP/USD) en el checkout del vendedor.
ALTER TABLE public.app_dat_configuracion_tienda
  ADD COLUMN IF NOT EXISTS mostrar_selector_moneda boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.app_dat_configuracion_tienda.mostrar_selector_moneda IS
  'Si true, el cajero puede elegir la moneda (CUP/USD) por método de pago en cada venta.';
