-- ============================================================================
-- 47 · Tests transaccionales · Guard seguro por search_path (C9, Fase 0.5)
-- ============================================================================
-- Acompanan a `presentaciones_inventario/45_guard_search_path.sql` (funcion
-- nueva `_safe`) y al patch OPCIONAL `presentaciones_inventario/46_patch_guard_en_sitio.sql`.
--
-- ----------------------------------------------------------------------------
-- COMO SE CORREN
-- ----------------------------------------------------------------------------
-- Requieren un rol con CREATE en `public` y EXECUTE en el guard: **Supabase SQL
-- Editor** (postgres) o el proyecto **debug `qhprswhhfasrikhawjoz`**. Todas las
-- secciones salvo la D ocurren entre `BEGIN` y `ROLLBACK`: crean el guard
-- `_safe`, dos sondas temporales y (en B) aplican el patch del 46 dentro de la
-- transaccion; al final **no queda nada aplicado**.
--
--   · Seccion A  · reproduce el 42P01 con el guard VIVO (sin escribir nada).
--   · Seccion A2 · reproduce el mecanismo con `search_path=''` **sin DDL**: esta
--                  seccion si corre con el MCP de produccion en modo lectura.
--   · Seccion B  · aplica 45 + 46 dentro de la transaccion y comprueba que
--                  `fn_preview_entrega_fisica_v2(3,3,4,1,null,null)` deja de
--                  dar 42P01.
--   · Seccion C  · equivalencia `_safe` vs guard vivo (usuario CON acceso y SIN
--                  acceso) y el caso `search_path=''` (viva 42P01 / `_safe` OK).
--   · Seccion D  · reverificacion final: nada aplicado y md5 vivos intactos.
--                  Corre incluso en produccion con `supabase_read_only_user`.
--
-- LIMITACION MEDIDA (produccion `vsieeihstajlrdvpuooh`, MCP de sesion): el rol
-- es `supabase_read_only_user`, con `has_schema_privilege(current_user,'public','CREATE')=false`
-- y `has_function_privilege(current_user,'public.check_user_has_access_to_tienda(bigint)','EXECUTE')=false`.
-- Por eso, contra produccion solo se pudieron ejecutar A2 (mecanismo) y D
-- (reverificacion); A, B y C quedan listos para debug/Editor.
-- ============================================================================


-- ############################################################################
-- SECCION A · El sintoma con el guard VIVO: 42P01
-- ############################################################################

BEGIN;

DO $test$
DECLARE
    v_sqlstate text;
BEGIN
    BEGIN
        PERFORM public.fn_preview_entrega_fisica_v2(3, 3, 4, 1, null, null);
    EXCEPTION WHEN others THEN
        v_sqlstate := SQLSTATE;
    END;

    IF v_sqlstate IS DISTINCT FROM '42P01' THEN
        RAISE EXCEPTION
            'A1 FALLO: fn_preview_entrega_fisica_v2 debia dar 42P01 con el guard vivo; obtuve %',
            coalesce(v_sqlstate, 'sin error');
    END IF;
END $test$;

ROLLBACK;


-- ############################################################################
-- SECCION A2 · Mecanismo puro (SIN DDL; corre tambien en produccion read-only)
--   `search_path=''` + tabla sin calificar -> 42P01
--   `search_path=''` + tabla calificada   -> OK
-- ############################################################################

BEGIN;

DO $test$
DECLARE
    v_n      integer;
    v_state  text;
BEGIN
    PERFORM set_config('search_path', '', false);

    -- (a) sin calificar: debe fallar con 42P01 (la tabla SI existe en public)
    BEGIN
        SELECT count(*) INTO v_n FROM app_dat_vendedor;
    EXCEPTION WHEN others THEN
        v_state := SQLSTATE;
    END;

    IF v_state IS DISTINCT FROM '42P01' THEN
        RAISE EXCEPTION
            'A2a FALLO: esperaba 42P01 para `app_dat_vendedor` sin calificar; obtuve %',
            coalesce(v_state, 'sin error');
    END IF;

    -- (b) calificado: debe funcionar bajo el mismo search_path vacio
    SELECT count(*) INTO v_n FROM public.app_dat_vendedor;

    IF v_n IS NULL THEN
        RAISE EXCEPTION 'A2b FALLO: el conteo calificado no deberia ser NULL';
    END IF;
END $test$;

ROLLBACK;


-- ############################################################################
-- SECCION B · Con 45 + 46 aplicados en la transaccion: se acaba el 42P01
--   (la DDL va INLINE para que el test sea autocontenido; es copia exacta de
--    45_guard_search_path.sql y 46_patch_guard_en_sitio.sql)
-- ############################################################################

BEGIN;

