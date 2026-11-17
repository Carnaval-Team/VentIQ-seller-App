BEGIN;

-- BORRADOR MC-025. NO EJECUTAR en main.
-- Alta de mostrador producto-v1. El actor es auth.uid(). La misma clave y la
-- misma solicitud devuelven la operación ya creada y no vuelven a mover stock.
-- Otra solicitud con esa clave entra en conflicto. El flag sigue apagado:
-- mientras lo esté, la función rechaza el alta antes de escribir.

SET LOCAL app.m01_r14_venta_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r14_venta_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador MC-025: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF to_regprocedure('public.fn_m01_validar_linea_v1(jsonb)') IS NULL
       OR to_regprocedure('public.fn_m01_validar_constancia_politica(bigint,bigint,text,bigint,jsonb)') IS NULL
       OR to_regprocedure('public.fn_descontar_venta_enrutada_v2(bigint,numeric,bigint,bigint,integer,boolean)') IS NULL
       OR to_regprocedure('public.fn_cantidad_en_base(bigint,numeric)') IS NULL
       OR to_regclass('public.app_dat_operacion_offline_idempotencia') IS NULL THEN
        RAISE EXCEPTION 'Falta el validador, la constancia o el inventario de la venta';
    END IF;
    IF to_regprocedure('public.fn_m01_registrar_venta_v1(jsonb)') IS NOT NULL THEN
        RAISE EXCEPTION 'El alta producto-v1 ya existe';
    END IF;
END;
$preflight$;

