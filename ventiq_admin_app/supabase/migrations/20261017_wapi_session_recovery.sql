-- ============================================================================
--  WAPI — Recuperación automática de sesiones (watchdog) + diagnóstico
--  Fecha: 2026-10-17
--
--  QUÉ AÑADE
--    1. Columnas de estado/recuperación en `app_wapi_sesion`:
--         raw_status         · el status CRUDO que reporta OpenWA
--                              ("action_required", "qr_ready", "failed"...).
--                              Sin esto es imposible diagnosticar después por
--                              qué se cayó: sólo guardábamos el normalizado.
--         last_recovery_at   · cuándo se intentó recuperar por última vez.
--         recovery_attempts  · intentos acumulados (cooldown / anti-bucle).
--         last_error_code    · último error relevante.
--         last_error_message · su detalle.
--         watchdog_enabled   · si el watchdog puede recuperar esta sesión.
--                              Se apaga con un `stop` intencionado.
--    2. `fn_wapi_session_watchdog()` — dispara la Edge Function
--       `wapi-session-health` con service_role (lee los secretos de Vault,
--       igual que fn_wapi_dispatch_diario).
--    3. Job de pg_cron `wapi_session_watchdog` cada 5 minutos.
--    4. `fn_wapi_session_recovery_report(p_id_tienda)` — snapshot legible
--       desde el SQL Editor o la app.
--
--  POR QUÉ
--    OpenWA pierde la sesión de forma aleatoria (OOM de Chromium, bucle de
--    reconexión, modal "What's new" no confirmado). Hasta ahora NADA del lado
--    de Supabase lo detectaba: la columna `status` sólo se refrescaba cuando el
--    usuario abría la app, y las difusiones seguían enviando contra una sesión
--    muerta hasta llenar el historial (4.995 filas `fallido`, 565 `pendiente`).
--    El watchdog convierte ese "hay que reiniciar la sesión" manual en un
--    reintento automático: stop → start, o force-kill → start si está FAILED.
--
--  SEGURIDAD DEL WATCHDOG
--    · Sólo toca sesiones con `watchdog_enabled = true`.
--    · NO toca sesiones sin vincular que están esperando QR (reiniciarlas
--      invalidaría el QR que el usuario va a escanear).
--    · Cooldown de 10 minutos y 3 intentos por ventana, para no martillear.
--    · Se puede desactivar el job: SELECT cron.unschedule('wapi_session_watchdog');
--
--  NOTA: el código de las Edge Functions está escrito para funcionar ANTES y
--  DESPUÉS de aplicar esta migración (si las columnas no existen, degrada y
--  sigue guardando el estado base). Aun así, aplícala cuanto antes.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Columnas de recuperación
-- ---------------------------------------------------------------------------
ALTER TABLE public.app_wapi_sesion
  ADD COLUMN IF NOT EXISTS raw_status          text,
  ADD COLUMN IF NOT EXISTS last_recovery_at    timestamptz,
  ADD COLUMN IF NOT EXISTS recovery_attempts   int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_error_code     text,
  ADD COLUMN IF NOT EXISTS last_error_message  text,
  ADD COLUMN IF NOT EXISTS watchdog_enabled    boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN public.app_wapi_sesion.raw_status IS
  'Status crudo reportado por OpenWA (ready|qr_ready|disconnected|action_required|failed|...)';
COMMENT ON COLUMN public.app_wapi_sesion.recovery_attempts IS
  'Recuperaciones intentadas en la ventana actual; el watchdog lo resetea cuando la sesión vuelve a CONNECTED';
COMMENT ON COLUMN public.app_wapi_sesion.watchdog_enabled IS
  'Si wapi-session-health puede recuperar esta sesión. Se pone en false con un stop intencionado';

-- Busca rápido las sesiones que el watchdog debe mirar.
CREATE INDEX IF NOT EXISTS idx_wapi_sesion_watchdog
  ON public.app_wapi_sesion(id)
  WHERE watchdog_enabled = true;

-- ---------------------------------------------------------------------------
-- 2. Disparador del watchdog (pg_cron → Edge Function)
--    Reusa los secretos de Vault que ya usa fn_wapi_dispatch_diario.
--    El advisory lock evita solapar dos corridas si una tarda más de 5 min.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_wapi_session_watchdog()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault
AS $$
DECLARE
  v_url    text;
  v_token  text;
  v_lock   boolean;
