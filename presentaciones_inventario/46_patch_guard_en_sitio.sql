-- ============================================================================
-- 46 · PATCH OPCIONAL EN SITIO del guard  (NO APLICADO POR DEFECTO)
--      public.check_user_has_access_to_tienda(bigint) -> void
-- ============================================================================
--   ########################################################################
--   #  [!] ESTE ARCHIVO NO SE APLICA SOLO.                                 #
--   #  Es la opcion (a) de la Fase 0.5 (C9): tocar la funcion VIVA.        #
--   #  Solo se ejecuta si el usuario lo decide explicitamente.             #
--   #  Si NO se aplica, el stack nuevo funciona igual porque los objetos   #
--   #  nuevos usan `fn_check_user_has_access_to_tienda_safe` (archivo 45). #
--   #  Lo unico que queda sin arreglar es la app VIEJA en la cola offline  #
--   #  (`fn_registrar_venta_offline_v2/v3`), que hoy da 42P01.             #
--   ########################################################################
--
-- Contexto: docs/PLAN_CONSUMO_INGREDIENTES_ELABORADOS_PRESENTACIONES.md
-- (§3.1 C9, §6 Fase 0.5) y docs/_analisis/VERIFICACION_PLAN_2.md (A2/C9).
--
-- ----------------------------------------------------------------------------
-- QUE ARREGLA
-- ----------------------------------------------------------------------------
-- `check_user_has_access_to_tienda` no tiene `SET search_path` (`proconfig`
-- null) y resuelve 7 tablas sin calificar. Cualquier llamador con
-- `SET search_path = ''` la invoca heredando el `search_path` vacio y muere con
-- **42P01 relation "app_dat_vendedor" does not exist**. Con este patch el guard
-- (i) califica las 7 tablas con `public.` y (ii) fija
-- `SET search_path = public, pg_catalog`.
--
-- Desbloquea de golpe los 4 llamadores rotos (los usa la app HOY):
--   · fn_ejecutar_entrega_fisica_v2      (search_path = '')
--   · fn_preview_entrega_fisica_v2       (search_path = '')
--   · fn_registrar_venta_offline_v2      (search_path = '')  <- app offline
--   · fn_registrar_venta_offline_v3      (search_path = '')  <- app offline
-- (`auto_sync_service.dart:4015` llama a la _v3 con fallbacks que NO reconocen
-- el 42P01, porque `_isRpcUnavailable` solo busca `pgrst202`.)
--
-- ----------------------------------------------------------------------------
-- QUE **NO** CAMBIA
-- ----------------------------------------------------------------------------
--   · Misma FIRMA: `check_user_has_access_to_tienda(bigint)`, `RETURNS void`.
--   · Misma semantica: mismas 7 fuentes de rol (`app_dat_vendedor` +
--     `app_dat_tpv`, `app_dat_almacenero` + `app_dat_almacen`,
--     `app_dat_supervisor`, `auditor`, `app_dat_gerente`,
--     `app_dat_jefe_cocina` + `app_dat_cocina`), mismo filtro
--     `uuid = auth.uid()`, mismo `deleted_at IS NULL`.
--   · Mismo MENSAJE de error exacto: 'Acceso denegado: No tienes permisos para
--     acceder a esta tienda' y mismo ERRCODE (P0001, el de un RAISE EXCEPTION
--     sin `USING ERRCODE`).
--   · Mismo modo de seguridad: se mantiene **SECURITY INVOKER** (no se eleva a
--     DEFINER). El bug es de `search_path`, no de privilegios; no se toca RLS
--     ni el efecto de las policies.
--   · Mismos GRANT: `CREATE OR REPLACE` **conserva** el ACL actual
--     `{postgres,anon,authenticated,service_role}`. Este archivo NO ejecuta
--     REVOKE/GRANT (si se quisiera endurecer, hay una linea comentada al final).
--   · No se toca ninguna otra funcion.
--
-- ----------------------------------------------------------------------------
-- COMO REVERTIR (md5 de referencia)
-- ----------------------------------------------------------------------------
-- Definicion viva ORIGINAL (antes del patch), leida con `pg_get_functiondef`:
--   md5 = **438dbaec6f0fe94c23d4cb414cc41d89**
--   proconfig = null | prosecdef = false
--   proacl = {postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}
--
-- Revertir = volver a ejecutar el **BLOQUE DE REVERSION** del final de este
-- archivo (misma funcion, cuerpo original sin calificar y sin `SET`).
--
-- Aviso de fidelidad del md5: el cuerpo original guarda finales de linea CRLF
-- dentro de `$function$`; el bloque de reversion de abajo usa LF. Si al
-- restaurar el md5 no es exactamente `438dbaec...`, comprueba primero si la
-- unica diferencia son los CR (`md5(replace(def, chr(13), ''))` debe coincidir).
-- La forma robusta: guardar antes de aplicar
--   SELECT pg_get_functiondef('public.check_user_has_access_to_tienda(bigint)'::regprocedure);
-- (el runbook de task-9 guarda este backup) y reejecutar ese texto tal cual.
--
-- ----------------------------------------------------------------------------
-- COMO PROBAR (sin aplicar)
-- ----------------------------------------------------------------------------
-- Ver `presentaciones_inventario/47_tests_guard_search_path.sql`:
--   · seccion A  -> hoy: 42P01 con el guard vivo (comprobacion de sintoma);
--   · seccion B  -> aplica ESTE patch + el 45 dentro de `BEGIN ... ROLLBACK`
--                   y comprueba que `fn_preview_entrega_fisica_v2(3,3,4,1,null,null)`
--                   ya no da 42P01;
--   · seccion D  -> reverifica que no quedo nada aplicado.
-- En produccion `vsieeihstajlrdvpuooh` el MCP de sesion es
-- `supabase_read_only_user` (sin CREATE en `public`, sin EXECUTE en el guard):
-- **no puede aplicar esto**. Se prueba en debug `qhprswhhfasrikhawjoz` o en el
-- Editor SQL. Nada de este archivo se ha aplicado a produccion.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.check_user_has_access_to_tienda(
    id_tienda_param bigint
)
RETURNS void
LANGUAGE plpgsql
-- NOTA: a proposito NO se pone `SECURITY DEFINER` (la viva es INVOKER); solo se
-- califica y se fija el search_path. Este `SET` es lo que rompe la herencia del
-- `search_path = ''` de los 4 llamadores.
SET search_path = public, pg_catalog
AS $function$
DECLARE
    user_has_access boolean;
