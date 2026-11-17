BEGIN;

-- BORRADOR M01-R0e2 (enmienda de revokes de idempotencia). NO EJECUTAR.
-- El script 10 (R0e) revoco la tabla a anon/authenticated, pero REVOKE ALL
-- ON TABLE no retira los GRANTs hechos a PUBLIC ni los otorgados por
-- columna. Lectura newa 2026-11-16: anon y authenticated conservan
-- INSERT/UPDATE/TRUNCATE/TRIGGER tabulares y UPDATE por columna en
-- app_dat_operacion_offline_idempotencia (heredados de PUBLIC o por
-- columna). Este corte solo cierra ese hueco; no reinstala policies ni
-- toca datos.

SET LOCAL app.m01_r0e2_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r0e2_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador R0e2: requiere revision del conjunto M01 y ejecucion manual en newa';
    END IF;
    -- El corte solo aplica si R0e ya dejo RLS y la policy de lectura propia.
    IF (SELECT relrowsecurity FROM pg_class
        WHERE oid = 'public.app_dat_operacion_offline_idempotencia'::regclass) IS DISTINCT FROM true
       OR NOT EXISTS (
           SELECT 1 FROM pg_policies
           WHERE schemaname = 'public'
             AND tablename = 'app_dat_operacion_offline_idempotencia'
             AND policyname = 'm01_idempotencia_leer'
       ) THEN
        RAISE EXCEPTION 'Falta el RLS/policy de R0e en idempotencia; aplicar el script 10 primero';
    END IF;
END;
$preflight$;

-- 1) Nivel tabla: tambien PUBLIC (de donde heredan anon y authenticated).
REVOKE ALL ON TABLE public.app_dat_operacion_offline_idempotencia FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.app_dat_operacion_offline_idempotencia TO authenticated;

-- 2) Nivel columna: REVOKE ALL ON TABLE no cubre GRANTs por columna.
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

-- 3) Verificacion: authenticated conserva solo SELECT; anon no ve nada.
DO $idempotencia_verify$
BEGIN
    IF NOT has_table_privilege('authenticated', 'public.app_dat_operacion_offline_idempotencia', 'SELECT')
       OR has_table_privilege('anon', 'public.app_dat_operacion_offline_idempotencia', 'SELECT')
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
