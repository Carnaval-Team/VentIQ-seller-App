-- =============================================================================
-- Ficha de cobro en app_dat_agente.
-- La misma persona puede ser socio, agente de despliegue (licencias)
-- y agente de Carnaval. La tarjeta vive aquí, una sola vez.
-- Requiere carnavalapp.inventtia_agentes (sql_updates/inventtia_agentes.sql).
-- =============================================================================

BEGIN;

ALTER TABLE public.app_dat_agente
  ADD COLUMN IF NOT EXISTS tarjeta text,
  ADD COLUMN IF NOT EXISTS es_socio boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS despliega boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS id_agente_carnaval bigint;

COMMENT ON COLUMN public.app_dat_agente.tarjeta IS
  'Número de tarjeta para el pago al trabajador.';
COMMENT ON COLUMN public.app_dat_agente.es_socio IS
  'Parte en partes iguales el neto de Inventtia y el 1% global de Carnaval.';
COMMENT ON COLUMN public.app_dat_agente.despliega IS
  'Se puede asignar como agente de una licencia. Quien solo es socio o agente Carnaval queda en false.';
COMMENT ON COLUMN public.app_dat_agente.id_agente_carnaval IS
  'Agente de Carnaval (1% de sus tiendas) que corresponde a esta persona.';

CREATE UNIQUE INDEX IF NOT EXISTS uq_app_dat_agente_carnaval
  ON public.app_dat_agente (id_agente_carnaval)
  WHERE id_agente_carnaval IS NOT NULL;

ALTER TABLE public.app_dat_agente
  DROP CONSTRAINT IF EXISTS app_dat_agente_id_agente_carnaval_fkey;

ALTER TABLE public.app_dat_agente
  ADD CONSTRAINT app_dat_agente_id_agente_carnaval_fkey
  FOREIGN KEY (id_agente_carnaval)
  REFERENCES carnavalapp.inventtia_agentes(id)
  ON DELETE SET NULL;

COMMIT;
