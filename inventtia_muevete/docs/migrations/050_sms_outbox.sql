-- ============================================================================
-- 050_sms_outbox.sql
-- Servicio de SMS reutilizable (outbox genérica) + fallback SIN SMS para
-- verificar contactos de emergencia.
--
-- ANEXO DE DISEÑO: docs/plan-taxi-precio-fijo/16-sms-y-verificacion-contactos.md
--
-- PRERREQUISITOS
--   · 037_taxi_seguridad.sql
--       - muevete.contactos_emergencia (con codigo_hash, token_hash,
--         token_expira_at ya creados por 037)
--       - muevete.fn_token_hash(text)  (pepper en Vault o GUC)
--       - muevete.fn_confirmar_contacto(bigint, text, text)
--       - muevete.fn_iniciar_validacion_contacto(bigint)  ← se reemplaza aquí
--       - muevete.is_superadmin(), muevete.set_updated_at()
--   · pgcrypto (digest/gen_random_bytes) ya usado por 037.
--   · Proyecto de PRUEBAS: qhprswhhfasrikhawjoz.
--
-- QUÉ HACE
--   1. muevete.configuracion_sms (singleton): proveedor, remitente, activo,
--      max_intentos. Default 'mock': no envía nada y deja el flujo probado.
--   2. muevete.sms_mensajes (outbox genérica, reutilizable por CUALQUIER app).
--       · destinatario E.164 validado por CHECK.
--       · estado: pendiente | enviado | error | entregado | cancelado.
--       · RLS activada: sólo service_role escribe/lee; is_superadmin() puede
--         auditar por política explícita. anon/authenticated SIN acceso directo.
--   3. RPCs:
--       · fn_sms_encolar(...)          authenticated + service_role
--       · fn_sms_pendientes(limite)    service_role
--       · fn_sms_marcar(...)           service_role
--       · fn_contacto_invitacion(...)  authenticated (dueño del contacto)
--       · fn_confirmar_contacto_invitacion(token)  anon + authenticated
--         (endpoint de la página pública de confirmación; el contacto abre el
--          enlace que le llega por WhatsApp y no necesita cuenta)
--   4. Enganche del OTP al outbox: se reemplaza fn_iniciar_validacion_contacto
--      para que además de generar el código de 4 dígitos ENCOLE el SMS con
--      tipo='contacto_emergencia'. El código sigue sin devolverse fuera de dev.
--
-- REGLAS
--   · El OTP NUNCA se escribe en logs de la Edge Function ni se devuelve al
--     cliente en producción (se mantiene el comportamiento de 037: sólo con
--     el GUC muevete.entorno='dev').
--   · El outbox guarda el texto en claro porque el proveedor necesita el
--     texto; el acceso a la tabla queda limitado a service_role.
--   · El token de invitación viaja en claro UNA vez (respuesta de
--     fn_contacto_invitacion); en BD sólo queda sha256(token || pepper).
--   · Rate limit básico: máximo 5 SMS al mismo destinatario en 10 minutos.
--
-- IDEMPOTENCIA: IF NOT EXISTS / OR REPLACE / DROP POLICY IF EXISTS + CREATE /
--   INSERT ... ON CONFLICT / GRANT (repetible).
--
-- APLICAR SÓLO EN EL PROYECTO DE PRUEBAS. Nunca contra producción desde este
--   entorno: la verificación manual del final crea y borra datos de prueba.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 0. Prerrequisitos (falla rápido si falta la base de 037)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('muevete.contactos_emergencia') IS NULL THEN
    RAISE EXCEPTION 'falta muevete.contactos_emergencia (aplicar 037 primero)';
  END IF;
  IF to_regprocedure('muevete.fn_token_hash(text)') IS NULL THEN
    RAISE EXCEPTION 'falta muevete.fn_token_hash(text) (aplicar 037 primero)';
  END IF;
  IF to_regprocedure('muevete.fn_iniciar_validacion_contacto(bigint)') IS NULL THEN
    RAISE EXCEPTION 'falta muevete.fn_iniciar_validacion_contacto(bigint) (037)';
  END IF;
  IF to_regprocedure('muevete.is_superadmin()') IS NULL THEN
    RAISE EXCEPTION 'falta muevete.is_superadmin() (030)';
  END IF;
  IF to_regprocedure('muevete.set_updated_at()') IS NULL THEN
    RAISE EXCEPTION 'falta muevete.set_updated_at() (030)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pgcrypto') THEN
    RAISE EXCEPTION 'falta la extensión pgcrypto (gen_random_bytes/digest)';
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 0.b Columnas de invitación (defensivo)
--     037 ya las crea; si un entorno tiene 037 a medias, se completan aquí.
-- ----------------------------------------------------------------------------
ALTER TABLE muevete.contactos_emergencia
  ADD COLUMN IF NOT EXISTS token_hash      text,
  ADD COLUMN IF NOT EXISTS token_expira_at timestamptz;

