-- ============================================================================
-- Home banners — gestión desde Superadmin (carnavalAPP)
-- ============================================================================
-- Crea la tabla de banners del carrusel de inicio y las RPCs usadas por:
--   • App cliente: fn_home_banners_list (solo activos)
--   • Superadmin: fn_admin_home_banners_list, fn_admin_home_banners_upsert,
--                 fn_admin_home_banners_delete
--
-- No se permite acceso directo a la tabla; todo pasa por RPCs SECURITY DEFINER.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Tabla
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS carnavalapp.home_banners (
  id           BIGSERIAL PRIMARY KEY,
  image_url    TEXT NOT NULL,
  link         TEXT,
  descripcion  TEXT,
  orden        INTEGER NOT NULL DEFAULT 0,
  activo       BOOLEAN NOT NULL DEFAULT TRUE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE carnavalapp.home_banners IS
  'Banners del carrusel del inicio de la app Carnaval';
COMMENT ON COLUMN carnavalapp.home_banners.image_url IS
  'URL pública de la imagen del banner (recomendado 16:7, ~1200x525)';
COMMENT ON COLUMN carnavalapp.home_banners.link IS
  'Ruta interna (p.ej. /search?categoryId=14) o URL externa https://…';
COMMENT ON COLUMN carnavalapp.home_banners.orden IS
  'Orden de aparición en el carrusel; menor valor = primero';
COMMENT ON COLUMN carnavalapp.home_banners.activo IS
  'false oculta el banner en la app cliente';

CREATE INDEX IF NOT EXISTS idx_home_banners_activo_orden
  ON carnavalapp.home_banners (activo, orden, id);

-- ----------------------------------------------------------------------------
-- 2) RLS: bloquear acceso directo; todo via RPCs SECURITY DEFINER
-- ----------------------------------------------------------------------------
ALTER TABLE carnavalapp.home_banners ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'carnavalapp'
      AND tablename  = 'home_banners'
      AND policyname = 'deny_all_direct_access'
  ) THEN
    CREATE POLICY deny_all_direct_access ON carnavalapp.home_banners
      FOR ALL TO authenticated, anon
      USING (false);
  END IF;
END
$$;

-- ----------------------------------------------------------------------------
-- 3) Funciones para la app cliente
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION carnavalapp.fn_home_banners_list()
RETURNS SETOF carnavalapp.home_banners
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = carnavalapp, public, pg_temp
AS $$
  SELECT *
  FROM carnavalapp.home_banners
  WHERE activo = TRUE
  ORDER BY orden ASC, id ASC;
$$;

-- ----------------------------------------------------------------------------
-- 4) Funciones para el superadmin
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION carnavalapp.fn_admin_home_banners_list()
RETURNS SETOF carnavalapp.home_banners
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = carnavalapp, public, pg_temp
AS $$
  SELECT *
  FROM carnavalapp.home_banners
  ORDER BY orden ASC, id ASC;
$$;

CREATE OR REPLACE FUNCTION carnavalapp.fn_admin_home_banners_upsert(
  p_id            BIGINT   DEFAULT NULL,
  p_image_url     TEXT     DEFAULT NULL,
  p_link          TEXT     DEFAULT NULL,
  p_descripcion   TEXT     DEFAULT NULL,
  p_orden         INTEGER  DEFAULT 0,
  p_activo        BOOLEAN  DEFAULT TRUE
)
RETURNS carnavalapp.home_banners
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = carnavalapp, public, pg_temp
AS $$
DECLARE
  v_row carnavalapp.home_banners;
