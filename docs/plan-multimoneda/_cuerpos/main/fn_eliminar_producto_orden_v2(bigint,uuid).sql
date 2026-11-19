CREATE OR REPLACE FUNCTION public.fn_eliminar_producto_orden_v2(p_id_extraccion bigint, p_uuid_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_extraccion       RECORD;
    v_nuevo_total      NUMERIC;
    v_es_elaborado     BOOLEAN;
    v_estado           INT;
    v_id_almacen       BIGINT;
    v_bom              JSONB;
    v_cantidad_base    NUMERIC;
BEGIN
    -- 1. Obtener extracciÃ³n
    SELECT e.*, o.id AS op_id
      INTO v_extraccion
      FROM public.app_dat_extraccion_productos e
      JOIN public.app_dat_operaciones        o ON o.id = e.id_operacion
     WHERE e.id = p_id_extraccion;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('status','error','message','ExtracciÃ³n no encontrada');
    END IF;

    -- 2. Verificar estado Pendiente
    SELECT eo.estado INTO v_estado
      FROM public.app_dat_estado_operacion eo
     WHERE eo.id_operacion = v_extraccion.op_id
     ORDER BY eo.created_at DESC, eo.id DESC
     LIMIT 1;

    IF v_estado IS DISTINCT FROM 1 THEN
        RETURN jsonb_build_object('status','error','message','Solo se pueden editar Ã³rdenes en estado Pendiente');
    END IF;

    -- 3. Verificar si es elaborado (mismo criterio que las otras rutas)
    SELECT (es_elaborado or es_servicio) INTO v_es_elaborado
      FROM public.app_dat_producto WHERE id = v_extraccion.id_producto;

    -- 4. Restaurar inventario (devolver stock)
    IF v_es_elaborado IS NOT TRUE THEN
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
            COALESCE(ip.cantidad_final, 0) + v_extraccion.cantidad,  -- devolver stock
            v_extraccion.sku_producto,
            v_extraccion.sku_ubicacion,
            3,
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
        -- Devolucion de materia prima acotada al almacen de la linea.
        -- FASE 4: la linea guarda la presentacion VENDIDA; la receta se consumio
        -- en equivalente BASE => se convierte antes de devolver.
        v_id_almacen := public.fn_almacen_de_extraccion(p_id_extraccion);

        IF v_id_almacen IS NULL THEN
            RETURN jsonb_build_object(
                'status','error',
                'message','No se pudo determinar el almacen de la linea para devolver la materia prima',
                'error_code','ALMACEN_NOT_RESOLVED',
                'id_extraccion', p_id_extraccion
            );
        END IF;

        v_cantidad_base := public.fn_cantidad_en_base(v_extraccion.id_presentacion, v_extraccion.cantidad);

        v_bom := public.fn_devolver_ingredientes_elaborado_v2(
            p_id_producto_elaborado := v_extraccion.id_producto,
            p_cantidad              := v_cantidad_base,
            p_id_almacen            := v_id_almacen,
            p_id_extraccion         := p_id_extraccion,
            p_origen_cambio         := 4
        );

        IF (v_bom->>'status') <> 'success' THEN
            RETURN jsonb_build_object(
                'status',     'error',
                'message',    COALESCE(v_bom->>'message', 'Error devolviendo materia prima'),
                'error_code', COALESCE(v_bom->>'error_code', 'BOM_ERROR'),
                'id_almacen', v_id_almacen
            );
        END IF;
    END IF;

    -- 5. Eliminar extracciÃ³n
    DELETE FROM public.app_dat_extraccion_productos WHERE id = p_id_extraccion;

    -- 6. Recalcular total
    SELECT COALESCE(SUM(cantidad * precio_unitario), 0)
      INTO v_nuevo_total
      FROM public.app_dat_extraccion_productos
     WHERE id_operacion = v_extraccion.op_id;

    UPDATE public.app_dat_operacion_venta
       SET importe_total = v_nuevo_total
     WHERE id_operacion = v_extraccion.op_id;

    -- 7. Redistribuir pagos proporcionalmente (solo si quedan productos)
    IF v_nuevo_total > 0 THEN
        PERFORM public._fn_distribuir_pagos_orden(v_extraccion.op_id, v_nuevo_total);
    END IF;

    -- 8. Log
    INSERT INTO public.app_dat_log_modificacion_orden
        (id_operacion, uuid_usuario, accion, detalle, created_at)
    VALUES (
        v_extraccion.op_id,
        p_uuid_usuario,
        'remove_product',
        jsonb_build_object(
            'id_extraccion',   p_id_extraccion,
            'id_producto',     v_extraccion.id_producto,
            'cantidad',        v_extraccion.cantidad,
            'cantidad_base',   v_cantidad_base,
            'precio_unitario', v_extraccion.precio_unitario,
            'importe',         v_extraccion.importe,
            'nuevo_total_orden',v_nuevo_total,
            'id_almacen_bom',  v_id_almacen
        ),
        NOW()
    );

    RETURN jsonb_build_object(
        'status',       'success',
        'id_extraccion',p_id_extraccion,
        'total_orden',  v_nuevo_total,
        'message',      'Producto eliminado correctamente'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('status','error','message','Error: ' || SQLERRM, 'sqlstate', SQLSTATE);
END;
$function$

