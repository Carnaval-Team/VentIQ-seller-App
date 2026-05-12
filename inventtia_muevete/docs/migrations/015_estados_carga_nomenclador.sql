-- ============================================================
-- Migración 015: Nomenclador de estados y bitácora de cambios
-- ============================================================
-- Sustituye el uso directo de la columna `estado` en cargas
-- por un sistema de dos tablas:
--   • app_nom_estado        → catálogo de estados válidos
--   • app_dat_estado_carga  → bitácora de cada cambio de estado
-- El estado vigente de una carga se obtiene consultando el
-- registro MÁS RECIENTE de app_dat_estado_carga para ese id.
-- ============================================================

-- ── 1. Nomenclador de estados ─────────────────────────────────
CREATE TABLE IF NOT EXISTS muevete.app_nom_estado (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo      text   NOT NULL UNIQUE,          -- 'publicada', 'aceptada', etc.
  nombre      text   NOT NULL,                 -- etiqueta visual
  descripcion text,
  orden       int    NOT NULL DEFAULT 0,       -- para ordenar en UI
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- Valores iniciales (mismos que existían en el CHECK de cargas)
INSERT INTO muevete.app_nom_estado (codigo, nombre, descripcion, orden) VALUES
  ('publicada',   'Publicada',    'Carga publicada y visible para carriers',          1),
  ('en_matching', 'En Matching',  'Sistema buscando carriers adecuados',              2),
  ('ofertada',    'Con Ofertas',  'Al menos un carrier hizo una oferta',              3),
  ('aceptada',    'Aceptada',     'Shipper aceptó una oferta, carrier asignado',      4),
  ('en_transito', 'En Tránsito',  'Carrier confirmó recogida, carga en camino',       5),
  ('entregada',   'Entregada',    'Carrier confirmó entrega en destino',              6),
  ('completada',  'Completada',   'Shipper confirmó recepción, ciclo cerrado',        7),
  ('cancelada',   'Cancelada',    'Carga cancelada por shipper o sistema',            8),
  ('disputa',     'En Disputa',   'Existe un conflicto abierto sobre esta carga',     9)
ON CONFLICT (codigo) DO NOTHING;

-- ── 2. Bitácora de cambios de estado ─────────────────────────
CREATE TABLE IF NOT EXISTS muevete.app_dat_estado_carga (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  carga_id       bigint      NOT NULL REFERENCES muevete.cargas(id) ON DELETE CASCADE,
  estado_codigo  text        NOT NULL REFERENCES muevete.app_nom_estado(codigo),
  -- Quién hizo el cambio (solo uno de los tres tendrá valor)
  usuario_uuid   uuid        REFERENCES auth.users(id),   -- auth user genérico
  driver_id      bigint      REFERENCES muevete.drivers(id),
  -- Contexto adicional
  motivo         text,                                     -- razón del cambio (opcional)
  metadata       jsonb,                                    -- datos extra libres
  created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dat_estado_carga_id
  ON muevete.app_dat_estado_carga(carga_id, created_at DESC);

-- ── 3. Vista que expone el estado vigente de cada carga ───────
-- Úsala en queries en lugar de leer la columna `estado` de cargas.
CREATE OR REPLACE VIEW muevete.v_cargas_estado_actual AS
SELECT DISTINCT ON (d.carga_id)
  d.carga_id,
  d.estado_codigo   AS estado,
  n.nombre          AS estado_nombre,
  d.usuario_uuid,
  d.driver_id,
  d.motivo,
  d.created_at      AS estado_at
FROM  muevete.app_dat_estado_carga d
JOIN  muevete.app_nom_estado       n ON n.codigo = d.estado_codigo
ORDER BY d.carga_id, d.created_at DESC;

-- ── 4. Función helper para cambiar estado (desde backend/RPC) ─
CREATE OR REPLACE FUNCTION muevete.fn_cambiar_estado_carga(
  p_carga_id      bigint,
  p_estado_codigo text,
  p_usuario_uuid  uuid    DEFAULT NULL,
  p_driver_id     bigint  DEFAULT NULL,
  p_motivo        text    DEFAULT NULL,
  p_metadata      jsonb   DEFAULT NULL
)
RETURNS muevete.app_dat_estado_carga
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_row muevete.app_dat_estado_carga;
BEGIN
  -- Validar que el código existe
  IF NOT EXISTS (
    SELECT 1 FROM muevete.app_nom_estado
    WHERE codigo = p_estado_codigo AND activo = true
  ) THEN
    RAISE EXCEPTION 'Estado no válido: %', p_estado_codigo;
  END IF;

  INSERT INTO muevete.app_dat_estado_carga
    (carga_id, estado_codigo, usuario_uuid, driver_id, motivo, metadata)
  VALUES
    (p_carga_id, p_estado_codigo, p_usuario_uuid, p_driver_id, p_motivo, p_metadata)
  RETURNING * INTO v_row;

  -- Mantener la columna estado en cargas sincronizada (compatibilidad)
  UPDATE muevete.cargas
  SET estado     = p_estado_codigo,
      updated_at = now()
  WHERE id = p_carga_id;

  RETURN v_row;
END;
$$;

-- ── 5. Migración de datos existentes ──────────────────────────
-- Insertar el estado actual de cada carga en la bitácora
-- para que el historial arranque con el estado que ya tenían.
INSERT INTO muevete.app_dat_estado_carga (carga_id, estado_codigo, motivo)
SELECT id, estado, 'Migración inicial desde columna estado'
FROM   muevete.cargas
WHERE  NOT EXISTS (
  SELECT 1 FROM muevete.app_dat_estado_carga e
  WHERE e.carga_id = muevete.cargas.id
);

-- ── 6. RLS básico ─────────────────────────────────────────────
ALTER TABLE muevete.app_nom_estado        ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.app_dat_estado_carga  ENABLE ROW LEVEL SECURITY;

-- Nomenclador: lectura pública para usuarios autenticados
CREATE POLICY "nom_estado_read" ON muevete.app_nom_estado
  FOR SELECT TO authenticated USING (true);

-- Bitácora: sólo backend (service_role) puede insertar;
-- lectura para participantes de la carga (shipper o carrier asignado).
CREATE POLICY "dat_estado_insert_service" ON muevete.app_dat_estado_carga
  FOR INSERT TO service_role WITH CHECK (true);

CREATE POLICY "dat_estado_select_participantes" ON muevete.app_dat_estado_carga
  FOR SELECT TO authenticated
  USING (
    -- El shipper de la carga
    EXISTS (
      SELECT 1 FROM muevete.cargas c
      WHERE c.id = carga_id
        AND c.shipper_id = auth.uid()
    )
    OR
    -- El carrier asignado (a través de su driver)
    EXISTS (
      SELECT 1 FROM muevete.cargas c
      JOIN  muevete.drivers d ON d.id = c.carrier_driver_id
      WHERE c.id = carga_id
        AND d.uuid = auth.uid()
    )
  );
