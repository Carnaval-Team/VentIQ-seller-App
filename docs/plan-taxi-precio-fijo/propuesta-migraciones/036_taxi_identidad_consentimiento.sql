-- ============================================================================
-- 036_taxi_identidad_consentimiento.sql
-- KYC obligatorio (perfil + CI + documentos + poblado) y consentimiento
-- versionado con auditoría. Incluye el gate de elegibilidad y sus RPC.
--
-- ANEXO DE DISEÑO: docs/plan-taxi-precio-fijo/09-identidad-y-vehiculos.md §4 y §5
--
-- PRERREQUISITOS
--   · 030_baseline_sync_produccion.sql  (NO se redefine: get_my_driver_id,
--     is_superadmin, complete_ride_payment, set_updated_at, triggers de push)
--   · 031_taxi_zonas_tarifas.sql        (config de tarifas, solicitudes)
--   · 035_taxi_vehiculos_catalogo.sql   (pasajeros/capacidad; el gate usa
--     la capacidad en 039, no aquí)
--
-- QUÉ HACE
--   1. users: poblado, ci, direccion, docs, tipo_documento + estado KYC.
--   2. drivers: ci, poblado, direccion + estado KYC (backfill desde carnet).
--   3. documentos_legales (versión + hash SHA-256 + publicación).
--   4. consentimientos (único por usuario+documento+versión, inmutable).
--   5. configuracion_identidad (singleton) con válvula de suspensión.
--   6. RPCs: fn_ci_valido, fn_usuario_habilitado (GATE), fn_aceptar_consentimiento,
--            fn_guardar_identidad, fn_kyc_revisar, fn_suspender_bloqueo_identidad.
--   7. Triggers de guarda (campos sensibles sólo por RPC) y RLS.
--
-- REGLAS
--   · El gate IMPIDE OPERAR, NO REGISTRARSE: la app deja crear cuenta y navegar;
--     bloquear publicar/tomar es responsabilidad de las RPC 038–040 (que lo
--     validan llamando a fn_usuario_habilitado).
--   · Sin dependencia de `service_role`: todo lo privilegiado va por RPC
--     SECURITY DEFINER y el cliente usa la clave publishable/anon.
--   · La suspensión (bloqueo_suspendido_hasta) relaja perfil/KYC/consentimiento,
--     pero NO `drivers.kyc` (aprobación de conducción) ni borra evidencia.
--
-- IDEMPOTENCIA
--   ADD COLUMN IF NOT EXISTS · CREATE TABLE/INDEX IF NOT EXISTS ·
--   ADD CONSTRAINT guardado con pg_constraint · CREATE OR REPLACE FUNCTION/VIEW ·
--   DROP TRIGGER IF EXISTS + CREATE · INSERT ... ON CONFLICT DO NOTHING.
--   Re-ejecutar dos veces no debe fallar.
--
-- NO EJECUTAR CONTRA SUPABASE DESDE ESTE ENTORNO (sólo se entrega el archivo).
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. muevete.users — identidad y estado KYC
--    (ci, direccion, province, municipality, tipo_documento, doc_* ya existen
--     en el entorno de desarrollo; IF NOT EXISTS las cubre en cualquier otro.)
-- ----------------------------------------------------------------------------
ALTER TABLE muevete.users
  ADD COLUMN IF NOT EXISTS ci                   character varying,
  ADD COLUMN IF NOT EXISTS poblado              text,
  ADD COLUMN IF NOT EXISTS direccion            text,
  ADD COLUMN IF NOT EXISTS province             text,
  ADD COLUMN IF NOT EXISTS municipality         text,
  ADD COLUMN IF NOT EXISTS tipo_documento       text,
  ADD COLUMN IF NOT EXISTS doc_frente_url       text,
  ADD COLUMN IF NOT EXISTS doc_dorso_url        text,
  ADD COLUMN IF NOT EXISTS kyc_estado           text NOT NULL DEFAULT 'pendiente',
  ADD COLUMN IF NOT EXISTS kyc_motivo           text,
  ADD COLUMN IF NOT EXISTS kyc_revisado_por     uuid,
  ADD COLUMN IF NOT EXISTS kyc_revisado_at      timestamptz,
  ADD COLUMN IF NOT EXISTS perfil_completado_at timestamptz;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'users_kyc_estado_chk'
                    AND conrelid = 'muevete.users'::regclass) THEN
    ALTER TABLE muevete.users
      ADD CONSTRAINT users_kyc_estado_chk
      CHECK (kyc_estado IN ('pendiente','en_revision','aprobado','rechazado')) NOT VALID;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'users_ci_formato_chk'
                    AND conrelid = 'muevete.users'::regclass) THEN
    -- NOT VALID: no rompe filas históricas con CI sucio; el gate valida.
    ALTER TABLE muevete.users
      ADD CONSTRAINT users_ci_formato_chk
      CHECK (ci IS NULL OR ci ~ '^[0-9]{11}$') NOT VALID;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS users_ci_idx
  ON muevete.users (ci) WHERE ci IS NOT NULL;
CREATE INDEX IF NOT EXISTS users_kyc_estado_idx
  ON muevete.users (kyc_estado);

COMMENT ON COLUMN muevete.users.poblado IS
  'Poblado / reparto / consejo popular. Obligatorio para el gate de identidad.';
COMMENT ON COLUMN muevete.users.kyc_estado IS
  'pendiente | en_revision | aprobado | rechazado. El gate exige que no sea rechazado; si requiere_aprobacion_kyc_cliente, exige aprobado.';
COMMENT ON COLUMN muevete.users.perfil_completado_at IS
  'Última vez que el usuario guardó su identidad por fn_guardar_identidad.';

-- ----------------------------------------------------------------------------
-- 2. muevete.drivers — identidad y estado KYC
--    En el flujo viejo el CI se guardaba en `carnet`; se copia a `ci`.
-- ----------------------------------------------------------------------------
ALTER TABLE muevete.drivers
  ADD COLUMN IF NOT EXISTS ci               character varying,
  ADD COLUMN IF NOT EXISTS poblado          text,
  ADD COLUMN IF NOT EXISTS direccion        text,
  ADD COLUMN IF NOT EXISTS kyc_estado       text NOT NULL DEFAULT 'pendiente',
  ADD COLUMN IF NOT EXISTS kyc_revisado_por uuid,
  ADD COLUMN IF NOT EXISTS kyc_revisado_at  timestamptz;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'drivers_kyc_estado_chk'
                    AND conrelid = 'muevete.drivers'::regclass) THEN
    ALTER TABLE muevete.drivers
      ADD CONSTRAINT drivers_kyc_estado_chk
      CHECK (kyc_estado IN ('pendiente','en_revision','aprobado','rechazado')) NOT VALID;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'drivers_ci_formato_chk'
                    AND conrelid = 'muevete.drivers'::regclass) THEN
    ALTER TABLE muevete.drivers
      ADD CONSTRAINT drivers_ci_formato_chk
      CHECK (ci IS NULL OR ci ~ '^[0-9]{11}$') NOT VALID;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS drivers_ci_idx
  ON muevete.drivers (ci) WHERE ci IS NOT NULL;
