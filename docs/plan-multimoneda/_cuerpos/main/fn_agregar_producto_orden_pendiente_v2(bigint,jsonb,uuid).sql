CREATE OR REPLACE FUNCTION public.fn_agregar_producto_orden_pendiente_v2(p_id_operacion bigint, p_producto jsonb, p_uuid_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_estado           INT;
    v_id_extraccion    BIGINT;
    v_importe          NUMERIC;
    v_nuevo_total      NUMERIC;
    v_es_elaborado     BOOLEAN;
    v_extraccion_exist RECORD;   -- para detectar duplicado
    v_nueva_cantidad   NUMERIC;
    v_id_medio_pago    INT;
    v_id_almacen       BIGINT;
    v_bom              JSONB;
    v_cantidad_base    NUMERIC;
BEGIN
    -- 1. Verificar estado Pendiente
    SELECT eo.estado INTO v_estado
      FROM public.app_dat_estado_operacion eo
     WHERE eo.id_operacion = p_id_operacion
     ORDER BY eo.created_at DESC, eo.id DESC
     LIMIT 1;

    IF v_estado IS DISTINCT FROM 1 THEN
        RETURN jsonb_build_object('status','error','message','Solo se pueden editar Ã³rdenes en estado Pendiente');
    END IF;

    -- 2. Validar campos mÃ­nimos
    IF p_producto->>'id_producto'     IS NULL OR
       p_producto->>'cantidad'        IS NULL OR
       p_producto->>'precio_unitario' IS NULL OR
       p_producto->>'id_medio_pago'   IS NULL THEN
        RETURN jsonb_build_object('status','error','message','El producto debe incluir id_producto, cantidad, precio_unitario e id_medio_pago');
    END IF;

    v_id_medio_pago := (p_producto->>'id_medio_pago')::INT;

    -- 3. Buscar si ya existe una extracciÃ³n con el mismo producto/variante/ubicaciÃ³n
    SELECT ep.id, ep.cantidad
      INTO v_extraccion_exist
      FROM public.app_dat_extraccion_productos ep
     WHERE ep.id_operacion = p_id_operacion
       AND ep.id_producto  = (p_producto->>'id_producto')::BIGINT
       AND COALESCE(ep.id_variante,  0) = COALESCE(NULLIF(p_producto->>'id_variante',  '')::BIGINT, 0)
       AND COALESCE(ep.id_ubicacion, 0) = COALESCE(NULLIF(p_producto->>'id_ubicacion', '')::BIGINT, 0)
     ORDER BY ep.created_at DESC
     LIMIT 1;

    IF FOUND THEN
        -- â”€â”€ Producto duplicado: redirigir a la version _v2 del ajuste â”€â”€
        v_nueva_cantidad := v_extraccion_exist.cantidad + (p_producto->>'cantidad')::NUMERIC;

        RETURN public.fn_actualizar_cantidad_producto_orden_v2(
            v_extraccion_exist.id,
            v_nueva_cantidad,
            p_uuid_usuario
        );
    END IF;

    v_importe := (p_producto->>'cantidad')::NUMERIC * (p_producto->>'precio_unitario')::NUMERIC;

    -- 4. Insertar extracciÃ³n (producto nuevo en la orden). La cantidad de la
    --    LINEA sigue en la presentacion vendida.
    INSERT INTO public.app_dat_extraccion_productos (
        id_operacion, id_producto, id_variante, id_opcion_variante,
        id_ubicacion, id_presentacion,
        cantidad, precio_unitario, importe, importe_real,
        sku_producto, sku_ubicacion, created_at
    ) VALUES (
        p_id_operacion,
        (p_producto->>'id_producto')::BIGINT,
        NULLIF(p_producto->>'id_variante',       '')::BIGINT,
        NULLIF(p_producto->>'id_opcion_variante','')::BIGINT,
        NULLIF(p_producto->>'id_ubicacion',      '')::BIGINT,
        NULLIF(p_producto->>'id_presentacion',   '')::BIGINT,
        (p_producto->>'cantidad')::NUMERIC,
        (p_producto->>'precio_unitario')::NUMERIC,
        v_importe,
        (p_producto->>'cantidad')::NUMERIC * COALESCE(
            NULLIF(p_producto->>'precio_real','')::NUMERIC,
            (p_producto->>'precio_unitario')::NUMERIC
        ),
        p_producto->>'sku_producto',
        p_producto->>'sku_ubicacion',
        NOW()
    ) RETURNING id INTO v_id_extraccion;

    -- 5. Verificar si es elaborado
    SELECT (es_elaborado or es_servicio) INTO v_es_elaborado
      FROM public.app_dat_producto WHERE id = (p_producto->>'id_producto')::BIGINT;

    -- 6. Ajustar inventario
    IF v_es_elaborado IS NOT TRUE THEN
        INSERT INTO public.app_dat_inventario_productos (
            id_producto, id_variante, id_opcion_variante, id_ubicacion, id_presentacion,
            cantidad_inicial, cantidad_final, sku_producto, sku_ubicacion,
            origen_cambio, id_extraccion, created_at
        )
        SELECT
            (p_producto->>'id_producto')::BIGINT,
            NULLIF(p_producto->>'id_variante',       '')::BIGINT,
            NULLIF(p_producto->>'id_opcion_variante','')::BIGINT,
            NULLIF(p_producto->>'id_ubicacion',      '')::BIGINT,
            NULLIF(p_producto->>'id_presentacion',   '')::BIGINT,
            COALESCE(ip.cantidad_final, 0),
            COALESCE(ip.cantidad_final, 0) - (p_producto->>'cantidad')::NUMERIC,
            p_producto->>'sku_producto',
            p_producto->>'sku_ubicacion',
            3, v_id_extraccion, NOW()
        FROM (
            SELECT cantidad_final
              FROM public.app_dat_inventario_productos
             WHERE id_producto = (p_producto->>'id_producto')::BIGINT
               AND COALESCE(id_variante,  0) = COALESCE(NULLIF(p_producto->>'id_variante','')::BIGINT, 0)
               AND COALESCE(id_ubicacion, 0) = COALESCE(NULLIF(p_producto->>'id_ubicacion','')::BIGINT, 0)
             ORDER BY created_at DESC, id DESC
             LIMIT 1
        ) ip;
        -- NOTA: el SKU propio se mueve en la presentacion vendida (fisico), igual
        -- que la viva: la linea y el ledger hablan la misma unidad.
    ELSE
        -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
        -- FASE 2 / C5 Â· Descuento de materia prima por EQUIVALENTE BASE.
        -- La linea trae la cantidad en la presentacion vendida; la receta se
        -- multiplica por unidades base. Si la linea no trae presentacion,
        -- fn_cantidad_en_base devuelve la cantidad sin tocar (comportamiento
        -- anterior, compatible con builds viejos).
        -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
        v_id_almacen := COALESCE(
            public.fn_almacen_de_extraccion(v_id_extraccion),
            public.fn_almacen_de_operacion(p_id_operacion)
        );

        IF v_id_almacen IS NULL THEN
            RETURN jsonb_build_object(
                'status','error',
                'message','No se pudo determinar el almacen para descontar la materia prima',
                'error_code','ALMACEN_NOT_RESOLVED',
                'id_operacion', p_id_operacion
            );
        END IF;

        v_cantidad_base := public.fn_cantidad_en_base(
            NULLIF(p_producto->>'id_presentacion', '')::BIGINT,
            (p_producto->>'cantidad')::NUMERIC
        );

        v_bom := public.fn_descontar_ingredientes_elaborado_v2(
            p_id_producto_elaborado := (p_producto->>'id_producto')::BIGINT,
            p_cantidad              := v_cantidad_base,
            p_id_almacen            := v_id_almacen,
            p_id_extraccion         := v_id_extraccion,
            p_origen_cambio         := 4
        );

        IF (v_bom->>'status') <> 'success' THEN
            RETURN jsonb_build_object(
                'status',        'error',
                'message',       COALESCE(v_bom->>'message', 'Error descontando materia prima'),
                'error_code',    COALESCE(v_bom->>'error_code', 'BOM_ERROR'),
                'id_ingrediente', v_bom->'id_ingrediente',
                'disponible',    COALESCE(v_bom->'cantidad_disponible', to_jsonb(0)),
                'requerido',     COALESCE(v_bom->'cantidad_requerida',  to_jsonb(0)),
                'id_almacen',    v_id_almacen
            );
        END IF;
    END IF;

    -- 7. Recalcular total
    SELECT COALESCE(SUM(cantidad * precio_unitario), 0)
      INTO v_nuevo_total
      FROM public.app_dat_extraccion_productos
     WHERE id_operacion = p_id_operacion;

    UPDATE public.app_dat_operacion_venta
       SET importe_total = v_nuevo_total
     WHERE id_operacion = p_id_operacion;

    -- 8. Registrar/acumular pago para el mÃ©todo seleccionado
    IF EXISTS (
        SELECT 1 FROM public.app_dat_pago_venta
         WHERE id_operacion_venta = p_id_operacion
           AND id_medio_pago = v_id_medio_pago
    ) THEN
        UPDATE public.app_dat_pago_venta
           SET monto = monto + v_importe
         WHERE id_operacion_venta = p_id_operacion
           AND id_medio_pago = v_id_medio_pago;
    ELSE
        INSERT INTO public.app_dat_pago_venta (id_operacion_venta, id_medio_pago, monto, created_at)
        VALUES (p_id_operacion, v_id_medio_pago, v_importe, NOW());
    END IF;

    -- 9. Log
    INSERT INTO public.app_dat_log_modificacion_orden
        (id_operacion, uuid_usuario, accion, detalle, created_at)
    VALUES (
        p_id_operacion,
        p_uuid_usuario,
        'add_product',
        jsonb_build_object(
            'id_extraccion',    v_id_extraccion,
            'producto',         p_producto,
            'importe',          v_importe,
            'id_medio_pago',    v_id_medio_pago,
            'nuevo_total_orden',v_nuevo_total,
            'id_almacen_bom',   v_id_almacen,
            'cantidad_base',    v_cantidad_base
        ),
        NOW()
    );

    RETURN jsonb_build_object(
        'status',        'success',
        'id_extraccion', v_id_extraccion,
        'importe',       v_importe,
        'total_orden',   v_nuevo_total,
        'message',       'Producto agregado correctamente'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('status','error','message','Error: ' || SQLERRM, 'sqlstate', SQLSTATE);
END;
$function$

