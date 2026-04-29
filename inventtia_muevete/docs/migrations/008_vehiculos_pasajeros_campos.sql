-- =============================================================================
-- MIGRACIÓN 008: Campos adicionales para vehículos de transporte de pasajeros
--
-- CONTEXTO: muevete.vehiculos ya tiene marca, modelo, chapa, capacidad, color.
--           Se agregan campos de condición, año, aire acondicionado,
--           id_tipo_vehiculo (FK a vehicle_type) y uuid del conductor propietario.
--
-- REGLA: Solo ADD COLUMN IF NOT EXISTS.
-- =============================================================================

ALTER TABLE muevete.vehiculos
  ADD COLUMN IF NOT EXISTS id_tipo_vehiculo bigint,
  -- FK a muevete.vehicle_type (auto, moto, microbus, camioneta, etc.)

  ADD COLUMN IF NOT EXISTS año             integer,
  -- Año de fabricación del vehículo

  ADD COLUMN IF NOT EXISTS condicion       text DEFAULT 'bueno',
  -- 'excelente' | 'bueno' | 'regular'

  ADD COLUMN IF NOT EXISTS aire_acondicionado boolean NOT NULL DEFAULT false,
  -- ¿Tiene A/C?

  ADD COLUMN IF NOT EXISTS capacidad_int   integer,
  -- Número entero de asientos de pasajeros (reemplaza el varchar "capacidad")
  -- "capacidad" varchar original se mantiene para backward compat

  ADD COLUMN IF NOT EXISTS driver_uuid     uuid;
  -- UUID del conductor dueño del vehículo (para RLS y queries directas)

-- -----------------------------------------------------------------------------
-- FK a vehicle_type (solo si la tabla existe)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'muevete'
      AND table_name   = 'vehicle_type'
  ) THEN
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.table_constraints
      WHERE constraint_name = 'vehiculos_id_tipo_vehiculo_fkey'
        AND table_schema     = 'muevete'
        AND table_name       = 'vehiculos'
    ) THEN
      ALTER TABLE muevete.vehiculos
        ADD CONSTRAINT vehiculos_id_tipo_vehiculo_fkey
        FOREIGN KEY (id_tipo_vehiculo) REFERENCES muevete.vehicle_type(id);
    END IF;
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- Índices
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_vehiculos_driver_uuid
  ON muevete.vehiculos (driver_uuid);

CREATE INDEX IF NOT EXISTS idx_vehiculos_id_tipo
  ON muevete.vehiculos (id_tipo_vehiculo);
