-- ============================================================================
-- 041_taxi_rls_hardening.sql
-- Endurecimiento de RLS y permisos del módulo taxi. **MIGRACIÓN DE CUTOVER.**
--
-- ⚠️⚠️  NO APLICAR ANTES DE PUBLICAR LAS APPS NUEVAS  ⚠️⚠️
--
--   Esta migración REVOCA escrituras directas que las builds VIEJAS usan.
--   Si se aplica antes de que el parque esté actualizado:
--     · la app vieja no podrá insertar solicitudes ni viajes → sin viajes;
--     · el chofer viejo no podrá actualizar su ubicación de viaje;
--     · las ofertas (negociación) dejan de poder crearse.
--   Es exactamente lo que se quiere, pero SÓLO cuando ya nadie usa el flujo
--   viejo. Orden obligatorio (plan §4.3):
--
--       1. Aplicar 030–040 (ya hecho).
--       2. Publicar apps nuevas (cliente + chofer) con el flujo sin negociación.
--       3. Subir la versión mínima / forzar actualización.
--       4. APLICAR 041.
--       5. Encender `taxi_precio_fijo_activo = true`.
--
--   Ver `docs/plan-taxi-precio-fijo/06-aplicar-migraciones.md` §cutover.
--
-- ANEXO DE DISEÑO
--   · 04-diseno-tecnico.md       §6.2 (endurecimiento)
--   · 09-identidad-y-vehiculos.md §6.4 (fuga de datos personales en users)
--   · PLAN-IMPLEMENTACION.md     §4 tabla de agujeros
--
-- QUÉ CIERRA (cada punto es un agujero real y explotable desde la app)
--   1. `users_` (FOR ALL USING true): cualquiera leía CI, documentos, teléfono,
--      dirección y KYC de TODOS los usuarios. Se elimina.
--   2. `solicitudes_select_own_client` (user_id = auth.uid() OR true): el OR true
--      lo anulaba; cualquiera leía todas las solicitudes.
--   3. `drivers_see_solicitudes` (USING true): idem, y además exponía el viaje
--      aceptado de otros choferes. Se sustituye por dos políticas acotadas.
--   4. `solicitudes_insert_client` + `solicitudes_update_own_client`: permitían
--      publicar con precio libre y editar cualquier columna (incluido el precio
--      ya congelado). El precio sólo lo escribe `fn_crear_solicitud`.
--   5. `viajes_insert_authenticated` (WITH CHECK true): cualquiera creaba viajes.
--   6. `wallet_drivers_insert_own` / `wallet_drivers_update_own`: el chofer podía
--      subirse el saldo. Agujero de dinero directo.
--   7. `transacciones_insert_client`: transacciones de wallet falsas.
--   8. `suscription_user_insert_own` / `suscription_user_update_own`: el cliente
--      podía acreditarse saldo. Agujero de dinero directo.
--   9. `ofertas_insert_driver` / `ofertas_update_client` / `drivers_own_ofertas`
--      (ALL): el flujo de negociación ya no existe; se deja sólo lectura.
--  10. `places_` (FOR ALL USING true): cualquiera movía el pin de cualquier
--      chofer y lo ponía en línea. Se elimina; quedan las políticas propias.
--
-- LO QUE **NO** CAMBIA
--   · Las RPC son SECURITY DEFINER: las revocaciones no les afectan.
--   · El cliente sigue leyendo su propia solicitud, su wallet y su historial.
--   · El chofer sigue leyendo solicitudes `pendiente` (necesario para la lista
--     en tiempo real) y las suyas aceptadas/completadas.
--   · `place`: se mantiene la lectura para el mapa y la escritura de lo propio.
--   · `configuracion_tarifas`, `zonas_tarifa`, `tarifas_municipio`: lectura para
--     autenticados; escritura sólo superadmin (ya estaba así en 034).
--
-- IDEMPOTENCIA
--   DROP POLICY IF EXISTS / CREATE POLICY dentro de DO con guarda /
--   REVOKE (idempotente por naturaleza) / CREATE INDEX IF NOT EXISTS.
--
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 0. Prerrequisitos
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_falta text[] := ARRAY[]::text[];
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'muevete' AND p.proname = 'fn_tomar_viaje') THEN
    v_falta := array_append(v_falta, '039.fn_tomar_viaje');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'muevete' AND p.proname = 'fn_completar_viaje') THEN
    v_falta := array_append(v_falta, '040.fn_completar_viaje');
  END IF;
  IF cardinality(v_falta) > 0 THEN
    RAISE EXCEPTION 'prerrequisitos_faltantes: %', v_falta USING ERRCODE = 'P0001';
  END IF;

  -- Aviso ruidoso: el flag debe seguir APAGADO hasta publicar las apps nuevas.
  IF coalesce((SELECT taxi_precio_fijo_activo
                 FROM muevete.configuracion_tarifas WHERE id = 1), false) THEN
    RAISE NOTICE 'AVISO: taxi_precio_fijo_activo ya está en true. Asegúrate de que TODAS las apps en circulación son las nuevas antes de continuar.';
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 1. `users`: cerrar la fuga de datos personales
--    `users_` era FOR ALL USING (true): cualquiera leía documentos de todos.
--    Ya existen users_select_own, users_update_own, users_insert_own,
--    users_select_conductor_asignado y superadmin_all_users.
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS users_ ON muevete.users;

