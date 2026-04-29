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
BEGIN
    -- Obtener información de la orden
    SELECT * INTO v_order_record
    FROM carnavalapp."Orders"
    WHERE id = NEW.order_id;

    -- Detectar si es una orden de paquetería: cuando es paquetería NO se debe
    -- modificar el inventario (cantidad_final permanece igual) y se ignora la
    -- validación de stock insuficiente.
    v_es_paqueteria := (v_order_record IS NOT NULL
                        AND v_order_record.paqueteria IS NOT NULL
                        AND v_order_record.paqueteria <> 'null'::jsonb);

    -- Solo procesar si la orden existe y está en estado "Creado" o "Pendiente de Pago"
    IF v_order_record IS NULL OR 
       (v_order_record.status NOT IN ('Creado', 'Pendiente de Pago','Nuevo','En Revision')) THEN
        RETURN NEW;
    END IF;

    -- Obtener UUID del usuario
    SELECT uuid, name, email, telefono INTO v_usuario_record
    FROM carnavalapp."Usuarios"
    WHERE id = v_order_record.user_id;

    IF v_usuario_record IS NULL THEN
        RAISE NOTICE 'Usuario no encontrado para orden %', v_order_record.id;
        RETURN NEW;
    END IF;

    -- Crear cliente una sola vez para toda la orden
    v_codigo_cliente := 'CLI' || UPPER(SUBSTRING(MD5(RANDOM()::TEXT) FROM 1 FOR 12));
    
    -- En paquetería el email del Usuario suele ser sintético (no cumple el
    -- CHECK app_dat_clientes_email_check). Se pasa NULL para evitar la
    -- violación. Si el email pasa el check (regex razonable), se usa.
    INSERT INTO public.app_dat_clientes (
        codigo_cliente, tipo_cliente, nombre_completo,
        email, telefono, activo
    ) VALUES (
        v_codigo_cliente, 1, COALESCE(v_usuario_record.name, 'Cliente App Carnaval'),
        CASE
            WHEN v_es_paqueteria THEN NULL
            WHEN v_usuario_record.email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
                THEN v_usuario_record.email
            ELSE NULL
        END,
        v_usuario_record.telefono, true
    ) RETURNING id INTO v_cliente_id;

    -- Obtener tipo de operación "Venta"
    SELECT id INTO v_tipo_operacion_id
    FROM public.app_nom_tipo_operacion
    WHERE denominacion ILIKE '%venta%'
    LIMIT 1;

    IF v_tipo_operacion_id IS NULL THEN
        RAISE NOTICE 'Tipo de operación Venta no encontrado';
        RETURN NEW;
    END IF;

    -- Procesar OrderDetails agrupados por proveedor
    FOR v_proveedor_actual IN 
        SELECT DISTINCT proveedor 
        FROM carnavalapp."OrderDetails"
        WHERE order_id = v_order_record.id
        AND proveedor IS NOT NULL
    LOOP
        -- Obtener ID de tienda según el proveedor del OrderDetail
        SELECT id INTO v_tienda_id
        FROM public.app_dat_tienda
        WHERE id_tienda_carnaval = v_proveedor_actual
        LIMIT 1;

        IF v_tienda_id IS NULL THEN
            RAISE NOTICE 'Tienda no encontrada para proveedor % en orden %', v_proveedor_actual, v_order_record.id;
            CONTINUE;
        END IF;

        -- Verificar si ya existe una operación para esta orden y tienda
        v_operacion_id := NULL;
        v_es_nueva_operacion := FALSE;

        SELECT id, uuid INTO v_operacion_id, v_usuario_operacion_uuid
        FROM public.app_dat_operaciones 
        WHERE observaciones = 'Venta desde orden ' || v_order_record.id 
        AND id_tienda = v_tienda_id
        LIMIT 1;

        -- Calcular importe total para este proveedor (se usa tanto en creación como actualización)
        SELECT COALESCE(SUM(price * COALESCE(quantity, 1)), 0) INTO v_importe_total_proveedor
        FROM carnavalapp."OrderDetails"
        WHERE order_id = v_order_record.id
        AND proveedor = v_proveedor_actual;

        IF v_operacion_id IS NULL THEN
            v_es_nueva_operacion := TRUE;
            
            -- Resetear variables de configuración por cada paso del loop
            v_tpv_config_id := NULL;
            v_vendedor_config_uuid := NULL;
            v_usuario_operacion_uuid := v_usuario_record.uuid; -- Default: Usuario de la orden (Cliente)

            -- Buscar configuración de tienda
            SELECT tpv_trabajador_encargado_carnaval INTO v_config_tienda
            FROM public.app_dat_configuracion_tienda
            WHERE id_tienda = v_tienda_id;

            -- Extraer datos si hay configuración
            IF v_config_tienda IS NOT NULL THEN
                v_tpv_config_id := (v_config_tienda ->> 'tpv_id')::BIGINT;
                v_vendedor_config_uuid := (v_config_tienda ->> 'app_dat_vendedor_uuid')::UUID;
                
                -- Si hay un vendedor configurado, usarlo como usuario de la operación
                IF v_vendedor_config_uuid IS NOT NULL THEN
                    v_usuario_operacion_uuid := v_vendedor_config_uuid;
                END IF;
            END IF;

            -- Obtener o crear TPV 
            -- Prioridad: 1. Configuración, 2. Búsqueda normal, 3. Creación
            IF v_tpv_config_id IS NOT NULL THEN
                v_tpv_id := v_tpv_config_id;
            ELSE
                -- Obtener o crear TPV para esta tienda
                SELECT id INTO v_tpv_id
                FROM public.app_dat_tpv
                WHERE id_tienda = v_tienda_id
                LIMIT 1;

                IF v_tpv_id IS NULL THEN
                    -- Crear almacén
                    INSERT INTO public.app_dat_almacen (
                        id_tienda, denominacion, direccion, ubicacion
                    ) VALUES (
                        v_tienda_id, 'Almacen para vender en carnaval', NULL, NULL
                    ) RETURNING id INTO v_almacen_id;

                    -- Crear TPV
                    INSERT INTO public.app_dat_tpv (
                        id_tienda, id_almacen, denominacion
                    ) VALUES (
                        v_tienda_id, v_almacen_id, 'TPV de venta carnaval'
                    ) RETURNING id INTO v_tpv_id;
                END IF;
            END IF;

            -- Crear operación para este proveedor
            INSERT INTO public.app_dat_operaciones (
                id_tipo_operacion, uuid, id_tienda,
                observaciones, created_at
            ) VALUES (
                v_tipo_operacion_id, v_usuario_operacion_uuid, v_tienda_id,
                'Venta desde orden ' || v_order_record.id, 
                now()
            ) RETURNING id INTO v_operacion_id;

            -- Crear operación de venta para este proveedor
            INSERT INTO public.app_dat_operacion_venta (
                id_operacion, id_tpv, denominacion,
                codigo_promocion, id_promocion, id_cliente,
                importe_total, es_pagada, id_turno_apertura
            ) VALUES (
                v_operacion_id, v_tpv_id, 'Venta desde orden ' || v_order_record.id,
                NULL, NULL, v_cliente_id,
                v_importe_total_proveedor, true, NULL
            );

            -- Determinar medio de pago (1=Efectivo, 4=Transferencia/Otro)
            v_medio_pago_id := CASE 
                WHEN v_order_record.metodo_pago ILIKE 'Efectivo' THEN 1
                ELSE 4
            END;

            -- Registrar pago asociado a la venta
            INSERT INTO public.app_dat_pago_venta (
                id_operacion_venta, id_medio_pago, monto, 
                creado_por, tipo_pago
            ) VALUES (
                v_operacion_id, v_medio_pago_id, v_importe_total_proveedor,
                v_usuario_operacion_uuid, 1
            );
        ELSE
            -- Operación ya existe: Actualizar importes
            RAISE NOTICE 'Operación ya existe (ID: %), actualizando productos e importes', v_operacion_id;
            
            UPDATE public.app_dat_operacion_venta 
            SET importe_total = v_importe_total_proveedor
            WHERE id_operacion = v_operacion_id
            RETURNING id_tpv INTO v_tpv_id;

            UPDATE public.app_dat_pago_venta 
            SET monto = v_importe_total_proveedor
            WHERE id_operacion_venta = v_operacion_id; 
            -- Nota: id_operacion_venta es PK igual a id_operacion en 1:1, pero en esquema id_operacion_venta es PK de app_dat_operacion_venta?
            -- Revisando esquema: app_dat_operacion_venta PK es id_operacion. 
            -- app_dat_pago_venta tiene FK id_operacion_venta -> app_dat_operacion_venta(id_operacion).
            -- Por tanto WHERE id_operacion_venta = v_operacion_id es correcto.
        END IF;

        -- Inicializar detalle de productos
        v_productos_detalle := '';

        -- Procesar todos los detalles de la orden para este proveedor
        FOR v_order_detail IN 
            SELECT * FROM carnavalapp."OrderDetails"
            WHERE order_id = v_order_record.id
            AND proveedor = v_proveedor_actual
        LOOP
            -- Obtener producto
            SELECT id, denominacion INTO v_producto_id, v_producto_nombre
            FROM public.app_dat_producto
            WHERE id_vendedor_app = v_order_detail.product_id
            LIMIT 1;

            IF v_producto_id IS NULL THEN
                CONTINUE;
            END IF;

            -- Verificar si el producto ya fue agregado a la operación
            IF EXISTS (
                SELECT 1 FROM public.app_dat_extraccion_productos
                WHERE id_operacion = v_operacion_id
                AND id_producto = v_producto_id
            ) THEN
                CONTINUE;
            END IF;
            SELECT stock::BIGINT INTO v_stock_producto
            FROM carnavalapp."Productos"
            WHERE id = v_order_detail.product_id;

            -- En paquetería el inventario no se valida ni se descuenta:
            -- el "producto" es el servicio de envío, no algo físico en stock.
            IF NOT v_es_paqueteria
               AND (COALESCE(v_order_detail.quantity, 1))::BIGINT > (COALESCE(v_stock_producto, 0))::BIGINT THEN
                RAISE NOTICE 'Stock insuficiente (producto carnaval %, stock %, solicitado %). No se actualiza inventario.',
                    v_order_detail.product_id, COALESCE(v_stock_producto, 0), COALESCE(v_order_detail.quantity, 1);
                CONTINUE;
            END IF;
            
            DECLARE
                v_ubicacion_especifica BIGINT;
            BEGIN
                SELECT id_ubicacion INTO v_ubicacion_especifica
                FROM public.relation_products_carnaval
                WHERE id_producto = v_producto_id
                  AND id_producto_carnaval = v_order_detail.product_id
                LIMIT 1;

                -- Obtener inventario más reciente según ubicación
                IF v_ubicacion_especifica IS NOT NULL THEN
                    SELECT * INTO v_inventario_record
                    FROM public.app_dat_inventario_productos
                    WHERE id_producto = v_producto_id
                      AND id_ubicacion = v_ubicacion_especifica
                    ORDER BY id desc, created_at DESC
                    LIMIT 1;
                    
                    RAISE NOTICE 'Usando ubicación específica % para producto % desde relation_products_carnaval', 
                        v_ubicacion_especifica, v_producto_id;
                ELSE
                    -- Obtener inventario más reciente
                    SELECT * INTO v_inventario_record
                    FROM public.app_dat_inventario_productos
                    WHERE id_producto = v_producto_id
                    ORDER BY id desc, created_at DESC
                    LIMIT 1;
                    RAISE NOTICE 'No se encontró ubicación específica para producto %, usando inventario más reciente', v_producto_id;
                END IF;
            END;

            -- En paquetería seguimos adelante aunque no haya inventario:
            -- registramos solo la extracción (con ubicación opcional) y NO
            -- modificamos cantidad_final.
            IF v_inventario_record IS NULL AND NOT v_es_paqueteria THEN
                CONTINUE;
            END IF;

            -- Crear extracción de producto
            INSERT INTO public.app_dat_extraccion_productos (
                id_operacion, id_producto, id_variante, id_opcion_variante,
                id_ubicacion, id_presentacion, cantidad, precio_unitario,
                sku_producto, sku_ubicacion, importe, importe_real
            ) VALUES (
                v_operacion_id, v_producto_id,
                CASE WHEN v_inventario_record IS NULL THEN NULL ELSE v_inventario_record.id_variante END,
                CASE WHEN v_inventario_record IS NULL THEN NULL ELSE v_inventario_record.id_opcion_variante END,
                CASE WHEN v_inventario_record IS NULL THEN NULL ELSE v_inventario_record.id_ubicacion END,
                CASE WHEN v_inventario_record IS NULL THEN NULL ELSE v_inventario_record.id_presentacion END,
                COALESCE(v_order_detail.quantity, 1),
                v_order_detail.price,
                CASE WHEN v_inventario_record IS NULL THEN NULL ELSE v_inventario_record.sku_producto END,
                CASE WHEN v_inventario_record IS NULL THEN NULL ELSE v_inventario_record.sku_ubicacion END,
                v_order_detail.price * COALESCE(v_order_detail.quantity, 1),
                v_order_detail.price * COALESCE(v_order_detail.quantity, 1)
            ) RETURNING id INTO v_extraccion_id;

            -- Actualizar inventario SOLO si no es paquetería y existe registro previo.
            -- En paquetería cantidad_final no debe cambiar.
            IF NOT v_es_paqueteria AND v_inventario_record IS NOT NULL THEN
                v_nueva_cantidad_final := GREATEST(0, v_inventario_record.cantidad_final - COALESCE(v_order_detail.quantity, 1));

                INSERT INTO public.app_dat_inventario_productos (
                    id_producto, id_variante, id_opcion_variante, id_ubicacion,
                    id_presentacion, cantidad_inicial, sku_producto, sku_ubicacion,
                    cantidad_final, origen_cambio, id_recepcion, id_extraccion,
                    id_control, id_proveedor
                ) VALUES (
                    v_producto_id, v_inventario_record.id_variante,
                    v_inventario_record.id_opcion_variante, v_inventario_record.id_ubicacion,
                    v_inventario_record.id_presentacion, v_inventario_record.cantidad_final,
                    v_inventario_record.sku_producto, v_inventario_record.sku_ubicacion,
                    v_nueva_cantidad_final, 2, NULL, v_extraccion_id, NULL, v_proveedor_actual
                );
            ELSE
                RAISE NOTICE 'Paquetería: omitiendo actualización de inventario para producto % (orden %)', v_producto_id, v_order_record.id;
            END IF;
            
            -- Agregar al detalle para notificación
            v_productos_detalle := v_productos_detalle || E'\n- ' || v_producto_nombre || ' (x' || COALESCE(v_order_detail.quantity, 1) || ')';
        END LOOP;

        -- Crear estado y notificación solo si se agregaron productos o es nueva
        IF v_productos_detalle <> '' THEN
            IF v_es_nueva_operacion THEN
                -- Determinar estado inicial (1 = Pendiente)
                v_estado_final := 1;

                -- Crear estado de operación
                INSERT INTO public.app_dat_estado_operacion (
                    id_operacion, estado, uuid, comentario
                ) VALUES (
                    v_operacion_id, v_estado_final, v_usuario_operacion_uuid,
                    'Creado desde orden ' || v_order_record.id || ' - ' || v_order_record.status
                );
            END IF;

             -- Crear notificación para el usuario asignado
            -- Solo si no existe ya una notificación para esta operación (evitar duplicados)
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
            RAISE NOTICE 'Operación % % para orden % - Proveedor %', v_operacion_id, 
                CASE WHEN v_es_nueva_operacion THEN 'creada' ELSE 'actualizada' END, 
                v_order_record.id, v_proveedor_actual;
        END IF;
    END LOOP;

    RETURN NEW;
END;