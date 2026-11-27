-- Multitienda: relaciona una tienda secundaria con su tienda principal.
-- Una tienda con id_tienda_principal NULL es independiente o principal.
-- Una secundaria no se lista como cliente independiente en licencias/reparto:
-- se muestra solo la principal, que aclara cuántas secundarias incluye.

ALTER TABLE public.app_dat_tienda
  ADD COLUMN IF NOT EXISTS id_tienda_principal bigint
    REFERENCES public.app_dat_tienda (id);

ALTER TABLE public.app_dat_tienda
  DROP CONSTRAINT IF EXISTS chk_tienda_no_es_su_principal;

ALTER TABLE public.app_dat_tienda
  ADD CONSTRAINT chk_tienda_no_es_su_principal
    CHECK (id_tienda_principal IS NULL OR id_tienda_principal <> id);

CREATE INDEX IF NOT EXISTS idx_app_dat_tienda_principal
  ON public.app_dat_tienda (id_tienda_principal)
  WHERE id_tienda_principal IS NOT NULL;
