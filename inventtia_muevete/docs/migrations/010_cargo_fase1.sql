-- ============================================================
-- Migration 010 – Cargo MVP (Fase 1)
-- Schema: muevete
-- Tables: muevete.cargas, muevete.ofertas_carga
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 1.  muevete.cargas
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS muevete.cargas (
  id                      BIGSERIAL PRIMARY KEY,
  -- shipper: references muevete.users.uuid (auth user uuid)
  shipper_id              UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Type
  tipo                    TEXT NOT NULL DEFAULT 'ftl'
                            CHECK (tipo IN ('ftl','ltl')),
  estado                  TEXT NOT NULL DEFAULT 'publicada'
                            CHECK (estado IN (
                              'publicada','en_matching','ofertada',
                              'aceptada','en_transito','entregada',
                              'completada','cancelada','disputa'
                            )),

  -- Origin
  dir_origen              TEXT NOT NULL,
  lat_origen              DOUBLE PRECISION NOT NULL DEFAULT 0,
  lon_origen              DOUBLE PRECISION NOT NULL DEFAULT 0,
  ciudad_origen           TEXT,
  estado_origen           TEXT,
  pais_origen             TEXT,

  -- Destination
  dir_destino             TEXT NOT NULL,
  lat_destino             DOUBLE PRECISION NOT NULL DEFAULT 0,
  lon_destino             DOUBLE PRECISION NOT NULL DEFAULT 0,
  ciudad_destino          TEXT,
  estado_destino          TEXT,
  pais_destino            TEXT,

  -- Cargo details
  descripcion             TEXT,
  tipo_mercancia          TEXT,
  peso_kg                 NUMERIC(12,2),
  volumen_m3              NUMERIC(10,3),
  longitud_m              NUMERIC(8,2),
  ancho_m                 NUMERIC(8,2),
  alto_m                  NUMERIC(8,2),
  valor_declarado         NUMERIC(15,2),
  requiere_refrigeracion  BOOLEAN NOT NULL DEFAULT FALSE,
  temperatura_min         NUMERIC(5,1),
  temperatura_max         NUMERIC(5,1),
  requiere_seguro         BOOLEAN NOT NULL DEFAULT FALSE,
  instrucciones           TEXT,

  -- Equipment
  tipo_equipo             TEXT,
  id_tipo_vehiculo        BIGINT REFERENCES muevete.vehiculos(id),

  -- Dates
  fecha_recogida          DATE,
  fecha_entrega           DATE,
  ventana_recogida_desde  TIME,
  ventana_recogida_hasta  TIME,
  ventana_entrega_desde   TIME,
  ventana_entrega_hasta   TIME,

  -- Pricing
  precio_ofertado         NUMERIC(15,2),
  precio_final            NUMERIC(15,2),
  moneda                  TEXT NOT NULL DEFAULT 'USD',

  -- Visibility
  destacada               BOOLEAN NOT NULL DEFAULT FALSE,
  destacada_hasta         TIMESTAMPTZ,
  exclusiva_hasta         TIMESTAMPTZ,

  -- Distance
  distancia_km            NUMERIC(10,2),
  distancia_millas        NUMERIC(10,2),

  -- LTL
  es_ltl                  BOOLEAN NOT NULL DEFAULT FALSE,
  ltl_espacio_ocupado     NUMERIC(5,2),

  -- Recurring
  es_recurrente           BOOLEAN NOT NULL DEFAULT FALSE,

  -- Assignment: references muevete.drivers.id
  carrier_driver_id       BIGINT REFERENCES muevete.drivers(id),
  oferta_aceptada_id      BIGINT,

  -- Tracking
  ultima_lat              DOUBLE PRECISION,
  ultima_lon              DOUBLE PRECISION,
  ultima_ubicacion_at     TIMESTAMPTZ,

  -- Expiration
  expires_at              TIMESTAMPTZ,

  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_cargas_shipper_id    ON muevete.cargas (shipper_id);
CREATE INDEX IF NOT EXISTS idx_cargas_estado        ON muevete.cargas (estado);
CREATE INDEX IF NOT EXISTS idx_cargas_carrier       ON muevete.cargas (carrier_driver_id);
CREATE INDEX IF NOT EXISTS idx_cargas_ciudad_origen ON muevete.cargas (ciudad_origen);
CREATE INDEX IF NOT EXISTS idx_cargas_created_at    ON muevete.cargas (created_at DESC);

-- RLS
ALTER TABLE muevete.cargas ENABLE ROW LEVEL SECURITY;

-- Shippers see/manage their own loads
CREATE POLICY "shipper_own_cargas" ON muevete.cargas
  FOR ALL USING (shipper_id = auth.uid());

-- Carriers and dispatchers can read published/offered loads,
-- plus their own assigned loads
CREATE POLICY "carriers_see_available" ON muevete.cargas
  FOR SELECT USING (
    estado IN ('publicada','en_matching','ofertada')
    OR carrier_driver_id = (
      SELECT id FROM muevete.drivers WHERE uuid = auth.uid() LIMIT 1
    )
  );


-- ────────────────────────────────────────────────────────────
-- 2.  muevete.ofertas_carga
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS muevete.ofertas_carga (
  id                      BIGSERIAL PRIMARY KEY,
  carga_id                BIGINT NOT NULL REFERENCES muevete.cargas(id) ON DELETE CASCADE,
  -- driver_id: references muevete.drivers.id
  driver_id               BIGINT NOT NULL REFERENCES muevete.drivers(id) ON DELETE CASCADE,

  precio                  NUMERIC(15,2) NOT NULL,
  tarifa_por_milla        NUMERIC(10,4),
  tiempo_estimado_dias    INTEGER,
  fecha_recogida_prop     DATE,
  fecha_entrega_prop      DATE,
  vehiculo_id             BIGINT REFERENCES muevete.vehiculos(id),
  incluye_seguro          BOOLEAN NOT NULL DEFAULT FALSE,
  notas                   TEXT,

  estado                  TEXT NOT NULL DEFAULT 'pendiente'
                            CHECK (estado IN (
                              'pendiente','aceptada','rechazada',
                              'retirada','expirada'
                            )),
  matching_score          NUMERIC(5,2),

  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ,

  -- One active offer per carrier per carga
  CONSTRAINT uq_oferta_carrier_carga UNIQUE (carga_id, driver_id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_ofertas_carga_id   ON muevete.ofertas_carga (carga_id);
CREATE INDEX IF NOT EXISTS idx_ofertas_driver_id  ON muevete.ofertas_carga (driver_id);
CREATE INDEX IF NOT EXISTS idx_ofertas_estado     ON muevete.ofertas_carga (estado);

-- RLS
ALTER TABLE muevete.ofertas_carga ENABLE ROW LEVEL SECURITY;

-- Carriers manage their own offers
CREATE POLICY "carrier_own_ofertas" ON muevete.ofertas_carga
  FOR ALL USING (
    driver_id = (
      SELECT id FROM muevete.drivers WHERE uuid = auth.uid() LIMIT 1
    )
  );

-- Shippers see offers on their loads
CREATE POLICY "shipper_sees_ofertas" ON muevete.ofertas_carga
  FOR SELECT USING (
    carga_id IN (
      SELECT id FROM muevete.cargas WHERE shipper_id = auth.uid()
    )
  );


-- ────────────────────────────────────────────────────────────
-- 3.  muevete.drivers – dispatcher_id already exists as BIGINT
--     (self-referencing FK added in a previous migration).
--     No changes needed here.
-- ────────────────────────────────────────────────────────────
-- (muevete.drivers.dispatcher_id BIGINT → muevete.drivers(id) already present)
