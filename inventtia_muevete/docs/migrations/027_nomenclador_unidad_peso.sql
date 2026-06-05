-- ─────────────────────────────────────────────────────────────────────────────
-- Migración 027 – Nomenclador de unidades de peso + peso_valor en cargas
-- peso_kg = valor canónico en kilogramos (filtros/comparaciones)
-- peso_valor = valor ingresado en la unidad seleccionada (visualización)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS muevete.app_nom_unidad_peso (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre        text    NOT NULL,
  simbolo       text    NOT NULL,
  codigo        text    NOT NULL UNIQUE,
  factor_a_kg   numeric(18, 8) NOT NULL CHECK (factor_a_kg > 0),
  activo        boolean NOT NULL DEFAULT true,
  orden         int     NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE  muevete.app_nom_unidad_peso IS 'Unidades de peso para cargas. factor_a_kg convierte 1 unidad → kg.';
COMMENT ON COLUMN muevete.app_nom_unidad_peso.factor_a_kg IS 'Multiplicador: peso_kg = peso_valor * factor_a_kg';

INSERT INTO muevete.app_nom_unidad_peso (nombre, simbolo, codigo, factor_a_kg, orden) VALUES
  ('Kilogramo',  'kg',  'KG',  1,              1),
  ('Tonelada',   't',   'TON', 1000,           2),
  ('Libra',      'lb',  'LB',  0.45359237,     3)
ON CONFLICT (codigo) DO NOTHING;

ALTER TABLE muevete.cargas
  ADD COLUMN IF NOT EXISTS unidad_peso_id bigint
    REFERENCES muevete.app_nom_unidad_peso(id),
  ADD COLUMN IF NOT EXISTS peso_valor numeric(14, 4);

COMMENT ON COLUMN muevete.cargas.peso_valor IS 'Peso en la unidad elegida (unidad_peso_id). No convertir al mostrar.';
COMMENT ON COLUMN muevete.cargas.peso_kg IS 'Peso normalizado en kg: peso_valor * factor_a_kg';
COMMENT ON COLUMN muevete.cargas.unidad_peso IS 'DEPRECATED: usar unidad_peso_id. Se mantiene por compatibilidad.';

-- Migrar filas existentes
UPDATE muevete.cargas c
SET
  unidad_peso_id = COALESCE(
    c.unidad_peso_id,
    (SELECT id FROM muevete.app_nom_unidad_peso WHERE codigo = 'TON' LIMIT 1)
  ),
  peso_valor = CASE
    WHEN c.peso_kg IS NULL THEN NULL
    WHEN c.unidad_peso = 'tonelada' THEN c.peso_kg / 1000.0
    ELSE c.peso_kg
  END
WHERE c.peso_kg IS NOT NULL
  AND c.peso_valor IS NULL
  AND c.unidad_peso = 'tonelada';

UPDATE muevete.cargas c
SET
  unidad_peso_id = COALESCE(
    c.unidad_peso_id,
    (SELECT id FROM muevete.app_nom_unidad_peso WHERE codigo = 'KG' LIMIT 1)
  ),
  peso_valor = c.peso_kg
WHERE c.peso_kg IS NOT NULL
  AND c.peso_valor IS NULL
  AND (c.unidad_peso IS NULL OR c.unidad_peso = 'kg');

-- Sincronizar peso_kg desde valor + nomenclador (corrige datos inconsistentes)
UPDATE muevete.cargas c
SET peso_kg = ROUND((c.peso_valor * u.factor_a_kg)::numeric, 4)
FROM muevete.app_nom_unidad_peso u
WHERE c.peso_valor IS NOT NULL
  AND c.unidad_peso_id = u.id;

ALTER TABLE muevete.app_nom_unidad_peso ENABLE ROW LEVEL SECURITY;

CREATE POLICY "read_unidad_peso" ON muevete.app_nom_unidad_peso
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "admin_unidad_peso" ON muevete.app_nom_unidad_peso
  FOR ALL USING (auth.role() = 'service_role');
