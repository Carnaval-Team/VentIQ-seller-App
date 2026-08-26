-- Opción global de tienda: mostrar método de pago en el ticket.
ALTER TABLE public.app_dat_configuracion_tienda
  ADD COLUMN IF NOT EXISTS mostrar_metodo_pago_ticket boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN public.app_dat_configuracion_tienda.mostrar_metodo_pago_ticket IS
  'Si true, el ticket de venta incluye el desglose/método(s) de pago de la orden.';
