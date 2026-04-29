-- =============================================================================
-- MIGRACIÓN 001: Soporte para registro de múltiples tipos de usuario
-- Plataforma Muevete — Registro Shipper / Carrier / Dispatcher
--
-- REGLA: Solo se agregan columnas nuevas con ADD COLUMN IF NOT EXISTS.
--        Ninguna columna, constraint ni relación existente es modificada.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. muevete.users — agregar discriminador de tipo y campos de shipper
-- -----------------------------------------------------------------------------
ALTER TABLE muevete.users
  ADD COLUMN IF NOT EXISTS tipo_usuario text NOT NULL DEFAULT 'cliente_pasajero',
  -- Valores: 'cliente_pasajero' | 'shipper'
  -- 'cliente_pasajero' → flujo taxi existente (sin cambios)
  -- 'shipper'          → flujo de envíos de carga (nuevo)

  -- Campos exclusivos de shipper (NULL para cliente_pasajero)
  ADD COLUMN IF NOT EXISTS tipo_cuenta text DEFAULT 'individual',
  -- Valores: 'individual' | 'empresa' | 'cooperativa'

  ADD COLUMN IF NOT EXISTS empresa_nombre text,
  ADD COLUMN IF NOT EXISTS empresa_rut text,
  ADD COLUMN IF NOT EXISTS empresa_direccion text,
  ADD COLUMN IF NOT EXISTS mercaderias_habituales jsonb DEFAULT '[]'::jsonb;
  -- Ej: ["general","refrigerada","peligrosa","sobredimensionada","vehiculos","electronica"]

-- -----------------------------------------------------------------------------
-- 2. muevete.drivers — agregar discriminador de tipo y campos de carrier/dispatcher
-- -----------------------------------------------------------------------------
ALTER TABLE muevete.drivers
  ADD COLUMN IF NOT EXISTS tipo_usuario text NOT NULL DEFAULT 'conductor_pasajeros',
  -- Valores: 'conductor_pasajeros' | 'carrier_carga' | 'dispatcher'
  -- 'conductor_pasajeros' → flujo taxi existente (sin cambios)
  -- 'carrier_carga'       → transportista de carga (nuevo)
  -- 'dispatcher'          → gestor de flota que administra carriers (nuevo)

  -- FK al dispatcher propietario (solo se rellena en filas carrier_carga creadas por un dispatcher)
  -- NULL = carrier independiente o conductor de pasajeros
  ADD COLUMN IF NOT EXISTS dispatcher_id bigint,

  -- Campos profesionales de carga (NULL para conductor_pasajeros)
  ADD COLUMN IF NOT EXISTS mc_number text,
  ADD COLUMN IF NOT EXISTS dot_number text,

  -- Campos específicos del vehículo de carga (solo para carrier_carga y dispatcher)
  ADD COLUMN IF NOT EXISTS tipo_carroceria text,
  -- Valores: 'furgon_seco' | 'flatbed' | 'reefer' | 'tanque' | 'curtainsider' | 'volcadora'

  ADD COLUMN IF NOT EXISTS capacidad_ton numeric,
  ADD COLUMN IF NOT EXISTS longitud_plataforma_m numeric,
  ADD COLUMN IF NOT EXISTS seguro_carga_vigente boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS seguro_carga_vence date,
  ADD COLUMN IF NOT EXISTS seguro_carga_url text,   -- URL del certificado subido

  -- Campos del dispatcher
  ADD COLUMN IF NOT EXISTS empresa_nombre text,
  ADD COLUMN IF NOT EXISTS empresa_rut text,
  ADD COLUMN IF NOT EXISTS empresa_direccion text;

