-- ============================================================================
-- 034_taxi_rls_tarifas.sql
-- H0 · RLS de las tablas nuevas de tarifas y permisos de las RPC de lectura.
--
-- ANEXO DE DISEÑO: docs/plan-taxi-precio-fijo/04-diseno-tecnico.md §6.1
--
-- PRERREQUISITOS
--   · 030_baseline_sync_produccion.sql (provee muevete.is_superadmin())
--   · 031_taxi_zonas_tarifas.sql (tablas)
--   · 032_taxi_geo_y_cotizacion.sql (funciones)
--
-- ALCANCE
--   · Habilita RLS y crea políticas para: zonas_tarifa, tarifas_municipio,
--     configuracion_tarifas.
--   · NO toca las políticas existentes de solicitudes_transporte, viajes,
--     wallet_drivers, transacciones_wallet ni ofertas_chofer.
--     Ese endurecimiento es 038_taxi_rls_hardening.sql y se aplica SÓLO en el
--     cutover (si se aplica antes, las apps actuales dejan de funcionar).
--
-- IDEMPOTENCIA
--   · ENABLE ROW LEVEL SECURITY es idempotente.
--   · DROP POLICY IF EXISTS + CREATE POLICY.
--   · REVOKE/GRANT son idempotentes.
--
-- NO EJECUTAR CONTRA SUPABASE DESDE ESTE ENTORNO (sólo se entrega el archivo).
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Habilitar RLS
-- ----------------------------------------------------------------------------
ALTER TABLE muevete.zonas_tarifa           ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.tarifas_municipio      ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.configuracion_tarifas  ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- 2. Sin acceso para anon (defensa en profundidad además de RLS)
-- ----------------------------------------------------------------------------
REVOKE ALL ON muevete.zonas_tarifa          FROM anon;
REVOKE ALL ON muevete.tarifas_municipio     FROM anon;
REVOKE ALL ON muevete.configuracion_tarifas FROM anon;

-- ----------------------------------------------------------------------------
-- 3. Políticas de LECTURA para authenticated
--    El chofer necesita el nombre de la zona y la tarifa; el cliente necesita
--    la comisión para mostrar "te toca"; el superadmin necesita todo.
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS zonas_tarifa_select_auth ON muevete.zonas_tarifa;
CREATE POLICY zonas_tarifa_select_auth
  ON muevete.zonas_tarifa
  FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS tarifas_municipio_select_auth ON muevete.tarifas_municipio;
CREATE POLICY tarifas_municipio_select_auth
  ON muevete.tarifas_municipio
  FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS configuracion_tarifas_select_auth ON muevete.configuracion_tarifas;
CREATE POLICY configuracion_tarifas_select_auth
  ON muevete.configuracion_tarifas
  FOR SELECT TO authenticated
  USING (true);

-- ----------------------------------------------------------------------------
-- 4. Políticas de ESCRITURA: patrón superadmin_all_* (como el resto del esquema)
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS superadmin_all_zonas_tarifa ON muevete.zonas_tarifa;
CREATE POLICY superadmin_all_zonas_tarifa
  ON muevete.zonas_tarifa
  FOR ALL TO authenticated
  USING (muevete.is_superadmin())
  WITH CHECK (muevete.is_superadmin());

DROP POLICY IF EXISTS superadmin_all_tarifas_municipio ON muevete.tarifas_municipio;
CREATE POLICY superadmin_all_tarifas_municipio
  ON muevete.tarifas_municipio
  FOR ALL TO authenticated
  USING (muevete.is_superadmin())
  WITH CHECK (muevete.is_superadmin());

DROP POLICY IF EXISTS superadmin_all_configuracion_tarifas ON muevete.configuracion_tarifas;
CREATE POLICY superadmin_all_configuracion_tarifas
  ON muevete.configuracion_tarifas
  FOR ALL TO authenticated
  USING (muevete.is_superadmin())
  WITH CHECK (muevete.is_superadmin());

-- ----------------------------------------------------------------------------
-- 5. GRANTs de tabla
--    - SELECT: cualquier autenticado (necesario para la UI y las RPC).
--    - Escritura: authenticated, pero las políticas de §4 la limitan a
--      superadmin. Las RPC SECURITY DEFINER no dependen de estos grants.
--    - configuracion_tarifas es singleton: se permite UPDATE, no INSERT/DELETE
--      (la fila la creó 031).
-- ----------------------------------------------------------------------------
GRANT SELECT ON muevete.zonas_tarifa, muevete.tarifas_municipio,
               muevete.configuracion_tarifas TO authenticated;

GRANT INSERT, UPDATE, DELETE ON muevete.zonas_tarifa      TO authenticated;
GRANT INSERT, UPDATE, DELETE ON muevete.tarifas_municipio TO authenticated;
GRANT UPDATE                 ON muevete.configuracion_tarifas TO authenticated;

-- ----------------------------------------------------------------------------
-- 6. Permisos de ejecución de las RPC de lectura/cotización
--    (032 ya los concede; se repiten aquí de forma idempotente para que este
--    archivo deje el módulo "listo para usar" por sí solo.)
--    Las RPC de escritura (035–037) se conceden en sus propios archivos.
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION muevete.fn_punto_en_poligono(double precision, double precision, jsonb)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_punto_en_poligono(double precision, double precision, jsonb)
  TO authenticated;

REVOKE ALL ON FUNCTION muevete.fn_zona_de_punto(double precision, double precision, timestamptz)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_zona_de_punto(double precision, double precision, timestamptz)
  TO authenticated;

