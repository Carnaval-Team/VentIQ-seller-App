-- =============================================================================
-- MIGRACIÓN 002: Soporte para múltiples carrocerías por transportista de carga
--
-- CONTEXTO: Un carrier_carga puede gestionar varias plataformas/carrocerías.
--           Los campos tipo_carroceria/capacidad_ton/etc. en muevete.drivers
--           se mantienen (backward compat) pero ya no se usan en el flujo nuevo.
--           La fuente de verdad pasa a ser muevete.carrocerias.
--
-- REGLA: Solo ADD COLUMN IF NOT EXISTS / CREATE TABLE IF NOT EXISTS.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. muevete.carrocerias — una fila por plataforma/vehículo de carga
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS muevete.carrocerias (
  id                  bigint GENERATED ALWAYS AS IDENTITY NOT NULL,

  -- FK al conductor/carrier dueño de esta carrocería
  driver_id           bigint NOT NULL,

  -- Datos del vehículo
  marca               text,
  modelo              text,
  matricula           text,
  tipo_carroceria     text NOT NULL,
  -- Valores: 'furgon_seco' | 'flatbed' | 'reefer' | 'tanque' | 'curtainsider' | 'volcadora'

  capacidad_ton       numeric,
  longitud_m          numeric,

  -- Seguro de carga
  seguro_vigente      boolean NOT NULL DEFAULT false,
  seguro_vence        date,
  seguro_url          text,

  -- Números regulatorios (opcionales por carrocería)
  mc_number           text,
  dot_number          text,

  -- Estado
  activo              boolean NOT NULL DEFAULT true,
  created_at          timestamp with time zone NOT NULL DEFAULT now(),
  updated_at          timestamp with time zone NOT NULL DEFAULT now(),

  CONSTRAINT carrocerias_pkey PRIMARY KEY (id),
  CONSTRAINT carrocerias_driver_fkey
    FOREIGN KEY (driver_id) REFERENCES muevete.drivers(id)
    ON DELETE CASCADE
);

-- -----------------------------------------------------------------------------
-- 2. Índices
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_carrocerias_driver_id
  ON muevete.carrocerias (driver_id);

CREATE INDEX IF NOT EXISTS idx_carrocerias_tipo
  ON muevete.carrocerias (tipo_carroceria);

-- -----------------------------------------------------------------------------
-- 3. Trigger: updated_at automático
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE trigger_schema = 'muevete'
      AND event_object_table = 'carrocerias'
      AND trigger_name = 'trg_carrocerias_updated_at'
  ) THEN
    CREATE TRIGGER trg_carrocerias_updated_at
      BEFORE UPDATE ON muevete.carrocerias
      FOR EACH ROW EXECUTE FUNCTION muevete.set_updated_at();
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 4. RLS — misma política que otras tablas del esquema muevete
--    El driver puede ver/editar sus propias carrocerías.
--    Los admins pueden ver todo.
-- -----------------------------------------------------------------------------
ALTER TABLE muevete.carrocerias ENABLE ROW LEVEL SECURITY;

-- Driver ve sus propias carrocerías
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'muevete'
      AND tablename  = 'carrocerias'
      AND policyname = 'carrocerias_driver_select'
  ) THEN
    CREATE POLICY carrocerias_driver_select
      ON muevete.carrocerias FOR SELECT
      USING (
        driver_id IN (
          SELECT id FROM muevete.drivers WHERE uuid = auth.uid()
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'muevete'
      AND tablename  = 'carrocerias'
      AND policyname = 'carrocerias_driver_insert'
  ) THEN
    CREATE POLICY carrocerias_driver_insert
      ON muevete.carrocerias FOR INSERT
      WITH CHECK (
        driver_id IN (
          SELECT id FROM muevete.drivers WHERE uuid = auth.uid()
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'muevete'
      AND tablename  = 'carrocerias'
      AND policyname = 'carrocerias_driver_update'
  ) THEN
    CREATE POLICY carrocerias_driver_update
      ON muevete.carrocerias FOR UPDATE
      USING (
        driver_id IN (
          SELECT id FROM muevete.drivers WHERE uuid = auth.uid()
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'muevete'
      AND tablename  = 'carrocerias'
      AND policyname = 'carrocerias_driver_delete'
  ) THEN
    CREATE POLICY carrocerias_driver_delete
      ON muevete.carrocerias FOR DELETE
      USING (
        driver_id IN (
          SELECT id FROM muevete.drivers WHERE uuid = auth.uid()
        )
      );
  END IF;
END $$;
