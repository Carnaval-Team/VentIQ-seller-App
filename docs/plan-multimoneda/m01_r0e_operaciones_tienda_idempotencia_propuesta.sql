BEGIN;

-- BORRADOR PARCIAL M01-R0e (tienda, operaciones e idempotencia). NO EJECUTAR.
-- Baseline newa confirmado: app_dat_tienda con 'tienda policy' ALL public/true;
-- app_dat_operaciones con 'Open access to operaciones' SELECT public/true y
-- 'operaciones permitidas' ALL public/true; app_dat_operacion_offline_idempotencia
-- sin RLS ni policies. app_dat_superadmin YA tiene policies acotadas
-- (own/full); no se toca en este corte.
-- Decisiones:
--   * Tienda: lectura por acceso (puede_leer), UPDATE solo admin. INSERT y
--     DELETE sin policy -> denegado para authenticated; el alta legitima es la
--     RPC R0d (DEFINER). Columnas de tienda se dejan concedidas bajo esa
--     policy hasta mapear sus campos (pendiente explicito).
--   * Operaciones: leer != operar. SELECT con puede_leer (incluye
--     supervisor/auditor lectura); INSERT exige el nuevo predicado
--     fn_m01_operaciones_puede_operar (admin O vendedor/almacenero/jefe de
--     cocina de esa tienda; auditor y supervisor solo leen); UPDATE/DELETE
--     solo admin. Las ventas offline siguen por sus RPC DEFINER.
--   * Idempotencia: es interna de las RPC de sync; authenticated solo puede
--     leer sus propias claves (uuid_usuario = auth.uid()), sin escritura.
-- DEPENDENCIAS: S01 + helpers M01. No toca fn_admin_caja_* ni
-- fn_registrar_venta_offline_v4: su endurecimiento interno queda para el
-- corte de RPCs offline.

SET LOCAL app.m01_r0e_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r0e_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador parcial R0e: requiere revision del conjunto M01 y ejecucion manual en newa';
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
          AND p.proname = 'fn_m01_operaciones_puede_operar'
    ) THEN
        RAISE EXCEPTION 'Ya existe el helper de operaciones; revisar avances de newa';
    END IF;
    IF (SELECT count(*) FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'app_dat_tienda'
          AND policyname IN ('tienda policy')) <> 1
       OR (SELECT count(*) FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'app_dat_operaciones'
          AND policyname IN ('Open access to operaciones', 'operaciones permitidas')) <> 2 THEN
        RAISE EXCEPTION 'Baseline de policies de tienda/operaciones distinto al inspeccionado';
    END IF;
    IF (SELECT relrowsecurity FROM pg_class
        WHERE oid = 'public.app_dat_operacion_offline_idempotencia'::regclass) IS DISTINCT FROM false
       OR EXISTS (
           SELECT 1 FROM pg_policies
           WHERE schemaname = 'public' AND tablename = 'app_dat_operacion_offline_idempotencia'
       ) THEN
        RAISE EXCEPTION 'Baseline de idempotencia distinto (esperado: sin RLS ni policies)';
    END IF;
END;
$preflight$;

-- Operar != leer: admin o vendedor/almacenero/jefe de la tienda.

