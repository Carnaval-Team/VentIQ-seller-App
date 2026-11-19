CREATE OR REPLACE FUNCTION public.fn_cerrar_turno_offline(p_client_uuid uuid, p_id_tpv bigint, p_efectivo_real numeric, p_usuario uuid, p_productos jsonb DEFAULT '[]'::jsonb, p_observaciones text DEFAULT NULL::text, p_fecha_cierre timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_existing bigint;
    v_ok boolean;
    v_turno_abierto bigint;
BEGIN
    SELECT id_operacion INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid AND tipo = 'cierre_turno';

    IF v_existing IS NOT NULL THEN
        RETURN jsonb_build_object(
            'status', 'success', 'idempotent', true,
            'message', 'Cierre ya procesado'
        );
    END IF;

    SELECT id INTO v_turno_abierto
    FROM app_dat_caja_turno
    WHERE id_tpv = p_id_tpv AND estado = 1
    ORDER BY fecha_apertura DESC NULLS LAST
    LIMIT 1;

    IF v_turno_abierto IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'success', 'idempotent', true,
            'message', 'No hay turno abierto; nada que cerrar'
        );
    END IF;

    v_ok := public.fn_cerrar_turno_tpv(
        p_id_tpv := p_id_tpv,
        p_efectivo_real := p_efectivo_real,
        p_usuario := p_usuario,
        p_productos := p_productos,
        p_observaciones := p_observaciones
    );

    IF v_ok THEN
        INSERT INTO public.app_dat_operacion_offline_idempotencia
            (client_uuid, id_operacion, tipo, uuid_usuario)
        VALUES (p_client_uuid, v_turno_abierto, 'cierre_turno', p_usuario)
        ON CONFLICT (client_uuid) DO NOTHING;

        IF p_fecha_cierre IS NOT NULL THEN
            UPDATE app_dat_caja_turno
            SET fecha_cierre = p_fecha_cierre
            WHERE id = v_turno_abierto;
        END IF;

        RETURN jsonb_build_object('status', 'success', 'idempotent', false);
    END IF;

    RETURN jsonb_build_object(
        'status', 'error', 'message', 'El servidor rechazó el cierre del turno'
    );
END;
$function$

