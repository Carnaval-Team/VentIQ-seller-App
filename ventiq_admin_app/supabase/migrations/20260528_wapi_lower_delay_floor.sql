-- Baja el piso del CHECK de delay_min_seconds (10 → 5) y ajusta el default
-- a 5/10 para nuevas programaciones. Las filas existentes no se modifican.
--
-- Motivación: el flujo nuevo envía a varios destinatarios en paralelo por
-- producto, así que el delay entre lotes de productos puede ser menor sin
-- pasar el techo de 20 msgs/min/sesión de OpenWA.

ALTER TABLE public.app_wapi_programacion
  DROP CONSTRAINT IF EXISTS app_wapi_programacion_delay_min_seconds_check;

ALTER TABLE public.app_wapi_programacion
  ADD  CONSTRAINT app_wapi_programacion_delay_min_seconds_check
       CHECK (delay_min_seconds >= 5);

ALTER TABLE public.app_wapi_programacion
  ALTER COLUMN delay_min_seconds SET DEFAULT 5,
  ALTER COLUMN delay_max_seconds SET DEFAULT 10;
