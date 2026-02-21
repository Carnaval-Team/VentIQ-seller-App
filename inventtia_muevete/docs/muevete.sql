-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

CREATE TABLE muevete.configuracion_navegacion (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  precio_x_km numeric,
  tiempo_espera_driver integer,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT configuracion_navegacion_pkey PRIMARY KEY (id)
);
CREATE TABLE muevete.drivers (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  name text,
  email character varying UNIQUE,
  telefono character varying,
  estado boolean NOT NULL DEFAULT false,
  kyc boolean DEFAULT false,
  image character varying DEFAULT 'https://hiviparyarodbcnmcjli.supabase.co/storage/v1/object/public/drivers/perfil/1727132569606711.jpg'::character varying,
  vehiculo bigint,
  categoria character varying,
  circulacion character varying,
  carnet character varying,
  licencia character varying,
  revisado boolean DEFAULT false,
  motivo text,
  uuid uuid,
  CONSTRAINT drivers_pkey PRIMARY KEY (id),
  CONSTRAINT drivers_uuid_fkey FOREIGN KEY (uuid) REFERENCES auth.users(id),
  CONSTRAINT drivers_vehiculo_fkey FOREIGN KEY (vehiculo) REFERENCES muevete.vehiculos(id)
);
CREATE TABLE muevete.place (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  latitude double precision DEFAULT '22.406959'::double precision,
  longitude double precision DEFAULT '-79.965681'::double precision,
  image_url character varying DEFAULT 'https://hiviparyarodbcnmcjli.supabase.co/storage/v1/object/public/marcadores/maker1.png?t=2024-09-14T13%3A24%3A43.250Z'::character varying,
  driver bigint NOT NULL UNIQUE,
  description text,
  title text,
  categoria character varying DEFAULT 'Ligero'::character varying,
  kyc boolean DEFAULT false,
  estado boolean DEFAULT false,
  vehiculo_id bigint,
  CONSTRAINT place_pkey PRIMARY KEY (id, driver),
  CONSTRAINT place_driver_fkey FOREIGN KEY (driver) REFERENCES muevete.drivers(id),
  CONSTRAINT place_vehiculo_id_fkey FOREIGN KEY (vehiculo_id) REFERENCES muevete.vehiculos(id)
);
CREATE TABLE muevete.suscription_plan (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  name text,
  status boolean,
  cost numeric,
  value numeric,
  recomended boolean,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT suscription_plan_pkey PRIMARY KEY (id)
);
CREATE TABLE muevete.suscription_plan_user_history (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  last_balance numeric,
  new_balance numeric,
  plan_id bigint,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  user_id uuid,
  CONSTRAINT suscription_plan_user_history_pkey PRIMARY KEY (id)
);
CREATE TABLE muevete.suscription_user (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  user_id uuid,
  current_balance numeric,
  active_until timestamp without time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT suscription_user_pkey PRIMARY KEY (id)
);
CREATE TABLE muevete.users (
  user_id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  name text,
  phone character varying,
  email character varying,
  image text,
  uuid uuid,
  ci character varying,
  latitud text,
  longitud text,
  province text,
  municipality text,
  direccion text,
  pais text,
  CONSTRAINT users_pkey PRIMARY KEY (user_id),
  CONSTRAINT clientes_uuid_fkey FOREIGN KEY (uuid) REFERENCES auth.users(id)
);
CREATE TABLE muevete.vehiculos (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  marca character varying,
  modelo character varying,
  chapa character varying,
  circulacion character varying,
  categoria text,
  capacidad character varying,
  image character varying,
  descripcion character varying,
  color character varying,
  CONSTRAINT vehiculos_pkey PRIMARY KEY (id)
);
CREATE TABLE muevete.viajes (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  driver_id smallint,
  user character varying,
  estado boolean DEFAULT false,
  visto boolean DEFAULT false,
  user_display character varying,
  completado boolean DEFAULT false,
  latitud_cliente text,
  longitud_cliente text,
  telefono character varying,
  CONSTRAINT viajes_pkey PRIMARY KEY (id),
  CONSTRAINT viajes_driver_fkey FOREIGN KEY (driver_id) REFERENCES muevete.drivers(id)
);

-- =============================================
-- Tablas faltantes referenciadas en lib/services/
-- =============================================

CREATE TABLE muevete.solicitudes_transporte (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  user_id uuid,
  lat_origen double precision,
  lon_origen double precision,
  lat_destino double precision,
  lon_destino double precision,
  tipo_vehiculo character varying,
  precio_oferta numeric,
  estado character varying DEFAULT 'pendiente'::character varying,
  direccion_origen text,
  direccion_destino text,
  distancia_km double precision,
  expires_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT solicitudes_transporte_pkey PRIMARY KEY (id),
  CONSTRAINT solicitudes_transporte_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id)
);

