-- ============================================================================
--  WAPI Notifications — Fix dispatcher para Supabase Cloud (sin superuser)
--  Fecha: 2026-05-27
--  Contexto:
--    En Supabase Cloud, el rol `postgres` ya no es superuser desde 2024,
--    así que `ALTER DATABASE postgres SET app.xxx = ...` (la idea original
--    en 20260525_wapi_notifications.sql) falla con "permission denied".
--
--    Esta migración:
--      1. Guarda la URL del proyecto y la service_role key en Supabase Vault
--         (bóveda cifrada, accesible solo vía SECURITY DEFINER).
--      2. Reemplaza `fn_wapi_dispatch_diario()` para leer los secretos
--         desde Vault en lugar de los GUC.
--      3. (Opcional) Re-registra el job de pg_cron por idempotencia.
--
--    Es seguro re-ejecutar: usa upsert en Vault y CREATE OR REPLACE en la
--    función.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. Extensiones requeridas
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS supabase_vault;
CREATE EXTENSION IF NOT EXISTS pg_net;
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ---------------------------------------------------------------------------
-- 1. Guardar / actualizar secretos en Vault
--    `vault.create_secret` falla si el `name` ya existe, así que primero
--    intentamos UPDATE y, si no existe, INSERT-creamos.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_url   constant text := 'https://vsieeihstajlrdvpuooh.supabase.co';
  v_token constant text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZzaWVlaWhzdGFqbHJkdnB1b29oIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1NDUzMjIwNiwiZXhwIjoyMDcwMTA4MjA2fQ.d9fKCcunP_J0tdlZF8eg0vAD-bsK3XfemavnZWT3Ro8';
  v_id    uuid;
BEGIN
  -- ----- wapi_supabase_url -----
  SELECT id INTO v_id FROM vault.secrets WHERE name = 'wapi_supabase_url';
  IF v_id IS NULL THEN
    PERFORM vault.create_secret(
      v_url,
      'wapi_supabase_url',
      'URL base del proyecto Supabase usada por fn_wapi_dispatch_diario'
    );
  ELSE
    PERFORM vault.update_secret(
      v_id,
      v_url,
      'wapi_supabase_url',
      'URL base del proyecto Supabase usada por fn_wapi_dispatch_diario'
    );
  END IF;

  -- ----- wapi_service_role_key -----
  SELECT id INTO v_id FROM vault.secrets WHERE name = 'wapi_service_role_key';
  IF v_id IS NULL THEN
    PERFORM vault.create_secret(
      v_token,
      'wapi_service_role_key',
      'Service role key usada por fn_wapi_dispatch_diario para llamar a la edge function'
    );
  ELSE
    PERFORM vault.update_secret(
      v_id,
      v_token,
      'wapi_service_role_key',
      'Service role key usada por fn_wapi_dispatch_diario para llamar a la edge function'
    );
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 2. Reemplazar la función dispatcher para que lea desde Vault
-- ---------------------------------------------------------------------------
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
    RAISE NOTICE 'WAPI dispatch saltado: faltan secretos wapi_supabase_url / wapi_service_role_key en Vault';
    RETURN;
  END IF;

  -- URL completa de la edge function (tolerante a trailing slash)
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
                   'Content-Type',  'application/json'
                 ),
      body    := jsonb_build_object('id_programacion', r.id)
    );

    -- Marcar last_run_at; el trigger recalcula next_run_at +1 día
    UPDATE public.app_wapi_programacion
       SET last_run_at = now()
     WHERE id = r.id;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- 3. Asegurar que el cron job sigue registrado (idempotente)
--    La migración anterior ya lo crea; este bloque solo cubre entornos
--    donde se haya borrado manualmente.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'wapi_dispatch_diario') THEN
    PERFORM cron.schedule(
      'wapi_dispatch_diario',
      '* * * * *',
      $cron$SELECT public.fn_wapi_dispatch_diario()$cron$
    );
  END IF;
END $$;

-- ============================================================================
-- 4. Verificación manual (NO se ejecuta automáticamente — copiar/pegar a mano
--    después de aplicar la migración)
-- ============================================================================
--
--   -- a) Confirmar que los secretos están en Vault
--   SELECT name, created_at, updated_at
--     FROM vault.secrets
--    WHERE name IN ('wapi_supabase_url', 'wapi_service_role_key');
--
--   -- b) Disparar el dispatcher manualmente (sin esperar al cron)
--   SELECT public.fn_wapi_dispatch_diario();
--
--   -- c) ¿Se actualizó last_run_at y next_run_at avanzó?
--   SELECT id, activa, hora_envio, next_run_at, last_run_at
--     FROM public.app_wapi_programacion
--    ORDER BY id DESC;
--
--   -- d) ¿pg_net hizo la llamada HTTP?
--   SELECT id, status_code, LEFT(content::text, 300) AS content, created
--     FROM net._http_response
--    ORDER BY created DESC
--    LIMIT 10;
--
--   -- e) ¿Se generaron filas en el log de envío?
--   SELECT id, chat_id, tipo_envio, estado, error_message, sent_at, created_at
--     FROM public.app_wapi_envio_log
--    ORDER BY created_at DESC
--    LIMIT 20;
--
-- ============================================================================
-- FIN — WAPI dispatcher Vault migration
-- ============================================================================
