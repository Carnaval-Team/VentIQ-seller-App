BEGIN;

-- BORRADOR PARCIAL M01-R0b (policies de personal). NO EJECUTAR aisladamente.
-- Sustituye las policies publicas permisivas de app_dat_trabajadores y
-- app_dat_vendedor por policies acotadas a authenticated, y limita las
-- columnas actualizables directamente para que identidad (uuid/id_tienda/
-- id_roll/deleted_at) y vinculos (id_tpv/id_trabajador/user_mail/salarios)
-- solo puedan cambiarse por RPC privilegiada.
-- DEPENDENCIAS DURAS antes de aplicar:
--   * fn_config_tienda_puede_escribir / fn_config_tienda_puede_leer (S01).
--   * fn_m01_personal_reasignar_vendedor (R0b-RPC) si se revoca UPDATE de
--     id_tpv; si no, la reasignacion legitima queda sin via.
--   * R0d: crear_estructura_tienda es INVOKER; la policy INSERT de
--     trabajadores lo bloquea hasta que exista entrada protegida.
--   * fn_editar_trabajador_basico y fn_actualizar_datos_rol_trabajador son
--     INVOKER: perderan la capacidad de tocar columnas restringidas hasta
--     convertirse o sustituirse por rutas DEFINER validadas.
-- app_dat_recursos_humanos sigue SIN RLS (hallazgo de este corte); el helper
-- de lectura lo usa como fuente de pertenencia RH y debe protegerse en su
-- propio borrador antes de liberar M01.

SET LOCAL app.m01_r0b_policies_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r0b_policies_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador parcial R0b-policies: requiere revision del conjunto M01 y ejecucion manual en newa';
    END IF;
    IF has_schema_privilege('anon', 'public', 'CREATE')
       OR has_schema_privilege('authenticated', 'public', 'CREATE') THEN
        RAISE EXCEPTION 'public permite CREATE a roles no confiables; revisar antes de aplicar';
    END IF;
    IF to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL
       OR to_regprocedure('public.fn_config_tienda_puede_leer(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Faltan los predicados S01; no reemplazarlos por permisos genericos';
    END IF;
    IF to_regclass('public.app_dat_recursos_humanos') IS NULL THEN
        RAISE EXCEPTION 'No existe la fuente de pertenencia RH esperada';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN (
              'fn_m01_personal_es_recursos_humanos',
              'fn_m01_personal_tienda_para_vinculos',
              'fn_m01_personal_vendedor_id_tienda'
          )
    ) THEN
        RAISE EXCEPTION 'Ya existen helpers M01 de personal; revisar avances de newa';
    END IF;
    -- Baseline exacto de policies observado en newa; aborta si el remoto cambio.
    IF (SELECT count(*) FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'app_dat_trabajadores'
          AND policyname IN ('all workers', 'worker police select')) <> 2 THEN
        RAISE EXCEPTION 'Baseline de policies de trabajadores distinto al inspeccionado';
    END IF;
    IF (SELECT count(*) FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'app_dat_vendedor'
          AND policyname IN ('Open access to vendedor', 'all vednedor', 'select all')) <> 3 THEN
        RAISE EXCEPTION 'Baseline de policies de vendedor distinto al inspeccionado';
    END IF;
    IF to_regprocedure('public.fn_m01_personal_reasignar_vendedor(bigint,bigint)') IS NULL THEN
        RAISE WARNING 'RPC de reasignacion ausente: revocar UPDATE de id_tpv dejara sin via la reasignacion legitima';
    END IF;
END;
$preflight$;

-- =====================================================
-- Helpers de predicado (lectura y resolucion de ambito)
-- =====================================================

