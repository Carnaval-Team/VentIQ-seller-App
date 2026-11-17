BEGIN;

-- BORRADOR PARCIAL M01-R0d (entradas protegidas). NO EJECUTAR aisladamente.
-- Tres acciones coordinadas, sin tocar los cuerpos de las funciones legacy:
--   1) ALTER FUNCTION ... SET search_path = pg_catalog, public en las DEFINER
--      de asignacion/altas que no tenian path fijo (protege resolucion de
--      objetos sin romper referencias publicas no calificadas).
--   2) REVOKE EXECUTE de PUBLIC/anon/authenticated en esas DEFINER: ejecutan
--      como postgres y hoy cualquier cliente puede invocarlas sin guardas.
--      service_role conserva EXECUTE para llamadas servidor legadas.
--   3) Wrappers fn_m01_* validados (actor = auth.uid(), admin de la tienda
--      derivada, coherencia trabajador/TPV/cocina<->tienda, identidad del
--      creador) que delegan en la funcion legacy. El creador/ registrador
--      nunca se acepta como parametro: se fija a auth.uid().
-- DEPENDENCIAS: S01 + helpers M01 de ambito (R0b/R0c). La conversion de las
-- INVOKER fn_*_rol_trabajador queda para un corte posterior; este archivo
-- cubre las entradas DEFINER y el alta inicial de tiendas.
-- Tras aplicar: el cliente debe llamar a fn_m01_*; las llamadas directas a
-- las legacy quedaran denegadas (dependencia de despliegue ya registrada).

SET LOCAL app.m01_r0d_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r0d_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador parcial R0d: requiere revision del conjunto M01 y ejecucion manual en newa';
    END IF;
    IF has_schema_privilege('anon', 'public', 'CREATE')
       OR has_schema_privilege('authenticated', 'public', 'CREATE') THEN
        RAISE EXCEPTION 'public permite CREATE a roles no confiables; revisar antes de aplicar';
    END IF;
    IF to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL
       OR to_regprocedure('public.fn_is_superadmin_full_access()') IS NULL
       OR to_regprocedure('public.fn_m01_personal_tienda_de_trabajador(bigint)') IS NULL
       OR to_regprocedure('public.fn_m01_personal_tienda_de_almacen(bigint)') IS NULL
       OR to_regprocedure('public.fn_m01_personal_tienda_de_cocina(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Faltan predicados S01/M01; aplicar cortes previos antes';
    END IF;
    IF to_regprocedure('public.crear_estructura_tienda(uuid,character varying,character varying,character varying,character varying,character varying,character varying,character varying,numeric,numeric,jsonb,jsonb,jsonb,jsonb)') IS NULL THEN
        RAISE EXCEPTION 'No existe crear_estructura_tienda con la firma esperada';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname LIKE 'fn_m01\_%' ESCAPE '\'
          AND p.proname IN (
              'fn_m01_asignar_vendedor', 'fn_m01_desasignar_vendedor',
              'fn_m01_asignar_supervisor', 'fn_m01_desasignar_supervisor',
              'fn_m01_asignar_jefe_cocina', 'fn_m01_crear_tpv',
              'fn_m01_crear_gerente', 'fn_m01_crear_estructura_tienda'
          )
    ) THEN
        RAISE EXCEPTION 'Ya existen wrappers M01; revisar avances de newa';
    END IF;
END;
$preflight$;

-- =====================================================
-- 1) search_path fijo en DEFINER legacy sin el (o con 'public' debil)
-- =====================================================