BEGIN
  IF p_id IS NULL THEN
    INSERT INTO carnavalapp.home_banners (
      image_url, link, descripcion, orden, activo, created_at, updated_at
    ) VALUES (
      p_image_url, p_link, p_descripcion, COALESCE(p_orden, 0), COALESCE(p_activo, TRUE), NOW(), NOW()
    )
    RETURNING * INTO v_row;
  ELSE
    UPDATE carnavalapp.home_banners
    SET
      image_url   = COALESCE(p_image_url, image_url),
      link        = COALESCE(p_link, link),
      descripcion = COALESCE(p_descripcion, descripcion),
      orden       = COALESCE(p_orden, orden),
      activo      = COALESCE(p_activo, activo),
      updated_at  = NOW()
    WHERE id = p_id
    RETURNING * INTO v_row;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Banner no encontrado: %', p_id;
    END IF;
  END IF;

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION carnavalapp.fn_admin_home_banners_delete(
  p_id    BIGINT,
  p_hard  BOOLEAN DEFAULT FALSE
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = carnavalapp, public, pg_temp
AS $$
BEGIN
  IF p_hard THEN
    DELETE FROM carnavalapp.home_banners WHERE id = p_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Banner no encontrado: %', p_id;
    END IF;
  ELSE
    UPDATE carnavalapp.home_banners
    SET activo = FALSE, updated_at = NOW()
    WHERE id = p_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Banner no encontrado: %', p_id;
    END IF;
  END IF;

  RETURN TRUE;
END;
$$;

-- ----------------------------------------------------------------------------
-- 5) Permisos de ejecución
-- ----------------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION carnavalapp.fn_home_banners_list() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION carnavalapp.fn_admin_home_banners_list() TO authenticated;
GRANT EXECUTE ON FUNCTION carnavalapp.fn_admin_home_banners_upsert(BIGINT, TEXT, TEXT, TEXT, INTEGER, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION carnavalapp.fn_admin_home_banners_delete(BIGINT, BOOLEAN) TO authenticated;

-- Secuencia para posibles necesidades de carga/importación directa
GRANT USAGE, SELECT ON SEQUENCE carnavalapp.home_banners_id_seq TO authenticated;

-- ----------------------------------------------------------------------------
-- 6) Storage: políticas para subir/actualizar/borrar imágenes en imagenes/banners/
-- ----------------------------------------------------------------------------
-- El bucket 'imagenes' ya existe y es público. Estas policies permiten que
-- un superadmin activo gestione objetos dentro de imagenes/banners/.
-- La lectura pública ya funciona porque el bucket es público; no hace falta
-- policy de SELECT para las URLs públicas.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename  = 'buckets'
      AND policyname = 'home_banners_buckets_select_public'
  ) THEN
    CREATE POLICY home_banners_buckets_select_public
      ON storage.buckets FOR SELECT
      TO public
      USING (public = true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename  = 'objects'
      AND policyname = 'home_banners_objects_insert_superadmin'
  ) THEN
    CREATE POLICY home_banners_objects_insert_superadmin
      ON storage.objects FOR INSERT
      TO authenticated
      WITH CHECK (
        bucket_id = 'imagenes'
        AND name LIKE 'banners/%'
        AND EXISTS (
          SELECT 1 FROM public.app_dat_superadmin
          WHERE uuid = auth.uid() AND activo = true
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename  = 'objects'
      AND policyname = 'home_banners_objects_update_superadmin'
  ) THEN
    CREATE POLICY home_banners_objects_update_superadmin
      ON storage.objects FOR UPDATE
      TO authenticated
      USING (
        bucket_id = 'imagenes'
        AND name LIKE 'banners/%'
        AND EXISTS (
          SELECT 1 FROM public.app_dat_superadmin
          WHERE uuid = auth.uid() AND activo = true
        )
      )
      WITH CHECK (
        bucket_id = 'imagenes'
        AND name LIKE 'banners/%'
        AND EXISTS (
          SELECT 1 FROM public.app_dat_superadmin
          WHERE uuid = auth.uid() AND activo = true
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename  = 'objects'
      AND policyname = 'home_banners_objects_delete_superadmin'
  ) THEN
    CREATE POLICY home_banners_objects_delete_superadmin
      ON storage.objects FOR DELETE
      TO authenticated
      USING (
        bucket_id = 'imagenes'
        AND name LIKE 'banners/%'
        AND EXISTS (
          SELECT 1 FROM public.app_dat_superadmin
          WHERE uuid = auth.uid() AND activo = true
        )
      );
  END IF;
END
$$;

-- ----------------------------------------------------------------------------
-- 7) Storage: políticas para subidas multipart en imagenes/banners/
-- ----------------------------------------------------------------------------
-- Archivos grandes usan s3_multipart_uploads / s3_multipart_uploads_parts.
-- Sin estas policies el upload cae en 403 aunque storage.objects esté OK.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename  = 's3_multipart_uploads'
      AND policyname = 'home_banners_multipart_uploads_insert_superadmin'
  ) THEN
    CREATE POLICY home_banners_multipart_uploads_insert_superadmin
      ON storage.s3_multipart_uploads FOR INSERT
      TO authenticated
      WITH CHECK (
        bucket_id = 'imagenes'
        AND key LIKE 'banners/%'
        AND EXISTS (
          SELECT 1 FROM public.app_dat_superadmin
          WHERE uuid = auth.uid() AND activo = true
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename  = 's3_multipart_uploads'
      AND policyname = 'home_banners_multipart_uploads_select_superadmin'
  ) THEN
    CREATE POLICY home_banners_multipart_uploads_select_superadmin
      ON storage.s3_multipart_uploads FOR SELECT
      TO authenticated
      USING (
        bucket_id = 'imagenes'
        AND key LIKE 'banners/%'
        AND EXISTS (
          SELECT 1 FROM public.app_dat_superadmin
          WHERE uuid = auth.uid() AND activo = true
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename  = 's3_multipart_uploads'
      AND policyname = 'home_banners_multipart_uploads_update_superadmin'
  ) THEN
    CREATE POLICY home_banners_multipart_uploads_update_superadmin
      ON storage.s3_multipart_uploads FOR UPDATE
      TO authenticated
      USING (
        bucket_id = 'imagenes'
        AND key LIKE 'banners/%'
        AND EXISTS (
          SELECT 1 FROM public.app_dat_superadmin
          WHERE uuid = auth.uid() AND activo = true
        )
      )
      WITH CHECK (
        bucket_id = 'imagenes'
        AND key LIKE 'banners/%'
        AND EXISTS (
          SELECT 1 FROM public.app_dat_superadmin
          WHERE uuid = auth.uid() AND activo = true
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename  = 's3_multipart_uploads_parts'
      AND policyname = 'home_banners_multipart_parts_insert_superadmin'
  ) THEN
    CREATE POLICY home_banners_multipart_parts_insert_superadmin
      ON storage.s3_multipart_uploads_parts FOR INSERT
      TO authenticated
      WITH CHECK (
        bucket_id = 'imagenes'
        AND EXISTS (
          SELECT 1 FROM storage.s3_multipart_uploads
          WHERE id = upload_id
            AND bucket_id = 'imagenes'
            AND key LIKE 'banners/%'
            AND owner_id = (auth.uid())::text
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename  = 's3_multipart_uploads_parts'
      AND policyname = 'home_banners_multipart_parts_select_superadmin'
  ) THEN
    CREATE POLICY home_banners_multipart_parts_select_superadmin
      ON storage.s3_multipart_uploads_parts FOR SELECT
      TO authenticated
      USING (
        bucket_id = 'imagenes'
        AND EXISTS (
          SELECT 1 FROM storage.s3_multipart_uploads
          WHERE id = upload_id
            AND bucket_id = 'imagenes'
            AND key LIKE 'banners/%'
            AND owner_id = (auth.uid())::text
        )
      );
  END IF;
END
$$;
