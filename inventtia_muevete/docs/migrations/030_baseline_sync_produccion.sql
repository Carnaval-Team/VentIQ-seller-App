-- ============================================================================
-- 030_baseline_sync_produccion.sql
--
-- PROPÓSITO
--   Sincronizar el repositorio con los objetos que EXISTEN en la base de datos
--   de producción (`vsieeihstajlrdvpuooh`, esquema `muevete`) pero que no
--   estaban versionados en ningún `.sql` del repo.
--
-- CÓMO SE OBTUVO
--   Inventario real por SQL el 2026-11-12:
--     - pg_proc / pg_namespace      → 13 funciones en `muevete`
--     - pg_trigger                  → 4 triggers no internos
--     - pg_views                    → 2 vistas (ya versionadas en 015 y 022)
--     - pg_policies                 → 118 políticas
--   Comparado contra `inventtia_muevete/docs/migrations/*.sql`.
--
-- DELTA ENCONTRADO (lo que este archivo añade al repo)
--   1. muevete.get_my_driver_id()            → no existía en el repo
--   2. complete_ride_payment (5 args, legacy) → el repo solo versiona la de 6
--   3. triggers de push (pg_net): notificaciones_push, solicitudes_push,
--      ofertas_push                           → solo documentados en notifi-readme.md
--
-- ORDEN
--   Ejecutar DESPUÉS de 001..029 (depende de tablas y de la función de 6 args).
--   Es idempotente: en producción no cambia nada salvo que falte un objeto.
--
-- NOTA DE SEGURIDAD
--   En producción los triggers de push tienen el `service_role` JWT EMBEBIDO en
--   el texto del trigger (visible en pg_trigger para cualquiera con acceso a
--   catálogo). Aquí se reconstruyen leyendo el secreto desde Vault
--   (`wapi_service_role_key` / `wapi_supabase_url`, que ya existen en el
--   proyecto). Ver docs/plan-taxi-precio-fijo/05-sincronizacion-bd-repo.md.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. get_my_driver_id() → id del chofer del usuario autenticado
--    Usada por el flujo de chofer; SECURITY DEFINER para saltar RLS de drivers.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.get_my_driver_id()
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'muevete'
AS $function$
  SELECT id FROM muevete.drivers WHERE uuid = auth.uid() LIMIT 1;
$function$;

REVOKE ALL ON FUNCTION muevete.get_my_driver_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION muevete.get_my_driver_id() TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. complete_ride_payment: sobrecarga legacy de 5 argumentos
--    Producción la tiene además de la de 6. Se conserva por compatibilidad con
--    llamadas antiguas, delegando en la de 6 con p_precio_base = p_precio_final
--    (delta de espera = 0 ⇒ comportamiento idéntico al original de 5 args).
--
--    DEPRECADA: el flujo de precio fijo cerrará por muevete.fn_completar_viaje.
--    No borrar hasta que no existan clientes con la versión antigua.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.complete_ride_payment(
  p_metodo_pago text,
  p_client_uuid uuid,
  p_driver_id   bigint,
  p_viaje_id    bigint,
  p_precio_final numeric
)
RETURNS json
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'muevete'
AS $function$
  SELECT muevete.complete_ride_payment(
    p_metodo_pago, p_client_uuid, p_driver_id, p_viaje_id, p_precio_final, p_precio_final
  );
$function$;

