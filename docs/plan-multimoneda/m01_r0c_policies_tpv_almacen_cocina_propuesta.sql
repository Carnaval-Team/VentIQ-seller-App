BEGIN;

-- BORRADOR PARCIAL M01-R0c (infraestructura TPV/almacen/cocina). NO EJECUTAR.
-- Sustituye las policies publicas permisivas de app_dat_tpv y app_dat_almacen
-- y activa RLS en app_dat_cocina (baseline newa: tpv 2 policies public/true,
-- almacen 1 ALL public/true, cocina sin RLS). Las tres se acotan por
-- id_tienda: lectura con fn_config_tienda_puede_leer (vendedor, almacenero y
-- cocina la necesitan para operar) y escritura con fn_config_tienda_puede_escribir.
-- Las ligas estructurales (id_tienda, id_almacen, deleted_at) quedan fuera de
-- la actualizacion directa: se exige coherencia almacen<->tienda en INSERT y
-- esas columnas solo las cambian rutas privilegiadas (crear_tpv_completo y
-- futuras RPC validadas). UPDATE directo solo para campos operativos.
-- DEPENDENCIAS: crear_estructura_tienda es INVOKER y crea almacenes/TPV de
-- tiendas nuevas; las policies INSERT lo bloquean hasta R0d. Las
-- fn_admin_caja_tpv_*_offline son DEFINER y siguen operando (quedan por
-- endurecer en R0e). El helper de ambito por almacen/cocina lo consumen
-- tambien las policies de roles del siguiente archivo.

SET LOCAL app.m01_r0c_infra_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r0c_infra_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador parcial R0c-infra: requiere revision del conjunto M01 y ejecucion manual en newa';
    END IF;
    IF has_schema_privilege('anon', 'public', 'CREATE')
       OR has_schema_privilege('authenticated', 'public', 'CREATE') THEN
        RAISE EXCEPTION 'public permite CREATE a roles no confiables; revisar antes de aplicar';
    END IF;
    IF to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL
       OR to_regprocedure('public.fn_config_tienda_puede_leer(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Faltan los predicados S01';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN (
              'fn_m01_personal_tienda_de_almacen',
              'fn_m01_personal_tienda_de_cocina'
          )
    ) THEN
        RAISE EXCEPTION 'Ya existen helpers M01 de ambito; revisar avances de newa';
    END IF;
    IF (SELECT count(*) FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'app_dat_tpv'
          AND policyname IN ('Open access to tpv', 'all on tpv')) <> 2 THEN
        RAISE EXCEPTION 'Baseline de policies de tpv distinto al inspeccionado';
    END IF;
    IF (SELECT count(*) FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'app_dat_almacen'
          AND policyname IN ('almacne')) <> 1 THEN
        RAISE EXCEPTION 'Baseline de policies de almacen distinto al inspeccionado';
    END IF;
    IF (SELECT relrowsecurity FROM pg_class
        WHERE oid = 'public.app_dat_cocina'::regclass) IS DISTINCT FROM false
       OR EXISTS (
           SELECT 1 FROM pg_policies
           WHERE schemaname = 'public' AND tablename = 'app_dat_cocina'
       ) THEN
        RAISE EXCEPTION 'Baseline de cocina distinto al inspeccionado (esperado: sin RLS y sin policies)';
    END IF;
END;
$preflight$;

-- Helpers de ambito derivado (los usan estas policies y las de roles R0c).

CREATE FUNCTION public.fn_m01_personal_tienda_de_almacen(
    p_id_almacen bigint
)
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
    SELECT a.id_tienda FROM public.app_dat_almacen a WHERE a.id = p_id_almacen;
$function$;

