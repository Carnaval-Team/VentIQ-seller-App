-- ============================================================================
-- 10_admin_caja_precio_tpv_offline.sql
-- ----------------------------------------------------------------------------
-- Wrapper IDEMPOTENTE: upsert precio por TPV desde Admin Lite (Caja).
-- APLICAR MANUALMENTE en Supabase (SQL Editor).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_admin_caja_precio_tpv_offline(
    p_client_uuid uuid,
    p_id_producto bigint,
    p_id_tpv bigint,
    p_precio_venta_cup numeric,
    p_fecha_desde date DEFAULT CURRENT_DATE,
    p_id_precio bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_existing bigint;
    v_price_id bigint;
BEGIN
    SELECT id_operacion INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid;

    IF v_existing IS NOT NULL THEN
        RETURN jsonb_build_object(
            'success', true,
            'idempotent', true,
            'id_precio', v_existing,
            'message', 'Precio TPV ya aplicado (idempotente)'
        );
    END IF;

    IF p_id_precio IS NOT NULL AND p_id_precio > 0 THEN
        UPDATE public.app_dat_precio_tpv
        SET precio_venta_cup = p_precio_venta_cup,
            fecha_desde = COALESCE(p_fecha_desde, CURRENT_DATE),
            es_activo = true,
            deleted_at = NULL,
            updated_at = now()
        WHERE id = p_id_precio
        RETURNING id INTO v_price_id;
    END IF;

    IF v_price_id IS NULL THEN
        SELECT id INTO v_price_id
        FROM public.app_dat_precio_tpv
        WHERE id_producto = p_id_producto
          AND id_tpv = p_id_tpv
          AND deleted_at IS NULL
          AND es_activo IS TRUE
        ORDER BY fecha_desde DESC NULLS LAST, id DESC
        LIMIT 1;

        IF v_price_id IS NOT NULL THEN
            UPDATE public.app_dat_precio_tpv
            SET precio_venta_cup = p_precio_venta_cup,
                fecha_desde = COALESCE(p_fecha_desde, CURRENT_DATE),
                updated_at = now()
            WHERE id = v_price_id;
        ELSE
            INSERT INTO public.app_dat_precio_tpv (
                id_producto, id_tpv, precio_venta_cup, fecha_desde, es_activo
            ) VALUES (
                p_id_producto, p_id_tpv, p_precio_venta_cup,
                COALESCE(p_fecha_desde, CURRENT_DATE), true
            )
            RETURNING id INTO v_price_id;
        END IF;
    END IF;

    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario)
    VALUES (p_client_uuid, v_price_id, 'admin_precio_tpv', auth.uid())
    ON CONFLICT (client_uuid) DO NOTHING;

    RETURN jsonb_build_object(
        'success', true,
        'idempotent', false,
        'id_precio', v_price_id
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_admin_caja_precio_tpv_offline TO authenticated;