-- B0 · guard nuevo `_safe` (copia de 45)
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
        SELECT 1 FROM public.app_dat_jefe_cocina jc
          JOIN public.app_dat_cocina c ON c.id = jc.id_cocina
         WHERE jc.uuid = auth.uid()
           AND c.id_tienda = id_tienda_param
           AND c.deleted_at IS NULL
    ) INTO user_has_access;

    IF NOT user_has_access THEN
        RAISE EXCEPTION 'Acceso denegado: No tienes permisos para acceder a esta tienda';
    END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_check_user_has_access_to_tienda_safe(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_check_user_has_access_to_tienda_safe(bigint) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_check_user_has_access_to_tienda_safe(bigint)
    TO authenticated, service_role;

-- B1 · patch opcional del guard vivo (copia de 46; dentro de la transaccion)
CREATE OR REPLACE FUNCTION public.check_user_has_access_to_tienda(
    id_tienda_param bigint
)
RETURNS void
LANGUAGE plpgsql
SET search_path = public, pg_catalog
AS $function$
DECLARE
    user_has_access boolean;
BEGIN
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
        SELECT 1 FROM public.app_dat_jefe_cocina jc
          JOIN public.app_dat_cocina c ON c.id = jc.id_cocina
         WHERE jc.uuid = auth.uid()
           AND c.id_tienda = id_tienda_param
           AND c.deleted_at IS NULL
    ) INTO user_has_access;

    IF NOT user_has_access THEN
        RAISE EXCEPTION 'Acceso denegado: No tienes permisos para acceder a esta tienda';
    END IF;
END;
$function$;

-- B2 · sonda con search_path vacio que llama al guard NUEVO
CREATE OR REPLACE FUNCTION public._probe_guard_safe(p_id_tienda bigint)
RETURNS void
LANGUAGE plpgsql
SET search_path = ''
AS $p$
BEGIN
    PERFORM public.fn_check_user_has_access_to_tienda_safe(p_id_tienda);
END;
$p$;

DO $test$
DECLARE
    v_uid      uuid;
    v_tienda   bigint;
    v_state    text;
    v_mensaje  text;
BEGIN
    -- usuario real con acceso a su tienda
    SELECT v.uuid, t.id_tienda
      INTO v_uid, v_tienda
      FROM public.app_dat_vendedor v
      JOIN public.app_dat_tpv t ON t.id = v.id_tpv
     WHERE v.uuid IS NOT NULL
     LIMIT 1;

    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'B2 FALLO: no hay ningun vendedor con tpv para probar';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', v_uid::text, false);
    PERFORM set_config('request.jwt.claims',
                       json_build_object('sub', v_uid::text)::text, false);

    -- (a) el preview roto ya NO debe dar 42P01 con el patch aplicado
    BEGIN
        PERFORM public.fn_preview_entrega_fisica_v2(3, 3, 4, 1, null, null);
    EXCEPTION WHEN others THEN
        v_state := SQLSTATE;
    END;

    IF v_state IS NOT DISTINCT FROM '42P01' THEN
        RAISE EXCEPTION
            'B2a FALLO: fn_preview_entrega_fisica_v2 sigue dando 42P01 con el patch';
    END IF;

    -- (b) el guard nuevo funciona bajo search_path = ''
    BEGIN
        PERFORM public._probe_guard_safe(v_tienda);
    EXCEPTION WHEN others THEN
        RAISE EXCEPTION
            'B2b FALLO: la sonda con search_path vacio no deberia fallar; sqlstate=% mensaje=%',
            SQLSTATE, SQLERRM;
    END;

    -- (c) sin acceso: mismo mensaje exacto que la viva
    PERFORM set_config('request.jwt.claim.sub',
                       '00000000-0000-0000-0000-0000000000ff', false);
    PERFORM set_config('request.jwt.claims',
                       json_build_object('sub', '00000000-0000-0000-0000-0000000000ff')::text, false);

    v_mensaje := NULL;
    BEGIN
        PERFORM public._probe_guard_safe(v_tienda);
    EXCEPTION WHEN others THEN
        v_mensaje := SQLERRM;
    END;

    IF v_mensaje IS NULL THEN
        RAISE EXCEPTION 'B2c FALLO: un uuid sin acceso no deberia pasar el guard';
    END IF;
    IF v_mensaje <> 'Acceso denegado: No tienes permisos para acceder a esta tienda' THEN
        RAISE EXCEPTION 'B2c FALLO: mensaje distinto: %', v_mensaje;
    END IF;
END $test$;

DROP FUNCTION public._probe_guard_safe(bigint);