CREATE INDEX IF NOT EXISTS drivers_kyc_estado_idx
  ON muevete.drivers (kyc_estado);

-- Backfill: `carnet` guardaba el CI en el flujo viejo
UPDATE muevete.drivers
   SET ci = carnet
 WHERE ci IS NULL
   AND carnet ~ '^[0-9]{11}$';

-- Sincroniza el estado nuevo con los flags legacy (kyc/revisado)
UPDATE muevete.drivers
   SET kyc_estado = CASE
         WHEN coalesce(kyc, false) AND coalesce(revisado, false) THEN 'aprobado'
         WHEN coalesce(revisado, false) AND NOT coalesce(kyc, false) THEN 'rechazado'
         ELSE 'pendiente'
       END
 WHERE kyc_estado = 'pendiente';

-- ----------------------------------------------------------------------------
-- 3. muevete.documentos_legales (versionado + hash)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS muevete.documentos_legales (
  id              bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  codigo          text        NOT NULL,             -- 'privacidad' | 'terminos' | 'kyc' ...
  version         text        NOT NULL,             -- '1.0.0'
  titulo          text        NOT NULL,
  resumen         text,
  contenido_md    text        NOT NULL,
  es_obligatorio  boolean     NOT NULL DEFAULT true,
  publicado       boolean     NOT NULL DEFAULT false,
  vigente_desde   timestamptz NOT NULL DEFAULT now(),
  vigente_hasta   timestamptz,
  hash_contenido  text,
  created_by      uuid,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT documentos_legales_pkey PRIMARY KEY (id),
  CONSTRAINT documentos_legales_codigo_version_unq UNIQUE (codigo, version),
  CONSTRAINT documentos_legales_vigencia_chk
    CHECK (vigente_hasta IS NULL OR vigente_hasta > vigente_desde)
);

-- Sólo puede haber UNA versión publicada y vigente por código
CREATE UNIQUE INDEX IF NOT EXISTS documentos_legales_vigente_uidx
  ON muevete.documentos_legales (codigo)
  WHERE publicado AND vigente_hasta IS NULL;

CREATE INDEX IF NOT EXISTS documentos_legales_codigo_idx
  ON muevete.documentos_legales (codigo, vigente_desde DESC);

COMMENT ON TABLE muevete.documentos_legales IS
  'Documentos legales versionados. Al publicar una versión nueva se cierra la anterior (vigente_hasta). El hash permite probar qué texto aceptó cada usuario.';

-- Hash del contenido (auditoría). pgcrypto está instalado; se busca en extensions/public.
CREATE OR REPLACE FUNCTION muevete.fn_doc_legal_hash()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = muevete, extensions, public, pg_temp
AS $$
BEGIN
  NEW.hash_contenido := encode(digest(coalesce(NEW.contenido_md, ''), 'sha256'), 'hex');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_documentos_legales_hash ON muevete.documentos_legales;
CREATE TRIGGER trg_documentos_legales_hash
  BEFORE INSERT OR UPDATE OF contenido_md ON muevete.documentos_legales
  FOR EACH ROW EXECUTE FUNCTION muevete.fn_doc_legal_hash();

DROP TRIGGER IF EXISTS trg_documentos_legales_updated_at ON muevete.documentos_legales;
CREATE TRIGGER trg_documentos_legales_updated_at
  BEFORE UPDATE ON muevete.documentos_legales
  FOR EACH ROW EXECUTE FUNCTION muevete.set_updated_at();

-- ----------------------------------------------------------------------------
-- 4. muevete.consentimientos (auditoría inmutable)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS muevete.consentimientos (
  id                bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  user_uuid         uuid        NOT NULL,
  documento_id      bigint      NOT NULL,
  documento_codigo  text        NOT NULL,
  documento_version text        NOT NULL,
  aceptado          boolean     NOT NULL DEFAULT true,
  aceptado_at       timestamptz NOT NULL DEFAULT now(),
  metodo            text        NOT NULL DEFAULT 'app',
  app_version       text,
  user_agent        text,
  metadata          jsonb       NOT NULL DEFAULT '{}'::jsonb,
  created_at        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT consentimientos_pkey PRIMARY KEY (id),
  CONSTRAINT consentimientos_user_fkey FOREIGN KEY (user_uuid) REFERENCES auth.users(id),
  CONSTRAINT consentimientos_documento_fkey
    FOREIGN KEY (documento_id) REFERENCES muevete.documentos_legales(id),
  CONSTRAINT consentimientos_metodo_chk
    CHECK (metodo IN ('app','web','admin','migracion')),
  CONSTRAINT consentimientos_unq UNIQUE (user_uuid, documento_codigo, documento_version)
);

CREATE INDEX IF NOT EXISTS consentimientos_user_idx
  ON muevete.consentimientos (user_uuid, aceptado_at DESC);
CREATE INDEX IF NOT EXISTS consentimientos_doc_idx
  ON muevete.consentimientos (documento_codigo, documento_version);

COMMENT ON TABLE muevete.consentimientos IS
  'Evidencia de aceptación de documentos legales. Inmutable: se inserta, no se actualiza. Sólo por RPC.';

-- ----------------------------------------------------------------------------
-- 5. muevete.configuracion_identidad (singleton)
--    Incluye la válvula de suspensión operativa (bloqueo_suspendido_hasta).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS muevete.configuracion_identidad (
  id                              smallint    NOT NULL DEFAULT 1,
  kyc_obligatorio                 boolean     NOT NULL DEFAULT true,
  consentimiento_obligatorio      boolean     NOT NULL DEFAULT true,
  requiere_aprobacion_kyc_cliente boolean     NOT NULL DEFAULT false,
  requiere_aprobacion_kyc_chofer  boolean     NOT NULL DEFAULT true,
  dias_gracia                     integer     NOT NULL DEFAULT 0,
  mensaje_bloqueo                 text        NOT NULL DEFAULT
    'Para usar Muevete necesitas completar tu perfil y aceptar las políticas de privacidad.',
  -- Suspensión TEMPORAL del bloqueo: si > now(), el gate relaja KYC y
  -- consentimiento sin borrar evidencia. Se reanuda sola al vencer o con
  -- fn_suspender_bloqueo_identidad(0, NULL).
  bloqueo_suspendido_hasta        timestamptz,
  suspension_motivo               text,
  updated_at                      timestamptz NOT NULL DEFAULT now(),
  updated_by                      uuid,

  CONSTRAINT configuracion_identidad_pkey PRIMARY KEY (id),
  CONSTRAINT configuracion_identidad_singleton CHECK (id = 1),
  CONSTRAINT configuracion_identidad_gracia_chk CHECK (dias_gracia BETWEEN 0 AND 90)
);