BEGIN
  -- Anti-solape: si la corrida anterior sigue viva, esta se descarta.
  v_lock := pg_try_advisory_lock(hashtext('wapi_session_watchdog'));
  IF NOT v_lock THEN
    RAISE NOTICE 'WAPI watchdog: corrida anterior aún en curso, se salta esta';
    RETURN;
  END IF;

  BEGIN
    SELECT decrypted_secret INTO v_url
      FROM vault.decrypted_secrets
     WHERE name = 'wapi_supabase_url';

    SELECT decrypted_secret INTO v_token
      FROM vault.decrypted_secrets
     WHERE name = 'wapi_service_role_key';

    IF v_url IS NULL OR v_token IS NULL THEN
      RAISE NOTICE 'WAPI watchdog saltado: faltan secretos wapi_supabase_url / wapi_service_role_key en Vault';
      PERFORM pg_advisory_unlock(hashtext('wapi_session_watchdog'));
      RETURN;
    END IF;

    -- Sólo se dispara si hay algo que mirar: una sesión con watchdog activo.
    IF NOT EXISTS (
      SELECT 1 FROM public.app_wapi_sesion WHERE watchdog_enabled = true
    ) THEN
      PERFORM pg_advisory_unlock(hashtext('wapi_session_watchdog'));
      RETURN;
    END IF;

    v_url := rtrim(v_url, '/') || '/functions/v1/wapi-session-health';

    PERFORM net.http_post(
      url     := v_url,
      headers := jsonb_build_object(
                   'Authorization', 'Bearer ' || v_token,
                   'apikey',        v_token,
                   'Content-Type',  'application/json'
                 ),
      -- dry_run=false, force=false: la política la decide la Edge Function.
      body    := jsonb_build_object('dry_run', false)
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'WAPI watchdog: error disparando la Edge Function: %', SQLERRM;
  END;

  PERFORM pg_advisory_unlock(hashtext('wapi_session_watchdog'));
END $$;

COMMENT ON FUNCTION public.fn_wapi_session_watchdog() IS
  'Cada 5 min dispara wapi-session-health para detectar y recuperar sesiones OpenWA caídas.';

REVOKE ALL ON FUNCTION public.fn_wapi_session_watchdog() FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Job de pg_cron (idempotente)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'wapi_session_watchdog') THEN
    PERFORM cron.schedule(
      'wapi_session_watchdog',
      '*/5 * * * *',
      $cron$SELECT public.fn_wapi_session_watchdog()$cron$
    );
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 4. Reporte de diagnóstico (para el SQL Editor o la app)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_wapi_session_recovery_report(
  p_id_tienda bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, cron
AS $$
DECLARE
  v_result jsonb;
BEGIN
  -- Con una tienda concreta se exige acceso; sin argumento es una herramienta
  -- de operador (se concede sólo a service_role).
  IF p_id_tienda IS NOT NULL AND NOT public.fn_user_can_access_tienda(p_id_tienda) THEN
    RAISE EXCEPTION 'No autorizado para la tienda %', p_id_tienda;
  END IF;

  SELECT jsonb_build_object(
    'sesiones', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'id', s.id,
               'id_tienda', s.id_tienda,
               'nombre', s.nombre,
               'wapi_session_id', s.wapi_session_id,
               'status', s.status,
               'raw_status', s.raw_status,
               'phone_number', s.phone_number,
               'last_status_at', s.last_status_at,
               'minutos_sin_status', round(extract(epoch FROM (now() - s.last_status_at)) / 60),
               'last_recovery_at', s.last_recovery_at,
               'recovery_attempts', s.recovery_attempts,
               'watchdog_enabled', s.watchdog_enabled,
               'last_error_code', s.last_error_code,
               'last_error_message', s.last_error_message,
               'programaciones_activas', (
                 SELECT count(*) FROM public.app_wapi_programacion p
                  WHERE p.id_sesion = s.id AND p.activa = true
               )
             ) ORDER BY s.id)
        FROM public.app_wapi_sesion s
       WHERE p_id_tienda IS NULL OR s.id_tienda = p_id_tienda
    ), '[]'::jsonb),
    'cron_watchdog', (
      SELECT jsonb_build_object(
               'schedule', j.schedule,
               'active', j.active,
               'ultima_corrida', (
                 SELECT max(d.start_time) FROM cron.job_run_details d
                  WHERE d.jobid = j.jobid
               ),
               'ultimo_estado', (
                 SELECT d.status FROM cron.job_run_details d
                  WHERE d.jobid = j.jobid
                  ORDER BY d.start_time DESC LIMIT 1
               )
             )
        FROM cron.job j WHERE j.jobname = 'wapi_session_watchdog'
    ),
    'db_now', now()
  ) INTO v_result;

  RETURN v_result;
END $$;

COMMENT ON FUNCTION public.fn_wapi_session_recovery_report(bigint) IS
  'Estado de recuperación de las sesiones WAPI y del job watchdog. p_id_tienda NULL = todas (sólo service_role).';

REVOKE ALL ON FUNCTION public.fn_wapi_session_recovery_report(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_wapi_session_recovery_report(bigint) TO authenticated, service_role;

-- ============================================================================
--  VERIFICACIÓN (copiar/pegar)
-- ============================================================================
--   -- a) ¿Están las columnas?
--   SELECT column_name, data_type FROM information_schema.columns
--    WHERE table_name = 'app_wapi_sesion' ORDER BY ordinal_position;
--
--   -- b) Estado de las sesiones + watchdog
--   SELECT jsonb_pretty(public.fn_wapi_session_recovery_report());
--
--   -- c) Disparar el watchdog a mano (no esperar al cron)
--   SELECT public.fn_wapi_session_watchdog();
--   -- y mirar qué dijo (5-15 s después):
--   SELECT status_code, LEFT(content::text, 500), error_msg, created
--     FROM net._http_response ORDER BY created DESC LIMIT 5;
--
--   -- d) Dry-run desde la Edge Function (no toca nada). Ojo: `net.http_post`
--   --    es asíncrono, así que hay que mirar net._http_response.
--   --    Más cómodo: llamar la función desde la app o con curl + service_role.
--
--   -- e) Frenar el watchdog para una sesión concreta (parada intencionada)
--   UPDATE public.app_wapi_sesion SET watchdog_enabled = false WHERE id = 22;
--
--   -- f) Desactivar el job del todo
--   SELECT cron.unschedule('wapi_session_watchdog');
--
-- ============================================================================
-- FIN — WAPI recuperación de sesiones
-- ============================================================================