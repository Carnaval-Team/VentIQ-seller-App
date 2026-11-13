-- ============================================================================
-- 031_taxi_zonas_tarifas.sql
-- H0 · Fundaciones de datos: zonas, tarifas municipales, configuración global,
--      multiplicador por tipo de vehículo y columnas snapshot de tarifa.
--
-- ANEXO DE DISEÑO: docs/plan-taxi-precio-fijo/04-diseno-tecnico.md §2.2–§2.8, §2.10, §2.11
--
-- PRERREQUISITOS
--   · 030_baseline_sync_produccion.sql ya aplicado. De ese baseline se REUTILIZAN
--     y NO se redefinen aquí:
--       - muevete.set_updated_at()                (función de trigger)
--       - muevete.get_my_driver_id()
--       - muevete.is_superadmin()
--       - muevete.complete_ride_payment(...)      (6 args + sobrecarga legacy de 5)
--       - triggers de push: solicitudes_push, ofertas_push, notificaciones_push
--
-- IDEMPOTENCIA
--   · CREATE TABLE / INDEX / SCHEMA ....... IF NOT EXISTS
--   · ALTER TABLE ADD COLUMN ............. IF NOT EXISTS
--   · ADD CONSTRAINT ...................... guardado con pg_constraint (DO $$)
--   · CREATE TRIGGER ...................... DROP TRIGGER IF EXISTS + CREATE
--   · INSERT singleton .................... ON CONFLICT DO NOTHING
--   · CREATE FUNCTION ..................... CREATE OR REPLACE
--   Re-ejecutar este archivo dos veces seguidas no debe producir errores.
--
-- NO EJECUTAR CONTRA SUPABASE DESDE ESTE ENTORNO (sólo se entrega el archivo).
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 0. Esquema (no-op si ya existe; el esquema muevete es preexistente)
-- ----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS muevete;

-- ----------------------------------------------------------------------------
-- 1. muevete.zonas_tarifa
--    D1: geometría = GeoJSON Polygon en jsonb: coordinates = [anillo, huecos...]
--        cada punto es [lon, lat].
--    D3: modo ∈ ('fijo','fijo_mas_km','por_km').
--    Solapes: MAYOR prioridad gana (ver 032, fn_zona_de_punto).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS muevete.zonas_tarifa (
  id             bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  -- Desvío D-01 del anexo: identificador estable para seed y logs (MUN, FB, Z1..Z9)
  codigo         text,
  nombre         text        NOT NULL,
  provincia      text,
  municipio      text,
  geometria      jsonb       NOT NULL,
  modo           text        NOT NULL,
  monto_fijo     numeric,
  precio_km      numeric,
  prioridad      integer     NOT NULL DEFAULT 0,
  activo         boolean     NOT NULL DEFAULT true,
  vigente_desde  timestamptz NOT NULL DEFAULT now(),
  vigente_hasta  timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT zonas_tarifa_pkey PRIMARY KEY (id),
  CONSTRAINT zonas_tarifa_codigo_key UNIQUE (codigo),
  CONSTRAINT zonas_tarifa_geo_valida
    CHECK (jsonb_typeof(geometria -> 'coordinates') = 'array'),
  CONSTRAINT zonas_tarifa_modo_chk
    CHECK (modo IN ('fijo','fijo_mas_km','por_km')),
  CONSTRAINT zonas_tarifa_montos_chk CHECK (
       (modo = 'fijo'        AND monto_fijo IS NOT NULL AND monto_fijo >= 0)
    OR (modo = 'fijo_mas_km' AND monto_fijo IS NOT NULL AND monto_fijo >= 0
                            AND precio_km  IS NOT NULL AND precio_km  >= 0)
    OR (modo = 'por_km'      AND precio_km  IS NOT NULL AND precio_km  >= 0)
  ),
  CONSTRAINT zonas_tarifa_vigencia_chk
    CHECK (vigente_hasta IS NULL OR vigente_hasta > vigente_desde)
);

COMMENT ON TABLE muevete.zonas_tarifa IS
  'Zonas tarifarias del taxi. geometria = GeoJSON Polygon {type, coordinates:[[[lon,lat],...]]}. En solapes gana la prioridad mayor.';
COMMENT ON COLUMN muevete.zonas_tarifa.modo IS
  'fijo = dentro de la zona monto_fijo; si el viaje sale, km_total * precio_km. fijo_mas_km = monto_fijo + km*precio_km. por_km = km*precio_km.';
