BEGIN;

-- BORRADOR MC-040. NO EJECUTAR en main.
-- newa ya tiene el pedido, pero abre comanda para cualquier origen distinto
-- de tpv. El resolvedor devuelve barra, cocina_al_pedido, cocina_por_tanda
-- o servicio. Este corte deja la comanda solo en cocina_al_pedido.
-- No enciende el flag.

SET LOCAL app.m01_r24_enrutado_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r24_enrutado_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador MC-040: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF to_regprocedure('public.fn_m01_pedir_item_mesa_v1(jsonb)') IS NULL THEN
        RAISE EXCEPTION 'Falta el pedido de mesa v1';
    END IF;
    IF position('IS DISTINCT FROM ''tpv''' in pg_get_functiondef('public.fn_m01_pedir_item_mesa_v1(jsonb)'::regprocedure)) = 0 THEN
        RAISE EXCEPTION 'El pedido de mesa v1 ya enruta la comanda';
    END IF;
END;
$preflight$;
CREATE OR REPLACE FUNCTION public.fn_m01_pedir_item_mesa_v1(p_solicitud jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_uuid uuid;
    v_cuenta record;
    v_flag boolean;
    v_calc jsonb;
    v_origen jsonb;
    v_stock jsonb;
    v_comanda jsonb;
    v_item bigint;
    v_base numeric;
    v_presentacion bigint;
    v_existente record;
    v_cocina bigint;
    v_movido boolean := false;
    v_estado smallint;
    v_comanda_item bigint;
BEGIN
    IF v_actor IS NULL OR p_solicitud->>'version_monetaria' IS DISTINCT FROM 'producto-v1' THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_uuid := (p_solicitud->>'client_uuid')::uuid;
    SELECT * INTO v_cuenta
    FROM public.app_dat_mesa_cuenta_abierta
    WHERE id = (p_solicitud->>'id_cuenta')::bigint
      AND estado = 1;
    IF v_uuid IS NULL OR NOT FOUND THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF public.fn_config_tienda_puede_leer(v_cuenta.id_tienda) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    SELECT c.permitir_moneda_por_producto INTO v_flag
    FROM public.app_dat_configuracion_tienda c
    WHERE c.id_tienda = v_cuenta.id_tienda;
    IF v_flag IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Activacion de moneda por producto no autorizada' USING ERRCODE = '42501';
    END IF;
    PERFORM public.fn_m01_validar_constancia_politica(
        (p_solicitud->>'id_constancia')::bigint,
        v_cuenta.id_tienda,
        p_solicitud->>'dispositivo',
        (p_solicitud->>'id_revision')::bigint,
        p_solicitud->'huella'
    );
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_uuid::text, 0));
    SELECT * INTO v_existente
    FROM public.app_dat_mesa_v1_idempotencia
    WHERE client_uuid = v_uuid;
    IF FOUND THEN
        IF v_existente.tipo IS DISTINCT FROM 'pedido_mesa_v1'
           OR v_existente.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existente.solicitud IS DISTINCT FROM p_solicitud THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object(
            'status', 'success', 'idempotent', true,
            'id_item', v_existente.id_item, 'id_cuenta', v_existente.id_cuenta,
            'origen', 'barra', 'stock_movido', true, 'message', 'Pedido ya registrado'
        );
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.app_dat_mesa_cuenta_item
        WHERE id_cuenta = v_cuenta.id AND version_monetaria IS NULL
    ) THEN
        RAISE EXCEPTION 'La cuenta no puede mezclar contratos' USING ERRCODE = '23514';
    END IF;
    IF v_cuenta.id_tpv IS NULL THEN
        RAISE EXCEPTION 'La cuenta no tiene TPV' USING ERRCODE = '23514';
    END IF;
    v_origen := public.fn_resolver_origen_venta(
        (p_solicitud #>> '{linea,id_producto}')::bigint, v_cuenta.id_tpv
    );
    IF v_origen->>'status' IS DISTINCT FROM 'success' THEN
        RAISE EXCEPTION '%', COALESCE(v_origen->>'message', 'No se pudo enrutar el pedido')
            USING ERRCODE = '23514';
    END IF;
    v_calc := public.fn_m01_validar_linea_v1(p_solicitud->'linea');
    IF v_calc->>'status' IS DISTINCT FROM 'success' THEN
        RAISE EXCEPTION '%', COALESCE(v_calc->>'error_code', 'SNAPSHOT_INVALID')
            USING ERRCODE = '23514';
    END IF;
    v_presentacion := NULLIF(p_solicitud #>> '{linea,id_presentacion}', '')::bigint;
    INSERT INTO public.app_dat_mesa_cuenta_item (
        id_cuenta, id_producto, id_variante, id_opcion_variante, id_presentacion,
        id_ubicacion, cantidad, precio_unitario, id_metodo_pago, notas,
        version_monetaria, id_linea_cliente, moneda_venta, seleccion_pendiente,
        precio_unitario_nativo, descuento_manual_unitario_nativo, importe_neto_nativo,
        tasa_cambio_cup, importe_neto_cup_equivalente, snapshot_precio, snapshot_tasa,
        snapshot_ajustes, stock_movido
    ) VALUES (
        v_cuenta.id,
        (p_solicitud #>> '{linea,id_producto}')::bigint,
        NULLIF(p_solicitud #>> '{linea,id_variante}', '')::bigint,
        NULLIF(p_solicitud #>> '{linea,id_opcion_variante}', '')::bigint,
        v_presentacion,
        NULLIF(p_solicitud #>> '{linea,id_ubicacion}', '')::bigint,
        (p_solicitud #>> '{linea,cantidad}')::numeric,
        CASE WHEN p_solicitud #>> '{linea,moneda_venta}' = 'CUP'
             THEN (v_calc->>'unit_net')::numeric
             ELSE (v_calc->>'cup_net')::numeric / (p_solicitud #>> '{linea,cantidad}')::numeric
        END,
        CASE WHEN p_solicitud #>> '{linea,seleccion_cobro,tipo}' = 'pendiente' THEN NULL
             ELSE (p_solicitud #>> '{linea,seleccion_cobro,id_medio_pago}')::bigint END,
        p_solicitud #>> '{linea,notas}',
        'producto-v1', v_uuid, p_solicitud #>> '{linea,moneda_venta}',
        p_solicitud #>> '{linea,seleccion_cobro,tipo}' = 'pendiente',
        (v_calc->>'unit_net')::numeric,
        COALESCE(NULLIF(p_solicitud #>> '{linea,descuento_manual_unitario_nativo}', '')::numeric, 0),
        (v_calc->>'line_net')::numeric,
        (v_calc->>'rate_cup')::numeric,
        (v_calc->>'cup_net')::numeric,
        p_solicitud #> '{linea,snapshot_precio}',
        p_solicitud #> '{linea,snapshot_tasa}',
        COALESCE(p_solicitud #> '{linea,snapshot_ajustes_automaticos}', '[]'::jsonb),
        false
    ) RETURNING id INTO v_item;

    UPDATE public.app_dat_mesa_cuenta_abierta
    SET version_monetaria = 'producto-v1',
        id_revision_politica = (p_solicitud->>'id_revision')::bigint,
        id_constancia_politica = (p_solicitud->>'id_constancia')::bigint
    WHERE id = v_cuenta.id;

    v_base := CASE
        WHEN v_presentacion IS NULL THEN (p_solicitud #>> '{linea,cantidad}')::numeric
        ELSE public.fn_cantidad_en_base(v_presentacion, (p_solicitud #>> '{linea,cantidad}')::numeric)
    END;
    v_stock := public.fn_descontar_venta_enrutada_v2(
        (p_solicitud #>> '{linea,id_producto}')::bigint,
        v_base, v_cuenta.id_tpv, NULL, 4, false
    );
    IF v_stock->>'status' IS DISTINCT FROM 'success' THEN
        RAISE EXCEPTION 'No se pudo mover el inventario de la linea' USING ERRCODE = '23514';
    END IF;
    v_movido := v_stock->>'descontado' = 'true';
    v_cocina := NULLIF(v_origen->>'id_cocina', '')::bigint;
    IF v_origen->>'origen' = 'cocina_al_pedido' AND v_cocina IS NOT NULL THEN
        v_comanda := public.fn_disparar_comanda(
            v_cocina,
            (p_solicitud #>> '{linea,id_producto}')::bigint,
            (p_solicitud #>> '{linea,cantidad}')::numeric,
            v_cuenta.id, v_item, v_cuenta.id_tpv, v_actor,
            p_solicitud #>> '{linea,notas}', v_stock
        );
        IF v_comanda->>'status' IS DISTINCT FROM 'success' THEN
            RAISE EXCEPTION 'No se pudo abrir la comanda' USING ERRCODE = '23514';
        END IF;
        v_comanda_item := NULLIF(v_comanda->>'id_comanda_item', '')::bigint;
        v_estado := 1;
    ELSIF v_origen->>'origen' = 'cocina_por_tanda' THEN
        v_estado := 4;
    END IF;
    UPDATE public.app_dat_mesa_cuenta_item
    SET stock_movido = v_movido,
        origen_stock = CASE v_origen->>'origen'
            WHEN 'cocina_por_tanda' THEN 'tanda'
            WHEN 'cocina_al_pedido' THEN 'al_pedido'
            WHEN 'servicio' THEN 'servicio'
            ELSE 'tpv' END,
        id_cocina = v_cocina,
        id_comanda_item = v_comanda_item,
        estado_servicio = v_estado
    WHERE id = v_item;

    INSERT INTO public.app_dat_mesa_v1_idempotencia
        (client_uuid, tipo, uuid_usuario, id_tienda, id_cuenta, id_item, solicitud)
    VALUES
        (v_uuid, 'pedido_mesa_v1', v_actor, v_cuenta.id_tienda, v_cuenta.id, v_item, p_solicitud);

    RETURN jsonb_build_object(
        'status', 'success', 'idempotent', false,
        'id_item', v_item, 'id_cuenta', v_cuenta.id,
        'origen', v_origen->>'origen',
        'origen_stock', CASE v_origen->>'origen'
            WHEN 'cocina_por_tanda' THEN 'tanda'
            WHEN 'cocina_al_pedido' THEN 'al_pedido'
            WHEN 'servicio' THEN 'servicio'
            ELSE 'tpv' END,
        'id_cocina', v_cocina,
        'stock_movido', v_movido,
        'id_comanda', NULLIF(v_comanda->>'id_comanda', '')::bigint,
        'id_comanda_item', v_comanda_item,
        'estado_servicio', v_estado,
        'message', 'Pedido registrado'
    );
END;
$function$;
REVOKE ALL ON FUNCTION public.fn_m01_pedir_item_mesa_v1(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_pedir_item_mesa_v1(jsonb) TO authenticated;

COMMIT;
