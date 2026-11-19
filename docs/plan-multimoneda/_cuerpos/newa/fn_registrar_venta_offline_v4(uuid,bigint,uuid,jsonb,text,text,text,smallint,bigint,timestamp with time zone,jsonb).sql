CREATE OR REPLACE FUNCTION public.fn_registrar_venta_offline_v4(p_client_uuid uuid, p_id_tpv bigint, p_uuid uuid, p_productos jsonb, p_codigo_promocion text DEFAULT NULL::text, p_denominacion text DEFAULT NULL::text, p_observaciones text DEFAULT NULL::text, p_estado_inicial smallint DEFAULT 1, p_id_cliente bigint DEFAULT NULL::bigint, p_fecha_creacion timestamp with time zone DEFAULT NULL::timestamp with time zone, p_pagos jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
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
    v_fecha timestamptz;
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
           -- R33: la fecha no entra en la comparación.
           OR (v_existing.m01_solicitud - 'fecha_creacion') IS DISTINCT FROM (v_request - 'fecha_creacion')
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
        -- R33: nunca en el futuro (antes: se copiaba tal cual).
        v_fecha := LEAST(p_fecha_creacion, now());
        UPDATE public.app_dat_operaciones
        SET created_at = v_fecha
        WHERE id = v_op;
        UPDATE public.app_dat_operacion_venta
        SET created_at = v_fecha
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
$function$