BEGIN
    -- Verificar si el usuario tiene acceso a la tienda en cualquiera de los roles
    SELECT EXISTS (
        SELECT 1 FROM public.app_dat_vendedor WHERE uuid = auth.uid() AND id_tpv IN (
            SELECT id FROM public.app_dat_tpv WHERE id_tienda = id_tienda_param
        )
        UNION
        SELECT 1 FROM public.app_dat_almacenero WHERE uuid = auth.uid() AND id_almacen IN (
            SELECT id FROM public.app_dat_almacen WHERE id_tienda = id_tienda_param
        )
        UNION
        SELECT 1 FROM public.app_dat_supervisor WHERE uuid = auth.uid() AND id_tienda = id_tienda_param
        UNION
        SELECT 1 FROM public.auditor WHERE uuid = auth.uid() AND id_tienda = id_tienda_param
        UNION
        SELECT 1 FROM public.app_dat_gerente WHERE uuid = auth.uid() AND id_tienda = id_tienda_param
        UNION
        -- FASE 3: jefe de cocina / cocinero. Su ambito es la cocina,
        -- y la cocina pertenece a una tienda.
        SELECT 1 FROM public.app_dat_jefe_cocina jc
          JOIN public.app_dat_cocina c ON c.id = jc.id_cocina
         WHERE jc.uuid = auth.uid()
           AND c.id_tienda = id_tienda_param
           AND c.deleted_at IS NULL
    ) INTO user_has_access;

    -- Si no tiene acceso, lanzar error
    IF NOT user_has_access THEN
        RAISE EXCEPTION 'Acceso denegado: No tienes permisos para acceder a esta tienda';
    END IF;
END;
$function$;

-- Los GRANT no se tocan: CREATE OR REPLACE conserva el ACL actual
-- {postgres,anon,authenticated,service_role}. Si algun dia se decide endurecer
-- el guard en sitio, descomentar (ojo: quitaria a `anon`, que hoy lo tiene):
--
-- REVOKE ALL ON FUNCTION public.check_user_has_access_to_tienda(bigint) FROM PUBLIC;
-- REVOKE ALL ON FUNCTION public.check_user_has_access_to_tienda(bigint) FROM anon;
-- GRANT EXECUTE ON FUNCTION public.check_user_has_access_to_tienda(bigint) TO authenticated, service_role;

COMMENT ON FUNCTION public.check_user_has_access_to_tienda(bigint) IS
    'Verifica el acceso del usuario (auth.uid()) a una tienda por cualquiera de sus roles (vendedor/almacenero/supervisor/auditor/gerente/jefe de cocina). Parche C9 (Fase 0.5, archivo 46, OPCIONAL): tablas calificadas con public. y SET search_path = public, pg_catalog para no heredar el search_path vacio de sus llamadores. Misma firma, misma semantica y mismo mensaje; SECURITY INVOKER.';

