BEGIN;

-- BORRADOR M01-R0i evidencia. NO EJECUTAR.
-- Unica alta de las columnas compartidas de idempotencia. No pertenece a
-- Admin Lite: la venta offline del vendedor y cualquier entrada posterior
-- las consumen. No hace backfill, no cambia la PK y no reescribe filas.

SET LOCAL app.m01_r0i_evidencia_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r0i_evidencia_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador R0i-evidencia: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF has_schema_privilege('anon', 'public', 'CREATE')
       OR has_schema_privilege('authenticated', 'public', 'CREATE') THEN
        RAISE EXCEPTION 'public permite CREATE a roles no confiables';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_class
        WHERE oid = 'public.app_dat_operacion_offline_idempotencia'::regclass
          AND relowner = 'postgres'::regrole
    ) THEN
        RAISE EXCEPTION 'La tabla de idempotencia no tiene el propietario esperado';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'public.app_dat_operacion_offline_idempotencia'::regclass
          AND attname IN ('m01_solicitud', 'm01_id_tienda')
          AND NOT attisdropped
    ) THEN
        RAISE EXCEPTION 'La evidencia M01 ya existe; revisar antes de continuar';
    END IF;
END;
$preflight$;

ALTER TABLE public.app_dat_operacion_offline_idempotencia
    ADD COLUMN m01_solicitud jsonb,
    ADD COLUMN m01_id_tienda bigint;

COMMENT ON COLUMN public.app_dat_operacion_offline_idempotencia.m01_solicitud IS
    'Solicitud exacta emitida por el servidor para comparar replay. NULL en claves anteriores: no se reconstruye.';
COMMENT ON COLUMN public.app_dat_operacion_offline_idempotencia.m01_id_tienda IS
    'Tienda derivada al aceptar la solicitud. NULL en claves anteriores: no se inventa.';

COMMIT;
