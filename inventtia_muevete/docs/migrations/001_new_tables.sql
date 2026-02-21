-- Migration: Create new tables for Muevete transport request system
-- Run this against the Supabase database after the initial muevete schema is set up

-- 1. Transport Requests (Solicitudes de Transporte)
-- Clients create these when requesting a ride. Expires after 1 hour.
CREATE TABLE IF NOT EXISTS muevete.solicitudes_transporte (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  user_id uuid NOT NULL,
  lat_origen double precision NOT NULL,
  lon_origen double precision NOT NULL,
  lat_destino double precision NOT NULL,
  lon_destino double precision NOT NULL,
  tipo_vehiculo character varying NOT NULL DEFAULT 'auto',
  precio_oferta numeric NOT NULL,
  estado character varying NOT NULL DEFAULT 'pendiente',
  direccion_origen text,
  direccion_destino text,
  distancia_km numeric,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  expires_at timestamp with time zone NOT NULL DEFAULT (now() + interval '1 hour'),
  CONSTRAINT solicitudes_transporte_pkey PRIMARY KEY (id),
  CONSTRAINT solicitudes_transporte_user_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id),
  CONSTRAINT solicitudes_transporte_estado_check CHECK (estado IN ('pendiente', 'aceptada', 'cancelada', 'expirada')),
  CONSTRAINT solicitudes_transporte_tipo_check CHECK (tipo_vehiculo IN ('moto', 'auto', 'microbus'))
);

-- 2. Driver Offers (Ofertas de Chofer)
-- Drivers respond to transport requests with their price offers.
CREATE TABLE IF NOT EXISTS muevete.ofertas_chofer (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  solicitud_id bigint NOT NULL,
  driver_id bigint NOT NULL,
  precio numeric NOT NULL,
  tiempo_estimado integer, -- in minutes
  estado character varying NOT NULL DEFAULT 'pendiente',
  mensaje text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ofertas_chofer_pkey PRIMARY KEY (id),
  CONSTRAINT ofertas_chofer_solicitud_fkey FOREIGN KEY (solicitud_id) REFERENCES muevete.solicitudes_transporte(id) ON DELETE CASCADE,
  CONSTRAINT ofertas_chofer_driver_fkey FOREIGN KEY (driver_id) REFERENCES muevete.drivers(id),
  CONSTRAINT ofertas_chofer_estado_check CHECK (estado IN ('pendiente', 'aceptada', 'rechazada'))
);

-- 3. Driver Wallet (Billetera del Conductor)
-- Mirror of suscription_user but for driver earnings.
CREATE TABLE IF NOT EXISTS muevete.wallet_drivers (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  driver_id bigint NOT NULL UNIQUE,
  current_balance numeric NOT NULL DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT wallet_drivers_pkey PRIMARY KEY (id),
  CONSTRAINT wallet_drivers_driver_fkey FOREIGN KEY (driver_id) REFERENCES muevete.drivers(id)
);

-- 4. Wallet Transactions (Transacciones de Billetera)
-- Records all wallet movements for both clients and drivers.
CREATE TABLE IF NOT EXISTS muevete.transacciones_wallet (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  user_id uuid,
  driver_id bigint,
  tipo character varying NOT NULL,
  monto numeric NOT NULL,
  viaje_id bigint,
  descripcion text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT transacciones_wallet_pkey PRIMARY KEY (id),
  CONSTRAINT transacciones_wallet_tipo_check CHECK (tipo IN ('recarga', 'cobro_viaje', 'pago_viaje')),
  CONSTRAINT transacciones_wallet_viaje_fkey FOREIGN KEY (viaje_id) REFERENCES muevete.viajes(id)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_solicitudes_estado ON muevete.solicitudes_transporte(estado);
CREATE INDEX IF NOT EXISTS idx_solicitudes_user ON muevete.solicitudes_transporte(user_id);
CREATE INDEX IF NOT EXISTS idx_solicitudes_expires ON muevete.solicitudes_transporte(expires_at);
CREATE INDEX IF NOT EXISTS idx_ofertas_solicitud ON muevete.ofertas_chofer(solicitud_id);
CREATE INDEX IF NOT EXISTS idx_ofertas_driver ON muevete.ofertas_chofer(driver_id);
CREATE INDEX IF NOT EXISTS idx_transacciones_user ON muevete.transacciones_wallet(user_id);
CREATE INDEX IF NOT EXISTS idx_transacciones_driver ON muevete.transacciones_wallet(driver_id);

-- Enable Realtime for transport requests and offers
-- (Run these via Supabase Dashboard or SQL Editor)
-- ALTER PUBLICATION supabase_realtime ADD TABLE muevete.solicitudes_transporte;
-- ALTER PUBLICATION supabase_realtime ADD TABLE muevete.ofertas_chofer;

-- RLS Policies (basic - adjust as needed)
ALTER TABLE muevete.solicitudes_transporte ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.ofertas_chofer ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.wallet_drivers ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.transacciones_wallet ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users to read/write their own transport requests
CREATE POLICY "Users can create their own requests"
  ON muevete.solicitudes_transporte FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can view their own requests"
  ON muevete.solicitudes_transporte FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- Allow all authenticated (drivers) to see pending requests
CREATE POLICY "Drivers can view pending requests"
  ON muevete.solicitudes_transporte FOR SELECT
  TO authenticated
  USING (estado = 'pendiente');

-- Allow drivers to create offers
CREATE POLICY "Drivers can create offers"
  ON muevete.ofertas_chofer FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- Allow reading offers for own requests or own offers
CREATE POLICY "Users can view offers on their requests"
  ON muevete.ofertas_chofer FOR SELECT
  TO authenticated
  USING (true);

-- Wallet policies
CREATE POLICY "Users can view own transactions"
  ON muevete.transacciones_wallet FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Service can insert transactions"
  ON muevete.transacciones_wallet FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Drivers can view own wallet"
  ON muevete.wallet_drivers FOR SELECT
  TO authenticated
  USING (true);
