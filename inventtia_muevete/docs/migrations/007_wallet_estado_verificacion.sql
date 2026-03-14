-- Migration: Add estado column to transacciones_wallet + verificacion_operacion_recarga table
-- This supports the new pending recharge flow where recargas stay pending until admin approval.

-- 1. Add 'estado' column to transacciones_wallet (default 'completada' for existing rows)
ALTER TABLE muevete.transacciones_wallet
  ADD COLUMN IF NOT EXISTS estado character varying NOT NULL DEFAULT 'completada';

-- 2. Update tipo CHECK constraint to include new transaction types
ALTER TABLE muevete.transacciones_wallet
  DROP CONSTRAINT IF EXISTS transacciones_wallet_tipo_check;

ALTER TABLE muevete.transacciones_wallet
  ADD CONSTRAINT transacciones_wallet_tipo_check
  CHECK (tipo IN ('recarga', 'cobro_viaje', 'pago_viaje', 'reembolso', 'comision_viaje'));

-- 3. Add estado CHECK constraint
ALTER TABLE muevete.transacciones_wallet
  ADD CONSTRAINT transacciones_wallet_estado_check
  CHECK (estado IN ('pendiente', 'aceptada', 'cancelada', 'completada'));

-- 4. Add balance_despues column for audit trail
ALTER TABLE muevete.transacciones_wallet
  ADD COLUMN IF NOT EXISTS balance_despues numeric;

-- 5. Create verificacion_operacion_recarga table
CREATE TABLE IF NOT EXISTS muevete.verificacion_operacion_recarga (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  transaccion_id bigint NOT NULL,
  imagen_url text,
  detalle_texto text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT verificacion_operacion_recarga_pkey PRIMARY KEY (id),
  CONSTRAINT verificacion_operacion_recarga_tx_fkey
    FOREIGN KEY (transaccion_id) REFERENCES muevete.transacciones_wallet(id) ON DELETE CASCADE
);

-- Index for fast lookup by transaction
CREATE INDEX IF NOT EXISTS idx_verificacion_transaccion
  ON muevete.verificacion_operacion_recarga(transaccion_id);

-- Index for filtering pending transactions
CREATE INDEX IF NOT EXISTS idx_transacciones_estado
  ON muevete.transacciones_wallet(estado);

-- 6. RLS for verificacion table
ALTER TABLE muevete.verificacion_operacion_recarga ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can insert verification"
  ON muevete.verificacion_operacion_recarga FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Users can view own verifications"
  ON muevete.verificacion_operacion_recarga FOR SELECT
  TO authenticated
  USING (true);