ALTER FUNCTION public.crear_tpv_completo(bigint, bigint, character varying, jsonb, jsonb[], jsonb[], uuid) SET search_path = pg_catalog, public;
ALTER FUNCTION public.create_gerente_from_email(text, text, text, bigint) SET search_path = pg_catalog, public;
ALTER FUNCTION public.fn_asignar_vendedor(uuid, bigint, bigint, bigint) SET search_path = pg_catalog, public;
ALTER FUNCTION public.fn_desasignar_vendedor(uuid, bigint) SET search_path = pg_catalog, public;
ALTER FUNCTION public.fn_asignar_supervisor(uuid, bigint, bigint) SET search_path = pg_catalog, public;
ALTER FUNCTION public.fn_desasignar_supervisor(uuid, bigint) SET search_path = pg_catalog, public;
ALTER FUNCTION public.fn_asignar_jefe_cocina(uuid, bigint, bigint, boolean) SET search_path = pg_catalog, public;
ALTER FUNCTION public.fn_insertar_trabajador_basico(bigint, character varying, character varying, uuid, integer) SET search_path = pg_catalog, public;
ALTER FUNCTION public.fn_restaurar_trabajador(bigint, bigint) SET search_path = pg_catalog, public;
ALTER FUNCTION public.fn_hr_update_worker_salary(integer, integer, numeric, numeric, uuid, text, text, numeric) SET search_path = pg_catalog, public;
ALTER FUNCTION public.fn_is_superadmin_full_access() SET search_path = pg_catalog, public;
ALTER FUNCTION public.fn_user_is_dueno(bigint) SET search_path = pg_catalog, public;
ALTER FUNCTION public.fn_check_is_hr_user(uuid, integer) SET search_path = pg_catalog, public;
ALTER FUNCTION public.fn_hr_assert_access(bigint) SET search_path = pg_catalog, public;
-- INVOKER sin path propio: el wrapper deja search_path en pg_catalog y
-- app_dat_tienda deja de resolverse. public va despues de pg_catalog.
ALTER FUNCTION public.crear_estructura_tienda(uuid, character varying, character varying, character varying, character varying, character varying, character varying, character varying, numeric, numeric, jsonb, jsonb, jsonb, jsonb) SET search_path = pg_catalog, public;

-- =====================================================
-- 2) Las DEFINER sensibles dejan de ser invocables por clientes
-- =====================================================