COMMENT ON COLUMN muevete.zonas_tarifa.prioridad IS
  'Resolución de solapes: MAYOR gana. A igual prioridad gana el id menor (determinista).';

CREATE INDEX IF NOT EXISTS zonas_tarifa_activas_idx
  ON muevete.zonas_tarifa (activo, prioridad DESC)
  WHERE activo;

-- ----------------------------------------------------------------------------
-- 2. muevete.tarifas_municipio  (fallback D4 cuando el origen no cae en zona)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS muevete.tarifas_municipio (
  id          bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  provincia   text    NOT NULL,
  municipio   text    NOT NULL,
  modo        text    NOT NULL DEFAULT 'fijo',
  monto_fijo  numeric NOT NULL DEFAULT 1500,
  precio_km   numeric NOT NULL DEFAULT 400,
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT tarifas_municipio_pkey PRIMARY KEY (id),
  CONSTRAINT tarifas_municipio_unq UNIQUE (provincia, municipio),
  CONSTRAINT tarifas_municipio_modo_chk
    CHECK (modo IN ('fijo','fijo_mas_km','por_km')),
  CONSTRAINT tarifas_municipio_montos_chk
    CHECK (monto_fijo >= 0 AND precio_km >= 0)
);

COMMENT ON TABLE muevete.tarifas_municipio IS
  'Tarifa de respaldo (D4) cuando el punto de origen no cae en ninguna zona activa.';

-- ----------------------------------------------------------------------------
-- 3. muevete.configuracion_tarifas  (singleton id = 1)
--    D5: comisión global configurable.
--    D6: permite_deuda + limite_deuda_efectivo.
--    §2.3 del plan: parámetros de arranque.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS muevete.configuracion_tarifas (
  id                          smallint     NOT NULL DEFAULT 1,
  moneda                      text         NOT NULL DEFAULT 'CUP',
  -- D5
  comision_pct                numeric(5,2) NOT NULL DEFAULT 15.00,
  tope_comision_viaje         numeric      NOT NULL DEFAULT 2500,
  recarga_pct                 numeric(5,2) NOT NULL DEFAULT 11.00,
  -- D6
  limite_deuda_efectivo       numeric      NOT NULL DEFAULT 1000,
  permite_deuda               boolean      NOT NULL DEFAULT true,
  dias_max_deuda              integer      NOT NULL DEFAULT 7,
  -- Pisos por tipo (post-multiplicador)
  precio_minimo_auto          numeric      NOT NULL DEFAULT 1500,
  precio_minimo_moto          numeric      NOT NULL DEFAULT 900,
  precio_minimo_microbus      numeric      NOT NULL DEFAULT 2250,
  -- Válvula de elasticidad del viaje corto (auto)
  precio_corto_auto           numeric      NOT NULL DEFAULT 1000,
  umbral_km_corto             numeric(4,1) NOT NULL DEFAULT 1.5,
  -- Recargos
  recargo_nocturno_pct        numeric(5,2) NOT NULL DEFAULT 20,
  ventana_nocturna_inicio     time         NOT NULL DEFAULT '22:00',
  ventana_nocturna_fin        time         NOT NULL DEFAULT '06:00',
  prima_distancia_cup         numeric      NOT NULL DEFAULT 500,
  umbral_prima_distancia_km   numeric(4,1) NOT NULL DEFAULT 8,
  -- Espera (se cobra al cerrar: fn_completar_viaje)
  gracia_espera_min           integer      NOT NULL DEFAULT 3,
  tope_cobro_espera           numeric      NOT NULL DEFAULT 1200,
  -- Redondeo HACIA ARRIBA a múltiplos de redondeo_cup
  redondeo_cup                integer      NOT NULL DEFAULT 50,
  -- Descuento por pagar con wallet (persistido; ver D-08 del anexo)
  descuento_pago_wallet_pct   numeric(5,2) NOT NULL DEFAULT 5,
  -- D4: respaldo cuando no existe fila en tarifas_municipio
  -- (desvío D-13: §2.3 del plan los exige; §4.1 del plan los omitía)
  monto_fijo_fallback_municipio numeric    NOT NULL DEFAULT 1500,
  precio_km_fallback            numeric    NOT NULL DEFAULT 400,
  -- Vigencia / revisión de precio
  precio_vigente_desde        timestamptz  NOT NULL DEFAULT now(),
  -- §8.6 del plan: flag de corte / rollback
  taxi_precio_fijo_activo     boolean      NOT NULL DEFAULT false,
  updated_at                  timestamptz  NOT NULL DEFAULT now(),

  CONSTRAINT configuracion_tarifas_pkey PRIMARY KEY (id),
  CONSTRAINT configuracion_tarifas_singleton CHECK (id = 1),
  CONSTRAINT configuracion_tarifas_comision_chk CHECK (comision_pct BETWEEN 0 AND 30),
  CONSTRAINT configuracion_tarifas_recarga_chk  CHECK (recarga_pct BETWEEN 0 AND 50),
  CONSTRAINT configuracion_tarifas_deuda_chk    CHECK (limite_deuda_efectivo BETWEEN 0 AND 5000),
  CONSTRAINT configuracion_tarifas_redondeo_chk CHECK (redondeo_cup IN (0,5,25,50,100)),
  CONSTRAINT configuracion_tarifas_fallback_chk CHECK (
       monto_fijo_fallback_municipio BETWEEN 0 AND 20000
   AND precio_km_fallback           BETWEEN 0 AND 5000),
  CONSTRAINT configuracion_tarifas_nocturno_chk CHECK (recargo_nocturno_pct BETWEEN 0 AND 50),
  CONSTRAINT configuracion_tarifas_espera_chk   CHECK (gracia_espera_min BETWEEN 0 AND 30
                                                       AND tope_cobro_espera >= 0)
);

