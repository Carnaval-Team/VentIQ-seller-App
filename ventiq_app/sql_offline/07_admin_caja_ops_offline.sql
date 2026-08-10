-- ============================================================================
-- 07_admin_caja_ops_offline.sql
-- ----------------------------------------------------------------------------
-- Wrappers IDEMPOTENTES para Admin Lite en Caja (ventiq_app):
--   - fn_admin_caja_actualizar_precios_offline
--   - fn_admin_caja_ajuste_inventario_offline
--   - fn_admin_caja_recepcion_offline
--   - fn_admin_caja_crear_producto_offline
--
-- Reusan public.app_dat_operacion_offline_idempotencia (client_uuid PK).
-- El cliente de Caja hace fallback a tablas/RPC originales si estos no existen.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Actualizar precio venta y/o costo (precio_promedio → historial por trigger).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_admin_caja_actualizar_precios_offline(
    p_client_uuid uuid,
    p_id_producto bigint,
    p_id_presentacion bigint DEFAULT NULL,
    p_precio_venta_cup numeric DEFAULT NULL,
    p_precio_costo_usd numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_existing bigint;
    v_pres_id bigint;
BEGIN
    SELECT id_operacion INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid;

    IF v_existing IS NOT NULL THEN
        RETURN jsonb_build_object(
            'success', true,
            'idempotent', true,
            'id_producto', p_id_producto,
            'message', 'Precios ya actualizados (idempotente)'
        );
    END IF;

    IF p_precio_venta_cup IS NOT NULL THEN
        UPDATE public.app_dat_precio_venta
        SET precio_venta_cup = p_precio_venta_cup,
            fecha_desde = CURRENT_DATE,
            fecha_hasta = NULL
        WHERE id = (
            SELECT id FROM public.app_dat_precio_venta
            WHERE id_producto = p_id_producto
            ORDER BY created_at DESC NULLS LAST, id DESC
            LIMIT 1
        );

        IF NOT FOUND THEN
            INSERT INTO public.app_dat_precio_venta (
                id_producto, precio_venta_cup, fecha_desde
            ) VALUES (
                p_id_producto, p_precio_venta_cup, CURRENT_DATE
            );
        END IF;
    END IF;

    IF p_precio_costo_usd IS NOT NULL THEN
        v_pres_id := p_id_presentacion;
        IF v_pres_id IS NULL THEN
            SELECT id INTO v_pres_id
            FROM public.app_dat_producto_presentacion
            WHERE id_producto = p_id_producto AND es_base IS TRUE
            LIMIT 1;
        END IF;
        IF v_pres_id IS NULL THEN
            SELECT id INTO v_pres_id
            FROM public.app_dat_producto_presentacion
            WHERE id_producto = p_id_producto
            ORDER BY id
            LIMIT 1;
        END IF;
        IF v_pres_id IS NOT NULL THEN
            UPDATE public.app_dat_producto_presentacion
            SET precio_promedio = p_precio_costo_usd
            WHERE id = v_pres_id;
        END IF;
    END IF;

    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario)
    VALUES (p_client_uuid, p_id_producto, 'admin_precio', auth.uid())
    ON CONFLICT (client_uuid) DO NOTHING;

    RETURN jsonb_build_object(
        'success', true,
        'idempotent', false,
        'id_producto', p_id_producto
    );
END;
$function$;

-- ----------------------------------------------------------------------------
-- Ajuste de inventario idempotente (envuelve fn_insertar_ajuste_inventario2).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_admin_caja_ajuste_inventario_offline(
    p_client_uuid uuid,
    p_id_producto bigint,
    p_id_ubicacion bigint,
    p_id_presentacion bigint,
    p_cantidad_anterior numeric,
    p_cantidad_nueva numeric,
    p_motivo text,
    p_observaciones text,
    p_uuid_usuario uuid,
    p_id_tipo_operacion bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_existing bigint;
    v_tipo bigint;
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
            'message', 'Ajuste ya registrado (idempotente)'
        );
    END IF;

    v_tipo := p_id_tipo_operacion;
    IF v_tipo IS NULL THEN
        SELECT id INTO v_tipo
        FROM public.app_nom_tipo_operacion
        WHERE denominacion ILIKE '%ajuste%'
        ORDER BY id
        LIMIT 1;
    END IF;

    IF v_tipo IS NULL THEN
        RAISE EXCEPTION 'No se encontró tipo de operación de ajuste';
    END IF;

    v_result := public.fn_insertar_ajuste_inventario2(
        p_id_producto := p_id_producto,
        p_id_ubicacion := p_id_ubicacion,
        p_id_presentacion := p_id_presentacion,
        p_cantidad_anterior := p_cantidad_anterior,
        p_cantidad_nueva := p_cantidad_nueva,
        p_motivo := p_motivo,
        p_observaciones := COALESCE(p_observaciones, '') || ' [caja:' || p_client_uuid::text || ']',
        p_uuid_usuario := p_uuid_usuario,
        p_id_tipo_operacion := v_tipo
    );

    v_op_id := NULLIF(v_result->>'id_operacion', '')::bigint;

    IF v_op_id IS NOT NULL THEN
        INSERT INTO public.app_dat_operacion_offline_idempotencia
            (client_uuid, id_operacion, tipo, uuid_usuario)
        VALUES (p_client_uuid, v_op_id, 'admin_ajuste', p_uuid_usuario)
        ON CONFLICT (client_uuid) DO NOTHING;
    END IF;

    RETURN COALESCE(v_result, jsonb_build_object('status', 'error'));
