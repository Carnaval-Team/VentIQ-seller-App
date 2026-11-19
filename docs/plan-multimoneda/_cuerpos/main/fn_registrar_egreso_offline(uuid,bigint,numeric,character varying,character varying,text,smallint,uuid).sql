CREATE OR REPLACE FUNCTION public.fn_registrar_egreso_offline(p_client_uuid uuid, p_id_turno bigint, p_monto_entrega numeric, p_nombre_recibe character varying, p_nombre_autoriza character varying, p_motivo_entrega text, p_id_medio_pago smallint DEFAULT NULL::smallint, p_uuid_usuario uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_existing bigint;
    v_result jsonb;
    v_new_id bigint;
BEGIN
    -- 1) ¿Ya se procesó este egreso offline? -> devolver idempotente.
    SELECT id_operacion INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid;

    IF v_existing IS NOT NULL THEN
        RETURN jsonb_build_object(
            'success', true,
            'egreso_id', v_existing,
            'idempotent', true,
            'message', 'Egreso ya registrado previamente (idempotente)'
        );
    END IF;

    -- 2) Registrar usando la función existente.
    v_result := public.registrar_egreso_parcial_v2(
        p_id_turno := p_id_turno,
        p_monto_entrega := p_monto_entrega,
        p_nombre_recibe := p_nombre_recibe,
        p_nombre_autoriza := p_nombre_autoriza,
        p_motivo_entrega := p_motivo_entrega,
        p_id_medio_pago := p_id_medio_pago
    );

    -- 3) Si fue exitoso, persistir el mapeo de idempotencia.
    IF v_result IS NOT NULL AND (v_result->>'success') = 'true' THEN
        v_new_id := NULLIF(v_result->>'egreso_id', '')::bigint;
        IF v_new_id IS NOT NULL THEN
            INSERT INTO public.app_dat_operacion_offline_idempotencia
                (client_uuid, id_operacion, tipo, uuid_usuario)
            VALUES (p_client_uuid, v_new_id, 'egreso', p_uuid_usuario)
            ON CONFLICT (client_uuid) DO NOTHING;
        END IF;

        v_result := v_result || jsonb_build_object(
            'idempotent', false,
            'client_uuid', p_client_uuid
        );
    END IF;

    RETURN v_result;
END;
$function$