CREATE FUNCTION public.fn_m01_personal_es_recursos_humanos(
    p_id_tienda bigint
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
    SELECT p_id_tienda IS NOT NULL
       AND auth.uid() IS NOT NULL
       AND EXISTS (
           SELECT 1 FROM public.app_dat_recursos_humanos rh
           WHERE rh.id_tienda = p_id_tienda
             AND rh.uuid = auth.uid()
       );
$function$;

CREATE FUNCTION public.fn_m01_personal_tienda_para_vinculos(
    p_id_trabajador bigint,
    p_id_tpv bigint
)
RETURNS bigint
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_worker_store bigint;
    v_tpv_store bigint;
BEGIN
    IF p_id_trabajador IS NOT NULL THEN
        SELECT w.id_tienda INTO v_worker_store
        FROM public.app_dat_trabajadores w
        WHERE w.id = p_id_trabajador;
    END IF;
    IF p_id_tpv IS NOT NULL THEN
        SELECT t.id_tienda INTO v_tpv_store
        FROM public.app_dat_tpv t
        WHERE t.id = p_id_tpv;
    END IF;
    IF v_worker_store IS NOT NULL AND v_tpv_store IS NOT NULL
       AND v_worker_store IS DISTINCT FROM v_tpv_store THEN
        RETURN NULL;
    END IF;
    RETURN COALESCE(v_worker_store, v_tpv_store);
END;
$function$;

CREATE FUNCTION public.fn_m01_personal_vendedor_id_tienda(
    p_id_vendedor bigint
)
RETURNS bigint
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_id_trabajador bigint;
    v_id_tpv bigint;
BEGIN
    SELECT v.id_trabajador, v.id_tpv
    INTO v_id_trabajador, v_id_tpv
    FROM public.app_dat_vendedor v
    WHERE v.id = p_id_vendedor;
    RETURN public.fn_m01_personal_tienda_para_vinculos(v_id_trabajador, v_id_tpv);
END;
$function$;

-- Las policies invocan estos helpers como el rol consultante.
GRANT EXECUTE ON FUNCTION public.fn_m01_personal_es_recursos_humanos(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_m01_personal_tienda_para_vinculos(bigint, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_m01_personal_vendedor_id_tienda(bigint) TO authenticated;

-- =====================================================
-- app_dat_trabajadores
-- =====================================================

DROP POLICY "all workers" ON public.app_dat_trabajadores;
DROP POLICY "worker police select" ON public.app_dat_trabajadores;

CREATE POLICY m01_trabajadores_leer ON public.app_dat_trabajadores
    FOR SELECT TO authenticated
    USING (
        uuid = auth.uid()
        OR public.fn_config_tienda_puede_leer(id_tienda)
        OR public.fn_m01_personal_es_recursos_humanos(id_tienda)
    );

CREATE POLICY m01_trabajadores_insertar ON public.app_dat_trabajadores
    FOR INSERT TO authenticated
    WITH CHECK (public.fn_config_tienda_puede_escribir(id_tienda));

CREATE POLICY m01_trabajadores_actualizar ON public.app_dat_trabajadores
    FOR UPDATE TO authenticated
    USING (public.fn_config_tienda_puede_escribir(id_tienda))
    WITH CHECK (public.fn_config_tienda_puede_escribir(id_tienda));

CREATE POLICY m01_trabajadores_eliminar ON public.app_dat_trabajadores
    FOR DELETE TO authenticated
    USING (public.fn_config_tienda_puede_escribir(id_tienda));

REVOKE ALL ON TABLE public.app_dat_trabajadores FROM anon;

-- Identidad, rol, nomina y bajas solo por RPC privilegiada; el INVOKER
-- fn_editar_trabajador_basico conserva nombres/apellidos y el flag operativo.
REVOKE UPDATE ON TABLE public.app_dat_trabajadores FROM authenticated;
GRANT UPDATE (nombres, apellidos, maneja_apertura_control)
    ON TABLE public.app_dat_trabajadores TO authenticated;

-- =====================================================
-- app_dat_vendedor
-- =====================================================

DROP POLICY "Open access to vendedor" ON public.app_dat_vendedor;
DROP POLICY "all vednedor" ON public.app_dat_vendedor;
DROP POLICY "select all" ON public.app_dat_vendedor;

CREATE POLICY m01_vendedor_leer ON public.app_dat_vendedor
    FOR SELECT TO authenticated
    USING (
        uuid = auth.uid()
        OR public.fn_config_tienda_puede_leer(
            public.fn_m01_personal_vendedor_id_tienda(id))
    );

CREATE POLICY m01_vendedor_insertar ON public.app_dat_vendedor
    FOR INSERT TO authenticated
    WITH CHECK (
        public.fn_config_tienda_puede_escribir(
            public.fn_m01_personal_tienda_para_vinculos(id_trabajador, id_tpv))
    );

CREATE POLICY m01_vendedor_actualizar ON public.app_dat_vendedor
    FOR UPDATE TO authenticated
    USING (
        public.fn_config_tienda_puede_escribir(
            public.fn_m01_personal_vendedor_id_tienda(id)))
    WITH CHECK (
        public.fn_config_tienda_puede_escribir(
            public.fn_m01_personal_tienda_para_vinculos(id_trabajador, id_tpv)));

CREATE POLICY m01_vendedor_eliminar ON public.app_dat_vendedor
    FOR DELETE TO authenticated
    USING (
        public.fn_config_tienda_puede_escribir(
            public.fn_m01_personal_vendedor_id_tienda(id)));

REVOKE ALL ON TABLE public.app_dat_vendedor FROM anon;

-- id_tpv, uuid e id_trabajador solo por RPC (guarda R0b / rutas de rol);
-- quedan editables directamente los campos operativos de administracion.
REVOKE UPDATE ON TABLE public.app_dat_vendedor FROM authenticated;
GRANT UPDATE (numero_confirmacion, permitir_customizar_precio_venta)
    ON TABLE public.app_dat_vendedor TO authenticated;

COMMIT;