CREATE FUNCTION public.fn_m01_operaciones_puede_operar(
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
       AND (
           public.fn_config_tienda_puede_escribir(p_id_tienda)
           OR EXISTS (
               SELECT 1 FROM public.app_dat_vendedor v
               JOIN public.app_dat_tpv t ON t.id = v.id_tpv
               WHERE v.uuid = auth.uid() AND t.id_tienda = p_id_tienda
           )
           OR EXISTS (
               SELECT 1 FROM public.app_dat_almacenero a
               JOIN public.app_dat_almacen al ON al.id = a.id_almacen
               WHERE a.uuid = auth.uid() AND al.id_tienda = p_id_tienda
                 AND al.deleted_at IS NULL
           )
           OR EXISTS (
               SELECT 1 FROM public.app_dat_jefe_cocina j
               JOIN public.app_dat_cocina c ON c.id = j.id_cocina
               WHERE j.uuid = auth.uid() AND c.id_tienda = p_id_tienda
                 AND c.deleted_at IS NULL
           )
       );
$function$;

GRANT EXECUTE ON FUNCTION public.fn_m01_operaciones_puede_operar(bigint) TO authenticated;

-- =====================================================
-- app_dat_tienda
-- =====================================================

DROP POLICY "tienda policy" ON public.app_dat_tienda;

CREATE POLICY m01_tienda_leer ON public.app_dat_tienda
    FOR SELECT TO authenticated
    USING (public.fn_config_tienda_puede_leer(id));

CREATE POLICY m01_tienda_actualizar ON public.app_dat_tienda
    FOR UPDATE TO authenticated
    USING (public.fn_config_tienda_puede_escribir(id))
    WITH CHECK (public.fn_config_tienda_puede_escribir(id));

REVOKE ALL ON TABLE public.app_dat_tienda FROM anon;

-- =====================================================
-- app_dat_operaciones
-- =====================================================

DROP POLICY "Open access to operaciones" ON public.app_dat_operaciones;
DROP POLICY "operaciones permitidas" ON public.app_dat_operaciones;

CREATE POLICY m01_operaciones_leer ON public.app_dat_operaciones
    FOR SELECT TO authenticated
    USING (public.fn_config_tienda_puede_leer(id_tienda));

CREATE POLICY m01_operaciones_insertar ON public.app_dat_operaciones
    FOR INSERT TO authenticated
    WITH CHECK (public.fn_m01_operaciones_puede_operar(id_tienda));

CREATE POLICY m01_operaciones_actualizar ON public.app_dat_operaciones
    FOR UPDATE TO authenticated
    USING (public.fn_config_tienda_puede_escribir(id_tienda))
    WITH CHECK (public.fn_config_tienda_puede_escribir(id_tienda));

CREATE POLICY m01_operaciones_eliminar ON public.app_dat_operaciones
    FOR DELETE TO authenticated
    USING (public.fn_config_tienda_puede_escribir(id_tienda));

REVOKE ALL ON TABLE public.app_dat_operaciones FROM anon;

-- =====================================================
-- app_dat_operacion_offline_idempotencia (RLS estaba desactivado)
-- =====================================================

ALTER TABLE public.app_dat_operacion_offline_idempotencia ENABLE ROW LEVEL SECURITY;

CREATE POLICY m01_idempotencia_leer ON public.app_dat_operacion_offline_idempotencia
    FOR SELECT TO authenticated
    USING (uuid_usuario = auth.uid());

REVOKE ALL ON TABLE public.app_dat_operacion_offline_idempotencia FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.app_dat_operacion_offline_idempotencia TO authenticated;

-- REVOKE ALL ON TABLE no retira GRANTs hechos por columna ni los de PUBLIC:
-- se revocan explicitamente todas las columnas existentes.
DO $idempotencia_cols$
DECLARE
    v_cols text;
BEGIN
    SELECT string_agg(format('%I', attname), ', ' ORDER BY attnum)
      INTO v_cols
      FROM pg_attribute
     WHERE attrelid = 'public.app_dat_operacion_offline_idempotencia'::regclass
       AND attnum > 0
       AND NOT attisdropped;
    IF v_cols IS NOT NULL THEN
        EXECUTE format(
            'REVOKE ALL (%s) ON TABLE public.app_dat_operacion_offline_idempotencia FROM PUBLIC, anon, authenticated',
            v_cols
        );
    END IF;
END;
$idempotencia_cols$;

-- Verificacion: tras los revokes no debe quedar escritura efectiva
-- (tabular ni por columna) para los roles de cliente.
DO $idempotencia_verify$
BEGIN
    IF has_table_privilege('anon', 'public.app_dat_operacion_offline_idempotencia', 'SELECT')
       OR has_any_column_privilege('anon', 'public.app_dat_operacion_offline_idempotencia', 'SELECT')
       OR has_any_column_privilege('authenticated', 'public.app_dat_operacion_offline_idempotencia', 'INSERT')
       OR has_any_column_privilege('authenticated', 'public.app_dat_operacion_offline_idempotencia', 'UPDATE')
       OR has_table_privilege('authenticated', 'public.app_dat_operacion_offline_idempotencia', 'DELETE')
       OR has_table_privilege('authenticated', 'public.app_dat_operacion_offline_idempotencia', 'TRUNCATE')
       OR has_table_privilege('authenticated', 'public.app_dat_operacion_offline_idempotencia', 'TRIGGER') THEN
        RAISE EXCEPTION 'app_dat_operacion_offline_idempotencia conserva privilegios indebidos para anon/authenticated';
    END IF;
END;
$idempotencia_verify$;

COMMIT;
