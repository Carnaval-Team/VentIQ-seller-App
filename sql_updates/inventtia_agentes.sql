-- =============================================================================
-- Agentes Inventtia con N tiendas Carnaval (proveedores)
-- Comisión: 1% de las ventas sumadas de sus tiendas (se calcula en app).
-- Productos en referral_excluded_products no acumulan (igual que referidos).
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS carnavalapp.inventtia_agentes (
  id bigserial PRIMARY KEY,
  nombre text NOT NULL,
  apellidos text NOT NULL,
  activo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Si existía la versión con un solo proveedor_id, migrar a N:N
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'carnavalapp'
      AND table_name = 'inventtia_agentes'
      AND column_name = 'proveedor_id'
  ) THEN
    CREATE TABLE IF NOT EXISTS carnavalapp.inventtia_agente_tiendas (
      agente_id bigint NOT NULL
        REFERENCES carnavalapp.inventtia_agentes(id) ON DELETE CASCADE,
      proveedor_id bigint NOT NULL
        REFERENCES carnavalapp.proveedores(id) ON DELETE RESTRICT,
      PRIMARY KEY (agente_id, proveedor_id)
    );

    INSERT INTO carnavalapp.inventtia_agente_tiendas (agente_id, proveedor_id)
    SELECT id, proveedor_id
    FROM carnavalapp.inventtia_agentes
    WHERE proveedor_id IS NOT NULL
    ON CONFLICT DO NOTHING;

    ALTER TABLE carnavalapp.inventtia_agentes DROP COLUMN proveedor_id;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS carnavalapp.inventtia_agente_tiendas (
  agente_id bigint NOT NULL
    REFERENCES carnavalapp.inventtia_agentes(id) ON DELETE CASCADE,
  proveedor_id bigint NOT NULL
    REFERENCES carnavalapp.proveedores(id) ON DELETE RESTRICT,
  PRIMARY KEY (agente_id, proveedor_id)
);

CREATE INDEX IF NOT EXISTS inventtia_agente_tiendas_proveedor_idx
  ON carnavalapp.inventtia_agente_tiendas (proveedor_id);

CREATE INDEX IF NOT EXISTS inventtia_agentes_activo_idx
  ON carnavalapp.inventtia_agentes (activo)
  WHERE activo = true;

COMMENT ON TABLE carnavalapp.inventtia_agentes IS
  'Agentes Inventtia. Cobran % sobre la suma de ventas de sus tiendas asociadas.';
COMMENT ON TABLE carnavalapp.inventtia_agente_tiendas IS
  'Tiendas (proveedores Carnaval) asociadas a un agente.';

ALTER TABLE carnavalapp.inventtia_agentes ENABLE ROW LEVEL SECURITY;
ALTER TABLE carnavalapp.inventtia_agente_tiendas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS inventtia_agentes_all ON carnavalapp.inventtia_agentes;
CREATE POLICY inventtia_agentes_all
  ON carnavalapp.inventtia_agentes
  FOR ALL TO authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS inventtia_agente_tiendas_all ON carnavalapp.inventtia_agente_tiendas;
CREATE POLICY inventtia_agente_tiendas_all
  ON carnavalapp.inventtia_agente_tiendas
  FOR ALL TO authenticated
  USING (true)
  WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE, DELETE
  ON carnavalapp.inventtia_agentes TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON carnavalapp.inventtia_agente_tiendas TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE carnavalapp.inventtia_agentes_id_seq TO authenticated;
GRANT ALL ON carnavalapp.inventtia_agentes TO service_role;
GRANT ALL ON carnavalapp.inventtia_agente_tiendas TO service_role;
GRANT ALL ON SEQUENCE carnavalapp.inventtia_agentes_id_seq TO service_role;

COMMIT;