-- Refuerzo: el conductor asignado ve sólo lo mínimo del cliente durante el
-- viaje. Se recrea para dejar explícito el alcance (sigue leyendo la fila
-- completa de `users`, pero sólo mientras el viaje está vivo).
DROP POLICY IF EXISTS users_select_conductor_asignado ON muevete.users;
CREATE POLICY users_select_conductor_asignado ON muevete.users
  FOR SELECT TO authenticated
  USING (
    muevete.get_my_driver_id() IS NOT NULL
    AND EXISTS (
      SELECT 1
        FROM muevete.solicitudes_transporte s
       WHERE s.user_id   = muevete.users.uuid
         AND s.driver_id = muevete.get_my_driver_id()
         AND s.estado IN ('aceptada', 'completada')
    )
  );

-- ----------------------------------------------------------------------------
-- 2. `solicitudes_transporte`
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS drivers_see_solicitudes               ON muevete.solicitudes_transporte;
DROP POLICY IF EXISTS solicitudes_select_own_client         ON muevete.solicitudes_transporte;
DROP POLICY IF EXISTS solicitudes_update_own_client         ON muevete.solicitudes_transporte;
DROP POLICY IF EXISTS solicitudes_insert_client             ON muevete.solicitudes_transporte;
DROP POLICY IF EXISTS solicitudes_select_driver_asignado    ON muevete.solicitudes_transporte;

-- El cliente ve SU solicitud (sin OR true)
CREATE POLICY solicitudes_select_own_client ON muevete.solicitudes_transporte
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- El chofer ve las pendientes (lista en tiempo real) y las suyas
CREATE POLICY solicitudes_select_driver_asignado ON muevete.solicitudes_transporte
  FOR SELECT TO authenticated
  USING (
    muevete.get_my_driver_id() IS NOT NULL
    AND (
      (estado = 'pendiente' AND driver_id IS NULL)
      OR driver_id = muevete.get_my_driver_id()
    )
  );

-- Sin INSERT/UPDATE/DELETE: la creación y las transiciones van por RPC.
-- (Se borraron las políticas; el GRANT se revoca en §7.)

-- ----------------------------------------------------------------------------
-- 3. `viajes`
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS viajes_insert_authenticated ON muevete.viajes;
DROP POLICY IF EXISTS driver_own_viajes           ON muevete.viajes;
DROP POLICY IF EXISTS viajes_update_driver        ON muevete.viajes;
DROP POLICY IF EXISTS viajes_select_driver_own    ON muevete.viajes;

CREATE POLICY viajes_select_driver_own ON muevete.viajes
  FOR SELECT TO authenticated
  USING (driver_id = muevete.get_my_driver_id());

-- `client_own_viajes` y `viajes_select_client` siguen vigentes (lectura).

-- ----------------------------------------------------------------------------
-- 4. Dinero: wallet_drivers, transacciones_wallet, suscription_user
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS wallet_drivers_insert_own     ON muevete.wallet_drivers;
DROP POLICY IF EXISTS wallet_drivers_update_own     ON muevete.wallet_drivers;

DROP POLICY IF EXISTS transacciones_insert_client   ON muevete.transacciones_wallet;
DROP POLICY IF EXISTS transacciones_insert_driver   ON muevete.transacciones_wallet;

DROP POLICY IF EXISTS suscription_user_insert_own   ON muevete.suscription_user;
DROP POLICY IF EXISTS suscription_user_update_own   ON muevete.suscription_user;

-- Se mantienen las SELECT propias (saldo, deuda, historial).

