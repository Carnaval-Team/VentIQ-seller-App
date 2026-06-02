-- ============================================================================
--  WAPI Notifications — Inspección rápida del JWT en Vault
--  Fecha: 2026-06-02
--  Descripción:
--    Función helper para confirmar que el JWT guardado en Vault como
--    `wapi_service_role_key` es el que esperamos. Devuelve metadatos del
--    token (alg, ref del proyecto, role, iat, exp) SIN exponer la clave
--    completa — sólo el prefijo y sufijo para comparar visualmente con
--    el dashboard de Supabase.
--
--    Razonamiento: cuando el cron-dispatch devuelve 401 "No autenticado"
--    pero los demás campos del debug están OK, casi siempre es porque la
--    clave en Vault no es la actual del proyecto. Esta función lo aclara
--    en 1 query.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_wapi_inspect_vault_token()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault
AS $$
DECLARE
  v_token       text;
  v_url         text;
  v_parts       text[];
  v_payload     jsonb;
BEGIN
  SELECT decrypted_secret INTO v_url
    FROM vault.decrypted_secrets WHERE name = 'wapi_supabase_url';

  SELECT decrypted_secret INTO v_token
    FROM vault.decrypted_secrets WHERE name = 'wapi_service_role_key';

  IF v_token IS NULL THEN
    RETURN jsonb_build_object('error', 'wapi_service_role_key no existe en Vault');
  END IF;

  -- Un JWT tiene 3 partes separadas por punto: header.payload.signature
  v_parts := string_to_array(v_token, '.');
  IF array_length(v_parts, 1) <> 3 THEN
    RETURN jsonb_build_object(
      'error',     'El secreto no parece ser un JWT (no tiene 3 partes)',
      'preview',   left(v_token, 20) || '…' || right(v_token, 10),
      'length',    length(v_token)
    );
  END IF;

  -- Decodificar el payload (base64url). PostgreSQL no soporta base64url
  -- nativo, pero los JWT de Supabase tienen padding compatible con
  -- base64 estándar (rellenamos con '=' si hace falta).
  BEGIN
    v_payload := convert_from(
      decode(
        v_parts[2] ||
          repeat('=', (4 - (length(v_parts[2]) % 4)) % 4),
        'base64'
      ),
      'UTF8'
    )::jsonb;
  EXCEPTION WHEN OTHERS THEN
    v_payload := jsonb_build_object('decode_error', SQLERRM);
  END;

  RETURN jsonb_build_object(
    'vault_url',         v_url,
    'token_length',      length(v_token),
    'token_prefix',      left(v_token, 25),
    'token_suffix',      right(v_token, 15),
    'payload',           v_payload,
    'hint',              'Compara token_prefix y token_suffix con la service_role key del Dashboard. Si difieren, la migración _update_service_key no se aplicó o se pegó la clave equivocada.'
  );
END $$;

GRANT EXECUTE ON FUNCTION public.fn_wapi_inspect_vault_token() TO authenticated;

-- Uso:
--   SELECT jsonb_pretty(public.fn_wapi_inspect_vault_token());
--
-- Lo que debes ver en "payload":
--   {
--     "iss": "supabase",
--     "ref": "vsieeihstajlrdvpuooh",   <-- TU project ref
--     "role": "service_role",          <-- DEBE ser service_role, no anon
--     "iat": ...,
--     "exp": ...
--   }
--
-- Si "role" dice "anon" → pegaste la anon key en lugar de la service_role.
-- Si "ref" no coincide con tu proyecto → la clave es de otro proyecto.
-- Si exp < now → el JWT expiró.