-- B3 · dentro de la transaccion el guard vivo SI es el parcheado (md5 distinto)
DO $test$
BEGIN
    IF md5(pg_get_functiondef('public.check_user_has_access_to_tienda(bigint)'::regprocedure))
       = '438dbaec6f0fe94c23d4cb414cc41d89' THEN
        RAISE EXCEPTION 'B3 FALLO: el patch no esta vigente dentro de la transaccion';
    END IF;
END $test$;

ROLLBACK;


-- ############################################################################
-- SECCION C · Equivalencia `_safe` vs guard VIVO (el vivo sigue SIN patch)
--   (a) usuario CON acceso  -> los dos pasan
--   (b) usuario SIN acceso  -> los dos, mismo mensaje
--   (c) bajo search_path='': la viva 42P01, `_safe` OK  <- el arreglo
--
--   NOTA: si el patch 46 YA esta aplicado en la base, C-c fallara a proposito
--   (el guard vivo ya no dara 42P01). En ese caso, omitir el bloque (c).
-- ############################################################################

BEGIN;

-- C0 · solo el guard nuevo (no se toca el vivo en esta seccion)
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
        SELECT 1 FROM public.app_dat_jefe_cocina jc
          JOIN public.app_dat_cocina c ON c.id = jc.id_cocina
         WHERE jc.uuid = auth.uid()
           AND c.id_tienda = id_tienda_param
           AND c.deleted_at IS NULL
    ) INTO user_has_access;

    IF NOT user_has_access THEN
        RAISE EXCEPTION 'Acceso denegado: No tienes permisos para acceder a esta tienda';
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public._probe_guard_viva(p_id_tienda bigint)
RETURNS void
LANGUAGE plpgsql
SET search_path = ''
AS $p$
BEGIN
    PERFORM public.check_user_has_access_to_tienda(p_id_tienda);
END;
$p$;

CREATE OR REPLACE FUNCTION public._probe_guard_safe(p_id_tienda bigint)
RETURNS void
LANGUAGE plpgsql
SET search_path = ''
AS $p$
BEGIN
    PERFORM public.fn_check_user_has_access_to_tienda_safe(p_id_tienda);
END;
$p$;

DO $test$
DECLARE
    v_uid_ok    uuid;
    v_tienda    bigint;
    v_uid_ko    uuid := '00000000-0000-0000-0000-0000000000ff';
    v_msg_viva  text;
    v_msg_safe  text;
BEGIN
    SELECT v.uuid, t.id_tienda
      INTO v_uid_ok, v_tienda
      FROM public.app_dat_vendedor v
      JOIN public.app_dat_tpv t ON t.id = v.id_tpv
     WHERE v.uuid IS NOT NULL
     LIMIT 1;

    IF v_uid_ok IS NULL THEN
        RAISE EXCEPTION 'C FALLO: no hay ningun vendedor con tpv para probar';
    END IF;

    -- (a) usuario CON acceso: ninguno de los dos debe fallar
    PERFORM set_config('request.jwt.claim.sub', v_uid_ok::text, false);
    PERFORM set_config('request.jwt.claims',
                       json_build_object('sub', v_uid_ok::text)::text, false);

    v_msg_viva := NULL;
    BEGIN
        PERFORM public.check_user_has_access_to_tienda(v_tienda);
    EXCEPTION WHEN others THEN
        v_msg_viva := SQLERRM;
    END;
    v_msg_safe := NULL;
    BEGIN
        PERFORM public.fn_check_user_has_access_to_tienda_safe(v_tienda);
    EXCEPTION WHEN others THEN
        v_msg_safe := SQLERRM;
    END;

    IF v_msg_viva IS DISTINCT FROM v_msg_safe THEN
        RAISE EXCEPTION 'C-a FALLO (con acceso): viva=[%] safe=[%]',
            coalesce(v_msg_viva, '<sin error>'), coalesce(v_msg_safe, '<sin error>');
    END IF;
    IF v_msg_viva IS NOT NULL THEN
        RAISE EXCEPTION 'C-a FALLO: el usuario de prueba no deberia ser rechazado: %', v_msg_viva;
    END IF;

    -- (b) usuario SIN acceso: mismo rechazo, mismo mensaje
    PERFORM set_config('request.jwt.claim.sub', v_uid_ko::text, false);
    PERFORM set_config('request.jwt.claims',
                       json_build_object('sub', v_uid_ko::text)::text, false);

    v_msg_viva := NULL;
    BEGIN
        PERFORM public.check_user_has_access_to_tienda(v_tienda);
    EXCEPTION WHEN others THEN
        v_msg_viva := SQLERRM;
    END;
    v_msg_safe := NULL;
    BEGIN
        PERFORM public.fn_check_user_has_access_to_tienda_safe(v_tienda);
    EXCEPTION WHEN others THEN
        v_msg_safe := SQLERRM;
    END;

    IF v_msg_viva IS DISTINCT FROM v_msg_safe THEN
        RAISE EXCEPTION 'C-b FALLO (sin acceso): viva=[%] safe=[%]',
            coalesce(v_msg_viva, '<sin error>'), coalesce(v_msg_safe, '<sin error>');
    END IF;
    IF v_msg_viva IS DISTINCT FROM 'Acceso denegado: No tienes permisos para acceder a esta tienda' THEN
        RAISE EXCEPTION 'C-b FALLO: mensaje inesperado de la viva: %', coalesce(v_msg_viva, '<sin error>');
    END IF;

    -- (c) bajo search_path='' (llamador con SET search_path = ''):
    --     la viva muere con 42P01, la nueva pasa
    PERFORM set_config('request.jwt.claim.sub', v_uid_ok::text, false);
    PERFORM set_config('request.jwt.claims',
                       json_build_object('sub', v_uid_ok::text)::text, false);

    v_msg_viva := NULL;
    BEGIN
        PERFORM public._probe_guard_viva(v_tienda);
    EXCEPTION WHEN others THEN
        v_msg_viva := SQLSTATE;
    END;
    IF v_msg_viva IS DISTINCT FROM '42P01' THEN
        RAISE EXCEPTION 'C-c FALLO: la viva bajo search_path vacio debia dar 42P01; dio %',
            coalesce(v_msg_viva, '<sin error>');
    END IF;

    BEGIN
        PERFORM public._probe_guard_safe(v_tienda);
    EXCEPTION WHEN others THEN
        RAISE EXCEPTION 'C-c FALLO: la nueva bajo search_path vacio no deberia fallar: % (%)',
            SQLERRM, SQLSTATE;
    END;
