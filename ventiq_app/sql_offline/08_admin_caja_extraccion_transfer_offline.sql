-- ============================================================================
-- 08_admin_caja_extraccion_transfer_offline.sql
-- ----------------------------------------------------------------------------
-- Wrappers IDEMPOTENTES para Admin Lite en Caja (ventiq_app):
--   - fn_admin_caja_extraccion_offline
--   - fn_admin_caja_transferencia_offline
--
-- Reusan public.app_dat_operacion_offline_idempotencia (client_uuid PK).
-- APLICAR MANUALMENTE en Supabase (SQL Editor).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Extracción idempotente (envuelve fn_crear_extraccion_con_movimiento).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_admin_caja_extraccion_offline(
    p_client_uuid uuid,
    p_autorizado_por text,
    p_estado_inicial integer,
    p_id_motivo_operacion bigint,
    p_id_tienda bigint,
    p_observaciones text,
    p_productos jsonb,
    p_uuid uuid
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
            'message', 'Extracción ya registrada (idempotente)'
        );
    END IF;

    v_result := public.fn_crear_extraccion_con_movimiento(
        p_autorizado_por := p_autorizado_por,
        p_estado_inicial := p_estado_inicial,
        p_id_motivo_operacion := p_id_motivo_operacion,
        p_id_tienda := p_id_tienda,
        p_observaciones := COALESCE(p_observaciones, '') || ' [caja:' || p_client_uuid::text || ']',
        p_productos := p_productos,
        p_uuid := p_uuid
    );

    v_op_id := NULLIF(v_result->>'id_operacion', '')::bigint;

    IF v_op_id IS NOT NULL THEN
        INSERT INTO public.app_dat_operacion_offline_idempotencia
            (client_uuid, id_operacion, tipo, uuid_usuario)
        VALUES (p_client_uuid, v_op_id, 'admin_extraccion', p_uuid)
        ON CONFLICT (client_uuid) DO NOTHING;
    END IF;

    RETURN COALESCE(v_result, jsonb_build_object('status', 'error'));
END;
$function$;

-- ----------------------------------------------------------------------------
-- Transferencia idempotente (envuelve fn_transferir_inventario_entre_layouts).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_admin_caja_transferencia_offline(
    p_client_uuid uuid,
    p_id_layout_origen bigint,
    p_id_layout_destino bigint,
    p_productos jsonb,
    p_autorizado_por text,
    p_entregado_por text,
    p_transportado_por text,
    p_recibido_por text,
    p_observaciones text,
    p_id_tienda bigint,
    p_uuid uuid,
    p_completar_operaciones boolean DEFAULT true,
    p_moneda_factura text DEFAULT 'USD'
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
            'message', 'Transferencia ya registrada (idempotente)'
        );
    END IF;

    v_result := public.fn_transferir_inventario_entre_layouts(
        p_id_layout_origen := p_id_layout_origen,
        p_id_layout_destino := p_id_layout_destino,
        p_productos := p_productos,
        p_autorizado_por := p_autorizado_por,
        p_entregado_por := p_entregado_por,
        p_transportado_por := p_transportado_por,
        p_recibido_por := p_recibido_por,
        p_observaciones := COALESCE(p_observaciones, '') || ' [caja:' || p_client_uuid::text || ']',
        p_id_tienda := p_id_tienda,
        p_uuid := p_uuid,
        p_completar_operaciones := COALESCE(p_completar_operaciones, true),
        p_moneda_factura := COALESCE(p_moneda_factura, 'USD')
    );

    v_op_id := NULLIF(v_result->>'id_operacion', '')::bigint;
    IF v_op_id IS NULL THEN
        v_op_id := NULLIF(v_result->>'id_operacion_origen', '')::bigint;
    END IF;

    IF v_op_id IS NOT NULL THEN
        INSERT INTO public.app_dat_operacion_offline_idempotencia
            (client_uuid, id_operacion, tipo, uuid_usuario)
        VALUES (p_client_uuid, v_op_id, 'admin_transferencia', p_uuid)
        ON CONFLICT (client_uuid) DO NOTHING;
    END IF;

    RETURN COALESCE(v_result, jsonb_build_object('status', 'error'));
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_admin_caja_extraccion_offline TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_admin_caja_transferencia_offline TO authenticated;
