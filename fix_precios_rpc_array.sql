-- ✅ SECCIÓN DE PRECIOS CORREGIDA para manejar ARRAY de precios
-- Reemplaza la sección de precios en insert_producto_completo con esto:

-- Insertar precios (maneja array de precios)
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
            
            RAISE NOTICE 'Variantes creadas: %', variante_ids;
            
            -- Iterar sobre cada precio en el array
            FOR precio_counter IN 1..array_length(precios_data, 1)
            LOOP
                precio_item := precios_data[precio_counter];
                precio_valor := COALESCE((precio_item->>'precio_venta_cup')::NUMERIC, 0.0);
                fecha_desde_valor := COALESCE((precio_item->>'fecha_desde')::DATE, CURRENT_DATE);
                fecha_hasta_valor := (precio_item->>'fecha_hasta')::DATE;
                
                -- Si hay id_variante específico en el precio, usarlo
                IF precio_item->>'id_variante' IS NOT NULL AND precio_item->>'id_variante' != 'null' THEN
                    variante_id_actual := (precio_item->>'id_variante')::BIGINT;
                ELSE
                    -- Si no hay id_variante específico, usar la variante correspondiente por índice
                    IF precio_counter <= array_length(variante_ids, 1) THEN
                        variante_id_actual := variante_ids[precio_counter];
                    ELSE
                        -- Si hay más precios que variantes, usar la primera variante
                        variante_id_actual := variante_ids[1];
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
                fecha_desde_valor := COALESCE((precio_item->>'fecha_desde')::DATE, CURRENT_DATE);
                fecha_hasta_valor := (precio_item->>'fecha_hasta')::DATE;
                
                INSERT INTO app_dat_precio_venta (
                    id_producto,
                    id_variante,
                    precio_venta_cup,
                    fecha_desde,
                    fecha_hasta
                ) VALUES (
                    new_product_id,
                    NULL, -- Sin variante
                    precio_valor,
                    fecha_desde_valor,
                    fecha_hasta_valor
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

-- ✅ EJEMPLO DE USO:
-- Ahora puedes enviar múltiples precios así:
/*
precios_data = [
    {
        "precio_venta_cup": 45.0,
        "fecha_desde": "2025-08-30",
        "id_variante": null  // Se asignará automáticamente
    },
    {
        "precio_venta_cup": 50.0,
        "fecha_desde": "2025-09-01",
        "id_variante": null  // Se asignará automáticamente
    }
]
*/