CREATE TABLE muevete.ofertas_chofer (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  solicitud_id bigint NOT NULL,
  driver_id bigint NOT NULL,
  precio numeric,
  tiempo_estimado integer,
  estado character varying DEFAULT 'pendiente'::character varying,
  mensaje text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ofertas_chofer_pkey PRIMARY KEY (id),
  CONSTRAINT ofertas_chofer_solicitud_id_fkey FOREIGN KEY (solicitud_id) REFERENCES muevete.solicitudes_transporte(id),
  CONSTRAINT ofertas_chofer_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES muevete.drivers(id)
);

CREATE TABLE muevete.wallet_drivers (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  driver_id bigint NOT NULL UNIQUE,
  balance numeric DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT wallet_drivers_pkey PRIMARY KEY (id),
  CONSTRAINT wallet_drivers_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES muevete.drivers(id)
);

CREATE TABLE muevete.transacciones_wallet (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  user_id uuid,
  driver_id bigint,
  tipo character varying NOT NULL,
  monto numeric NOT NULL,
  balance_despues numeric,
  viaje_id bigint,
  descripcion text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT transacciones_wallet_pkey PRIMARY KEY (id),
  CONSTRAINT transacciones_wallet_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id),
  CONSTRAINT transacciones_wallet_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES muevete.drivers(id),
  CONSTRAINT transacciones_wallet_viaje_id_fkey FOREIGN KEY (viaje_id) REFERENCES muevete.viajes(id)
);

-- =============================================
-- Columna faltante en tabla existente
-- =============================================

-- wallet_service.dart lee/escribe 'balance' en suscription_user,
-- pero la tabla solo tiene 'current_balance'. Agregar columna 'balance':
ALTER TABLE muevete.suscription_user ADD COLUMN balance numeric DEFAULT 0;

-- =============================================================================
-- PERMISOS DE ACCESO AL SCHEMA muevete
-- =============================================================================
-- Ejecutar en el SQL Editor de Supabase Dashboard

-- 1) Permitir uso del schema
GRANT USAGE ON SCHEMA muevete TO anon, authenticated, service_role;

-- 2) Permisos sobre todas las tablas existentes
GRANT ALL ON ALL TABLES IN SCHEMA muevete TO authenticated, service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA muevete TO anon;

-- 3) Permisos sobre secuencias (necesario para GENERATED ALWAYS AS IDENTITY)
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA muevete TO authenticated, service_role;

-- 4) Permisos por defecto para tablas/secuencias futuras
ALTER DEFAULT PRIVILEGES IN SCHEMA muevete GRANT ALL ON TABLES TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA muevete GRANT SELECT ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA muevete GRANT USAGE, SELECT ON SEQUENCES TO authenticated, service_role;

-- 5) Exponer schema en PostgREST (para que supabase.schema('muevete') funcione)
--    Opcion A: hacerlo desde Dashboard > Project Settings > API > Exposed schemas > agregar "muevete"
--    Opcion B: por SQL:
ALTER ROLE authenticator SET pgrst.db_schemas = 'public, muevete';
NOTIFY pgrst, 'reload config';

-- =============================================================================
-- HABILITAR ROW LEVEL SECURITY EN TODAS LAS TABLAS
-- =============================================================================

ALTER TABLE muevete.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.drivers ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.place ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.vehiculos ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.viajes ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.configuracion_navegacion ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.suscription_plan ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.suscription_user ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.suscription_plan_user_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.solicitudes_transporte ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.ofertas_chofer ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.wallet_drivers ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.transacciones_wallet ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- POLITICAS RLS
-- =============================================================================
-- Logica basada en auth_service, driver_service, transport_request_service,
-- wallet_service y los modelos de la app.
--
-- Convencion:
--   - Las tablas con uuid/user_id vinculado a auth.users(id) usan auth.uid()
--   - Las tablas vinculadas a drivers.id usan un subselect:
--     (SELECT id FROM muevete.drivers WHERE uuid = auth.uid())

-- -------------------------------------------------------
-- muevete.users
-- auth_service: getUserProfile, updateUserProfile, createUserProfile
-- El usuario solo ve y modifica su propio perfil.
-- -------------------------------------------------------
CREATE POLICY "users_select_own" ON muevete.users
  FOR SELECT TO authenticated
  USING (uuid = auth.uid());

CREATE POLICY "users_insert_own" ON muevete.users
  FOR INSERT TO authenticated
  WITH CHECK (uuid = auth.uid());

