BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
DECLARE
    v_obj record;
    v_oid oid;
BEGIN
    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION 'Ejecutar la propuesta revisada como postgres para conservar propietarios y privilegios esperados';
    END IF;

    IF current_setting('app.config_tienda_rls_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Propuesta no autorizada: revisar y probar antes de establecer app.config_tienda_rls_approved=yes';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_class
        WHERE oid = 'public.app_dat_configuracion_tienda'::regclass
          AND relowner = (SELECT oid FROM pg_roles WHERE rolname = 'postgres')
          AND NOT relrowsecurity
    ) THEN
        RAISE EXCEPTION 'La tabla no coincide con el estado inspeccionado en newa; revisar antes de migrar';
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'app_dat_configuracion_tienda'
    ) THEN
        RAISE EXCEPTION 'Existen policies no revisadas en configuracion_tienda';
    END IF;

    IF has_schema_privilege('anon', 'public', 'CREATE')
       OR has_schema_privilege('authenticated', 'public', 'CREATE') THEN
        RAISE EXCEPTION 'public permite CREATE a roles no confiables; revisar search_path antes de migrar';
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN (
              'fn_config_tienda_puede_leer',
              'fn_config_tienda_puede_escribir',
              'fn_config_tienda_exigir_lectura'
          )
    ) THEN
        RAISE EXCEPTION 'Los nombres de helpers propuestos ya existen; no sobrescribir sin revision';
    END IF;

    FOR v_obj IN
        SELECT * FROM (VALUES
            ('public.sync_bundle(bigint,bigint)', ARRAY['555cc2eb80c80d1b42630e059be2b810']),
            ('public.fn_obtener_licencia_firmada(bigint)', ARRAY['05d6925a69a20a808f1d10dfcd53f7aa']),
            ('public.fn_moneda_consolidacion(bigint)', ARRAY['132b5269a00df2573d632fe81bad29f2'])
        ) AS expected(signature, expected_hashes)
    LOOP
        v_oid := to_regprocedure(v_obj.signature);
        IF v_oid IS NULL THEN
            RAISE EXCEPTION 'Falta funcion esperada: %', v_obj.signature;
        END IF;
        IF NOT (md5(pg_get_functiondef(v_oid)) = ANY(v_obj.expected_hashes)) THEN
            RAISE EXCEPTION 'Definicion distinta de la inspeccionada: %. No parchear automaticamente', v_obj.signature;
        END IF;
    END LOOP;
END;
$preflight$;

