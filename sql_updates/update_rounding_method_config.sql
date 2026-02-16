-- Agrega configuración de redondeo y actualiza el trigger de precios
-- Fecha: 2026-02-05

BEGIN;

ALTER TABLE public.app_dat_configuracion_tienda
  ADD COLUMN IF NOT EXISTS metodo_redondeo_precio_venta text NOT NULL
  DEFAULT 'NO_REDONDEAR';

UPDATE public.app_dat_configuracion_tienda
SET metodo_redondeo_precio_venta = 'NO_REDONDEAR'
WHERE metodo_redondeo_precio_venta IS NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'app_dat_configuracion_tienda_metodo_redondeo_check'
  ) THEN
    ALTER TABLE public.app_dat_configuracion_tienda
      ADD CONSTRAINT app_dat_configuracion_tienda_metodo_redondeo_check
      CHECK (
        metodo_redondeo_precio_venta IN (
          'NO_REDONDEAR',
          'REDONDEAR_POR_DEFECTO',
          'REDONDEAR_POR_EXCESO',
          'REDONDEAR_A_MULT_5_POR_DEFECTO',
          'REDONDEAR_A_MULT_5_POR_EXCESO'
        )
      );
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.trg_round_precio_venta_cup()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_store_id bigint;
  v_metodo text := 'NO_REDONDEAR';
BEGIN
  IF NEW.precio_venta_cup IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT p.id_tienda
  INTO v_store_id
  FROM public.app_dat_producto p
  WHERE p.id = NEW.id_producto
  LIMIT 1;

  IF v_store_id IS NOT NULL THEN
    SELECT COALESCE(ct.metodo_redondeo_precio_venta, 'NO_REDONDEAR')
    INTO v_metodo
    FROM public.app_dat_configuracion_tienda ct
    WHERE ct.id_tienda = v_store_id
    LIMIT 1;
  END IF;

  CASE v_metodo
    WHEN 'REDONDEAR_POR_DEFECTO' THEN
      NEW.precio_venta_cup := round(NEW.precio_venta_cup, 0);
    WHEN 'REDONDEAR_POR_EXCESO' THEN
      NEW.precio_venta_cup := ceil(NEW.precio_venta_cup);
    WHEN 'REDONDEAR_A_MULT_5_POR_DEFECTO' THEN
      NEW.precio_venta_cup := round(NEW.precio_venta_cup / 5.0) * 5;
    WHEN 'REDONDEAR_A_MULT_5_POR_EXCESO' THEN
      NEW.precio_venta_cup := ceil(NEW.precio_venta_cup / 5.0) * 5;
    ELSE
      NEW.precio_venta_cup := NEW.precio_venta_cup;
  END CASE;

  -- CASE v_metodo
  --   WHEN 'REDONDEAR_POR_DEFECTO' THEN
  --     NEW. := round(NEW.precio_venta_cup, 0);
  --   WHEN 'REDONDEAR_POR_EXCESO' THEN
  --     NEW.precio_venta_cup := ceil(NEW.precio_venta_cup);
  --   WHEN 'REDONDEAR_A_MULT_5_POR_DEFECTO' THEN
  --     NEW.precio_venta_cup := round(NEW.precio_venta_cup / 5.0) * 5;
  --   WHEN 'REDONDEAR_A_MULT_5_POR_EXCESO' THEN
  --     NEW.precio_venta_cup := ceil(NEW.precio_venta_cup / 5.0) * 5;
  --   ELSE
  --     NEW.precio_venta_cup := NEW.precio_venta_cup;
  -- END CASE;

  NEW.precio_venta_cup := round(NEW.precio_venta_cup, 2)::numeric(18, 2);

  RETURN NEW;
END;
$$;

COMMIT;
