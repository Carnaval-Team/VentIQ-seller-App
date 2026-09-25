-- ============================================================
-- Actualización de función: carnavalapp.fn_crear_operacion_desde_orden2()
-- Propósito: Capturar el precio oficial de venta (`precio_venta_cup`)
-- desde `public.app_dat_precio_venta` para el producto extraído y
-- guardarlo en la columna `precio_oficial_venta` de `public.app_dat_extraccion_productos`.
-- ============================================================

CREATE OR REPLACE FUNCTION carnavalapp.fn_crear_operacion_desde_orden2()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_order_record RECORD;
    v_usuario_record RECORD;
    v_order_detail RECORD;
    v_proveedor_actual BIGINT;
    v_tienda_id BIGINT;
    v_cliente_id BIGINT;
    v_tpv_id BIGINT;
    v_almacen_id BIGINT;
    v_tipo_operacion_id BIGINT;
    v_operacion_id BIGINT;
    v_producto_id BIGINT;
    v_inventario_record RECORD;
    v_extraccion_id BIGINT;
    v_nueva_cantidad_final NUMERIC;
    v_estado_final INTEGER;
    v_codigo_cliente VARCHAR(20);
    v_importe_total_proveedor NUMERIC;
    v_stock_producto BIGINT;
    -- Variables para configuración de tienda
    v_config_tienda JSONB;
    v_tpv_config_id BIGINT;
    v_vendedor_config_uuid UUID;
    v_usuario_operacion_uuid UUID;
    v_es_nueva_operacion BOOLEAN;

    v_productos_detalle TEXT;
    v_producto_nombre VARCHAR(255);
    v_medio_pago_id SMALLINT;
    v_es_paqueteria BOOLEAN;
    v_cantidad_solicitada NUMERIC;
    v_cantidad_real NUMERIC;
    v_stock_disponible NUMERIC;
    v_precio_oficial_venta NUMERIC;
    -- Variable para presentación de inventario
    v_presentacion_id_inv BIGINT;
    v_tiene_inventario BOOLEAN := FALSE;