COMMENT ON TABLE muevete.configuracion_tarifas IS
  'Configuración global del taxi (fila única id=1). Comisión D5, deuda D6, recargos, redondeo y flag de corte.';
COMMENT ON COLUMN muevete.configuracion_tarifas.permite_deuda IS
  'D6: true = el chofer puede quedar con saldo negativo hasta limite_deuda_efectivo. false = necesita saldo >= comisión.';
COMMENT ON COLUMN muevete.configuracion_tarifas.taxi_precio_fijo_activo IS
  'Flag de corte/rollback. false = apps viejas operan igual; true = sólo las RPC nuevas crean solicitudes y el dinero es inmutable.';

INSERT INTO muevete.configuracion_tarifas (id) VALUES (1)
ON CONFLICT (id) DO NOTHING;

-- ----------------------------------------------------------------------------
-- 4. muevete.vehicle_type.multiplicador_tarifa  (D2)
--    Columnas existentes verificadas en prod: tipo, precio_km_default,
--    precio_inside_sc, status, tiempo_min_por_km, precio_espera_min, categoria.
-- ----------------------------------------------------------------------------
ALTER TABLE muevete.vehicle_type
  ADD COLUMN IF NOT EXISTS multiplicador_tarifa numeric NOT NULL DEFAULT 1;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'vehicle_type_multiplicador_chk'
       AND conrelid = 'muevete.vehicle_type'::regclass
  ) THEN
    ALTER TABLE muevete.vehicle_type
      ADD CONSTRAINT vehicle_type_multiplicador_chk
      CHECK (multiplicador_tarifa BETWEEN 0.1 AND 5) NOT VALID;
  END IF;
END $$;

COMMENT ON COLUMN muevete.vehicle_type.multiplicador_tarifa IS
  'D2: multiplicador sobre la tarifa de zona. Valores sembrados en 033 (moto 0.60, auto 1.00, microbus 1.50, camioneta 1.20, minivan 1.30, tuktuk 0.50, bicicleta 0.30).';