REVOKE ALL ON FUNCTION muevete.fn_cotizar_viaje(
  double precision, double precision, double precision, double precision,
  bigint, timestamptz, double precision, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_cotizar_viaje(
  double precision, double precision, double precision, double precision,
  bigint, timestamptz, double precision, text, text) TO authenticated;

-- Los helpers internos siguen SIN permiso para authenticated (ver 032).
REVOKE ALL ON FUNCTION muevete.fn_punto_en_anillo(double precision, double precision, jsonb)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION muevete.fn_haversine_km(double precision, double precision, double precision, double precision)
  FROM PUBLIC, anon, authenticated;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN (ejecutar a mano; NO forma parte de la migración)
-- ============================================================================
-- 1) RLS habilitado en las 3 tablas:
--   SELECT relname, relrowsecurity
--     FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
--    WHERE n.nspname = 'muevete'
--      AND relname IN ('zonas_tarifa','tarifas_municipio','configuracion_tarifas');
--      -- esperado: relrowsecurity = true en las 3
--
-- 2) Políticas creadas (esperado: 6):
--   SELECT tablename, policyname, cmd
--     FROM pg_policies
--    WHERE schemaname = 'muevete'
--      AND tablename IN ('zonas_tarifa','tarifas_municipio','configuracion_tarifas')
--    ORDER BY tablename, policyname;
--
-- 3) Grants:
--   SELECT grantee, privilege_type, table_name
--     FROM information_schema.role_table_grants
--    WHERE table_schema='muevete'
--      AND table_name IN ('zonas_tarifa','tarifas_municipio','configuracion_tarifas')
--      AND grantee IN ('anon','authenticated')
--    ORDER BY table_name, grantee, privilege_type;
--      -- esperado: sin filas para anon; SELECT en las 3 para authenticated;
--      --           INSERT/UPDATE/DELETE en zonas_tarifa y tarifas_municipio;
--      --           sólo UPDATE en configuracion_tarifas
--
-- 4) Funciones ejecutables por authenticated (esperado: true en las 3 primeras,
--    false en los helpers):
--   SELECT has_function_privilege('authenticated',
--     'muevete.fn_cotizar_viaje(double precision,double precision,double precision,double precision,bigint,timestamptz,double precision,text,text)', 'EXECUTE');
--   SELECT has_function_privilege('authenticated',
--     'muevete.fn_punto_en_anillo(double precision,double precision,jsonb)', 'EXECUTE');
--
-- 5) Prueba de rol (con un JWT real de cliente/chofer, fuera de este script):
--    - SELECT sobre las 3 tablas → permitido.
--    - INSERT/UPDATE en zonas_tarifa → rechazado (no es superadmin).
--
-- 6) Idempotencia: re-ejecutar 034 completo no debe lanzar error.
--
-- ----------------------------------------------------------------------------
-- OPCIONAL · SÓLO ENTORNO DE DESARROLLO (qhprswhhfasrikhawjoz)
-- En dev la publicación supabase_realtime NO tiene las tablas de muevete
-- (en producción sí). Si se van a probar H2/H3 en dev y se quiere realtime,
-- ejecutar a mano (NO forma parte de esta migración):
--
--   ALTER TABLE muevete.solicitudes_transporte REPLICA IDENTITY FULL;
--   ALTER TABLE muevete.viajes                 REPLICA IDENTITY FULL;
--   ALTER PUBLICATION supabase_realtime ADD TABLE muevete.solicitudes_transporte;
--   ALTER PUBLICATION supabase_realtime ADD TABLE muevete.viajes;
--
-- Mientras no se haga, la app funciona con polling (10–15 s).
-- ============================================================================

-- ============================================================================
-- DOWN (documentado; NO ejecutar en despliegue normal)
-- ============================================================================
-- BEGIN;
-- DROP POLICY IF EXISTS superadmin_all_configuracion_tarifas ON muevete.configuracion_tarifas;
-- DROP POLICY IF EXISTS superadmin_all_tarifas_municipio      ON muevete.tarifas_municipio;
-- DROP POLICY IF EXISTS superadmin_all_zonas_tarifa          ON muevete.zonas_tarifa;
-- DROP POLICY IF EXISTS configuracion_tarifas_select_auth    ON muevete.configuracion_tarifas;
-- DROP POLICY IF EXISTS tarifas_municipio_select_auth        ON muevete.tarifas_municipio;
-- DROP POLICY IF EXISTS zonas_tarifa_select_auth             ON muevete.zonas_tarifa;
--
-- REVOKE ALL ON muevete.zonas_tarifa, muevete.tarifas_municipio,
--               muevete.configuracion_tarifas FROM authenticated;
--
-- ALTER TABLE muevete.zonas_tarifa          DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE muevete.tarifas_municipio     DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE muevete.configuracion_tarifas DISABLE ROW LEVEL SECURITY;
--
-- REVOKE ALL ON FUNCTION muevete.fn_cotizar_viaje(
--   double precision, double precision, double precision, double precision,
--   bigint, timestamptz, double precision, text, text) FROM authenticated;
-- REVOKE ALL ON FUNCTION muevete.fn_zona_de_punto(double precision, double precision, timestamptz)
--   FROM authenticated;
-- REVOKE ALL ON FUNCTION muevete.fn_punto_en_poligono(double precision, double precision, jsonb)
--   FROM authenticated;
-- COMMIT;
-- ============================================================================