END;
$function$;

-- ----------------------------------------------------------------------------
-- Recepción idempotente (envuelve fn_registrar_recepcion_con_inventario).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_admin_caja_recepcion_offline(
    p_client_uuid uuid,
    p_entregado_por text,
    p_id_tienda bigint,
    p_monto_total numeric,
    p_motivo integer,
    p_observaciones text,
    p_productos jsonb,
    p_recibido_por text,
    p_uuid uuid,
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
            'success', true,
            'idempotent', true,
            'id_operacion', v_existing,
            'message', 'Recepción ya registrada (idempotente)'
        );
    END IF;

    v_result := public.fn_registrar_recepcion_con_inventario(
        p_entregado_por := p_entregado_por,
        p_id_tienda := p_id_tienda,
        p_monto_total := p_monto_total,
        p_motivo := p_motivo,
        p_observaciones := COALESCE(p_observaciones, '') || ' [caja:' || p_client_uuid::text || ']',
        p_productos := p_productos,
        p_recibido_por := p_recibido_por,
        p_uuid := p_uuid,
        p_moneda_factura := COALESCE(p_moneda_factura, 'USD')
    );

    v_op_id := NULLIF(v_result->>'id_operacion', '')::bigint;

    IF v_op_id IS NOT NULL THEN
        INSERT INTO public.app_dat_operacion_offline_idempotencia
            (client_uuid, id_operacion, tipo, uuid_usuario)
        VALUES (p_client_uuid, v_op_id, 'admin_recepcion', p_uuid)
        ON CONFLICT (client_uuid) DO NOTHING;
    END IF;

    RETURN COALESCE(v_result, jsonb_build_object('success', false));
END;
$function$;

-- ----------------------------------------------------------------------------
-- Alta rápida de producto idempotente.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_admin_caja_crear_producto_offline(
    p_client_uuid uuid,
    p_id_tienda bigint,
    p_denominacion text,
    p_precio_venta_cup numeric,
    p_precio_costo_usd numeric DEFAULT 0,
    p_id_categoria bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_existing bigint;
    v_product_id bigint;
    v_pres_id bigint;
BEGIN
    SELECT id_operacion INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid;

    IF v_existing IS NOT NULL THEN
        RETURN jsonb_build_object(
            'success', true,
            'idempotent', true,
            'id_producto', v_existing,
            'message', 'Producto ya creado (idempotente)'
        );
    END IF;

    INSERT INTO public.app_dat_producto (denominacion, id_tienda)
    VALUES (p_denominacion, p_id_tienda)
    RETURNING id INTO v_product_id;

    INSERT INTO public.app_dat_precio_venta (
        id_producto, precio_venta_cup, fecha_desde
    ) VALUES (
        v_product_id, COALESCE(p_precio_venta_cup, 0), CURRENT_DATE
    );

    -- Presentación base: usar la presentación id=1 si existe, o la primera.
    SELECT id INTO v_pres_id FROM public.app_nom_presentacion ORDER BY id LIMIT 1;
    IF v_pres_id IS NOT NULL THEN
        INSERT INTO public.app_dat_producto_presentacion (
            id_producto, id_presentacion, cantidad, es_base, precio_promedio
        ) VALUES (
            v_product_id, v_pres_id, 1, TRUE, COALESCE(p_precio_costo_usd, 0)
        );
    END IF;

    IF p_id_categoria IS NOT NULL THEN
        BEGIN
            INSERT INTO public.app_dat_productos_subcategorias (
                id_producto, id_sub_categoria
            ) VALUES (v_product_id, p_id_categoria);
        EXCEPTION WHEN OTHERS THEN
            NULL; -- categoría opcional
        END;
    END IF;

    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario)
    VALUES (p_client_uuid, v_product_id, 'admin_producto', auth.uid())
    ON CONFLICT (client_uuid) DO NOTHING;

    RETURN jsonb_build_object(
        'success', true,
        'idempotent', false,
        'id_producto', v_product_id
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_admin_caja_actualizar_precios_offline TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_admin_caja_ajuste_inventario_offline TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_admin_caja_recepcion_offline TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_admin_caja_crear_producto_offline TO authenticated;