-- ----------------------------------------------------------------------------
-- 5. Columnas snapshot en muevete.solicitudes_transporte
--    Columnas preexistentes (16): id, user_id, lat_origen, lon_origen,
--    lat_destino, lon_destino, tipo_vehiculo, precio_oferta, estado,
--    direccion_origen, direccion_destino, distancia_km, expires_at,
--    created_at, id_tipo_vehiculo, metodo_pago.
-- ----------------------------------------------------------------------------
ALTER TABLE muevete.solicitudes_transporte
  ADD COLUMN IF NOT EXISTS driver_id         bigint REFERENCES muevete.drivers(id),
  ADD COLUMN IF NOT EXISTS aceptada_at       timestamptz,
  ADD COLUMN IF NOT EXISTS zona_id           bigint REFERENCES muevete.zonas_tarifa(id),
  ADD COLUMN IF NOT EXISTS tarifa_modo       text,
  ADD COLUMN IF NOT EXISTS precio_plataforma numeric,
  ADD COLUMN IF NOT EXISTS comision_pct      numeric,
  ADD COLUMN IF NOT EXISTS precio_chofer     numeric,
  ADD COLUMN IF NOT EXISTS moneda            text DEFAULT 'CUP',
  ADD COLUMN IF NOT EXISTS tarifa_detalle    jsonb,
  -- Desvío D-02: trazabilidad de la máquina de estados (anexo 02) y panel admin
  ADD COLUMN IF NOT EXISTS completada_at      timestamptz,
  ADD COLUMN IF NOT EXISTS cancelada_at       timestamptz,
  ADD COLUMN IF NOT EXISTS motivo_cancelacion text,
  ADD COLUMN IF NOT EXISTS updated_at         timestamptz NOT NULL DEFAULT now();

COMMENT ON COLUMN muevete.solicitudes_transporte.precio_plataforma IS
  'Lo que paga el cliente. CONGELADO al crear la solicitud por fn_crear_solicitud. Inmutable con el flag encendido.';
COMMENT ON COLUMN muevete.solicitudes_transporte.precio_chofer IS
  'Neto del chofer. CONGELADO al crear la solicitud (precio_plataforma - comisión).';
COMMENT ON COLUMN muevete.solicitudes_transporte.tarifa_detalle IS
  'Snapshot del desglose devuelto por fn_cotizar_viaje (zona, km, multiplicador, recargos, comisión).';
COMMENT ON COLUMN muevete.solicitudes_transporte.tarifa_modo IS
  'Snapshot del modo de la zona aplicado: fijo | fijo_mas_km | por_km. NULL = fila histórica de negociación.';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'solicitudes_precio_plataforma_chk'
                    AND conrelid = 'muevete.solicitudes_transporte'::regclass) THEN
    ALTER TABLE muevete.solicitudes_transporte
      ADD CONSTRAINT solicitudes_precio_plataforma_chk
      CHECK (precio_plataforma IS NULL OR precio_plataforma >= 0) NOT VALID;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'solicitudes_comision_pct_chk'
                    AND conrelid = 'muevete.solicitudes_transporte'::regclass) THEN
    ALTER TABLE muevete.solicitudes_transporte
      ADD CONSTRAINT solicitudes_comision_pct_chk
      CHECK (comision_pct IS NULL OR comision_pct BETWEEN 0 AND 30) NOT VALID;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'solicitudes_tarifa_modo_chk'
                    AND conrelid = 'muevete.solicitudes_transporte'::regclass) THEN
    ALTER TABLE muevete.solicitudes_transporte
      ADD CONSTRAINT solicitudes_tarifa_modo_chk
      CHECK (tarifa_modo IS NULL
             OR tarifa_modo IN ('fijo','fijo_mas_km','por_km')) NOT VALID;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS solicitudes_estado_created_idx
  ON muevete.solicitudes_transporte (estado, created_at DESC);
CREATE INDEX IF NOT EXISTS solicitudes_driver_idx
  ON muevete.solicitudes_transporte (driver_id);
CREATE INDEX IF NOT EXISTS solicitudes_zona_estado_idx
  ON muevete.solicitudes_transporte (zona_id, estado);
CREATE INDEX IF NOT EXISTS solicitudes_pendientes_idx
  ON muevete.solicitudes_transporte (created_at DESC)
  WHERE estado = 'pendiente';

-- ----------------------------------------------------------------------------
-- 6. Columnas nuevas en muevete.viajes  +  driver_id smallint -> bigint
--    Columnas preexistentes: id, created_at, driver_id(smallint), "user",
--    estado(bool), visto(bool), user_display, completado(bool),
--    latitud_cliente(text), longitud_cliente(text), telefono, cobro_espera,
--    tiempo_espera_segundos.
-- ----------------------------------------------------------------------------

