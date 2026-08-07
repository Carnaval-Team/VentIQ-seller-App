-- ============================================================================
-- Carnaval Orders: quién completó + historial de estados
-- ============================================================================

ALTER TABLE carnavalapp."Orders"
  ADD COLUMN IF NOT EXISTS completado_por TEXT,
  ADD COLUMN IF NOT EXISTS completado_en TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS carnavalapp.order_status_history (
  id BIGSERIAL PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES carnavalapp."Orders"(id) ON DELETE CASCADE,
  status TEXT NOT NULL,
  changed_by TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_order_status_history_order_id
  ON carnavalapp.order_status_history (order_id, created_at DESC);

COMMENT ON COLUMN carnavalapp."Orders".completado_por IS
  'Nombre del usuario (admin/caja) que marcó la orden como Completado';
COMMENT ON COLUMN carnavalapp."Orders".completado_en IS
  'Timestamp UTC en que se marcó Completado';
COMMENT ON TABLE carnavalapp.order_status_history IS
  'Historial de cambios de status de órdenes Carnaval (desde admin/app)';

GRANT SELECT, INSERT ON carnavalapp.order_status_history TO authenticated;
GRANT SELECT, INSERT ON carnavalapp.order_status_history TO anon;
GRANT USAGE, SELECT ON SEQUENCE carnavalapp.order_status_history_id_seq TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE carnavalapp.order_status_history_id_seq TO anon;
