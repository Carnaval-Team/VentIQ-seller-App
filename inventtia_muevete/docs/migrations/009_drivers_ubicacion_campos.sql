-- =============================================================================
-- MIGRACIÓN 009: Campos de ubicación para muevete.drivers
--
-- CONTEXTO: muevete.users ya tiene pais, province, municipality.
--           muevete.drivers carece de ellas, causando PGRST204 al registrar
--           conductores (carrier_carga, conductor_pasajeros, dispatcher).
--
-- REGLA: Solo ADD COLUMN IF NOT EXISTS.
-- =============================================================================

ALTER TABLE muevete.drivers
  ADD COLUMN IF NOT EXISTS pais         text,
  -- País de residencia / operación del conductor

  ADD COLUMN IF NOT EXISTS province     text,
  -- Estado / departamento / provincia

  ADD COLUMN IF NOT EXISTS municipality text;
  -- Municipio / ciudad

-- Índices para queries de filtrado geográfico
CREATE INDEX IF NOT EXISTS idx_drivers_pais
  ON muevete.drivers (pais);

CREATE INDEX IF NOT EXISTS idx_drivers_province
  ON muevete.drivers (province);
