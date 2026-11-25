-- ============================================================================
-- Fase 1 (aditivo): columnas producto-v1 para poder crear fn_listar_ordenes_m01
-- ============================================================================
-- NO incluye:
--   * triggers m01_* (Fase 3 / R12–R15)
--   * tablas de política R06/R07 ni FK a ellas
--   * CHECK estrictos de producto-v1 (evitan lock largo y no hacen falta
--     mientras el flag esté apagado y nadie escriba v1 en main)
--
-- Filas existentes: todas las columnas nuevas quedan NULL → clientes viejos
-- siguen igual. Solo habilita el preflight de promocion_m01/06.
--
-- Orden: después de 01–05; antes de reintentar 06.
-- ============================================================================

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';

-- operacion_venta: solo lo que exige el preflight de 06
ALTER TABLE public.app_dat_operacion_venta
  ADD COLUMN IF NOT EXISTS version_monetaria text;

COMMENT ON COLUMN public.app_dat_operacion_venta.version_monetaria IS
  'NULL = venta legacy; producto-v1 cuando el flag de tienda esté activo (Fase 2+).';

-- extraccion_productos: columnas que lee fn_listar_ordenes_m01
ALTER TABLE public.app_dat_extraccion_productos
  ADD COLUMN IF NOT EXISTS version_monetaria text,
  ADD COLUMN IF NOT EXISTS id_linea_cliente uuid,
  ADD COLUMN IF NOT EXISTS moneda_venta text,
  ADD COLUMN IF NOT EXISTS id_medio_pago_seleccionado smallint,
  ADD COLUMN IF NOT EXISTS seleccion_pendiente boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS precio_unitario_nativo numeric,
  ADD COLUMN IF NOT EXISTS descuento_manual_unitario_nativo numeric,
  ADD COLUMN IF NOT EXISTS precio_unitario_neto_nativo numeric,
  ADD COLUMN IF NOT EXISTS importe_bruto_nativo numeric,
  ADD COLUMN IF NOT EXISTS importe_neto_nativo numeric,
  ADD COLUMN IF NOT EXISTS tasa_cambio_cup numeric,
  ADD COLUMN IF NOT EXISTS importe_bruto_cup_equivalente numeric,
  ADD COLUMN IF NOT EXISTS importe_neto_cup_equivalente numeric,
  ADD COLUMN IF NOT EXISTS snapshot_precio jsonb,
  ADD COLUMN IF NOT EXISTS snapshot_descuentos jsonb,
  ADD COLUMN IF NOT EXISTS snapshot_tasa jsonb;

-- FK suave al catálogo de medios (nullable; filas viejas sin medio OK)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'app_dat_extraccion_productos_id_medio_pago_seleccionado_fkey'
  ) THEN
    ALTER TABLE public.app_dat_extraccion_productos
      ADD CONSTRAINT app_dat_extraccion_productos_id_medio_pago_seleccionado_fkey
      FOREIGN KEY (id_medio_pago_seleccionado)
      REFERENCES public.app_nom_medio_pago (id);
  END IF;
END $$;

-- Índice único parcial (idempotente)
CREATE UNIQUE INDEX IF NOT EXISTS m01_extraccion_linea_cliente
  ON public.app_dat_extraccion_productos (id_operacion, id_linea_cliente)
  WHERE id_linea_cliente IS NOT NULL;

-- Verificación = mismo criterio que el preflight de 06
DO $chk$
BEGIN
  IF (SELECT count(*) FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'app_dat_extraccion_productos'
        AND column_name IN (
          'version_monetaria', 'id_linea_cliente', 'moneda_venta',
          'id_medio_pago_seleccionado', 'seleccion_pendiente',
          'precio_unitario_nativo', 'descuento_manual_unitario_nativo',
          'precio_unitario_neto_nativo', 'importe_neto_nativo',
          'tasa_cambio_cup', 'snapshot_precio', 'snapshot_tasa',
          'snapshot_descuentos'
        )) < 13 THEN
    RAISE EXCEPTION 'Faltan columnas v1 en app_dat_extraccion_productos';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'app_dat_operacion_venta'
      AND column_name = 'version_monetaria'
  ) THEN
    RAISE EXCEPTION 'Falta version_monetaria en app_dat_operacion_venta';
  END IF;
END
$chk$;

COMMIT;
