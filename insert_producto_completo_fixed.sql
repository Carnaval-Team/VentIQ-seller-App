-- Función corregida para insert_producto_completo
-- PROBLEMA PRINCIPAL: Lógica de inserción de precios incorrecta

-- ✅ SECCIÓN DE PRECIOS CORREGIDA:
IF precios_data IS NOT NULL THEN
    IF variantes_data IS NOT NULL THEN
        -- Con variantes: crear un precio específico por cada variante
        DECLARE
            variante_record RECORD;
            precio_record RECORD;
            variante_counter INTEGER := 0;
        BEGIN
            -- Iterar sobre las variantes insertadas
            FOR variante_record IN 
                SELECT jsonb_array_elements_text(jsonb_object_keys(variantes_insertadas))::BIGINT as variante_id
            LOOP
                variante_counter := variante_counter + 1;
                
                -- Obtener el precio correspondiente (por índice o usar el primero si solo hay uno)
                SELECT * INTO precio_record 
                FROM (
                    SELECT 
                        row_number() OVER () as rn,
                        precio
                    FROM unnest(precios_data) AS precio
                ) numbered_precios 
                WHERE rn = LEAST(variante_counter, array_length(precios_data, 1))
                LIMIT 1;
                
                -- Insertar precio para esta variante específica
                INSERT INTO app_dat_precio_venta (
                    id_producto,
                    id_variante,
                    precio_venta_cup,
                    fecha_desde,
                    fecha_hasta
                ) VALUES (
                    new_product_id,
                    variante_record.variante_id,
                    COALESCE((precio_record.precio->>'precio_venta_cup')::NUMERIC, 0.0),
                    COALESCE((precio_record.precio->>'fecha_desde')::DATE, CURRENT_DATE),
                    (precio_record.precio->>'fecha_hasta')::DATE
                );
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
        )
        SELECT 
            new_product_id,
            NULL,
            COALESCE((precio->>'precio_venta_cup')::NUMERIC, 0.0),
            COALESCE((precio->>'fecha_desde')::DATE, CURRENT_DATE),
            (precio->>'fecha_hasta')::DATE
        FROM unnest(precios_data) AS precio;
    END IF;
    
    inserted_data := jsonb_set(inserted_data, '{precios_insertados}', 
                             (SELECT jsonb_agg(precio) FROM unnest(precios_data) AS precio));
END IF;

-- ✅ ALTERNATIVA MÁS SIMPLE Y ROBUSTA:
-- Si solo necesitas un precio base por producto (sin variantes específicas):

IF precios_data IS NOT NULL AND array_length(precios_data, 1) > 0 THEN
    DECLARE
        primer_precio JSONB;
        precio_valor NUMERIC;
    BEGIN
        -- Tomar el primer precio del array
        primer_precio := precios_data[1];
        
        -- Extraer y validar el valor del precio
        precio_valor := COALESCE(
            (primer_precio->>'precio_venta_cup')::NUMERIC,
            (primer_precio->>'precio')::NUMERIC,
            (primer_precio->>'precio_venta')::NUMERIC,
            0.0
        );
        
        -- Debug: Log del precio que se va a insertar
        RAISE NOTICE 'Insertando precio: % para producto: %', precio_valor, new_product_id;
        
        -- Insertar precio base (sin variante específica)
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
            COALESCE((primer_precio->>'fecha_desde')::DATE, CURRENT_DATE),
            (primer_precio->>'fecha_hasta')::DATE
        );
        
        inserted_data := jsonb_set(inserted_data, '{precio_insertado}', 
                                 jsonb_build_object('precio_venta_cup', precio_valor));
    END;
END IF;