CREATE FUNCTION public.fn_m01_registrar_venta_v1(p_solicitud jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_uuid uuid;
    v_tienda bigint;
    v_tpv bigint;
    v_vendedor bigint;
    v_revision bigint;
    v_constancia bigint;
    v_existente public.app_dat_operacion_offline_idempotencia%ROWTYPE;
    v_matches integer := 0;
    v_seller bigint;
    v_store bigint;
    v_flag boolean;
    v_linea jsonb;
    v_calc jsonb;
    v_operacion bigint;
    v_extraccion bigint;
    v_producto bigint;
    v_presentacion bigint;
    v_cantidad numeric;
    v_base numeric;
    v_medio smallint;
    v_pendiente boolean;
    v_stock jsonb;
    v_lineas jsonb := '[]'::jsonb;
BEGIN
    IF v_actor IS NULL OR p_solicitud IS NULL
       OR p_solicitud->>'version_monetaria' IS DISTINCT FROM 'producto-v1' THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF COALESCE(p_solicitud #>> '{origen,tipo}', 'mostrador') IS DISTINCT FROM 'mostrador' THEN
        RAISE EXCEPTION 'Origen no admitido en el alta v1' USING ERRCODE = '22023';
    END IF;
    v_uuid := (p_solicitud->>'client_uuid')::uuid;
    v_tienda := (p_solicitud->>'id_tienda')::bigint;
    v_tpv := (p_solicitud->>'id_tpv')::bigint;
    v_vendedor := (p_solicitud->>'id_vendedor')::bigint;
    v_revision := (p_solicitud #>> '{politica,id_revision}')::bigint;
    v_constancia := (p_solicitud #>> '{politica,id_constancia}')::bigint;
    IF v_uuid IS NULL OR v_tienda IS NULL OR v_tpv IS NULL OR v_vendedor IS NULL
       OR jsonb_typeof(p_solicitud->'lineas') IS DISTINCT FROM 'array'
       OR jsonb_array_length(p_solicitud->'lineas') = 0 THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_uuid::text, 0));
    SELECT * INTO v_existente
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = v_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existente.tipo IS DISTINCT FROM 'venta_v1'
           OR v_existente.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existente.m01_id_tienda IS DISTINCT FROM v_tienda
           OR v_existente.m01_solicitud IS DISTINCT FROM p_solicitud THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object(
            'status', 'success',
            'idempotent', true,
            'client_uuid', v_uuid,
            'id_operacion', v_existente.id_operacion
        );
    END IF;

    FOR v_seller, v_store IN
        SELECT v.id, t.id_tienda
        FROM public.app_dat_vendedor v
        JOIN public.app_dat_trabajadores w ON w.id = v.id_trabajador
        JOIN public.app_dat_tpv t ON t.id = v.id_tpv
        WHERE v.uuid = v_actor
          AND v.id = v_vendedor
          AND v.id_tpv = v_tpv
          AND t.id = v_tpv
          AND t.id_tienda = v_tienda
          AND w.uuid = v_actor
          AND w.id_tienda = t.id_tienda
          AND w.deleted_at IS NULL
        FOR SHARE OF v, w, t
    LOOP
        v_matches := v_matches + 1;
    END LOOP;
    IF v_matches IS DISTINCT FROM 1 THEN
        IF public.fn_config_tienda_puede_escribir(v_tienda) IS DISTINCT FROM true
           OR NOT EXISTS (
                SELECT 1
                FROM public.app_dat_vendedor v
                JOIN public.app_dat_trabajadores w ON w.id = v.id_trabajador
                JOIN public.app_dat_tpv t ON t.id = v.id_tpv
                WHERE v.id = v_vendedor
                  AND v.id_tpv = v_tpv
                  AND t.id_tienda = v_tienda
                  AND w.id_tienda = v_tienda
                  AND w.deleted_at IS NULL
           ) THEN
            RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
        END IF;
    END IF;

    PERFORM public.fn_m01_validar_constancia_politica(
        v_constancia,
        v_tienda,
        p_solicitud #>> '{politica,dispositivo}',
        v_revision,
        p_solicitud #> '{politica,huella}'
    );
    SELECT c.permitir_moneda_por_producto INTO v_flag
    FROM public.app_dat_configuracion_tienda c
    WHERE c.id_tienda = v_tienda;
    IF v_flag IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Activacion de moneda por producto no autorizada'
            USING ERRCODE = '42501';
    END IF;

    PERFORM pg_catalog.set_config('app.m01_venta_v1_interna', 'yes', true);
    INSERT INTO public.app_dat_operaciones (id_tipo_operacion, uuid, id_tienda)
    VALUES (2, v_uuid, v_tienda)
    RETURNING id INTO v_operacion;
    INSERT INTO public.app_dat_operacion_venta (
        id_operacion, id_tpv, es_pagada, version_monetaria,
        id_revision_politica, id_constancia_politica
    ) VALUES (
        v_operacion, v_tpv, false, 'producto-v1', v_revision, v_constancia
    );

    FOR v_linea IN
        SELECT value FROM jsonb_array_elements(p_solicitud->'lineas')
    LOOP
        v_calc := public.fn_m01_validar_linea_v1(v_linea);
        IF v_calc->>'status' IS DISTINCT FROM 'success' THEN
            RAISE EXCEPTION '%', COALESCE(v_calc->>'error_code', 'SNAPSHOT_INVALID')
                USING ERRCODE = '23514';
        END IF;
        v_producto := (v_linea->>'id_producto')::bigint;
        v_presentacion := NULLIF(v_linea->>'id_presentacion', '')::bigint;
        v_cantidad := (v_linea->>'cantidad')::numeric;
        v_pendiente := COALESCE(v_linea #>> '{seleccion_cobro,tipo}', '') = 'pendiente';
        v_medio := NULLIF(v_linea #>> '{seleccion_cobro,id_medio_pago}', '')::smallint;
        IF NOT EXISTS (
            SELECT 1 FROM public.app_dat_producto p
            WHERE p.id = v_producto
              AND p.id_tienda = v_tienda
              AND p.deleted_at IS NULL
        ) OR (v_presentacion IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM public.app_dat_producto_presentacion pp
            WHERE pp.id = v_presentacion AND pp.id_producto = v_producto
        )) THEN
            RAISE EXCEPTION 'Producto o presentacion fuera de la tienda'
                USING ERRCODE = '42501';
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
            v_operacion, v_producto,
            NULLIF(v_linea->>'id_variante', '')::bigint,
            NULLIF(v_linea->>'id_opcion_variante', '')::bigint,
            NULLIF(v_linea->>'id_ubicacion', '')::bigint,
            v_presentacion, v_cantidad,
            CASE WHEN v_linea->>'moneda_venta' = 'CUP'
                 THEN (v_calc->>'unit_before_manual')::numeric ELSE NULL END,
            round((v_calc->>'subtotal_before_manual')::numeric * (v_calc->>'rate_cup')::numeric, 2),
            (v_calc->>'cup_net')::numeric,
            'producto-v1', (v_linea->>'id_linea_cliente')::uuid, v_linea->>'moneda_venta',
            CASE WHEN v_pendiente THEN NULL ELSE v_medio END, v_pendiente,
            (v_linea #>> '{snapshot_precio,valor_publicado}')::numeric,
            (v_linea->>'descuento_manual_unitario_nativo')::numeric,
            (v_calc->>'unit_net')::numeric,
            (v_calc->>'line_gross')::numeric,
            (v_calc->>'line_net')::numeric,
            (v_calc->>'rate_cup')::numeric,
            round((v_calc->>'line_gross')::numeric * (v_calc->>'rate_cup')::numeric, 2),
            (v_calc->>'cup_net')::numeric,
            v_linea->'snapshot_precio',
            jsonb_build_object(
                'automaticos', COALESCE(v_linea->'snapshot_ajustes_automaticos', '[]'::jsonb),
                'manual_unitario', COALESCE(v_linea->>'descuento_manual_unitario_nativo', '0')
            ),
            v_linea->'snapshot_tasa'
        ) RETURNING id INTO v_extraccion;

        v_base := CASE
            WHEN v_presentacion IS NULL THEN v_cantidad
            ELSE public.fn_cantidad_en_base(v_presentacion, v_cantidad)
        END;
        v_stock := public.fn_descontar_venta_enrutada_v2(
            v_producto, v_base, v_tpv, v_extraccion, 4, false
        );
        IF v_stock IS NULL OR v_stock->>'status' IS DISTINCT FROM 'success' THEN
            RAISE EXCEPTION 'No se pudo mover el inventario de la linea'
                USING ERRCODE = '23514';
        END IF;
        v_lineas := v_lineas || jsonb_build_array(jsonb_build_object(
            'id_linea_cliente', v_linea->>'id_linea_cliente',
            'id_extraccion', v_extraccion,
            'importe_neto_nativo', v_calc->'line_net',
            'importe_neto_cup_equivalente', v_calc->'cup_net',
            'es_gratuidad', v_calc->'es_gratuidad'
        ));
    END LOOP;

    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES
        (v_uuid, v_operacion, 'venta_v1', v_actor, p_solicitud, v_tienda);

    RETURN jsonb_build_object(
        'status', 'success',
        'idempotent', false,
        'version_monetaria', 'producto-v1',
        'client_uuid', v_uuid,
        'id_operacion', v_operacion,
        'lineas', v_lineas
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_m01_registrar_venta_v1(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_registrar_venta_v1(jsonb) TO authenticated;

COMMIT;