-- 6.1 Ampliación de tipo (metadata-only en PostgreSQL 11+).
--     OJO: PostgreSQL rechaza ALTER TYPE de una columna referenciada por una
--     política RLS ("0A000: cannot alter type of a column used in a policy
--     definition"). En muevete.viajes hay 3 políticas que usan driver_id.
--     Se eliminan, se altera el tipo y se recrean IDÉNTICAS en la misma
--     transacción, para que un fallo posterior las deje como estaban.
DROP POLICY IF EXISTS driver_own_viajes    ON muevete.viajes;
DROP POLICY IF EXISTS viajes_select_driver ON muevete.viajes;
DROP POLICY IF EXISTS viajes_update_driver ON muevete.viajes;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'muevete' AND table_name = 'viajes'
       AND column_name = 'driver_id' AND data_type = 'smallint'
  ) THEN
    ALTER TABLE muevete.viajes ALTER COLUMN driver_id TYPE bigint;
  END IF;
END $$;

-- Recreación exacta. Sin cláusula TO => PUBLIC, como estaban definidas.
CREATE POLICY driver_own_viajes ON muevete.viajes
  FOR ALL
  USING (driver_id IN (SELECT drivers.id FROM muevete.drivers WHERE drivers.uuid = auth.uid()));

CREATE POLICY viajes_select_driver ON muevete.viajes
  FOR SELECT
  USING (driver_id IN (SELECT drivers.id FROM muevete.drivers WHERE drivers.uuid = auth.uid()));

CREATE POLICY viajes_update_driver ON muevete.viajes
  FOR UPDATE
  USING (driver_id IN (SELECT drivers.id FROM muevete.drivers WHERE drivers.uuid = auth.uid()));

-- 6.2 Columnas nuevas
ALTER TABLE muevete.viajes
  ADD COLUMN IF NOT EXISTS solicitud_id     bigint REFERENCES muevete.solicitudes_transporte(id),
  ADD COLUMN IF NOT EXISTS precio_plataforma numeric,
  ADD COLUMN IF NOT EXISTS precio_chofer     numeric,
  ADD COLUMN IF NOT EXISTS comision_pct      numeric,
  ADD COLUMN IF NOT EXISTS metodo_pago       text,
  ADD COLUMN IF NOT EXISTS updated_at        timestamptz NOT NULL DEFAULT now();

COMMENT ON COLUMN muevete.viajes.solicitud_id IS
  'FK a la solicitud que originó el viaje. La escribe fn_tomar_viaje (antes el vínculo se deducía de ofertas_chofer).';

CREATE UNIQUE INDEX IF NOT EXISTS viajes_solicitud_id_uidx
  ON muevete.viajes (solicitud_id)
  WHERE solicitud_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS viajes_activos_idx
  ON muevete.viajes (driver_id)
  WHERE completado = false;

-- ----------------------------------------------------------------------------
-- 7. Triggers updated_at (reutilizan muevete.set_updated_at() del baseline)
-- ----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_zonas_tarifa_updated_at ON muevete.zonas_tarifa;
CREATE TRIGGER trg_zonas_tarifa_updated_at
  BEFORE UPDATE ON muevete.zonas_tarifa
  FOR EACH ROW EXECUTE FUNCTION muevete.set_updated_at();

DROP TRIGGER IF EXISTS trg_tarifas_municipio_updated_at ON muevete.tarifas_municipio;
CREATE TRIGGER trg_tarifas_municipio_updated_at
  BEFORE UPDATE ON muevete.tarifas_municipio
  FOR EACH ROW EXECUTE FUNCTION muevete.set_updated_at();

DROP TRIGGER IF EXISTS trg_configuracion_tarifas_updated_at ON muevete.configuracion_tarifas;
CREATE TRIGGER trg_configuracion_tarifas_updated_at
  BEFORE UPDATE ON muevete.configuracion_tarifas
  FOR EACH ROW EXECUTE FUNCTION muevete.set_updated_at();

DROP TRIGGER IF EXISTS trg_solicitudes_updated_at ON muevete.solicitudes_transporte;
CREATE TRIGGER trg_solicitudes_updated_at
  BEFORE UPDATE ON muevete.solicitudes_transporte
  FOR EACH ROW EXECUTE FUNCTION muevete.set_updated_at();

DROP TRIGGER IF EXISTS trg_viajes_updated_at ON muevete.viajes;
CREATE TRIGGER trg_viajes_updated_at
  BEFORE UPDATE ON muevete.viajes
  FOR EACH ROW EXECUTE FUNCTION muevete.set_updated_at();

