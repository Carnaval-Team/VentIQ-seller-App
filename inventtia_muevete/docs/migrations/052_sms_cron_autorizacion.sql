-- ============================================================================
-- 052_sms_cron_autorizacion.sql
-- Arregla la autorización del cron `muevete-send-sms` contra el worker
-- `send-sms`. El job corría cada minuto pero TODAS las invocaciones
-- devolvían 401 `no_autorizado`: la cola nunca se consumió.
--
-- DIAGNÓSTICO (producción vsieeihstajlrdvpuooh, 2026-11-14)
--   · cron.job_run_details  → el job 15 figura `succeeded` cada minuto.
--     ESO NO SIGNIFICA QUE FUNCIONE: pg_cron sólo confirma que `net.http_post`
--     se encoló. El resultado real está en `net._http_response`.
--   · net._http_response    → 52 respuestas 401 `{"ok":false,"error":
--     "no_autorizado"}` y 0 respuestas con `procesados`.
--   · muevete.sms_mensajes  → 6 filas `pendiente`, `intentos = 0`, la más
--     antigua desde las 10:48. Cero entregas.
--   · El cuerpo del 401 es el de la propia función (no el del gateway),
--     así que la petición SÍ llegaba al worker y fallaba `autorizado()`.
--
-- POR QUÉ FALLABA `autorizado()`
--   La función autoriza si se cumple UNA de dos condiciones:
--     (a) `x-sms-secret` == secreto de Edge Function `SMS_CRON_SECRET`
--     (b) `Authorization` == `Bearer <SUPABASE_SERVICE_ROLE_KEY>` del runtime
--   Ninguna se cumplía:
--     (a) `sms_cron_secret` existe en Vault, pero el secreto de Edge Function
--         `SMS_CRON_SECRET` no está definido (o tiene otro valor). Vault y
--         los secrets de Edge Functions son almacenes DISTINTOS.
--     (b) `wapi_service_role_key` en Vault no coincide byte a byte con el
--         `SUPABASE_SERVICE_ROLE_KEY` que inyecta el runtime (típico cuando el
--         proyecto migró a las claves nuevas `sb_secret_...` y Vault conserva
--         el JWT legacy, o cuando la clave se rotó).
--
--   Con `verify_jwt = true` en la función, además, el gateway exige un JWT
--   válido ANTES de ejecutar el worker. Por eso el arreglo recomendado es
--   el de la RUTA A: un único secreto compartido, sin service_role en el cron.
--
-- NO EJECUTAR CONTRA SUPABASE DESDE ESTE ENTORNO (sólo se entrega el archivo).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. Prerrequisitos
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE EXCEPTION 'falta la extensión pg_cron';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
    RAISE EXCEPTION 'falta la extensión pg_net';
  END IF;
  IF to_regclass('vault.decrypted_secrets') IS NULL THEN
    RAISE EXCEPTION 'falta Vault';
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 1. Quitar el job viejo (idempotente: no falla si ya no existe)
-- ----------------------------------------------------------------------------
SELECT cron.unschedule(jobid)
  FROM cron.job
 WHERE jobname = 'muevete-send-sms';

-- ============================================================================
-- RUTA A (RECOMENDADA) — un solo secreto compartido
-- ============================================================================
-- Requiere DOS pasos fuera de SQL, en este orden:
--
--   A1. Copiar el secreto de Vault a los secrets de Edge Functions:
--         supabase secrets set SMS_CRON_SECRET="<mismo valor de
--         vault.secrets.sms_cron_secret>" --project-ref vsieeihstajlrdvpuooh
--       (o panel → Project Settings → Edge Functions → Secrets)
--
--   A2. Redesplegar SIN verificación JWT, para que el gateway no exija el
--       JWT antes de llegar a `autorizado()`:
--         supabase functions deploy send-sms --no-verify-jwt \
--           --project-ref vsieeihstajlrdvpuooh
--
--   El worker ya valida su propio secreto, así que desactivar verify_jwt no
--   abre nada: sin `x-sms-secret` correcto sigue respondiendo 401.
--
-- Con A1 y A2 hechos, este es el cron definitivo:

