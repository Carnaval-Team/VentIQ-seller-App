BEGIN;

-- BORRADOR MC-027. NO EJECUTAR en main.
-- Cambia la selección de una línea pendiente de cobro y aumenta su cantidad
-- con el mismo snapshot. No fusiona líneas, no reparte pagos y no revierte
-- inventario: bajar la cantidad o borrar la línea queda rechazado.

SET LOCAL app.m01_r16_ajuste_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r16_ajuste_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador MC-027: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF to_regprocedure('public.fn_m01_registrar_pagos_v1(jsonb)') IS NULL
       OR to_regprocedure('public.fn_m01_validar_linea_v1(jsonb)') IS NULL THEN
        RAISE EXCEPTION 'Falta el cobro o el validador de la linea v1';
    END IF;
    IF to_regprocedure('public.fn_m01_ajustar_linea_v1(jsonb)') IS NOT NULL THEN
        RAISE EXCEPTION 'El ajuste de linea v1 ya existe';
    END IF;
END;
$preflight$;

CREATE FUNCTION public.fn_m01_ajustar_linea_v1(p_solicitud jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_uuid uuid;
    v_venta uuid;
    v_linea_id uuid;
    v_tienda bigint;
    v_operacion bigint;
    v_tpv bigint;
    v_existente public.app_dat_operacion_offline_idempotencia%ROWTYPE;
    v_linea public.app_dat_extraccion_productos%ROWTYPE;
    v_accion text := p_solicitud->>'accion';
    v_calc jsonb;
    v_nueva numeric;
    v_base numeric;
    v_stock jsonb;
    v_payload jsonb;
BEGIN
    IF v_actor IS NULL OR p_solicitud->>'version_monetaria' IS DISTINCT FROM 'producto-v1' THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF p_solicitud ? 'snapshot_precio' OR p_solicitud ? 'precio_unitario_nativo' THEN
        RAISE EXCEPTION 'SNAPSHOT_INVALID' USING ERRCODE = '23514';
    END IF;
    v_uuid := (p_solicitud->>'client_uuid')::uuid;
    v_venta := (p_solicitud->>'client_uuid_venta')::uuid;
    v_linea_id := (p_solicitud->>'id_linea_cliente')::uuid;
    IF v_uuid IS NULL OR v_venta IS NULL OR v_linea_id IS NULL
       OR v_accion NOT IN ('seleccion', 'cantidad', 'eliminar') THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_uuid::text, 0));
    SELECT * INTO v_existente
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = v_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existente.tipo IS DISTINCT FROM 'ajuste_v1'
           OR v_existente.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existente.m01_solicitud IS DISTINCT FROM p_solicitud THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object(
            'status', 'success', 'idempotent', true,
            'client_uuid', v_uuid, 'id_operacion', v_existente.id_operacion
        );
    END IF;

    SELECT o.id, o.id_tienda, v.id_tpv INTO v_operacion, v_tienda, v_tpv
    FROM public.app_dat_operaciones o
    JOIN public.app_dat_operacion_venta v ON v.id_operacion = o.id
    WHERE o.uuid = v_venta AND v.version_monetaria = 'producto-v1';
    IF NOT FOUND OR public.fn_config_tienda_puede_leer(v_tienda) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_linea
    FROM public.app_dat_extraccion_productos e
    WHERE e.id_operacion = v_operacion
      AND e.id_linea_cliente = v_linea_id
      AND e.version_monetaria = 'producto-v1'
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.app_dat_pago_aplicacion a WHERE a.id_extraccion = v_linea.id
    ) OR v_accion = 'eliminar' OR (v_accion = 'cantidad' AND (p_solicitud->>'cantidad')::numeric < v_linea.cantidad) THEN
        RAISE EXCEPTION 'La linea cobrada o el inventario ya movido no se reescribe'
            USING ERRCODE = '42501';
    END IF;

    PERFORM pg_catalog.set_config('app.m01_venta_v1_interna', 'yes', true);
    IF v_accion = 'seleccion' THEN
        UPDATE public.app_dat_extraccion_productos
        SET seleccion_pendiente = (p_solicitud #>> '{seleccion_cobro,tipo}') = 'pendiente',
            id_medio_pago_seleccionado = CASE
                WHEN (p_solicitud #>> '{seleccion_cobro,tipo}') = 'pendiente' THEN NULL
                ELSE (p_solicitud #>> '{seleccion_cobro,id_medio_pago}')::smallint
            END
        WHERE id = v_linea.id;
    ELSE
        v_payload := jsonb_build_object(
            'moneda_venta', v_linea.moneda_venta,
            'cantidad', p_solicitud->>'cantidad',
            'precio_unitario_nativo', v_linea.snapshot_precio->>'valor_publicado',
            'descuento_manual_unitario_nativo', v_linea.descuento_manual_unitario_nativo::text,
            'snapshot_precio', v_linea.snapshot_precio,
            'snapshot_tasa', v_linea.snapshot_tasa,
            'snapshot_ajustes_automaticos', COALESCE(v_linea.snapshot_descuentos->'automaticos', '[]'::jsonb)
        );
        v_calc := public.fn_m01_validar_linea_v1(v_payload);
        IF v_calc->>'status' IS DISTINCT FROM 'success' THEN
            RAISE EXCEPTION '%', COALESCE(v_calc->>'error_code', 'SNAPSHOT_INVALID')
                USING ERRCODE = '23514';
        END IF;
        v_nueva := (p_solicitud->>'cantidad')::numeric;
        UPDATE public.app_dat_extraccion_productos
        SET cantidad = v_nueva,
            importe = round((v_calc->>'subtotal_before_manual')::numeric * v_linea.tasa_cambio_cup, 2),
            importe_real = (v_calc->>'cup_net')::numeric,
            precio_unitario_neto_nativo = (v_calc->>'unit_net')::numeric,
            importe_bruto_nativo = (v_calc->>'line_gross')::numeric,
            importe_neto_nativo = (v_calc->>'line_net')::numeric,
            importe_bruto_cup_equivalente = round((v_calc->>'line_gross')::numeric * v_linea.tasa_cambio_cup, 2),
            importe_neto_cup_equivalente = (v_calc->>'cup_net')::numeric
        WHERE id = v_linea.id;
        v_base := CASE
            WHEN v_linea.id_presentacion IS NULL THEN v_nueva - v_linea.cantidad
            ELSE public.fn_cantidad_en_base(v_linea.id_presentacion, v_nueva - v_linea.cantidad)
        END;
        IF v_base > 0 THEN
            v_stock := public.fn_descontar_venta_enrutada_v2(
                v_linea.id_producto, v_base, v_tpv, v_linea.id, 4, false
            );
            IF v_stock IS NULL OR v_stock->>'status' IS DISTINCT FROM 'success' THEN
                RAISE EXCEPTION 'No se pudo mover el inventario de la linea'
                    USING ERRCODE = '23514';
            END IF;
        END IF;
    END IF;

    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (v_uuid, v_operacion, 'ajuste_v1', v_actor, p_solicitud, v_tienda);
    RETURN jsonb_build_object(
        'status', 'success', 'idempotent', false,
        'client_uuid', v_uuid, 'id_operacion', v_operacion,
        'id_linea_cliente', v_linea_id
    );
END;
$function$;

CREATE FUNCTION public.fn_m01_extraccion_v1_directa()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
DECLARE
    v_version text;
BEGIN
    IF pg_catalog.current_setting('app.m01_venta_v1_interna', true) = 'yes' THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
    END IF;
    v_version := CASE WHEN TG_OP = 'DELETE' THEN OLD.version_monetaria ELSE NEW.version_monetaria END;
    IF TG_OP = 'UPDATE' THEN
        v_version := COALESCE(NEW.version_monetaria, OLD.version_monetaria);
    END IF;
    IF v_version = 'producto-v1' THEN
        RAISE EXCEPTION 'La linea producto-v1 no se escribe directo'
            USING ERRCODE = '42501';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS m01_extraccion_v1_directa ON public.app_dat_extraccion_productos;
CREATE TRIGGER m01_extraccion_v1_directa
    BEFORE INSERT OR UPDATE OR DELETE ON public.app_dat_extraccion_productos
    FOR EACH ROW EXECUTE FUNCTION public.fn_m01_extraccion_v1_directa();

REVOKE ALL ON FUNCTION public.fn_m01_ajustar_linea_v1(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_ajustar_linea_v1(jsonb) TO authenticated;

COMMIT;
