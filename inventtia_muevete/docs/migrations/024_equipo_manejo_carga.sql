-- ─────────────────────────────────────────────────────────────────────────────
-- Migración 024 – Nomenclador de opciones de manejo/equipo adicional para cargas
-- Crea app_nom_equipo_manejo_carga (nomenclador) +
--      cargas_equipo_manejo (pivot M:N) y migra opciones_equipo text[] existente.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Tabla nomenclador ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS muevete.app_nom_equipo_manejo_carga (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre      text   NOT NULL,
  descripcion text,
  -- código corto para filtros / APIs (ej: 'LIFTGATE', 'TEAM_DRIVER')
  codigo      text   NOT NULL UNIQUE,
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE  muevete.app_nom_equipo_manejo_carga         IS 'Nomenclador de opciones adicionales de equipo/manejo para cargas (liftgate, reefer, etc.)';
COMMENT ON COLUMN muevete.app_nom_equipo_manejo_carga.codigo  IS 'Código corto interno para filtros y APIs';

-- ── 2. Seed de opciones estándar ──────────────────────────────────────────────
INSERT INTO muevete.app_nom_equipo_manejo_carga (nombre, descripcion, codigo) VALUES
  ('Liftgate',            'Plataforma elevadora en el camión para carga sin muelle',          'LIFTGATE'),
  ('Devolución de palet', 'El carrier devuelve los paletas vacíos al origen',                 'PALLET_RETURN'),
  ('Conductor en equipo', 'Requiere dos conductores (team driver) para servicio continuo',    'TEAM_DRIVER'),
  ('Embalaje en manta',   'La carga se protege con mantas (blanket wrap)',                    'BLANKET_WRAP'),
  ('Lonas / toldos',      'Se requieren lonas para proteger la carga en plataforma abierta',  'TARPS'),
  ('Cinchos / straps',    'Sujeción adicional con cintas o straps',                           'STRAPS'),
  ('Temperatura controlada', 'Requiere unidad reefer para control de temperatura',            'REEFER'),
  ('Carga sobredimensionada', 'Carga que excede dimensiones estándar (wide/oversize load)',   'OVERSIZE'),
  ('Materiales peligrosos', 'Requiere placas HAZMAT y conductor certificado',                 'HAZMAT_EQUIP'),
  ('Descarga asistida',   'El carrier asiste en la descarga en destino',                      'ASSISTED_UNLOAD')
ON CONFLICT (codigo) DO NOTHING;

-- ── 3. Tabla pivot M:N ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS muevete.cargas_equipo_manejo (
  carga_id            bigint NOT NULL REFERENCES muevete.cargas(id) ON DELETE CASCADE,
  equipo_manejo_id    bigint NOT NULL REFERENCES muevete.app_nom_equipo_manejo_carga(id),
  created_at          timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT cargas_equipo_manejo_pkey PRIMARY KEY (carga_id, equipo_manejo_id)
);

COMMENT ON TABLE muevete.cargas_equipo_manejo IS 'Relación M:N entre cargas y opciones de equipo/manejo adicional';

-- ── 4. Migrar datos existentes desde opciones_equipo text[] ───────────────────
-- Mapea cada valor de texto al código correspondiente del nomenclador
-- (unnest no está permitido en JOIN ON; se usa CROSS JOIN LATERAL)
INSERT INTO muevete.cargas_equipo_manejo (carga_id, equipo_manejo_id)
SELECT c.id, n.id
FROM muevete.cargas c
CROSS JOIN LATERAL unnest(c.opciones_equipo) AS opcion(codigo)
JOIN muevete.app_nom_equipo_manejo_carga n
  ON n.codigo = upper(opcion.codigo)
WHERE c.opciones_equipo IS NOT NULL
  AND array_length(c.opciones_equipo, 1) > 0
ON CONFLICT DO NOTHING;

-- ── 5. Deprecar columna antigua (NO DROP) ────────────────────────────────────
COMMENT ON COLUMN muevete.cargas.opciones_equipo IS 'DEPRECATED: reemplazado por relación M:N cargas_equipo_manejo → app_nom_equipo_manejo_carga';

-- ── 6. RLS ────────────────────────────────────────────────────────────────────
ALTER TABLE muevete.app_nom_equipo_manejo_carga ENABLE ROW LEVEL SECURITY;

CREATE POLICY "read_equipo_manejo" ON muevete.app_nom_equipo_manejo_carga
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "admin_equipo_manejo" ON muevete.app_nom_equipo_manejo_carga
  FOR ALL USING (auth.role() = 'service_role');

ALTER TABLE muevete.cargas_equipo_manejo ENABLE ROW LEVEL SECURITY;

-- El shipper puede ver/gestionar las opciones de sus propias cargas
CREATE POLICY "shipper_equipo_manejo" ON muevete.cargas_equipo_manejo
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM muevete.cargas
      WHERE id = carga_id AND shipper_id = auth.uid()
    )
  );

-- Carriers y carriers por uuid pueden leer opciones de las cargas que gestionan
CREATE POLICY "carrier_read_equipo_manejo" ON muevete.cargas_equipo_manejo
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM muevete.cargas
      WHERE id = carga_id
        AND (carrier_uuid = auth.uid() OR shipper_id = auth.uid())
    )
  );

CREATE POLICY "service_equipo_manejo" ON muevete.cargas_equipo_manejo
  FOR ALL USING (auth.role() = 'service_role');
