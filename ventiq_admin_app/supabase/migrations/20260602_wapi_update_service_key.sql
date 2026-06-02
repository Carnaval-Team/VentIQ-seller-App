-- ============================================================================
--  WAPI Notifications — Actualizar service_role key en Vault
--  Fecha: 2026-06-02
--  Contexto:
--    El cron job `wapi_dispatch_diario` está corriendo cada minuto y
--    enviando HTTP POST a `/functions/v1/wapi-cron-dispatch`, pero las
--    respuestas devuelven 401 "No autenticado". Esto pasa cuando:
--      a) El service_role key guardado en Vault fue rotado en el dashboard
--         de Supabase y nadie actualizó Vault.
--      b) El JWT corresponde a otro proyecto.
--
--    Esta migración actualiza el secreto `wapi_service_role_key` con la
--    clave NUEVA. Antes de aplicar, sustituye <<PASTE_NEW_SERVICE_ROLE_KEY>>
--    por la clave actual que aparece en:
--      Supabase Dashboard → Project Settings → API → service_role secret
-- ============================================================================

DO $$
DECLARE
  v_token constant text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZzaWVlaWhzdGFqbHJkdnB1b29oIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1NDUzMjIwNiwiZXhwIjoyMDcwMTA4MjA2fQ.d9fKCcunP_J0tdlZF8eg0vAD-bsK3XfemavnZWT3Ro8';
  v_id    uuid;
BEGIN
  IF v_token = '<<PASTE_NEW_SERVICE_ROLE_KEY>>' THEN
    RAISE EXCEPTION 'Reemplaza <<PASTE_NEW_SERVICE_ROLE_KEY>> con la service_role key real antes de ejecutar.';
  END IF;

  SELECT id INTO v_id FROM vault.secrets WHERE name = 'wapi_service_role_key';
  IF v_id IS NULL THEN
    PERFORM vault.create_secret(
      v_token,
      'wapi_service_role_key',
      'Service role key (actualizada 2026-06-02)'
    );
  ELSE
    PERFORM vault.update_secret(
      v_id,
      v_token,
      'wapi_service_role_key',
      'Service role key (actualizada 2026-06-02)'
    );
  END IF;
END $$;

-- Verificación rápida:
--   SELECT name, updated_at FROM vault.secrets
--    WHERE name IN ('wapi_supabase_url','wapi_service_role_key');
--
-- Luego dispara manualmente y mira el HTTP response:
--   SELECT public.fn_wapi_force_dispatch(7);  -- ajusta id_programacion
--   -- espera ~5s
--   SELECT id, status_code, LEFT(content::text, 200)
--     FROM net._http_response
--    ORDER BY created DESC LIMIT 3;
