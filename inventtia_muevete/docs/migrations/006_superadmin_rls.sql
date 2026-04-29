-- ============================================================
-- Migration 006: Superadmin RLS policies for muevete tables
-- Allows users present in public.app_dat_superadmin (activo = true)
-- to SELECT, INSERT, UPDATE, DELETE on all muevete tables.
-- ============================================================

-- Helper function: returns TRUE if the current auth user
-- exists in public.app_dat_superadmin and is active.
CREATE OR REPLACE FUNCTION muevete.is_superadmin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.app_dat_superadmin
    WHERE uuid = auth.uid()
      AND activo = true
  );
$$;

-- ============================================================
-- 1. solicitudes_transporte
-- ============================================================
CREATE POLICY "superadmin_all_solicitudes_transporte"
  ON muevete.solicitudes_transporte
  FOR ALL
  TO authenticated
  USING (muevete.is_superadmin())
  WITH CHECK (muevete.is_superadmin());

-- ============================================================
-- 2. ofertas_chofer
-- ============================================================
CREATE POLICY "superadmin_all_ofertas_chofer"
  ON muevete.ofertas_chofer
  FOR ALL
  TO authenticated
  USING (muevete.is_superadmin())
  WITH CHECK (muevete.is_superadmin());

-- ============================================================
-- 3. viajes
-- ============================================================
CREATE POLICY "superadmin_all_viajes"
  ON muevete.viajes
  FOR ALL
  TO authenticated
  USING (muevete.is_superadmin())
  WITH CHECK (muevete.is_superadmin());

-- ============================================================
-- 4. wallet_drivers
-- ============================================================
CREATE POLICY "superadmin_all_wallet_drivers"
  ON muevete.wallet_drivers
  FOR ALL
  TO authenticated
  USING (muevete.is_superadmin())
  WITH CHECK (muevete.is_superadmin());

-- ============================================================
-- 5. transacciones_wallet
-- ============================================================
CREATE POLICY "superadmin_all_transacciones_wallet"
  ON muevete.transacciones_wallet
  FOR ALL
  TO authenticated
  USING (muevete.is_superadmin())
  WITH CHECK (muevete.is_superadmin());

-- ============================================================
-- 6. drivers
-- ============================================================
ALTER TABLE muevete.drivers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "superadmin_all_drivers"
  ON muevete.drivers
  FOR ALL
  TO authenticated
  USING (muevete.is_superadmin())
  WITH CHECK (muevete.is_superadmin());

-- drivers also need to read/update their own row
CREATE POLICY "drivers_own_row"
  ON muevete.drivers
  FOR ALL
  TO authenticated
  USING (uuid = auth.uid())
  WITH CHECK (uuid = auth.uid());

-- ============================================================
-- 7. place (driver positions)
-- ============================================================
CREATE POLICY "superadmin_all_place"
  ON muevete.place
  FOR ALL
  TO authenticated
  USING (muevete.is_superadmin())
  WITH CHECK (muevete.is_superadmin());

-- ============================================================
-- 8. vehiculos
-- ============================================================
ALTER TABLE muevete.vehiculos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "superadmin_all_vehiculos"
  ON muevete.vehiculos
  FOR ALL
  TO authenticated
  USING (muevete.is_superadmin())
  WITH CHECK (muevete.is_superadmin());

-- drivers can read vehicles (needed for joins)
CREATE POLICY "authenticated_read_vehiculos"
  ON muevete.vehiculos
  FOR SELECT
  TO authenticated
  USING (true);

-- ============================================================
-- 9. vehicle_type
-- ============================================================
ALTER TABLE muevete.vehicle_type ENABLE ROW LEVEL SECURITY;

CREATE POLICY "superadmin_all_vehicle_type"
  ON muevete.vehicle_type
  FOR ALL
  TO authenticated
  USING (muevete.is_superadmin())
  WITH CHECK (muevete.is_superadmin());

-- everyone authenticated can read vehicle types
CREATE POLICY "authenticated_read_vehicle_type"
  ON muevete.vehicle_type
  FOR SELECT
  TO authenticated
  USING (true);

-- ============================================================
-- 10. users (client users)
-- ============================================================
ALTER TABLE muevete.users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "superadmin_all_users"
  ON muevete.users
  FOR ALL
  TO authenticated
  USING (muevete.is_superadmin())
  WITH CHECK (muevete.is_superadmin());

