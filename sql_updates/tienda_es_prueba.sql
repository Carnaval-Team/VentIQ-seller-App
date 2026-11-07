-- Tiendas de prueba: no entran en el reparto de pagos a Inventtia.

BEGIN;

ALTER TABLE public.app_dat_tienda
  ADD COLUMN IF NOT EXISTS es_prueba boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.app_dat_tienda.es_prueba IS
  'Tienda de prueba. Se excluye de los cobros de licencia, del 1% de Carnaval y del pago a proveedores.';

COMMIT;
