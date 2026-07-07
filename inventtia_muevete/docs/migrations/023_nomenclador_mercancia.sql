-- ─────────────────────────────────────────────────────────────────────────────
-- Migración 023 – Nomenclador de tipo de mercancía
-- Crea app_nom_tipo_mercancia y migra cargas.tipo_mercancia (text) +
-- cargas.commodity_id (integer sin FK) → cargas.tipo_mercancia_id (FK).
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Tabla nomenclador ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS muevete.app_nom_tipo_mercancia (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre       text   NOT NULL,
  descripcion  text,
  -- código corto para filtros / APIs (ej: 'DRY_GOODS', 'PERISHABLE', 'HAZMAT')
  codigo       text   NOT NULL UNIQUE,
  -- código NMFC estándar US (opcional, para interoperabilidad con Truckstop/DAT)
  nmfc_codigo  text,
  activo       boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE  muevete.app_nom_tipo_mercancia                IS 'Nomenclador de tipos de mercancía (reemplaza tipo_mercancia text + commodity_id sin FK)';
COMMENT ON COLUMN muevete.app_nom_tipo_mercancia.codigo         IS 'Código corto interno para filtros';
COMMENT ON COLUMN muevete.app_nom_tipo_mercancia.nmfc_codigo    IS 'Código NMFC estándar (National Motor Freight Classification)';

-- ── 2. Seed de tipos estándar ─────────────────────────────────────────────────
INSERT INTO muevete.app_nom_tipo_mercancia (nombre, descripcion, codigo, nmfc_codigo) VALUES
  ('Bienes secos',         'Mercancía seca general sin requerimientos especiales',       'DRY_GOODS',    '100'),
  ('Perecederos',          'Alimentos y mercancía que requiere cadena de frío',          'PERISHABLE',   '145'),
  ('Materiales peligrosos','Mercancía que requiere manejo especial por riesgo (HAZMAT)', 'HAZMAT',       '060'),
  ('Automotriz',           'Piezas, repuestos y vehículos',                              'AUTOMOTIVE',   '049'),
  ('Construcción',         'Materiales de construcción: cemento, varilla, acero, etc.',  'CONSTRUCTION', '055'),
  ('Electrónica',          'Equipos y componentes electrónicos',                         'ELECTRONICS',  '110'),
  ('Maquinaria',           'Equipos industriales y maquinaria pesada',                   'MACHINERY',    '120'),
  ('Químicos',             'Productos químicos no peligrosos',                           'CHEMICALS',    '085'),
  ('Textil / Ropa',        'Prendas, telas y accesorios',                               'TEXTILE',      '150'),
  ('Farmacéuticos',        'Medicamentos y productos de salud',                          'PHARMA',       '135'),
  ('Agrícola / Granos',    'Granos, semillas y productos del campo',                     'AGRICULTURE',  '040'),
  ('Animales vivos',       'Transporte de animales',                                     'LIVESTOCK',    '070'),
  ('Artículos del hogar',  'Muebles y enseres del hogar',                               'HOUSEHOLD',    '100'),
  ('Tecnología',           'Servidores, equipos IT y telecomunicaciones',                'TECHNOLOGY',   '110'),
  ('Otro',                 'Tipo de mercancía no listado',                               'OTHER',        NULL)
ON CONFLICT (codigo) DO NOTHING;

-- ── 3. Agregar FK en cargas ───────────────────────────────────────────────────
ALTER TABLE muevete.cargas
  ADD COLUMN IF NOT EXISTS tipo_mercancia_id bigint
    REFERENCES muevete.app_nom_tipo_mercancia(id);

COMMENT ON COLUMN muevete.cargas.tipo_mercancia_id IS 'FK a app_nom_tipo_mercancia — reemplaza tipo_mercancia text + commodity_id';

-- ── 4. Migrar datos existentes ────────────────────────────────────────────────
-- Intenta mapear tipo_mercancia text existente al nuevo nomenclador (best-effort)
UPDATE muevete.cargas c
SET tipo_mercancia_id = n.id
FROM muevete.app_nom_tipo_mercancia n
WHERE c.tipo_mercancia_id IS NULL
  AND c.tipo_mercancia IS NOT NULL
  AND lower(c.tipo_mercancia) = lower(n.nombre);

-- Los que no matchearon se les asigna 'OTHER' temporalmente
UPDATE muevete.cargas
SET tipo_mercancia_id = (SELECT id FROM muevete.app_nom_tipo_mercancia WHERE codigo = 'OTHER')
WHERE tipo_mercancia_id IS NULL
  AND tipo_mercancia IS NOT NULL;

-- ── 5. Deprecar columnas antiguas (NO DROP — dar tiempo a RPCs) ───────────────
COMMENT ON COLUMN muevete.cargas.tipo_mercancia IS 'DEPRECATED: reemplazado por tipo_mercancia_id FK → app_nom_tipo_mercancia';
COMMENT ON COLUMN muevete.cargas.commodity_id   IS 'DEPRECATED: sustituido por tipo_mercancia_id. El campo nmfc_codigo queda en el nomenclador';

-- ── 6. RLS para app_nom_tipo_mercancia ────────────────────────────────────────
ALTER TABLE muevete.app_nom_tipo_mercancia ENABLE ROW LEVEL SECURITY;

-- Lectura pública (todos los usuarios autenticados)
CREATE POLICY "read_tipo_mercancia" ON muevete.app_nom_tipo_mercancia
  FOR SELECT USING (auth.role() = 'authenticated');

-- Solo service_role puede insertar/actualizar
CREATE POLICY "admin_tipo_mercancia" ON muevete.app_nom_tipo_mercancia
  FOR ALL USING (auth.role() = 'service_role');
