-- Migración: configuración de impresión y conteo de inventario en app_dat_configuracion_tienda
-- Ejecutar en Supabase para que admin y app compartan la misma configuración.

ALTER TABLE public.app_dat_configuracion_tienda
  ADD COLUMN IF NOT EXISTS guardar_impresora_por_defecto boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS tickets_a_imprimir jsonb NOT NULL DEFAULT '["cliente","almacen"]'::jsonb,
  ADD COLUMN IF NOT EXISTS copias_por_ticket jsonb NOT NULL DEFAULT '{"cliente":1,"almacen":1}'::jsonb,
  ADD COLUMN IF NOT EXISTS autocompletar_cantidad_real_conteo boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.app_dat_configuracion_tienda.guardar_impresora_por_defecto IS
  'Si true, los vendedores pueden recordar la impresora seleccionada para el turno';
COMMENT ON COLUMN public.app_dat_configuracion_tienda.tickets_a_imprimir IS
  'Lista de tickets a imprimir. Ej: ["cliente", "almacen"] (ordenado)';
COMMENT ON COLUMN public.app_dat_configuracion_tienda.copias_por_ticket IS
  'Cantidad de copias por tipo de ticket. Ej: {"cliente": 1, "almacen": 1}';
COMMENT ON COLUMN public.app_dat_configuracion_tienda.autocompletar_cantidad_real_conteo IS
  'Si true, en apertura/cierre de turno se muestra un botón para copiar la cantidad esperada como cantidad real contada';