-- ----------------------------------------------------------------------------
-- 5. `ofertas_chofer`: el flujo de negociación ya no existe. Sólo lectura.
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS ofertas_insert_driver        ON muevete.ofertas_chofer;
DROP POLICY IF EXISTS ofertas_update_client        ON muevete.ofertas_chofer;
DROP POLICY IF EXISTS drivers_own_ofertas          ON muevete.ofertas_chofer;
DROP POLICY IF EXISTS ofertas_select_own_driver    ON muevete.ofertas_chofer;

CREATE POLICY ofertas_select_own_driver ON muevete.ofertas_chofer
  FOR SELECT TO authenticated
  USING (driver_id = muevete.get_my_driver_id());

-- ----------------------------------------------------------------------------
-- 6. `place`: cerrar el ALL USING (true)
--    Se mantienen las escrituras de lo propio (ponerse en línea, mover el pin).
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS places_ ON muevete.place;

-- ----------------------------------------------------------------------------
-- 7. Revocación de escrituras directas (las RPC son SECURITY DEFINER)
-- ----------------------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON muevete.solicitudes_transporte FROM authenticated, anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON muevete.viajes                 FROM authenticated, anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON muevete.wallet_drivers         FROM authenticated, anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON muevete.transacciones_wallet   FROM authenticated, anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON muevete.suscription_user       FROM authenticated, anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON muevete.ofertas_chofer         FROM authenticated, anon;

-- Lectura se conserva (la RLS decide qué filas)
GRANT SELECT ON muevete.solicitudes_transporte, muevete.viajes,
                muevete.wallet_drivers, muevete.transacciones_wallet,
                muevete.suscription_user, muevete.ofertas_chofer
  TO authenticated;

-- Supabase concede REFERENCES y TRIGGER por defecto (pg_default_acl = arwdDxtm).
-- Con TRIGGER, un cliente podría crear triggers sobre las tablas de dinero;
-- con REFERENCES, crear FKs hacia ellas. Ninguna app los necesita: fuera.
REVOKE REFERENCES, TRIGGER ON muevete.solicitudes_transporte, muevete.viajes,
                              muevete.wallet_drivers, muevete.transacciones_wallet,
                              muevete.suscription_user, muevete.ofertas_chofer
  FROM authenticated, anon;

-- `anon` (sin sesión) no tiene nada que hacer en las tablas de viajes y dinero.
-- Sus políticas son TO authenticated o dependen de auth.uid(), así que ya no
-- podía leer nada; esto lo deja imposible por privilegio también.
REVOKE ALL ON muevete.solicitudes_transporte, muevete.viajes,
              muevete.wallet_drivers, muevete.transacciones_wallet,
              muevete.suscription_user, muevete.ofertas_chofer
  FROM anon;

-- Política redundante: el ramo `pendiente` de solicitudes_select_driver_asignado
-- ya cubre lo mismo con más precisión (excluye las pendientes ya tomadas).
DROP POLICY IF EXISTS solicitudes_select_pending_driver ON muevete.solicitudes_transporte;

-- NOTA ACEPTADA (riesgo residual consciente): `place_select_active` mantiene
-- qual = true y deja que cualquier autenticado vea los pines de los choferes en
-- línea. Es lo que alimenta el mapa del cliente ("choferes cerca"), así que se
-- conserva. Mitigación futura: limitar a choferes dentro del polígono de la
-- zona del cliente o devolver sólo un conteo. Documentado en 11-riesgos.

-- ----------------------------------------------------------------------------
-- 8. Integridad: un solo wallet por usuario
--    Las RPC apuntan a la fila de menor id para ser deterministas, pero si hay
--    duplicados el dinero se reparte mal. Se crea el índice único SÓLO si la
--    tabla ya está limpia; si hay duplicados se avisa y NO se crea (hay que
--    consolidarlos a mano antes de reintentar).
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_dups integer;
BEGIN
  SELECT count(*) INTO v_dups
    FROM (SELECT s.user_id
            FROM muevete.suscription_user s
           WHERE s.user_id IS NOT NULL
           GROUP BY s.user_id
          HAVING count(*) > 1) d;

  IF v_dups > 0 THEN
    RAISE WARNING 'suscription_user tiene % usuarios con más de un wallet: NO se crea el índice único. Consolídalos y vuelve a ejecutar 041.', v_dups;
  ELSE
    CREATE UNIQUE INDEX IF NOT EXISTS suscription_user_user_id_uidx
      ON muevete.suscription_user (user_id)
      WHERE user_id IS NOT NULL;

    -- El COMMENT va DENTRO del ELSE a propósito: `COMMENT ON INDEX` sobre un
    -- índice inexistente lanza error y abortaría la migración entera, justo en
    -- el caso (duplicados) en el que queremos sólo avisar.
    COMMENT ON INDEX muevete.suscription_user_user_id_uidx IS
      'Un wallet por usuario. Creado por 041 si no había duplicados.';
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS transacciones_wallet_viaje_idx
  ON muevete.transacciones_wallet (viaje_id)
  WHERE viaje_id IS NOT NULL;

