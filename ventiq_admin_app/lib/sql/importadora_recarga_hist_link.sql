-- Vincula movimientos de recarga en imp_hist_saldo con imp_dat_recarga_saldo
ALTER TABLE public.imp_hist_saldo
  ADD COLUMN IF NOT EXISTS id_recarga BIGINT
    REFERENCES public.imp_dat_recarga_saldo(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_imp_hist_saldo_recarga
  ON public.imp_hist_saldo (id_recarga);

COMMENT ON COLUMN public.imp_hist_saldo.id_recarga IS 'FK opcional a la recarga que originó el movimiento.';