-- ============================================================================
-- VERIFICACION (comentada; ejecutar solo DESPUES de decidir aplicar)
-- ============================================================================
--
-- V1 · Firma, retorno, modo y search_path (la firma NO debe cambiar):
--
--   SELECT pg_get_function_identity_arguments(p.oid) AS args,
--          p.prorettype::regtype AS ret, p.prosecdef, p.proconfig
--     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname = 'public' AND p.proname = 'check_user_has_access_to_tienda';
--   -- esperado: (id_tienda_param bigint) | void | false | {search_path=public, pg_catalog}
--
-- V2 · Los 4 llamadores rotos ya no dan 42P01 (probarlo con un usuario de la
--      tienda 4, o como postgres):
--
--   SELECT public.fn_preview_entrega_fisica_v2(3, 3, 4, 1, null, null);
--   -- antes: ERROR 42P01 relation "app_dat_vendedor" does not exist
--   -- despues: jsonb con 'status' (p.ej. 'success' / 'imposible'), sin 42P01
--
-- V3 · El ACL no cambio (mismos GRANT):
--
--   SELECT proacl FROM pg_proc
--    WHERE oid = 'public.check_user_has_access_to_tienda(bigint)'::regprocedure;
--   -- esperado: {postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}
--
-- V4 · Ya no queda ninguna funcion con `search_path` vacio que llame al guard
--      y no restaure (las 4 culpables dejan de romper):
--
--   SELECT p.proname, p.proconfig
--     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname = 'public'
--      AND array_to_string(p.proconfig, ',') = 'search_path=' || chr(34) || chr(34)
--      AND position('check_user_has_access_to_tienda' in p.prosrc) > 0
--    ORDER BY 1;
--   -- las 4 rompen porque el guard ya no depende del search_path del llamador:
--   -- la comprobacion real es V2 (ejecutar), no el censo.
--
-- ============================================================================
-- BLOQUE DE REVERSION  (cuerpo ORIGINAL; solo si se aplico el patch)
-- ============================================================================
-- Ejecutar tal cual para volver al estado md5 438dbaec6f0fe94c23d4cb414cc41d89:
--
-- CREATE OR REPLACE FUNCTION public.check_user_has_access_to_tienda(
--     id_tienda_param bigint
-- )
-- RETURNS void
-- LANGUAGE plpgsql
-- AS $function$DECLARE
--     user_has_access boolean;
-- BEGIN
--     -- Verificar si el usuario tiene acceso a la tienda en cualquiera de los roles
--     SELECT EXISTS (
--         SELECT 1 FROM app_dat_vendedor WHERE uuid = auth.uid() AND id_tpv IN (
--             SELECT id FROM app_dat_tpv WHERE id_tienda = id_tienda_param
--         )
--         UNION
--         SELECT 1 FROM app_dat_almacenero WHERE uuid = auth.uid() AND id_almacen IN (
--             SELECT id FROM app_dat_almacen WHERE id_tienda = id_tienda_param
--         )
--         UNION
--         SELECT 1 FROM app_dat_supervisor WHERE uuid = auth.uid() AND id_tienda = id_tienda_param
--         UNION
--         SELECT 1 FROM auditor WHERE uuid = auth.uid() AND id_tienda = id_tienda_param
--         UNION
--         SELECT 1 FROM app_dat_gerente WHERE uuid = auth.uid() AND id_tienda = id_tienda_param
--         UNION
--         -- FASE 3: jefe de cocina / cocinero. Su ambito es la cocina,
--         -- y la cocina pertenece a una tienda.
--         SELECT 1 FROM app_dat_jefe_cocina jc
--           JOIN app_dat_cocina c ON c.id = jc.id_cocina
--          WHERE jc.uuid = auth.uid()
--            AND c.id_tienda = id_tienda_param
--            AND c.deleted_at IS NULL
--     ) INTO user_has_access;
--
--     -- Si no tiene acceso, lanzar error
--     IF NOT user_has_access THEN
--         RAISE EXCEPTION 'Acceso denegado: No tienes permisos para acceder a esta tienda';
--     END IF;
-- END;$function$;
--
-- Y despues:  SELECT md5(pg_get_functiondef('public.check_user_has_access_to_tienda(bigint)'::regprocedure));
--             -- debe volver a 438dbaec6f0fe94c23d4cb414cc41d89 (ver aviso CRLF arriba)
-- ============================================================================