CREATE POLICY "users_update_own" ON muevete.users
  FOR UPDATE TO authenticated
  USING (uuid = auth.uid())
  WITH CHECK (uuid = auth.uid());

-- -------------------------------------------------------
-- muevete.drivers
-- auth_service: getDriverProfile, createDriverProfile, updateDriverProfile
-- driver_service: toggleOnlineStatus (update por id)
-- El driver solo ve y modifica su propio perfil.
-- -------------------------------------------------------
CREATE POLICY "drivers_select_own" ON muevete.drivers
  FOR SELECT TO authenticated
  USING (uuid = auth.uid());

CREATE POLICY "drivers_insert_own" ON muevete.drivers
  FOR INSERT TO authenticated
  WITH CHECK (uuid = auth.uid());

CREATE POLICY "drivers_update_own" ON muevete.drivers
  FOR UPDATE TO authenticated
  USING (uuid = auth.uid())
  WITH CHECK (uuid = auth.uid());

-- -------------------------------------------------------
-- muevete.vehiculos
-- Catalogo publico de vehiculos, solo lectura para autenticados.
-- -------------------------------------------------------
CREATE POLICY "vehiculos_select_all" ON muevete.vehiculos
  FOR SELECT TO authenticated
  USING (true);

-- -------------------------------------------------------
-- muevete.place
-- transport_request_service: getNearbyDrivers (SELECT donde estado=true)
-- driver_service: updateDriverLocation, toggleOnlineStatus (UPDATE por driver)
-- Todos los autenticados pueden leer places activos (para ver drivers cercanos).
-- Solo el driver duenno puede actualizar su place.
-- -------------------------------------------------------
CREATE POLICY "place_select_active" ON muevete.place
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "place_insert_own" ON muevete.place
  FOR INSERT TO authenticated
  WITH CHECK (
    driver IN (SELECT id FROM muevete.drivers WHERE uuid = auth.uid())
  );

CREATE POLICY "place_update_own" ON muevete.place
  FOR UPDATE TO authenticated
  USING (
    driver IN (SELECT id FROM muevete.drivers WHERE uuid = auth.uid())
  )
  WITH CHECK (
    driver IN (SELECT id FROM muevete.drivers WHERE uuid = auth.uid())
  );

-- -------------------------------------------------------
-- muevete.configuracion_navegacion
-- Configuracion global, solo lectura.
-- -------------------------------------------------------
CREATE POLICY "config_nav_select_all" ON muevete.configuracion_navegacion
  FOR SELECT TO authenticated
  USING (true);

-- -------------------------------------------------------
-- muevete.suscription_plan
-- Planes de suscripcion, catalogo publico, solo lectura.
-- -------------------------------------------------------
CREATE POLICY "suscription_plan_select_all" ON muevete.suscription_plan
  FOR SELECT TO authenticated
  USING (true);

-- -------------------------------------------------------
-- muevete.suscription_user
-- wallet_service: getClientBalance (SELECT), addFunds/processRidePayment (UPDATE)
-- El usuario solo ve y modifica su propia suscripcion.
-- -------------------------------------------------------
CREATE POLICY "suscription_user_select_own" ON muevete.suscription_user
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "suscription_user_insert_own" ON muevete.suscription_user
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "suscription_user_update_own" ON muevete.suscription_user
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- -------------------------------------------------------
-- muevete.suscription_plan_user_history
-- Historial de planes del usuario, solo lectura propia.
-- -------------------------------------------------------
CREATE POLICY "suscription_history_select_own" ON muevete.suscription_plan_user_history
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "suscription_history_insert_own" ON muevete.suscription_plan_user_history
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

-- -------------------------------------------------------
-- muevete.solicitudes_transporte
-- transport_request_service: createRequest (INSERT), cancelRequest (UPDATE),
--   getActiveRequest (SELECT por user_id)
-- driver_service: subscribeToRequests (Realtime INSERT -> necesita SELECT)
-- Clientes: CRUD sobre sus propias solicitudes.
-- Drivers: pueden leer solicitudes pendientes (para recibir peticiones).
-- -------------------------------------------------------
CREATE POLICY "solicitudes_select_own_client" ON muevete.solicitudes_transporte
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "solicitudes_select_pending_driver" ON muevete.solicitudes_transporte
  FOR SELECT TO authenticated
  USING (
    estado = 'pendiente'
    AND EXISTS (SELECT 1 FROM muevete.drivers WHERE uuid = auth.uid())
  );

