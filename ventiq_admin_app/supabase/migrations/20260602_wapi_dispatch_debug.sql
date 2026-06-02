-- ============================================================================
--  WAPI Notifications — Herramientas de diagnóstico para envío automático
--  Fecha: 2026-06-02
--  Descripción:
--    Añade dos funciones para que desde el UI Flutter (o desde la consola SQL)
--    podamos:
--      1. fn_wapi_dispatch_debug(p_id_tienda) — devuelve estado consolidado
--         de la programación, vault secrets, cron job, last http response.
--      2. fn_wapi_force_dispatch(p_id_programacion) — fuerza un disparo
--         INMEDIATO de una programación específica (ignora next_run_at)
--         simulando lo que haría el cron. Requiere ser gerente/supervisor de
--         la tienda dueña de la programación. Devuelve el http response_id
--         que pg_net asignó para poder rastrearlo.
--
--    Diseño: ambas son SECURITY DEFINER + chequean acceso vía
--    fn_user_can_access_tienda. NO exponen el service_role key — se leen
--    desde Vault internamente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. fn_wapi_dispatch_debug — estado consolidado para troubleshooting
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_wapi_dispatch_debug(p_id_tienda bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault, cron, net
AS $$
DECLARE
  v_result        jsonb;
  v_vault_url     boolean;
  v_vault_token   boolean;
  v_cron_job      jsonb;
  v_prog          jsonb;
  v_last_http     jsonb;
  v_cron_runs     jsonb;
BEGIN
  IF NOT public.fn_user_can_access_tienda(p_id_tienda) THEN
    RAISE EXCEPTION 'No autorizado para la tienda %', p_id_tienda;
  END IF;

  -- 1) ¿Existen los secretos en Vault?
  SELECT EXISTS (SELECT 1 FROM vault.secrets WHERE name = 'wapi_supabase_url')
    INTO v_vault_url;
  SELECT EXISTS (SELECT 1 FROM vault.secrets WHERE name = 'wapi_service_role_key')
    INTO v_vault_token;

  -- 2) ¿El cron job está registrado?
  SELECT to_jsonb(j) INTO v_cron_job
    FROM cron.job j
   WHERE j.jobname = 'wapi_dispatch_diario';

  -- 3) Programación actual (la última creada para esta tienda)
  SELECT jsonb_build_object(
           'id',            p.id,
           'activa',        p.activa,
           'hora_envio',    p.hora_envio,
           'timezone',      p.timezone,
           'next_run_at',   p.next_run_at,
           'last_run_at',   p.last_run_at,
           'next_run_at_local', (p.next_run_at AT TIME ZONE p.timezone),
           'now_db_utc',    now(),
           'now_local',     (now() AT TIME ZONE p.timezone),
           'overdue',       (p.next_run_at IS NOT NULL AND p.next_run_at <= now()),
           'sesion_id',     p.id_sesion,
           'sesion_status', s.status,
           'productos',     (SELECT count(*) FROM public.app_wapi_programacion_producto
                              WHERE id_programacion = p.id),
           'destinatarios', (SELECT count(*) FROM public.app_wapi_programacion_destinatario
                              WHERE id_programacion = p.id)
         )
    INTO v_prog
    FROM public.app_wapi_programacion p
    LEFT JOIN public.app_wapi_sesion s ON s.id = p.id_sesion
   WHERE p.id_tienda = p_id_tienda
   ORDER BY p.created_at DESC
   LIMIT 1;

  -- 4) Últimas 5 respuestas HTTP de pg_net (qué dijo la edge function)
  --    Sólo accesible si el usuario es service_role, así que envolvemos en try.
  BEGIN
    SELECT jsonb_agg(jsonb_build_object(
             'id',          r.id,
             'status_code', r.status_code,
             'content',     LEFT(coalesce(r.content::text, ''), 500),
             'error_msg',   r.error_msg,
             'created',     r.created
           ) ORDER BY r.created DESC)
      INTO v_last_http
      FROM (
        SELECT * FROM net._http_response
        ORDER BY created DESC
        LIMIT 5
      ) r;
  EXCEPTION WHEN OTHERS THEN
    v_last_http := jsonb_build_array(jsonb_build_object(
      'error', 'No se pudo leer net._http_response: ' || SQLERRM
    ));
  END;

  -- 5) Últimas 5 corridas del cron job
  BEGIN
    SELECT jsonb_agg(jsonb_build_object(
             'runid',     d.runid,
             'job_pid',   d.job_pid,
             'database',  d.database,
             'status',    d.status,
             'return_message', LEFT(coalesce(d.return_message, ''), 300),
             'start_time',  d.start_time,
             'end_time',    d.end_time
           ) ORDER BY d.start_time DESC)
      INTO v_cron_runs
      FROM (
        SELECT d.* FROM cron.job_run_details d
        JOIN cron.job j ON j.jobid = d.jobid
        WHERE j.jobname = 'wapi_dispatch_diario'
        ORDER BY d.start_time DESC
        LIMIT 5
      ) d;
  EXCEPTION WHEN OTHERS THEN
    v_cron_runs := jsonb_build_array(jsonb_build_object(
      'error', 'No se pudo leer cron.job_run_details: ' || SQLERRM
    ));
  END;

  v_result := jsonb_build_object(
    'vault_url_present',     v_vault_url,
    'vault_token_present',   v_vault_token,
    'cron_job',              v_cron_job,
    'programacion',          v_prog,
    'last_http_responses',   coalesce(v_last_http, '[]'::jsonb),
    'last_cron_runs',        coalesce(v_cron_runs, '[]'::jsonb),
    'db_now',                now()
  );

  RETURN v_result;
