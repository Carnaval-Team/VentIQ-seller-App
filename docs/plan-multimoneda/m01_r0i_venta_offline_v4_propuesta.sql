BEGIN;

-- BORRADOR M01-R0i venta offline. NO EJECUTAR.
-- Sustituye fn_registrar_venta_offline_v4. Conserva la firma y el resultado
-- status/id_operacion/idempotent que ya lee el sync del vendedor.
-- El actor es auth.uid(). p_uuid es el vendedor original y se valida; no
-- autentica. El primer envio exige vendedor, trabajador y TPV de la misma
-- tienda. Otro actor solo puede delegar si administra esa tienda.
-- El replay compara tipo, actor, solicitud y tienda, y no vuelve a vender
-- ni a reescribir pagos. Una clave vieja sin evidencia se retiene.
-- Las sobrecargas offline anteriores pierden EXECUTE de cliente: seguian
-- aceptando la misma clave global sin huella. fn_registrar_venta_v3 queda
-- disponible para la venta online.

SET LOCAL app.m01_r0i_venta_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r0i_venta_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador R0i-venta: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF has_schema_privilege('anon', 'public', 'CREATE')
       OR has_schema_privilege('authenticated', 'public', 'CREATE') THEN
        RAISE EXCEPTION 'public permite CREATE a roles no confiables';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc
        WHERE oid = to_regprocedure('public.fn_registrar_venta_offline_v4(uuid,bigint,uuid,jsonb,text,text,text,smallint,bigint,timestamptz,jsonb)')
          AND md5(prosrc) = '1833dad11bafe28cddd6a67184385ced'
          AND prosecdef AND proowner = 'postgres'::regrole
    ) THEN
        RAISE EXCEPTION 'fn_registrar_venta_offline_v4 difiere del baseline main; revisar sin reemplazar avances';
    END IF;
    IF to_regprocedure('public.fn_registrar_venta_v3(bigint,uuid,jsonb,text,text,text,smallint,bigint)') IS NULL
       OR to_regprocedure('public.fn_registrar_pago_venta_v2(bigint,jsonb)') IS NULL
       OR to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL
       OR to_regprocedure('public.fn_registrar_venta_offline_v3(uuid,bigint,uuid,jsonb,text,text,text,smallint,bigint,timestamptz,jsonb)') IS NULL
       OR to_regprocedure('public.fn_registrar_venta_offline(uuid,bigint,uuid,jsonb,text,text,text,smallint,bigint,timestamptz)') IS NULL
       OR to_regprocedure('public.fn_registrar_venta_offline(uuid,bigint,uuid,jsonb,text,text,text,smallint,bigint,timestamptz,jsonb)') IS NULL THEN
        RAISE EXCEPTION 'Faltan la venta vigente, el cobro o las entradas offline que este corte cierra';
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