CREATE POLICY "solicitudes_insert_client" ON muevete.solicitudes_transporte
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "solicitudes_update_own_client" ON muevete.solicitudes_transporte
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- -------------------------------------------------------
-- muevete.ofertas_chofer
-- driver_service: makeOffer (INSERT)
-- transport_request_service: subscribeToOffers (Realtime -> SELECT),
--   acceptOffer (UPDATE estado + SELECT)
-- Drivers: insertan y leen sus propias ofertas.
-- Clientes: leen ofertas de sus solicitudes y las aceptan (UPDATE).
-- -------------------------------------------------------
CREATE POLICY "ofertas_select_own_driver" ON muevete.ofertas_chofer
  FOR SELECT TO authenticated
  USING (
    driver_id IN (SELECT id FROM muevete.drivers WHERE uuid = auth.uid())
  );

CREATE POLICY "ofertas_select_own_client" ON muevete.ofertas_chofer
  FOR SELECT TO authenticated
  USING (
    solicitud_id IN (
      SELECT id FROM muevete.solicitudes_transporte WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "ofertas_insert_driver" ON muevete.ofertas_chofer
  FOR INSERT TO authenticated
  WITH CHECK (
    driver_id IN (SELECT id FROM muevete.drivers WHERE uuid = auth.uid())
  );

CREATE POLICY "ofertas_update_client" ON muevete.ofertas_chofer
  FOR UPDATE TO authenticated
  USING (
    solicitud_id IN (
      SELECT id FROM muevete.solicitudes_transporte WHERE user_id = auth.uid()
    )
  );

-- -------------------------------------------------------
-- muevete.viajes
-- driver_service: getActiveTrip (SELECT), updateTripStatus (UPDATE)
-- Drivers: leen y actualizan sus propios viajes.
-- Clientes: leen viajes donde son el usuario.
-- -------------------------------------------------------
CREATE POLICY "viajes_select_driver" ON muevete.viajes
  FOR SELECT TO authenticated
  USING (
    driver_id IN (SELECT id FROM muevete.drivers WHERE uuid = auth.uid())
  );

CREATE POLICY "viajes_select_client" ON muevete.viajes
  FOR SELECT TO authenticated
  USING (
    "user" = auth.uid()::text
  );

CREATE POLICY "viajes_insert_authenticated" ON muevete.viajes
  FOR INSERT TO authenticated
  WITH CHECK (true);

CREATE POLICY "viajes_update_driver" ON muevete.viajes
  FOR UPDATE TO authenticated
  USING (
    driver_id IN (SELECT id FROM muevete.drivers WHERE uuid = auth.uid())
  );

-- -------------------------------------------------------
-- muevete.wallet_drivers
-- wallet_service: getDriverBalance (SELECT), processRidePayment (UPDATE)
-- El driver solo ve y modifica su propia wallet.
-- -------------------------------------------------------
CREATE POLICY "wallet_drivers_select_own" ON muevete.wallet_drivers
  FOR SELECT TO authenticated
  USING (
    driver_id IN (SELECT id FROM muevete.drivers WHERE uuid = auth.uid())
  );

CREATE POLICY "wallet_drivers_insert_own" ON muevete.wallet_drivers
  FOR INSERT TO authenticated
  WITH CHECK (
    driver_id IN (SELECT id FROM muevete.drivers WHERE uuid = auth.uid())
  );

CREATE POLICY "wallet_drivers_update_own" ON muevete.wallet_drivers
  FOR UPDATE TO authenticated
  USING (
    driver_id IN (SELECT id FROM muevete.drivers WHERE uuid = auth.uid())
  );

-- -------------------------------------------------------
-- muevete.transacciones_wallet
-- wallet_service: addFunds (INSERT), getTransactions (SELECT),
--   processRidePayment (INSERT para ambas partes)
-- Usuarios ven sus transacciones. Drivers ven las suyas.
-- Insertar: usuario para sus propias, driver para las suyas.
-- -------------------------------------------------------
CREATE POLICY "transacciones_select_client" ON muevete.transacciones_wallet
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "transacciones_select_driver" ON muevete.transacciones_wallet
  FOR SELECT TO authenticated
  USING (
    driver_id IN (SELECT id FROM muevete.drivers WHERE uuid = auth.uid())
  );

CREATE POLICY "transacciones_insert_client" ON muevete.transacciones_wallet
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    OR driver_id IN (SELECT id FROM muevete.drivers WHERE uuid = auth.uid())
  );

-- =============================================================================
-- NOTA IMPORTANTE SOBRE service_role
-- =============================================================================
-- service_role BYPASSA RLS automaticamente en Supabase.
-- Si processRidePayment necesita escribir en wallet del driver Y del cliente
-- al mismo tiempo (cross-user), se recomienda ejecutar esa logica desde una
-- Edge Function con service_role key, no desde el cliente Flutter directamente.