REVOKE ALL ON FUNCTION muevete.complete_ride_payment(text, uuid, bigint, bigint, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION muevete.complete_ride_payment(text, uuid, bigint, bigint, numeric)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Triggers de push vía pg_net → Edge Function `send-push-notification`
--
--    Se crean SOLO si no existen (en producción ya están: no se tocan).
--    La URL y el token salen de Vault; si faltan, se avisa y no se crea nada.
--    El cuerpo usa el template de webhooks de Supabase para el registro nuevo.
-- ---------------------------------------------------------------------------
DO $do$
DECLARE
  v_url  text;
  v_key  text;
  v_hdr  text;
  v_tpl  text;
BEGIN
  SELECT decrypted_secret INTO v_url
    FROM vault.decrypted_secrets WHERE name = 'wapi_supabase_url';
  SELECT decrypted_secret INTO v_key
    FROM vault.decrypted_secrets WHERE name = 'wapi_service_role_key';

  IF v_url IS NULL OR v_key IS NULL THEN
    RAISE NOTICE 'Vault sin wapi_supabase_url / wapi_service_role_key: se omiten los triggers de push.';
    RETURN;
  END IF;

  v_url := rtrim(v_url, '/') || '/functions/v1/send-push-notification';
  v_hdr := json_build_object(
             'Content-type', 'application/json',
             'Authorization', 'Bearer ' || v_key
           )::text;

  -- notificaciones_push
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'muevete' AND c.relname = 'notificaciones' AND t.tgname = 'notificaciones_push'
  ) THEN
    v_tpl := '{"type":"INSERT","table":"notificaciones","record":"{ ...new_row... }"}';
    EXECUTE format(
      'CREATE TRIGGER notificaciones_push AFTER INSERT ON muevete.notificaciones
       FOR EACH ROW EXECUTE FUNCTION supabase_functions.http_request(%L, %L, %L::jsonb, %L::jsonb, %L)',
      v_url, 'POST', v_hdr, v_tpl, '5000'
    );
    RAISE NOTICE 'Creado trigger notificaciones_push';
  END IF;

  -- solicitudes_push
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'muevete' AND c.relname = 'solicitudes_transporte' AND t.tgname = 'solicitudes_push'
  ) THEN
    v_tpl := '{"type":"INSERT","table":"solicitudes_transporte","record":"{ ...new_row... }"}';
    EXECUTE format(
      'CREATE TRIGGER solicitudes_push AFTER INSERT ON muevete.solicitudes_transporte
       FOR EACH ROW EXECUTE FUNCTION supabase_functions.http_request(%L, %L, %L::jsonb, %L::jsonb, %L)',
      v_url, 'POST', v_hdr, v_tpl, '5000'
    );
    RAISE NOTICE 'Creado trigger solicitudes_push';
  END IF;

  -- ofertas_push  (DEPRECADO con el flujo de precio fijo: se deja por compatibilidad)
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'muevete' AND c.relname = 'ofertas_chofer' AND t.tgname = 'ofertas_push'
  ) THEN
    v_tpl := '{"type":"INSERT","table":"ofertas_chofer","record":"{ ...new_row ...}"}';
    EXECUTE format(
      'CREATE TRIGGER ofertas_push AFTER INSERT ON muevete.ofertas_chofer
       FOR EACH ROW EXECUTE FUNCTION supabase_functions.http_request(%L, %L, %L::jsonb, %L::jsonb, %L)',
      v_url, 'POST', v_hdr, v_tpl, '5000'
    );
    RAISE NOTICE 'Creado trigger ofertas_push';
  END IF;
END
$do$;

-- ---------------------------------------------------------------------------
-- 4. Duplicados en `public` (deuda, NO se recrean)
--    Producción tiene además public.complete_ride_payment en sus dos
--    sobrecargas. Son copias legacy de cuando el esquema no estaba separado.
--    No se tocan en esta migración. Se eliminarán cuando se confirme que
--    ninguna app ni función las invoca:
--
--      DROP FUNCTION IF EXISTS public.complete_ride_payment(text, uuid, bigint, bigint, numeric);
--      DROP FUNCTION IF EXISTS public.complete_ride_payment(text, uuid, bigint, bigint, numeric, numeric);
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 5. Vistas: v_cargas_estado_actual (015) y v_cargas_con_nomencladores (022)
--    ya están versionadas en el repo. No se tocan.
--
-- 6. is_superadmin() (006) y set_updated_at() (002) ya están versionadas.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- VERIFICACIÓN (pegar en el SQL editor tras aplicar)
-- ---------------------------------------------------------------------------
-- Esperado: 13 funciones en `muevete` (14 filas por la sobrecarga de 5 args).
--
--   SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args
--   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname = 'muevete' ORDER BY 1, 2;
--
-- Esperado: 4 triggers no internos.
--
--   SELECT c.relname, t.tgname
--   FROM pg_trigger t
--   JOIN pg_class c ON c.oid = t.tgrelid
--   JOIN pg_namespace n ON n.oid = c.relnamespace
--   WHERE n.nspname = 'muevete' AND NOT t.tgisinternal ORDER BY 1, 2;
-- ---------------------------------------------------------------------------