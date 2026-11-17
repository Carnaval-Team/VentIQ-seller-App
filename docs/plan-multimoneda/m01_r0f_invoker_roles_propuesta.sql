BEGIN;

-- BORRADOR M01-R0f. NO EJECUTAR. Convierte las INVOKER de gestion de
-- trabajadores/roles en entradas DEFINER validadas, sin tocar sus cuerpos.
-- Baseline: las 4 son INVOKER (prosecdef=false) y devuelven jsonb.
-- Tras aplicar R0b/R0c, estas funciones pierden las columnas restringidas
-- (uuid, id_roll, id_tienda) y las membresias controladas: sus wrappers
-- restauran el flujo legitimo ejecutando como postgres tras validar.
-- Reglas: actor = auth.uid(); ambito derivado del trabajador en DB, nunca del
-- parametro p_id_tienda; p_uuid de edicion basica rechazado (la identidad es
-- fn_m01_personal_vincular_usuario_trabajador); p_usuario_uuid debe coincidir
-- con trabajadores.uuid; el rol 'dueno' no se concede ni se elimina aqui.
-- DEPENDENCIAS: R0a-R0e aplicados (helpers S01 + R0c).

SET LOCAL app.m01_r0f_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r0f_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador R0f: requiere revision y ejecucion manual en newa';
    END IF;
    IF to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL
       OR to_regprocedure('public.fn_m01_personal_tienda_de_trabajador(bigint)') IS NULL
       OR to_regprocedure('public.fn_m01_personal_tienda_de_almacen(bigint)') IS NULL
       OR to_regprocedure('public.fn_m01_personal_tienda_de_cocina(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Faltan helpers S01/M01; aplicar R0b-R0c antes';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN (
              'fn_m01_editar_trabajador_basico',
              'fn_m01_agregar_rol_trabajador',
              'fn_m01_actualizar_datos_rol_trabajador',
              'fn_m01_eliminar_rol_trabajador'
          )
    ) THEN
        RAISE EXCEPTION 'Ya existen wrappers R0f; revisar avances de newa';
    END IF;
END;
$preflight$;

-- Edicion basica: nombres/apellidos. Identidad solo por la RPC dedicada.

