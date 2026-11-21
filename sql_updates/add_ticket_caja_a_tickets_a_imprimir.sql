-- Recibo de caja como ticket propio en app_dat_configuracion_tienda.tickets_a_imprimir
--
-- Hasta ahora el TPV imprimía siempre factura, guía de almacén y recibo de caja y
-- no leía tickets_a_imprimir (que solo conocía 'cliente' y 'almacen'). El TPV
-- pasa a respetar la lista:
--   'cliente' -> factura       'almacen' -> guía de almacén       'caja' -> recibo de caja
--
-- Para que las tiendas existentes sigan imprimiendo lo mismo, las que ya tenían
-- 'cliente' reciben también 'caja'. Las que no lo tenían (p. ej. lista vacía:
-- «no se imprimirá ningún ticket») se dejan como están.
--
-- Solo datos y valor por defecto; no cambia el esquema ni crea tablas, y los
-- clientes antiguos (admin sin el chip «Recibo caja») conservan 'caja' porque
-- reenvían la lista completa que leyeron.
--
-- ORDEN DE DESPLIEGUE (expansión -> clientes): ejecutar antes de publicar el
-- TPV que lee tickets_a_imprimir. Sin este script, una tienda con
-- ['cliente','almacen'] dejaría de imprimir el recibo de caja.

BEGIN;

DO $$
BEGIN
    IF to_regclass('public.app_dat_configuracion_tienda') IS NULL
       OR NOT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = 'app_dat_configuracion_tienda'
              AND column_name = 'tickets_a_imprimir'
       ) THEN
        RAISE EXCEPTION 'Falta app_dat_configuracion_tienda.tickets_a_imprimir';
    END IF;
END $$;

ALTER TABLE public.app_dat_configuracion_tienda
    ALTER COLUMN tickets_a_imprimir
    SET DEFAULT '["cliente","almacen","caja"]'::jsonb;

UPDATE public.app_dat_configuracion_tienda
SET tickets_a_imprimir = tickets_a_imprimir || '["caja"]'::jsonb
WHERE jsonb_typeof(tickets_a_imprimir) = 'array'
  AND tickets_a_imprimir ? 'cliente'
  AND NOT (tickets_a_imprimir ? 'caja');

COMMENT ON COLUMN public.app_dat_configuracion_tienda.tickets_a_imprimir IS
  'Tickets de la venta del TPV: "cliente" (factura), "almacen" (guía de almacén), "caja" (recibo de caja). Lista vacía = no se imprime ninguno.';

-- Verificación: ninguna tienda con factura se queda sin recibo de caja.
DO $$
DECLARE
    v_pendientes integer;
BEGIN
    SELECT count(*) INTO v_pendientes
    FROM public.app_dat_configuracion_tienda
    WHERE jsonb_typeof(tickets_a_imprimir) = 'array'
      AND tickets_a_imprimir ? 'cliente'
      AND NOT (tickets_a_imprimir ? 'caja');
    IF v_pendientes <> 0 THEN
        RAISE EXCEPTION 'Quedan % tiendas con cliente y sin caja', v_pendientes;
    END IF;
END $$;

COMMIT;