REVOKE EXECUTE ON FUNCTION public.fn_asignar_vendedor(uuid, bigint, bigint, bigint) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_desasignar_vendedor(uuid, bigint) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_asignar_supervisor(uuid, bigint, bigint) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_desasignar_supervisor(uuid, bigint) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_asignar_jefe_cocina(uuid, bigint, bigint, boolean) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.create_gerente_from_email(text, text, text, bigint) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.crear_tpv_completo(bigint, bigint, character varying, jsonb, jsonb[], jsonb[], uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.crear_estructura_tienda(uuid, character varying, character varying, character varying, character varying, character varying, character varying, character varying, numeric, numeric, jsonb, jsonb, jsonb, jsonb) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.fn_asignar_vendedor(uuid, bigint, bigint, bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_desasignar_vendedor(uuid, bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_asignar_supervisor(uuid, bigint, bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_desasignar_supervisor(uuid, bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_asignar_jefe_cocina(uuid, bigint, bigint, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.create_gerente_from_email(text, text, text, bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.crear_tpv_completo(bigint, bigint, character varying, jsonb, jsonb[], jsonb[], uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.crear_estructura_tienda(uuid, character varying, character varying, character varying, character varying, character varying, character varying, character varying, numeric, numeric, jsonb, jsonb, jsonb, jsonb) TO service_role;

-- =====================================================
-- 3) Wrappers validados (actor auth.uid(); delegan en la legacy)
-- =====================================================

CREATE FUNCTION public.fn_m01_asignar_vendedor(
    p_uuid_usuario uuid,
    p_id_tienda bigint,
    p_id_tpv bigint DEFAULT NULL,
    p_id_trabajador bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
    IF auth.uid() IS NULL OR p_uuid_usuario IS NULL
       OR public.fn_config_tienda_puede_escribir(p_id_tienda) IS DISTINCT FROM true
       OR (p_id_trabajador IS NOT NULL
           AND public.fn_m01_personal_tienda_de_trabajador(p_id_trabajador) IS DISTINCT FROM p_id_tienda)
       OR (p_id_tpv IS NOT NULL
           AND (SELECT t.id_tienda FROM public.app_dat_tpv t WHERE t.id = p_id_tpv) IS DISTINCT FROM p_id_tienda) THEN
        RAISE EXCEPTION 'No autorizado para esta asignacion' USING ERRCODE = '42501';
    END IF;
    RETURN public.fn_asignar_vendedor(p_uuid_usuario, p_id_tienda, p_id_tpv, p_id_trabajador);
END;
$function$;

CREATE FUNCTION public.fn_m01_desasignar_vendedor(
    p_uuid_usuario uuid,
    p_id_tienda bigint
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
    IF auth.uid() IS NULL OR p_uuid_usuario IS NULL
       OR public.fn_config_tienda_puede_escribir(p_id_tienda) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'No autorizado para esta asignacion' USING ERRCODE = '42501';
    END IF;
    RETURN public.fn_desasignar_vendedor(p_uuid_usuario, p_id_tienda);
END;
$function$;

CREATE FUNCTION public.fn_m01_asignar_supervisor(
    p_uuid_usuario uuid,
    p_id_tienda bigint,
    p_id_trabajador bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
    IF auth.uid() IS NULL OR p_uuid_usuario IS NULL
       OR public.fn_config_tienda_puede_escribir(p_id_tienda) IS DISTINCT FROM true
       OR (p_id_trabajador IS NOT NULL
           AND public.fn_m01_personal_tienda_de_trabajador(p_id_trabajador) IS DISTINCT FROM p_id_tienda) THEN
        RAISE EXCEPTION 'No autorizado para esta asignacion' USING ERRCODE = '42501';
    END IF;
    RETURN public.fn_asignar_supervisor(p_uuid_usuario, p_id_tienda, p_id_trabajador);
END;
$function$;

CREATE FUNCTION public.fn_m01_desasignar_supervisor(
    p_uuid_usuario uuid,
    p_id_tienda bigint
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
    IF auth.uid() IS NULL OR p_uuid_usuario IS NULL
       OR public.fn_config_tienda_puede_escribir(p_id_tienda) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'No autorizado para esta asignacion' USING ERRCODE = '42501';
    END IF;
    RETURN public.fn_desasignar_supervisor(p_uuid_usuario, p_id_tienda);
END;
$function$;

CREATE FUNCTION public.fn_m01_asignar_jefe_cocina(
    p_uuid uuid,
    p_id_cocina bigint,
    p_id_trabajador bigint DEFAULT NULL,
    p_es_jefe boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
    IF auth.uid() IS NULL OR p_uuid IS NULL
       OR public.fn_config_tienda_puede_escribir(
           public.fn_m01_personal_tienda_de_cocina(p_id_cocina)) IS DISTINCT FROM true
       OR (p_id_trabajador IS NOT NULL
           AND public.fn_m01_personal_tienda_de_trabajador(p_id_trabajador)
               IS DISTINCT FROM public.fn_m01_personal_tienda_de_cocina(p_id_cocina)) THEN
        RAISE EXCEPTION 'No autorizado para esta asignacion' USING ERRCODE = '42501';
    END IF;
    RETURN public.fn_asignar_jefe_cocina(p_uuid, p_id_cocina, p_id_trabajador, p_es_jefe);
END;
$function$;

CREATE FUNCTION public.fn_m01_crear_tpv(
    p_id_tienda bigint,
    p_id_almacen bigint,
    p_denominacion character varying,
    p_configuracion jsonb DEFAULT NULL,
    p_vendedores_data jsonb[] DEFAULT NULL,
    p_dispositivos_data jsonb[] DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
    IF auth.uid() IS NULL
       OR public.fn_config_tienda_puede_escribir(p_id_tienda) IS DISTINCT FROM true
       OR (p_id_almacen IS NOT NULL
           AND public.fn_m01_personal_tienda_de_almacen(p_id_almacen) IS DISTINCT FROM p_id_tienda) THEN
        RAISE EXCEPTION 'No autorizado para crear este TPV' USING ERRCODE = '42501';
    END IF;
    RETURN public.crear_tpv_completo(
        p_id_tienda, p_id_almacen, p_denominacion,
        p_configuracion, p_vendedores_data, p_dispositivos_data,
        auth.uid()
    );
END;
$function$;

CREATE FUNCTION public.fn_m01_crear_gerente(
    p_email text,
    p_nombres text,
    p_apellidos text,
    p_id_tienda bigint
)
RETURNS TABLE(
    gerente_id bigint, trabajador_id bigint, uuid uuid, email text,
    nombres text, apellidos text, id_tienda bigint, created_at timestamp with time zone
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
    IF auth.uid() IS NULL
       OR public.fn_config_tienda_puede_escribir(p_id_tienda) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'No autorizado para crear este gerente' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    SELECT * FROM public.create_gerente_from_email(p_email, p_nombres, p_apellidos, p_id_tienda);
END;
$function$;

CREATE FUNCTION public.fn_m01_crear_estructura_tienda(
    p_denominacion_tienda character varying,
    p_direccion_tienda character varying,
    p_ubicacion_tienda character varying,
    p_pais character varying DEFAULT NULL,
    p_estado character varying DEFAULT NULL,
    p_nombre_pais character varying DEFAULT NULL,
    p_nombre_estado character varying DEFAULT NULL,
    p_latitude numeric DEFAULT NULL,
    p_longitude numeric DEFAULT NULL,
    p_almacenes_data jsonb DEFAULT NULL,
    p_tpv_data jsonb DEFAULT NULL,
    p_personal_data jsonb DEFAULT NULL,
    p_layouts_data jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_uuid uuid := auth.uid();
BEGIN
    -- Alta inicial: quien se registra todavia no pertenece a ninguna tienda.
    -- El creador es siempre auth.uid(). No se acepta un uuid ajeno y no se
    -- exige un rol previo. Las demas entradas siguen exigiendo admin de tienda.
    IF v_uuid IS NULL THEN
        RAISE EXCEPTION 'No autorizado para crear tiendas' USING ERRCODE = '42501';
    END IF;
    RETURN public.crear_estructura_tienda(
        v_uuid,
        p_denominacion_tienda, p_direccion_tienda, p_ubicacion_tienda,
        p_pais, p_estado, p_nombre_pais, p_nombre_estado,
        p_latitude, p_longitude,
        p_almacenes_data, p_tpv_data, p_personal_data, p_layouts_data
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_m01_asignar_vendedor(uuid, bigint, bigint, bigint) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_m01_desasignar_vendedor(uuid, bigint) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_m01_asignar_supervisor(uuid, bigint, bigint) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_m01_desasignar_supervisor(uuid, bigint) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_m01_asignar_jefe_cocina(uuid, bigint, bigint, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_m01_crear_tpv(bigint, bigint, character varying, jsonb, jsonb[], jsonb[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_m01_crear_gerente(text, text, text, bigint) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_m01_crear_estructura_tienda(character varying, character varying, character varying, character varying, character varying, character varying, character varying, numeric, numeric, jsonb, jsonb, jsonb, jsonb) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.fn_m01_asignar_vendedor(uuid, bigint, bigint, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_m01_desasignar_vendedor(uuid, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_m01_asignar_supervisor(uuid, bigint, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_m01_desasignar_supervisor(uuid, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_m01_asignar_jefe_cocina(uuid, bigint, bigint, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_m01_crear_tpv(bigint, bigint, character varying, jsonb, jsonb[], jsonb[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_m01_crear_gerente(text, text, text, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_m01_crear_estructura_tienda(character varying, character varying, character varying, character varying, character varying, character varying, character varying, numeric, numeric, jsonb, jsonb, jsonb, jsonb) TO authenticated;

COMMIT;