-- FK diferida hacia muevete.drivers (auto-referencial: dispatcher_id → drivers.id)
-- Se agrega solo si no existe ya
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'drivers_dispatcher_id_fkey'
      AND table_schema = 'muevete'
      AND table_name   = 'drivers'
  ) THEN
    ALTER TABLE muevete.drivers
      ADD CONSTRAINT drivers_dispatcher_id_fkey
      FOREIGN KEY (dispatcher_id) REFERENCES muevete.drivers(id);
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 3. muevete.vehiculos — agregar columnas de vehículo de carga
-- -----------------------------------------------------------------------------
ALTER TABLE muevete.vehiculos
  ADD COLUMN IF NOT EXISTS tipo_carroceria text,
  ADD COLUMN IF NOT EXISTS capacidad_ton numeric,
  ADD COLUMN IF NOT EXISTS longitud_m numeric,
  ADD COLUMN IF NOT EXISTS año integer,
  ADD COLUMN IF NOT EXISTS tiene_gps boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS seguro_vigente boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS seguro_vence date;

-- -----------------------------------------------------------------------------
-- 4. muevete.sub_usuarios — tabla nueva para relación dispatcher ↔ carrier
--    y shipper ↔ operador empresarial
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS muevete.sub_usuarios (
  id                  bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  propietario_uuid    uuid NOT NULL,
  tipo_propietario    text NOT NULL,
  -- 'dispatcher' | 'shipper'
  sub_uuid            uuid NOT NULL,
  sub_driver_id       bigint,
  rol                 text NOT NULL DEFAULT 'conductor',
  -- dispatcher→carrier: 'conductor'
  -- shipper→operador:   'operador' | 'admin'
  invitacion_estado   text NOT NULL DEFAULT 'pendiente',
  -- 'pendiente' | 'activo' | 'revocado'
  invitacion_email    text,
  invitacion_token    text,
  activo              boolean NOT NULL DEFAULT false,
  created_at          timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT sub_usuarios_pkey PRIMARY KEY (id),
  CONSTRAINT sub_usuarios_propietario_fkey FOREIGN KEY (propietario_uuid) REFERENCES auth.users(id),
  CONSTRAINT sub_usuarios_sub_uuid_fkey    FOREIGN KEY (sub_uuid)         REFERENCES auth.users(id),
  CONSTRAINT sub_usuarios_sub_driver_fkey  FOREIGN KEY (sub_driver_id)    REFERENCES muevete.drivers(id),
  CONSTRAINT uq_sub_usuario UNIQUE (propietario_uuid, sub_uuid)
);

-- -----------------------------------------------------------------------------
-- 5. Índices para las nuevas columnas (mejoran queries de filtrado por tipo)
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_users_tipo_usuario
  ON muevete.users (tipo_usuario);

CREATE INDEX IF NOT EXISTS idx_drivers_tipo_usuario
  ON muevete.drivers (tipo_usuario);

CREATE INDEX IF NOT EXISTS idx_drivers_dispatcher_id
  ON muevete.drivers (dispatcher_id);

CREATE INDEX IF NOT EXISTS idx_sub_usuarios_propietario
  ON muevete.sub_usuarios (propietario_uuid);

CREATE INDEX IF NOT EXISTS idx_sub_usuarios_sub_driver
  ON muevete.sub_usuarios (sub_driver_id);

-- -----------------------------------------------------------------------------
-- 6. Valores por defecto para filas existentes
--    Las filas actuales en users son clientes de taxi → cliente_pasajero
--    Las filas actuales en drivers son conductores de taxi → conductor_pasajeros
--    (ya cubierto por los DEFAULT, pero se explicita para claridad)
-- -----------------------------------------------------------------------------
-- No se necesita UPDATE adicional porque los DEFAULT ya aplican
-- a las filas existentes cuando no tienen valor (NULL → DEFAULT no aplica
-- retroactivamente; usar UPDATE solo si hay NULLs en filas existentes)

UPDATE muevete.users
  SET tipo_usuario = 'cliente_pasajero'
  WHERE tipo_usuario IS NULL;

UPDATE muevete.drivers
  SET tipo_usuario = 'conductor_pasajeros'
  WHERE tipo_usuario IS NULL;
