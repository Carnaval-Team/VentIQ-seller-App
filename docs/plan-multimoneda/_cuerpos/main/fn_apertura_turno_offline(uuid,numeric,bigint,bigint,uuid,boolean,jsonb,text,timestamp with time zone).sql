CREATE OR REPLACE FUNCTION public.fn_apertura_turno_offline(p_client_uuid uuid, p_efectivo_inicial numeric, p_id_tpv bigint, p_id_vendedor bigint, p_usuario uuid, p_maneja_inventario boolean DEFAULT false, p_productos jsonb DEFAULT '[]'::jsonb, p_observaciones text DEFAULT NULL::text, p_fecha_apertura timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_existing bigint;
    v_turno_abierto bigint;
    v_new_id bigint;
BEGIN
    SELECT id_operacion INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid AND tipo = 'apertura_turno';

    IF v_existing IS NOT NULL THEN
        -- Solo reutilizar si el turno sigue abierto; si ya cerró, crear uno nuevo.
        IF EXISTS (
            SELECT 1 FROM app_dat_caja_turno
            WHERE id = v_existing AND estado = 1
        ) THEN
            RETURN jsonb_build_object(
                'status', 'success', 'id_turno', v_existing, 'idempotent', true
            );
        END IF;

        DELETE FROM public.app_dat_operacion_offline_idempotencia
        WHERE client_uuid = p_client_uuid AND tipo = 'apertura_turno';
    END IF;

    SELECT id INTO v_turno_abierto
    FROM app_dat_caja_turno
    WHERE id_tpv = p_id_tpv AND id_vendedor = p_id_vendedor AND estado = 1
    ORDER BY fecha_apertura DESC NULLS LAST
    LIMIT 1;

    IF v_turno_abierto IS NOT NULL THEN
        INSERT INTO public.app_dat_operacion_offline_idempotencia
            (client_uuid, id_operacion, tipo, uuid_usuario)
        VALUES (p_client_uuid, v_turno_abierto, 'apertura_turno', p_usuario)
        ON CONFLICT (client_uuid) DO NOTHING;

        RETURN jsonb_build_object(
            'status', 'success', 'id_turno', v_turno_abierto, 'idempotent', true,
            'message', 'Turno ya estaba abierto; reutilizado'
        );
    END IF;

    v_new_id := public.registrar_apertura_turno_v3(
        p_efectivo_inicial := p_efectivo_inicial,
        p_id_tpv := p_id_tpv,
        p_id_vendedor := p_id_vendedor,
        p_usuario := p_usuario,
        p_maneja_inventario := p_maneja_inventario,
        p_productos := p_productos,
        p_observaciones := p_observaciones
    );

    IF v_new_id IS NOT NULL THEN
        INSERT INTO public.app_dat_operacion_offline_idempotencia
            (client_uuid, id_operacion, tipo, uuid_usuario)
        VALUES (p_client_uuid, v_new_id, 'apertura_turno', p_usuario)
        ON CONFLICT (client_uuid) DO NOTHING;

        -- Forzar la hora real de apertura del dispositivo.
        IF p_fecha_apertura IS NOT NULL THEN
            UPDATE app_dat_caja_turno
            SET fecha_apertura = p_fecha_apertura
            WHERE id = v_new_id;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'status', 'success', 'id_turno', v_new_id, 'idempotent', false
    );
END;
$function$

