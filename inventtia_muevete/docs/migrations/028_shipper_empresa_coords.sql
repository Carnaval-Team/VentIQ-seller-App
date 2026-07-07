-- Migration 028: Add latitude/longitude columns for shipper company location
-- These are set optionally when the user taps the map during registration.

ALTER TABLE muevete.users
  ADD COLUMN IF NOT EXISTS emp_lat  double precision,
  ADD COLUMN IF NOT EXISTS emp_lng  double precision;

COMMENT ON COLUMN muevete.users.emp_lat IS 'Latitud de la ubicación de la empresa (opcional)';
COMMENT ON COLUMN muevete.users.emp_lng IS 'Longitud de la ubicación de la empresa (opcional)';
