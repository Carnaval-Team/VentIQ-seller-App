-- Migration 027: Add driving license and vehicle circulation license photo columns
-- to muevete.drivers for conductor_pasajeros role.
-- Each document stores front and back photo URLs (same pattern as doc_frente_url / doc_dorso_url).

ALTER TABLE muevete.drivers
  ADD COLUMN IF NOT EXISTS lic_conduccion_frente_url  text,
  ADD COLUMN IF NOT EXISTS lic_conduccion_dorso_url   text,
  ADD COLUMN IF NOT EXISTS lic_circulacion_frente_url text,
  ADD COLUMN IF NOT EXISTS lic_circulacion_dorso_url  text;

COMMENT ON COLUMN muevete.drivers.lic_conduccion_frente_url  IS 'Foto frente de la Licencia de Conducción';
COMMENT ON COLUMN muevete.drivers.lic_conduccion_dorso_url   IS 'Foto dorso de la Licencia de Conducción';
COMMENT ON COLUMN muevete.drivers.lic_circulacion_frente_url IS 'Foto frente de la Licencia de Circulación del vehículo';
COMMENT ON COLUMN muevete.drivers.lic_circulacion_dorso_url  IS 'Foto dorso de la Licencia de Circulación del vehículo';