CREATE OR REPLACE FUNCTION public.fn_registrar_venta_offline_v4(
    p_client_uuid uuid,
    p_id_tpv bigint,
    p_uuid uuid,
    p_productos jsonb,
    p_codigo_promocion text DEFAULT NULL,
    p_denominacion text DEFAULT NULL,
    p_observaciones text DEFAULT NULL,
    p_estado_inicial smallint DEFAULT 1,
    p_id_cliente bigint DEFAULT NULL,
    p_fecha_creacion timestamp with time zone DEFAULT NULL,
    p_pagos jsonb DEFAULT NULL
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
    v_matches integer := 0;
    v_seller_id bigint;
    v_store bigint;
    v_result jsonb;
    v_op bigint;
    v_ok boolean;
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL OR p_id_tpv IS NULL OR p_uuid IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    v_request := jsonb_build_object(
        'version', 1,
        'id_tpv', p_id_tpv,
        'uuid_vendedor', p_uuid,
        'productos', p_productos,
        'codigo_promocion', p_codigo_promocion,
        'denominacion', p_denominacion,
        'observaciones', p_observaciones,
        'estado_inicial', p_estado_inicial,
        'id_cliente', p_id_cliente,
        'fecha_creacion', p_fecha_creacion,
        'pagos', p_pagos
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));

    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;

    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'venta_v4'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
           OR v_existing.m01_id_tienda IS NULL
           OR v_existing.id_operacion IS NULL THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        IF public.fn_config_tienda_puede_escribir(v_existing.m01_id_tienda) IS DISTINCT FROM true
           AND NOT EXISTS (
                SELECT 1
                FROM public.app_dat_vendedor v
                JOIN public.app_dat_trabajadores w ON w.id = v.id_trabajador
                WHERE v.uuid = v_actor
                  AND w.uuid = v_actor
                  AND w.deleted_at IS NULL
                  AND w.id_tienda = v_existing.m01_id_tienda
           ) THEN
            RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object(
            'status', 'success',
            'id_operacion', v_existing.id_operacion,
            'idempotent', true,
            'client_uuid', p_client_uuid,
            'message', 'Operación ya registrada previamente (idempotente)'
        );
    END IF;

    FOR v_seller_id, v_store IN
        SELECT v.id, t.id_tienda
        FROM public.app_dat_vendedor v
        JOIN public.app_dat_trabajadores w ON w.id = v.id_trabajador
        JOIN public.app_dat_tpv t ON t.id = v.id_tpv
        WHERE v.uuid = p_uuid
          AND v.id_tpv = p_id_tpv
          AND t.id = p_id_tpv
          AND w.uuid = p_uuid
          AND w.id_tienda = t.id_tienda
          AND w.deleted_at IS NULL
        FOR SHARE OF v, w, t
    LOOP
        v_matches := v_matches + 1;
    END LOOP;
    IF v_matches IS DISTINCT FROM 1
       OR v_store IS NULL
       OR (p_uuid IS DISTINCT FROM v_actor
           AND public.fn_config_tienda_puede_escribir(v_store) IS DISTINCT FROM true) THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    v_result := public.fn_registrar_venta_v3(
        p_id_tpv, p_uuid, p_productos, p_codigo_promocion,
        p_denominacion, p_observaciones, p_estado_inicial, p_id_cliente
    );
    IF v_result IS NULL OR v_result->>'status' IS DISTINCT FROM 'success' THEN
        RETURN v_result;
    END IF;
    v_op := NULLIF(v_result->>'id_operacion', '')::bigint;
    IF v_op IS NULL THEN
        RAISE EXCEPTION 'Registro de venta incompleto';
    END IF;

    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES
        (p_client_uuid, v_op, 'venta_v4', v_actor, v_request, v_store);

    IF p_fecha_creacion IS NOT NULL THEN
        UPDATE public.app_dat_operaciones
        SET created_at = p_fecha_creacion
        WHERE id = v_op;
        UPDATE public.app_dat_operacion_venta
        SET created_at = p_fecha_creacion
        WHERE id_operacion = v_op;
    END IF;

    IF p_pagos IS NOT NULL
       AND jsonb_typeof(p_pagos) = 'array'
       AND jsonb_array_length(p_pagos) > 0 THEN
        v_ok := public.fn_registrar_pago_venta_v2(v_op, p_pagos);
        IF NOT COALESCE(v_ok, false) THEN
            RAISE EXCEPTION 'No se pudieron registrar los pagos de la operación %', v_op;
        END IF;
        v_result := v_result || jsonb_build_object('pagos_registrados', true);
    END IF;

    RETURN v_result || jsonb_build_object('idempotent', false, 'client_uuid', p_client_uuid);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_registrar_venta_offline_v4(uuid,bigint,uuid,jsonb,text,text,text,smallint,bigint,timestamptz,jsonb)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_registrar_venta_offline_v4(uuid,bigint,uuid,jsonb,text,text,text,smallint,bigint,timestamptz,jsonb)
    TO authenticated;

REVOKE ALL ON FUNCTION public.fn_registrar_venta_offline_v3(uuid,bigint,uuid,jsonb,text,text,text,smallint,bigint,timestamptz,jsonb)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_registrar_venta_offline(uuid,bigint,uuid,jsonb,text,text,text,smallint,bigint,timestamptz)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_registrar_venta_offline(uuid,bigint,uuid,jsonb,text,text,text,smallint,bigint,timestamptz,jsonb)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_registrar_venta_offline_v2(uuid,bigint,uuid,jsonb,text,text,text,smallint,bigint,timestamptz,jsonb)
    FROM PUBLIC, anon, authenticated;

COMMIT;
