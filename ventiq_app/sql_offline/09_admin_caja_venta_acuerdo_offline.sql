-- ============================================================================
-- 09_admin_caja_venta_acuerdo_offline.sql
-- ----------------------------------------------------------------------------
-- Wrapper IDEMPOTENTE: venta por acuerdo desde Admin Lite (Caja).
-- Encadena: fn_registrar_venta → fn_registrar_pago_venta → completar estado.
-- APLICAR MANUALMENTE en Supabase (SQL Editor).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_admin_caja_venta_acuerdo_offline(
    p_client_uuid uuid,
    p_denominacion text,
    p_estado_inicial integer,
    p_id_tpv bigint,
    p_observaciones text,
    p_productos jsonb,
    p_uuid uuid,
    p_id_medio_pago bigint,
    p_monto_total numeric,
    p_id_cliente bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_existing bigint;
    v_result jsonb;
    v_op_id bigint;
BEGIN
    SELECT id_operacion INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid;

    IF v_existing IS NOT NULL THEN
        RETURN jsonb_build_object(
            'status', 'success',
            'idempotent', true,
            'id_operacion', v_existing,
            'message', 'Venta por acuerdo ya registrada (idempotente)'
        );
    END IF;

    v_result := public.fn_registrar_venta(
        p_codigo_promocion := NULL,
        p_denominacion := p_denominacion,
        p_estado_inicial := COALESCE(p_estado_inicial, 1),
        p_id_tpv := p_id_tpv,
        p_observaciones := COALESCE(p_observaciones, '') || ' [caja:' || p_client_uuid::text || ']',
        p_productos := p_productos,
        p_uuid := p_uuid,
        p_id_cliente := p_id_cliente
    );

    v_op_id := NULLIF(v_result->>'id_operacion', '')::bigint;
    IF v_op_id IS NULL THEN
        RAISE EXCEPTION 'fn_registrar_venta no devolvió id_operacion: %', v_result;
    END IF;

    PERFORM public.fn_registrar_pago_venta(
        p_id_operacion_venta := v_op_id,
        p_pagos := jsonb_build_array(
            jsonb_build_object(
                'id_medio_pago', p_id_medio_pago,
                'monto', COALESCE(p_monto_total, 0),
                'referencia_pago', 'Venta por Acuerdo - ' || p_client_uuid::text
            )
        )
    );

    PERFORM public.fn_registrar_cambio_estado_operacion(
        p_id_operacion := v_op_id,
        p_nuevo_estado := 2,
        p_uuid_usuario := p_uuid
    );

    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario)
    VALUES (p_client_uuid, v_op_id, 'admin_venta_acuerdo', p_uuid)
    ON CONFLICT (client_uuid) DO NOTHING;

    RETURN jsonb_build_object(
        'status', 'success',
        'idempotent', false,
        'id_operacion', v_op_id
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_admin_caja_venta_acuerdo_offline TO authenticated;
