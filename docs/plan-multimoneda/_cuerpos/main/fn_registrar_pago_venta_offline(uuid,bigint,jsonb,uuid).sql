CREATE OR REPLACE FUNCTION public.fn_registrar_pago_venta_offline(p_client_uuid uuid, p_id_operacion_venta bigint, p_pagos jsonb, p_uuid_usuario uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_existing bigint;
    v_ok boolean;
BEGIN
    -- 1) ¿Ya se registraron estos pagos? -> idempotente, no duplicar.
    SELECT id_operacion INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid;

    IF v_existing IS NOT NULL THEN
        RETURN jsonb_build_object(
            'success', true, 'idempotent', true,
            'id_operacion', v_existing,
            'message', 'Pagos ya registrados previamente (idempotente)'
        );
    END IF;

    -- 2) Registrar pagos usando la función existente.
    v_ok := public.fn_registrar_pago_venta(
        p_id_operacion_venta := p_id_operacion_venta,
        p_pagos := p_pagos
    );

    IF v_ok THEN
        INSERT INTO public.app_dat_operacion_offline_idempotencia
            (client_uuid, id_operacion, tipo, uuid_usuario)
        VALUES (p_client_uuid, p_id_operacion_venta, 'pago', p_uuid_usuario)
        ON CONFLICT (client_uuid) DO NOTHING;

        RETURN jsonb_build_object(
            'success', true, 'idempotent', false,
            'id_operacion', p_id_operacion_venta
        );
    END IF;

    RETURN jsonb_build_object(
        'success', false, 'message', 'El servidor rechazó el registro de pagos'
    );
END;
$function$

