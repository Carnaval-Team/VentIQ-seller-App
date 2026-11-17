BEGIN;

-- BORRADOR MC-008. NO EJECUTAR en main.
-- La lectura de una clave solo devuelve la del propio usuario y, si tiene
-- tienda, la de una tienda que puede leer. Conocer el UUID de otra venta
-- no devuelve su operación. No toca turnos, egresos ni Admin Lite.

SET LOCAL app.m01_r08_idempotencia_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r08_idempotencia_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador MC-008: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF to_regclass('public.app_dat_operacion_offline_idempotencia') IS NULL
       OR to_regprocedure('public.fn_config_tienda_puede_leer(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta la idempotencia compartida o su lectura por tienda';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_policy
        WHERE polrelid = 'public.app_dat_operacion_offline_idempotencia'::regclass
          AND polname = 'm01_idempotencia_leer'
    ) OR to_regprocedure('public.fn_m01_leer_idempotencia(uuid)') IS NOT NULL THEN
        RAISE EXCEPTION 'El aislamiento M01 de idempotencia ya existe o falta su policy';
    END IF;
END;
$preflight$;

DROP POLICY m01_idempotencia_leer ON public.app_dat_operacion_offline_idempotencia;

CREATE POLICY m01_idempotencia_leer
    ON public.app_dat_operacion_offline_idempotencia
    FOR SELECT TO authenticated
    USING (
        uuid_usuario = auth.uid()
        AND (
            m01_id_tienda IS NULL
            OR m01_id_tienda = 0
            OR public.fn_config_tienda_puede_leer(m01_id_tienda)
        )
    );

CREATE OR REPLACE FUNCTION public.fn_m01_leer_idempotencia(p_client_uuid uuid)
RETURNS TABLE (
    client_uuid uuid,
    tipo text,
    id_operacion bigint,
    m01_id_tienda bigint
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog
AS $function$
    SELECT i.client_uuid, i.tipo, i.id_operacion, i.m01_id_tienda
    FROM public.app_dat_operacion_offline_idempotencia i
    WHERE i.client_uuid = p_client_uuid
      AND i.uuid_usuario = auth.uid();
$function$;

REVOKE ALL ON FUNCTION public.fn_m01_leer_idempotencia(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_leer_idempotencia(uuid) TO authenticated;

COMMIT;