INSERT INTO muevete.configuracion_identidad (id) VALUES (1)
ON CONFLICT (id) DO NOTHING;

DROP TRIGGER IF EXISTS trg_configuracion_identidad_updated_at ON muevete.configuracion_identidad;
CREATE TRIGGER trg_configuracion_identidad_updated_at
  BEFORE UPDATE ON muevete.configuracion_identidad
  FOR EACH ROW EXECUTE FUNCTION muevete.set_updated_at();

COMMENT ON TABLE muevete.configuracion_identidad IS
  'Configuración del gate de identidad. La suspensión temporal evita quedarse sin choferes operativos por una incidencia.';

-- ----------------------------------------------------------------------------
-- 6. Trigger de guarda: campos sensibles sólo por RPC
--    (mismo patrón que fn_solicitud_guarda de 031)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_identidad_guarda()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = muevete, pg_temp
AS $$
BEGIN
  IF coalesce(current_setting('muevete.rpc', true), 'off') = 'on' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.kyc_estado        IS DISTINCT FROM OLD.kyc_estado
       OR NEW.kyc_revisado_por IS DISTINCT FROM OLD.kyc_revisado_por
       OR NEW.kyc_revisado_at  IS DISTINCT FROM OLD.kyc_revisado_at
    THEN
      RAISE EXCEPTION 'kyc_solo_por_rpc_o_superadmin' USING ERRCODE = '42501';
    END IF;

    -- En users, CI/poblado/dirección/documentos sólo por fn_guardar_identidad
    IF TG_TABLE_NAME = 'users' THEN
      IF NEW.ci              IS DISTINCT FROM OLD.ci
         OR NEW.poblado      IS DISTINCT FROM OLD.poblado
         OR NEW.direccion    IS DISTINCT FROM OLD.direccion
         OR NEW.doc_frente_url IS DISTINCT FROM OLD.doc_frente_url
         OR NEW.doc_dorso_url  IS DISTINCT FROM OLD.doc_dorso_url
      THEN
        RAISE EXCEPTION 'usar_fn_guardar_identidad' USING ERRCODE = '42501';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION muevete.fn_identidad_guarda() IS
  'Bloquea escrituras directas de campos KYC/identidad fuera de las RPC.';

DROP TRIGGER IF EXISTS trg_users_identidad_guarda ON muevete.users;
CREATE TRIGGER trg_users_identidad_guarda
  BEFORE UPDATE ON muevete.users
  FOR EACH ROW EXECUTE FUNCTION muevete.fn_identidad_guarda();

DROP TRIGGER IF EXISTS trg_drivers_identidad_guarda ON muevete.drivers;
CREATE TRIGGER trg_drivers_identidad_guarda
  BEFORE UPDATE ON muevete.drivers
  FOR EACH ROW EXECUTE FUNCTION muevete.fn_identidad_guarda();

-- ----------------------------------------------------------------------------
-- 7. Validación de CI (formato cubano: 11 dígitos con fecha plausible)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_ci_valido(p_ci text)
RETURNS boolean
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v text := regexp_replace(coalesce(p_ci, ''), '\s', '', 'g');
BEGIN
  IF v !~ '^[0-9]{11}$' THEN
    RETURN false;
  END IF;
  IF substr(v, 3, 2)::integer NOT BETWEEN 1 AND 12 THEN
    RETURN false;
  END IF;
  IF substr(v, 5, 2)::integer NOT BETWEEN 1 AND 31 THEN
    RETURN false;
  END IF;
  BEGIN
    PERFORM to_date(substr(v, 1, 6), 'YYMMDD');
  EXCEPTION WHEN others THEN
    RETURN false;
  END;
  RETURN true;
END;
$$;

COMMENT ON FUNCTION muevete.fn_ci_valido(text) IS
  'Valida formato de CI cubano (11 dígitos con fecha plausible). No consulta el registro civil: la verificación real es la revisión KYC.';

