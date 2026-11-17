BEGIN;

-- BORRADOR PARCIAL M01-R0c (tablas de membresia de roles). NO EJECUTAR.
-- Baseline newa: app_dat_almacenero y app_dat_gerente con RLS pero ALL
-- public/true; app_dat_supervisor, auditor y app_dat_jefe_cocina sin RLS;
-- seg_roll con RLS pero ALL public/true (fuente de etiquetas de rol:
-- trabajadores.id_roll la referencia y 'Superadmin'/'Gerente General'
-- habilitan el bootstrap de tiendas, asi que tambien es raiz de confianza).
-- Modelo: membresia = alta/baja por policy, no UPDATE en sitio (salvo el flag
-- operativo es_jefe). Lectura: fila propia (uuid = auth.uid(), necesaria para
-- la deteccion de rol del cliente) + acceso de tienda. Escritura: solo
-- fn_config_tienda_puede_escribir del ambito derivado, con coherencia
-- trabajador<->ambito en INSERT (un trabajador de otra tienda no puede
-- quedar ligado a un almacen/cocina/tienda que no es la suya).
-- seg_roll: lectura authenticated de roles globales (id_tienda NULL) y de la
-- tienda propia; escritura por tienda solo admin, y filas globales solo
-- superadmin full. Solo denominacion/descripcion son editables directo.
-- DEPENDENCIAS: helpers de ambito del archivo R0c-infra (aplicar despues).
-- Las INVOKER fn_agregar_rol_trabajador/fn_eliminar_rol_trabajador/
-- fn_asignar_rol_almacenero siguen operando para gerente/dueño bajo policy;
-- fn_actualizar_datos_rol_trabajador (INVOKER) perdera las columnas de rol
-- hasta su conversion DEFINER (R0d), como ya quedo registrado en R0b.

SET LOCAL app.m01_r0c_roles_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r0c_roles_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador parcial R0c-roles: requiere revision del conjunto M01 y ejecucion manual en newa';
    END IF;
    IF has_schema_privilege('anon', 'public', 'CREATE')
       OR has_schema_privilege('authenticated', 'public', 'CREATE') THEN
        RAISE EXCEPTION 'public permite CREATE a roles no confiables; revisar antes de aplicar';
    END IF;
    IF to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL
       OR to_regprocedure('public.fn_config_tienda_puede_leer(bigint)') IS NULL
       OR to_regprocedure('public.fn_is_superadmin_full_access()') IS NULL
       OR to_regprocedure('public.fn_m01_personal_tienda_de_almacen(bigint)') IS NULL
       OR to_regprocedure('public.fn_m01_personal_tienda_de_cocina(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Faltan predicados S01/M01 o helpers de ambito; aplicar R0c-infra antes';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'fn_m01_personal_tienda_de_trabajador'
    ) THEN
        RAISE EXCEPTION 'Ya existe el helper de trabajador; revisar avances de newa';
    END IF;
    IF (SELECT count(*) FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'app_dat_almacenero'
          AND policyname IN ('almacenero')) <> 1
       OR (SELECT count(*) FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'app_dat_gerente'
          AND policyname IN ('geneente')) <> 1
       OR (SELECT count(*) FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'seg_roll'
          AND policyname IN ('seg_toll')) <> 1 THEN
        RAISE EXCEPTION 'Baseline de policies distinto al inspeccionado';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relname IN ('app_dat_supervisor', 'auditor', 'app_dat_jefe_cocina')
          AND c.relrowsecurity
    ) OR EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename IN ('app_dat_supervisor', 'auditor', 'app_dat_jefe_cocina')
    ) THEN
        RAISE EXCEPTION 'Baseline de supervisor/auditor/jefe_cocina distinto (esperado: sin RLS ni policies)';
    END IF;
END;
$preflight$;