-- users can read/update their own row
CREATE POLICY "users_own_row"
  ON muevete.users
  FOR ALL
  TO authenticated
  USING (uuid = auth.uid())
  WITH CHECK (uuid = auth.uid());

-- ============================================================
-- 11. direcciones_rapidas
-- ============================================================
CREATE POLICY "superadmin_all_direcciones_rapidas"
  ON muevete.direcciones_rapidas
  FOR ALL
  TO authenticated
  USING (muevete.is_superadmin())
  WITH CHECK (muevete.is_superadmin());

-- ============================================================
-- 12. notificaciones
-- ============================================================
CREATE POLICY "superadmin_all_notificaciones"
  ON muevete.notificaciones
  FOR ALL
  TO authenticated
  USING (muevete.is_superadmin())
  WITH CHECK (muevete.is_superadmin());

-- ============================================================
-- 13. push_tokens
-- ============================================================
CREATE POLICY "superadmin_all_push_tokens"
  ON muevete.push_tokens
  FOR ALL
  TO authenticated
  USING (muevete.is_superadmin())
  WITH CHECK (muevete.is_superadmin());

-- ============================================================
-- 14. valoraciones_viaje
-- ============================================================
ALTER TABLE muevete.valoraciones_viaje ENABLE ROW LEVEL SECURITY;

CREATE POLICY "superadmin_all_valoraciones_viaje"
  ON muevete.valoraciones_viaje
  FOR ALL
  TO authenticated
  USING (muevete.is_superadmin())
  WITH CHECK (muevete.is_superadmin());

-- users can insert their own ratings
CREATE POLICY "users_insert_own_valoraciones"
  ON muevete.valoraciones_viaje
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- users can read ratings
CREATE POLICY "authenticated_read_valoraciones"
  ON muevete.valoraciones_viaje
  FOR SELECT
  TO authenticated
  USING (true);

-- ============================================================
-- 15. configuracion_navegacion
-- ============================================================
ALTER TABLE muevete.configuracion_navegacion ENABLE ROW LEVEL SECURITY;

CREATE POLICY "superadmin_all_configuracion_navegacion"
  ON muevete.configuracion_navegacion
  FOR ALL
  TO authenticated
  USING (muevete.is_superadmin())
  WITH CHECK (muevete.is_superadmin());

-- everyone authenticated can read config
CREATE POLICY "authenticated_read_configuracion"
  ON muevete.configuracion_navegacion
  FOR SELECT
  TO authenticated
  USING (true);

-- ============================================================
-- 16. suscription_user (client wallets)
-- ============================================================
ALTER TABLE muevete.suscription_user ENABLE ROW LEVEL SECURITY;

CREATE POLICY "superadmin_all_suscription_user"
  ON muevete.suscription_user
  FOR ALL
  TO authenticated
  USING (muevete.is_superadmin())
  WITH CHECK (muevete.is_superadmin());

-- users can read their own wallet
CREATE POLICY "users_own_suscription"
  ON muevete.suscription_user
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- ============================================================
-- 17. suscription_plan
-- ============================================================
ALTER TABLE muevete.suscription_plan ENABLE ROW LEVEL SECURITY;

CREATE POLICY "superadmin_all_suscription_plan"
  ON muevete.suscription_plan
  FOR ALL
  TO authenticated
  USING (muevete.is_superadmin())
  WITH CHECK (muevete.is_superadmin());

-- everyone can read plans
CREATE POLICY "authenticated_read_suscription_plan"
  ON muevete.suscription_plan
  FOR SELECT
  TO authenticated
  USING (true);

-- ============================================================
-- 18. suscription_plan_user_history
-- ============================================================
ALTER TABLE muevete.suscription_plan_user_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "superadmin_all_suscription_plan_user_history"
  ON muevete.suscription_plan_user_history
  FOR ALL
  TO authenticated
  USING (muevete.is_superadmin())
  WITH CHECK (muevete.is_superadmin());

-- users can read their own history
CREATE POLICY "users_own_plan_history"
  ON muevete.suscription_plan_user_history
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- ============================================================
-- Verify: list all new superadmin policies
-- ============================================================
SELECT tablename, policyname
FROM pg_policies
WHERE schemaname = 'muevete'
  AND policyname LIKE 'superadmin_%'
ORDER BY tablename;