CREATE UNIQUE INDEX IF NOT EXISTS contactos_emergencia_token_uidx
  ON muevete.contactos_emergencia (token_hash) WHERE token_hash IS NOT NULL;

-- ----------------------------------------------------------------------------
-- 1. muevete.configuracion_sms (singleton)
--    El default 'mock' permite arrancar sin cuenta de proveedor: la Edge
--    Function marca los SMS como enviados y NO llama a nadie.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS muevete.configuracion_sms (
  id            smallint PRIMARY KEY DEFAULT 1,
  proveedor     text NOT NULL DEFAULT 'mock'
                  CHECK (proveedor IN ('mock','clicksend','twilio')),
  remitente     text,
  activo        boolean NOT NULL DEFAULT true,
  max_intentos  smallint NOT NULL DEFAULT 3
                  CHECK (max_intentos BETWEEN 1 AND 10),
  updated_at    timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT configuracion_sms_singleton CHECK (id = 1)
);

INSERT INTO muevete.configuracion_sms (id) VALUES (1)
ON CONFLICT (id) DO NOTHING;

DROP TRIGGER IF EXISTS trg_configuracion_sms_updated_at ON muevete.configuracion_sms;
CREATE TRIGGER trg_configuracion_sms_updated_at
  BEFORE UPDATE ON muevete.configuracion_sms
  FOR EACH ROW EXECUTE FUNCTION muevete.set_updated_at();

COMMENT ON TABLE muevete.configuracion_sms IS
  'Configuración del servicio de SMS. Fila única id=1. proveedor=mock no envía nada (modo sin SMS).';
COMMENT ON COLUMN muevete.configuracion_sms.remitente IS
  'Alpha Tag / remitente que verá el destinatario (ClickSend: from; Twilio: From).';

-- ----------------------------------------------------------------------------
-- 2. muevete.sms_mensajes (outbox genérica)
--    Cualquier app del ecosistema encola con fn_sms_encolar(p_app => ...); un
--    único worker (Edge Function send-sms) despacha.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS muevete.sms_mensajes (
  id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  app                text NOT NULL DEFAULT 'muevete',
  destinatario       text NOT NULL,
  texto              text NOT NULL,
  tipo               text NOT NULL DEFAULT 'otro'
                       CHECK (tipo IN ('otp','contacto_emergencia','panico','aviso','otro')),
  ref_tabla          text,
  ref_id             text,
  estado             text NOT NULL DEFAULT 'pendiente'
                       CHECK (estado IN ('pendiente','enviado','error','entregado','cancelado')),
  proveedor          text,
  proveedor_msg_id   text,
  intentos           smallint NOT NULL DEFAULT 0,
  ultimo_error       text,
  programado_at      timestamptz NOT NULL DEFAULT now(),
  enviado_at         timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now(),

  -- E.164: +, primer dígito 1-9, entre 8 y 15 dígitos en total.
  CONSTRAINT sms_mensajes_destinatario_e164
    CHECK (destinatario ~ '^\+[1-9][0-9]{7,14}$'),
  CONSTRAINT sms_mensajes_texto_len
    CHECK (char_length(texto) BETWEEN 1 AND 480)
);

