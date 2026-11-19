CREATE OR REPLACE FUNCTION public.fn_actualizar_cantidad_producto_orden_v2(p_id_extraccion bigint, p_nueva_cantidad numeric, p_uuid_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_extraccion        RECORD;
    v_operacion         RECORD;
    v_ultimo_inventario RECORD;
    v_delta             NUMERIC;
    v_delta_base        NUMERIC;
    v_nuevo_importe     NUMERIC;
    v_nuevo_total       NUMERIC;
    v_es_elaborado      BOOLEAN;
    v_id_almacen        BIGINT;
    v_bom               JSONB;
BEGIN
    -- 1. Obtener datos actuales de la extracción
    SELECT e.*, o.id AS op_id
      INTO v_extraccion
      FROM public.app_dat_extraccion_productos e
      JOIN public.app_dat_operaciones           o ON o.id = e.id_operacion
     WHERE e.id = p_id_extraccion;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('status','error','message','Extracción no encontrada');
    END IF;

    -- 2. Verificar que la orden esté en estado Pendiente (estado = 1)
    SELECT eo.estado INTO v_operacion
      FROM public.app_dat_estado_operacion eo
     WHERE eo.id_operacion = v_extraccion.op_id
     ORDER BY eo.created_at DESC, eo.id DESC
     LIMIT 1;

    IF v_operacion.estado IS DISTINCT FROM 1 THEN
        RETURN jsonb_build_object('status','error','message','Solo se pueden editar órdenes en estado Pendiente');
    END IF;

    IF p_nueva_cantidad <= 0 THEN
        RETURN jsonb_build_object('status','error','message','La nueva cantidad debe ser mayor que 0. Para eliminar usa fn_eliminar_producto_orden.');
    END IF;

    -- 3. Calcular delta (diferencia entre nueva y antigua cantidad).
    --    El delta esta en la PRESENTACION vendida; FASE 2 lo convierte a base.
    v_delta := p_nueva_cantidad - v_extraccion.cantidad;

    -- 4. Verificar si el producto es elaborado
    SELECT (es_elaborado or es_servicio) INTO v_es_elaborado
      FROM public.app_dat_producto
     WHERE id = v_extraccion.id_producto;

    -- 5. Si no es elaborado, verificar/ajustar inventario base
    IF v_es_elaborado IS NOT TRUE THEN
        SELECT cantidad_final
          INTO v_ultimo_inventario
          FROM public.app_dat_inventario_productos
         WHERE id_producto = v_extraccion.id_producto
           AND COALESCE(id_variante,  0) = COALESCE(v_extraccion.id_variante,  0)
           AND COALESCE(id_ubicacion, 0) = COALESCE(v_extraccion.id_ubicacion, 0)
         ORDER BY created_at DESC, id DESC
         LIMIT 1;

        IF v_delta > 0 AND (v_ultimo_inventario IS NULL OR v_ultimo_inventario.cantidad_final < v_delta) THEN
            RETURN jsonb_build_object(
                'status','error',
                'message','Stock insuficiente para aumentar la cantidad',
                'disponible', COALESCE(v_ultimo_inventario.cantidad_final, 0),
                'requerido',  v_delta
            );
        END IF;

        -- Registrar ajuste de inventario del producto base (presentacion vendida)
        INSERT INTO public.app_dat_inventario_productos (
            id_producto, id_variante, id_opcion_variante, id_ubicacion, id_presentacion,
            cantidad_inicial, cantidad_final,
            sku_producto, sku_ubicacion,
            origen_cambio, id_extraccion, created_at
        )
        SELECT
            v_extraccion.id_producto,
            v_extraccion.id_variante,
            v_extraccion.id_opcion_variante,
            v_extraccion.id_ubicacion,
            v_extraccion.id_presentacion,
            COALESCE(ip.cantidad_final, 0),
            COALESCE(ip.cantidad_final, 0) - v_delta,
            v_extraccion.sku_producto,
            v_extraccion.sku_ubicacion,
            3,   -- Origen: Venta / ajuste
            p_id_extraccion,
            NOW()
        FROM (
            SELECT cantidad_final
              FROM public.app_dat_inventario_productos
             WHERE id_producto = v_extraccion.id_producto
               AND COALESCE(id_variante,  0) = COALESCE(v_extraccion.id_variante,  0)
               AND COALESCE(id_ubicacion, 0) = COALESCE(v_extraccion.id_ubicacion, 0)
             ORDER BY created_at DESC, id DESC
             LIMIT 1
        ) ip;
    ELSE
        -- ══════════════════════════════════════════════════════════════════
        -- FASE 2 / C5 · Ajuste de materia prima por EQUIVALENTE BASE.
        -- `v_delta` viene en la presentacion vendida; se convierte con
        -- fn_cantidad_en_base(id_presentacion de la linea, delta) y el consumo
        -- y la devolucion son simetricos (ambos `_v2`).
        -- ══════════════════════════════════════════════════════════════════
        v_id_almacen := public.fn_almacen_de_extraccion(p_id_extraccion);

        IF v_id_almacen IS NULL THEN
            RETURN jsonb_build_object(
                'status','error',
                'message','No se pudo determinar el almacen de la linea para ajustar la materia prima',
                'error_code','ALMACEN_NOT_RESOLVED',
                'id_extraccion', p_id_extraccion
            );
        END IF;

        v_delta_base := public.fn_cantidad_en_base(v_extraccion.id_presentacion, v_delta);

        IF v_delta > 0 THEN
            -- Aumentar cantidad → descontar más ingredientes (en base)
            v_bom := public.fn_descontar_ingredientes_elaborado_v2(
                p_id_producto_elaborado := v_extraccion.id_producto,
                p_cantidad              := v_delta_base,
                p_id_almacen            := v_id_almacen,
                p_id_extraccion         := p_id_extraccion,
                p_origen_cambio         := 4
            );
        ELSIF v_delta < 0 THEN
            -- Disminuir cantidad → devolver ingredientes a la presentacion BASE
            v_bom := public.fn_devolver_ingredientes_elaborado_v2(
                p_id_producto_elaborado := v_extraccion.id_producto,
                p_cantidad              := ABS(v_delta_base),
                p_id_almacen            := v_id_almacen,
                p_id_extraccion         := p_id_extraccion,
                p_origen_cambio         := 4
            );
        ELSE
            -- delta = 0: nada que mover
            v_bom := jsonb_build_object('status','success','lineas_afectadas',0);
        END IF;

        IF (v_bom->>'status') <> 'success' THEN
            -- Reescribir al formato de error que ya espera esta pantalla,
            -- conservando el detalle del helper.
            RETURN jsonb_build_object(
                'status',        'error',
                'message',       COALESCE(v_bom->>'message', 'Error ajustando materia prima'),
                'error_code',    COALESCE(v_bom->>'error_code', 'BOM_ERROR'),
                'id_ingrediente', v_bom->'id_ingrediente',
                'disponible',    COALESCE(v_bom->'cantidad_disponible', to_jsonb(0)),
                'requerido',     COALESCE(v_bom->'cantidad_requerida',  to_jsonb(0)),
                'id_almacen',    v_id_almacen
            );
        END IF;
    END IF;

    -- 6. Actualizar extracción (la LINEA sigue en la presentacion vendida)
    v_nuevo_importe := p_nueva_cantidad * v_extraccion.precio_unitario;

    UPDATE public.app_dat_extraccion_productos
       SET cantidad        = p_nueva_cantidad,
           importe         = v_nuevo_importe,
           importe_real    = p_nueva_cantidad * COALESCE(v_extraccion.precio_unitario, 0)
     WHERE id = p_id_extraccion;

    -- 7. Recalcular importe total de la venta
    SELECT COALESCE(SUM(cantidad * precio_unitario), 0)
      INTO v_nuevo_total
      FROM public.app_dat_extraccion_productos
     WHERE id_operacion = v_extraccion.op_id;

    UPDATE public.app_dat_operacion_venta
       SET importe_total = v_nuevo_total
     WHERE id_operacion = v_extraccion.op_id;

    -- 8. Redistribuir pagos proporcionalmente
    PERFORM public._fn_distribuir_pagos_orden(v_extraccion.op_id, v_nuevo_total);

    -- 9. Log
    INSERT INTO public.app_dat_log_modificacion_orden
        (id_operacion, uuid_usuario, accion, detalle, created_at)
    VALUES (
        v_extraccion.op_id,
        p_uuid_usuario,
        'update_quantity',
        jsonb_build_object(
            'id_extraccion',    p_id_extraccion,
            'id_producto',      v_extraccion.id_producto,
            'cantidad_anterior',v_extraccion.cantidad,
            'cantidad_nueva',   p_nueva_cantidad,
            'importe_anterior', v_extraccion.importe,
            'importe_nuevo',    v_nuevo_importe,
            'delta',            v_delta,
            'delta_base',       v_delta_base,
            'nuevo_total_orden',v_nuevo_total,
            'id_almacen_bom',   v_id_almacen
        ),
        NOW()
    );

    RETURN jsonb_build_object(
        'status',         'success',
        'id_extraccion',  p_id_extraccion,
        'cantidad_nueva', p_nueva_cantidad,
        'importe_nuevo',  v_nuevo_importe,
        'total_orden',    v_nuevo_total,
        'message',        'Cantidad actualizada correctamente'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('status','error','message','Error: ' || SQLERRM, 'sqlstate', SQLSTATE);
END;
$function$

