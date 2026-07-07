-- Licencias: operativa en drivers (choferes pasaje) y por vehículo en carrocerías (carrier).

ALTER TABLE muevete.drivers
  ADD COLUMN IF NOT EXISTS lic_operativa_frente_url text,
  ADD COLUMN IF NOT EXISTS lic_operativa_dorso_url  text;

COMMENT ON COLUMN muevete.drivers.lic_operativa_frente_url IS 'Licencia operativa del conductor (opcional, choferes de pasaje)';
COMMENT ON COLUMN muevete.drivers.lic_operativa_dorso_url  IS 'Dorso licencia operativa del conductor (opcional)';

ALTER TABLE muevete.carrocerias
  ADD COLUMN IF NOT EXISTS lic_circulacion_frente_url text,
  ADD COLUMN IF NOT EXISTS lic_circulacion_dorso_url  text,
  ADD COLUMN IF NOT EXISTS lic_operativa_frente_url    text,
  ADD COLUMN IF NOT EXISTS lic_operativa_dorso_url     text;

COMMENT ON COLUMN muevete.carrocerias.lic_circulacion_frente_url IS 'Licencia de circulación del vehículo (frente)';
COMMENT ON COLUMN muevete.carrocerias.lic_circulacion_dorso_url  IS 'Licencia de circulación del vehículo (dorso)';
COMMENT ON COLUMN muevete.carrocerias.lic_operativa_frente_url   IS 'Licencia operativa del vehículo (opcional, frente)';
COMMENT ON COLUMN muevete.carrocerias.lic_operativa_dorso_url    IS 'Licencia operativa del vehículo (opcional, dorso)';
