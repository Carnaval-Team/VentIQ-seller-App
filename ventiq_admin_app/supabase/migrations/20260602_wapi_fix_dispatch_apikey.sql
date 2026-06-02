-- ============================================================================
--  WAPI Notifications — Añadir header apikey al dispatcher
--  Fecha: 2026-06-02
--  Descripción:
--    Algunas configuraciones del Edge Functions gateway de Supabase
--    requieren tanto Authorization como apikey. Esta migración:
--      1. Añade el header `apikey` (mismo valor que el Bearer) a la llamada
--         que hace fn_wapi_dispatch_diario.
--      2. Refactor: extrae también el envío al force_dispatch para que use
--         los mismos headers.
--
--    Por qué el bug:
--      Sin apikey, el gateway puede responder 401 antes de invocar tu
--      función. El cuerpo de error termina viéndose como un 401 genérico
--      aunque el JWT sea válido.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_wapi_dispatch_diario()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault
AS $$
DECLARE
  v_url   text;
  v_token text;
  r       record;
BEGIN
  SELECT decrypted_secret INTO v_url
    FROM vault.decrypted_secrets
    WHERE name = 'wapi_supabase_url';

  SELECT decrypted_secret INTO v_token
    FROM vault.decrypted_secrets
    WHERE name = 'wapi_service_role_key';

  IF v_url IS NULL OR v_token IS NULL THEN
    RAISE NOTICE 'WAPI dispatch saltado: faltan secretos en Vault';
    RETURN;
  END IF;

  v_url := rtrim(v_url, '/') || '/functions/v1/wapi-cron-dispatch';

  FOR r IN
    SELECT id
      FROM public.app_wapi_programacion
     WHERE activa = true
       AND next_run_at IS NOT NULL
       AND next_run_at <= now()
     FOR UPDATE SKIP LOCKED
  LOOP
    PERFORM net.http_post(
      url     := v_url,
      headers := jsonb_build_object(
                   'Authorization', 'Bearer ' || v_token,
                   'apikey',        v_token,           -- ← NUEVO
                   'Content-Type',  'application/json'
                 ),
      body    := jsonb_build_object('id_programacion', r.id)
    );

    UPDATE public.app_wapi_programacion
       SET last_run_at = now()
     WHERE id = r.id;
  END LOOP;
END $$;

-- También actualizar fn_wapi_force_dispatch con apikey
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
  SELECT id_tienda INTO v_id_tienda
    FROM public.app_wapi_programacion
   WHERE id = p_id_programacion;

  IF v_id_tienda IS NULL THEN
    RAISE EXCEPTION 'Programación % no existe', p_id_programacion;
  END IF;

  IF NOT public.fn_user_can_access_tienda(v_id_tienda) THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  SELECT decrypted_secret INTO v_url
    FROM vault.decrypted_secrets WHERE name = 'wapi_supabase_url';

  SELECT decrypted_secret INTO v_token
    FROM vault.decrypted_secrets WHERE name = 'wapi_service_role_key';

  IF v_url IS NULL OR v_token IS NULL THEN
    RAISE EXCEPTION 'Faltan secretos en Vault';
  END IF;

  v_url := rtrim(v_url, '/') || '/functions/v1/wapi-cron-dispatch';

  SELECT net.http_post(
    url     := v_url,
    headers := jsonb_build_object(
                 'Authorization', 'Bearer ' || v_token,
                 'apikey',        v_token,           -- ← NUEVO
                 'Content-Type',  'application/json'
               ),
    body    := jsonb_build_object('id_programacion', p_id_programacion)
  ) INTO v_request_id;

  RETURN jsonb_build_object(
    'success',         true,
    'request_id',      v_request_id,
    'url',             v_url,
    'id_programacion', p_id_programacion,
    'note',            'Llamada disparada con apikey. Revisa fn_wapi_dispatch_debug.'
  );
END $$;
