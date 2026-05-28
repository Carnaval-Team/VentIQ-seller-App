-- ============================================================================
-- Migración: soporte para múltiples fotos por factura
-- Ejecutar en el SQL Editor de Supabase.
-- ============================================================================

-- 1. Nueva tabla de fotos
CREATE TABLE IF NOT EXISTS public.imp_dat_factura_foto (
    id           BIGSERIAL    PRIMARY KEY,
    id_factura   BIGINT       NOT NULL REFERENCES public.imp_dat_factura(id) ON DELETE CASCADE,
    foto_url     TEXT         NOT NULL,
    numero_pagina INTEGER     NOT NULL DEFAULT 1,   -- página/orden de la foto
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now()
);

COMMENT ON TABLE  public.imp_dat_factura_foto              IS 'Fotos de cada factura de importadora (una por página).';
COMMENT ON COLUMN public.imp_dat_factura_foto.numero_pagina IS 'Número de página de la factura que representa esta foto.';

CREATE INDEX IF NOT EXISTS idx_imp_dat_factura_foto_factura
    ON public.imp_dat_factura_foto (id_factura, numero_pagina ASC);

-- 2. RLS
ALTER TABLE public.imp_dat_factura_foto ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'imp_dat_factura_foto'
      AND policyname = 'Acceso autenticado - imp_dat_factura_foto'
  ) THEN
    EXECUTE $policy$
      CREATE POLICY "Acceso autenticado - imp_dat_factura_foto"
          ON public.imp_dat_factura_foto FOR ALL
          TO authenticated USING (TRUE) WITH CHECK (TRUE)
    $policy$;
  END IF;
END $$;

-- 3. Columnas de metadatos de archivo (nombre visible y tipo MIME)
ALTER TABLE public.imp_dat_factura_foto
    ADD COLUMN IF NOT EXISTS nombre_archivo TEXT,
    ADD COLUMN IF NOT EXISTS mime_type      TEXT DEFAULT 'image/jpeg';

-- 4. Migrar foto_url existente en imp_dat_factura → imp_dat_factura_foto
INSERT INTO public.imp_dat_factura_foto (id_factura, foto_url, numero_pagina, created_at)
SELECT id, foto_url, 1, created_at
FROM public.imp_dat_factura
WHERE foto_url IS NOT NULL AND foto_url <> '';