BEGIN
    -- Obtener información de la orden
    SELECT * INTO v_order_record
    FROM carnavalapp."Orders"
    WHERE id = NEW.order_id;

    v_es_paqueteria := COALESCE(
        v_order_record IS NOT NULL
        AND v_order_record.paqueteria IS NOT NULL
        AND v_order_record.paqueteria <> 'null'::jsonb
        AND jsonb_typeof(v_order_record.paqueteria) = 'object'
        AND v_order_record.paqueteria <> '{}'::jsonb,
        FALSE
    );

    IF v_order_record IS NULL OR 
       (v_order_record.status NOT IN ('Creado', 'Pendiente de Pago','Nuevo','En Revision')) THEN
        RETURN NEW;
    END IF;

    SELECT uuid, name, email, telefono INTO v_usuario_record
    FROM carnavalapp."Usuarios"
    WHERE id = v_order_record.user_id;

    IF v_usuario_record IS NULL THEN
        RETURN NEW;
    END IF;

    v_codigo_cliente := 'CLI' || UPPER(SUBSTRING(MD5(RANDOM()::TEXT) FROM 1 FOR 12));

    INSERT INTO public.app_dat_clientes (
        codigo_cliente, tipo_cliente, nombre_completo,
        email, telefono, activo
    ) VALUES (
        v_codigo_cliente, 1, COALESCE(v_usuario_record.name, 'Cliente App Carnaval'),
        CASE
            WHEN v_usuario_record.email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
                THEN v_usuario_record.email
            ELSE NULL
        END,
        v_usuario_record.telefono, true
    ) RETURNING id INTO v_cliente_id;

    SELECT id INTO v_tipo_operacion_id
    FROM public.app_nom_tipo_operacion
    WHERE denominacion ILIKE '%venta%'
    LIMIT 1;

    IF v_tipo_operacion_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF NEW.proveedor IS NULL THEN
        RETURN NEW;
    END IF;

    FOR v_proveedor_actual IN SELECT NEW.proveedor LOOP
        SELECT id INTO v_tienda_id
        FROM public.app_dat_tienda
        WHERE id_tienda_carnaval = v_proveedor_actual
        LIMIT 1;

        IF v_tienda_id IS NULL THEN
            CONTINUE;
        END IF;

        v_operacion_id := NULL;
        v_es_nueva_operacion := FALSE;

        SELECT id, uuid INTO v_operacion_id, v_usuario_operacion_uuid
        FROM public.app_dat_operaciones 
        WHERE observaciones = 'Venta desde orden ' || v_order_record.id 
        AND id_tienda = v_tienda_id
        LIMIT 1;

        WITH detalles AS (
            SELECT od.id, od.price, od.quantity
            FROM carnavalapp."OrderDetails" od
            WHERE od.order_id = v_order_record.id
              AND od.proveedor = v_proveedor_actual
            UNION
            SELECT NEW.id, NEW.price, NEW.quantity
            FROM (SELECT 1) _
            WHERE NEW.proveedor = v_proveedor_actual
        )
        SELECT COALESCE(SUM(price * COALESCE(quantity, 1)), 0)
        INTO v_importe_total_proveedor
        FROM detalles;

        IF v_operacion_id IS NULL THEN
            v_es_nueva_operacion := TRUE;
            v_tpv_config_id := NULL;
            v_vendedor_config_uuid := NULL;
            v_usuario_operacion_uuid := v_usuario_record.uuid;

            SELECT tpv_trabajador_encargado_carnaval INTO v_config_tienda
            FROM public.app_dat_configuracion_tienda
            WHERE id_tienda = v_tienda_id;

            IF v_config_tienda IS NOT NULL THEN
                v_tpv_config_id := (v_config_tienda ->> 'tpv_id')::BIGINT;
                v_vendedor_config_uuid := (v_config_tienda ->> 'app_dat_vendedor_uuid')::UUID;
                IF v_vendedor_config_uuid IS NOT NULL THEN
                    v_usuario_operacion_uuid := v_vendedor_config_uuid;
                END IF;
            END IF;

            IF v_tpv_config_id IS NOT NULL THEN
                v_tpv_id := v_tpv_config_id;
            ELSE
                SELECT id INTO v_tpv_id
                FROM public.app_dat_tpv
                WHERE id_tienda = v_tienda_id
                LIMIT 1;

                IF v_tpv_id IS NULL THEN
                    INSERT INTO public.app_dat_almacen (
                        id_tienda, denominacion, direccion, ubicacion
                    ) VALUES (
                        v_tienda_id, 'Almacen para vender en carnaval', NULL, NULL
                    ) RETURNING id INTO v_almacen_id;

                    INSERT INTO public.app_dat_tpv (
                        id_tienda, id_almacen, denominacion
                    ) VALUES (
                        v_tienda_id, v_almacen_id, 'TPV de venta carnaval'
                    ) RETURNING id INTO v_tpv_id;
                END IF;
            END IF;

            INSERT INTO public.app_dat_operaciones (
                id_tipo_operacion, uuid, id_tienda,
                observaciones, created_at, id_carnaval_order
            ) VALUES (
                v_tipo_operacion_id, v_usuario_operacion_uuid, v_tienda_id,
                'Venta desde orden ' || v_order_record.id, 
                now(), v_order_record.id
            ) RETURNING id INTO v_operacion_id;

            INSERT INTO public.app_dat_operacion_venta (
                id_operacion, id_tpv, denominacion,
                codigo_promocion, id_promocion, id_cliente,
                importe_total, es_pagada, id_turno_apertura
            ) VALUES (
                v_operacion_id, v_tpv_id, 'Venta desde orden ' || v_order_record.id,
                NULL, NULL, v_cliente_id,
                v_importe_total_proveedor, true, NULL
            );

            v_medio_pago_id := CASE 
                WHEN v_order_record.metodo_pago ILIKE 'Efectivo' THEN 1
                ELSE 4
            END;

            INSERT INTO public.app_dat_pago_venta (
                id_operacion_venta, id_medio_pago, monto, 
                creado_por, tipo_pago
            ) VALUES (
                v_operacion_id, v_medio_pago_id, v_importe_total_proveedor,
                v_usuario_operacion_uuid, 1
            );
        ELSE
            UPDATE public.app_dat_operacion_venta 
            SET importe_total = v_importe_total_proveedor
            WHERE id_operacion = v_operacion_id
            RETURNING id_tpv INTO v_tpv_id;

            UPDATE public.app_dat_pago_venta 
            SET monto = v_importe_total_proveedor
            WHERE id_operacion_venta = v_operacion_id;
        END IF;

        v_productos_detalle := '';

        FOR v_order_detail IN SELECT NEW.* LOOP
            SELECT id, denominacion INTO v_producto_id, v_producto_nombre
            FROM public.app_dat_producto
            WHERE id_vendedor_app = v_order_detail.product_id
            LIMIT 1;

            IF v_producto_id IS NULL THEN
                CONTINUE;
            END IF;

            -- Obtener precio oficial de venta desde app_dat_precio_venta
            SELECT pv.precio_venta_cup
            INTO v_precio_oficial_venta
            FROM public.app_dat_precio_venta pv
            WHERE pv.id_producto = v_producto_id
            ORDER BY pv.created_at DESC
            LIMIT 1;

            v_cantidad_solicitada := COALESCE(v_order_detail.quantity, 1);

            DECLARE
                v_ubicacion_especifica BIGINT;
            BEGIN
                SELECT id_ubicacion INTO v_ubicacion_especifica
                FROM public.relation_products_carnaval
                WHERE id_producto = v_producto_id
                  AND id_producto_carnaval = v_order_detail.product_id
                LIMIT 1;

                IF v_ubicacion_especifica IS NOT NULL THEN
                    SELECT * INTO v_inventario_record
                    FROM public.app_dat_inventario_productos
                    WHERE id_producto = v_producto_id
                      AND id_ubicacion = v_ubicacion_especifica
                    ORDER BY id desc, created_at DESC
                    LIMIT 1;
                    v_tiene_inventario := FOUND;
                ELSE
                    SELECT * INTO v_inventario_record
                    FROM public.app_dat_inventario_productos
                    WHERE id_producto = v_producto_id
                    ORDER BY id desc, created_at DESC
                    LIMIT 1;
                    v_tiene_inventario := FOUND;
                END IF;
            END;

            IF v_es_paqueteria THEN
                v_cantidad_real := v_cantidad_solicitada;
            ELSE
                v_stock_disponible := COALESCE(v_inventario_record.cantidad_final, 0);

                IF v_stock_disponible <= 0 THEN
                    DELETE FROM carnavalapp."OrderDetails"
                    WHERE id = v_order_detail.id;

                    SELECT COALESCE(SUM(price * COALESCE(quantity, 1)), 0)
                    INTO v_importe_total_proveedor
                    FROM carnavalapp."OrderDetails"
                    WHERE order_id = v_order_record.id
                      AND proveedor = v_proveedor_actual;

                    UPDATE public.app_dat_operacion_venta
                    SET importe_total = v_importe_total_proveedor
                    WHERE id_operacion = v_operacion_id;

                    UPDATE public.app_dat_pago_venta
                    SET monto = v_importe_total_proveedor
                    WHERE id_operacion_venta = v_operacion_id;

                    CONTINUE;
                END IF;

                IF v_cantidad_solicitada > v_stock_disponible THEN
                    v_cantidad_real := v_stock_disponible;

                    UPDATE carnavalapp."OrderDetails"
                    SET quantity = v_cantidad_real
                    WHERE id = v_order_detail.id;

                    SELECT COALESCE(SUM(price * COALESCE(quantity, 1)), 0)
                    INTO v_importe_total_proveedor
                    FROM carnavalapp."OrderDetails"
                    WHERE order_id = v_order_record.id
                      AND proveedor = v_proveedor_actual;

                    UPDATE public.app_dat_operacion_venta
                    SET importe_total = v_importe_total_proveedor
                    WHERE id_operacion = v_operacion_id;

                    UPDATE public.app_dat_pago_venta
                    SET monto = v_importe_total_proveedor
                    WHERE id_operacion_venta = v_operacion_id;
                ELSE
                    v_cantidad_real := v_cantidad_solicitada;
                END IF;
            END IF;

            IF NOT v_tiene_inventario AND NOT v_es_paqueteria THEN
                CONTINUE;
            END IF;

            -- Crear extracción de producto incluyendo precio_oficial_venta
            INSERT INTO public.app_dat_extraccion_productos (
                id_operacion, id_producto, id_variante, id_opcion_variante,
                id_ubicacion, id_presentacion, cantidad, precio_unitario,
                sku_producto, sku_ubicacion, importe, importe_real,
                precio_oficial_venta
            ) VALUES (
                v_operacion_id, v_producto_id,
                CASE WHEN v_inventario_record IS NULL THEN NULL ELSE v_inventario_record.id_variante END,
                CASE WHEN v_inventario_record IS NULL THEN NULL ELSE v_inventario_record.id_opcion_variante END,
                CASE WHEN v_inventario_record IS NULL THEN NULL ELSE v_inventario_record.id_ubicacion END,
                CASE WHEN v_inventario_record IS NULL THEN NULL ELSE v_inventario_record.id_presentacion END,
                v_cantidad_real,
                v_order_detail.price,
                CASE WHEN v_inventario_record IS NULL THEN NULL ELSE v_inventario_record.sku_producto END,
                CASE WHEN v_inventario_record IS NULL THEN NULL ELSE v_inventario_record.sku_ubicacion END,
                v_order_detail.price * v_cantidad_real,
                v_order_detail.price * v_cantidad_real,
                v_precio_oficial_venta
            ) RETURNING id INTO v_extraccion_id;

            IF NOT v_es_paqueteria AND v_tiene_inventario THEN
                v_nueva_cantidad_final := GREATEST(0, v_inventario_record.cantidad_final - v_cantidad_real);

                IF v_inventario_record.id_presentacion IS NULL THEN
                    SELECT id INTO v_presentacion_id_inv
                    FROM public.app_dat_producto_presentacion
                    WHERE id_producto = v_producto_id
                    ORDER BY id ASC
                    LIMIT 1;

                    IF v_presentacion_id_inv IS NULL THEN
                        CONTINUE;
                    END IF;
                ELSE
                    v_presentacion_id_inv := v_inventario_record.id_presentacion;
                END IF;

                BEGIN
                    INSERT INTO public.app_dat_inventario_productos (
                        id_producto, id_variante, id_opcion_variante, id_ubicacion,
                        id_presentacion, cantidad_inicial, sku_producto, sku_ubicacion,
                        cantidad_final, origen_cambio, id_recepcion, id_extraccion,
                        id_control, id_proveedor
                    ) VALUES (
                        v_producto_id, v_inventario_record.id_variante,
                        v_inventario_record.id_opcion_variante, v_inventario_record.id_ubicacion,
                        v_presentacion_id_inv, v_inventario_record.cantidad_final,
                        v_inventario_record.sku_producto, v_inventario_record.sku_ubicacion,
                        v_nueva_cantidad_final, 2, NULL, v_extraccion_id, NULL, v_proveedor_actual
                    );
                EXCEPTION
                    WHEN OTHERS THEN
                        NULL;
                END;
            END IF;

            v_productos_detalle := v_productos_detalle || E'\n- ' || v_producto_nombre || ' (x' || v_cantidad_real || ')';
        END LOOP;

        IF v_productos_detalle <> '' THEN
            IF v_es_nueva_operacion THEN
                v_estado_final := 1;
                INSERT INTO public.app_dat_estado_operacion (
                    id_operacion, estado, uuid, comentario
                ) VALUES (
                    v_operacion_id, v_estado_final, v_usuario_operacion_uuid,
                    'Creado desde orden ' || v_order_record.id || ' - ' || v_order_record.status
                );
            END IF;

            IF NOT EXISTS (
                SELECT 1 FROM public.app_dat_notificaciones 
                WHERE data->>'operacion_id' = v_operacion_id::TEXT
                AND tipo = 'venta'
            ) THEN
                INSERT INTO public.app_dat_notificaciones (
                    user_id, tipo, titulo, mensaje, data, prioridad
                ) VALUES (
                    v_usuario_operacion_uuid,
                    'venta',
                    CASE WHEN v_es_nueva_operacion THEN 'Nueva compra desde carnaval (Orden #' || v_order_record.id || ')'
                         ELSE 'Actualización de orden #' || v_order_record.id END,
                    'Cliente: ' || COALESCE(v_usuario_record.name, 'Cliente App Carnaval') || E'\nProductos:' || v_productos_detalle,
                    jsonb_build_object(
                        'operacion_id', v_operacion_id,
                        'orden_id', v_order_record.id,
                        'tpv_id', v_tpv_id
                    ),
                    'alta'
                );
            END IF;
        END IF;
    END LOOP;

    RETURN NEW;
END;
$function$;
