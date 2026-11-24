-- ============================================================================
-- G2: ampliar fn_config_tienda_puede_leer (RH + trabajador de la tienda)
-- ============================================================================
-- Decisión 2026-11-23: los dos grupos que quedaban fuera en main deben poder
-- leer configuración (licencia, consolidación, sync_bundle):
--   * app_dat_recursos_humanos de la tienda
--   * app_dat_trabajadores con uuid en esa tienda
--
-- newa: aplicar ya (S01 ya existe).
-- main: en el pase, DESPUÉS de S01 (`configuracion_tienda_rls_propuesta.sql`).
--       Si S01 se aplica desde el borrador ya parcheado con G2, este script
--       es idempotente (REPLACE con el mismo cuerpo).
-- ============================================================================

DO $preflight$
BEGIN
  IF to_regprocedure('public.fn_config_tienda_puede_leer(bigint)') IS NULL
     OR to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL THEN
    RAISE EXCEPTION 'Faltan fn_config_tienda_puede_leer/escribir (aplicar S01 antes)';
  END IF;
  IF to_regclass('public.app_dat_recursos_humanos') IS NULL THEN
    RAISE EXCEPTION 'Falta app_dat_recursos_humanos';
  END IF;
  IF to_regclass('public.app_dat_trabajadores') IS NULL THEN
    RAISE EXCEPTION 'Falta app_dat_trabajadores';
  END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.fn_config_tienda_puede_leer(p_id_tienda bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
    SELECT p_id_tienda IS NOT NULL
       AND auth.uid() IS NOT NULL
       AND (
           public.fn_config_tienda_puede_escribir(p_id_tienda)
           OR EXISTS (
               SELECT 1 FROM public.app_dat_supervisor s
               WHERE s.id_tienda = p_id_tienda AND s.uuid = auth.uid()
           )
           OR EXISTS (
               SELECT 1 FROM public.auditor a
               WHERE a.id_tienda = p_id_tienda AND a.uuid = auth.uid()
           )
           OR EXISTS (
               SELECT 1 FROM public.app_dat_vendedor v
               JOIN public.app_dat_tpv t ON t.id = v.id_tpv
               WHERE t.id_tienda = p_id_tienda AND v.uuid = auth.uid()
           )
           OR EXISTS (
               SELECT 1 FROM public.app_dat_almacenero a
               JOIN public.app_dat_almacen al ON al.id = a.id_almacen
               WHERE al.id_tienda = p_id_tienda AND a.uuid = auth.uid()
                 AND al.deleted_at IS NULL
           )
           OR EXISTS (
               SELECT 1 FROM public.app_dat_jefe_cocina j
               JOIN public.app_dat_cocina c ON c.id = j.id_cocina
               WHERE c.id_tienda = p_id_tienda AND j.uuid = auth.uid()
                 AND c.deleted_at IS NULL
           )
           OR EXISTS (
               SELECT 1 FROM public.app_dat_recursos_humanos rh
               WHERE rh.id_tienda = p_id_tienda AND rh.uuid = auth.uid()
           )
           OR EXISTS (
               SELECT 1 FROM public.app_dat_trabajadores tr
               WHERE tr.id_tienda = p_id_tienda AND tr.uuid = auth.uid()
           )
       );
$function$;

REVOKE ALL ON FUNCTION public.fn_config_tienda_puede_leer(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_config_tienda_puede_leer(bigint)
  TO authenticated, service_role;