-- ----------------------------------------------------------------------------
-- 8. GATE · fn_usuario_habilitado
--    Única fuente de verdad de "puede operar". No bloquea el registro.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_usuario_habilitado(
  p_uuid uuid DEFAULT auth.uid(),
  p_rol  text DEFAULT NULL      -- 'cliente' | 'chofer' | NULL (autodetecta)
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_uid uuid := coalesce(p_uuid, auth.uid());

  v_cfg_rows integer := 0;
  v_kyc_obl  boolean := false;
  v_cons_obl boolean := false;
  v_req_cli  boolean := false;
  v_req_cho  boolean := true;
  v_msg      text;
  v_susp     timestamptz;
  v_suspendido boolean := false;

  v_rol        text;
  v_hay_user   boolean := false;
  v_hay_driver boolean := false;

  u_ci text; u_tipo_doc text; u_frente text; u_dorso text;
  u_prov text; u_muni text; u_poblado text; u_dir text;
  u_kyc_estado text;

  d_ci text; d_tipo_doc text; d_frente text; d_dorso text;
  d_prov text; d_muni text; d_poblado text; d_dir text;
  d_kyc_estado text; d_kyc boolean := false;

  v_faltantes    text[] := ARRAY[]::text[];
  v_motivos      text[] := ARRAY[]::text[];
  v_consent_ok   boolean := true;
  v_consent_falt text[] := ARRAY[]::text[];
  v_kyc_ok       boolean := true;
  v_perfil_ok    boolean := false;
  v_habilitado   boolean := false;
  v_doc          record;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'no_autenticado' USING ERRCODE = '28000';
  END IF;

  -- ── 0. Configuración y suspensión operativa ───────────────────────────
  SELECT count(*) INTO v_cfg_rows FROM muevete.configuracion_identidad WHERE id = 1;
  IF v_cfg_rows > 0 THEN
    SELECT kyc_obligatorio, consentimiento_obligatorio,
           requiere_aprobacion_kyc_cliente, requiere_aprobacion_kyc_chofer,
           mensaje_bloqueo, bloqueo_suspendido_hasta
      INTO v_kyc_obl, v_cons_obl, v_req_cli, v_req_cho, v_msg, v_susp
      FROM muevete.configuracion_identidad
     WHERE id = 1;

    IF v_susp IS NOT NULL AND v_susp > now() THEN
      v_suspendido := true;
      v_kyc_obl  := false;
      v_cons_obl := false;
    END IF;
  END IF;

  -- ── 1. Datos del usuario / chofer (escalares: SELECT INTO con 0 filas = NULL) ──
  SELECT ci, tipo_documento, doc_frente_url, doc_dorso_url,
         province, municipality, poblado, direccion, kyc_estado
    INTO u_ci, u_tipo_doc, u_frente, u_dorso,
         u_prov, u_muni, u_poblado, u_dir, u_kyc_estado
    FROM muevete.users WHERE uuid = v_uid LIMIT 1;
  v_hay_user := FOUND;

  SELECT ci, tipo_documento, doc_frente_url, doc_dorso_url,
         province, municipality, poblado, direccion, kyc_estado,
         coalesce(kyc, false)
    INTO d_ci, d_tipo_doc, d_frente, d_dorso,
         d_prov, d_muni, d_poblado, d_dir, d_kyc_estado, d_kyc
    FROM muevete.drivers WHERE uuid = v_uid LIMIT 1;
  v_hay_driver := FOUND;

  v_rol := coalesce(p_rol,
                    CASE WHEN v_hay_driver THEN 'chofer'
                         WHEN v_hay_user   THEN 'cliente' END);
  IF v_rol IS NULL THEN
    RAISE EXCEPTION 'usuario_sin_perfil' USING ERRCODE = 'P0001';
  END IF;
  IF v_rol NOT IN ('cliente','chofer') THEN
    RAISE EXCEPTION 'rol_invalido: %', v_rol USING ERRCODE = 'P0001';
  END IF;

  -- ── 2. Perfil / documentos ────────────────────────────────────────────
  IF v_rol = 'cliente' THEN
    IF NOT v_hay_user THEN
      v_faltantes := array_append(v_faltantes, 'perfil_cliente');
    ELSE
      IF NOT muevete.fn_ci_valido(u_ci)                  THEN v_faltantes := array_append(v_faltantes, 'ci'); END IF;
      IF coalesce(trim(u_tipo_doc), '') = ''             THEN v_faltantes := array_append(v_faltantes, 'tipo_documento'); END IF;
      IF coalesce(trim(u_frente), '') = ''               THEN v_faltantes := array_append(v_faltantes, 'doc_frente'); END IF;
      IF coalesce(trim(u_dorso), '') = ''                THEN v_faltantes := array_append(v_faltantes, 'doc_dorso'); END IF;
      IF coalesce(trim(u_prov), '') = ''                 THEN v_faltantes := array_append(v_faltantes, 'provincia'); END IF;
      IF coalesce(trim(u_muni), '') = ''                 THEN v_faltantes := array_append(v_faltantes, 'municipio'); END IF;
      IF coalesce(trim(u_poblado), '') = ''              THEN v_faltantes := array_append(v_faltantes, 'poblado'); END IF;
      IF coalesce(trim(u_dir), '') = ''                  THEN v_faltantes := array_append(v_faltantes, 'direccion'); END IF;
    END IF;
  ELSE
    IF NOT v_hay_driver THEN
      v_faltantes := array_append(v_faltantes, 'perfil_chofer');
    ELSE
      IF NOT muevete.fn_ci_valido(d_ci)                  THEN v_faltantes := array_append(v_faltantes, 'ci'); END IF;
      IF coalesce(trim(d_tipo_doc), '') = ''             THEN v_faltantes := array_append(v_faltantes, 'tipo_documento'); END IF;
      IF coalesce(trim(d_frente), '') = ''               THEN v_faltantes := array_append(v_faltantes, 'doc_frente'); END IF;
      IF coalesce(trim(d_dorso), '') = ''                THEN v_faltantes := array_append(v_faltantes, 'doc_dorso'); END IF;
      IF coalesce(trim(d_prov), '') = ''                 THEN v_faltantes := array_append(v_faltantes, 'provincia'); END IF;
      IF coalesce(trim(d_muni), '') = ''                 THEN v_faltantes := array_append(v_faltantes, 'municipio'); END IF;
      IF coalesce(trim(d_poblado), '') = ''              THEN v_faltantes := array_append(v_faltantes, 'poblado'); END IF;
      IF coalesce(trim(d_dir), '') = ''                  THEN v_faltantes := array_append(v_faltantes, 'direccion'); END IF;
    END IF;
  END IF;

  v_perfil_ok := array_length(v_faltantes, 1) IS NULL;

  -- ── 3. Estado KYC ─────────────────────────────────────────────────────
  IF v_rol = 'cliente' THEN
    IF v_kyc_obl THEN
      IF u_kyc_estado = 'rechazado' THEN
        v_kyc_ok := false;
        v_motivos := array_append(v_motivos, 'kyc_rechazado');
      ELSIF v_req_cli AND coalesce(u_kyc_estado, 'pendiente') <> 'aprobado' THEN
        v_kyc_ok := false;
        v_motivos := array_append(v_motivos, 'kyc_pendiente_aprobacion');
      END IF;
    END IF;
  ELSE
    -- La aprobación de conducción (drivers.kyc) NO se suspende nunca
    IF d_kyc_estado = 'rechazado' THEN
      v_kyc_ok := false;
      v_motivos := array_append(v_motivos, 'kyc_rechazado');
    ELSIF v_req_cho AND coalesce(d_kyc_estado, 'pendiente') <> 'aprobado' THEN
      v_kyc_ok := false;
      v_motivos := array_append(v_motivos, 'kyc_pendiente_aprobacion');
    END IF;
  END IF;

  -- ── 4. Consentimientos de documentos obligatorios vigentes ────────────
  IF v_cons_obl THEN
    IF NOT EXISTS (
      SELECT 1 FROM muevete.documentos_legales
       WHERE publicado AND es_obligatorio
         AND (vigente_hasta IS NULL OR vigente_hasta > now())
    ) THEN
      -- Sin documentos publicados no se puede exigir consentimiento (evita lockout)
      v_consent_ok := true;
    ELSE
      FOR v_doc IN
        SELECT dl.codigo, dl.version
          FROM muevete.documentos_legales dl
         WHERE dl.publicado
           AND dl.es_obligatorio
           AND (dl.vigente_hasta IS NULL OR dl.vigente_hasta > now())
      LOOP
        IF NOT EXISTS (
          SELECT 1 FROM muevete.consentimientos c
           WHERE c.user_uuid = v_uid
             AND c.documento_codigo = v_doc.codigo
             AND c.documento_version = v_doc.version
             AND c.aceptado
        ) THEN
          v_consent_ok := false;
          v_consent_falt := array_append(v_consent_falt,
                                         v_doc.codigo || '@' || v_doc.version);
        END IF;
      END LOOP;
    END IF;

    IF NOT v_consent_ok THEN
      v_motivos := array_append(v_motivos, 'consentimiento_pendiente');
    END IF;
  END IF;

  -- ── 5. Veredicto ──────────────────────────────────────────────────────
  v_habilitado :=
        (NOT v_kyc_obl OR v_perfil_ok)
    AND v_kyc_ok
    AND v_consent_ok
    AND (v_rol <> 'chofer' OR (v_hay_driver AND coalesce(d_kyc, false)))
    AND (v_rol <> 'cliente' OR v_hay_user);

  RETURN jsonb_build_object(
    'habilitado',        v_habilitado,
    'uuid',              v_uid,
    'rol',               v_rol,
    'kyc_obligatorio',   v_kyc_obl,
    'consentimiento_obligatorio', v_cons_obl,
    'perfil', jsonb_build_object(
      'ok',         v_perfil_ok,
      'faltantes',  to_jsonb(v_faltantes),
      'kyc_estado', CASE WHEN v_rol = 'cliente' THEN u_kyc_estado ELSE d_kyc_estado END
    ),
    'consentimiento', jsonb_build_object(
      'ok',        v_consent_ok,
      'faltantes', to_jsonb(v_consent_falt)
    ),
    'motivos',            to_jsonb(v_motivos),
    'mensaje',            v_msg,
    'bloqueo_suspendido', v_suspendido,
    'suspension_hasta',   v_susp,
    'operar_permitido',   v_habilitado
  );
END;
$$;

COMMENT ON FUNCTION muevete.fn_usuario_habilitado(uuid, text) IS
  'RPC. Gate único de elegibilidad. Lo usan la app y las RPC de precio (038–040).';

-- ----------------------------------------------------------------------------
-- 9. RPC · aceptar consentimiento (auditado e idempotente)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_aceptar_consentimiento(
  p_codigo      text,
  p_version     text,
  p_metodo      text  DEFAULT 'app',
  p_app_version text  DEFAULT NULL,
  p_user_agent  text  DEFAULT NULL,
  p_metadata    jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_doc muevete.documentos_legales%ROWTYPE;
  v_id  bigint;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'no_autenticado' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO v_doc
    FROM muevete.documentos_legales
   WHERE codigo = p_codigo AND version = p_version
   LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'documento_no_existe: %@%', p_codigo, p_version USING ERRCODE = 'P0042';
  END IF;
  IF NOT v_doc.publicado
     OR (v_doc.vigente_hasta IS NOT NULL AND v_doc.vigente_hasta <= now()) THEN
    RAISE EXCEPTION 'documento_no_vigente: %@%', p_codigo, p_version USING ERRCODE = 'P0043';
  END IF;

  INSERT INTO muevete.consentimientos
    (user_uuid, documento_id, documento_codigo, documento_version,
     aceptado, metodo, app_version, user_agent, metadata)
  VALUES
    (v_uid, v_doc.id, v_doc.codigo, v_doc.version,
     true, p_metodo, p_app_version, p_user_agent, coalesce(p_metadata, '{}'::jsonb))
  ON CONFLICT (user_uuid, documento_codigo, documento_version) DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    SELECT id INTO v_id FROM muevete.consentimientos
     WHERE user_uuid = v_uid AND documento_codigo = v_doc.codigo
       AND documento_version = v_doc.version;
  END IF;

  RETURN jsonb_build_object(
    'success',           true,
    'consentimiento_id', v_id,
    'codigo',            v_doc.codigo,
    'version',           v_doc.version,
    'hash_contenido',    v_doc.hash_contenido,
    'aceptado_at',       now());
END;
$$;

-- ----------------------------------------------------------------------------
-- 10. RPC · guardar identidad (perfil + documentos)
--     Whitelist de campos. No permite tocar kyc_estado (eso es del superadmin).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_guardar_identidad(
  p_rol   text,                    -- 'cliente' | 'chofer'
  p_datos jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_ci       text := nullif(trim(p_datos ->> 'ci'), '');
  v_poblado  text := nullif(trim(p_datos ->> 'poblado'), '');
  v_dir      text := nullif(trim(p_datos ->> 'direccion'), '');
  v_prov     text := nullif(trim(p_datos ->> 'province'), '');
  v_muni     text := nullif(trim(p_datos ->> 'municipality'), '');
  v_tipo_doc text := nullif(trim(p_datos ->> 'tipo_documento'), '');
  v_frente   text := nullif(trim(p_datos ->> 'doc_frente_url'), '');
  v_dorso    text := nullif(trim(p_datos ->> 'doc_dorso_url'), '');
  v_nombre   text := nullif(trim(p_datos ->> 'name'), '');
  v_telefono text := nullif(trim(p_datos ->> 'telefono'), '');
  v_gate     jsonb;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'no_autenticado' USING ERRCODE = '28000';
  END IF;
  IF p_rol NOT IN ('cliente','chofer') THEN
    RAISE EXCEPTION 'rol_invalido: %', p_rol USING ERRCODE = 'P0001';
  END IF;
  IF v_ci IS NOT NULL AND NOT muevete.fn_ci_valido(v_ci) THEN
    RAISE EXCEPTION 'ci_invalido' USING ERRCODE = 'P0044';
  END IF;

  IF p_rol = 'cliente' THEN
    UPDATE muevete.users SET
      ci             = coalesce(v_ci, ci),
      poblado        = coalesce(v_poblado, poblado),
      direccion      = coalesce(v_dir, direccion),
      province       = coalesce(v_prov, province),
      municipality   = coalesce(v_muni, municipality),
      tipo_documento = coalesce(v_tipo_doc, tipo_documento),
      doc_frente_url = coalesce(v_frente, doc_frente_url),
      doc_dorso_url  = coalesce(v_dorso, doc_dorso_url),
      name           = coalesce(v_nombre, name),
      phone          = coalesce(v_telefono, phone),
      kyc_estado     = CASE
                         WHEN kyc_estado = 'rechazado' THEN 'en_revision'
                         WHEN kyc_estado = 'aprobado'  THEN 'aprobado'
                         ELSE 'en_revision'
                       END,
      perfil_completado_at = now()
    WHERE uuid = v_uid;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'perfil_no_existe' USING ERRCODE = 'P0045';
    END IF;
  ELSE
    UPDATE muevete.drivers SET
      ci             = coalesce(v_ci, ci),
      poblado        = coalesce(v_poblado, poblado),
      direccion      = coalesce(v_dir, direccion),
      province       = coalesce(v_prov, province),
      municipality   = coalesce(v_muni, municipality),
      tipo_documento = coalesce(v_tipo_doc, tipo_documento),
      doc_frente_url = coalesce(v_frente, doc_frente_url),
      doc_dorso_url  = coalesce(v_dorso, doc_dorso_url),
      name           = coalesce(v_nombre, name),
      telefono       = coalesce(v_telefono, telefono),
      kyc_estado     = CASE
                         WHEN kyc_estado = 'rechazado' THEN 'en_revision'
                         WHEN kyc_estado = 'aprobado'  THEN 'aprobado'
                         ELSE 'en_revision'
                       END
    WHERE uuid = v_uid;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'perfil_chofer_no_existe' USING ERRCODE = 'P0045';
    END IF;
  END IF;

  v_gate := muevete.fn_usuario_habilitado(v_uid, p_rol);

  RETURN jsonb_build_object('success', true, 'rol', p_rol, 'gate', v_gate);
END;
$$;

-- ----------------------------------------------------------------------------
-- 11. RPC · revisión KYC (sólo superadmin)
--     Sincroniza los flags legacy de drivers (kyc/revisado/motivo).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_kyc_revisar(
  p_rol      text,     -- 'cliente' | 'chofer'
  p_uuid     uuid,
  p_decision text,     -- 'aprobado' | 'rechazado' | 'en_revision'
  p_motivo   text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  IF NOT muevete.is_superadmin() THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;
  IF p_decision NOT IN ('aprobado','rechazado','en_revision') THEN
    RAISE EXCEPTION 'decision_invalida: %', p_decision USING ERRCODE = 'P0001';
  END IF;

  IF p_rol = 'cliente' THEN
    UPDATE muevete.users
       SET kyc_estado       = p_decision,
           kyc_motivo       = p_motivo,
           kyc_revisado_por = auth.uid(),
           kyc_revisado_at  = now()
     WHERE uuid = p_uuid;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'usuario_no_existe' USING ERRCODE = 'P0045';
    END IF;
  ELSIF p_rol = 'chofer' THEN
    UPDATE muevete.drivers
       SET kyc_estado       = p_decision,
           kyc_revisado_por = auth.uid(),
           kyc_revisado_at  = now(),
           kyc              = (p_decision = 'aprobado'),
           revisado         = (p_decision IN ('aprobado','rechazado')),
           motivo           = p_motivo
     WHERE uuid = p_uuid;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'chofer_no_existe' USING ERRCODE = 'P0045';
    END IF;
  ELSE
    RAISE EXCEPTION 'rol_invalido: %', p_rol USING ERRCODE = 'P0001';
  END IF;

  RETURN jsonb_build_object('success', true, 'rol', p_rol, 'uuid', p_uuid,
                            'decision', p_decision, 'revisado_at', now());
END;
$$;

-- ----------------------------------------------------------------------------
-- 12. RPC · suspender / reanudar el bloqueo de identidad (válvula operativa)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_suspender_bloqueo_identidad(
  p_minutos integer,
  p_motivo  text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_hasta timestamptz;
BEGIN
  IF NOT muevete.is_superadmin() THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;
  IF p_minutos IS NULL OR p_minutos < 0 OR p_minutos > 43200 THEN  -- máx 30 días
    RAISE EXCEPTION 'minutos_invalidos: %', p_minutos USING ERRCODE = 'P0001';
  END IF;

  IF p_minutos = 0 THEN
    v_hasta := NULL;                                  -- reanudar
  ELSE
    v_hasta := now() + make_interval(mins => p_minutos);
  END IF;

  UPDATE muevete.configuracion_identidad
     SET bloqueo_suspendido_hasta = v_hasta,
         suspension_motivo        = p_motivo,
         updated_by               = auth.uid()
   WHERE id = 1;

  RETURN jsonb_build_object(
    'success',          true,
    'suspendido',       v_hasta IS NOT NULL,
    'suspension_hasta', v_hasta,
    'motivo',           p_motivo);
END;
$$;

-- ----------------------------------------------------------------------------
-- 13. Permisos de funciones
--     Helpers internos: sin acceso. RPC: sólo authenticated (clave publishable).
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION muevete.fn_ci_valido(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_ci_valido(text) TO authenticated;

REVOKE ALL ON FUNCTION muevete.fn_usuario_habilitado(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_usuario_habilitado(uuid, text) TO authenticated;

REVOKE ALL ON FUNCTION muevete.fn_aceptar_consentimiento(text, text, text, text, text, jsonb)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_aceptar_consentimiento(text, text, text, text, text, jsonb)
  TO authenticated;

REVOKE ALL ON FUNCTION muevete.fn_guardar_identidad(text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_guardar_identidad(text, jsonb) TO authenticated;

REVOKE ALL ON FUNCTION muevete.fn_kyc_revisar(text, uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_kyc_revisar(text, uuid, text, text) TO authenticated;

REVOKE ALL ON FUNCTION muevete.fn_suspender_bloqueo_identidad(integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_suspender_bloqueo_identidad(integer, text) TO authenticated;

-- ----------------------------------------------------------------------------
-- 14. RLS de las tablas nuevas
-- ----------------------------------------------------------------------------
ALTER TABLE muevete.documentos_legales      ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.consentimientos         ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.configuracion_identidad ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON muevete.documentos_legales, muevete.consentimientos,
              muevete.configuracion_identidad FROM anon;

-- Documentos: lectura de publicados (o superadmin); escritura superadmin
DROP POLICY IF EXISTS documentos_legales_select_auth ON muevete.documentos_legales;
CREATE POLICY documentos_legales_select_auth
  ON muevete.documentos_legales FOR SELECT TO authenticated
  USING (publicado OR muevete.is_superadmin());

DROP POLICY IF EXISTS superadmin_all_documentos_legales ON muevete.documentos_legales;
CREATE POLICY superadmin_all_documentos_legales
  ON muevete.documentos_legales FOR ALL TO authenticated
  USING (muevete.is_superadmin()) WITH CHECK (muevete.is_superadmin());

-- Consentimientos: cada usuario ve los suyos; superadmin todos.
-- Sin política de INSERT/UPDATE/DELETE: sólo se escriben por RPC SECURITY DEFINER.
DROP POLICY IF EXISTS consentimientos_select_own ON muevete.consentimientos;
CREATE POLICY consentimientos_select_own
  ON muevete.consentimientos FOR SELECT TO authenticated
  USING (user_uuid = auth.uid());

DROP POLICY IF EXISTS superadmin_all_consentimientos ON muevete.consentimientos;
CREATE POLICY superadmin_all_consentimientos
  ON muevete.consentimientos FOR ALL TO authenticated
  USING (muevete.is_superadmin()) WITH CHECK (muevete.is_superadmin());

-- Configuración identidad: lectura autenticada; escritura superadmin
DROP POLICY IF EXISTS configuracion_identidad_select_auth ON muevete.configuracion_identidad;
CREATE POLICY configuracion_identidad_select_auth
  ON muevete.configuracion_identidad FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS superadmin_all_configuracion_identidad ON muevete.configuracion_identidad;
CREATE POLICY superadmin_all_configuracion_identidad
  ON muevete.configuracion_identidad FOR ALL TO authenticated
  USING (muevete.is_superadmin()) WITH CHECK (muevete.is_superadmin());

GRANT SELECT ON muevete.documentos_legales, muevete.configuracion_identidad TO authenticated;
GRANT SELECT ON muevete.consentimientos TO authenticated;
GRANT INSERT, UPDATE, DELETE ON muevete.documentos_legales TO authenticated;
GRANT UPDATE ON muevete.configuracion_identidad TO authenticated;
-- consentimientos: sin INSERT/UPDATE/DELETE para authenticated (sólo RPC)

-- ----------------------------------------------------------------------------
-- 15. Lectura mínima del cliente asignado (necesaria para el viaje)
--     La política blanket `users_ FOR ALL USING(true)` se cierra en 041; aquí
--     sólo se añade el acceso legítimo del chofer asignado. Es aditiva.
--
--     DEPENDENCIA CON 041 (hardening, otro archivo): para que esta política
--     evalúe el EXISTS, 041 debe crear en solicitudes_transporte una política
--     `solicitudes_select_driver_asignado` con
--         USING (driver_id = muevete.get_my_driver_id())
--     Si 041 elimina `drivers_see_solicitudes` sin añadir esa política, el
--     chofer no podrá leer el nombre/teléfono del cliente en el viaje.
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS users_select_conductor_asignado ON muevete.users;
CREATE POLICY users_select_conductor_asignado
  ON muevete.users FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
        FROM muevete.solicitudes_transporte s
       WHERE s.user_id = muevete.users.uuid
         AND s.driver_id = muevete.get_my_driver_id()
         AND s.estado IN ('aceptada','completada')
    )
  );

-- ----------------------------------------------------------------------------
-- 16. Seed de documentos legales + configuración del gate
--     ⚠️ PLACEHOLDER: el texto legal real se carga antes del cutover (bloqueante).
-- ----------------------------------------------------------------------------
INSERT INTO muevete.documentos_legales
  (codigo, version, titulo, resumen, contenido_md, es_obligatorio, publicado, vigente_desde)
VALUES
  ('privacidad', '1.0.0', 'Política de Privacidad',
   'Qué datos recogemos, para qué y durante cuánto tiempo.',
   '<!-- PLACEHOLDER: reemplazar por el texto legal aprobado antes del cutover -->'
   || E'\n\n## 1. Datos que recopilamos\n'
   || E'- Identificación: nombre, carnet de identidad, fotos del carnet.\n'
   || E'- Contacto: teléfono, correo.\n'
   || E'- Ubicación: necesaria para emparejar viajes.\n\n'
   || E'## 2. Uso de los datos\n'
   || E'Los datos se usan para prestar el servicio de transporte y cumplir obligaciones legales.\n\n'
   || E'## 3. Conservación y derechos\n'
   || E'Puedes solicitar acceso, rectificación o eliminación de tus datos.\n',
   true, true, now()),

  ('terminos', '1.0.0', 'Términos y Condiciones',
   'Reglas de uso del servicio de transporte.',
   '<!-- PLACEHOLDER: reemplazar por el texto legal aprobado antes del cutover -->'
   || E'\n\n## 1. Servicio\n'
   || E'Muevete conecta pasajeros con conductores. El precio lo fija la plataforma.\n\n'
   || E'## 2. Obligaciones del pasajero y del conductor\n'
   || E'Respeto, veracidad de los datos y cumplimiento de las normas de tránsito.\n\n'
   || E'## 3. Comisiones y pagos\n'
   || E'La comisión vigente se muestra en la app antes de aceptar un viaje.\n',
   true, true, now()),

  ('kyc', '1.0.0', 'Consentimiento de verificación de identidad',
   'Tratamiento de tu CI y de las fotos de tu carnet.',
   '<!-- PLACEHOLDER: reemplazar por el texto legal aprobado antes del cutover -->'
   || E'\n\nAutorizas la verificación de tu identidad mediante el carnet de identidad '
   || E'y su revisión por el equipo de operaciones. Las imágenes se almacenan de forma '
   || E'restringida y sólo se usan para verificación.\n',
   true, true, now())
ON CONFLICT (codigo, version) DO NOTHING;

UPDATE muevete.configuracion_identidad SET
  kyc_obligatorio                 = true,
  consentimiento_obligatorio      = true,
  requiere_aprobacion_kyc_cliente = false,   -- D-3: el cliente no espera aprobación
  requiere_aprobacion_kyc_chofer  = true,    -- el chofer sí
  dias_gracia                     = 0,
  updated_at                      = now()
WHERE id = 1;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN (ejecutar a mano; NO forma parte de la migración)
-- ============================================================================
-- 1) Columnas:
--   SELECT column_name FROM information_schema.columns
--    WHERE table_schema='muevete' AND table_name='users'
--      AND column_name IN ('poblado','ci','direccion','kyc_estado',
--                          'kyc_revisado_por','perfil_completado_at');
--   SELECT column_name FROM information_schema.columns
--    WHERE table_schema='muevete' AND table_name='drivers'
--      AND column_name IN ('ci','poblado','direccion','kyc_estado');
--
-- 2) Backfill de CI del chofer desde carnet:
--   SELECT count(*) FILTER (WHERE ci IS NOT NULL) AS con_ci,
--          count(*) FILTER (WHERE kyc_estado = 'aprobado') AS aprobados
--     FROM muevete.drivers;
--
-- 3) Documentos publicados (esperado 3, v1.0.0, con hash no nulo):
--   SELECT codigo, version, es_obligatorio, publicado, left(hash_contenido,12) AS hash
--     FROM muevete.documentos_legales ORDER BY codigo;
--
-- 4) Gate de un usuario con perfil incompleto (habilitado=false + faltantes):
--   SELECT jsonb_pretty(muevete.fn_usuario_habilitado('<uuid>', 'cliente'));
--
-- 5) Consentimiento idempotente (mismo consentimiento_id las dos veces):
--   SELECT muevete.fn_aceptar_consentimiento('privacidad','1.0.0','app','test','test');
--   SELECT muevete.fn_aceptar_consentimiento('privacidad','1.0.0','app','test','test');
--
-- 6) Suspensión (5 min) y reanudación:
--   SELECT muevete.fn_suspender_bloqueo_identidad(5, 'prueba');
--   SELECT jsonb_pretty(muevete.fn_usuario_habilitado('<uuid incompleto>', 'cliente'));
--     -- habilitado=true, bloqueo_suspendido=true
--   SELECT muevete.fn_suspender_bloqueo_identidad(0, NULL);
--   SELECT jsonb_pretty(muevete.fn_usuario_habilitado('<uuid incompleto>', 'cliente'));
--     -- habilitado=false
--
-- 7) CI:
--   SELECT muevete.fn_ci_valido('90010112345') AS ok,      -- true
--          muevete.fn_ci_valido('90013212345') AS mes_malo, -- false
--          muevete.fn_ci_valido('123')          AS corto;    -- false
--
-- 8) Trigger de guarda (debe fallar):
--   UPDATE muevete.users SET ci = '90010112345' WHERE uuid = '<uuid>';
--     -- ERROR: usar_fn_guardar_identidad
--
-- 9) RLS:
--   SELECT tablename, policyname FROM pg_policies
--    WHERE schemaname='muevete'
--      AND tablename IN ('documentos_legales','consentimientos','configuracion_identidad')
--    ORDER BY tablename, policyname;   -- esperado 6+1 políticas
--
-- 10) Idempotencia: re-ejecutar 036 completo no falla.
-- ============================================================================