-- ----------------------------------------------------------------------------
-- 8. Trigger de guarda del dinero (§2.8 del anexo)
--    Segunda línea de defensa: con el flag apagado no estorba a las apps viejas;
--    con el flag encendido, sólo las RPC (que marcan muevete.rpc='on') pueden
--    escribir las columnas de tarifa.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_solicitud_guarda()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = muevete, pg_temp
AS $$
BEGIN
  -- Sesiones de RPC (SECURITY DEFINER) marcan la transacción
  IF coalesce(current_setting('muevete.rpc', true), 'off') = 'on' THEN
    RETURN NEW;
  END IF;

  -- Flag apagado = modo legacy: no se estorba a las apps viejas
  IF NOT coalesce((SELECT taxi_precio_fijo_activo
                     FROM muevete.configuracion_tarifas WHERE id = 1), false) THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    RAISE EXCEPTION 'usar_fn_crear_solicitud' USING ERRCODE = '42501';
  END IF;

  IF NEW.precio_plataforma IS DISTINCT FROM OLD.precio_plataforma
     OR NEW.comision_pct    IS DISTINCT FROM OLD.comision_pct
     OR NEW.precio_chofer   IS DISTINCT FROM OLD.precio_chofer
     OR NEW.tarifa_detalle  IS DISTINCT FROM OLD.tarifa_detalle
     OR NEW.zona_id         IS DISTINCT FROM OLD.zona_id
     OR NEW.driver_id       IS DISTINCT FROM OLD.driver_id
     OR NEW.precio_oferta   IS DISTINCT FROM OLD.precio_oferta
  THEN
    RAISE EXCEPTION 'campos_de_tarifa_inmutables' USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION muevete.fn_solicitud_guarda() IS
  'Impide escribir precio/zona/driver por fuera de las RPC cuando taxi_precio_fijo_activo = true.';

DROP TRIGGER IF EXISTS trg_solicitud_guarda ON muevete.solicitudes_transporte;
CREATE TRIGGER trg_solicitud_guarda
  BEFORE INSERT OR UPDATE ON muevete.solicitudes_transporte
  FOR EACH ROW EXECUTE FUNCTION muevete.fn_solicitud_guarda();

COMMIT;

-- ============================================================================
-- VERIFICACIÓN (ejecutar a mano; NO forma parte de la migración)
-- ============================================================================
-- 1) Objetos creados:
--   SELECT table_name FROM information_schema.tables
--    WHERE table_schema='muevete'
--      AND table_name IN ('zonas_tarifa','tarifas_municipio','configuracion_tarifas');
--
-- 2) Columnas nuevas:
--   SELECT column_name, data_type FROM information_schema.columns
--    WHERE table_schema='muevete' AND table_name='solicitudes_transporte'
--      AND column_name IN ('driver_id','aceptada_at','zona_id','tarifa_modo',
--                          'precio_plataforma','comision_pct','precio_chofer',
--                          'moneda','tarifa_detalle','completada_at',
--                          'cancelada_at','motivo_cancelacion','updated_at')
--    ORDER BY column_name;
--   SELECT column_name FROM information_schema.columns
--    WHERE table_schema='muevete' AND table_name='viajes'
--      AND column_name IN ('solicitud_id','precio_plataforma','precio_chofer',
--                          'comision_pct','metodo_pago','updated_at');
--   SELECT column_name, data_type FROM information_schema.columns
--    WHERE table_schema='muevete' AND table_name='viajes' AND column_name='driver_id';
--      -- esperado: bigint
--
-- 3) Singleton de configuración:
--   SELECT id, comision_pct, permite_deuda, limite_deuda_efectivo,
--          taxi_precio_fijo_activo FROM muevete.configuracion_tarifas;
--      -- esperado: 1 fila, comision 15.00, permite_deuda true, limite 1000,
--      --           taxi_precio_fijo_activo false
--
-- 4) Triggers:
--   SELECT tgname FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
--     JOIN pg_namespace n ON n.oid=c.relnamespace
--    WHERE n.nspname='muevete'
--      AND tgname IN ('trg_zonas_tarifa_updated_at','trg_tarifas_municipio_updated_at',
--                     'trg_configuracion_tarifas_updated_at','trg_solicitudes_updated_at',
--                     'trg_viajes_updated_at','trg_solicitud_guarda')
--    ORDER BY tgname;
--      -- esperado: 6 filas
--
-- 5) Bundle único de viajes:
--   SELECT count(*) FROM muevete.viajes v GROUP BY v.solicitud_id
--     HAVING count(*) > 1 AND v.solicitud_id IS NOT NULL;
--      -- esperado: 0 filas
--
-- 6) Idempotencia: re-ejecutar 031 completo no debe lanzar error.
-- ============================================================================