-- Cola: el worker pide pendientes ordenados por programado_at.
CREATE INDEX IF NOT EXISTS sms_mensajes_cola_idx
  ON muevete.sms_mensajes (estado, programado_at)
  WHERE estado = 'pendiente';

-- Rate limit (destinatario, últimos 10 minutos) y limpieza por antigüedad.
CREATE INDEX IF NOT EXISTS sms_mensajes_destinatario_idx
  ON muevete.sms_mensajes (destinatario, created_at DESC);

COMMENT ON TABLE muevete.sms_mensajes IS
  'Outbox de SMS reutilizable por cualquier app. Escribe/lee service_role (Edge Function send-sms) o las RPC SECURITY DEFINER.';
COMMENT ON COLUMN muevete.sms_mensajes.texto IS
  'Texto que se envía tal cual. Puede llevar un OTP: NUNCA se loguea completo desde la Edge Function.';
COMMENT ON COLUMN muevete.sms_mensajes.ref_tabla IS
  'Referencia lógica opcional (sin FK) para trazabilidad: contactos_emergencia, eventos_panico, etc.';
COMMENT ON COLUMN muevete.sms_mensajes.estado IS
  'pendiente → enviado/error. error se reintenta con backoff hasta max_intentos; entregado/cancelado los puede marcar el worker o un webhook futuro.';

