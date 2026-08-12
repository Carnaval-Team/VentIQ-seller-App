-- ============================================================================
--  WAPI Notifications — Conceder acceso de lectura/uso al rol AUDITOR
--  Fecha: 2026-07-11
--  Descripción:
--    El helper RLS `fn_user_can_access_tienda` solo reconocía a gerente y
--    supervisor. Como TODAS las tablas WAPI (incluida `app_wapi_licencia`)
--    se filtran con este helper, un AUDITOR de una tienda con licencia WAPI
--    activa veía la pantalla "Notificación a Clientes" como si no tuviera
--    suscripción: su SELECT sobre `app_wapi_licencia` devolvía 0 filas por
--    RLS, el cliente recibía null y ofrecía adquirir licencia.
--
--    Aquí ampliamos el helper para incluir al rol auditor (tabla `auditor`,
--    columnas uuid + id_tienda). Al ser un helper SECURITY DEFINER usado por
--    todas las políticas WAPI, este cambio da acceso coherente en todas las
--    tablas del módulo sin tocar cada política individual.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_user_can_access_tienda(p_id_tienda bigint)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.app_dat_gerente
    WHERE id_tienda = p_id_tienda AND uuid = auth.uid()
  ) OR EXISTS (
    SELECT 1 FROM public.app_dat_supervisor
    WHERE id_tienda = p_id_tienda AND uuid = auth.uid()
  ) OR EXISTS (
    SELECT 1 FROM public.auditor
    WHERE id_tienda = p_id_tienda AND uuid = auth.uid()
  );
$$;

-- ============================================================================
-- FIN — WAPI auditor access migration
-- ============================================================================
