-- ============================================================================
-- 037_taxi_seguridad.sql
-- Seguridad del viaje: contactos de emergencia, pánico (con outbox de envío
-- diferido), enlaces de viaje compartido, verificación mutua, incidentes,
-- bloqueos y emparejamientos bloqueados.
--
-- ANEXO DE DISEÑO: docs/plan-taxi-precio-fijo/07-seguridad-del-viaje.md §4 y §3
--
-- PRERREQUISITOS
--   · 030_baseline_sync_produccion.sql (NO se redefine: set_updated_at,
--     get_my_driver_id, is_superadmin, complete_ride_payment, triggers de push)
--   · 031_taxi_zonas_tarifas.sql        (solicitudes_transporte, viajes)
--   · 035/036                           (no se tocan)
--
-- QUÉ HACE
--   1. configuracion_seguridad (singleton de umbrales).
--   2. contactos_emergencia (validación por OTP o por token de invitación).
--   3. eventos_panico + eventos_panico_ubicaciones (con estado de ENVÍO DIFERIDO
--      para cuando el teléfono no tiene red).
--   4. enlaces_viaje (token hasheado, expiración, permisos) + viaje_ubicaciones.
--      El enlace público NO da acceso a tablas: sólo a la RPC fn_ver_enlace_viaje.
--   5. incidentes, bloqueos, emparejamientos_bloqueados.
--   6. Columnas de seguridad en solicitudes_transporte y viajes.
--   7. RPCs (SECURITY DEFINER) + triggers de cierre + RLS.
--
-- REGLAS
--   · Sin `service_role`: todo lo privilegiado va por RPC SECURITY DEFINER.
--     ÚNICA excepción de lectura pública: `fn_ver_enlace_viaje(token)` se
--     concede a `anon` porque el enlace compartido se abre sin sesión; valida
--     token + expiración + permisos y devuelve sólo datos de la whitelist
--     (nunca teléfono, CI completa, correo ni documentos).
--   · El token en claro NUNCA se guarda: sólo sha256(token || pepper).
--     El pepper se lee de Vault (seguridad_token_pepper) o del GUC
--     muevete.seguridad_pepper. Si no existe, fn_token_hash LANZA
--     pepper_no_configurado: NO hay fallback literal en producción (sólo
--     se admite un literal de test con muevete.entorno=dev).
--     El OTP de contactos NUNCA se devuelve en producción; sin SMS el
--     contacto queda verificado=false ('sin verificar').
--   · La Edge Function pública del enlace en vivo NO se implementa aquí:
--     sólo modelo de datos + RPC. Su despliegue es una decisión aparte.
--
-- DEPENDENCIA CON 041 (anotada, no implementada aquí)
--   Cuando 041 cierre `drivers_see_solicitudes`, el pánico y la verificación
--   mutua NO deben depender de que la app lea solicitudes ajenas: las RPC de
--   este archivo son SECURITY DEFINER y resuelven la participación en servidor.
--   Además, 041 debe crear `solicitudes_select_driver_asignado`
--   (driver_id = get_my_driver_id()) para que las pantallas del chofer lean su
--   propia solicitud.
--
-- IDEMPOTENCIA: IF NOT EXISTS / OR REPLACE / DROP POLICY IF EXISTS /
--   DROP TRIGGER IF EXISTS + CREATE / INSERT ... ON CONFLICT.
--
-- NO EJECUTAR CONTRA SUPABASE DESDE ESTE ENTORNO (sólo se entrega el archivo).
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. muevete.configuracion_seguridad (singleton)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS muevete.configuracion_seguridad (
  id                          smallint PRIMARY KEY DEFAULT 1,
  numeros_emergencia          jsonb NOT NULL DEFAULT '{"policia":"106"}'::jsonb,
  contacto_soporte            text  NOT NULL DEFAULT '',
  horario_revision            text  NOT NULL DEFAULT 'L-V 09:00-17:00',
  max_contactos               smallint NOT NULL DEFAULT 3,
  minutos_vida_enlace         integer  NOT NULL DEFAULT 120,
  minutos_tracking_panico     integer  NOT NULL DEFAULT 30,
  segundos_muestreo_panico    integer  NOT NULL DEFAULT 15,
  umbral_bloqueo_incidentes   smallint NOT NULL DEFAULT 2,
  dias_ventana_reincidencia   integer  NOT NULL DEFAULT 90,
  dias_bloqueo_temporal       integer  NOT NULL DEFAULT 30,
  no_show_umbral              smallint NOT NULL DEFAULT 3,
  dias_restriccion_no_show    integer  NOT NULL DEFAULT 7,
  dias_ventana_reporte        integer  NOT NULL DEFAULT 7,
  horas_sla_critico           integer  NOT NULL DEFAULT 24,
  horas_sla_normal            integer  NOT NULL DEFAULT 48,
  dias_retencion_ubicaciones  integer  NOT NULL DEFAULT 30,
  meses_retencion_incidentes  integer  NOT NULL DEFAULT 24,
  modo_panico_default         text NOT NULL DEFAULT 'discreto',
  actualizado_at              timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT configuracion_seguridad_singleton CHECK (id = 1),
  CONSTRAINT configuracion_seguridad_modo_chk
    CHECK (modo_panico_default IN ('discreto','visible')),
  CONSTRAINT configuracion_seguridad_limites_chk CHECK (
       max_contactos BETWEEN 1 AND 5
   AND minutos_vida_enlace BETWEEN 5 AND 1440
   AND minutos_tracking_panico BETWEEN 5 AND 240
   AND segundos_muestreo_panico BETWEEN 5 AND 120
  )
);

INSERT INTO muevete.configuracion_seguridad (id) VALUES (1)
ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION muevete.fn_config_seguridad_touch()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = muevete, pg_temp
AS $$
BEGIN
  NEW.actualizado_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_configuracion_seguridad_touch ON muevete.configuracion_seguridad;
CREATE TRIGGER trg_configuracion_seguridad_touch
  BEFORE UPDATE ON muevete.configuracion_seguridad
  FOR EACH ROW EXECUTE FUNCTION muevete.fn_config_seguridad_touch();

COMMENT ON TABLE muevete.configuracion_seguridad IS
  'Umbrales y textos de seguridad. El número de policía sale de aquí (numeros_emergencia->>''policia''), no del código Dart.';

-- ----------------------------------------------------------------------------
-- 2. muevete.contactos_emergencia
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS muevete.contactos_emergencia (
  id                   bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  user_uuid            uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  nombre               text NOT NULL CHECK (char_length(btrim(nombre)) BETWEEN 2 AND 60),
  telefono             text NOT NULL CHECK (telefono ~ '^\+[0-9]{8,15}$'),  -- E.164
  parentesco           text,
  prioridad            smallint NOT NULL DEFAULT 2 CHECK (prioridad BETWEEN 1 AND 3),
  canal                text NOT NULL DEFAULT 'sms' CHECK (canal IN ('push','sms','whatsapp')),
  contacto_uuid        uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  estado               text NOT NULL DEFAULT 'pendiente'
                         CHECK (estado IN ('pendiente','aceptado','rechazado','revocado')),
  -- Sin proveedor SMS de servidor el contacto puede usarse SIN verificar.
  verificado           boolean NOT NULL DEFAULT false,
  codigo_hash          text,          -- OTP de 4 dígitos (hash)
  codigo_expira_at     timestamptz,
  token_hash           text,          -- invitación por enlace (Edge Function)
  token_expira_at      timestamptz,
  aceptado_at          timestamptz,
  aceptado_ip          inet,
  intentos_validacion  smallint NOT NULL DEFAULT 0,
  avisos_sin_entrega   smallint NOT NULL DEFAULT 0,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT contactos_emergencia_pkey PRIMARY KEY (id)
);

CREATE UNIQUE INDEX IF NOT EXISTS contactos_emergencia_user_tel_uidx
  ON muevete.contactos_emergencia (user_uuid, telefono) WHERE estado <> 'revocado';
CREATE UNIQUE INDEX IF NOT EXISTS contactos_emergencia_principal_uidx
  ON muevete.contactos_emergencia (user_uuid) WHERE prioridad = 1 AND estado = 'aceptado';
CREATE UNIQUE INDEX IF NOT EXISTS contactos_emergencia_token_uidx
  ON muevete.contactos_emergencia (token_hash) WHERE token_hash IS NOT NULL;
CREATE INDEX IF NOT EXISTS contactos_emergencia_contacto_idx
  ON muevete.contactos_emergencia (contacto_uuid) WHERE contacto_uuid IS NOT NULL;

DROP TRIGGER IF EXISTS trg_contactos_emergencia_updated_at ON muevete.contactos_emergencia;
CREATE TRIGGER trg_contactos_emergencia_updated_at
  BEFORE UPDATE ON muevete.contactos_emergencia
  FOR EACH ROW EXECUTE FUNCTION muevete.set_updated_at();

-- Validaciones de negocio que no caben en un CHECK:
--   · no ser uno mismo (misma cuenta o mismo teléfono normalizado)
--   · máximo de contactos vigentes (config)
--   · no borrar el último contacto aceptado
CREATE OR REPLACE FUNCTION muevete.fn_contacto_emergencia_guarda()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_max        smallint := 3;
  v_mi_tel     text;
  v_vigentes   integer;
  v_aceptados  integer;
BEGIN
  SELECT coalesce(max_contactos, 3) INTO v_max
    FROM muevete.configuracion_seguridad WHERE id = 1;

  IF TG_OP = 'DELETE' THEN
    IF OLD.estado = 'aceptado' THEN
      SELECT count(*) INTO v_aceptados
        FROM muevete.contactos_emergencia
       WHERE user_uuid = OLD.user_uuid AND estado = 'aceptado' AND id <> OLD.id;
      IF v_aceptados = 0 THEN
        RAISE EXCEPTION 'no_puedes_borrar_el_ultimo_contacto_aceptado' USING ERRCODE = 'P0111';
      END IF;
    END IF;
    RETURN OLD;
  END IF;

  -- No ser uno mismo por cuenta
  IF NEW.contacto_uuid IS NOT NULL AND NEW.contacto_uuid = NEW.user_uuid THEN
    RAISE EXCEPTION 'contacto_invalido: mismo usuario' USING ERRCODE = 'P0112';
  END IF;

  -- No ser uno mismo por teléfono (users.phone puede venir '55512345' o '+5355512345')
  SELECT regexp_replace(coalesce(phone, ''), '\D', '', 'g') INTO v_mi_tel
    FROM muevete.users WHERE uuid = NEW.user_uuid LIMIT 1;
  IF v_mi_tel <> ''
     AND regexp_replace(NEW.telefono, '\D', '', 'g') = v_mi_tel THEN
    RAISE EXCEPTION 'contacto_invalido: mismo telefono' USING ERRCODE = 'P0112';
  END IF;

  -- Máximo de contactos vigentes
  SELECT count(*) INTO v_vigentes
    FROM muevete.contactos_emergencia
   WHERE user_uuid = NEW.user_uuid
     AND estado <> 'revocado'
     AND (TG_OP = 'INSERT' OR id <> NEW.id);
  IF v_vigentes >= v_max THEN
    RAISE EXCEPTION 'maximo_contactos_alcanzado: %', v_max USING ERRCODE = 'P0113';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_contactos_emergencia_guarda ON muevete.contactos_emergencia;
CREATE TRIGGER trg_contactos_emergencia_guarda
  BEFORE INSERT OR UPDATE OR DELETE ON muevete.contactos_emergencia
  FOR EACH ROW EXECUTE FUNCTION muevete.fn_contacto_emergencia_guarda();

COMMENT ON TABLE muevete.contactos_emergencia IS
  'Contactos de emergencia del usuario (máx 3, prioridad 1 obligatoria y aceptada). Se validan por OTP o por invitación en app.';

