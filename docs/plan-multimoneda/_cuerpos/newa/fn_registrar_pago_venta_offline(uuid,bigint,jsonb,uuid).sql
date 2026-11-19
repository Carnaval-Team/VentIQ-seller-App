CREATE OR REPLACE FUNCTION public.fn_registrar_pago_venta_offline(p_client_uuid uuid, p_id_operacion_venta bigint, p_pagos jsonb, p_uuid_usuario uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_request jsonb;
    v_existing public.app_dat_operacion_offline_idempotencia%ROWTYPE;
    v_store bigint;
    v_sale_actor uuid;
    v_tpv bigint;
    v_seller_ok boolean;
    v_ok boolean;
BEGIN
    IF v_actor IS NULL
       OR p_client_uuid IS NULL
       OR p_id_operacion_venta IS NULL
       OR p_pagos IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    v_request := jsonb_build_object(
        'version', 1,
        'id_operacion_venta', p_id_operacion_venta,
        'uuid_vendedor', p_uuid_usuario,
        'pagos', p_pagos
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));

    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;

    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'pago'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
           OR v_existing.m01_id_tienda IS NULL
           OR v_existing.id_operacion IS DISTINCT FROM p_id_operacion_venta THEN
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
            'id_operacion', v_existing.id_operacion,
            'message', 'Pagos ya registrados previamente (idempotente)'
        );
    END IF;

    SELECT o.id_tienda, o.uuid, ov.id_tpv
    INTO v_store, v_sale_actor, v_tpv
    FROM public.app_dat_operaciones o
    JOIN public.app_dat_operacion_venta ov ON ov.id_operacion = o.id
    WHERE o.id = p_id_operacion_venta
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

    v_ok := public.fn_registrar_pago_venta(p_id_operacion_venta, p_pagos);
    IF NOT COALESCE(v_ok, false) THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'El servidor rechazó el registro de pagos'
        );
    END IF;

    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES
        (p_client_uuid, p_id_operacion_venta, 'pago', v_actor, v_request, v_store);

    RETURN jsonb_build_object(
        'success', true,
        'idempotent', false,
        'id_operacion', p_id_operacion_venta
    );
END;
$function$

