DECLARE
    new_product_id BIGINT;
    user_has_access BOOLEAN;
    tienda_id BIGINT;
    inserted_data JSONB := '{}'::JSONB;
    temp_json JSONB;
    temp_id BIGINT;
    variantes_insertadas JSONB := '{}'::JSONB;
    opciones_insertadas JSONB := '[]'::JSONB;
BEGIN
    -- Verificar permisos del usuario en la tienda
    tienda_id := (producto_data->>'id_tienda')::BIGINT;
    
    SELECT EXISTS (
        SELECT 1 FROM (
            SELECT id_tienda FROM app_dat_gerente WHERE uuid = auth.uid() AND id_tienda = tienda_id
            UNION
            SELECT id_tienda FROM app_dat_supervisor WHERE uuid = auth.uid() AND id_tienda = tienda_id
            UNION
            SELECT a.id_tienda FROM app_dat_almacenero al
            JOIN app_dat_almacen a ON al.id_almacen = a.id
            WHERE al.uuid = auth.uid() AND a.id_tienda = tienda_id
        ) AS usuarios_tienda
    ) INTO user_has_access;
    
    IF NOT user_has_access THEN
        RAISE EXCEPTION 'Acceso denegado: No tienes permisos para crear productos en esta tienda';
    END IF;

    -- ✅ INSERTAR PRODUCTO PRINCIPAL
    INSERT INTO app_dat_producto (
        id_tienda,
        sku,
        id_categoria,
        denominacion,
        nombre_comercial,
        denominacion_corta,
        descripcion,
        descripcion_corta,
        um,
        es_refrigerado,
        es_fragil,
        es_peligroso,
        es_vendible,
        es_comprable,
        es_inventariable,
        es_por_lotes,
        dias_alert_caducidad,
        codigo_barras,
        es_servicio,
        id_proveedor
    ) VALUES (
        (producto_data->>'id_tienda')::BIGINT,
        producto_data->>'sku',
        (producto_data->>'id_categoria')::BIGINT,
        producto_data->>'denominacion',
        producto_data->>'nombre_comercial',
        producto_data->>'denominacion_corta',
        producto_data->>'descripcion',
        producto_data->>'descripcion_corta',
        producto_data->>'um',
        COALESCE((producto_data->>'es_refrigerado')::BOOLEAN, FALSE),
        COALESCE((producto_data->>'es_fragil')::BOOLEAN, FALSE),
        COALESCE((producto_data->>'es_peligroso')::BOOLEAN, FALSE),
        COALESCE((producto_data->>'es_vendible')::BOOLEAN, TRUE),
        COALESCE((producto_data->>'es_comprable')::BOOLEAN, TRUE),
        COALESCE((producto_data->>'es_inventariable')::BOOLEAN, TRUE),
        COALESCE((producto_data->>'es_por_lotes')::BOOLEAN, FALSE),
        (producto_data->>'dias_alert_caducidad')::NUMERIC,
        producto_data->>'codigo_barras',
        COALESCE((producto_data->>'es_servicio')::BOOLEAN, FALSE),
        CASE 
            WHEN producto_data->>'id_proveedor' IS NOT NULL 
                 AND producto_data->>'id_proveedor' != 'null'
            THEN (producto_data->>'id_proveedor')::BIGINT
            ELSE NULL
        END
    ) RETURNING id INTO new_product_id;
    
    inserted_data := jsonb_set(inserted_data, '{producto_id}', to_jsonb(new_product_id));
    RAISE NOTICE 'Producto insertado con ID: %', new_product_id;
    -- ✅ LOGGING: Información del proveedor
    IF producto_data->>'id_proveedor' IS NOT NULL AND producto_data->>'id_proveedor' != 'null' THEN
        RAISE NOTICE ' Proveedor asignado: ID %', (producto_data->>'id_proveedor')::BIGINT;
        inserted_data := jsonb_set(inserted_data, '{id_proveedor}', to_jsonb((producto_data->>'id_proveedor')::BIGINT));
    ELSE
        RAISE NOTICE ' Sin proveedor asignado (opcional)';
        inserted_data := jsonb_set(inserted_data, '{id_proveedor}', 'null'::JSONB);
    END IF;
    
    -- ✅ INSERTAR SUBCATEGORÍAS
    IF subcategorias_data IS NOT NULL THEN
        INSERT INTO app_dat_productos_subcategorias (id_producto, id_sub_categoria)
        SELECT 
            new_product_id, 
            (subcategoria->>'id_sub_categoria')::BIGINT
        FROM unnest(subcategorias_data) AS subcategoria;
        
        inserted_data := jsonb_set(inserted_data, '{subcategorias_insertadas}', 
                                 (SELECT jsonb_agg(subcategoria) FROM unnest(subcategorias_data) AS subcategoria));
        RAISE NOTICE 'Subcategorías insertadas: %', array_length(subcategorias_data, 1);
    END IF;

    -- ✅ INSERTAR PRESENTACIONES
    IF presentaciones_data IS NOT NULL THEN
        WITH inserted_presentaciones AS (
            INSERT INTO app_dat_producto_presentacion (
                id_producto, 
                id_presentacion, 
                cantidad, 
                es_base
            )
            SELECT 
                new_product_id,
                (presentacion->>'id_presentacion')::BIGINT,
                (presentacion->>'cantidad')::NUMERIC,
                COALESCE((presentacion->>'es_base')::BOOLEAN, FALSE)
            FROM unnest(presentaciones_data) AS presentacion
            RETURNING id, id_presentacion, cantidad, es_base
        )
        SELECT jsonb_agg(jsonb_build_object(
            'id', id,
            'id_presentacion', id_presentacion,
            'cantidad', cantidad,
            'es_base', es_base
        )) INTO temp_json
        FROM inserted_presentaciones;
        
        inserted_data := jsonb_set(inserted_data, '{presentaciones_insertadas}', temp_json);
        RAISE NOTICE 'Presentaciones insertadas: %', array_length(presentaciones_data, 1);
    END IF;

    -- ✅ INSERTAR MULTIMEDIAS
    IF multimedias_data IS NOT NULL THEN
        INSERT INTO app_dat_producto_multimedias (id_producto, media)
        SELECT 
            new_product_id, 
            multimedia->>'media'
        FROM unnest(multimedias_data) AS multimedia;
        
        inserted_data := jsonb_set(inserted_data, '{multimedias_insertadas}', 
                                 (SELECT jsonb_agg(multimedia) FROM unnest(multimedias_data) AS multimedia));
        RAISE NOTICE 'Multimedias insertadas: %', array_length(multimedias_data, 1);
    END IF;

    -- ✅ INSERTAR ETIQUETAS
    IF etiquetas_data IS NOT NULL THEN
        INSERT INTO app_dat_producto_etiquetas (id_producto, etiqueta)
        SELECT 
            new_product_id, 
            etiqueta->>'etiqueta'
        FROM unnest(etiquetas_data) AS etiqueta;
        
        inserted_data := jsonb_set(inserted_data, '{etiquetas_insertadas}', 
                                 (SELECT jsonb_agg(etiqueta) FROM unnest(etiquetas_data) AS etiqueta));
        RAISE NOTICE 'Etiquetas insertadas: %', array_length(etiquetas_data, 1);
    END IF;

    -- ✅ CORREGIDO: INSERTAR VARIANTES Y OPCIONES
    IF variantes_data IS NOT NULL THEN
        DECLARE
            variante_record RECORD;
            opcion_item JSONB;
            opcion_id BIGINT;
        BEGIN
            FOR temp_json IN SELECT * FROM unnest(variantes_data)
            LOOP
                -- Insertar variante
                INSERT INTO app_dat_variantes (
                    id_sub_categoria,
                    id_atributo
                ) VALUES (
                    (temp_json->>'id_sub_categoria')::BIGINT,
                    (temp_json->>'id_atributo')::BIGINT
                ) RETURNING id INTO temp_id;
                
                RAISE NOTICE 'Variante insertada con ID: %', temp_id;
                
                -- ✅ NUEVO: Insertar opciones de la variante
                IF temp_json->'opciones' IS NOT NULL THEN
                    FOR opcion_item IN SELECT * FROM jsonb_array_elements(temp_json->'opciones')
                    LOOP
                        -- Verificar si la opción ya existe o crearla
                        IF opcion_item->>'id_opcion' IS NOT NULL AND opcion_item->>'id_opcion' != 'null' THEN
                            -- Usar opción existente
                            opcion_id := (opcion_item->>'id_opcion')::BIGINT;
                        ELSE
                            -- Crear nueva opción
                            INSERT INTO app_dat_atributo_opcion (
                                id_atributo,
                                valor,
                                sku_codigo
                            ) VALUES (
                                (temp_json->>'id_atributo')::BIGINT,
                                opcion_item->>'valor',
                                opcion_item->>'sku_codigo'
                            ) RETURNING id INTO opcion_id;
                        END IF;
                        
                        -- Registrar opción insertada/usada
                        opciones_insertadas := opciones_insertadas || jsonb_build_object(
                            'id_opcion', opcion_id,
                            'id_variante', temp_id,
                            'valor', opcion_item->>'valor',
                            'sku_codigo', opcion_item->>'sku_codigo'
                        );
                        
                        RAISE NOTICE 'Opción procesada: % para variante: %', opcion_id, temp_id;
                    END LOOP;
                END IF;
                
                -- Registrar variante insertada
                variantes_insertadas := jsonb_set(variantes_insertadas, 
                                                ARRAY[temp_id::TEXT], 
                                                jsonb_build_object(
                                                    'id_variante', temp_id,
                                                    'id_sub_categoria', (temp_json->>'id_sub_categoria')::BIGINT,
                                                    'id_atributo', (temp_json->>'id_atributo')::BIGINT,
                                                    'opciones', temp_json->'opciones'
                                                ));
            END LOOP;
        END;
        
        inserted_data := jsonb_set(inserted_data, '{variantes_insertadas}', variantes_insertadas);
        inserted_data := jsonb_set(inserted_data, '{opciones_insertadas}', opciones_insertadas);
        RAISE NOTICE 'Total variantes insertadas: %', jsonb_object_keys(variantes_insertadas);
    END IF;

    -- ✅ CORREGIDO: INSERTAR PRECIOS (maneja array)
    IF precios_data IS NOT NULL AND array_length(precios_data, 1) > 0 THEN
        DECLARE
            precio_item JSONB;
            precio_valor NUMERIC;
            fecha_desde_valor DATE;
            fecha_hasta_valor DATE;
            precio_counter INTEGER := 0;
            variante_ids BIGINT[];
            variante_id_actual BIGINT;
        BEGIN
            RAISE NOTICE 'Procesando % precios para producto: %', array_length(precios_data, 1), new_product_id;
            
            IF variantes_data IS NOT NULL THEN
                -- Con variantes: obtener IDs de variantes creadas
                SELECT ARRAY(
                    SELECT jsonb_object_keys(variantes_insertadas)::BIGINT
                ) INTO variante_ids;
                
                -- Iterar sobre cada precio en el array
                FOR precio_counter IN 1..array_length(precios_data, 1)
                LOOP
                    precio_item := precios_data[precio_counter];
                    precio_valor := COALESCE((precio_item->>'precio_venta_cup')::NUMERIC, 0.0);
                    fecha_desde_valor := COALESCE((precio_item->>'fecha_desde')::DATE, CURRENT_DATE);
                    fecha_hasta_valor := (precio_item->>'fecha_hasta')::DATE;
                    
                    -- Asignar variante por índice o usar la especificada
                    IF precio_item->>'id_variante' IS NOT NULL AND precio_item->>'id_variante' != 'null' THEN
                        variante_id_actual := (precio_item->>'id_variante')::BIGINT;
                    ELSE
                        -- Usar variante correspondiente por índice
                        IF precio_counter <= array_length(variante_ids, 1) THEN
                            variante_id_actual := variante_ids[precio_counter];
                        ELSE
                            variante_id_actual := variante_ids[1]; -- Fallback a primera variante
                        END IF;
                    END IF;
                    
                    INSERT INTO app_dat_precio_venta (
                        id_producto,
                        id_variante,
                        precio_venta_cup,
                        fecha_desde,
                        fecha_hasta
                    ) VALUES (
                        new_product_id,
                        variante_id_actual,
                        precio_valor,
                        fecha_desde_valor,
                        fecha_hasta_valor
                    );
                    
                    RAISE NOTICE 'Precio % insertado: % para variante: %', precio_counter, precio_valor, variante_id_actual;
                END LOOP;
            ELSE
                -- Sin variantes: insertar todos los precios como precios base
                FOR precio_counter IN 1..array_length(precios_data, 1)
                LOOP
                    precio_item := precios_data[precio_counter];
                    precio_valor := COALESCE((precio_item->>'precio_venta_cup')::NUMERIC, 0.0);
                    
                    INSERT INTO app_dat_precio_venta (
                        id_producto,
                        id_variante,
                        precio_venta_cup,
                        fecha_desde,
                        fecha_hasta
                    ) VALUES (
                        new_product_id,
                        NULL,
                        precio_valor,
                        COALESCE((precio_item->>'fecha_desde')::DATE, CURRENT_DATE),
                        (precio_item->>'fecha_hasta')::DATE
                    );
                    
                    RAISE NOTICE 'Precio base % insertado: %', precio_counter, precio_valor;
                END LOOP;
            END IF;
            
            inserted_data := jsonb_set(inserted_data, '{precios_insertados}', 
                                     jsonb_build_object(
                                         'total_precios', array_length(precios_data, 1),
                                         'precios', precios_data
                                     ));
        END;
    END IF;

    -- Retornar todos los IDs insertados
    RETURN jsonb_build_object(
        'success', true,
        'message', 'Producto y relaciones insertados correctamente',
        'data', inserted_data
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Error al insertar producto: ' || SQLERRM,
            'error_code', SQLSTATE
        );
END;