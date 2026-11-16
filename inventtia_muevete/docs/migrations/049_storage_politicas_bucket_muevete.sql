-- ============================================================================
-- 049_storage_politicas_bucket_muevete.sql
-- Políticas de Storage para el bucket `muevete` (documentos del KYC).
--
-- SÍNTOMA (producción, 2026-11-14)
--   Al subir la foto del carnet con un usuario ya registrado:
--       POST /object/muevete/docs/<uuid>/ci_frente.jpg  →  400 AccessDenied
--   Storage devuelve:
--       {"statusCode":"403","error":"Unauthorized",
--        "message":"new row violates row-level security policy",
--        "code":"AccessDenied"}
--   Y al abrir el objeto directamente (`GET /object/muevete/...`) también 403.
--
-- CAUSA
--   La app sube con `upsert: true` y **nombre de archivo fijo**
--   (`docs/{uuid}/ci_frente.jpg`). Cuando el objeto ya existe (reintento, cambio
--   de foto o subida previa), Storage ejecuta `INSERT ... ON CONFLICT DO UPDATE`
--   (`UpsertObjectProbe`) y ese camino exige una política **UPDATE** sobre
--   `storage.objects`. Además, leer el objeto por la API exige **SELECT**.
--
--   En producción el bucket `muevete` sólo tenía:
--       · INSERT genérica  `Storage: allow authenticated insert to own or public
--                          bucket`  (with_check = true)
--       · DELETE genérica
--   **No había UPDATE ni SELECT**, así que:
--       · el upsert de una foto existente fallaba con 42501 (RLS), y
--       · el GET autenticado del objeto también.
--   En el proyecto de PRUEBAS funcionaba porque allí están las políticas
--   `give all to all` (INSERT/SELECT/UPDATE/DELETE con `true`).
--
-- QUÉ HACE
--   Tres políticas permisivas acotadas al bucket `muevete` (no a todo Storage):
--       · INSERT → subir documentos
--       · UPDATE → reemplazarlos (ESTO es lo que arregla el fallo)
--       · SELECT → leerlos por la API
--
-- POR QUÉ NO SE RESTRINGE A `docs/{auth.uid()}/`
--   El registro (`register_screen.dart`) sube los documentos **antes** de tener
--   la cuenta definitiva, con una carpeta temporal (`_tempUuid =
--   DateTime.now().millisecondsSinceEpoch`). Si se exigiera `auth.uid()` en la
--   ruta, se rompería el registro. Se acota por BUCKET, que es el permiso que
--   falta, y se deja anotada la mejora futura.
--
-- MEJORA FUTURA (cuando el registro suba a `docs/{auth.uid()}/…`)
--   Cambiar los `WITH CHECK`/`USING` por:
--       bucket_id = 'muevete'
--       AND (storage.foldername(name))[1] = 'docs'
--       AND (storage.foldername(name))[2] = auth.uid()::text
--
-- NOTA DE SEGURIDAD (aparte)
--   La política genérica `Storage: allow authenticated insert to own or public
--   bucket` (with_check = true, roles anon/authenticated/service_role) deja que
--   cualquier usuario —o anónimo— escriba en CUALQUIER bucket. No se elimina en
--   esta migración para no romper otras apps; conviene sustituirla por políticas
--   por bucket más adelante.
--
-- IDEMPOTENCIA
--   DROP POLICY IF EXISTS + CREATE POLICY.
--
-- NO EJECUTAR CONTRA SUPABASE DESDE ESTE ENTORNO (sólo se entrega el archivo).
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 0. Prerrequisitos
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('storage.objects') IS NULL THEN
    RAISE EXCEPTION 'no existe storage.objects';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'muevete') THEN
    RAISE EXCEPTION 'no existe el bucket muevete';
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 1. Políticas del bucket `muevete`
--    Se incluye `anon` porque el registro puede subir documentos antes del
--    inicio de sesión (es el mismo criterio de la política genérica actual).
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS muevete_objects_insert ON storage.objects;
CREATE POLICY muevete_objects_insert ON storage.objects
  FOR INSERT TO anon, authenticated, service_role
  WITH CHECK (bucket_id = 'muevete');

-- ESTA es la que faltaba: permite reemplazar una foto ya subida (upsert).
DROP POLICY IF EXISTS muevete_objects_update ON storage.objects;
CREATE POLICY muevete_objects_update ON storage.objects
  FOR UPDATE TO anon, authenticated, service_role
  USING (bucket_id = 'muevete')
  WITH CHECK (bucket_id = 'muevete');

-- Lectura por la API (`GET /object/muevete/...`). La URL pública
-- (`/object/public/muevete/...`) ya funcionaba por ser bucket público.
DROP POLICY IF EXISTS muevete_objects_select ON storage.objects;
CREATE POLICY muevete_objects_select ON storage.objects
  FOR SELECT TO anon, authenticated, service_role
  USING (bucket_id = 'muevete');

COMMIT;

-- ============================================================================
-- VERIFICACIÓN (ejecutar a mano; NO forma parte de la migración)
-- ============================================================================
-- 1) Políticas del bucket:
--   SELECT policyname, cmd, permissive, roles::text
--     FROM pg_policies
--    WHERE schemaname='storage' AND tablename='objects'
--      AND policyname LIKE 'muevete_objects_%'
--    ORDER BY cmd;
--   -- esperado: INSERT, SELECT, UPDATE (PERMISSIVE, {anon,authenticated,service_role})
--
-- 2) Prueba definitiva: desde la app, subir la foto del carnet **dos veces
--    seguidas**. La segunda es la que antes fallaba (upsert).
--    En Storage → Logs debe verse `POST | 200` y nunca otro `400`.
--
-- 3) El objeto quedó:
--   SELECT name, bucket_id, owner_id, metadata->>'mimetype' AS mime,
--          (metadata->>'size')::int AS bytes, created_at, updated_at
--     FROM storage.objects
--    WHERE bucket_id='muevete' AND name LIKE 'docs/%'
--    ORDER BY updated_at DESC LIMIT 10;
--
-- 4) La URL pública abre en el navegador (bucket público):
--   https://<proyecto>.supabase.co/storage/v1/object/public/muevete/docs/<uuid>/ci_frente.jpg
--
-- ============================================================================
-- ROLLBACK
-- ============================================================================
-- DROP POLICY IF EXISTS muevete_objects_insert ON storage.objects;
-- DROP POLICY IF EXISTS muevete_objects_update ON storage.objects;
-- DROP POLICY IF EXISTS muevete_objects_select ON storage.objects;
-- ============================================================================