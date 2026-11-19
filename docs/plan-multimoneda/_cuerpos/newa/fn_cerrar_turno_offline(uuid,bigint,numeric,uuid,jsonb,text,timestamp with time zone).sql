CREATE OR REPLACE FUNCTION public.fn_cerrar_turno_offline(p_client_uuid uuid, p_id_tpv bigint, p_efectivo_real numeric, p_usuario uuid, p_productos jsonb DEFAULT '[]'::jsonb, p_observaciones text DEFAULT NULL::text, p_fecha_cierre timestamp with time zone DEFAULT NULL::timestamp with time zone)
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
    v_open bigint;
    v_ok boolean;
    v_extra text;
    v_fecha_apertura timestamptz;
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL OR p_id_tpv IS NULL OR p_usuario IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_extra := current_setting('app.m01_caja_extra', true);
    PERFORM set_config('app.m01_caja_extra', '', true);
    v_request := jsonb_build_object(
        'version', 1,
        'id_tpv', p_id_tpv,
        'efectivo_real', p_efectivo_real,
        'usuario', p_usuario,
        'productos', COALESCE(p_productos, '[]'::jsonb),
        'observaciones', p_observaciones,
        'fecha_cierre', p_fecha_cierre,
        'extra', CASE
            WHEN v_extra IS NULL OR btrim(v_extra) = '' THEN '{}'::jsonb
            ELSE v_extra::jsonb
        END
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));
    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'cierre_turno'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           -- R33: la fecha no entra en la comparación.
           OR (v_existing.m01_solicitud - 'fecha_cierre') IS DISTINCT FROM (v_request - 'fecha_cierre')
           OR v_existing.m01_id_tienda IS NULL THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        IF public.fn_config_tienda_puede_escribir(v_existing.m01_id_tienda) IS DISTINCT FROM true
           AND NOT EXISTS (
                SELECT 1
                FROM public.app_dat_vendedor s
                JOIN public.app_dat_trabajadores w ON w.id = s.id_trabajador
                WHERE s.uuid = v_actor AND w.uuid = v_actor
                  AND w.deleted_at IS NULL
                  AND w.id_tienda = v_existing.m01_id_tienda
           ) THEN
            RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object(
            'status', 'success', 'idempotent', true,
            'message', 'Cierre ya procesado'
        );
    END IF;

    SELECT t.id_tienda, ct.id
    INTO v_store, v_open
    FROM public.app_dat_tpv t
    LEFT JOIN public.app_dat_caja_turno ct
      ON ct.id_tpv = t.id AND ct.estado = 1 AND ct.creado_por = p_usuario
    WHERE t.id = p_id_tpv
    ORDER BY ct.fecha_apertura DESC NULLS LAST
    LIMIT 1;
    IF v_store IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF public.fn_config_tienda_puede_escribir(v_store) IS DISTINCT FROM true
       AND NOT EXISTS (
            SELECT 1
            FROM public.app_dat_vendedor s
            JOIN public.app_dat_trabajadores w ON w.id = s.id_trabajador
            WHERE s.uuid = v_actor AND s.id_tpv = p_id_tpv
              AND w.uuid = v_actor AND w.deleted_at IS NULL
              AND w.id_tienda = v_store
       ) THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF v_open IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'success', 'idempotent', true,
            'message', 'No hay turno abierto; nada que cerrar'
        );
    END IF;
    SELECT fecha_apertura INTO v_fecha_apertura
    FROM public.app_dat_caja_turno
    WHERE id = v_open;

    v_ok := public.fn_cerrar_turno_tpv(
        p_id_tpv := p_id_tpv,
        p_efectivo_real := p_efectivo_real,
        p_usuario := p_usuario,
        p_productos := p_productos,
        p_observaciones := p_observaciones
    );
    IF v_ok IS DISTINCT FROM true THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El servidor rechazó el cierre del turno'
        );
    END IF;
    IF p_fecha_cierre IS NOT NULL THEN
        -- R33: nunca futura ni anterior a la apertura (antes: sin acotar).
        UPDATE public.app_dat_caja_turno
        SET fecha_cierre = GREATEST(v_fecha_apertura, LEAST(p_fecha_cierre, now()))
        WHERE id = v_open;
    END IF;
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, v_open, 'cierre_turno', v_actor, v_request, v_store);
    RETURN jsonb_build_object('status', 'success', 'idempotent', false);
END;
$function$

