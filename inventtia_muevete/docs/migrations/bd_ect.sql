-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

CREATE TABLE muevete.configuracion_navegacion (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  precio_x_km numeric,
  tiempo_espera_driver integer,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT configuracion_navegacion_pkey PRIMARY KEY (id)
);
CREATE TABLE muevete.direcciones_rapidas (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  user_id uuid NOT NULL,
  label text NOT NULL,
  icon text NOT NULL DEFAULT 'place'::text,
  direccion text NOT NULL,
  latitud double precision NOT NULL,
  longitud double precision NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT direcciones_rapidas_pkey PRIMARY KEY (id),
  CONSTRAINT direcciones_rapidas_user_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id)
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
  usado_actualmente boolean DEFAULT false,
  CONSTRAINT drivers_pkey PRIMARY KEY (id),
  CONSTRAINT drivers_uuid_fkey FOREIGN KEY (uuid) REFERENCES auth.users(id),
  CONSTRAINT drivers_vehiculo_fkey FOREIGN KEY (vehiculo) REFERENCES muevete.vehiculos(id)
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
  id_tipo_vehiculo bigint,
  metodo_pago character varying DEFAULT 'efectivo'::character varying,
  CONSTRAINT solicitudes_transporte_pkey PRIMARY KEY (id),
  CONSTRAINT solicitudes_transporte_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id)
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
  balance numeric DEFAULT 0,
  CONSTRAINT suscription_user_pkey PRIMARY KEY (id)
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
  photo_url text,
  CONSTRAINT users_pkey PRIMARY KEY (user_id),
  CONSTRAINT clientes_uuid_fkey FOREIGN KEY (uuid) REFERENCES auth.users(id)
);
CREATE TABLE muevete.vehicle_type (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  tipo text,
  precio_km_default numeric,
  status boolean,
  tiempo_min_por_km numeric,
  CONSTRAINT vehicle_type_pkey PRIMARY KEY (id)
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
  id_tipo_vehiculo bigint,
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
CREATE TABLE muevete.wallet_drivers (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  driver_id bigint NOT NULL UNIQUE,
  balance numeric DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT wallet_drivers_pkey PRIMARY KEY (id),
  CONSTRAINT wallet_drivers_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES muevete.drivers(id)
);