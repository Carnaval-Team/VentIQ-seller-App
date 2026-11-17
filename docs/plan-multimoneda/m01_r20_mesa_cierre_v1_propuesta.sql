BEGIN;

-- BORRADOR MC-041. NO EJECUTAR en main.
-- Cierra una cuenta producto-v1 en una sola transaccion. Si la linea ya
-- movio stock al pedir, el cierre no lo vuelve a descontar. El cobro va
-- en la misma funcion. El flag apagado rechaza antes de escribir.

SET LOCAL app.m01_r20_cierre_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r20_cierre_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador MC-041: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF to_regprocedure('public.fn_m01_pedir_item_mesa_v1(jsonb)') IS NULL
       OR to_regprocedure('public.fn_m01_registrar_pagos_v1(jsonb)') IS NULL THEN
        RAISE EXCEPTION 'Falta el pedido de mesa v1 o el cobro v1';
    END IF;
    IF to_regprocedure('public.fn_m01_finalizar_cuenta_v1(jsonb)') IS NOT NULL THEN
        RAISE EXCEPTION 'El cierre de mesa v1 ya existe';
    END IF;
END;
$preflight$;

CREATE FUNCTION public.fn_m01_finalizar_cuenta_v1(p_solicitud jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_uuid uuid;
    v_pago uuid;
    v_cuenta record;
    v_item record;
    v_flag boolean;
    v_existente record;
    v_operacion bigint;
    v_calc jsonb;
    v_linea jsonb;
    v_pagos jsonb := '[]'::jsonb;
    v_base numeric;
    v_stock jsonb;
BEGIN
    IF v_actor IS NULL OR p_solicitud->>'version_monetaria' IS DISTINCT FROM 'producto-v1' THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_uuid := (p_solicitud->>'client_uuid')::uuid;
    v_pago := (p_solicitud->>'client_uuid_pago')::uuid;
    SELECT * INTO v_cuenta
    FROM public.app_dat_mesa_cuenta_abierta
    WHERE id = (p_solicitud->>'id_cuenta')::bigint
      AND version_monetaria = 'producto-v1'
      AND estado = 1;
    IF v_uuid IS NULL OR v_pago IS NULL OR NOT FOUND THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF public.fn_config_tienda_puede_leer(v_cuenta.id_tienda) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    SELECT permitir_moneda_por_producto INTO v_flag
    FROM public.app_dat_configuracion_tienda
    WHERE id_tienda = v_cuenta.id_tienda;
    IF v_flag IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Activacion de moneda por producto no autorizada' USING ERRCODE = '42501';
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_uuid::text, 0));
    SELECT * INTO v_existente
    FROM public.app_dat_mesa_v1_idempotencia
    WHERE client_uuid = v_uuid;
    IF FOUND THEN
        IF v_existente.tipo IS DISTINCT FROM 'cierre_mesa_v1'
           OR v_existente.solicitud IS DISTINCT FROM p_solicitud THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object(
            'status', 'success', 'idempotent', true,
            'id_operacion', v_existente.id_operacion, 'id_cuenta', v_cuenta.id
        );
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.app_dat_mesa_cuenta_item
        WHERE id_cuenta = v_cuenta.id AND version_monetaria IS NULL
          AND COALESCE(estado_servicio, 0) IS DISTINCT FROM 5
    ) THEN
        RAISE EXCEPTION 'La cuenta no puede mezclar contratos' USING ERRCODE = '23514';
    END IF;

    PERFORM pg_catalog.set_config('app.m01_venta_v1_interna', 'yes', true);
    INSERT INTO public.app_dat_operaciones (id_tipo_operacion, uuid, id_tienda)
    VALUES (2, v_uuid, v_cuenta.id_tienda)
    RETURNING id INTO v_operacion;
    INSERT INTO public.app_dat_operacion_venta (
        id_operacion, id_tpv, es_pagada, version_monetaria,
        id_revision_politica, id_constancia_politica
    ) VALUES (
        v_operacion, v_cuenta.id_tpv, false, 'producto-v1',
        v_cuenta.id_revision_politica, v_cuenta.id_constancia_politica
    );

    FOR v_item IN
        SELECT * FROM public.app_dat_mesa_cuenta_item
        WHERE id_cuenta = v_cuenta.id
          AND version_monetaria = 'producto-v1'
          AND COALESCE(estado_servicio, 0) IS DISTINCT FROM 5
    LOOP
        v_linea := jsonb_build_object(
            'cantidad', v_item.cantidad::text,
            'moneda_venta', v_item.moneda_venta,
            'descuento_manual_unitario_nativo', COALESCE(v_item.descuento_manual_unitario_nativo, 0)::text,
            'snapshot_precio', v_item.snapshot_precio,
            'snapshot_tasa', v_item.snapshot_tasa,
            'snapshot_ajustes_automaticos', COALESCE(v_item.snapshot_ajustes, '[]'::jsonb),
            'importe_neto_nativo', v_item.importe_neto_nativo::text
        );
        v_calc := public.fn_m01_validar_linea_v1(v_linea);
        IF v_calc->>'status' IS DISTINCT FROM 'success' THEN
            RAISE EXCEPTION '%', COALESCE(v_calc->>'error_code', 'SNAPSHOT_INVALID')
                USING ERRCODE = '23514';
        END IF;
        INSERT INTO public.app_dat_extraccion_productos (
            id_operacion, id_producto, id_variante, id_opcion_variante,
            id_ubicacion, id_presentacion, cantidad,
            precio_unitario, importe, importe_real,
            version_monetaria, id_linea_cliente, moneda_venta,
            id_medio_pago_seleccionado, seleccion_pendiente,
            precio_unitario_nativo, descuento_manual_unitario_nativo,
            precio_unitario_neto_nativo, importe_bruto_nativo, importe_neto_nativo,
            tasa_cambio_cup, importe_bruto_cup_equivalente, importe_neto_cup_equivalente,
            snapshot_precio, snapshot_descuentos, snapshot_tasa
        ) VALUES (
            v_operacion, v_item.id_producto, v_item.id_variante, v_item.id_opcion_variante,
            v_item.id_ubicacion, v_item.id_presentacion, v_item.cantidad,
            CASE WHEN v_item.moneda_venta = 'CUP'
                 THEN (v_calc->>'unit_before_manual')::numeric ELSE NULL END,
            round((v_calc->>'subtotal_before_manual')::numeric * (v_calc->>'rate_cup')::numeric, 2),
            (v_calc->>'cup_net')::numeric,
            'producto-v1', v_item.id_linea_cliente, v_item.moneda_venta,
            CASE WHEN v_item.seleccion_pendiente THEN NULL ELSE v_item.id_metodo_pago END,
            COALESCE(v_item.seleccion_pendiente, false),
            (v_item.snapshot_precio->>'valor_publicado')::numeric,
            v_item.descuento_manual_unitario_nativo,
            (v_calc->>'unit_net')::numeric,
            (v_calc->>'line_gross')::numeric,
            (v_calc->>'line_net')::numeric,
            (v_calc->>'rate_cup')::numeric,
            round((v_calc->>'line_gross')::numeric * (v_calc->>'rate_cup')::numeric, 2),
            (v_calc->>'cup_net')::numeric,
            v_item.snapshot_precio,
            jsonb_build_object(
                'automaticos', COALESCE(v_item.snapshot_ajustes, '[]'::jsonb),
                'manual_unitario', COALESCE(v_item.descuento_manual_unitario_nativo, 0)
            ),
            v_item.snapshot_tasa
        );
        IF v_item.stock_movido IS NOT TRUE THEN
            v_base := CASE
                WHEN v_item.id_presentacion IS NULL THEN v_item.cantidad
                ELSE public.fn_cantidad_en_base(v_item.id_presentacion, v_item.cantidad)
            END;
            v_stock := public.fn_descontar_venta_enrutada_v2(
                v_item.id_producto, v_base, v_cuenta.id_tpv, NULL, 4, false
            );
            IF v_stock->>'status' IS DISTINCT FROM 'success' THEN
                RAISE EXCEPTION 'No se pudo mover el inventario de la linea' USING ERRCODE = '23514';
            END IF;
        END IF;
        IF COALESCE(v_item.seleccion_pendiente, false) IS FALSE
           AND v_item.importe_neto_nativo > 0
           AND v_item.id_metodo_pago IS NOT NULL THEN
            v_pagos := v_pagos || jsonb_build_array(jsonb_build_object(
                'monto_nativo', v_item.importe_neto_nativo::text,
                'moneda', v_item.moneda_venta,
                'id_medio_pago', v_item.id_metodo_pago,
                'aplicaciones', jsonb_build_array(jsonb_build_object(
                    'id_linea_cliente', v_item.id_linea_cliente,
                    'monto_nativo', v_item.importe_neto_nativo::text
                ))
            ));
        ELSIF COALESCE(v_item.seleccion_pendiente, false)
           AND v_item.importe_neto_nativo > 0
           AND to_regprocedure('public.fn_m01_cxc_registrar_v1(jsonb)') IS NOT NULL THEN
            PERFORM public.fn_m01_cxc_registrar_v1(jsonb_build_object(
                'version_monetaria', 'producto-v1',
                'id_tienda', v_cuenta.id_tienda,
                'id_cliente', NULLIF(p_solicitud->>'id_cliente', '')::bigint,
                'id_operacion', v_operacion,
                'id_linea_cliente', v_item.id_linea_cliente,
                'moneda', v_item.moneda_venta,
                'monto_nativo', v_item.importe_neto_nativo
            ));
        END IF;
    END LOOP;

    IF jsonb_array_length(v_pagos) > 0 THEN
        PERFORM public.fn_m01_registrar_pagos_v1(jsonb_build_object(
            'version_monetaria', 'producto-v1',
            'client_uuid', v_pago,
            'client_uuid_venta', v_uuid,
            'pagos', v_pagos
        ));
    END IF;

    UPDATE public.app_dat_mesa_cuenta_abierta
    SET estado = 2, id_operacion_venta = v_operacion, closed_at = pg_catalog.now()
    WHERE id = v_cuenta.id;

    INSERT INTO public.app_dat_mesa_v1_idempotencia
        (client_uuid, tipo, uuid_usuario, id_tienda, id_cuenta, id_operacion, solicitud)
    VALUES
        (v_uuid, 'cierre_mesa_v1', v_actor, v_cuenta.id_tienda, v_cuenta.id, v_operacion, p_solicitud);

    RETURN jsonb_build_object(
        'status', 'success', 'idempotent', false,
        'id_operacion', v_operacion, 'id_cuenta', v_cuenta.id
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_m01_finalizar_cuenta_v1(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_finalizar_cuenta_v1(jsonb) TO authenticated;

COMMIT;