-- ----------------------------------------------------------------------------
-- 3. RPC · fn_sms_encolar (cualquier app del ecosistema)
--    Valida E.164, longitud y rate limit; inserta en el outbox.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_sms_encolar(
  p_destinatario text,
  p_texto        text,
  p_tipo         text DEFAULT 'otro',
  p_app          text DEFAULT 'muevete',
  p_ref_tabla    text DEFAULT NULL,
  p_ref_id       text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_dest   text := btrim(coalesce(p_destinatario, ''));
  v_texto  text := coalesce(p_texto, '');
  v_tipo   text := lower(coalesce(nullif(btrim(p_tipo), ''), 'otro'));
  v_app    text := coalesce(nullif(btrim(p_app), ''), 'muevete');
  v_recent integer;
  v_id     bigint;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  IF v_dest !~ '^\+[1-9][0-9]{7,14}$' THEN
    RAISE EXCEPTION 'destinatario_invalido: se espera E.164 (ej. +5355550001)'
      USING ERRCODE = 'P0064';
  END IF;

  IF char_length(v_texto) < 1 OR char_length(v_texto) > 480 THEN
    RAISE EXCEPTION 'texto_invalido: entre 1 y 480 caracteres'
      USING ERRCODE = 'P0063';
  END IF;

  IF v_tipo NOT IN ('otp','contacto_emergencia','panico','aviso','otro') THEN
    RAISE EXCEPTION 'tipo_invalido: %', v_tipo USING ERRCODE = 'P0001';
  END IF;

  -- Rate limit: máximo 5 SMS al mismo destinatario en 10 minutos.
  -- Lock por destinatario para que dos llamadas concurrentes no lo esquiven.
  PERFORM pg_advisory_xact_lock(hashtext('sms_rate:' || v_dest));

  SELECT count(*) INTO v_recent
    FROM muevete.sms_mensajes
   WHERE destinatario = v_dest
     AND created_at > now() - interval '10 minutes';

  IF v_recent >= 5 THEN
    RAISE EXCEPTION 'sms_rate_limit: máximo 5 SMS cada 10 minutos por destinatario'
      USING ERRCODE = 'P0065',
            HINT = 'Espera o revisa si la app está en bucle de reintentos.';
  END IF;

  INSERT INTO muevete.sms_mensajes
    (app, destinatario, texto, tipo, ref_tabla, ref_id, estado)
  VALUES
    (v_app, v_dest, v_texto, v_tipo, p_ref_tabla, p_ref_id, 'pendiente')
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('success', true, 'id', v_id, 'estado', 'pendiente');
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_sms_encolar(text, text, text, text, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_sms_encolar(text, text, text, text, text, text)
  TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 4. RPC · fn_sms_pendientes (sólo service_role)
--    La llama la Edge Function send-sms. No marca nada: el worker marca con
--    fn_sms_marcar después de cada intento.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_sms_pendientes(p_limite integer DEFAULT 20)
RETURNS SETOF muevete.sms_mensajes
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_limite integer := greatest(1, least(coalesce(p_limite, 20), 100));
BEGIN
  IF coalesce(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'solo_service_role' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
    SELECT m.*
      FROM muevete.sms_mensajes m
     WHERE m.estado = 'pendiente'
       AND m.programado_at <= now()
     ORDER BY m.programado_at, m.id
     LIMIT v_limite;
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_sms_pendientes(integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION muevete.fn_sms_pendientes(integer) TO service_role;

-- ----------------------------------------------------------------------------
-- 5. RPC · fn_sms_marcar (sólo service_role)
--    resultado: enviado | entregado | error | cancelado.
--    Si error: intentos+1 y backoff de 5 min × intentos mientras queden
--    intentos; al agotarse max_intentos queda 'error' definitivo.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_sms_marcar(
  p_id               bigint,
  p_estado           text,
  p_error            text DEFAULT NULL,
  p_proveedor        text DEFAULT NULL,
  p_proveedor_msg_id text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_msg      muevete.sms_mensajes%ROWTYPE;
  v_estado   text := lower(btrim(coalesce(p_estado, '')));
  v_intentos smallint;
  v_max      smallint := 3;
  v_prog     timestamptz;
BEGIN
  IF coalesce(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'solo_service_role' USING ERRCODE = '42501';
  END IF;

  IF v_estado NOT IN ('enviado','entregado','error','cancelado') THEN
    RAISE EXCEPTION 'estado_invalido: %', v_estado USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_msg
    FROM muevete.sms_mensajes
   WHERE id = p_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'sms_no_existe' USING ERRCODE = 'P0066';
  END IF;

  IF v_estado = 'error' THEN
    SELECT coalesce(max_intentos, 3) INTO v_max
      FROM muevete.configuracion_sms WHERE id = 1;

    v_intentos := v_msg.intentos + 1;

    IF v_intentos < coalesce(v_max, 3) THEN
      -- Reintento: vuelve a la cola con backoff lineal 5/10/15... minutos.
      UPDATE muevete.sms_mensajes
         SET estado           = 'pendiente',
             intentos         = v_intentos,
             ultimo_error     = left(coalesce(p_error, 'error'), 500),
             proveedor        = coalesce(p_proveedor, proveedor),
             proveedor_msg_id = coalesce(p_proveedor_msg_id, proveedor_msg_id),
             programado_at    = now() + (interval '5 minutes' * v_intentos)
       WHERE id = p_id
       RETURNING programado_at INTO v_prog;

      RETURN jsonb_build_object(
        'success', true, 'id', p_id, 'estado', 'pendiente',
        'intentos', v_intentos, 'programado_at', v_prog);
    END IF;

    -- Se agotaron los intentos: error definitivo (no vuelve a la cola).
    UPDATE muevete.sms_mensajes
       SET estado           = 'error',
           intentos         = v_intentos,
           ultimo_error     = left(coalesce(p_error, 'error'), 500),
           proveedor        = coalesce(p_proveedor, proveedor),
           proveedor_msg_id = coalesce(p_proveedor_msg_id, proveedor_msg_id)
     WHERE id = p_id
     RETURNING programado_at INTO v_prog;

    RETURN jsonb_build_object(
      'success', true, 'id', p_id, 'estado', 'error',
      'intentos', v_intentos, 'programado_at', v_prog,
      'definitivo', true);
  END IF;

  -- enviado / entregado / cancelado: terminales.
  UPDATE muevete.sms_mensajes
     SET estado           = v_estado,
         enviado_at       = CASE WHEN v_estado IN ('enviado','entregado')
                                 THEN coalesce(enviado_at, now()) ELSE enviado_at END,
         ultimo_error     = CASE WHEN p_error IS NULL THEN ultimo_error
                                 ELSE left(p_error, 500) END,
         proveedor        = coalesce(p_proveedor, proveedor),
         proveedor_msg_id = coalesce(p_proveedor_msg_id, proveedor_msg_id)
   WHERE id = p_id
   RETURNING programado_at INTO v_prog;

  RETURN jsonb_build_object(
    'success', true, 'id', p_id, 'estado', v_estado,
    'intentos', v_msg.intentos, 'programado_at', v_prog);
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_sms_marcar(bigint, text, text, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION muevete.fn_sms_marcar(bigint, text, text, text, text)
  TO service_role;

-- ----------------------------------------------------------------------------
-- 6. FALLBACK SIN SMS · fn_contacto_invitacion
--    El dueño del contacto genera un enlace (token 32 bytes hex) y lo comparte
--    por WhatsApp/Telegram. En BD sólo queda el hash; expira en 7 días.
--    La app arma el texto a compartir con {url}.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_contacto_invitacion(p_contacto_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, public, extensions, pg_temp
AS $$
DECLARE
  v_uid     uuid := auth.uid();
  v_c       muevete.contactos_emergencia%ROWTYPE;
  v_token   text;
  v_hash    text;
  v_expira  timestamptz;
  v_base    text;
  v_intento integer := 0;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'no_autenticado' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO v_c FROM muevete.contactos_emergencia WHERE id = p_contacto_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'contacto_no_existe' USING ERRCODE = 'P0114';
  END IF;
  IF v_c.user_uuid <> v_uid AND NOT muevete.is_superadmin() THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  -- Ya verificado: no hace falta otro enlace (evita reenvíos innecesarios).
  IF v_c.estado = 'aceptado' AND v_c.verificado THEN
    RETURN jsonb_build_object(
      'success', true, 'contacto_id', p_contacto_id,
      'ya_confirmado', true, 'estado', v_c.estado);
  END IF;

  LOOP
    v_intento := v_intento + 1;
    -- 32 bytes aleatorios en hexadecimal (64 caracteres); el índice único de
    -- token_hash cubre la (improbable) colisión.
    v_token := encode(gen_random_bytes(32), 'hex');
    v_hash  := muevete.fn_token_hash(v_token);

    BEGIN
      UPDATE muevete.contactos_emergencia
         SET token_hash      = v_hash,
             token_expira_at = now() + interval '7 days'
       WHERE id = p_contacto_id
       RETURNING token_expira_at INTO v_expira;
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      IF v_intento >= 3 THEN
        RAISE EXCEPTION 'no_se_pudo_generar_token' USING ERRCODE = 'P0106';
      END IF;
    END;
  END LOOP;

  -- Base opcional para el enlace absoluto. Si no está configurada se devuelve
  -- la ruta relativa (como fn_crear_enlace_viaje) y la app antepone su domino.
  --   ALTER DATABASE postgres SET muevete.url_publica = 'https://muevete.app';
  v_base := nullif(btrim(coalesce(current_setting('muevete.url_publica', true), '')), '');

  RETURN jsonb_build_object(
    'success',       true,
    'contacto_id',   p_contacto_id,
    'token',         v_token,
    'url',           CASE WHEN v_base IS NULL THEN '/c/' || v_token
                          ELSE rtrim(v_base, '/') || '/c/' || v_token END,
    'expira_at',     v_expira,
    'dias_vigencia', 7,
    'canal',         'enlace',
    'mensaje',       'Comparte este enlace por WhatsApp o Telegram. El contacto lo abre y confirma sin instalar la app.');
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_contacto_invitacion(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_contacto_invitacion(bigint) TO authenticated;

-- ----------------------------------------------------------------------------
-- 7. FALLBACK SIN SMS · fn_confirmar_contacto_invitacion
--    Endpoint de la PÁGINA PÚBLICA: el contacto abre /c/<token>, sin cuenta.
--    Es SECURITY DEFINER y sólo actúa por posesión del token (32 bytes), igual
--    que fn_ver_enlace_viaje: no expone la tabla ni datos del titular.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_confirmar_contacto_invitacion(p_token text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, public, extensions, pg_temp
AS $$
DECLARE
  v_hash  text;
  v_c     muevete.contactos_emergencia%ROWTYPE;
  v_mask  text;
  v_ya    boolean;
BEGIN
  IF p_token IS NULL OR length(btrim(p_token)) < 16 THEN
    RETURN jsonb_build_object('success', false, 'motivo', 'token_invalido');
  END IF;

  v_hash := muevete.fn_token_hash(btrim(p_token));

  SELECT * INTO v_c
    FROM muevete.contactos_emergencia
   WHERE token_hash = v_hash
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'motivo', 'token_invalido');
  END IF;

  v_mask := '••••' || right(regexp_replace(v_c.telefono, '\D', '', 'g'), 4);
  v_ya   := (v_c.estado = 'aceptado' AND v_c.verificado);

  -- Reabrir el enlace de un contacto ya confirmado es idempotente.
  IF v_ya THEN
    RETURN jsonb_build_object(
      'success', true, 'ya_confirmado', true,
      'contacto_nombre', v_c.nombre, 'aceptado_por', v_mask);
  END IF;

  IF v_c.token_expira_at IS NULL OR v_c.token_expira_at <= now() THEN
    RETURN jsonb_build_object(
      'success', false, 'motivo', 'token_expirado',
      'contacto_nombre', v_c.nombre);
  END IF;

  UPDATE muevete.contactos_emergencia
     SET estado          = 'aceptado',
         verificado      = true,
         aceptado_at     = now(),
         codigo_hash     = NULL,
         codigo_expira_at = NULL,
         token_hash      = NULL,
         token_expira_at = NULL
   WHERE id = v_c.id;

  RETURN jsonb_build_object(
    'success', true, 'ya_confirmado', false,
    'contacto_nombre', v_c.nombre, 'aceptado_por', v_mask);
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_confirmar_contacto_invitacion(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION muevete.fn_confirmar_contacto_invitacion(text)
  TO anon, authenticated;

-- ----------------------------------------------------------------------------
-- 8. ENGANCHAR EL OTP AL OUTBOX
--    Se reemplaza fn_iniciar_validacion_contacto (037): mismo contrato +
--    sms_id y sms_estado. El envío NO puede romper la validación: si el outbox
--    falla (p. ej. rate limit) se devuelve sms_estado='no_encolado'.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_iniciar_validacion_contacto(p_contacto_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, public, extensions, pg_temp
AS $$
DECLARE
  v_uid         uuid := auth.uid();
  v_c           muevete.contactos_emergencia%ROWTYPE;
  v_codigo      text;
  v_nombre      text;
  v_texto       text;
  v_sms         jsonb;
  v_sms_id      bigint;
  v_sms_estado  text;
  v_expira      timestamptz;
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
    RETURN jsonb_build_object('success', true, 'estado', 'aceptado',
                              'ya_validado', true);
  END IF;

  v_codigo := lpad((floor(random() * 10000))::int::text, 4, '0');
  v_expira := now() + interval '24 hours';

  UPDATE muevete.contactos_emergencia
     SET codigo_hash         = muevete.fn_token_hash(v_codigo),
         codigo_expira_at    = v_expira,
         intentos_validacion = 0
   WHERE id = p_contacto_id;

  -- Nombre del titular para el texto del SMS (sin exponer teléfonos ajenos).
  SELECT nullif(btrim(coalesce(u.name, '')), '')
    INTO v_nombre
    FROM muevete.users u
   WHERE u.uuid = v_c.user_uuid
   LIMIT 1;
  v_nombre := left(coalesce(v_nombre, 'Un usuario de Muévete'), 40);

  v_texto := 'Muévete: ' || v_nombre
          || ' te agregó como contacto de emergencia. Código: ' || v_codigo
          || '. Válido 24 h.';

  BEGIN
    v_sms := muevete.fn_sms_encolar(
      p_destinatario => v_c.telefono,
      p_texto        => v_texto,
      p_tipo         => 'contacto_emergencia',
      p_app          => 'muevete',
      p_ref_tabla    => 'contactos_emergencia',
      p_ref_id       => p_contacto_id::text);
    v_sms_id     := (v_sms ->> 'id')::bigint;
    v_sms_estado := v_sms ->> 'estado';
  EXCEPTION WHEN others THEN
    -- Outbox caído o rate limit: la validación sigue funcionando (el contacto
    -- siempre puede confirmar por enlace). Se informa sin tumbar la RPC.
    v_sms_id     := NULL;
    v_sms_estado := 'no_encolado';
  END;

  IF coalesce(current_setting('muevete.entorno', true), '') = 'dev' THEN
    RETURN jsonb_build_object(
      'success',     true,
      'contacto_id', p_contacto_id,
      'codigo',      v_codigo,
      'entorno_dev', true,
      'expira_at',   v_expira,
      'sms_id',      v_sms_id,
      'sms_estado',  v_sms_estado,
      'mensaje',     'Entorno dev: código devuelto para pruebas');
  END IF;

  RETURN jsonb_build_object(
    'success',     true,
    'contacto_id', p_contacto_id,
    'entorno_dev', false,
    'verificado',  false,
    'expira_at',   v_expira,
    'sms_id',      v_sms_id,
    'sms_estado',  v_sms_estado,
    'mensaje',     'Contacto guardado sin verificar. Comparte el enlace de invitación o espera el SMS.');
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_iniciar_validacion_contacto(bigint)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_iniciar_validacion_contacto(bigint)
  TO authenticated;

-- ----------------------------------------------------------------------------
-- 9. RLS y permisos
--    · configuracion_sms: lectura autenticada; escritura superadmin.
--    · sms_mensajes: sólo service_role escribe/lee; is_superadmin() audita por
--      política explícita. anon y authenticated NO tienen acceso directo (las
--      apps usan fn_sms_encolar, SECURITY DEFINER).
-- ----------------------------------------------------------------------------
ALTER TABLE muevete.configuracion_sms ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.sms_mensajes      ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE muevete.configuracion_sms FROM anon;
REVOKE ALL ON TABLE muevete.sms_mensajes      FROM PUBLIC, anon, authenticated;

DROP POLICY IF EXISTS configuracion_sms_select_auth ON muevete.configuracion_sms;
CREATE POLICY configuracion_sms_select_auth
  ON muevete.configuracion_sms FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS superadmin_all_configuracion_sms ON muevete.configuracion_sms;
CREATE POLICY superadmin_all_configuracion_sms
  ON muevete.configuracion_sms FOR ALL TO authenticated
  USING (muevete.is_superadmin()) WITH CHECK (muevete.is_superadmin());

GRANT SELECT ON TABLE muevete.configuracion_sms TO authenticated;

-- El outbox expone el texto (puede llevar OTP). Sólo service_role (BYPASSRLS)
-- y, para auditoría, el superadmin con esta política de sólo lectura.
DROP POLICY IF EXISTS sms_mensajes_superadmin_select ON muevete.sms_mensajes;
CREATE POLICY sms_mensajes_superadmin_select
  ON muevete.sms_mensajes FOR SELECT TO authenticated
  USING (muevete.is_superadmin());

GRANT SELECT ON TABLE muevete.sms_mensajes TO authenticated;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN (ejecutar a mano; NO forma parte de la migración)
-- ============================================================================
-- 0) Objetos creados:
--   SELECT to_regclass('muevete.configuracion_sms'), to_regclass('muevete.sms_mensajes');
--   SELECT proveedor, remitente, activo, max_intentos FROM muevete.configuracion_sms;
--   -- esperado: mock | NULL | true | 3
--
-- 1) Encolar y contar pendientes:
--   SELECT muevete.fn_sms_encolar('+5355550001','prueba','aviso');
--   SELECT count(*) FROM muevete.sms_mensajes WHERE estado='pendiente';
--
-- 2) Rate limit (la 6.ª al mismo número debe fallar con SQLSTATE P0065):
--   DO $$
--   DECLARE i int; BEGIN
--     FOR i IN 1..6 LOOP
--       BEGIN
--         PERFORM muevete.fn_sms_encolar('+5355559000','rate '||i,'aviso');
--         RAISE NOTICE 'llamada % OK', i;
--       EXCEPTION WHEN others THEN
--         RAISE NOTICE 'llamada % ERROR % %', i, SQLSTATE, SQLERRM;
--       END;
--     END LOOP;
--   END $$;
--
-- 3) Invitación sin SMS (con sesión del dueño del contacto):
--   SELECT muevete.fn_contacto_invitacion(<contacto_id>);
--   -- devuelve {success, token, url, expira_at}; token no queda en claro:
--   SELECT length(token_hash), token_hash = muevete.fn_token_hash('<token>')
--     FROM muevete.contactos_emergencia WHERE id = <contacto_id>;
--
-- 4) Confirmación pública (rol anon, sin sesión):
--   SET ROLE anon;
--   SELECT muevete.fn_confirmar_contacto_invitacion('<token>');
--   RESET ROLE;
--   -- esperado: success=true, ya_confirmado=false, aceptado_por='••••<4 dígitos>'
--   -- y el contacto queda estado='aceptado', verificado=true, token_hash=NULL.
--
-- 5) OTP enganchado al outbox (con sesión del dueño):
--   SELECT muevete.fn_iniciar_validacion_contacto(<contacto_id>);
--   -- esperado: sms_id no nulo y sms_estado='pendiente' (sin 'codigo' fuera de dev).
--   SELECT id, tipo, ref_tabla, ref_id, estado
--     FROM muevete.sms_mensajes ORDER BY id DESC LIMIT 1;
--
-- 6) Worker sólo con service_role:
--   SET ROLE service_role;
--   SELECT muevete.fn_sms_pendientes(5);
--   SELECT muevete.fn_sms_marcar(<id>,'enviado',NULL,'mock','mock-<id>');
--   RESET ROLE;
--
-- 7) RLS: un usuario normal no ve el outbox:
--   SET ROLE authenticated;
--   SELECT count(*) FROM muevete.sms_mensajes;   -- 0 (política is_superadmin)
--   RESET ROLE;
--
-- 8) Idempotencia: re-ejecutar 050 completo no falla.
-- ============================================================================

-- ============================================================================
-- ROLLBACK (documentado; NO ejecutar en despliegue normal)
-- ============================================================================
-- BEGIN;
--   -- Restaurar la versión de fn_iniciar_validacion_contacto de 037 (copiar
--   -- el cuerpo desde 037_taxi_seguridad.sql) y después:
--   DROP FUNCTION IF EXISTS muevete.fn_confirmar_contacto_invitacion(text);
--   DROP FUNCTION IF EXISTS muevete.fn_contacto_invitacion(bigint);
--   DROP FUNCTION IF EXISTS muevete.fn_sms_marcar(bigint, text, text, text, text);
--   DROP FUNCTION IF EXISTS muevete.fn_sms_pendientes(integer);
--   DROP FUNCTION IF EXISTS muevete.fn_sms_encolar(text, text, text, text, text, text);
--   DROP TABLE IF EXISTS muevete.sms_mensajes;
--   DROP TABLE IF EXISTS muevete.configuracion_sms;
-- COMMIT;
-- ============================================================================