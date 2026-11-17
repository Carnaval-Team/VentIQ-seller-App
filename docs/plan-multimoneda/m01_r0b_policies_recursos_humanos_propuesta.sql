BEGIN;

-- BORRADOR PARCIAL M01-R0b (fuente de pertenencia RH). NO EJECUTAR aisladamente.
-- app_dat_recursos_humanos no tenia RLS ni policies en newa: es una fuente de
-- autorizacion (define quien puede operar nomina) expuesta a escritura.
-- Activa RLS y la acota a authenticated: lectura propia, por acceso de tienda
-- o por pertenencia RH a esa tienda; altas/bajas solo administracion
-- (fn_config_tienda_puede_escribir). UPDATE queda revocado por columna:
-- las filas de RH son pura pertenencia (uuid/tienda/trabajador) y mutarlas
-- en sitio cambiaria identidad; la via es baja+alta o la RPC de identidad.
-- DEPENDENCIA: la lectura por pertenencia RH usa
-- fn_m01_personal_es_recursos_humanos (creada en m01_r0b_policies_personal)
-- porque una policy no puede consultar la propia tabla protegida sin una
-- funcion DEFINER; aplicar despues de ese archivo.
-- Nota: las rutas INVOKER fn_*_trabajador_completo siguen funcionando para
-- gerente/dueño (las policies validan al llamador); perderan solo el UPDATE
-- directo, que queda reservado a la RPC de identidad.

SET LOCAL app.m01_r0b_rh_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r0b_rh_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador parcial R0b-RH: requiere revision del conjunto M01 y ejecucion manual en newa';
    END IF;
    IF to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL
       OR to_regprocedure('public.fn_config_tienda_puede_leer(bigint)') IS NULL
       OR to_regprocedure('public.fn_m01_personal_es_recursos_humanos(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Faltan predicados S01/RH; aplicar m01_r0b_policies_personal antes o revisar el conjunto';
    END IF;
    IF (SELECT relrowsecurity FROM pg_class
        WHERE oid = 'public.app_dat_recursos_humanos'::regclass) IS DISTINCT FROM false THEN
        RAISE EXCEPTION 'RLS ya activado en recursos_humanos; revisar avances de newa';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'app_dat_recursos_humanos'
    ) THEN
        RAISE EXCEPTION 'Ya existen policies en recursos_humanos; revisar antes de aplicar';
    END IF;
END;
$preflight$;

ALTER TABLE public.app_dat_recursos_humanos ENABLE ROW LEVEL SECURITY;

CREATE POLICY m01_rrhh_leer ON public.app_dat_recursos_humanos
    FOR SELECT TO authenticated
    USING (
        uuid = auth.uid()
        OR public.fn_config_tienda_puede_leer(id_tienda)
        OR public.fn_m01_personal_es_recursos_humanos(id_tienda)
    );

CREATE POLICY m01_rrhh_insertar ON public.app_dat_recursos_humanos
    FOR INSERT TO authenticated
    WITH CHECK (public.fn_config_tienda_puede_escribir(id_tienda));

CREATE POLICY m01_rrhh_eliminar ON public.app_dat_recursos_humanos
    FOR DELETE TO authenticated
    USING (public.fn_config_tienda_puede_escribir(id_tienda));

REVOKE ALL ON TABLE public.app_dat_recursos_humanos FROM anon;
GRANT SELECT, INSERT, DELETE ON TABLE public.app_dat_recursos_humanos TO authenticated;

COMMIT;