END $test$;

DROP FUNCTION public._probe_guard_viva(bigint);
DROP FUNCTION public._probe_guard_safe(bigint);

ROLLBACK;


-- ############################################################################
-- SECCION D · Reverificacion final (SIN DDL; corre en produccion read-only)
--   Nada de 45/46 quedo aplicado y los md5 de las funciones vivas no cambiaron.
-- ############################################################################

SELECT
    to_regprocedure('public.fn_check_user_has_access_to_tienda_safe(bigint)') IS NULL
        AS safe_no_quedo_creada,
    md5(pg_get_functiondef('public.check_user_has_access_to_tienda(bigint)'::regprocedure))
        = '438dbaec6f0fe94c23d4cb414cc41d89'
        AS guard_viva_intacta,
    md5(pg_get_functiondef('public.fn_preview_entrega_fisica_v2(bigint,bigint,bigint,numeric,bigint,bigint)'::regprocedure))
        = 'c46c5d977095057a7f33b8f7b360e254'
        AS preview_entrega_v2_intacta,
    md5(pg_get_functiondef('public.fn_ejecutar_entrega_fisica_v2(bigint,bigint,bigint,numeric,integer,bigint,bigint,bigint,bigint,uuid,text)'::regprocedure))
        = '9edf415b400a467a1d6627a628fd3376'
        AS ejecutar_entrega_v2_intacta,
    (SELECT count(*)
       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND array_to_string(p.proconfig, ',') = 'search_path=' || chr(34) || chr(34))
        AS funciones_con_search_path_vacio;   -- esperado: 31
-- Esperado: true / true / true / true / 31

-- ============================================================================
-- RESULTADO MEDIDO EN PRODUCCION (`vsieeihstajlrdvpuooh`, MCP read-only)
-- ============================================================================
--   · A2: `do $do$ begin perform set_config('search_path','',false);
--          select count(*) from app_dat_vendedor; end $do$;`
--         -> ERROR 42P01 relation "app_dat_vendedor" does not exist  (CONFIRMADO)
--   · A2b: el mismo bloque con `public.app_dat_vendedor` -> OK sin error
--   · C-a (cuerpo calificado, uuid real 220da392-de30-4d8c-9e34-131264e4caee
--          de la tienda 222) -> EXISTS = true, sin excepcion
--   · C-b (uuid 00000000-0000-0000-0000-0000000000ff, tienda 222)
--         -> EXISTS = false, sin excepcion
--   · D (antes y despues): safe_no_quedo_creada = true;
--         guard_viva_intacta = true (438dbaec...); funciones_con_search_path_vacio = 31
--   · El propio `fn_preview_entrega_fisica_v2` NO se pudo ejecutar en produccion
--     por MCP: `42501 permission denied for function fn_preview_entrega_fisica_v2`
--     (el rol `supabase_read_only_user` no tiene EXECUTE). Seccion A/B pendientes
--     de debug `qhprswhhfasrikhawjoz` o del Editor SQL.
-- ============================================================================