CREATE FUNCTION public.fn_m01_personal_tienda_de_trabajador(
    p_id_trabajador bigint
)
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
    SELECT w.id_tienda FROM public.app_dat_trabajadores w WHERE w.id = p_id_trabajador;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_m01_personal_tienda_de_trabajador(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_is_superadmin_full_access() TO authenticated;

-- =====================================================
-- app_dat_almacenero (ambito = almacen -> tienda)
-- =====================================================

DROP POLICY "almacenero" ON public.app_dat_almacenero;

CREATE POLICY m01_almacenero_leer ON public.app_dat_almacenero
    FOR SELECT TO authenticated
    USING (
        uuid = auth.uid()
        OR public.fn_config_tienda_puede_leer(
            public.fn_m01_personal_tienda_de_almacen(id_almacen))
    );

CREATE POLICY m01_almacenero_insertar ON public.app_dat_almacenero
    FOR INSERT TO authenticated
    WITH CHECK (
        public.fn_config_tienda_puede_escribir(
            public.fn_m01_personal_tienda_de_almacen(id_almacen))
        AND (id_trabajador IS NULL
             OR public.fn_m01_personal_tienda_de_trabajador(id_trabajador)
                = public.fn_m01_personal_tienda_de_almacen(id_almacen))
    );

CREATE POLICY m01_almacenero_eliminar ON public.app_dat_almacenero
    FOR DELETE TO authenticated
    USING (
        public.fn_config_tienda_puede_escribir(
            public.fn_m01_personal_tienda_de_almacen(id_almacen))
    );

REVOKE ALL ON TABLE public.app_dat_almacenero FROM anon;
GRANT SELECT, INSERT, DELETE ON TABLE public.app_dat_almacenero TO authenticated;
REVOKE UPDATE ON TABLE public.app_dat_almacenero FROM authenticated;

-- =====================================================
-- app_dat_jefe_cocina (RLS estaba desactivado; ambito = cocina -> tienda)
-- =====================================================

ALTER TABLE public.app_dat_jefe_cocina ENABLE ROW LEVEL SECURITY;

CREATE POLICY m01_jefe_cocina_leer ON public.app_dat_jefe_cocina
    FOR SELECT TO authenticated
    USING (
        uuid = auth.uid()
        OR public.fn_config_tienda_puede_leer(
            public.fn_m01_personal_tienda_de_cocina(id_cocina))
    );

CREATE POLICY m01_jefe_cocina_insertar ON public.app_dat_jefe_cocina
    FOR INSERT TO authenticated
    WITH CHECK (
        public.fn_config_tienda_puede_escribir(
            public.fn_m01_personal_tienda_de_cocina(id_cocina))
        AND (id_trabajador IS NULL
             OR public.fn_m01_personal_tienda_de_trabajador(id_trabajador)
                = public.fn_m01_personal_tienda_de_cocina(id_cocina))
    );

CREATE POLICY m01_jefe_cocina_actualizar ON public.app_dat_jefe_cocina
    FOR UPDATE TO authenticated
    USING (
        public.fn_config_tienda_puede_escribir(
            public.fn_m01_personal_tienda_de_cocina(id_cocina)))
    WITH CHECK (
        public.fn_config_tienda_puede_escribir(
            public.fn_m01_personal_tienda_de_cocina(id_cocina)));

CREATE POLICY m01_jefe_cocina_eliminar ON public.app_dat_jefe_cocina
    FOR DELETE TO authenticated
    USING (
        public.fn_config_tienda_puede_escribir(
            public.fn_m01_personal_tienda_de_cocina(id_cocina))
    );

REVOKE ALL ON TABLE public.app_dat_jefe_cocina FROM anon;
GRANT SELECT, INSERT, DELETE ON TABLE public.app_dat_jefe_cocina TO authenticated;
REVOKE UPDATE ON TABLE public.app_dat_jefe_cocina FROM authenticated;
GRANT UPDATE (es_jefe) ON TABLE public.app_dat_jefe_cocina TO authenticated;

-- =====================================================
-- app_dat_supervisor y auditor (RLS estaba desactivado)
-- =====================================================

ALTER TABLE public.app_dat_supervisor ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.auditor ENABLE ROW LEVEL SECURITY;

CREATE POLICY m01_supervisor_leer ON public.app_dat_supervisor
    FOR SELECT TO authenticated
    USING (uuid = auth.uid() OR public.fn_config_tienda_puede_leer(id_tienda));

CREATE POLICY m01_supervisor_insertar ON public.app_dat_supervisor
    FOR INSERT TO authenticated
    WITH CHECK (
        public.fn_config_tienda_puede_escribir(id_tienda)
        AND (id_trabajador IS NULL
             OR public.fn_m01_personal_tienda_de_trabajador(id_trabajador) = id_tienda)
    );

CREATE POLICY m01_supervisor_eliminar ON public.app_dat_supervisor
    FOR DELETE TO authenticated
    USING (public.fn_config_tienda_puede_escribir(id_tienda));

CREATE POLICY m01_auditor_leer ON public.auditor
    FOR SELECT TO authenticated
    USING (uuid = auth.uid() OR public.fn_config_tienda_puede_leer(id_tienda));

CREATE POLICY m01_auditor_insertar ON public.auditor
    FOR INSERT TO authenticated
    WITH CHECK (
        public.fn_config_tienda_puede_escribir(id_tienda)
        AND (id_trabajador IS NULL
             OR public.fn_m01_personal_tienda_de_trabajador(id_trabajador) = id_tienda)
    );

CREATE POLICY m01_auditor_eliminar ON public.auditor
    FOR DELETE TO authenticated
    USING (public.fn_config_tienda_puede_escribir(id_tienda));

REVOKE ALL ON TABLE public.app_dat_supervisor FROM anon;
REVOKE ALL ON TABLE public.auditor FROM anon;
GRANT SELECT, INSERT, DELETE ON TABLE public.app_dat_supervisor TO authenticated;
GRANT SELECT, INSERT, DELETE ON TABLE public.auditor TO authenticated;
REVOKE UPDATE ON TABLE public.app_dat_supervisor FROM authenticated;
REVOKE UPDATE ON TABLE public.auditor FROM authenticated;

-- =====================================================
-- app_dat_gerente
-- =====================================================

DROP POLICY "geneente" ON public.app_dat_gerente;

CREATE POLICY m01_gerente_leer ON public.app_dat_gerente
    FOR SELECT TO authenticated
    USING (uuid = auth.uid() OR public.fn_config_tienda_puede_leer(id_tienda));

CREATE POLICY m01_gerente_insertar ON public.app_dat_gerente
    FOR INSERT TO authenticated
    WITH CHECK (
        public.fn_config_tienda_puede_escribir(id_tienda)
        AND (id_trabajador IS NULL
             OR public.fn_m01_personal_tienda_de_trabajador(id_trabajador) = id_tienda)
    );

CREATE POLICY m01_gerente_eliminar ON public.app_dat_gerente
    FOR DELETE TO authenticated
    USING (public.fn_config_tienda_puede_escribir(id_tienda));

REVOKE ALL ON TABLE public.app_dat_gerente FROM anon;
GRANT SELECT, INSERT, DELETE ON TABLE public.app_dat_gerente TO authenticated;
REVOKE UPDATE ON TABLE public.app_dat_gerente FROM authenticated;

-- =====================================================
-- seg_roll (etiquetas de rol; filas globales solo superadmin full)
-- =====================================================

DROP POLICY "seg_toll" ON public.seg_roll;

CREATE POLICY m01_seg_roll_leer ON public.seg_roll
    FOR SELECT TO authenticated
    USING (
        id_tienda IS NULL
        OR public.fn_config_tienda_puede_leer(id_tienda)
    );

CREATE POLICY m01_seg_roll_insertar ON public.seg_roll
    FOR INSERT TO authenticated
    WITH CHECK (
        public.fn_config_tienda_puede_escribir(id_tienda)
        OR (id_tienda IS NULL AND public.fn_is_superadmin_full_access())
    );

CREATE POLICY m01_seg_roll_actualizar ON public.seg_roll
    FOR UPDATE TO authenticated
    USING (
        public.fn_config_tienda_puede_escribir(id_tienda)
        OR (id_tienda IS NULL AND public.fn_is_superadmin_full_access()))
    WITH CHECK (
        public.fn_config_tienda_puede_escribir(id_tienda)
        OR (id_tienda IS NULL AND public.fn_is_superadmin_full_access()));

CREATE POLICY m01_seg_roll_eliminar ON public.seg_roll
    FOR DELETE TO authenticated
    USING (
        public.fn_config_tienda_puede_escribir(id_tienda)
        OR (id_tienda IS NULL AND public.fn_is_superadmin_full_access()));

REVOKE ALL ON TABLE public.seg_roll FROM anon;
REVOKE UPDATE ON TABLE public.seg_roll FROM authenticated;
GRANT UPDATE (denominacion, descripcion) ON TABLE public.seg_roll TO authenticated;

COMMIT;
