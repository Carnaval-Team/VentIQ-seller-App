-- =============================================================================
-- Ajuste de lo que el cliente transfirió al renovar la licencia.
-- El plan sigue en USD; el reparto usa recibido_cup.
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.app_dat_cobro_licencia (
  id bigserial PRIMARY KEY,
  id_suscripcion bigint NOT NULL REFERENCES public.app_suscripciones(id) ON DELETE CASCADE,
  periodo date NOT NULL,
  recibido_usd numeric,
  recibido_cup numeric,
  transaccion text,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id_suscripcion, periodo)
);

COMMENT ON TABLE public.app_dat_cobro_licencia IS
  'Monto real recibido (USD y CUP) y código de la transferencia de una licencia en un mes.';

ALTER TABLE public.app_dat_cobro_licencia ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS app_dat_cobro_licencia_all ON public.app_dat_cobro_licencia;
CREATE POLICY app_dat_cobro_licencia_all
  ON public.app_dat_cobro_licencia
  FOR ALL TO authenticated
  USING (public.fn_is_superadmin_full_access())
  WITH CHECK (public.fn_is_superadmin_full_access());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.app_dat_cobro_licencia TO authenticated;
GRANT ALL ON public.app_dat_cobro_licencia TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.app_dat_cobro_licencia_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.app_dat_cobro_licencia_id_seq TO service_role;

COMMIT;