-- ----------------------------------------------------------------------------
-- 9. Realtime: filas completas en los payloads de UPDATE
--    (necesario para que la app del cliente detecte driver_id/estado y el
--    chofer detecte que un viaje ya fue tomado).
-- ----------------------------------------------------------------------------
ALTER TABLE muevete.solicitudes_transporte REPLICA IDENTITY FULL;
ALTER TABLE muevete.viajes                 REPLICA IDENTITY FULL;

DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE muevete.solicitudes_transporte;
  EXCEPTION WHEN duplicate_object THEN
    NULL;   -- ya estaba publicada
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE muevete.viajes;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;
END $$;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN (ejecutar a mano; NO forma parte de la migración)
-- ============================================================================
-- 1) Políticas resultantes:
--   SELECT tablename, policyname, cmd
--     FROM pg_policies
--    WHERE schemaname = 'muevete'
--      AND tablename IN ('users','solicitudes_transporte','viajes',
--                        'wallet_drivers','transacciones_wallet',
--                        'suscription_user','ofertas_chofer','place')
--    ORDER BY tablename, policyname;
--   -- NO debe quedar ninguna con qual = 'true' sobre users ni place,
--   -- ni ninguna política de INSERT/UPDATE/DELETE en las tablas de dinero.
--
-- 2) Permisos de tabla.
--    Esperado para `authenticated`: SÓLO 'SELECT' (ni REFERENCES ni TRIGGER).
--    Esperado para `anon`: vacío (ninguna fila).
--   SELECT table_name, grantee,
--          string_agg(privilege_type, ',' ORDER BY privilege_type) AS privs
--     FROM information_schema.role_table_grants
--    WHERE table_schema = 'muevete' AND grantee IN ('authenticated','anon')
--      AND table_name IN ('solicitudes_transporte','viajes','wallet_drivers',
--                         'transacciones_wallet','suscription_user','ofertas_chofer')
--    GROUP BY table_name, grantee
--    ORDER BY table_name, grantee;
--
-- 3) Con JWT de CLIENTE (no superadmin):
--   -- debe fallar (sin privilegio):
--   UPDATE muevete.solicitudes_transporte SET precio_plataforma = 1;
--   UPDATE muevete.suscription_user SET balance = 999999;
--   INSERT INTO muevete.transacciones_wallet (user_id, tipo, monto, estado)
--     VALUES (auth.uid(), 'recarga', 999999, 'completada');
--   INSERT INTO muevete.viajes (driver_id) VALUES (1);
--   -- debe devolver SÓLO las suyas:
--   SELECT count(*) FROM muevete.solicitudes_transporte;   -- las propias
--   -- y NO debe poder leer otros usuarios:
--   SELECT count(*) FROM muevete.users;                    -- 1 (la propia)
--
-- 4) Con JWT de CHOFER:
--   SELECT count(*) FROM muevete.solicitudes_transporte;
--   -- pendientes + las suyas; nunca las aceptadas de otro chofer
--   SELECT count(*) FROM muevete.users;                    -- sólo clientes de
--   -- viajes vivos con él (o 0 si no tiene viaje)
--   UPDATE muevete.wallet_drivers SET balance = 999999;    -- debe fallar
--
-- 5) Las RPC siguen funcionando (no les afectan las revocaciones):
--   SELECT muevete.fn_viajes_disponibles(22.40689, -79.96450, 5);
--
-- 6) Índice de wallet:
--   SELECT indexname FROM pg_indexes
--    WHERE schemaname='muevete' AND indexname='suscription_user_user_id_uidx';
--
-- ============================================================================
-- ROLLBACK (NO automático: revertir esto reabre agujeros de dinero)
-- ============================================================================
-- Si hay que revertir de urgencia, lo mínimo es devolver los GRANT de escritura
-- y recrear las políticas viejas. Queda documentado en el commit de cutover.
-- ============================================================================