CREATE FUNCTION public.fn_m01_personal_tienda_de_cocina(
    p_id_cocina bigint
)
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
    SELECT c.id_tienda FROM public.app_dat_cocina c WHERE c.id = p_id_cocina;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_m01_personal_tienda_de_almacen(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_m01_personal_tienda_de_cocina(bigint) TO authenticated;

-- =====================================================
-- app_dat_tpv
-- =====================================================

DROP POLICY "Open access to tpv" ON public.app_dat_tpv;
DROP POLICY "all on tpv" ON public.app_dat_tpv;

CREATE POLICY m01_tpv_leer ON public.app_dat_tpv
    FOR SELECT TO authenticated
    USING (public.fn_config_tienda_puede_leer(id_tienda));

CREATE POLICY m01_tpv_insertar ON public.app_dat_tpv
    FOR INSERT TO authenticated
    WITH CHECK (
        public.fn_config_tienda_puede_escribir(id_tienda)
        AND (id_almacen IS NULL
             OR public.fn_m01_personal_tienda_de_almacen(id_almacen) = id_tienda)
    );

CREATE POLICY m01_tpv_actualizar ON public.app_dat_tpv
    FOR UPDATE TO authenticated
    USING (public.fn_config_tienda_puede_escribir(id_tienda))
    WITH CHECK (
        public.fn_config_tienda_puede_escribir(id_tienda)
        AND (id_almacen IS NULL
             OR public.fn_m01_personal_tienda_de_almacen(id_almacen) = id_tienda)
    );

CREATE POLICY m01_tpv_eliminar ON public.app_dat_tpv
    FOR DELETE TO authenticated
    USING (public.fn_config_tienda_puede_escribir(id_tienda));

REVOKE ALL ON TABLE public.app_dat_tpv FROM anon;

REVOKE UPDATE ON TABLE public.app_dat_tpv FROM authenticated;
GRANT UPDATE (denominacion, modo_servicentro, servicentro_columnas)
    ON TABLE public.app_dat_tpv TO authenticated;

-- =====================================================
-- app_dat_almacen
-- =====================================================

DROP POLICY "almacne" ON public.app_dat_almacen;

CREATE POLICY m01_almacen_leer ON public.app_dat_almacen
    FOR SELECT TO authenticated
    USING (public.fn_config_tienda_puede_leer(id_tienda));

CREATE POLICY m01_almacen_insertar ON public.app_dat_almacen
    FOR INSERT TO authenticated
    WITH CHECK (public.fn_config_tienda_puede_escribir(id_tienda));

CREATE POLICY m01_almacen_actualizar ON public.app_dat_almacen
    FOR UPDATE TO authenticated
    USING (public.fn_config_tienda_puede_escribir(id_tienda))
    WITH CHECK (public.fn_config_tienda_puede_escribir(id_tienda));

CREATE POLICY m01_almacen_eliminar ON public.app_dat_almacen
    FOR DELETE TO authenticated
    USING (public.fn_config_tienda_puede_escribir(id_tienda));

REVOKE ALL ON TABLE public.app_dat_almacen FROM anon;

REVOKE UPDATE ON TABLE public.app_dat_almacen FROM authenticated;
GRANT UPDATE (denominacion, direccion, ubicacion, es_cocina)
    ON TABLE public.app_dat_almacen TO authenticated;

-- =====================================================
-- app_dat_cocina (RLS estaba desactivado)
-- =====================================================

ALTER TABLE public.app_dat_cocina ENABLE ROW LEVEL SECURITY;

CREATE POLICY m01_cocina_leer ON public.app_dat_cocina
    FOR SELECT TO authenticated
    USING (public.fn_config_tienda_puede_leer(id_tienda));

CREATE POLICY m01_cocina_insertar ON public.app_dat_cocina
    FOR INSERT TO authenticated
    WITH CHECK (
        public.fn_config_tienda_puede_escribir(id_tienda)
        AND (id_almacen IS NULL
             OR public.fn_m01_personal_tienda_de_almacen(id_almacen) = id_tienda)
    );

CREATE POLICY m01_cocina_actualizar ON public.app_dat_cocina
    FOR UPDATE TO authenticated
    USING (public.fn_config_tienda_puede_escribir(id_tienda))
    WITH CHECK (
        public.fn_config_tienda_puede_escribir(id_tienda)
        AND (id_almacen IS NULL
             OR public.fn_m01_personal_tienda_de_almacen(id_almacen) = id_tienda)
    );

CREATE POLICY m01_cocina_eliminar ON public.app_dat_cocina
    FOR DELETE TO authenticated
    USING (public.fn_config_tienda_puede_escribir(id_tienda));

REVOKE ALL ON TABLE public.app_dat_cocina FROM anon;

REVOKE UPDATE ON TABLE public.app_dat_cocina FROM authenticated;
GRANT UPDATE (denominacion, descripcion, impresora, orden, activa)
    ON TABLE public.app_dat_cocina TO authenticated;

COMMIT;
