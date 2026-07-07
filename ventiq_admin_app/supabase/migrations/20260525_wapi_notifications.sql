-- ============================================================================
--  WAPI Notifications — Difusión WhatsApp para tiendas Pro/Avanzado
--  Fecha: 2026-05-25
--  Descripción:
--    Tablas + RLS + pg_cron + Edge Function dispatcher para envíos
--    manuales y programados de productos a WhatsApp vía la API WAPI
--    (OpenWA) hospedada externamente. Las llamadas HTTP a la API
--    se hacen exclusivamente desde Edge Functions (X-API-Key oculta).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. Extensiones requeridas
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pg_net;
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ---------------------------------------------------------------------------
-- 1. app_wapi_sesion -- bots / sesiones WhatsApp
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_wapi_sesion (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_tienda       bigint NOT NULL REFERENCES public.app_dat_tienda(id) ON DELETE CASCADE,
  nombre          text   NOT NULL,
  wapi_session_id text   NOT NULL UNIQUE,
  status          text   NOT NULL DEFAULT 'INITIALIZING'
                  CHECK (status IN ('INITIALIZING','SCAN_QR','CONNECTING',
                                    'CONNECTED','DISCONNECTED','FAILED')),
  phone_number    text,
  last_qr_image   text,
  last_status_at  timestamptz NOT NULL DEFAULT now(),
  created_by      uuid   NOT NULL REFERENCES auth.users(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_wapi_sesion_tienda ON public.app_wapi_sesion(id_tienda);
CREATE INDEX IF NOT EXISTS idx_wapi_sesion_status ON public.app_wapi_sesion(status);

COMMENT ON TABLE  public.app_wapi_sesion              IS 'Sesiones/bots de WhatsApp asociados a una tienda';
COMMENT ON COLUMN public.app_wapi_sesion.wapi_session_id IS 'ID devuelto por la API WAPI externa (sess_xxx)';
COMMENT ON COLUMN public.app_wapi_sesion.last_qr_image   IS 'Último QR (data URI base64) recibido. Útil para reconexión.';

-- ---------------------------------------------------------------------------
-- 2. app_wapi_destinatario -- contactos/grupos guardados para reuso
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_wapi_destinatario (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_tienda  bigint NOT NULL REFERENCES public.app_dat_tienda(id) ON DELETE CASCADE,
  id_sesion  bigint REFERENCES public.app_wapi_sesion(id) ON DELETE SET NULL,
  tipo       text   NOT NULL CHECK (tipo IN ('numero','grupo')),
  chat_id    text   NOT NULL,
  etiqueta   text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id_tienda, chat_id)
);
CREATE INDEX IF NOT EXISTS idx_wapi_dest_tienda ON public.app_wapi_destinatario(id_tienda);

COMMENT ON TABLE  public.app_wapi_destinatario IS 'Destinatarios guardados (números o grupos) por tienda';
COMMENT ON COLUMN public.app_wapi_destinatario.chat_id IS 'Formato WAPI: 52155...@c.us (número) o xxx-yyy@g.us (grupo)';

-- ---------------------------------------------------------------------------
-- 3. app_wapi_programacion -- envío automático diario (Plan Avanzado)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_wapi_programacion (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_tienda         bigint NOT NULL REFERENCES public.app_dat_tienda(id) ON DELETE CASCADE,
  id_sesion         bigint NOT NULL REFERENCES public.app_wapi_sesion(id) ON DELETE CASCADE,
  nombre            text   NOT NULL DEFAULT 'Difusión diaria',
  hora_envio        time   NOT NULL,
  timezone          text   NOT NULL DEFAULT 'America/Mexico_City',
  activa            boolean NOT NULL DEFAULT true,
  -- Anti-ban: jitter entre mensajes (segundos)
  delay_min_seconds int    NOT NULL DEFAULT 30  CHECK (delay_min_seconds >= 10),
  delay_max_seconds int    NOT NULL DEFAULT 90  CHECK (delay_max_seconds >= delay_min_seconds),
  last_run_at       timestamptz,
  next_run_at       timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_wapi_prog_next
  ON public.app_wapi_programacion(next_run_at)
  WHERE activa = true;
CREATE INDEX IF NOT EXISTS idx_wapi_prog_tienda
  ON public.app_wapi_programacion(id_tienda);

COMMENT ON TABLE public.app_wapi_programacion IS 'Programaciones diarias de difusión automática (Plan Avanzado)';

-- ---------------------------------------------------------------------------
-- 4. Tablas de unión N:N
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_wapi_programacion_producto (
  id_programacion bigint NOT NULL REFERENCES public.app_wapi_programacion(id) ON DELETE CASCADE,
  id_producto     bigint NOT NULL REFERENCES public.app_dat_producto(id)     ON DELETE CASCADE,
  orden           int    NOT NULL DEFAULT 0,
  PRIMARY KEY (id_programacion, id_producto)
);

CREATE TABLE IF NOT EXISTS public.app_wapi_programacion_destinatario (
  id_programacion bigint NOT NULL REFERENCES public.app_wapi_programacion(id)  ON DELETE CASCADE,
  id_destinatario bigint NOT NULL REFERENCES public.app_wapi_destinatario(id)  ON DELETE CASCADE,
  PRIMARY KEY (id_programacion, id_destinatario)
);

-- ---------------------------------------------------------------------------
-- 5. app_wapi_envio_log -- bitácora unificada (manual + programado)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_wapi_envio_log (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_tienda       bigint NOT NULL REFERENCES public.app_dat_tienda(id) ON DELETE CASCADE,
  id_sesion       bigint REFERENCES public.app_wapi_sesion(id) ON DELETE SET NULL,
  id_programacion bigint REFERENCES public.app_wapi_programacion(id) ON DELETE SET NULL,
  id_producto     bigint REFERENCES public.app_dat_producto(id) ON DELETE SET NULL,
  chat_id         text   NOT NULL,
  tipo_envio      text   NOT NULL CHECK (tipo_envio IN ('manual','programado')),
  estado          text   NOT NULL CHECK (estado IN ('pendiente','enviado','fallido')),
  mensaje_id      text,
  error_code      text,
  error_message   text,
  sent_at         timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_wapi_log_tienda_fecha
  ON public.app_wapi_envio_log(id_tienda, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_wapi_log_sesion
  ON public.app_wapi_envio_log(id_sesion);

COMMENT ON TABLE public.app_wapi_envio_log IS 'Bitácora de cada mensaje enviado (un row por producto x destinatario)';

-- ============================================================================
-- 6. RLS (Row Level Security)
--    Acceso permitido solo al gerente o supervisor de la tienda
-- ============================================================================

ALTER TABLE public.app_wapi_sesion                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_wapi_destinatario              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_wapi_programacion              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_wapi_programacion_producto     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_wapi_programacion_destinatario ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_wapi_envio_log                 ENABLE ROW LEVEL SECURITY;

-- Helper: ¿El usuario actual tiene acceso a la tienda?
CREATE OR REPLACE FUNCTION public.fn_user_can_access_tienda(p_id_tienda bigint)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.app_dat_gerente
    WHERE id_tienda = p_id_tienda AND uuid = auth.uid()
  ) OR EXISTS (
    SELECT 1 FROM public.app_dat_supervisor
    WHERE id_tienda = p_id_tienda AND uuid = auth.uid()
  );
$$;

-- app_wapi_sesion
DROP POLICY IF EXISTS wapi_sesion_access ON public.app_wapi_sesion;
CREATE POLICY wapi_sesion_access ON public.app_wapi_sesion
  USING      (public.fn_user_can_access_tienda(id_tienda))
  WITH CHECK (public.fn_user_can_access_tienda(id_tienda));

-- app_wapi_destinatario
DROP POLICY IF EXISTS wapi_destinatario_access ON public.app_wapi_destinatario;
CREATE POLICY wapi_destinatario_access ON public.app_wapi_destinatario
  USING      (public.fn_user_can_access_tienda(id_tienda))
  WITH CHECK (public.fn_user_can_access_tienda(id_tienda));

-- app_wapi_programacion
DROP POLICY IF EXISTS wapi_programacion_access ON public.app_wapi_programacion;
CREATE POLICY wapi_programacion_access ON public.app_wapi_programacion
  USING      (public.fn_user_can_access_tienda(id_tienda))
  WITH CHECK (public.fn_user_can_access_tienda(id_tienda));

-- Tablas de unión: validan vía la programación padre
DROP POLICY IF EXISTS wapi_prog_prod_access ON public.app_wapi_programacion_producto;
CREATE POLICY wapi_prog_prod_access ON public.app_wapi_programacion_producto
  USING (EXISTS (
    SELECT 1 FROM public.app_wapi_programacion p
    WHERE p.id = id_programacion
      AND public.fn_user_can_access_tienda(p.id_tienda)
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.app_wapi_programacion p
    WHERE p.id = id_programacion
      AND public.fn_user_can_access_tienda(p.id_tienda)
  ));

DROP POLICY IF EXISTS wapi_prog_dest_access ON public.app_wapi_programacion_destinatario;
CREATE POLICY wapi_prog_dest_access ON public.app_wapi_programacion_destinatario
  USING (EXISTS (
    SELECT 1 FROM public.app_wapi_programacion p
    WHERE p.id = id_programacion
      AND public.fn_user_can_access_tienda(p.id_tienda)
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.app_wapi_programacion p
    WHERE p.id = id_programacion
      AND public.fn_user_can_access_tienda(p.id_tienda)
  ));

-- app_wapi_envio_log: lectura por tienda; inserts solo desde service role
DROP POLICY IF EXISTS wapi_log_select ON public.app_wapi_envio_log;
CREATE POLICY wapi_log_select ON public.app_wapi_envio_log
  FOR SELECT USING (public.fn_user_can_access_tienda(id_tienda));

-- ============================================================================
-- 7. Triggers
-- ============================================================================

-- 7.1 updated_at automático en sesion y programacion
CREATE OR REPLACE FUNCTION public.fn_wapi_set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_wapi_sesion_updated_at ON public.app_wapi_sesion;
CREATE TRIGGER trg_wapi_sesion_updated_at
  BEFORE UPDATE ON public.app_wapi_sesion
  FOR EACH ROW EXECUTE FUNCTION public.fn_wapi_set_updated_at();

-- 7.2 Recalcular next_run_at cuando se inserta/edita la programación
CREATE OR REPLACE FUNCTION public.fn_wapi_recalc_next_run()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_today_local timestamp;
  v_next_local  timestamp;
BEGIN
  IF NEW.activa THEN
    v_today_local := (now() AT TIME ZONE NEW.timezone)::date;
    v_next_local  := v_today_local + NEW.hora_envio;
    NEW.next_run_at := v_next_local AT TIME ZONE NEW.timezone;
    -- Si ya pasó hoy, mover a mañana
    IF NEW.next_run_at <= now() THEN
      NEW.next_run_at := NEW.next_run_at + interval '1 day';
    END IF;
  ELSE
    NEW.next_run_at := NULL;
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_wapi_prog_recalc ON public.app_wapi_programacion;
CREATE TRIGGER trg_wapi_prog_recalc
  BEFORE INSERT OR UPDATE OF hora_envio, activa, timezone, last_run_at
  ON public.app_wapi_programacion
  FOR EACH ROW EXECUTE FUNCTION public.fn_wapi_recalc_next_run();

-- ============================================================================
-- 8. Dispatcher pg_cron: cada minuto dispara HTTP a la Edge Function
-- ============================================================================
--   Antes de habilitar pg_cron en producción, ejecutar UNA VEZ:
--     ALTER DATABASE postgres SET app.supabase_url     = 'https://<proj>.supabase.co';
--     ALTER DATABASE postgres SET app.service_role_key = '<service_role_key>';
--
--   En entornos donde aún no se han configurado los GUC, la función falla
--   silenciosamente sin afectar inserts en la tabla.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_wapi_dispatch_diario()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_url   text;
  v_token text;
  r       record;
BEGIN
  BEGIN
    v_url   := current_setting('app.supabase_url')     || '/functions/v1/wapi-cron-dispatch';
    v_token := current_setting('app.service_role_key');
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'WAPI dispatch saltado: GUCs app.supabase_url/app.service_role_key no configurados';
    RETURN;
  END;

  FOR r IN
    SELECT id FROM public.app_wapi_programacion
    WHERE activa = true AND next_run_at IS NOT NULL AND next_run_at <= now()
    FOR UPDATE SKIP LOCKED
  LOOP
    PERFORM net.http_post(
      url     := v_url,
      headers := jsonb_build_object(
                   'Authorization','Bearer ' || v_token,
                   'Content-Type','application/json'),
      body    := jsonb_build_object('id_programacion', r.id)
    );
    -- Marcar last_run_at; el trigger recalculará next_run_at +1 día
    UPDATE public.app_wapi_programacion
       SET last_run_at = now()
     WHERE id = r.id;
  END LOOP;
END $$;

-- Programar cron cada minuto (idempotente)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'wapi_dispatch_diario') THEN
    PERFORM cron.schedule('wapi_dispatch_diario', '* * * * *',
                          $cron$SELECT public.fn_wapi_dispatch_diario()$cron$);
  END IF;
END $$;

-- ============================================================================
-- 9. RPC helper: lectura compacta del estado del módulo para una tienda
--    (usada por el Flutter para evitar múltiples round trips)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_wapi_get_dashboard(p_id_tienda bigint)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT public.fn_user_can_access_tienda(p_id_tienda) THEN
    RAISE EXCEPTION 'No autorizado para la tienda %', p_id_tienda;
  END IF;

  SELECT jsonb_build_object(
    'sesiones', COALESCE((
      SELECT jsonb_agg(to_jsonb(s) ORDER BY s.created_at DESC)
      FROM public.app_wapi_sesion s
      WHERE s.id_tienda = p_id_tienda
    ), '[]'::jsonb),
    'programacion', (
      SELECT to_jsonb(p)
      FROM public.app_wapi_programacion p
      WHERE p.id_tienda = p_id_tienda
      ORDER BY p.created_at DESC
      LIMIT 1
    ),
    'logs_recientes', COALESCE((
      SELECT jsonb_agg(to_jsonb(l))
      FROM (
        SELECT * FROM public.app_wapi_envio_log
        WHERE id_tienda = p_id_tienda
        ORDER BY created_at DESC
        LIMIT 10
      ) l
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END $$;

GRANT EXECUTE ON FUNCTION public.fn_wapi_get_dashboard(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_user_can_access_tienda(bigint) TO authenticated;

-- ============================================================================
-- FIN — WAPI Notifications migration
-- ============================================================================
