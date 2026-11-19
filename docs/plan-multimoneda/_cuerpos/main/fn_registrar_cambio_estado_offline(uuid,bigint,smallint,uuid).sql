CREATE OR REPLACE FUNCTION public.fn_registrar_cambio_estado_offline(p_client_uuid uuid, p_id_operacion bigint, p_nuevo_estado smallint, p_uuid_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_existing bigint;
BEGIN
    -- 1) ¿Ya se aplicó este cambio de estado? -> idempotente.
    SELECT id_operacion INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid;

    IF v_existing IS NOT NULL THEN
        RETURN jsonb_build_object(
            'success', true, 'idempotent', true,
            'message', 'Cambio de estado ya aplicado (idempotente)'
        );
    END IF;

    -- 2) Aplicar el cambio de estado usando la función existente.
    PERFORM public.fn_registrar_cambio_estado_operacion(
        p_id_operacion := p_id_operacion,
        p_nuevo_estado := p_nuevo_estado,
        p_uuid_usuario := p_uuid_usuario
    );

    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario)
    VALUES (p_client_uuid, p_id_operacion, 'estado:' || p_nuevo_estado, p_uuid_usuario)
    ON CONFLICT (client_uuid) DO NOTHING;

    RETURN jsonb_build_object('success', true, 'idempotent', false);
END;
$function$