-- ----------------------------------------------------------------------------
-- 3. Pánico (evento + posiciones) con OUTBOX de envío diferido
--    envio_estado: pendiente_envio (sin red/confirmación), enviado, fallido, no_aplica
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS muevete.eventos_panico (
  id                          bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  client_event_id             uuid NOT NULL UNIQUE,   -- idempotencia del disparo
  solicitud_id                bigint NOT NULL REFERENCES muevete.solicitudes_transporte(id) ON DELETE RESTRICT,
  viaje_id                    bigint REFERENCES muevete.viajes(id) ON DELETE SET NULL,
  user_uuid                   uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  rol                         text NOT NULL CHECK (rol IN ('cliente','chofer')),
  modo                        text NOT NULL DEFAULT 'discreto'
                                CHECK (modo IN ('discreto','visible','solo_106')),
  origen                      text NOT NULL DEFAULT 'boton'
                                CHECK (origen IN ('boton','accesibilidad','automatico','solo_106')),
  lat                         double precision CHECK (lat BETWEEN -90 AND 90),
  lon                         double precision CHECK (lon BETWEEN -180 AND 180),
  precision_m                 real,
  capturado_at                timestamptz NOT NULL,
  recibido_at                 timestamptz NOT NULL DEFAULT now(),
  estado                      text NOT NULL DEFAULT 'activo'
                                CHECK (estado IN ('activo','cancelado_falso','gestionado','cerrado')),
  acciones                    jsonb NOT NULL DEFAULT '[]'::jsonb,
  notificados                 jsonb NOT NULL DEFAULT '[]'::jsonb,
  contacto_ppal_enmascarado   text,
  -- Outbox: el evento se registra aunque el envío a contactos falle
  envio_estado                text NOT NULL DEFAULT 'pendiente_envio'
                                CHECK (envio_estado IN ('pendiente_envio','enviado','fallido','no_aplica')),
  envio_intentos              smallint NOT NULL DEFAULT 0,
  envio_ultimo_error          text,
  enviado_at                  timestamptz,
  atendido_por                uuid,
  atendido_at                 timestamptz,
  created_at                  timestamptz NOT NULL DEFAULT now(),
  updated_at                  timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT eventos_panico_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS eventos_panico_abiertos_idx
  ON muevete.eventos_panico (created_at DESC) WHERE estado = 'activo';
CREATE INDEX IF NOT EXISTS eventos_panico_user_idx
  ON muevete.eventos_panico (user_uuid, created_at DESC);
CREATE INDEX IF NOT EXISTS eventos_panico_outbox_idx
  ON muevete.eventos_panico (envio_estado, capturado_at)
  WHERE envio_estado = 'pendiente_envio';

DROP TRIGGER IF EXISTS trg_eventos_panico_updated_at ON muevete.eventos_panico;
CREATE TRIGGER trg_eventos_panico_updated_at
  BEFORE UPDATE ON muevete.eventos_panico
  FOR EACH ROW EXECUTE FUNCTION muevete.set_updated_at();

CREATE TABLE IF NOT EXISTS muevete.eventos_panico_ubicaciones (
  id             bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  evento_id      bigint NOT NULL REFERENCES muevete.eventos_panico(id) ON DELETE CASCADE,
  lat            double precision NOT NULL,
  lon            double precision NOT NULL,
  precision_m    real,
  velocidad_mps  real,
  capturado_at   timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT eventos_panico_ubicaciones_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS eventos_panico_ubicaciones_evento_idx
  ON muevete.eventos_panico_ubicaciones (evento_id, capturado_at);

COMMENT ON COLUMN muevete.eventos_panico.envio_estado IS
  'Outbox: pendiente_envio = registrado pero el aviso a contactos aún no se confirmó (sin red o push no entregado). Reintento por RPC.';

-- ----------------------------------------------------------------------------
-- 4. Enlaces de viaje compartido + posiciones del viaje
--    El token en claro NUNCA se guarda: sha256(token || pepper) en token_hash.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS muevete.enlaces_viaje (
  id                    bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  solicitud_id          bigint NOT NULL REFERENCES muevete.solicitudes_transporte(id) ON DELETE CASCADE,
  viaje_id              bigint REFERENCES muevete.viajes(id) ON DELETE SET NULL,
  creado_por_uuid       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  rol                   text NOT NULL DEFAULT 'cliente' CHECK (rol IN ('cliente','chofer')),
  token_hash            text NOT NULL UNIQUE,
  alcance               text NOT NULL DEFAULT 'completo' CHECK (alcance IN ('completo','solo_estado')),
  permisos              jsonb NOT NULL DEFAULT
                          '{"ubicacion":true,"contraparte":true,"destino":true,"telefono":false,"ci":false}'::jsonb,
  expira_at             timestamptz NOT NULL,
  revocado_at           timestamptz,
  motivo_revocacion     text,
  accesos               integer NOT NULL DEFAULT 0,
  ultimo_acceso_at      timestamptz,
  ultima_ip_truncada    inet,          -- /24; la setea la capa pública si puede
  created_at            timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT enlaces_viaje_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS enlaces_viaje_vigentes_idx
  ON muevete.enlaces_viaje (token_hash) WHERE revocado_at IS NULL;
CREATE INDEX IF NOT EXISTS enlaces_viaje_solicitud_idx
  ON muevete.enlaces_viaje (solicitud_id);

COMMENT ON TABLE muevete.enlaces_viaje IS
  'Enlaces de viaje compartido. token_hash = sha256(token||pepper); el token en claro sólo se devuelve al crearlo. El público lee por RPC, nunca por tabla.';

CREATE TABLE IF NOT EXISTS muevete.viaje_ubicaciones (
  id            bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  solicitud_id  bigint NOT NULL REFERENCES muevete.solicitudes_transporte(id) ON DELETE CASCADE,
  rol           text NOT NULL CHECK (rol IN ('cliente','chofer')),
  lat           double precision NOT NULL,
  lon           double precision NOT NULL,
  precision_m   real,
  capturado_at  timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT viaje_ubicaciones_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS viaje_ubicaciones_sol_idx
  ON muevete.viaje_ubicaciones (solicitud_id, capturado_at DESC);

-- ----------------------------------------------------------------------------
-- 5. Incidentes, bloqueos y emparejamientos bloqueados
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS muevete.incidentes (
  id                     bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  solicitud_id           bigint REFERENCES muevete.solicitudes_transporte(id) ON DELETE SET NULL,
  viaje_id               bigint REFERENCES muevete.viajes(id) ON DELETE SET NULL,
  reportado_por_uuid     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  rol_reporta            text NOT NULL CHECK (rol_reporta IN ('cliente','chofer')),
  contraparte_uuid       uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  contraparte_driver_id  bigint REFERENCES muevete.drivers(id) ON DELETE SET NULL,
  tipo                   text NOT NULL CHECK (tipo IN (
                           'robo_con_violencia','robo_sin_violencia','agresion_fisica','amenaza',
                           'acoso_sexual','acoso_verbal','suplantacion','vehiculo_incorrecto',
                           'no_show_pasajero','cobro_abusivo','extorsion','otro')),
  severidad              text NOT NULL CHECK (severidad IN ('baja','media','alta','critica')),
  descripcion            text NOT NULL CHECK (char_length(descripcion) BETWEEN 20 AND 2000),
  evidencia              jsonb NOT NULL DEFAULT '[]'::jsonb,
  estado                 text NOT NULL DEFAULT 'reportado'
                           CHECK (estado IN ('reportado','en_revision','confirmado','descartado','escalado')),
  solicita_no_emparejar  boolean NOT NULL DEFAULT false,
  posicion_al_reportar   jsonb,
  revisado_por           uuid,
  revisado_at            timestamptz,
  resolucion             text,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT incidentes_pkey PRIMARY KEY (id),
  CONSTRAINT incidentes_no_autoreporte
    CHECK (contraparte_uuid IS NULL OR contraparte_uuid <> reportado_por_uuid)
);

CREATE INDEX IF NOT EXISTS incidentes_bandeja_idx
  ON muevete.incidentes (estado, severidad, created_at DESC);
CREATE INDEX IF NOT EXISTS incidentes_sujeto_idx
  ON muevete.incidentes (contraparte_uuid, created_at DESC) WHERE contraparte_uuid IS NOT NULL;
CREATE INDEX IF NOT EXISTS incidentes_driver_idx
  ON muevete.incidentes (contraparte_driver_id, created_at DESC) WHERE contraparte_driver_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS incidentes_sin_duplicados_uidx
  ON muevete.incidentes (reportado_por_uuid, viaje_id, tipo)
  WHERE viaje_id IS NOT NULL AND estado <> 'descartado';

DROP TRIGGER IF EXISTS trg_incidentes_updated_at ON muevete.incidentes;
CREATE TRIGGER trg_incidentes_updated_at
  BEFORE UPDATE ON muevete.incidentes
  FOR EACH ROW EXECUTE FUNCTION muevete.set_updated_at();

CREATE TABLE IF NOT EXISTS muevete.bloqueos (
  id              bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  user_uuid       uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  driver_id       bigint REFERENCES muevete.drivers(id) ON DELETE CASCADE,
  tipo_bloqueo    text NOT NULL CHECK (tipo_bloqueo IN
                    ('automatico_temporal','administrativo','permanente','restriccion_no_show')),
  motivo          text NOT NULL,
  incidente_id    bigint REFERENCES muevete.incidentes(id) ON DELETE SET NULL,
  vigente_desde   timestamptz NOT NULL DEFAULT now(),
  vigente_hasta   timestamptz,
  creado_por      uuid,
  creado_motivo   text,
  revocado_por    uuid,
  revocado_at     timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT bloqueos_pkey PRIMARY KEY (id),
  CONSTRAINT bloqueos_un_solo_sujeto CHECK (num_nonnulls(user_uuid, driver_id) = 1)
);

CREATE INDEX IF NOT EXISTS bloqueos_user_vigentes_idx
  ON muevete.bloqueos (user_uuid) WHERE revocado_at IS NULL;
CREATE INDEX IF NOT EXISTS bloqueos_driver_vigentes_idx
  ON muevete.bloqueos (driver_id) WHERE revocado_at IS NULL;

CREATE TABLE IF NOT EXISTS muevete.emparejamientos_bloqueados (
  id            bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  user_uuid     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  driver_id     bigint NOT NULL REFERENCES muevete.drivers(id) ON DELETE CASCADE,
  motivo        text NOT NULL,
  incidente_id  bigint REFERENCES muevete.incidentes(id) ON DELETE SET NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT emparejamientos_bloqueados_pkey PRIMARY KEY (id),
  CONSTRAINT emparejamientos_bloqueados_uidx UNIQUE (user_uuid, driver_id)
);

-- ----------------------------------------------------------------------------
-- 6. Columnas nuevas en tablas existentes (aditivas)
-- ----------------------------------------------------------------------------
ALTER TABLE muevete.solicitudes_transporte
  ADD COLUMN IF NOT EXISTS seguridad_snapshot jsonb;

ALTER TABLE muevete.viajes
  ADD COLUMN IF NOT EXISTS abordaje_at           timestamptz,
  ADD COLUMN IF NOT EXISTS abordaje_metodo       text,
  ADD COLUMN IF NOT EXISTS abordaje_confirmado_por uuid,
  ADD COLUMN IF NOT EXISTS chapa_confirmada      boolean;

COMMENT ON COLUMN muevete.solicitudes_transporte.seguridad_snapshot IS
  'Snapshot de seguridad por solicitud: {contacto_ok, contacto_masked, compartido, enlaces, ficha_servida, cerrado_at}.';
COMMENT ON COLUMN muevete.viajes.abordaje_metodo IS
  'ficha | cache | sin_verificacion. Registra cómo se verificó la identidad al abordar.';

-- ============================================================================
-- 7. HELPERS INTERNOS
-- ============================================================================

-- Hash del token/enlace. Pepper: Vault o GUC. NUNCA se guarda el token en claro.
CREATE OR REPLACE FUNCTION muevete.fn_token_hash(p_token text)
RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = muevete, public, extensions, pg_temp
AS $$
DECLARE
  v_pepper text;
BEGIN
  BEGIN
    SELECT decrypted_secret INTO v_pepper
      FROM vault.decrypted_secrets
     WHERE name = 'seguridad_token_pepper'
     LIMIT 1;
  EXCEPTION WHEN others THEN
    v_pepper := NULL;
  END;

  IF v_pepper IS NULL OR v_pepper = '' THEN
    v_pepper := current_setting('muevete.seguridad_pepper', true);
  END IF;

  IF v_pepper IS NULL OR v_pepper = '' THEN
    -- Sin pepper NO se hashea: un literal público anularía la seguridad del token.
    IF coalesce(current_setting('muevete.entorno', true), '') = 'dev' THEN
      v_pepper := 'dev-only-pepper-no-usar-en-produccion';
    ELSE
      RAISE EXCEPTION 'pepper_no_configurado'
        USING ERRCODE = 'P0120',
              HINT = 'Crear vault.secrets(name=seguridad_token_pepper) o fijar GUC muevete.seguridad_pepper';
    END IF;
  END IF;

  RETURN encode(digest(p_token || v_pepper, 'sha256'), 'hex');
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_token_hash(text) FROM PUBLIC, anon, authenticated;

-- ¿El par usuario↔chofer tiene un bloqueo de emparejamiento?
CREATE OR REPLACE FUNCTION muevete.fn_emparejamiento_bloqueado(
  p_user_uuid uuid,
  p_driver_id bigint
) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM muevete.emparejamientos_bloqueados e
     WHERE e.user_uuid = p_user_uuid AND e.driver_id = p_driver_id
  );
$$;

REVOKE ALL ON FUNCTION muevete.fn_emparejamiento_bloqueado(uuid, bigint) FROM PUBLIC, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 8. RPC · fn_gate_seguridad
--    ok = tiene contacto de emergencia aceptado (prioridad 1) y no está bloqueado.
--    Lo llaman la app (pantalla de gate), 038 (crear) y 039 (tomar).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_gate_seguridad(
  p_user_uuid uuid,
  p_driver_id bigint DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_motivos text[] := ARRAY[]::text[];
  v_tiene_contacto boolean := false;
  v_contacto_verificado boolean := false;
  v_bloqueo_motivo text;
  v_bloqueo_hasta  timestamptz;
BEGIN
  IF p_user_uuid IS DISTINCT FROM auth.uid()
     AND NOT muevete.is_superadmin()
     AND p_driver_id IS DISTINCT FROM muevete.get_my_driver_id() THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  -- Sin SMS de servidor, exigir OTP bloquearía a todos. El gate exige un
  -- contacto DESIGNado (pendiente o aceptado) y expone si está verificado.
  SELECT EXISTS (
    SELECT 1 FROM muevete.contactos_emergencia
     WHERE user_uuid = p_user_uuid
       AND prioridad = 1
       AND estado IN ('pendiente','aceptado')
  ) INTO v_tiene_contacto;

  IF NOT v_tiene_contacto THEN
    v_motivos := array_append(v_motivos, 'sin_contacto_emergencia');
  END IF;

  SELECT coalesce((
    SELECT c.verificado FROM muevete.contactos_emergencia c
     WHERE c.user_uuid = p_user_uuid AND c.prioridad = 1
       AND c.estado IN ('pendiente','aceptado')
     ORDER BY c.verificado DESC LIMIT 1), false) INTO v_contacto_verificado;

  SELECT b.motivo, b.vigente_hasta INTO v_bloqueo_motivo, v_bloqueo_hasta
    FROM muevete.bloqueos b
   WHERE b.revocado_at IS NULL
     AND (b.vigente_hasta IS NULL OR b.vigente_hasta > now())
     AND (b.user_uuid = p_user_uuid
          OR (p_driver_id IS NOT NULL AND b.driver_id = p_driver_id))
   ORDER BY b.vigente_desde DESC
   LIMIT 1;

  IF v_bloqueo_motivo IS NOT NULL THEN
    v_motivos := array_append(v_motivos, 'bloqueado');
  END IF;

  RETURN jsonb_build_object(
    'ok',               cardinality(v_motivos) = 0,
    'motivos',          to_jsonb(v_motivos),
    'contacto_verificado', v_contacto_verificado,
    'bloqueado_hasta',  v_bloqueo_hasta,
    'motivo_bloqueo_publico',
      CASE WHEN v_bloqueo_motivo IS NULL THEN NULL
           ELSE 'Reportes de seguridad confirmados' END
  );
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_gate_seguridad(uuid, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_gate_seguridad(uuid, bigint) TO authenticated;

-- ----------------------------------------------------------------------------
-- 9. RPC · validación de contacto: iniciar (OTP) y confirmar (OTP o invitación)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_iniciar_validacion_contacto(p_contacto_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, public, extensions, pg_temp
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_c      muevete.contactos_emergencia%ROWTYPE;
  v_codigo text;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'no_autenticado' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO v_c FROM muevete.contactos_emergencia WHERE id = p_contacto_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'contacto_no_existe' USING ERRCODE = 'P0114';
  END IF;
  IF v_c.user_uuid <> v_uid THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;
  IF v_c.estado = 'aceptado' THEN
    RETURN jsonb_build_object('success', true, 'estado', 'aceptado', 'ya_validado', true);
  END IF;

  v_codigo := lpad((floor(random() * 10000))::int::text, 4, '0');

  UPDATE muevete.contactos_emergencia
     SET codigo_hash      = muevete.fn_token_hash(v_codigo),
         codigo_expira_at = now() + interval '24 hours',
         intentos_validacion = 0
   WHERE id = p_contacto_id;

  -- El OTP NUNCA se devuelve al cliente en producción: permitiría verificar
  -- un teléfono ajeno. Sin proveedor SMS el contacto queda verificado=false
  -- y la UI muestra 'sin verificar'. El código sólo se retorna en entorno dev.
  IF coalesce(current_setting('muevete.entorno', true), '') = 'dev' THEN
    RETURN jsonb_build_object(
      'success',     true,
      'contacto_id', p_contacto_id,
      'codigo',      v_codigo,
      'entorno_dev', true,
      'expira_at',   now() + interval '24 hours',
      'mensaje',     'Entorno dev: código devuelto para pruebas');
  END IF;

  RETURN jsonb_build_object(
    'success',     true,
    'contacto_id', p_contacto_id,
    'entorno_dev', false,
    'verificado',  false,
    'expira_at',   now() + interval '24 hours',
    'mensaje',     'Contacto guardado sin verificar. Sin SMS de servidor no podemos confirmar el número.');
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_iniciar_validacion_contacto(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_iniciar_validacion_contacto(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION muevete.fn_confirmar_contacto(
  p_contacto_id bigint,
  p_codigo      text DEFAULT NULL,
  p_token       text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, public, extensions, pg_temp
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_c      muevete.contactos_emergencia%ROWTYPE;
  v_ok     boolean := false;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'no_autenticado' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO v_c FROM muevete.contactos_emergencia WHERE id = p_contacto_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'contacto_no_existe' USING ERRCODE = 'P0114';
  END IF;

  -- El titular puede confirmar con el OTP; el contacto invitado también
  IF v_uid <> v_c.user_uuid AND v_uid <> coalesce(v_c.contacto_uuid, v_uid) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  IF p_token IS NOT NULL AND v_c.token_hash IS NOT NULL
     AND v_c.token_expira_at > now()
     AND muevete.fn_token_hash(p_token) = v_c.token_hash THEN
    v_ok := true;
  ELSIF p_codigo IS NOT NULL AND v_c.codigo_hash IS NOT NULL
        AND v_c.codigo_expira_at > now()
        AND muevete.fn_token_hash(p_codigo) = v_c.codigo_hash THEN
    v_ok := true;
  ELSIF v_uid = v_c.contacto_uuid AND v_c.estado = 'pendiente' THEN
    -- Aceptación desde la app del contacto (invitación in-app)
    v_ok := true;
  END IF;

  IF NOT v_ok THEN
    UPDATE muevete.contactos_emergencia
       SET intentos_validacion = CASE WHEN intentos_validacion + 1 >= 3 THEN 0
                                      ELSE intentos_validacion + 1 END,
           codigo_hash      = CASE WHEN intentos_validacion + 1 >= 3 THEN NULL
                                   ELSE codigo_hash END,
           codigo_expira_at = CASE WHEN intentos_validacion + 1 >= 3 THEN NULL
                                   ELSE codigo_expira_at END
     WHERE id = p_contacto_id;
    RAISE EXCEPTION 'codigo_invalido' USING ERRCODE = 'P0115';
  END IF;

  UPDATE muevete.contactos_emergencia
     SET estado        = 'aceptado',
         verificado    = true,
         aceptado_at   = now(),
         codigo_hash   = NULL,
         token_hash    = NULL
   WHERE id = p_contacto_id;

  RETURN jsonb_build_object('success', true, 'estado', 'aceptado',
                            'contacto_id', p_contacto_id);
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_confirmar_contacto(bigint, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_confirmar_contacto(bigint, text, text) TO authenticated;

-- ----------------------------------------------------------------------------
-- 10. RPC · fn_disparar_panico (pieza crítica; registra aunque falle el envío)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_disparar_panico(
  p_solicitud_id    bigint,
  p_client_event_id uuid,
  p_lat             double precision,
  p_lon             double precision,
  p_precision_m     real DEFAULT NULL,
  p_modo            text DEFAULT 'discreto',
  p_compartir       boolean DEFAULT true,
  p_capturado_at    timestamptz DEFAULT now()
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, public, extensions, pg_temp
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_sol       muevete.solicitudes_transporte%ROWTYPE;
  v_evento    bigint;
  v_enlace    jsonb;
  v_contactos jsonb;
  v_viaje_id  bigint;
  v_rol       text;
  v_tracking_min integer := 30;
  v_muestreo_s   integer := 15;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'no_autenticado' USING ERRCODE = 'P0100';
  END IF;
  IF p_modo NOT IN ('discreto','visible','solo_106') THEN
    RAISE EXCEPTION 'modo_invalido: %', p_modo USING ERRCODE = 'P0001';
  END IF;

  SELECT coalesce(minutos_tracking_panico,30), coalesce(segundos_muestreo_panico,15)
    INTO v_tracking_min, v_muestreo_s
    FROM muevete.configuracion_seguridad WHERE id = 1;
  SELECT * INTO v_sol FROM muevete.solicitudes_transporte WHERE id = p_solicitud_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'solicitud_no_existe' USING ERRCODE = 'P0101';
  END IF;

  -- Sólo los dos participantes del viaje
  IF v_sol.user_id <> v_uid
     AND NOT EXISTS (SELECT 1 FROM muevete.drivers d
                      WHERE d.id = v_sol.driver_id AND d.uuid = v_uid) THEN
    RAISE EXCEPTION 'no_participante' USING ERRCODE = 'P0102';
  END IF;

  -- Ventana válida: aceptada, o hasta 10 min después de completada
  IF NOT (
       v_sol.estado = 'aceptada'
       OR (v_sol.estado = 'completada' AND EXISTS (
             SELECT 1 FROM muevete.viajes v
              WHERE v.solicitud_id = p_solicitud_id
                AND v.updated_at > now() - interval '10 minutes'))
  ) THEN
    RAISE EXCEPTION 'viaje_no_activo' USING ERRCODE = 'P0103';
  END IF;

  -- Idempotencia por client_event_id
  SELECT id INTO v_evento FROM muevete.eventos_panico
   WHERE client_event_id = p_client_event_id;
  IF v_evento IS NOT NULL THEN
    RETURN jsonb_build_object('evento_id', v_evento, 'duplicado', true);
  END IF;

  SELECT id INTO v_viaje_id FROM muevete.viajes
   WHERE solicitud_id = p_solicitud_id ORDER BY id DESC LIMIT 1;

  v_rol := CASE WHEN v_sol.user_id = v_uid THEN 'cliente' ELSE 'chofer' END;

  BEGIN
  INSERT INTO muevete.eventos_panico (
    client_event_id, solicitud_id, viaje_id, user_uuid, rol, modo, origen,
    lat, lon, precision_m, capturado_at,
    envio_estado, acciones
  ) VALUES (
    p_client_event_id, p_solicitud_id, v_viaje_id, v_uid, v_rol, p_modo, 'boton',
    p_lat, p_lon, p_precision_m, coalesce(p_capturado_at, now()),
    'pendiente_envio',
    jsonb_build_array(jsonb_build_object('tipo','disparo','at', now(), 'modo', p_modo))
  ) RETURNING id INTO v_evento;
  EXCEPTION WHEN unique_violation THEN
    -- Carrera con otro disparo del mismo client_event_id (reintento del outbox):
    -- se devuelve el evento ya registrado en vez de fallar.
    SELECT id INTO v_evento FROM muevete.eventos_panico
     WHERE client_event_id = p_client_event_id;
    RETURN jsonb_build_object('evento_id', v_evento, 'duplicado', true);
  END;

  -- Enlace compartido automático si el viaje sigue vivo
  IF p_compartir AND v_sol.estado = 'aceptada' THEN
    BEGIN
      v_enlace := muevete.fn_crear_enlace_viaje(p_solicitud_id, 'completo');
    EXCEPTION WHEN others THEN
      v_enlace := NULL;   -- el pánico no depende del enlace
    END;
  END IF;

  -- Push a contactos que tengan cuenta (dispara notificaciones_push)
  INSERT INTO muevete.notificaciones (user_uuid, tipo, titulo, mensaje, data)
  SELECT c.contacto_uuid, 'panico_contacto',
         'Alerta de emergencia de ' || left(coalesce(u.name, 'un contacto'), 20),
         'Activó la emergencia a las '
           || to_char(coalesce(p_capturado_at, now()) AT TIME ZONE 'America/Havana', 'HH24:MI')
           || '. Abre la app para ver la ubicación.',
         jsonb_build_object('evento_id', v_evento, 'solicitud_id', p_solicitud_id,
                            'lat', p_lat, 'lon', p_lon,
                            'enlace', v_enlace ->> 'url')
    FROM muevete.contactos_emergencia c
    LEFT JOIN muevete.users u ON u.uuid = c.user_uuid
   WHERE c.user_uuid = v_uid
     AND c.estado = 'aceptado'
     AND c.contacto_uuid IS NOT NULL;

  -- Lista de contactos para el SMS prellenado (sólo al titular)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'nombre', c.nombre, 'telefono', c.telefono, 'canal', c.canal,
           'enlace', v_enlace ->> 'url') ORDER BY c.prioridad), '[]'::jsonb)
    INTO v_contactos
    FROM muevete.contactos_emergencia c
   WHERE c.user_uuid = v_uid AND c.estado = 'aceptado';

  UPDATE muevete.eventos_panico
     SET notificados = v_contactos,
         contacto_ppal_enmascarado = (
           SELECT '••••' || right(regexp_replace(c.telefono, '\D', '', 'g'), 3)
             FROM muevete.contactos_emergencia c
            WHERE c.user_uuid = v_uid AND c.estado = 'aceptado'
            ORDER BY c.prioridad
            LIMIT 1)
   WHERE id = v_evento;

  RETURN jsonb_build_object(
    'evento_id',           v_evento,
    'enlace',              v_enlace,
    'contactos',           v_contactos,
    'envio_estado',        'pendiente_envio',
    'minutos_tracking',    v_tracking_min,
    'segundos_muestreo',   v_muestreo_s);
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_disparar_panico(
  bigint, uuid, double precision, double precision, real, text, boolean, timestamptz)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_disparar_panico(
  bigint, uuid, double precision, double precision, real, text, boolean, timestamptz)
  TO authenticated;

-- ----------------------------------------------------------------------------
-- 11. RPC · posiciones de pánico, cancelación ("falsa alarma") y OUTBOX
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_registrar_posicion_panico(
  p_evento_id     bigint,
  p_lat           double precision,
  p_lon           double precision,
  p_precision_m   real DEFAULT NULL,
  p_velocidad_mps real DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_evento muevete.eventos_panico%ROWTYPE;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  SELECT * INTO v_evento FROM muevete.eventos_panico WHERE id = p_evento_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'evento_no_existe' USING ERRCODE = 'P0104';
  END IF;
  IF v_evento.user_uuid <> v_uid THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;
  IF v_evento.estado <> 'activo' THEN
    RETURN jsonb_build_object('success', true, 'ignorado', true,
                              'motivo', 'evento_no_activo');
  END IF;

  INSERT INTO muevete.eventos_panico_ubicaciones
    (evento_id, lat, lon, precision_m, velocidad_mps)
  VALUES (p_evento_id, p_lat, p_lon, p_precision_m, p_velocidad_mps);

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_registrar_posicion_panico(bigint, double precision, double precision, real, real)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_registrar_posicion_panico(bigint, double precision, double precision, real, real)
  TO authenticated;

CREATE OR REPLACE FUNCTION muevete.fn_cancelar_panico(
  p_evento_id bigint,
  p_motivo    text DEFAULT 'falsa_alarma'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_evento muevete.eventos_panico%ROWTYPE;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  SELECT * INTO v_evento FROM muevete.eventos_panico WHERE id = p_evento_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'evento_no_existe' USING ERRCODE = 'P0104';
  END IF;
  IF v_evento.user_uuid <> v_uid AND NOT muevete.is_superadmin() THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;
  IF v_evento.estado <> 'activo' THEN
    RETURN jsonb_build_object('success', true, 'idempotente', true,
                              'estado', v_evento.estado);
  END IF;

  UPDATE muevete.eventos_panico
     SET estado   = 'cancelado_falso',
         acciones = acciones || jsonb_build_array(
                      jsonb_build_object('tipo','falsa_alarma','at', now(),
                                         'motivo', p_motivo))
   WHERE id = p_evento_id;

  -- Avisar a los contactos que fue falsa alarma
  INSERT INTO muevete.notificaciones (user_uuid, tipo, titulo, mensaje, data)
  SELECT c.contacto_uuid, 'panico_falsa_alarma', 'FALSA ALARMA',
         'La persona que activó la alerta indicó que fue un error. Puedes estar tranquilo/a.',
         jsonb_build_object('evento_id', p_evento_id)
    FROM muevete.contactos_emergencia c
   WHERE c.user_uuid = v_evento.user_uuid
     AND c.estado = 'aceptado'
     AND c.contacto_uuid IS NOT NULL;

  RETURN jsonb_build_object('success', true, 'estado', 'cancelado_falso');
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_cancelar_panico(bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_cancelar_panico(bigint, text) TO authenticated;

-- Outbox: reintento y confirmación de envío
CREATE OR REPLACE FUNCTION muevete.fn_reintentar_envio_panico(p_evento_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_evento muevete.eventos_panico%ROWTYPE;
  v_contactos jsonb;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  SELECT * INTO v_evento FROM muevete.eventos_panico WHERE id = p_evento_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'evento_no_existe' USING ERRCODE = 'P0104';
  END IF;
  IF v_evento.user_uuid <> v_uid AND NOT muevete.is_superadmin() THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;
  IF v_evento.envio_estado = 'enviado' THEN
    RETURN jsonb_build_object('success', true, 'idempotente', true,
                              'envio_estado', 'enviado');
  END IF;

  UPDATE muevete.eventos_panico
     SET envio_estado = 'pendiente_envio',
         envio_intentos = envio_intentos + 1
   WHERE id = p_evento_id;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'nombre', c.nombre, 'telefono', c.telefono, 'canal', c.canal)
           ORDER BY c.prioridad), '[]'::jsonb)
    INTO v_contactos
    FROM muevete.contactos_emergencia c
   WHERE c.user_uuid = v_evento.user_uuid AND c.estado = 'aceptado';

  RETURN jsonb_build_object(
    'success',        true,
    'evento_id',      p_evento_id,
    'envio_estado',   'pendiente_envio',
    'envio_intentos', v_evento.envio_intentos + 1,
    'lat', v_evento.lat, 'lon', v_evento.lon,
    'capturado_at',   v_evento.capturado_at,
    'contactos',      v_contactos);
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_reintentar_envio_panico(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_reintentar_envio_panico(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION muevete.fn_marcar_envio_panico(
  p_evento_id bigint,
  p_ok        boolean,
  p_error     text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_evento muevete.eventos_panico%ROWTYPE;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  SELECT * INTO v_evento FROM muevete.eventos_panico WHERE id = p_evento_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'evento_no_existe' USING ERRCODE = 'P0104';
  END IF;
  IF v_evento.user_uuid <> v_uid AND NOT muevete.is_superadmin() THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  UPDATE muevete.eventos_panico
     SET envio_estado       = CASE WHEN p_ok THEN 'enviado' ELSE 'fallido' END,
         enviado_at         = CASE WHEN p_ok THEN now() ELSE enviado_at END,
         envio_ultimo_error = CASE WHEN p_ok THEN NULL ELSE left(coalesce(p_error,'error'), 500) END
   WHERE id = p_evento_id;

  RETURN jsonb_build_object('success', true,
                            'envio_estado', CASE WHEN p_ok THEN 'enviado' ELSE 'fallido' END);
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_marcar_envio_panico(bigint, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_marcar_envio_panico(bigint, boolean, text) TO authenticated;

-- ----------------------------------------------------------------------------
-- 12. RPC · enlaces de viaje compartido (crear / revocar / ver con token)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_crear_enlace_viaje(
  p_solicitud_id bigint,
  p_alcance      text DEFAULT 'completo'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, public, extensions, pg_temp
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_sol      muevete.solicitudes_transporte%ROWTYPE;
  v_rol      text;
  v_token    text;
  v_hash     text;
  v_enlace   bigint;
  v_expira   timestamptz;
  v_minutos  integer := 120;
  v_intento  integer := 0;
  v_viaje_id bigint;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'no_autenticado' USING ERRCODE = '28000';
  END IF;
  IF p_alcance NOT IN ('completo','solo_estado') THEN
    RAISE EXCEPTION 'alcance_invalido: %', p_alcance USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_sol FROM muevete.solicitudes_transporte WHERE id = p_solicitud_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'solicitud_no_existe' USING ERRCODE = 'P0101';
  END IF;

  IF v_sol.user_id <> v_uid
     AND NOT EXISTS (SELECT 1 FROM muevete.drivers d
                      WHERE d.id = v_sol.driver_id AND d.uuid = v_uid) THEN
    RAISE EXCEPTION 'no_participante' USING ERRCODE = 'P0102';
  END IF;

  -- Compartible mientras el viaje está vivo, o 10 min después de cerrado (pánico)
  IF NOT (
       v_sol.estado IN ('pendiente','aceptada')
       OR EXISTS (SELECT 1 FROM muevete.viajes v
                   WHERE v.solicitud_id = p_solicitud_id
                     AND v.updated_at > now() - interval '10 minutes')
  ) THEN
    RAISE EXCEPTION 'viaje_cerrado' USING ERRCODE = 'P0105';
  END IF;

  v_rol := CASE WHEN v_sol.user_id = v_uid THEN 'cliente' ELSE 'chofer' END;

  SELECT coalesce(minutos_vida_enlace, 120) INTO v_minutos
    FROM muevete.configuracion_seguridad WHERE id = 1;

  SELECT id INTO v_viaje_id FROM muevete.viajes
   WHERE solicitud_id = p_solicitud_id ORDER BY id DESC LIMIT 1;

  LOOP
    v_intento := v_intento + 1;
    -- 32 bytes aleatorios (256 bits) → base64url de 43 caracteres (>= 32 bytes exigidos).
    v_token := rtrim(translate(encode(gen_random_bytes(32), 'base64'), '+/', '-_'), '=');
    v_hash  := muevete.fn_token_hash(v_token);

    BEGIN
      INSERT INTO muevete.enlaces_viaje (
        solicitud_id, viaje_id, creado_por_uuid, rol, token_hash,
        alcance, expira_at
      ) VALUES (
        p_solicitud_id, v_viaje_id, v_uid, v_rol, v_hash,
        p_alcance, now() + make_interval(mins => coalesce(v_minutos, 120))
      ) RETURNING id, expira_at INTO v_enlace, v_expira;
      EXIT;   -- insertado
    EXCEPTION WHEN unique_violation THEN
      IF v_intento >= 3 THEN
        RAISE EXCEPTION 'no_se_pudo_generar_token' USING ERRCODE = 'P0106';
      END IF;
    END;
  END LOOP;

  UPDATE muevete.solicitudes_transporte
     SET seguridad_snapshot = coalesce(seguridad_snapshot, '{}'::jsonb)
         || jsonb_build_object(
              'compartido', true,
              'enlaces', coalesce((seguridad_snapshot ->> 'enlaces')::int, 0) + 1)
   WHERE id = p_solicitud_id;

  -- El token en claro se devuelve UNA vez y no se persiste nunca.
  RETURN jsonb_build_object(
    'success',     true,
    'enlace_id',   v_enlace,
    'token',       v_token,
    'url',         '/f/' || v_token,
    'expira_at',   v_expira,
    'alcance',     p_alcance,
    'permisos',    jsonb_build_object('ubicacion', true, 'contraparte', true,
                                      'destino', true, 'telefono', false, 'ci', false));
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_crear_enlace_viaje(bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_crear_enlace_viaje(bigint, text) TO authenticated;

CREATE OR REPLACE FUNCTION muevete.fn_revocar_enlace_viaje(p_enlace_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_enf muevete.enlaces_viaje%ROWTYPE;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  SELECT * INTO v_enf FROM muevete.enlaces_viaje WHERE id = p_enlace_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'enlace_no_existe' USING ERRCODE = 'P0107';
  END IF;
  IF v_enf.creado_por_uuid <> v_uid AND NOT muevete.is_superadmin() THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  UPDATE muevete.enlaces_viaje
     SET revocado_at = now(), motivo_revocacion = 'usuario'
   WHERE id = p_enlace_id AND revocado_at IS NULL;

  RETURN jsonb_build_object('success', true, 'enlace_id', p_enlace_id);
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_revocar_enlace_viaje(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_revocar_enlace_viaje(bigint) TO authenticated;

-- RPC pública con token: el enlace compartido NO da acceso a tablas.
-- Devuelve whitelist; nunca teléfono, CI completa, correo ni documentos.
CREATE OR REPLACE FUNCTION muevete.fn_ver_enlace_viaje(p_token text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, public, extensions, pg_temp
AS $$
DECLARE
  v_hash    text;
  v_enf     muevete.enlaces_viaje%ROWTYPE;
  v_sol     muevete.solicitudes_transporte%ROWTYPE;
  v_estado  text;
  v_lat double precision; v_lon double precision;
  v_prec real; v_pos_at timestamptz;
  v_nombre text; v_marca text; v_modelo text; v_color text; v_chapa text;
BEGIN
  IF p_token IS NULL OR length(p_token) < 10 THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'invalido');
  END IF;

  v_hash := muevete.fn_token_hash(p_token);

  SELECT * INTO v_enf FROM muevete.enlaces_viaje WHERE token_hash = v_hash LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'invalido');
  END IF;
  IF v_enf.revocado_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'revocado');
  END IF;
  IF v_enf.expira_at <= now() THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'expirado');
  END IF;

  SELECT * INTO v_sol FROM muevete.solicitudes_transporte WHERE id = v_enf.solicitud_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'invalido');
  END IF;

  v_estado := CASE
                WHEN v_sol.estado = 'completada' THEN 'terminado'
                WHEN v_sol.estado IN ('cancelada','expirada') THEN 'cancelado'
                WHEN v_sol.estado = 'aceptada' THEN 'en_viaje'
                ELSE 'pendiente'
              END;

  IF v_estado IN ('terminado','cancelado') THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'terminado', 'estado', v_estado);
  END IF;

  UPDATE muevete.enlaces_viaje
     SET accesos = accesos + 1, ultimo_acceso_at = now()
   WHERE id = v_enf.id;

  IF coalesce((v_enf.permisos ->> 'ubicacion')::boolean, true) THEN
    SELECT lat, lon, precision_m, capturado_at
      INTO v_lat, v_lon, v_prec, v_pos_at
      FROM muevete.viaje_ubicaciones
     WHERE solicitud_id = v_enf.solicitud_id
     ORDER BY capturado_at DESC
     LIMIT 1;
  END IF;

  IF coalesce((v_enf.permisos ->> 'contraparte')::boolean, true)
     AND v_sol.driver_id IS NOT NULL THEN
    SELECT
      coalesce(nullif(trim(split_part(coalesce(d.name,''), ' ', 1)), ''), 'Conductor')
        || CASE WHEN split_part(coalesce(d.name,''), ' ', 2) <> ''
                THEN ' ' || left(split_part(coalesce(d.name,''), ' ', 2), 1) || '.'
                ELSE '' END,
      veh.marca, veh.modelo, veh.color, veh.chapa
      INTO v_nombre, v_marca, v_modelo, v_color, v_chapa
      FROM muevete.drivers d
      LEFT JOIN muevete.vehiculos veh ON veh.id = d.vehiculo
     WHERE d.id = v_sol.driver_id;
  END IF;

  RETURN jsonb_build_object(
    'ok',     true,
    'estado', v_estado,
    'actualizado_hace_s',
      CASE WHEN v_pos_at IS NULL THEN NULL
           ELSE greatest(0, extract(epoch FROM (now() - v_pos_at))::int) END,
    'posicion',
      CASE WHEN v_lat IS NULL THEN NULL
           ELSE jsonb_build_object('lat', v_lat, 'lon', v_lon,
                                   'precision_m', v_prec,
                                   'capturado_at', v_pos_at) END,
    'conductor',
      CASE WHEN v_nombre IS NULL THEN NULL
           ELSE jsonb_build_object('nombre_publico', v_nombre) END,
    'vehiculo',
      CASE WHEN v_chapa IS NULL THEN NULL
           ELSE jsonb_build_object('marca', v_marca, 'modelo', v_modelo,
                                   'color', v_color, 'chapa', v_chapa) END,
    'destino',
      CASE WHEN coalesce((v_enf.permisos ->> 'destino')::boolean, true)
           THEN v_sol.direccion_destino ELSE NULL END,
    'permisos', v_enf.permisos,
    'aviso', 'Muevete no sustituye a la policia. Si no sabes nada de la persona, llama al 106.'
  );
END;
$$;

-- Lectura pública por posesión del token. No hay tabla expuesta a anon.
REVOKE ALL ON FUNCTION muevete.fn_ver_enlace_viaje(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION muevete.fn_ver_enlace_viaje(text) TO anon, authenticated;

-- ----------------------------------------------------------------------------
-- 13. RPC · ficha de la contraparte (verificación mutua, whitelist estricta)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_ficha_contraparte(p_solicitud_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_sol    muevete.solicitudes_transporte%ROWTYPE;
  v_soy    text;
  v_nombre text;
  v_foto   text;
  v_ci4    text;
  v_verif  boolean := false;
  v_marca  text; v_modelo text; v_color text; v_chapa text;
  v_rating numeric := 0; v_trips integer := 0;
  v_ficha  jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'no_autenticado' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO v_sol FROM muevete.solicitudes_transporte WHERE id = p_solicitud_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'solicitud_no_existe' USING ERRCODE = 'P0101';
  END IF;

  IF v_sol.user_id = v_uid THEN
    v_soy := 'cliente';
  ELSIF EXISTS (SELECT 1 FROM muevete.drivers d
                 WHERE d.id = v_sol.driver_id AND d.uuid = v_uid) THEN
    v_soy := 'chofer';
  ELSE
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  -- Ventana: viaje vivo, o hasta 72 h después del cierre (para reportar)
  IF NOT (
       v_sol.estado IN ('pendiente','aceptada')
       OR coalesce(v_sol.updated_at, v_sol.created_at) > now() - interval '72 hours'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'fuera_de_ventana');
  END IF;

  IF v_soy = 'cliente' THEN
    SELECT
      coalesce(nullif(trim(split_part(coalesce(d.name,''), ' ', 1)), ''), 'Conductor')
        || CASE WHEN split_part(coalesce(d.name,''), ' ', 2) <> ''
                THEN ' ' || left(split_part(coalesce(d.name,''), ' ', 2), 1) || '.'
                ELSE '' END,
      d.image,
      right(regexp_replace(coalesce(d.ci, d.carnet, ''), '\D', '', 'g'), 4),
      (coalesce(d.kyc,false) AND coalesce(d.revisado,false)),
      veh.marca, veh.modelo, veh.color, veh.chapa
      INTO v_nombre, v_foto, v_ci4, v_verif, v_marca, v_modelo, v_color, v_chapa
      FROM muevete.drivers d
      LEFT JOIN muevete.vehiculos veh ON veh.id = d.vehiculo
     WHERE d.id = v_sol.driver_id;

    SELECT coalesce(avg(rating),0), count(*) INTO v_rating, v_trips
      FROM muevete.valoraciones_viaje WHERE driver_id = v_sol.driver_id;

    v_ficha := jsonb_build_object(
      'ok', true, 'rol', 'chofer',
      'nombre_publico', v_nombre,
      'foto_url', v_foto,
      'ci_parcial', CASE WHEN coalesce(v_ci4,'') = '' THEN NULL
                         ELSE '••••••' || v_ci4 END,
      'vehiculo', jsonb_build_object('marca', v_marca, 'modelo', v_modelo,
                                     'color', v_color, 'chapa', v_chapa),
      'rating', round(coalesce(v_rating,0),1),
      'viajes', coalesce(v_trips,0),
      'verificado', coalesce(v_verif,false));
  ELSE
    SELECT
      coalesce(nullif(trim(split_part(coalesce(u.name,''), ' ', 1)), ''), 'Pasajero')
        || CASE WHEN split_part(coalesce(u.name,''), ' ', 2) <> ''
                THEN ' ' || left(split_part(coalesce(u.name,''), ' ', 2), 1) || '.'
                ELSE '' END,
      coalesce(u.image, u.photo_url),
      right(regexp_replace(coalesce(u.ci, ''), '\D', '', 'g'), 4),
      (u.kyc_estado = 'aprobado')
      INTO v_nombre, v_foto, v_ci4, v_verif
      FROM muevete.users u
     WHERE u.uuid = v_sol.user_id;

    SELECT coalesce(avg(rating),0), count(*) INTO v_rating, v_trips
      FROM muevete.valoraciones_viaje WHERE user_id = v_sol.user_id;

    v_ficha := jsonb_build_object(
      'ok', true, 'rol', 'cliente',
      'nombre_publico', v_nombre,
      'foto_url', v_foto,
      'ci_parcial', CASE WHEN coalesce(v_ci4,'') = '' THEN NULL
                         ELSE '••••••' || v_ci4 END,
      'rating', round(coalesce(v_rating,0),1),
      'viajes', coalesce(v_trips,0),
      'verificado', coalesce(v_verif,false));
  END IF;

  UPDATE muevete.solicitudes_transporte
     SET seguridad_snapshot = coalesce(seguridad_snapshot, '{}'::jsonb)
         || jsonb_build_object('ficha_servida', true)
   WHERE id = p_solicitud_id;

  RETURN v_ficha;
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_ficha_contraparte(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_ficha_contraparte(bigint) TO authenticated;

-- ----------------------------------------------------------------------------
-- 14. RPC · confirmar abordaje (chofer inicia; cliente confirma chapa)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_confirmar_abordaje(
  p_viaje_id         bigint,
  p_chapa_confirmada boolean,
  p_metodo           text DEFAULT 'ficha'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_uid   uuid := auth.uid();
  v_drv   bigint := muevete.get_my_driver_id();
  v_viaje muevete.viajes%ROWTYPE;
  v_sol   muevete.solicitudes_transporte%ROWTYPE;
  v_es_chofer boolean;
  v_es_cliente boolean;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  IF p_metodo NOT IN ('ficha','cache','sin_verificacion') THEN
    RAISE EXCEPTION 'metodo_invalido: %', p_metodo USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_viaje FROM muevete.viajes WHERE id = p_viaje_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'viaje_no_existe' USING ERRCODE = 'P0030';
  END IF;
  SELECT * INTO v_sol FROM muevete.solicitudes_transporte WHERE id = v_viaje.solicitud_id;

  v_es_chofer  := v_drv IS NOT NULL AND v_viaje.driver_id = v_drv;
  v_es_cliente := v_sol.user_id = v_uid;

  IF NOT (v_es_chofer OR v_es_cliente) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;
  IF v_viaje.completado THEN
    RAISE EXCEPTION 'viaje_cerrado' USING ERRCODE = 'P0105';
  END IF;

  IF v_es_chofer THEN
    -- Si la ficha se sirvió, exigir confirmación de chapa para iniciar
    IF p_metodo = 'ficha' AND NOT coalesce(p_chapa_confirmada, false) THEN
      RAISE EXCEPTION 'chapa_no_confirmada' USING ERRCODE = 'P0116';
    END IF;

    UPDATE muevete.viajes
       SET estado = true,
           abordaje_at = now(),
           abordaje_metodo = p_metodo,
           abordaje_confirmado_por = v_uid,
           chapa_confirmada = coalesce(p_chapa_confirmada, false)
     WHERE id = p_viaje_id;

    UPDATE muevete.solicitudes_transporte
       SET seguridad_snapshot = coalesce(seguridad_snapshot, '{}'::jsonb)
           || jsonb_build_object('abordaje_metodo', p_metodo)
     WHERE id = v_sol.id;
  ELSE
    -- El pasajero sólo registra evidencia; no inicia el viaje
    UPDATE muevete.viajes
       SET abordaje_confirmado_por = coalesce(abordaje_confirmado_por, v_uid),
           chapa_confirmada = coalesce(chapa_confirmada, false)
                       OR coalesce(p_chapa_confirmada, false)
     WHERE id = p_viaje_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'viaje_id', p_viaje_id,
    'rol', CASE WHEN v_es_chofer THEN 'chofer' ELSE 'cliente' END,
    'chapa_confirmada', coalesce(p_chapa_confirmada, false),
    'metodo', p_metodo);
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_confirmar_abordaje(bigint, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_confirmar_abordaje(bigint, boolean, text) TO authenticated;

-- ----------------------------------------------------------------------------
-- 15. RPC · posiciones del viaje (para el enlace compartido)
--     El pasajero publica sólo si el viaje está compartido (hay enlace vigente).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_registrar_posicion_viaje(
  p_solicitud_id bigint,
  p_lat          double precision,
  p_lon          double precision,
  p_precision_m  real DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_sol muevete.solicitudes_transporte%ROWTYPE;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  SELECT * INTO v_sol FROM muevete.solicitudes_transporte WHERE id = p_solicitud_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'solicitud_no_existe' USING ERRCODE = 'P0101';
  END IF;
  IF v_sol.user_id <> v_uid
     AND NOT EXISTS (SELECT 1 FROM muevete.drivers d
                      WHERE d.id = v_sol.driver_id AND d.uuid = v_uid) THEN
    RAISE EXCEPTION 'no_participante' USING ERRCODE = 'P0102';
  END IF;
  IF v_sol.estado <> 'aceptada' THEN
    RETURN jsonb_build_object('success', true, 'ignorado', true);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM muevete.enlaces_viaje e
     WHERE e.solicitud_id = p_solicitud_id
       AND e.revocado_at IS NULL
       AND e.expira_at > now()
  ) THEN
    RETURN jsonb_build_object('success', true, 'ignorado', true,
                              'motivo', 'sin_enlace_compartido');
  END IF;

  INSERT INTO muevete.viaje_ubicaciones (solicitud_id, rol, lat, lon, precision_m)
  VALUES (p_solicitud_id,
          CASE WHEN v_sol.user_id = v_uid THEN 'cliente' ELSE 'chofer' END,
          p_lat, p_lon, p_precision_m);

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_registrar_posicion_viaje(bigint, double precision, double precision, real)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_registrar_posicion_viaje(bigint, double precision, double precision, real)
  TO authenticated;

-- ----------------------------------------------------------------------------
-- 16. RPC · incidentes y bloqueos
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_reportar_incidente(
  p_solicitud_id   bigint,
  p_tipo           text,
  p_descripcion    text,
  p_evidencia      jsonb DEFAULT '[]'::jsonb,
  p_no_emparejar   boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_drv       bigint := muevete.get_my_driver_id();
  v_sol       muevete.solicitudes_transporte%ROWTYPE;
  v_rol       text;
  v_contra_u  uuid;
  v_contra_d  bigint;
  v_sev       text;
  v_no_emp    boolean;
  v_inc       bigint;
  v_viaje_id  bigint;
  v_ventana   integer := 7;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'no_autenticado' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO v_sol FROM muevete.solicitudes_transporte WHERE id = p_solicitud_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'solicitud_no_existe' USING ERRCODE = 'P0101';
  END IF;

  IF v_sol.user_id = v_uid THEN
    v_rol := 'cliente';
    v_contra_u := NULL;
    v_contra_d := v_sol.driver_id;
  ELSIF v_drv IS NOT NULL AND v_sol.driver_id = v_drv THEN
    v_rol := 'chofer';
    v_contra_u := v_sol.user_id;
    v_contra_d := NULL;
  ELSE
    RAISE EXCEPTION 'no_participante' USING ERRCODE = 'P0102';
  END IF;

  SELECT coalesce(dias_ventana_reporte, 7) INTO v_ventana
    FROM muevete.configuracion_seguridad WHERE id = 1;

  IF coalesce(v_sol.updated_at, v_sol.created_at) < now() - make_interval(days => coalesce(v_ventana,7)) THEN
    RAISE EXCEPTION 'fuera_de_ventana' USING ERRCODE = 'P0117';
  END IF;

  v_sev := CASE
    WHEN p_tipo IN ('robo_con_violencia','agresion_fisica','amenaza','acoso_sexual') THEN 'critica'
    WHEN p_tipo IN ('suplantacion','vehiculo_incorrecto','acoso_verbal','extorsion') THEN 'alta'
    WHEN p_tipo IN ('no_show_pasajero','cobro_abusivo') THEN 'baja'
    ELSE 'media'
  END;

  v_no_emp := coalesce(p_no_emparejar, false) OR v_sev IN ('alta','critica');

  SELECT id INTO v_viaje_id FROM muevete.viajes
   WHERE solicitud_id = p_solicitud_id ORDER BY id DESC LIMIT 1;

  INSERT INTO muevete.incidentes (
    solicitud_id, viaje_id, reportado_por_uuid, rol_reporta,
    contraparte_uuid, contraparte_driver_id, tipo, severidad,
    descripcion, evidencia, estado, solicita_no_emparejar
  ) VALUES (
    p_solicitud_id, v_viaje_id, v_uid, v_rol,
    v_contra_u, v_contra_d, p_tipo, v_sev,
    p_descripcion, coalesce(p_evidencia, '[]'::jsonb), 'reportado', v_no_emp
  ) RETURNING id INTO v_inc;

  IF v_no_emp AND (v_contra_u IS NOT NULL OR v_contra_d IS NOT NULL) THEN
    INSERT INTO muevete.emparejamientos_bloqueados
      (user_uuid, driver_id, motivo, incidente_id)
    SELECT
      CASE WHEN v_rol = 'cliente' THEN v_uid ELSE v_contra_u END,
      CASE WHEN v_rol = 'chofer'  THEN v_drv ELSE v_contra_d END,
      'No volver a emparejar (reporte ' || v_inc || ')',
      v_inc
    ON CONFLICT (user_uuid, driver_id) DO NOTHING;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'incidente_id', v_inc,
    'estado', 'reportado',
    'severidad', v_sev,
    'no_emparejar', v_no_emp);
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_reportar_incidente(bigint, text, text, jsonb, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_reportar_incidente(bigint, text, text, jsonb, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION muevete.fn_no_show_pasajero(p_viaje_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_drv      bigint := muevete.get_my_driver_id();
  v_viaje    muevete.viajes%ROWTYPE;
  v_sol      muevete.solicitudes_transporte%ROWTYPE;
  v_inc      bigint;
  v_casos    integer;
  v_umbral   smallint := 3;
  v_dias     integer := 30;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  IF v_drv IS NULL THEN
    RAISE EXCEPTION 'no_es_chofer' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO v_viaje FROM muevete.viajes WHERE id = p_viaje_id;
  IF NOT FOUND OR v_viaje.driver_id <> v_drv THEN
    RAISE EXCEPTION 'viaje_no_existe_o_no_es_tuyo' USING ERRCODE = 'P0030';
  END IF;
  SELECT * INTO v_sol FROM muevete.solicitudes_transporte WHERE id = v_viaje.solicitud_id;

  SELECT coalesce(no_show_umbral,3), coalesce(dias_ventana_reincidencia,30)
    INTO v_umbral, v_dias
    FROM muevete.configuracion_seguridad WHERE id = 1;

  INSERT INTO muevete.incidentes (
    solicitud_id, viaje_id, reportado_por_uuid, rol_reporta,
    contraparte_uuid, tipo, severidad, descripcion, estado
  ) VALUES (
    v_sol.id, p_viaje_id, v_uid, 'chofer',
    v_sol.user_id, 'no_show_pasajero', 'baja',
    'El pasajero no apareció en el punto de recogida (reporte automático del chofer).',
    'reportado'
  ) RETURNING id INTO v_inc;

  SELECT count(*) INTO v_casos
    FROM muevete.incidentes
   WHERE contraparte_uuid = v_sol.user_id
     AND tipo = 'no_show_pasajero'
     AND created_at > now() - make_interval(days => coalesce(v_dias,30));

  RETURN jsonb_build_object(
    'success', true, 'incidente_id', v_inc,
    'casos_en_ventana', v_casos, 'umbral', v_umbral);
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_no_show_pasajero(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_no_show_pasajero(bigint) TO authenticated;

-- ----------------------------------------------------------------------------
-- 17. RPC · estado de la contraparte (señal de seguridad para la tarjeta)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_estado_contraparte(
  p_user_uuid uuid,
  p_driver_id bigint
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_drv       bigint := muevete.get_my_driver_id();
  v_dias      integer := 90;
  v_bloqueado boolean := false;
  v_alerta    boolean := false;
  v_emp       boolean := false;
BEGIN
  -- Sólo el chofer implicado puede consultar la señal de un pasajero de una
  -- solicitud visible para él; el superadmin puede todo.
  IF NOT muevete.is_superadmin() THEN
    IF v_drv IS NULL OR v_drv IS DISTINCT FROM p_driver_id THEN
      RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM muevete.solicitudes_transporte s
       WHERE s.user_id = p_user_uuid
         AND s.estado IN ('pendiente','aceptada')
    ) THEN
      RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
    END IF;
  END IF;

  SELECT coalesce(dias_ventana_reincidencia, 90) INTO v_dias
    FROM muevete.configuracion_seguridad WHERE id = 1;

  SELECT EXISTS (
    SELECT 1 FROM muevete.bloqueos b
     WHERE b.revocado_at IS NULL
       AND (b.vigente_hasta IS NULL OR b.vigente_hasta > now())
       AND (b.user_uuid = p_user_uuid OR b.driver_id = p_driver_id)
  ) INTO v_bloqueado;

  SELECT EXISTS (
    SELECT 1 FROM muevete.incidentes i
     WHERE i.estado = 'confirmado'
       AND i.severidad IN ('alta','critica')
       AND i.created_at > now() - make_interval(days => coalesce(v_dias,90))
       AND (i.contraparte_uuid = p_user_uuid OR i.contraparte_driver_id = p_driver_id)
  ) INTO v_alerta;

  v_emp := muevete.fn_emparejamiento_bloqueado(p_user_uuid, p_driver_id);

  RETURN jsonb_build_object(
    'bloqueado',              v_bloqueado,
    'alerta_seguridad',       v_alerta,
    'emparejamiento_bloqueado', v_emp,
    'recomendacion',
      CASE WHEN v_bloqueado THEN 'No disponible'
           WHEN v_emp       THEN 'No puedes tomar este viaje'
           WHEN v_alerta    THEN 'Pasajero con reportes de seguridad confirmados'
           ELSE NULL END);
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_estado_contraparte(uuid, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_estado_contraparte(uuid, bigint) TO authenticated;

-- ----------------------------------------------------------------------------
-- 18. RPC · resolución de incidentes y bloqueos (superadmin)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_resolver_incidente(
  p_incidente_id bigint,
  p_estado       text,
  p_resolucion   text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_inc      muevete.incidentes%ROWTYPE;
  v_criticos integer := 0;
  v_altos    integer := 0;
  v_umbral   smallint := 2;
  v_dias     integer := 90;
  v_bloqueo  bigint;
  v_sujeto_u uuid;
  v_sujeto_d bigint;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  IF NOT muevete.is_superadmin() THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;
  IF p_estado NOT IN ('en_revision','confirmado','descartado','escalado') THEN
    RAISE EXCEPTION 'estado_invalido: %', p_estado USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_inc FROM muevete.incidentes WHERE id = p_incidente_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'incidente_no_existe' USING ERRCODE = 'P0118';
  END IF;

  UPDATE muevete.incidentes
     SET estado      = p_estado,
         resolucion  = p_resolucion,
         revisado_por = auth.uid(),
         revisado_at  = now()
   WHERE id = p_incidente_id;

  -- Bloqueo automático SOLO al confirmar (nunca con un reporte sin confirmar)
  IF p_estado = 'confirmado' THEN
    SELECT coalesce(umbral_bloqueo_incidentes,2), coalesce(dias_ventana_reincidencia,90)
      INTO v_umbral, v_dias
      FROM muevete.configuracion_seguridad WHERE id = 1;

    v_sujeto_u := v_inc.contraparte_uuid;
    v_sujeto_d := v_inc.contraparte_driver_id;

    IF v_inc.severidad = 'critica' THEN
      INSERT INTO muevete.bloqueos
        (user_uuid, driver_id, tipo_bloqueo, motivo, incidente_id, creado_por)
      VALUES (v_sujeto_u, v_sujeto_d, 'permanente',
              'Incidente crítico confirmado: ' || v_inc.tipo,
              p_incidente_id, auth.uid())
      RETURNING id INTO v_bloqueo;
    ELSE
      SELECT count(*) FILTER (WHERE severidad = 'critica'),
             count(*) FILTER (WHERE severidad = 'alta')
        INTO v_criticos, v_altos
        FROM muevete.incidentes
       WHERE estado = 'confirmado'
         AND created_at > now() - make_interval(days => coalesce(v_dias,90))
         AND (contraparte_uuid IS NOT DISTINCT FROM v_sujeto_u)
         AND (contraparte_driver_id IS NOT DISTINCT FROM v_sujeto_d);

      IF (v_altos + v_criticos) >= coalesce(v_umbral, 2) THEN
        INSERT INTO muevete.bloqueos
          (user_uuid, driver_id, tipo_bloqueo, motivo, incidente_id,
           vigente_hasta, creado_por)
        VALUES (v_sujeto_u, v_sujeto_d, 'automatico_temporal',
                'Reincidencia de incidentes confirmados de seguridad',
                p_incidente_id,
                now() + make_interval(days => 30),
                auth.uid())
        RETURNING id INTO v_bloqueo;
      END IF;
    END IF;

    IF v_inc.solicita_no_emparejar AND v_inc.contraparte_uuid IS NOT NULL
       AND v_sujeto_d IS NOT NULL THEN
      INSERT INTO muevete.emparejamientos_bloqueados
        (user_uuid, driver_id, motivo, incidente_id)
      VALUES (v_sujeto_u, v_sujeto_d,
              'No volver a emparejar (incidente ' || p_incidente_id || ')',
              p_incidente_id)
      ON CONFLICT (user_uuid, driver_id) DO NOTHING;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'incidente_id', p_incidente_id,
    'estado', p_estado,
    'bloqueo_id', v_bloqueo);
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_resolver_incidente(bigint, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_resolver_incidente(bigint, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION muevete.fn_revocar_bloqueo(
  p_bloqueo_id bigint,
  p_motivo     text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  IF NOT muevete.is_superadmin() THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;
  IF p_motivo IS NULL OR length(trim(p_motivo)) < 5 THEN
    RAISE EXCEPTION 'motivo_requerido' USING ERRCODE = 'P0001';
  END IF;

  UPDATE muevete.bloqueos
     SET revocado_at  = now(),
         revocado_por = auth.uid(),
         creado_motivo = p_motivo
   WHERE id = p_bloqueo_id AND revocado_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'bloqueo_no_existe_o_ya_revocado' USING ERRCODE = 'P0119';
  END IF;

  RETURN jsonb_build_object('success', true, 'bloqueo_id', p_bloqueo_id);
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_revocar_bloqueo(bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_revocar_bloqueo(bigint, text) TO authenticated;

-- ----------------------------------------------------------------------------
-- 19. Cierre de seguridad (al completar/cancelar) + triggers
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_cierre_seguridad(
  p_solicitud_id bigint,
  p_motivo       text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
BEGIN
  UPDATE muevete.enlaces_viaje
     SET revocado_at = now(), motivo_revocacion = p_motivo
   WHERE solicitud_id = p_solicitud_id AND revocado_at IS NULL;

  UPDATE muevete.solicitudes_transporte
     SET seguridad_snapshot = coalesce(seguridad_snapshot, '{}'::jsonb)
         || jsonb_build_object('cerrado_at', now(), 'motivo_cierre', p_motivo)
   WHERE id = p_solicitud_id;
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_cierre_seguridad(bigint, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION muevete.trg_viaje_completado_seguridad()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
BEGIN
  IF NEW.completado AND NOT coalesce(OLD.completado, false)
     AND NEW.solicitud_id IS NOT NULL THEN
    PERFORM muevete.fn_cierre_seguridad(NEW.solicitud_id, 'viaje_completado');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_viaje_completado_seguridad ON muevete.viajes;
CREATE TRIGGER trg_viaje_completado_seguridad
  AFTER UPDATE OF completado ON muevete.viajes
  FOR EACH ROW EXECUTE FUNCTION muevete.trg_viaje_completado_seguridad();

CREATE OR REPLACE FUNCTION muevete.trg_solicitud_cerrada_seguridad()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
BEGIN
  IF NEW.estado IN ('cancelada','completada','expirada')
     AND OLD.estado IS DISTINCT FROM NEW.estado THEN
    PERFORM muevete.fn_cierre_seguridad(NEW.id, 'solicitud_' || NEW.estado);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_solicitud_cerrada_seguridad ON muevete.solicitudes_transporte;
CREATE TRIGGER trg_solicitud_cerrada_seguridad
  AFTER UPDATE OF estado ON muevete.solicitudes_transporte
  FOR EACH ROW EXECUTE FUNCTION muevete.trg_solicitud_cerrada_seguridad();

-- ----------------------------------------------------------------------------
-- 20. Retención (job opcional; se puede llamar desde pg_cron o consola)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_purgar_seguridad()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_dias_ubic   integer := 30;
  v_meses_inc   integer := 24;
  v_u  integer := 0;
  v_p  integer := 0;
  v_e  integer := 0;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  IF NOT muevete.is_superadmin()
     AND coalesce(current_setting('muevete.cron', true), 'off') <> 'on' THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  SELECT coalesce(dias_retencion_ubicaciones,30), coalesce(meses_retencion_incidentes,24)
    INTO v_dias_ubic, v_meses_inc
    FROM muevete.configuracion_seguridad WHERE id = 1;

  DELETE FROM muevete.viaje_ubicaciones
   WHERE capturado_at < now() - make_interval(days => coalesce(v_dias_ubic,30));
  GET DIAGNOSTICS v_u = ROW_COUNT;

  DELETE FROM muevete.eventos_panico_ubicaciones u
   USING muevete.eventos_panico e
   WHERE u.evento_id = e.id
     AND e.created_at < now() - interval '90 days';
  GET DIAGNOSTICS v_p = ROW_COUNT;

  DELETE FROM muevete.enlaces_viaje
   WHERE revocado_at IS NOT NULL
     AND revocado_at < now() - interval '6 months';
  GET DIAGNOSTICS v_e = ROW_COUNT;

  RETURN jsonb_build_object('success', true,
    'ubicaciones_viaje_borradas', v_u,
    'ubicaciones_panico_borradas', v_p,
    'enlaces_borrados', v_e,
    'nota', 'Incidentes y bloqueos NO se purgan automáticamente: revisión manual por retención legal.');
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_purgar_seguridad() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_purgar_seguridad() TO authenticated;

-- ============================================================================
-- 21. RLS
-- ============================================================================
ALTER TABLE muevete.configuracion_seguridad     ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.contactos_emergencia        ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.eventos_panico              ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.eventos_panico_ubicaciones  ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.enlaces_viaje               ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.viaje_ubicaciones           ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.incidentes                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.bloqueos                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.emparejamientos_bloqueados  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON muevete.configuracion_seguridad, muevete.contactos_emergencia,
               muevete.eventos_panico, muevete.eventos_panico_ubicaciones,
               muevete.enlaces_viaje, muevete.viaje_ubicaciones,
               muevete.incidentes, muevete.bloqueos,
               muevete.emparejamientos_bloqueados FROM anon;

-- Configuración: lectura autenticada; escritura superadmin
DROP POLICY IF EXISTS configuracion_seguridad_select_auth ON muevete.configuracion_seguridad;
CREATE POLICY configuracion_seguridad_select_auth
  ON muevete.configuracion_seguridad FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS superadmin_all_configuracion_seguridad ON muevete.configuracion_seguridad;
CREATE POLICY superadmin_all_configuracion_seguridad
  ON muevete.configuracion_seguridad FOR ALL TO authenticated
  USING (muevete.is_superadmin()) WITH CHECK (muevete.is_superadmin());
GRANT SELECT ON muevete.configuracion_seguridad TO authenticated;

-- Contactos: dueño (CRUD) + contacto invitado (sólo SELECT)
DROP POLICY IF EXISTS contactos_emergencia_own ON muevete.contactos_emergencia;
CREATE POLICY contactos_emergencia_own
  ON muevete.contactos_emergencia FOR ALL TO authenticated
  USING (user_uuid = auth.uid())
  WITH CHECK (user_uuid = auth.uid());
DROP POLICY IF EXISTS contactos_emergencia_invitado ON muevete.contactos_emergencia;
CREATE POLICY contactos_emergencia_invitado
  ON muevete.contactos_emergencia FOR SELECT TO authenticated
  USING (contacto_uuid = auth.uid());
DROP POLICY IF EXISTS superadmin_all_contactos_emergencia ON muevete.contactos_emergencia;
CREATE POLICY superadmin_all_contactos_emergencia
  ON muevete.contactos_emergencia FOR ALL TO authenticated
  USING (muevete.is_superadmin()) WITH CHECK (muevete.is_superadmin());
GRANT SELECT, INSERT, UPDATE, DELETE ON muevete.contactos_emergencia TO authenticated;

-- Pánico: sólo lectura del propio evento; escritura por RPC
DROP POLICY IF EXISTS eventos_panico_select_own ON muevete.eventos_panico;
CREATE POLICY eventos_panico_select_own
  ON muevete.eventos_panico FOR SELECT TO authenticated
  USING (user_uuid = auth.uid());
DROP POLICY IF EXISTS superadmin_all_eventos_panico ON muevete.eventos_panico;
CREATE POLICY superadmin_all_eventos_panico
  ON muevete.eventos_panico FOR ALL TO authenticated
  USING (muevete.is_superadmin()) WITH CHECK (muevete.is_superadmin());
GRANT SELECT ON muevete.eventos_panico TO authenticated;

DROP POLICY IF EXISTS eventos_panico_ubicaciones_own ON muevete.eventos_panico_ubicaciones;
CREATE POLICY eventos_panico_ubicaciones_own
  ON muevete.eventos_panico_ubicaciones FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM muevete.eventos_panico e
                  WHERE e.id = evento_id AND e.user_uuid = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM muevete.eventos_panico e
                       WHERE e.id = evento_id AND e.user_uuid = auth.uid()));
DROP POLICY IF EXISTS superadmin_all_eventos_panico_ubicaciones ON muevete.eventos_panico_ubicaciones;
CREATE POLICY superadmin_all_eventos_panico_ubicaciones
  ON muevete.eventos_panico_ubicaciones FOR ALL TO authenticated
  USING (muevete.is_superadmin()) WITH CHECK (muevete.is_superadmin());
GRANT SELECT, INSERT ON muevete.eventos_panico_ubicaciones TO authenticated;

-- Enlaces: el creador ve sus metadatos, NUNCA token_hash (grant por columna)
DROP POLICY IF EXISTS enlaces_viaje_select_own ON muevete.enlaces_viaje;
CREATE POLICY enlaces_viaje_select_own
  ON muevete.enlaces_viaje FOR SELECT TO authenticated
  USING (creado_por_uuid = auth.uid());
DROP POLICY IF EXISTS superadmin_all_enlaces_viaje ON muevete.enlaces_viaje;
CREATE POLICY superadmin_all_enlaces_viaje
  ON muevete.enlaces_viaje FOR ALL TO authenticated
  USING (muevete.is_superadmin()) WITH CHECK (muevete.is_superadmin());
REVOKE ALL ON muevete.enlaces_viaje FROM authenticated;
GRANT SELECT (id, solicitud_id, viaje_id, creado_por_uuid, rol, alcance,
              permisos, expira_at, revocado_at, motivo_revocacion,
              accesos, ultimo_acceso_at, created_at)
  ON muevete.enlaces_viaje TO authenticated;

-- Posiciones del viaje: participantes del viaje
DROP POLICY IF EXISTS viaje_ubicaciones_participante ON muevete.viaje_ubicaciones;
CREATE POLICY viaje_ubicaciones_participante
  ON muevete.viaje_ubicaciones FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM muevete.solicitudes_transporte s
     WHERE s.id = solicitud_id
       AND (s.user_id = auth.uid() OR s.driver_id = muevete.get_my_driver_id())
  ));
DROP POLICY IF EXISTS superadmin_all_viaje_ubicaciones ON muevete.viaje_ubicaciones;
CREATE POLICY superadmin_all_viaje_ubicaciones
  ON muevete.viaje_ubicaciones FOR ALL TO authenticated
  USING (muevete.is_superadmin()) WITH CHECK (muevete.is_superadmin());
GRANT SELECT ON muevete.viaje_ubicaciones TO authenticated;

-- Incidentes: el reportante ve los suyos; la contraparte NO
DROP POLICY IF EXISTS incidentes_select_own ON muevete.incidentes;
CREATE POLICY incidentes_select_own
  ON muevete.incidentes FOR SELECT TO authenticated
  USING (reportado_por_uuid = auth.uid());
DROP POLICY IF EXISTS superadmin_all_incidentes ON muevete.incidentes;
CREATE POLICY superadmin_all_incidentes
  ON muevete.incidentes FOR ALL TO authenticated
  USING (muevete.is_superadmin()) WITH CHECK (muevete.is_superadmin());
GRANT SELECT ON muevete.incidentes TO authenticated;

-- Bloqueos: el bloqueado ve que lo está (motivo público, sin detalle del reporte)
DROP POLICY IF EXISTS bloqueos_select_own ON muevete.bloqueos;
CREATE POLICY bloqueos_select_own
  ON muevete.bloqueos FOR SELECT TO authenticated
  USING (user_uuid = auth.uid()
         OR driver_id = muevete.get_my_driver_id());
DROP POLICY IF EXISTS superadmin_all_bloqueos ON muevete.bloqueos;
CREATE POLICY superadmin_all_bloqueos
  ON muevete.bloqueos FOR ALL TO authenticated
  USING (muevete.is_superadmin()) WITH CHECK (muevete.is_superadmin());
GRANT SELECT ON muevete.bloqueos TO authenticated;

-- Emparejamientos bloqueados: sólo servidor y superadmin
DROP POLICY IF EXISTS superadmin_all_emparejamientos_bloqueados ON muevete.emparejamientos_bloqueados;
CREATE POLICY superadmin_all_emparejamientos_bloqueados
  ON muevete.emparejamientos_bloqueados FOR ALL TO authenticated
  USING (muevete.is_superadmin()) WITH CHECK (muevete.is_superadmin());
GRANT SELECT ON muevete.emparejamientos_bloqueados TO authenticated;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN (ejecutar a mano; NO forma parte de la migración)
-- ============================================================================
-- 0) PEPPER DE PRODUCCIÓN (bloqueante antes de usar enlaces reales):
--   SELECT name FROM vault.secrets WHERE name = 'seguridad_token_pepper';
--   -- Si no existe, crear el secreto o fijar el GUC muevete.seguridad_pepper.
--   -- Sin pepper la función lanza pepper_no_configurado (no hay literal en prod).
--   -- Probar: SET muevete.entorno=''; SELECT muevete.fn_token_hash('x'); -> ERROR
--
-- 1) Objetos:
--   SELECT table_name FROM information_schema.tables
--    WHERE table_schema='muevete'
--      AND table_name IN ('configuracion_seguridad','contactos_emergencia',
--                         'eventos_panico','eventos_panico_ubicaciones',
--                         'enlaces_viaje','viaje_ubicaciones','incidentes',
--                         'bloqueos','emparejamientos_bloqueados');
--      -- esperado: 9 filas
--
-- 2) Columnas de outbox y de cierre:
--   SELECT column_name FROM information_schema.columns
--    WHERE table_schema='muevete' AND table_name='eventos_panico'
--      AND column_name IN ('envio_estado','envio_intentos','enviado_at','recibido_at');
--   SELECT column_name FROM information_schema.columns
--    WHERE table_schema='muevete' AND table_name='viajes'
--      AND column_name IN ('abordaje_at','abordaje_metodo','chapa_confirmada');
--
-- 3) Las RPC existen:
--   SELECT proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
--    WHERE n.nspname='muevete' AND proname LIKE 'fn_%'
--      AND proname IN ('fn_gate_seguridad','fn_disparar_panico','fn_crear_enlace_viaje',
--                      'fn_ver_enlace_viaje','fn_ficha_contraparte','fn_reportar_incidente',
--                      'fn_resolver_incidente','fn_revocar_bloqueo','fn_purgar_seguridad');
--
-- 3.b) Entropía del token: >= 32 bytes aleatorios => base64url de 43 chars.
--   -- Al crear un enlace, length(token) debe ser 43 y no aparecer en BD.
--
-- 3.c) OTP no se devuelve en producción:
--   -- Con muevete.entorno <> 'dev', fn_iniciar_validacion_contacto NO devuelve
--   -- la clave 'codigo' en el jsonb (sólo entorno_dev=false y verificado=false).
--
-- 4) El token no se guarda en claro:
--   SELECT count(*) FROM muevete.enlaces_viaje WHERE length(token_hash) <> 64;  -- 0
--   -- y ninguna columna contiene el token: no existe columna `token`.
--
-- 5) Enlace público sin login (con un token real creado por la app):
--   SET ROLE anon;
--   SELECT muevete.fn_ver_enlace_viaje('<token>');   -- ok:true, sin telefono/ci
--   RESET ROLE;
--
-- 6) RLS:
--   SELECT tablename, policyname FROM pg_policies
--    WHERE schemaname='muevete'
--      AND tablename IN ('contactos_emergencia','eventos_panico','enlaces_viaje',
--                        'incidentes','bloqueos','emparejamientos_bloqueados')
--    ORDER BY tablename, policyname;
--
-- 7) Cierre: completar un viaje de prueba debe revocar sus enlaces:
--   UPDATE muevete.viajes SET completado = true WHERE id = <viaje_id>;
--   SELECT revocado_at, motivo_revocacion FROM muevete.enlaces_viaje
--    WHERE solicitud_id = <solicitud_id>;   -- revocado_at no nulo, motivo 'viaje_completado'
--
-- 8) Idempotencia: re-ejecutar 037 completo no falla.
-- ============================================================================

-- ============================================================================
-- DOWN (documentado; NO ejecutar en despliegue normal)
-- ============================================================================
-- BEGIN;
-- DROP TRIGGER IF EXISTS trg_solicitud_cerrada_seguridad ON muevete.solicitudes_transporte;
-- DROP TRIGGER IF EXISTS trg_viaje_completado_seguridad ON muevete.viajes;
-- DROP FUNCTION IF EXISTS muevete.trg_solicitud_cerrada_seguridad();
-- DROP FUNCTION IF EXISTS muevete.trg_viaje_completado_seguridad();
-- DROP FUNCTION IF EXISTS muevete.fn_cierre_seguridad(bigint, text);
-- DROP FUNCTION IF EXISTS muevete.fn_purgar_seguridad();
-- DROP FUNCTION IF EXISTS muevete.fn_revocar_bloqueo(bigint, text);
-- DROP FUNCTION IF EXISTS muevete.fn_resolver_incidente(bigint, text, text);
-- DROP FUNCTION IF EXISTS muevete.fn_estado_contraparte(uuid, bigint);
-- DROP FUNCTION IF EXISTS muevete.fn_no_show_pasajero(bigint);
-- DROP FUNCTION IF EXISTS muevete.fn_reportar_incidente(bigint, text, text, jsonb, boolean);
-- DROP FUNCTION IF EXISTS muevete.fn_registrar_posicion_viaje(bigint, double precision, double precision, real);
-- DROP FUNCTION IF EXISTS muevete.fn_confirmar_abordaje(bigint, boolean, text);
-- DROP FUNCTION IF EXISTS muevete.fn_ficha_contraparte(bigint);
-- DROP FUNCTION IF EXISTS muevete.fn_ver_enlace_viaje(text);
-- DROP FUNCTION IF EXISTS muevete.fn_revocar_enlace_viaje(bigint);
-- DROP FUNCTION IF EXISTS muevete.fn_crear_enlace_viaje(bigint, text);
-- DROP FUNCTION IF EXISTS muevete.fn_marcar_envio_panico(bigint, boolean, text);
-- DROP FUNCTION IF EXISTS muevete.fn_reintentar_envio_panico(bigint);
-- DROP FUNCTION IF EXISTS muevete.fn_cancelar_panico(bigint, text);
-- DROP FUNCTION IF EXISTS muevete.fn_registrar_posicion_panico(bigint, double precision, double precision, real, real);
-- DROP FUNCTION IF EXISTS muevete.fn_disparar_panico(bigint, uuid, double precision, double precision, real, text, boolean, timestamptz);
-- DROP FUNCTION IF EXISTS muevete.fn_confirmar_contacto(bigint, text, text);
-- DROP FUNCTION IF EXISTS muevete.fn_iniciar_validacion_contacto(bigint);
-- DROP FUNCTION IF EXISTS muevete.fn_gate_seguridad(uuid, bigint);
-- DROP FUNCTION IF EXISTS muevete.fn_emparejamiento_bloqueado(uuid, bigint);
-- DROP FUNCTION IF EXISTS muevete.fn_token_hash(text);
-- DROP FUNCTION IF EXISTS muevete.fn_contacto_emergencia_guarda();
-- DROP FUNCTION IF EXISTS muevete.fn_config_seguridad_touch();
-- DROP TABLE IF EXISTS muevete.emparejamientos_bloqueados;
-- DROP TABLE IF EXISTS muevete.bloqueos;
-- DROP TABLE IF EXISTS muevete.incidentes;
-- DROP TABLE IF EXISTS muevete.viaje_ubicaciones;
-- DROP TABLE IF EXISTS muevete.enlaces_viaje;
-- DROP TABLE IF EXISTS muevete.eventos_panico_ubicaciones;
-- DROP TABLE IF EXISTS muevete.eventos_panico;
-- DROP TABLE IF EXISTS muevete.contactos_emergencia;
-- DROP TABLE IF EXISTS muevete.configuracion_seguridad;
-- ALTER TABLE muevete.solicitudes_transporte DROP COLUMN IF EXISTS seguridad_snapshot;
-- ALTER TABLE muevete.viajes
--   DROP COLUMN IF EXISTS abordaje_at, DROP COLUMN IF EXISTS abordaje_metodo,
--   DROP COLUMN IF EXISTS abordaje_confirmado_por, DROP COLUMN IF EXISTS chapa_confirmada;
-- COMMIT;
-- ============================================================================
