-- ============================================================================
-- Fase 1 (aditivo): helpers de acceso a configuración de tienda
-- ============================================================================
-- Extraído de S01 (`docs/plan-multimoneda/configuracion_tienda_rls_propuesta.sql`)
-- CON G2 (RH + trabajador) ya incluido en `puede_leer`.
--
-- Regla de oro: este script SOLO crea funciones nuevas. No hace
-- ENABLE RLS / REVOKE / policies sobre `app_dat_configuracion_tienda`
-- (eso sigue en S01 completo → Fase 3 / contrato, o pase autorizado aparte).
-- Tampoco parchea sync_bundle / licencia / consolidación.
--
-- Lo necesitan: `01_helpers_alineacion` (`fn_alinear_*` → puede_escribir)
-- y, más adelante, las guardas de lectura cuando se instalen.
-- ============================================================================

DO $preflight$
BEGIN
  IF to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NOT NULL
     OR to_regprocedure('public.fn_config_tienda_puede_leer(bigint)') IS NOT NULL
     OR to_regprocedure('public.fn_config_tienda_exigir_lectura(bigint)') IS NOT NULL THEN
    RAISE EXCEPTION
      'Ya existen helpers de config_tienda; no sobrescribir sin revisión (usar G2 si solo falta RH/trabajador)';
  END IF;
END;
$preflight$;

CREATE FUNCTION public.fn_config_tienda_puede_escribir(p_id_tienda bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
    SELECT p_id_tienda IS NOT NULL
       AND auth.uid() IS NOT NULL
       AND (
           EXISTS (
               SELECT 1 FROM public.app_dat_dueno d
               WHERE d.id_tienda = p_id_tienda AND d.uuid = auth.uid()
           )
           OR EXISTS (
               SELECT 1 FROM public.app_dat_gerente g
               WHERE g.id_tienda = p_id_tienda AND g.uuid = auth.uid()
           )
           OR EXISTS (
               SELECT 1 FROM public.app_dat_superadmin s
               WHERE s.uuid = auth.uid() AND s.activo = true AND s.nivel_acceso = 1
           )
       );
$function$;

CREATE FUNCTION public.fn_config_tienda_puede_leer(p_id_tienda bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
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

CREATE FUNCTION public.fn_config_tienda_exigir_lectura(p_id_tienda bigint)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
    IF auth.role() = 'service_role' THEN
        RETURN;
    END IF;
    IF NOT public.fn_config_tienda_puede_leer(p_id_tienda) THEN
        RAISE EXCEPTION 'Acceso denegado a configuracion de tienda' USING ERRCODE = '42501';
    END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_config_tienda_puede_escribir(bigint) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_config_tienda_puede_leer(bigint) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_config_tienda_exigir_lectura(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_config_tienda_puede_escribir(bigint) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_config_tienda_puede_leer(bigint) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_config_tienda_exigir_lectura(bigint) TO authenticated, service_role;