-- ============================================================================
-- DOWN (rollback de esquema; documentado, NO ejecutar en despliegue normal)
-- ----------------------------------------------------------------------------
-- El rollback de NEGOCIO es apagar el flag, no borrar columnas:
--   UPDATE muevete.configuracion_tarifas SET taxi_precio_fijo_activo = false WHERE id = 1;
-- ============================================================================
-- BEGIN;
-- DROP TRIGGER IF EXISTS trg_solicitud_guarda ON muevete.solicitudes_transporte;
-- DROP FUNCTION IF EXISTS muevete.fn_solicitud_guarda();
-- DROP TRIGGER IF EXISTS trg_viajes_updated_at ON muevete.viajes;
-- DROP TRIGGER IF EXISTS trg_solicitudes_updated_at ON muevete.solicitudes_transporte;
-- DROP TRIGGER IF EXISTS trg_configuracion_tarifas_updated_at ON muevete.configuracion_tarifas;
-- DROP TRIGGER IF EXISTS trg_tarifas_municipio_updated_at ON muevete.tarifas_municipio;
-- DROP TRIGGER IF EXISTS trg_zonas_tarifa_updated_at ON muevete.zonas_tarifa;
--
-- DROP INDEX IF EXISTS muevete.viajes_activos_idx;
-- DROP INDEX IF EXISTS muevete.viajes_solicitud_id_uidx;
-- ALTER TABLE muevete.viajes
--   DROP COLUMN IF EXISTS solicitud_id,
--   DROP COLUMN IF EXISTS precio_plataforma,
--   DROP COLUMN IF EXISTS precio_chofer,
--   DROP COLUMN IF EXISTS comision_pct,
--   DROP COLUMN IF EXISTS metodo_pago,
--   DROP COLUMN IF EXISTS updated_at;
-- -- OJO: volver smallint sólo si todos los valores caben en 32767.
-- -- ALTER TABLE muevete.viajes ALTER COLUMN driver_id TYPE smallint;
--
-- DROP INDEX IF EXISTS muevete.solicitudes_pendientes_idx;
-- DROP INDEX IF EXISTS muevete.solicitudes_zona_estado_idx;
-- DROP INDEX IF EXISTS muevete.solicitudes_driver_idx;
-- DROP INDEX IF EXISTS muevete.solicitudes_estado_created_idx;
-- ALTER TABLE muevete.solicitudes_transporte
--   DROP CONSTRAINT IF EXISTS solicitudes_tarifa_modo_chk,
--   DROP CONSTRAINT IF EXISTS solicitudes_comision_pct_chk,
--   DROP CONSTRAINT IF EXISTS solicitudes_precio_plataforma_chk,
--   DROP COLUMN IF EXISTS driver_id,
--   DROP COLUMN IF EXISTS aceptada_at,
--   DROP COLUMN IF EXISTS zona_id,
--   DROP COLUMN IF EXISTS tarifa_modo,
--   DROP COLUMN IF EXISTS precio_plataforma,
--   DROP COLUMN IF EXISTS comision_pct,
--   DROP COLUMN IF EXISTS precio_chofer,
--   DROP COLUMN IF EXISTS moneda,
--   DROP COLUMN IF EXISTS tarifa_detalle,
--   DROP COLUMN IF EXISTS completada_at,
--   DROP COLUMN IF EXISTS cancelada_at,
--   DROP COLUMN IF EXISTS motivo_cancelacion,
--   DROP COLUMN IF EXISTS updated_at;
--
-- ALTER TABLE muevete.vehicle_type DROP CONSTRAINT IF EXISTS vehicle_type_multiplicador_chk;
-- ALTER TABLE muevete.vehicle_type DROP COLUMN IF EXISTS multiplicador_tarifa;
--
-- DROP TABLE IF EXISTS muevete.configuracion_tarifas;
-- DROP TABLE IF EXISTS muevete.tarifas_municipio;
-- DROP TABLE IF EXISTS muevete.zonas_tarifa;
-- COMMIT;
-- ============================================================================