-- ============================================================================
-- DOWN (documentado; NO ejecutar en despliegue normal)
-- ----------------------------------------------------------------------------
-- Rollback de NEGOCIO (preferido):
--   UPDATE muevete.configuracion_identidad
--      SET kyc_obligatorio=false, consentimiento_obligatorio=false WHERE id=1;
-- ============================================================================
-- BEGIN;
-- DROP POLICY IF EXISTS users_select_conductor_asignado ON muevete.users;
-- DROP POLICY IF EXISTS superadmin_all_configuracion_identidad ON muevete.configuracion_identidad;
-- DROP POLICY IF EXISTS configuracion_identidad_select_auth ON muevete.configuracion_identidad;
-- DROP POLICY IF EXISTS superadmin_all_consentimientos ON muevete.consentimientos;
-- DROP POLICY IF EXISTS consentimientos_select_own ON muevete.consentimientos;
-- DROP POLICY IF EXISTS superadmin_all_documentos_legales ON muevete.documentos_legales;
-- DROP POLICY IF EXISTS documentos_legales_select_auth ON muevete.documentos_legales;
--
-- DROP TRIGGER IF EXISTS trg_users_identidad_guarda ON muevete.users;
-- DROP TRIGGER IF EXISTS trg_drivers_identidad_guarda ON muevete.drivers;
-- DROP FUNCTION IF EXISTS muevete.fn_identidad_guarda();
-- DROP TRIGGER IF EXISTS trg_configuracion_identidad_updated_at ON muevete.configuracion_identidad;
-- DROP TRIGGER IF EXISTS trg_documentos_legales_updated_at ON muevete.documentos_legales;
-- DROP TRIGGER IF EXISTS trg_documentos_legales_hash ON muevete.documentos_legales;
-- DROP FUNCTION IF EXISTS muevete.fn_doc_legal_hash();
--
-- DROP FUNCTION IF EXISTS muevete.fn_suspender_bloqueo_identidad(integer, text);
-- DROP FUNCTION IF EXISTS muevete.fn_kyc_revisar(text, uuid, text, text);
-- DROP FUNCTION IF EXISTS muevete.fn_guardar_identidad(text, jsonb);
-- DROP FUNCTION IF EXISTS muevete.fn_aceptar_consentimiento(text, text, text, text, text, jsonb);
-- DROP FUNCTION IF EXISTS muevete.fn_usuario_habilitado(uuid, text);
-- DROP FUNCTION IF EXISTS muevete.fn_ci_valido(text);
--
-- DROP TABLE IF EXISTS muevete.consentimientos;
-- DROP TABLE IF EXISTS muevete.documentos_legales;
-- DROP TABLE IF EXISTS muevete.configuracion_identidad;
--
-- DROP INDEX IF EXISTS muevete.drivers_kyc_estado_idx;
-- DROP INDEX IF EXISTS muevete.drivers_ci_idx;
-- ALTER TABLE muevete.drivers
--   DROP CONSTRAINT IF EXISTS drivers_ci_formato_chk,
--   DROP CONSTRAINT IF EXISTS drivers_kyc_estado_chk,
--   DROP COLUMN IF EXISTS kyc_revisado_at,
--   DROP COLUMN IF EXISTS kyc_revisado_por,
--   DROP COLUMN IF EXISTS kyc_estado,
--   DROP COLUMN IF EXISTS direccion,
--   DROP COLUMN IF EXISTS poblado,
--   DROP COLUMN IF EXISTS ci;
--
-- DROP INDEX IF EXISTS muevete.users_kyc_estado_idx;
-- DROP INDEX IF EXISTS muevete.users_ci_idx;
-- ALTER TABLE muevete.users
--   DROP CONSTRAINT IF EXISTS users_ci_formato_chk,
--   DROP CONSTRAINT IF EXISTS users_kyc_estado_chk,
--   DROP COLUMN IF EXISTS perfil_completado_at,
--   DROP COLUMN IF EXISTS kyc_revisado_at,
--   DROP COLUMN IF EXISTS kyc_revisado_por,
--   DROP COLUMN IF EXISTS kyc_motivo,
--   DROP COLUMN IF EXISTS kyc_estado,
--   DROP COLUMN IF EXISTS poblado;
-- -- NO se borran ci/direccion/docs de users: pueden preexistir y tener datos.
-- COMMIT;
-- ============================================================================