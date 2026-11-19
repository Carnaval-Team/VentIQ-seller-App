CREATE OR REPLACE FUNCTION public.fn_apertura_turno_offline(p_client_uuid uuid, p_efectivo_inicial numeric, p_id_tpv bigint, p_id_vendedor bigint, p_usuario uuid, p_maneja_inventario boolean DEFAULT false, p_productos jsonb DEFAULT '[]'::jsonb, p_observaciones text DEFAULT NULL::text, p_fecha_apertura timestamp with time zone DEFAULT NULL::timestamp with time zone)
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
    v_new_id bigint;
    v_allowed boolean;
    v_extra text;
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL
       OR p_id_tpv IS NULL OR p_id_vendedor IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_extra := current_setting('app.m01_caja_extra', true);
    PERFORM set_config('app.m01_caja_extra', '', true);
    v_request := jsonb_build_object(
        'version', 1,
        'efectivo_inicial', p_efectivo_inicial,
        'id_tpv', p_id_tpv,
        'id_vendedor', p_id_vendedor,
        'usuario', p_usuario,
        'maneja_inventario', p_maneja_inventario,
        'productos', COALESCE(p_productos, '[]'::jsonb),
        'observaciones', p_observaciones,
        'fecha_apertura', p_fecha_apertura,
        'extra', CASE
            WHEN v_extra IS NULL OR btrim(v_extra) = '' THEN '{}'::jsonb
            ELSE v_extra::jsonb
        END
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));
    -- R33: dos claves distintas del mismo TPV + vendedor se serializan.
    PERFORM pg_advisory_xact_lock(
        hashtextextended(format('apertura_turno:%s:%s', p_id_tpv, p_id_vendedor), 0)
    );
    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'apertura_turno'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           -- R33: la fecha no entra en la comparación (ver cabecera, punto 6).
           OR (v_existing.m01_solicitud - 'fecha_apertura') IS DISTINCT FROM (v_request - 'fecha_apertura')
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
        -- R33: si el turno sigue abierto, recuperar la apertura real.
        PERFORM public.fn_turno_alinear_fecha_apertura(v_existing.id_operacion, p_fecha_apertura);
        RETURN jsonb_build_object(
            'status', 'success', 'idempotent', true,
            'id_turno', v_existing.id_operacion,
            'message', 'Apertura ya procesada'
        );
    END IF;

    SELECT t.id_tienda INTO v_store
    FROM public.app_dat_tpv t
    WHERE t.id = p_id_tpv
    FOR SHARE;
    IF NOT FOUND OR v_store IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_allowed := public.fn_config_tienda_puede_escribir(v_store) IS TRUE
        OR EXISTS (
            SELECT 1
            FROM public.app_dat_vendedor s
            JOIN public.app_dat_trabajadores w ON w.id = s.id_trabajador
            WHERE s.uuid = v_actor AND s.id_tpv = p_id_tpv
              AND w.uuid = v_actor AND w.deleted_at IS NULL
              AND w.id_tienda = v_store
        );
    IF v_allowed IS DISTINCT FROM true
       OR (p_usuario IS NOT NULL AND p_usuario IS DISTINCT FROM v_actor
           AND public.fn_config_tienda_puede_escribir(v_store) IS DISTINCT FROM true) THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    SELECT id INTO v_open
    FROM public.app_dat_caja_turno
    WHERE id_tpv = p_id_tpv AND id_vendedor = p_id_vendedor AND estado = 1
    ORDER BY fecha_apertura DESC NULLS LAST
    LIMIT 1;
    IF v_open IS NOT NULL THEN
        INSERT INTO public.app_dat_operacion_offline_idempotencia
            (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
        VALUES (p_client_uuid, v_open, 'apertura_turno', v_actor, v_request, v_store);
        -- R33: antes se reutilizaba sin fecha → apertura = hora del sync.
        PERFORM public.fn_turno_alinear_fecha_apertura(v_open, p_fecha_apertura);
        RETURN jsonb_build_object(
            'status', 'success', 'idempotent', false,
            'id_turno', v_open,
            'message', 'Turno ya estaba abierto; reutilizado'
        );
    END IF;

    v_new_id := public.registrar_apertura_turno_v3(
        p_efectivo_inicial := p_efectivo_inicial,
        p_id_tpv := p_id_tpv,
        p_id_vendedor := p_id_vendedor,
        p_usuario := COALESCE(p_usuario, v_actor),
        p_maneja_inventario := COALESCE(p_maneja_inventario, false),
        p_productos := p_productos,
        p_observaciones := p_observaciones
    );
    IF v_new_id IS NULL THEN
        RAISE EXCEPTION 'El servidor rechazó la apertura' USING ERRCODE = '42501';
    END IF;
    -- R33: mismos límites que al reutilizar (antes: UPDATE sin acotar).
    PERFORM public.fn_turno_alinear_fecha_apertura(v_new_id, p_fecha_apertura);
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, v_new_id, 'apertura_turno', v_actor, v_request, v_store);
    RETURN jsonb_build_object(
        'status', 'success', 'id_turno', v_new_id, 'idempotent', false
    );
END;
$function$

