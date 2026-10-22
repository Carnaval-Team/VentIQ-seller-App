-- ============================================================================
-- 45 · Guard seguro por search_path (C9)
--      public.fn_check_user_has_access_to_tienda_safe(bigint) -> void
-- ============================================================================
-- Fase 0.5 del plan `docs/PLAN_CONSUMO_INGREDIENTES_ELABORADOS_PRESENTACIONES.md`
-- (§3.1 C9, §6 Fase 0.5). Contexto duro: `docs/_analisis/VERIFICACION_PLAN_2.md`
-- §3 (bloque A2 / C9) y correcciones C9-a/C9-b.
--
-- ----------------------------------------------------------------------------
-- EL DEFECTO (C9), medido
-- ----------------------------------------------------------------------------
-- `check_user_has_access_to_tienda` (viva) NO tiene `SET search_path` propio
-- (`proconfig = null`) y su cuerpo resuelve **7 tablas sin calificar**:
-- `app_dat_vendedor`, `app_dat_tpv`, `app_dat_almacenero`, `app_dat_almacen`,
-- `app_dat_supervisor`, `auditor`, `app_dat_gerente`, `app_dat_jefe_cocina`,
-- `app_dat_cocina`.
--
-- Cualquier llamador con `SET search_path = ''` la invoca heredando el
-- `search_path` vacio ⇒ **42P01 `relation "app_dat_vendedor" does not exist`**
-- (la tabla SI existe en `public`). En cada proyecto hay 31 funciones `public`
-- con `search_path` vacio; 8 llaman al guard y **4 rompen**:
--
--   · fn_ejecutar_entrega_fisica_v2      (search_path = '')  -> 42P01
--   · fn_preview_entrega_fisica_v2       (search_path = '')  -> 42P01
--   · fn_registrar_venta_offline_v2      (search_path = '')  -> 42P01
--   · fn_registrar_venta_offline_v3      (search_path = '')  -> 42P01
--
-- y dos de esos ya los llama la app (`auto_sync_service.dart:4015`), asi que C9
-- no es latente: es un fallo vivo del camino offline (con fallbacks que no
-- reconocen 42P01, porque `_isRpcUnavailable` solo busca `pgrst202`).
--
-- ----------------------------------------------------------------------------
-- QUE CREA ESTE ARCHIVO
-- ----------------------------------------------------------------------------
-- **Solo** una funcion NUEVA, el gemelo calificado del guard:
--
--   public.fn_check_user_has_access_to_tienda_safe(id_tienda_param bigint)
--     RETURNS void
--     LANGUAGE plpgsql
--     SECURITY DEFINER
--     SET search_path = public, pg_catalog
--
-- Mismas 7 fuentes de rol, misma semantica y **mismo mensaje de error** que la
-- viva (`'Acceso denegado: No tienes permisos para acceder a esta tienda'`,
-- ERRCODE por defecto P0001). Todas las tablas van calificadas con `public.`
--
-- ----------------------------------------------------------------------------
-- QUE **NO** TOCA (regla dura del usuario)
-- ----------------------------------------------------------------------------
--   · NO reemplaza `check_user_has_access_to_tienda`: la viva queda intacta
--     (md5 de `pg_get_functiondef` = `438dbaec6f0fe94c23d4cb414cc41d89`).
--   · NO reemplaza `fn_ejecutar_entrega_fisica_v2` ni
--     `fn_preview_entrega_fisica_v2` ni `fn_registrar_venta_offline_v2/v3`.
--   · NO cambia firmas, GRANT ni comportamiento de nada existente.
--   · Los 4 llamadores rotos **siguen rotos** mientras no se aplique el patch
--     opcional `46_patch_guard_en_sitio.sql` (decision del usuario). Lo que
--     desbloquea este archivo es la cadena NUEVA (`_v2`/`_v3` de las tareas 6/7),
--     que llama a este guard seguro en vez de al vivo.
--
-- ----------------------------------------------------------------------------
-- EVIDENCIA MEDIDA EN PRODUCCION (`vsieeihstajlrdvpuooh`, via MCP lectura)
-- ----------------------------------------------------------------------------
-- E1 · `proconfig`/md5 de la viva:
--        check_user_has_access_to_tienda | proconfig null |
--        md5 = 438dbaec6f0fe94c23d4cb414cc41d89 | SECURITY INVOKER
--        proacl = {postgres,anon,authenticated,service_role}
--      (los mismos md5 en debug `qhprswhhfasrikhawjoz`: VERIFICACION_PLAN_2 A15)
--
-- E2 · 31 funciones `public` con `search_path` vacio en produccion:
--        select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--         where n.nspname='public'
--           and array_to_string(p.proconfig,',') = 'search_path='||chr(34)||chr(34);
--        -> 31
--
-- E3 · **42P01 reproducido en produccion** (mecanismo puro, solo lectura):
--        do $do$ declare n integer; begin
--          perform set_config('search_path','',false);
--          select count(*) into n from app_dat_vendedor;   -- sin calificar
--        end $do$;
--        -> ERROR 42P01: relation "app_dat_vendedor" does not exist
--
-- E4 · **La calificacion lo arregla** (mismo escenario, nombres con `public.`):
--        do $do$ declare n integer; begin
--          perform set_config('search_path','',false);
--          select count(*) into n from public.app_dat_vendedor;
--        end $do$;
--        -> OK, sin error
--
-- E5 · **El cuerpo exacto de `_safe` validado en produccion** bajo
--      `search_path = ''`, sustituyendo `auth.uid()` por un uuid real:
--        · vendedor 220da392-de30-4d8c-9e34-131264e4caee / tienda 222
--          -> EXISTS(...) = true   (y el DO no lanzo excepcion)
--        · uuid 00000000-0000-0000-0000-0000000000ff / tienda 222
--          -> EXISTS(...) = false  (el DO lanzo si hubiera dado true)
--
-- E6 · Las 7 tablas y las 9 columnas del guard existen en `public` (bigint/uuid,
--      `app_dat_cocina.deleted_at timestamptz`).
--
-- E7 · `to_regprocedure('public.fn_check_user_has_access_to_tienda_safe(bigint)')`
--      = NULL en produccion antes de este archivo ⇒ nada quedo aplicado.
--
-- ----------------------------------------------------------------------------
-- POR QUE `SECURITY DEFINER` NO CAMBIA EL RESULTADO (verificado)
-- ----------------------------------------------------------------------------
-- 5 de las 7 tablas tienen RLS activo (`app_dat_vendedor`, `app_dat_tpv`,
-- `app_dat_almacen`, `app_dat_almacenero`, `app_dat_gerente`), y `postgres`
-- (dueno y ejecutor de un DEFINER) no esta sujeto a RLS porque FORCE ROW LEVEL
-- SECURITY = false. La diferencia seria relevante **solo si las policies
-- filtraran filas**; medido: **las 8 policies de esas tablas tienen
-- `qual = true`** (rol `public`), es decir, son permisivas y no filtran nada.
-- Ademas el filtro del guard esta anclado a `uuid = auth.uid()`, que sigue
-- leyendo el JWT de la peticion (no del ejecutor). Conclusion: mismo resultado
-- con acceso y sin acceso (probado ademas en E5 y en 47 seccion C).
--
-- ----------------------------------------------------------------------------
-- COMPORTAMIENTO IDENTICO EN LOS BORDES
-- ----------------------------------------------------------------------------
--   · `id_tienda_param` NULL  -> EXISTS = false -> mismo mensaje que la viva.
--   · sin JWT (`auth.uid()` NULL) -> `uuid = NULL` -> false -> mismo mensaje.
--   · sin filas de rol -> mensaje unico identico (no se anaden ERRCODE nuevos).
--
-- ----------------------------------------------------------------------------
-- APLICACION
-- ----------------------------------------------------------------------------
-- Un solo CREATE OR REPLACE, idempotente y aditivo:
--   psql ... -f presentaciones_inventario/45_guard_search_path.sql
-- o pegarlo en el Editor SQL del proyecto (debug primero, produccion despues).
-- No depende de ningun otro archivo de la Fase 0.5.
--
-- PRUEBA: `presentaciones_inventario/47_tests_guard_search_path.sql`.
--   · Las secciones A/A2 y D de 47 se pueden correr incluso con el MCP de
--     produccion en modo lectura (`supabase_read_only_user`: no puede DDL).
--   · Las secciones B y C (DDL dentro de la transaccion) requieren un rol con
--     CREATE/EXECUTE: **debug** `qhprswhhfasrikhawjoz` o el Editor SQL.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_check_user_has_access_to_tienda_safe(
    id_tienda_param bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $function$
DECLARE
    user_has_access boolean;
BEGIN
    -- Copia literal del guard vivo con las 7 fuentes calificadas.
    -- Verificar si el usuario tiene acceso a la tienda en cualquiera de los roles.
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

    -- Si no tiene acceso, lanzar error (mismo texto exacto que la viva).
    IF NOT user_has_access THEN
        RAISE EXCEPTION 'Acceso denegado: No tienes permisos para acceder a esta tienda';
    END IF;
END;
$function$;

-- ----------------------------------------------------------------------------
-- Permisos: nada para PUBLIC/anon (es un guard interno; solo lo llaman objetos
-- `_v2`/`_v3` con EXECUTE propio).
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.fn_check_user_has_access_to_tienda_safe(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_check_user_has_access_to_tienda_safe(bigint) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_check_user_has_access_to_tienda_safe(bigint)
    TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_check_user_has_access_to_tienda_safe(bigint) IS
    'Fase 0.5 / C9: guard de acceso a tienda seguro por search_path. Copia calificada de public.check_user_has_access_to_tienda (mismas 7 fuentes de rol, mismo mensaje de error), con SECURITY DEFINER y SET search_path = public, pg_catalog, de modo que funciona aunque el llamador tenga search_path vacio. La funcion viva NO se toca; este guard solo lo usan los objetos nuevos _v2/_v3. Ver 46_patch_guard_en_sitio.sql (patch opcional, no aplicado) y 47_tests_guard_search_path.sql.';

-- ============================================================================
-- VERIFICACION (comentada; ejecutar despues de aplicar)
-- ============================================================================
--
-- V1 · La funcion existe con la firma, el modo y el search_path esperados:
--
--   SELECT p.proname,
--          pg_get_function_identity_arguments(p.oid) AS args,
--          p.prorettype::regtype                     AS ret,
--          p.prosecdef                               AS security_definer,
--          p.proconfig                               AS proconfig
--     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname = 'public'
--      AND p.proname = 'fn_check_user_has_access_to_tienda_safe';
--   -- esperado: (id_tienda_param bigint) | void | true | {search_path=public, pg_catalog}
--
-- V2 · Permisos (nada para PUBLIC/anon):
--
--   SELECT proacl FROM pg_proc
--    WHERE oid = 'public.fn_check_user_has_access_to_tienda_safe(bigint)'::regprocedure;
--   -- esperado: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
--
-- V3 · La viva sigue INTACTA (no la tocamos):
--
--   SELECT md5(pg_get_functiondef('public.check_user_has_access_to_tienda(bigint)'::regprocedure));
--   -- esperado: 438dbaec6f0fe94c23d4cb414cc41d89
--
-- V4 · ⭐ El guard seguro funciona bajo `search_path = ''` donde el vivo da 42P01
--      (sonda temporal, dentro de una transaccion; ver 47 seccion B):
--
--   BEGIN;
--   CREATE FUNCTION public._probe_guard_safe(p_id_tienda bigint) RETURNS void
--     LANGUAGE plpgsql SET search_path = '' AS $p$
--     BEGIN PERFORM public.fn_check_user_has_access_to_tienda_safe(p_id_tienda); END $p$;
--   SELECT set_config('request.jwt.claims',
--          json_build_object('sub', (SELECT v.uuid::text
--                                      FROM public.app_dat_vendedor v
--                                      JOIN public.app_dat_tpv t ON t.id = v.id_tpv
--                                     WHERE t.id_tienda = 222 LIMIT 1))::text, false);
--   SELECT public._probe_guard_safe(222);   -- OK, sin 42P01
--   SELECT set_config('request.jwt.claims',
--          json_build_object('sub','00000000-0000-0000-0000-0000000000ff')::text, false);
--   SELECT public._probe_guard_safe(222);   -- ERROR 'Acceso denegado: ...' (mismo texto)
--   DROP FUNCTION public._probe_guard_safe(bigint);
--   ROLLBACK;
--
-- V5 · Los 4 llamadores rotos siguen rotos mientras no se aplique el 46
--      (esto es lo esperado; el 42P01 es el estado actual de produccion):
--
--   SELECT public.fn_preview_entrega_fisica_v2(3, 3, 4, 1, null, null);
--   -- esperado hoy: ERROR 42P01 relation "app_dat_vendedor" does not exist
--
-- V6 · Nada aplicado por accidente si solo se corrio la parte de prueba:
--
--   SELECT to_regprocedure('public.fn_check_user_has_access_to_tienda_safe(bigint)') IS NULL
--          AS safe_ausente,
--          md5(pg_get_functiondef('public.check_user_has_access_to_tienda(bigint)'::regprocedure))
--            = '438dbaec6f0fe94c23d4cb414cc41d89' AS guard_viva_intacta;
-- ============================================================================