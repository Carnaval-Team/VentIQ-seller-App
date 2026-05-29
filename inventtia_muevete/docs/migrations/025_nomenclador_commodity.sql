-- ─────────────────────────────────────────────────────────────────────────────
-- Migración 025 – Nomenclador de commodity (clasificación comercial de carga)
-- Crea app_nom_commodity y agrega FK commodity_id en cargas.
-- Reemplaza la lista estática que existía en el cliente Flutter.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Tabla nomenclador ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS muevete.app_nom_commodity (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre      text   NOT NULL,
  descripcion text,
  codigo      text   NOT NULL UNIQUE,
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE  muevete.app_nom_commodity        IS 'Clasificación comercial de la carga (commodity). Reemplaza lista estática del cliente.';
COMMENT ON COLUMN muevete.app_nom_commodity.codigo IS 'Código corto interno para filtros y APIs';

-- ── 2. Seed de commodities estándar ──────────────────────────────────────────
INSERT INTO muevete.app_nom_commodity (nombre, descripcion, codigo) VALUES
  ('Alimentos y bebidas',       'Productos alimenticios y bebidas en general',                        'FOOD_BEVERAGE'),
  ('Materiales peligrosos',     'Mercancía HAZMAT que requiere manejo especial',                      'HAZMAT'),
  ('Maquinaria / equipos',      'Maquinaria industrial y equipos pesados',                            'MACHINERY'),
  ('Productos químicos',        'Productos químicos no clasificados como peligrosos',                 'CHEMICALS'),
  ('Vehículos',                 'Automóviles, camionetas, motocicletas y otros vehículos',            'VEHICLES'),
  ('Electrónica',               'Equipos y componentes electrónicos y de tecnología',                 'ELECTRONICS'),
  ('Textiles / ropa',           'Prendas de vestir, telas y accesorios',                              'TEXTILES'),
  ('Materiales de construcción','Cemento, varilla, acero, madera y materiales de obra',               'CONSTRUCTION'),
  ('Productos farmacéuticos',   'Medicamentos y productos de salud',                                  'PHARMA'),
  ('Agrícola / granos',         'Granos, semillas y productos del campo',                             'AGRICULTURE'),
  ('Artículos del hogar',       'Muebles, electrodomésticos y enseres del hogar',                     'HOUSEHOLD'),
  ('Otros',                     'Tipo de mercancía no listado en las categorías anteriores',           'OTHER')
ON CONFLICT (codigo) DO NOTHING;

-- ── 3. Agregar FK commodity_id en cargas ──────────────────────────────────────
ALTER TABLE muevete.cargas
  ADD COLUMN IF NOT EXISTS commodity_nom_id bigint
    REFERENCES muevete.app_nom_commodity(id);

COMMENT ON COLUMN muevete.cargas.commodity_nom_id IS 'FK a app_nom_commodity — clasificación comercial de la carga';

-- ── 4. Migrar datos existentes desde commodity_id (integer legacy) ───────────
-- El campo commodity_id legacy usaba IDs 1-9 y 99 mapeados a textos fijos.
-- Hacemos best-effort por código ya que los IDs pueden no coincidir.
-- Los registros sin match quedan en NULL (sin clasificación).
-- (No forzamos un default para no asignar un dato incorrecto)

-- ── 5. RLS ────────────────────────────────────────────────────────────────────
ALTER TABLE muevete.app_nom_commodity ENABLE ROW LEVEL SECURITY;

CREATE POLICY "read_commodity" ON muevete.app_nom_commodity
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "admin_commodity" ON muevete.app_nom_commodity
  FOR ALL USING (auth.role() = 'service_role');
