-- ✅ SECCIÓN DE PRECIOS CORREGIDA para insert_producto_completo
-- Reemplaza la sección de precios existente con esto:

-- Insertar precios
IF precios_data IS NOT NULL THEN
    DECLARE
        primer_precio JSONB;
        precio_valor NUMERIC;
        fecha_desde_valor DATE;
        fecha_hasta_valor DATE;
    BEGIN
        -- Tomar el primer precio del array (ya que envías uno solo)
        primer_precio := precios_data[1];
        
        -- Extraer valores con validación
        precio_valor := COALESCE((primer_precio->>'precio_venta_cup')::NUMERIC, 0.0);
        fecha_desde_valor := COALESCE((primer_precio->>'fecha_desde')::DATE, CURRENT_DATE);
        fecha_hasta_valor := (primer_precio->>'fecha_hasta')::DATE;
        
        -- Debug log
        RAISE NOTICE 'Insertando precio: % para producto: %', precio_valor, new_product_id;
        
        IF variantes_data IS NOT NULL THEN
            -- Con variantes: insertar precio para cada variante creada
            DECLARE
                variante_id_actual BIGINT;
            BEGIN
                -- Iterar sobre las variantes insertadas
                FOR variante_id_actual IN 
                    SELECT jsonb_object_keys(variantes_insertadas)::BIGINT
                LOOP
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
                    
                    RAISE NOTICE 'Precio insertado para variante: %', variante_id_actual;
                END LOOP;
            END;
        ELSE
            -- Sin variantes: precio base del producto
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
                fecha_desde_valor,
                fecha_hasta_valor
            );
            
            RAISE NOTICE 'Precio base insertado: %', precio_valor;
        END IF;
        
        inserted_data := jsonb_set(inserted_data, '{precios_insertados}', 
                                 jsonb_build_object('precio_venta_cup', precio_valor));
    END;
END IF;

-- ✅ ALTERNATIVA MÁS SIMPLE (si prefieres):
-- Si solo quieres un precio base sin complicaciones con variantes:

/*
IF precios_data IS NOT NULL AND array_length(precios_data, 1) > 0 THEN
    DECLARE
        precio_valor NUMERIC;
    BEGIN
        precio_valor := COALESCE((precios_data[1]->>'precio_venta_cup')::NUMERIC, 0.0);
        
        RAISE NOTICE 'Insertando precio simple: % para producto: %', precio_valor, new_product_id;
        
        INSERT INTO app_dat_precio_venta (
            id_producto,
            id_variante,
            precio_venta_cup,
            fecha_desde,
            fecha_hasta
        ) VALUES (
            new_product_id,
            NULL, -- Sin variante específica
            precio_valor,
            COALESCE((precios_data[1]->>'fecha_desde')::DATE, CURRENT_DATE),
            (precios_data[1]->>'fecha_hasta')::DATE
        );
        
        inserted_data := jsonb_set(inserted_data, '{precio_insertado}', 
                                 jsonb_build_object('precio_venta_cup', precio_valor));
    END;
END IF;
*/