CREATE FUNCTION public.fn_config_tienda_puede_escribir(p_id_tienda bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
    SELECT p_id_tienda IS NOT NULL
       AND auth.uid() IS NOT NULL
       AND (
           EXISTS (
               SELECT 1 FROM public.app_dat_dueno d
               WHERE d.id_tienda = p_id_tienda AND d.uuid = auth.uid()
           )
           OR EXISTS (
               SELECT 1 FROM public.app_dat_gerente g
               WHERE g.id_tienda = p_id_tienda AND g.uuid = auth.uid()
           )
           OR EXISTS (
               SELECT 1 FROM public.app_dat_superadmin s
               WHERE s.uuid = auth.uid() AND s.activo = true AND s.nivel_acceso = 1
           )
       );
$function$;

CREATE FUNCTION public.fn_config_tienda_puede_leer(p_id_tienda bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
    SELECT p_id_tienda IS NOT NULL
       AND auth.uid() IS NOT NULL
       AND (
           public.fn_config_tienda_puede_escribir(p_id_tienda)
           OR EXISTS (
               SELECT 1 FROM public.app_dat_supervisor s
               WHERE s.id_tienda = p_id_tienda AND s.uuid = auth.uid()
           )
           OR EXISTS (
               SELECT 1 FROM public.auditor a
               WHERE a.id_tienda = p_id_tienda AND a.uuid = auth.uid()
           )
           OR EXISTS (
               SELECT 1 FROM public.app_dat_vendedor v
               JOIN public.app_dat_tpv t ON t.id = v.id_tpv
               WHERE t.id_tienda = p_id_tienda AND v.uuid = auth.uid()
           )
           OR EXISTS (
               SELECT 1 FROM public.app_dat_almacenero a
               JOIN public.app_dat_almacen al ON al.id = a.id_almacen
               WHERE al.id_tienda = p_id_tienda AND a.uuid = auth.uid()
                 AND al.deleted_at IS NULL
           )
           OR EXISTS (
               SELECT 1 FROM public.app_dat_jefe_cocina j
               JOIN public.app_dat_cocina c ON c.id = j.id_cocina
               WHERE c.id_tienda = p_id_tienda AND j.uuid = auth.uid()
                 AND c.deleted_at IS NULL
           )
       );
$function$;

CREATE FUNCTION public.fn_config_tienda_exigir_lectura(p_id_tienda bigint)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
    IF auth.role() = 'service_role' THEN
        RETURN;
    END IF;
    IF NOT public.fn_config_tienda_puede_leer(p_id_tienda) THEN
        RAISE EXCEPTION 'Acceso denegado a configuracion de tienda' USING ERRCODE = '42501';
    END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_config_tienda_puede_escribir(bigint) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_config_tienda_puede_leer(bigint) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_config_tienda_exigir_lectura(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_config_tienda_puede_escribir(bigint) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_config_tienda_puede_leer(bigint) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_config_tienda_exigir_lectura(bigint) TO authenticated, service_role;

ALTER TABLE public.app_dat_configuracion_tienda ENABLE ROW LEVEL SECURITY;

CREATE POLICY config_tienda_select ON public.app_dat_configuracion_tienda
    FOR SELECT TO authenticated
    USING (public.fn_config_tienda_puede_leer(id_tienda));

CREATE POLICY config_tienda_insert ON public.app_dat_configuracion_tienda
    FOR INSERT TO authenticated
    WITH CHECK (public.fn_config_tienda_puede_escribir(id_tienda));

CREATE POLICY config_tienda_update ON public.app_dat_configuracion_tienda
    FOR UPDATE TO authenticated
    USING (public.fn_config_tienda_puede_escribir(id_tienda))
    WITH CHECK (public.fn_config_tienda_puede_escribir(id_tienda));

CREATE POLICY config_tienda_delete ON public.app_dat_configuracion_tienda
    FOR DELETE TO authenticated
    USING (false);

REVOKE ALL ON TABLE public.app_dat_configuracion_tienda FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.app_dat_configuracion_tienda TO authenticated;

DO $guard_rpc$
DECLARE
    v_obj record;
    v_oid oid;
    v_def text;
    v_source text;
    v_new_source text;
    v_new_def text;
    v_guard text;
    v_language text;
BEGIN
    FOR v_obj IN
        SELECT * FROM (VALUES
            ('public.sync_bundle(bigint,bigint)', 'id_tienda_param'),
            ('public.fn_obtener_licencia_firmada(bigint)', 'p_id_tienda'),
            ('public.fn_moneda_consolidacion(bigint)', 'p_id_tienda')
        ) AS guarded(signature, store_argument)
    LOOP
        v_oid := v_obj.signature::regprocedure;
        SELECT pg_get_functiondef(p.oid), p.prosrc, l.lanname
        INTO v_def, v_source, v_language
        FROM pg_proc p JOIN pg_language l ON l.oid = p.prolang
        WHERE p.oid = v_oid;

        v_guard := format('    PERFORM public.fn_config_tienda_exigir_lectura(%I);', v_obj.store_argument);

        IF v_obj.signature = 'public.sync_bundle(bigint,bigint)' THEN
            v_guard := v_guard || E'\n' || $guard$
    IF id_tpv_param IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.app_dat_tpv t
        WHERE t.id = id_tpv_param AND t.id_tienda = id_tienda_param
    ) THEN
        RAISE EXCEPTION 'TPV no pertenece a la tienda solicitada' USING ERRCODE = '42501';
    END IF;
$guard$;
        END IF;

        IF v_language = 'plpgsql' THEN
            v_new_source := regexp_replace(
                v_source,
                E'(^|\n)([ \t]*)BEGIN([ \t]*\r?\n)',
                E'\\1\\2BEGIN\\3' || v_guard || E'\n',
                'i'
            );
            IF v_new_source = v_source THEN
                RAISE EXCEPTION 'No se encontro BEGIN principal en %', v_obj.signature;
            END IF;
            v_new_def := replace(v_def, v_source, v_new_source);
        ELSIF v_language = 'sql' AND v_obj.signature = 'public.fn_moneda_consolidacion(bigint)' THEN
            v_new_source := E'\n#variable_conflict use_column\nBEGIN\n'
                || v_guard || E'\n    RETURN QUERY\n' || v_source || E'\nEND;\n';
            v_new_def := replace(v_def, v_source, v_new_source);
            v_new_def := replace(v_new_def, E'LANGUAGE sql\n', E'LANGUAGE plpgsql\n');
        ELSE
            RAISE EXCEPTION 'Lenguaje no previsto en %', v_obj.signature;
        END IF;

        IF v_new_def = v_def OR position(v_guard IN v_new_def) = 0 THEN
            RAISE EXCEPTION 'No se construyo guarda verificable en %', v_obj.signature;
        END IF;
        EXECUTE v_new_def;
        EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', v_obj.signature);
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', v_obj.signature);
    END LOOP;
END;
$guard_rpc$;

DO $postflight$
DECLARE
    v_role text;
    v_privilege text;
    v_signature text;
BEGIN
    FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
        FOREACH v_privilege IN ARRAY ARRAY['DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'] LOOP
            IF has_table_privilege(v_role, 'public.app_dat_configuracion_tienda', v_privilege) THEN
                RAISE EXCEPTION 'Permiso efectivo residual: % %', v_role, v_privilege;
            END IF;
        END LOOP;
    END LOOP;
    FOREACH v_privilege IN ARRAY ARRAY['SELECT', 'INSERT', 'UPDATE'] LOOP
        IF has_table_privilege('anon', 'public.app_dat_configuracion_tienda', v_privilege) THEN
            RAISE EXCEPTION 'anon conserva permiso efectivo %', v_privilege;
        END IF;
    END LOOP;
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.app_dat_configuracion_tienda'::regclass) THEN
        RAISE EXCEPTION 'RLS no quedo activado';
    END IF;
    FOREACH v_signature IN ARRAY ARRAY[
        'public.sync_bundle(bigint,bigint)',
        'public.fn_obtener_licencia_firmada(bigint)',
        'public.fn_moneda_consolidacion(bigint)',
        'public.fn_config_tienda_puede_leer(bigint)',
        'public.fn_config_tienda_puede_escribir(bigint)',
        'public.fn_config_tienda_exigir_lectura(bigint)'
    ] LOOP
        IF has_function_privilege('anon', v_signature, 'EXECUTE') THEN
            RAISE EXCEPTION 'anon conserva EXECUTE efectivo en %', v_signature;
        END IF;
    END LOOP;
END;
$postflight$;

COMMIT;