END $$;

GRANT EXECUTE ON FUNCTION public.fn_wapi_dispatch_debug(bigint) TO authenticated;

-- ---------------------------------------------------------------------------
-- 2. fn_wapi_force_dispatch — fuerza un envío programado AHORA
--    Útil para debug: si funciona, el problema es de timing/cron;
--    si falla, el problema es de la edge function o del bot.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_wapi_force_dispatch(p_id_programacion bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault, net
AS $$
DECLARE
  v_url        text;
  v_token      text;
  v_id_tienda  bigint;
  v_request_id bigint;
BEGIN
  -- Validar acceso del caller a la tienda dueña de la programación
  SELECT id_tienda INTO v_id_tienda
    FROM public.app_wapi_programacion
   WHERE id = p_id_programacion;

  IF v_id_tienda IS NULL THEN
    RAISE EXCEPTION 'Programación % no existe', p_id_programacion;
  END IF;

  IF NOT public.fn_user_can_access_tienda(v_id_tienda) THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  -- Leer secretos
  SELECT decrypted_secret INTO v_url
    FROM vault.decrypted_secrets
   WHERE name = 'wapi_supabase_url';

  SELECT decrypted_secret INTO v_token
    FROM vault.decrypted_secrets
   WHERE name = 'wapi_service_role_key';

  IF v_url IS NULL OR v_token IS NULL THEN
    RAISE EXCEPTION 'Faltan secretos en Vault: wapi_supabase_url / wapi_service_role_key';
  END IF;

  v_url := rtrim(v_url, '/') || '/functions/v1/wapi-cron-dispatch';

  -- Disparar HTTP (asíncrono via pg_net). El response_id se puede mirar luego
  -- en net._http_response para ver qué dijo la edge.
  SELECT net.http_post(
    url     := v_url,
    headers := jsonb_build_object(
                 'Authorization', 'Bearer ' || v_token,
                 'Content-Type',  'application/json'
               ),
    body    := jsonb_build_object('id_programacion', p_id_programacion)
  ) INTO v_request_id;

  RETURN jsonb_build_object(
    'success',     true,
    'request_id',  v_request_id,
    'url',         v_url,
    'id_programacion', p_id_programacion,
    'note',        'Llamada disparada. Revisa fn_wapi_dispatch_debug para ver la respuesta.'
  );
END $$;

GRANT EXECUTE ON FUNCTION public.fn_wapi_force_dispatch(bigint) TO authenticated;

-- ============================================================================
-- Verificación manual (copiar/pegar en SQL Editor de Supabase):
-- ============================================================================
--
--   -- a) Ver estado completo
--   SELECT jsonb_pretty(public.fn_wapi_dispatch_debug(<id_tienda>));
--
--   -- b) Forzar un envío inmediato
--   SELECT public.fn_wapi_force_dispatch(<id_programacion>);
--
--   -- c) Esperar 5-10 segundos y volver a ver el estado
--   SELECT jsonb_pretty(public.fn_wapi_dispatch_debug(<id_tienda>));
--
-- ============================================================================
