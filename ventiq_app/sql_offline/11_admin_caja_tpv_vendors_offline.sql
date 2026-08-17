-- ============================================================================
-- 11_admin_caja_tpv_vendors_offline.sql
-- ----------------------------------------------------------------------------
-- Wrappers IDEMPOTENTES: crear/actualizar TPV y asignar/flags de vendedor.
-- APLICAR MANUALMENTE en Supabase (SQL Editor).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_admin_caja_tpv_create_offline(
    p_client_uuid uuid,
    p_denominacion text,
    p_id_tienda bigint,
    p_id_almacen bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_existing bigint;
    v_id bigint;
BEGIN
    SELECT id_operacion INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid;

    IF v_existing IS NOT NULL THEN
        RETURN jsonb_build_object(
            'success', true, 'idempotent', true, 'id_tpv', v_existing
        );
    END IF;

    INSERT INTO public.app_dat_tpv (denominacion, id_tienda, id_almacen)
    VALUES (p_denominacion, p_id_tienda, p_id_almacen)
    RETURNING id INTO v_id;

    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario)
    VALUES (p_client_uuid, v_id, 'admin_tpv_create', auth.uid())
    ON CONFLICT (client_uuid) DO NOTHING;

    RETURN jsonb_build_object('success', true, 'idempotent', false, 'id_tpv', v_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_admin_caja_tpv_update_offline(
    p_client_uuid uuid,
    p_id_tpv bigint,
    p_denominacion text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_existing bigint;
BEGIN
    SELECT id_operacion INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid;

    IF v_existing IS NOT NULL THEN
        RETURN jsonb_build_object(
            'success', true, 'idempotent', true, 'id_tpv', v_existing
        );
    END IF;

    UPDATE public.app_dat_tpv
    SET denominacion = p_denominacion
    WHERE id = p_id_tpv;

    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario)
    VALUES (p_client_uuid, p_id_tpv, 'admin_tpv_update', auth.uid())
    ON CONFLICT (client_uuid) DO NOTHING;

    RETURN jsonb_build_object('success', true, 'idempotent', false, 'id_tpv', p_id_tpv);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_admin_caja_vendor_assign_tpv_offline(
    p_client_uuid uuid,
    p_id_vendedor bigint,
    p_id_tpv bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_existing bigint;
BEGIN
    SELECT id_operacion INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid;

    IF v_existing IS NOT NULL THEN
        RETURN jsonb_build_object(
            'success', true, 'idempotent', true, 'id_vendedor', v_existing
        );
    END IF;

    UPDATE public.app_dat_vendedor
    SET id_tpv = p_id_tpv
    WHERE id = p_id_vendedor;

    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario)
    VALUES (p_client_uuid, p_id_vendedor, 'admin_vendor_assign', auth.uid())
    ON CONFLICT (client_uuid) DO NOTHING;

    RETURN jsonb_build_object(
        'success', true, 'idempotent', false, 'id_vendedor', p_id_vendedor
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_admin_caja_vendor_flags_offline(
    p_client_uuid uuid,
    p_id_vendedor bigint,
    p_permitir_customizar_precio_venta boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_existing bigint;
BEGIN
    SELECT id_operacion INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid;

    IF v_existing IS NOT NULL THEN
        RETURN jsonb_build_object(
            'success', true, 'idempotent', true, 'id_vendedor', v_existing
        );
    END IF;

    UPDATE public.app_dat_vendedor
    SET permitir_customizar_precio_venta = COALESCE(p_permitir_customizar_precio_venta, false)
    WHERE id = p_id_vendedor;

    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario)
    VALUES (p_client_uuid, p_id_vendedor, 'admin_vendor_flags', auth.uid())
    ON CONFLICT (client_uuid) DO NOTHING;

    RETURN jsonb_build_object(
        'success', true, 'idempotent', false, 'id_vendedor', p_id_vendedor
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_admin_caja_tpv_create_offline TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_admin_caja_tpv_update_offline TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_admin_caja_vendor_assign_tpv_offline TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_admin_caja_vendor_flags_offline TO authenticated;