SELECT cron.schedule('muevete-send-sms', '* * * * *', $job$
  SELECT net.http_post(
    url  := 'https://vsieeihstajlrdvpuooh.supabase.co/functions/v1/send-sms',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-sms-secret', (SELECT decrypted_secret
                         FROM vault.decrypted_secrets
                        WHERE name = 'sms_cron_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
$job$);

-- ============================================================================
-- RUTA B (alternativa) — mantener verify_jwt = true
-- ============================================================================
-- Sólo sirve si `wapi_service_role_key` en Vault es EXACTAMENTE la clave de
-- service_role vigente del proyecto. Si el proyecto usa claves nuevas
-- (`sb_secret_...`), el gateway no la acepta como JWT y hay que ir a la Ruta A.
--
--   SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'muevete-send-sms';
--
--   SELECT cron.schedule('muevete-send-sms', '* * * * *', $job$
--     SELECT net.http_post(
--       url := 'https://vsieeihstajlrdvpuooh.supabase.co/functions/v1/send-sms',
--       headers := jsonb_build_object(
--         'Content-Type', 'application/json',
--         'Authorization', 'Bearer ' || (SELECT decrypted_secret
--                                          FROM vault.decrypted_secrets
--                                         WHERE name = 'wapi_service_role_key'),
--         'apikey',        (SELECT decrypted_secret
--                             FROM vault.decrypted_secrets
--                            WHERE name = 'wapi_service_role_key')
--       ),
--       body := '{}'::jsonb,
--       timeout_milliseconds := 60000
--     );
--   $job$);

-- ============================================================================
-- VERIFICACIÓN (ejecutar a mano; NO forma parte de la migración)
-- ============================================================================
-- 1) ¿Existen los secretos en Vault y con qué formato?
--    (sólo largo y prefijo: no imprime el secreto)
--   SELECT name,
--          length(decrypted_secret) AS largo,
--          left(decrypted_secret, 12) AS prefijo,
--          CASE WHEN decrypted_secret LIKE 'eyJ%'        THEN 'jwt_legacy'
--               WHEN decrypted_secret LIKE 'sb_secret_%' THEN 'sb_secret'
--               ELSE 'texto' END AS formato
--     FROM vault.decrypted_secrets
--    ORDER BY name;
--
-- 2) ¿El job quedó bien programado y activo?
--   SELECT jobid, jobname, schedule, active FROM cron.job
--    WHERE jobname = 'muevete-send-sms';
--
-- 3) Pasado 1-2 minutos: ¿qué respondió realmente el gateway?
--    (esto es lo que hay que mirar, no el `succeeded` de cron)
--   SELECT status_code, left(content, 200) AS cuerpo, created, error_msg
--     FROM net._http_response
--    ORDER BY created DESC
--    LIMIT 5;
--   -- esperado: 200 y cuerpo con {"ok":true,"procesados":N,...}
--
-- 4) Prueba de extremo a extremo:
--   SELECT muevete.fn_sms_encolar('+5354590207',
--                                 'Prueba Muévete', 'aviso', 'muevete');
--   -- esperar ~1 minuto y revisar:
--   SELECT id, estado, intentos, proveedor, proveedor_msg_id,
--          left(ultimo_error, 120) AS error, enviado_at
--     FROM muevete.sms_mensajes
--    ORDER BY id DESC
--    LIMIT 5;
--   -- esperado: estado 'enviado' (o 'entregado') con enviado_at no nulo.
--
-- 5) Si quedan en 'error' con `whatsapp_sin_sesion`:
--      falta el secreto WAPI_SESSION_ID en Edge Functions. El worker lee
--      `configuracion_sms.whatsapp_session_id`, pero la versión desplegada
--      NO lo asignaba (bug corregido en index.ts); la sesión actual es
--      3f394210-aa7e-4279-a330-b5639d3024e7 y está CONNECTED.
--      Opción sin redesplegar:
--        supabase secrets set WAPI_SESSION_ID=3f394210-aa7e-4279-a330-b5639d3024e7 \
--          --project-ref vsieeihstajlrdvpuooh
--      También hacen falta WAPI_BASE_URL y WAPI_API_KEY del gateway OpenWA.

-- ============================================================================
-- ROLLBACK
-- ============================================================================
-- SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'muevete-send-sms';
-- ============================================================================