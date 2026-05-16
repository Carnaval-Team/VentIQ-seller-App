-- =============================================================================
-- MIGRACIÓN 020: Corregir RLS de solicitudes_plan
-- El superadmin necesita ver TODAS las solicitudes sin filtro de usuario.
-- Se reemplaza la política restrictiva por una abierta para authenticated.
-- La privacidad se gestiona a nivel de aplicación (el superadmin filtra todo,
-- la app móvil filtra por usuario_uuid en la query, no en RLS).
-- =============================================================================

-- Eliminar políticas anteriores
DROP POLICY IF EXISTS "solicitudes_plan_own_select"      ON muevete.solicitudes_plan;
DROP POLICY IF EXISTS "solicitudes_plan_service_select"  ON muevete.solicitudes_plan;
DROP POLICY IF EXISTS "solicitudes_plan_service_update"  ON muevete.solicitudes_plan;
DROP POLICY IF EXISTS "solicitudes_plan_service_insert"  ON muevete.solicitudes_plan;
DROP POLICY IF EXISTS "solicitudes_plan_own_insert"      ON muevete.solicitudes_plan;

-- SELECT: cualquier usuario autenticado puede leer todas las solicitudes
-- (la app móvil filtra por usuario_uuid en la query; el superadmin ve todo)
CREATE POLICY "solicitudes_plan_select_all" ON muevete.solicitudes_plan
  FOR SELECT TO authenticated
  USING (true);

-- INSERT: solo el propio usuario puede crear su solicitud
CREATE POLICY "solicitudes_plan_own_insert" ON muevete.solicitudes_plan
  FOR INSERT TO authenticated
  WITH CHECK (usuario_uuid = auth.uid());

-- UPDATE: solo service_role (las funciones SECURITY DEFINER aprueban/rechazan)
CREATE POLICY "solicitudes_plan_service_update" ON muevete.solicitudes_plan
  FOR UPDATE TO service_role
  USING (true);