CREATE FUNCTION public.fn_m01_editar_trabajador_basico(
    p_trabajador_id bigint,
    p_nombres text,
    p_apellidos text,
    p_uuid uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_tienda bigint;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Actor no autenticado';
    END IF;
    IF p_uuid IS NOT NULL THEN
        RAISE EXCEPTION 'La identidad se gestiona por fn_m01_personal_vincular_usuario_trabajador';
    END IF;
    SELECT t.id_tienda INTO v_tienda
    FROM public.app_dat_trabajadores t
    WHERE t.id = p_trabajador_id AND t.deleted_at IS NULL
    FOR UPDATE OF t;
    IF v_tienda IS NULL THEN
        RAISE EXCEPTION 'Trabajador % inexistente o eliminado', p_trabajador_id;
    END IF;
    IF NOT public.fn_config_tienda_puede_escribir(v_tienda) THEN
        RAISE EXCEPTION 'Sin permiso de administracion en la tienda del trabajador';
    END IF;
    RETURN public.fn_editar_trabajador_basico(p_trabajador_id, p_nombres, p_apellidos, NULL);
END;
$function$;

-- Agregar rol: tienda y uuid derivados del trabajador, nunca del llamador.

CREATE FUNCTION public.fn_m01_agregar_rol_trabajador(
    p_trabajador_id bigint,
    p_id_tienda bigint,
    p_tipo_rol text,
    p_usuario_uuid uuid,
    p_tpv_id bigint DEFAULT NULL,
    p_almacen_id bigint DEFAULT NULL,
    p_numero_confirmacion text DEFAULT NULL,
    p_id_cocina bigint DEFAULT NULL,
    p_es_jefe_cocina boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_tienda bigint;
    v_uuid uuid;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Actor no autenticado';
    END IF;
    IF lower(coalesce(p_tipo_rol, '')) = 'dueno' THEN
        RAISE EXCEPTION 'El rol dueno no se concede por esta via';
    END IF;
    SELECT t.id_tienda, t.uuid INTO v_tienda, v_uuid
    FROM public.app_dat_trabajadores t
    WHERE t.id = p_trabajador_id AND t.deleted_at IS NULL
    FOR UPDATE OF t;
    IF v_tienda IS NULL THEN
        RAISE EXCEPTION 'Trabajador % inexistente o eliminado', p_trabajador_id;
    END IF;
    IF p_id_tienda IS DISTINCT FROM v_tienda
       OR p_usuario_uuid IS DISTINCT FROM v_uuid THEN
        RAISE EXCEPTION 'Tienda o uuid incoherentes con el trabajador en DB';
    END IF;
    IF NOT public.fn_config_tienda_puede_escribir(v_tienda) THEN
        RAISE EXCEPTION 'Sin permiso de administracion en la tienda del trabajador';
    END IF;
    IF p_tpv_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.app_dat_tpv
        WHERE id = p_tpv_id AND id_tienda = v_tienda AND deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'TPV % no pertenece a la tienda del trabajador', p_tpv_id;
    END IF;
    IF p_almacen_id IS NOT NULL
       AND public.fn_m01_personal_tienda_de_almacen(p_almacen_id) IS DISTINCT FROM v_tienda THEN
        RAISE EXCEPTION 'Almacen % no pertenece a la tienda del trabajador', p_almacen_id;
    END IF;
    IF p_id_cocina IS NOT NULL
       AND public.fn_m01_personal_tienda_de_cocina(p_id_cocina) IS DISTINCT FROM v_tienda THEN
        RAISE EXCEPTION 'Cocina % no pertenece a la tienda del trabajador', p_id_cocina;
    END IF;
    RETURN public.fn_agregar_rol_trabajador(
        p_trabajador_id, v_tienda, p_tipo_rol, v_uuid,
        p_tpv_id, p_almacen_id, p_numero_confirmacion, p_id_cocina, p_es_jefe_cocina
    );
END;
$function$;

-- Actualizar datos de rol: ambito derivado; coherencia de vinculos.

CREATE FUNCTION public.fn_m01_actualizar_datos_rol_trabajador(
    p_trabajador_id bigint,
    p_tipo_rol text,
    p_tpv_id bigint DEFAULT NULL,
    p_almacen_id bigint DEFAULT NULL,
    p_numero_confirmacion text DEFAULT NULL,
    p_id_cocina bigint DEFAULT NULL,
    p_es_jefe_cocina boolean DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_tienda bigint;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Actor no autenticado';
    END IF;
    IF lower(coalesce(p_tipo_rol, '')) = 'dueno' THEN
        RAISE EXCEPTION 'El rol dueno no se gestiona por esta via';
    END IF;
    SELECT t.id_tienda INTO v_tienda
    FROM public.app_dat_trabajadores t
    WHERE t.id = p_trabajador_id AND t.deleted_at IS NULL
    FOR UPDATE OF t;
    IF v_tienda IS NULL THEN
        RAISE EXCEPTION 'Trabajador % inexistente o eliminado', p_trabajador_id;
    END IF;
    IF NOT public.fn_config_tienda_puede_escribir(v_tienda) THEN
        RAISE EXCEPTION 'Sin permiso de administracion en la tienda del trabajador';
    END IF;
    IF p_tpv_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.app_dat_tpv
        WHERE id = p_tpv_id AND id_tienda = v_tienda AND deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'TPV % no pertenece a la tienda del trabajador', p_tpv_id;
    END IF;
    IF p_almacen_id IS NOT NULL
       AND public.fn_m01_personal_tienda_de_almacen(p_almacen_id) IS DISTINCT FROM v_tienda THEN
        RAISE EXCEPTION 'Almacen % no pertenece a la tienda del trabajador', p_almacen_id;
    END IF;
    IF p_id_cocina IS NOT NULL
       AND public.fn_m01_personal_tienda_de_cocina(p_id_cocina) IS DISTINCT FROM v_tienda THEN
        RAISE EXCEPTION 'Cocina % no pertenece a la tienda del trabajador', p_id_cocina;
    END IF;
    RETURN public.fn_actualizar_datos_rol_trabajador(
        p_trabajador_id, p_tipo_rol, p_tpv_id, p_almacen_id,
        p_numero_confirmacion, p_id_cocina, p_es_jefe_cocina
    );
END;
$function$;

-- Eliminar rol: ambito derivado; dueno no se elimina por esta via.

CREATE FUNCTION public.fn_m01_eliminar_rol_trabajador(
    p_trabajador_id bigint,
    p_tipo_rol text,
    p_id_cocina bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_tienda bigint;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Actor no autenticado';
    END IF;
    IF lower(coalesce(p_tipo_rol, '')) = 'dueno' THEN
        RAISE EXCEPTION 'El rol dueno no se gestiona por esta via';
    END IF;
    SELECT t.id_tienda INTO v_tienda
    FROM public.app_dat_trabajadores t
    WHERE t.id = p_trabajador_id AND t.deleted_at IS NULL
    FOR UPDATE OF t;
    IF v_tienda IS NULL THEN
        RAISE EXCEPTION 'Trabajador % inexistente o eliminado', p_trabajador_id;
    END IF;
    IF NOT public.fn_config_tienda_puede_escribir(v_tienda) THEN
        RAISE EXCEPTION 'Sin permiso de administracion en la tienda del trabajador';
    END IF;
    IF p_id_cocina IS NOT NULL
       AND public.fn_m01_personal_tienda_de_cocina(p_id_cocina) IS DISTINCT FROM v_tienda THEN
        RAISE EXCEPTION 'Cocina % no pertenece a la tienda del trabajador', p_id_cocina;
    END IF;
    RETURN public.fn_eliminar_rol_trabajador(p_trabajador_id, p_tipo_rol, p_id_cocina);
END;
$function$;

-- Direct legacy execution blocked for clients.

REVOKE EXECUTE ON FUNCTION public.fn_editar_trabajador_basico(bigint, text, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_agregar_rol_trabajador(bigint, bigint, text, uuid, bigint, bigint, text, bigint, boolean) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_actualizar_datos_rol_trabajador(bigint, text, bigint, bigint, text, bigint, boolean) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_eliminar_rol_trabajador(bigint, text, bigint) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.fn_m01_editar_trabajador_basico(bigint, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_m01_agregar_rol_trabajador(bigint, bigint, text, uuid, bigint, bigint, text, bigint, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_m01_actualizar_datos_rol_trabajador(bigint, text, bigint, bigint, text, bigint, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_m01_eliminar_rol_trabajador(bigint, text, bigint) TO authenticated;

COMMIT;
