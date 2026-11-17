BEGIN;

-- BORRADOR M01-R0i estado offline. NO EJECUTAR.
-- Sustituye fn_registrar_cambio_estado_offline. Conserva la firma.
-- El actor es auth.uid(). p_uuid_usuario se valida contra la venta y no
-- autentica. El primer cambio exige operación, TPV y tienda coherentes.
-- Lo aplica el vendedor de esa venta o un administrador que declara a ese
-- vendedor. El replay compara tipo, actor, solicitud, operación y tienda,
-- y no vuelve a llamar a fn_registrar_cambio_estado_operacion.
-- Una clave vieja sin evidencia se retiene. No se revoca la función original:
-- el cambio de estado online todavía la usa.

SET LOCAL app.m01_r0i_estado_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r0i_estado_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador R0i-estado: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF has_schema_privilege('anon', 'public', 'CREATE')
       OR has_schema_privilege('authenticated', 'public', 'CREATE') THEN
        RAISE EXCEPTION 'public permite CREATE a roles no confiables';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc
        WHERE oid = to_regprocedure('public.fn_registrar_cambio_estado_offline(uuid,bigint,smallint,uuid)')
          AND md5(prosrc) = '565daac1a8fdbecbd2faffa8efcacfce'
          AND prosecdef AND proowner = 'postgres'::regrole
    ) THEN
        RAISE EXCEPTION 'fn_registrar_cambio_estado_offline difiere del baseline newa; revisar sin reemplazar avances';
    END IF;
    IF to_regprocedure('public.fn_registrar_cambio_estado_operacion(bigint,smallint,uuid)') IS NULL
       OR to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Faltan el cambio de estado vigente o el predicado S01';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'public.app_dat_operacion_offline_idempotencia'::regclass
          AND attname = 'm01_solicitud' AND atttypid = 'jsonb'::regtype AND NOT attisdropped
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'public.app_dat_operacion_offline_idempotencia'::regclass
          AND attname = 'm01_id_tienda' AND atttypid = 'bigint'::regtype AND NOT attisdropped
    ) THEN
        RAISE EXCEPTION 'Falta la evidencia compartida de idempotencia';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_class
        WHERE oid = 'public.app_dat_operacion_offline_idempotencia'::regclass
          AND (NOT relrowsecurity OR relowner <> 'postgres'::regrole)
    ) OR has_any_column_privilege('authenticated', 'public.app_dat_operacion_offline_idempotencia', 'INSERT')
       OR has_any_column_privilege('authenticated', 'public.app_dat_operacion_offline_idempotencia', 'UPDATE')
       OR has_table_privilege('authenticated', 'public.app_dat_operacion_offline_idempotencia', 'DELETE') THEN
        RAISE EXCEPTION 'Falta el aislamiento M01 de idempotencia';
    END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.fn_registrar_cambio_estado_offline(
    p_client_uuid uuid,
    p_id_operacion bigint,
    p_nuevo_estado smallint,
    p_uuid_usuario uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_request jsonb;
    v_existing public.app_dat_operacion_offline_idempotencia%ROWTYPE;
    v_tipo text;
    v_store bigint;
    v_sale_actor uuid;
    v_tpv bigint;
    v_seller_ok boolean;
BEGIN
    IF v_actor IS NULL
       OR p_client_uuid IS NULL
       OR p_id_operacion IS NULL
       OR p_nuevo_estado IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    v_tipo := 'estado:' || p_nuevo_estado::text;
    v_request := jsonb_build_object(
        'version', 1,
        'id_operacion', p_id_operacion,
        'nuevo_estado', p_nuevo_estado,
        'uuid_vendedor', p_uuid_usuario
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));

    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;

    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM v_tipo
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
           OR v_existing.m01_id_tienda IS NULL
           OR v_existing.id_operacion IS DISTINCT FROM p_id_operacion THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        IF public.fn_config_tienda_puede_escribir(v_existing.m01_id_tienda) IS DISTINCT FROM true
           AND NOT EXISTS (
                SELECT 1
                FROM public.app_dat_vendedor s
                JOIN public.app_dat_trabajadores w ON w.id = s.id_trabajador
                WHERE s.uuid = v_actor
                  AND w.uuid = v_actor
                  AND w.deleted_at IS NULL
                  AND w.id_tienda = v_existing.m01_id_tienda
           ) THEN
            RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object(
            'success', true,
            'idempotent', true,
            'message', 'Cambio de estado ya aplicado (idempotente)'
        );
    END IF;

    SELECT o.id_tienda, o.uuid, ov.id_tpv
    INTO v_store, v_sale_actor, v_tpv
    FROM public.app_dat_operaciones o
    JOIN public.app_dat_operacion_venta ov ON ov.id_operacion = o.id
    WHERE o.id = p_id_operacion
    FOR SHARE OF o, ov;
    IF NOT FOUND OR v_store IS NULL OR v_tpv IS NULL OR v_sale_actor IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    PERFORM 1
    FROM public.app_dat_tpv t
    WHERE t.id = v_tpv AND t.id_tienda = v_store
    FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM public.app_dat_vendedor s
        JOIN public.app_dat_trabajadores w ON w.id = s.id_trabajador
        WHERE s.uuid = v_actor
          AND s.id_tpv = v_tpv
          AND w.uuid = v_actor
          AND w.deleted_at IS NULL
          AND w.id_tienda = v_store
    ) INTO v_seller_ok;

    IF p_uuid_usuario IS NOT NULL AND p_uuid_usuario IS DISTINCT FROM v_actor THEN
        IF p_uuid_usuario IS DISTINCT FROM v_sale_actor
           OR public.fn_config_tienda_puede_escribir(v_store) IS DISTINCT FROM true THEN
            RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
        END IF;
    ELSIF v_actor IS DISTINCT FROM v_sale_actor OR v_seller_ok IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    PERFORM public.fn_registrar_cambio_estado_operacion(
        p_id_operacion, p_nuevo_estado, v_sale_actor
    );

    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES
        (p_client_uuid, p_id_operacion, v_tipo, v_actor, v_request, v_store);

    RETURN jsonb_build_object('success', true, 'idempotent', false);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_registrar_cambio_estado_offline(uuid,bigint,smallint,uuid)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_registrar_cambio_estado_offline(uuid,bigint,smallint,uuid)
    TO authenticated;

COMMIT;
