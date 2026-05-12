-- ─────────────────────────────────────────────────────────────────────────────
-- Migración 014 – Campos Truckstop en muevete.cargas
-- Agrega: código postal, nombre ubicación, contacto por punto,
--         commodity_id, opciones_equipo, numeros_referencia,
--         es_privada, horas_anticipacion_publica
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Ubicación origen ─────────────────────────────────────────────────────────
ALTER TABLE muevete.cargas
  ADD COLUMN IF NOT EXISTS nombre_ubicacion_origen   text,
  ADD COLUMN IF NOT EXISTS cp_origen                 text,
  ADD COLUMN IF NOT EXISTS contacto_origen_nombre    text,
  ADD COLUMN IF NOT EXISTS contacto_origen_tel       text;

-- ── Ubicación destino ────────────────────────────────────────────────────────
ALTER TABLE muevete.cargas
  ADD COLUMN IF NOT EXISTS nombre_ubicacion_destino  text,
  ADD COLUMN IF NOT EXISTS cp_destino                text,
  ADD COLUMN IF NOT EXISTS contacto_destino_nombre   text,
  ADD COLUMN IF NOT EXISTS contacto_destino_tel      text;

-- ── Mercancía y equipo ───────────────────────────────────────────────────────
ALTER TABLE muevete.cargas
  ADD COLUMN IF NOT EXISTS commodity_id              integer,
  ADD COLUMN IF NOT EXISTS opciones_equipo           text[]    DEFAULT '{}';

-- ── Comercial ────────────────────────────────────────────────────────────────
ALTER TABLE muevete.cargas
  ADD COLUMN IF NOT EXISTS numeros_referencia        text[]    DEFAULT '{}';

-- ── Privacidad y alcance ─────────────────────────────────────────────────────
ALTER TABLE muevete.cargas
  ADD COLUMN IF NOT EXISTS es_privada                boolean   NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS horas_anticipacion_publica integer;

-- ── Comentario descriptivo ───────────────────────────────────────────────────
COMMENT ON COLUMN muevete.cargas.nombre_ubicacion_origen    IS 'Nombre del lugar de recogida (ej: Almacén Central)';
COMMENT ON COLUMN muevete.cargas.cp_origen                  IS 'Código postal del punto de origen';
COMMENT ON COLUMN muevete.cargas.contacto_origen_nombre     IS 'Persona de contacto en el punto de origen';
COMMENT ON COLUMN muevete.cargas.contacto_origen_tel        IS 'Teléfono del contacto en origen';
COMMENT ON COLUMN muevete.cargas.nombre_ubicacion_destino   IS 'Nombre del lugar de entrega';
COMMENT ON COLUMN muevete.cargas.cp_destino                 IS 'Código postal del punto de destino';
COMMENT ON COLUMN muevete.cargas.contacto_destino_nombre    IS 'Persona de contacto en el punto de destino';
COMMENT ON COLUMN muevete.cargas.contacto_destino_tel       IS 'Teléfono del contacto en destino';
COMMENT ON COLUMN muevete.cargas.commodity_id               IS 'ID de clasificación de mercancía (estándar Truckstop/NMFC)';
COMMENT ON COLUMN muevete.cargas.opciones_equipo            IS 'Opciones adicionales de equipo: liftgate, pallet_return, team_driver, etc.';
COMMENT ON COLUMN muevete.cargas.numeros_referencia         IS 'Números de referencia internos del broker/shipper';
COMMENT ON COLUMN muevete.cargas.es_privada                 IS 'Si true, la carga solo es visible para carriers pre-aprobados';
COMMENT ON COLUMN muevete.cargas.horas_anticipacion_publica IS 'Horas antes de la recogida para pasar de privada a pública automáticamente';
