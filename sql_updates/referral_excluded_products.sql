-- =============================================================================
-- Productos excluidos del acumulado de pago a referidos (carnavalapp)
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS carnavalapp.referral_excluded_products (
  product_id bigint PRIMARY KEY
    REFERENCES carnavalapp."Productos"(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  note text
);

COMMENT ON TABLE carnavalapp.referral_excluded_products IS
  'Productos que no acumulan para comisión de referidos. Siguen visibles en el detalle de orden.';

ALTER TABLE carnavalapp.referral_excluded_products ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS referral_excluded_products_all
  ON carnavalapp.referral_excluded_products;
CREATE POLICY referral_excluded_products_all
  ON carnavalapp.referral_excluded_products
  FOR ALL TO authenticated
  USING (true)
  WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE, DELETE
  ON carnavalapp.referral_excluded_products TO authenticated;
GRANT ALL
  ON carnavalapp.referral_excluded_products TO service_role;

COMMIT;
