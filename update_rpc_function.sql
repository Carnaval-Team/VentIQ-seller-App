-- Eliminar la función anterior si existe
DROP FUNCTION IF EXISTS fn_crear_estructura_tienda_completa(uuid, character varying, character varying, character varying, jsonb, jsonb, jsonb, jsonb);

-- Crear la nueva función corregida
CREATE OR REPLACE FUNCTION crear_estructura_tienda(
    usuario_creador uuid,
    denominacion_tienda character varying,
    direccion_tienda character varying,
    ubicacion_tienda character varying,
    almacenes_data jsonb DEFAULT NULL,
    tpv_data jsonb DEFAULT NULL,
    personal_data jsonb DEFAULT NULL,
    layouts_data jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    nueva_tienda_id bigint;
    item_json JSONB;
    resultado JSONB := '{}'::JSONB;
    temp_id bigint;
    almacen_ids JSONB := '{}'::JSONB;
    tpv_ids JSONB := '{}'::JSONB;
    primer_almacen_id bigint;
BEGIN
    -- Crear la tienda principal
    INSERT INTO app_dat_tienda (
        denominacion,
        direccion,
        ubicacion,
        created_at
    ) VALUES (
        denominacion_tienda,
        direccion_tienda,
        ubicacion_tienda,
        NOW()
    ) RETURNING id INTO nueva_tienda_id;
    
    -- Asignar suscripción gratuita
    PERFORM public.fn_asignar_suscripcion_gratuita(
        nueva_tienda_id,
        usuario_creador
    );
    
    resultado := jsonb_set(resultado, '{tienda_id}', to_jsonb(nueva_tienda_id));
    
    -- PASO 1: Crear almacenes PRIMERO (los TPVs los necesitan)
    IF almacenes_data IS NOT NULL THEN
        FOR item_json IN SELECT * FROM jsonb_array_elements(almacenes_data)
        LOOP
            INSERT INTO app_dat_almacen (
                id_tienda,
                denominacion,
                direccion,
                ubicacion,
                created_at
            ) VALUES (
                nueva_tienda_id,
                item_json->>'denominacion',
                item_json->>'direccion',
                item_json->>'ubicacion',
                NOW()
            ) RETURNING id INTO temp_id;
            
            -- Guardar el ID del almacén para usarlo en TPVs
            almacen_ids := jsonb_set(almacen_ids, ARRAY[item_json->>'denominacion'], to_jsonb(temp_id));
            resultado := jsonb_set(resultado, ARRAY['almacenes_creados', (item_json->>'denominacion')], to_jsonb(temp_id));
            
            -- Guardar el primer almacén como default
            IF primer_almacen_id IS NULL THEN
                primer_almacen_id := temp_id;
            END IF;
        END LOOP;
    END IF;
    
    -- PASO 2: Crear TPVs (ahora ya tenemos almacenes)
    IF tpv_data IS NOT NULL THEN
        FOR item_json IN SELECT * FROM jsonb_array_elements(tpv_data)
        LOOP
            DECLARE
                almacen_id_para_tpv bigint;
            BEGIN
                -- Buscar el ID del almacén asignado al TPV
                IF item_json->>'almacen_asignado' IS NOT NULL THEN
                    almacen_id_para_tpv := (almacen_ids->(item_json->>'almacen_asignado'))::text::bigint;
                ELSE
                    -- Si no se especifica, usar el primer almacén
                    almacen_id_para_tpv := primer_almacen_id;
                END IF;
                
                INSERT INTO app_dat_tpv (
                    id_tienda,
                    id_almacen,
                    denominacion,
                    created_at
                ) VALUES (
                    nueva_tienda_id,
                    almacen_id_para_tpv,
                    item_json->>'denominacion',
                    NOW()
                ) RETURNING id INTO temp_id;
                
                -- Guardar el ID del TPV para usarlo en personal
                tpv_ids := jsonb_set(tpv_ids, ARRAY[item_json->>'denominacion'], to_jsonb(temp_id));
                resultado := jsonb_set(resultado, ARRAY['tpvs_creados', (item_json->>'denominacion')], to_jsonb(temp_id));
            END;
        END LOOP;
    END IF;
    
    -- PASO 3: Crear layouts de almacén si se proporcionan
    IF layouts_data IS NOT NULL THEN
        FOR item_json IN SELECT * FROM jsonb_array_elements(layouts_data)
        LOOP
            INSERT INTO app_dat_layout_almacen (
                id_almacen,
                id_tipo_layout,
                id_layout_padre,
                denominacion,
                sku_codigo,
                created_at
            ) VALUES (
                (almacen_ids->(item_json->>'almacen_asignado'))::text::bigint,
                (item_json->>'id_tipo_layout')::bigint,
                NULLIF((item_json->>'id_layout_padre')::bigint, 0),
                item_json->>'denominacion',
                item_json->>'sku_codigo',
                NOW()
            ) RETURNING id INTO temp_id;
            
            resultado := jsonb_set(resultado, ARRAY['layouts_creados', (item_json->>'denominacion')], to_jsonb(temp_id));
        END LOOP;
    END IF;
    
    -- PASO 4: Asignar personal (ahora ya tenemos almacenes y TPVs)
    IF personal_data IS NOT NULL THEN
        FOR item_json IN SELECT * FROM jsonb_array_elements(personal_data)
        LOOP
            -- Primero crear el trabajador
            INSERT INTO app_dat_trabajadores (
                id_tienda,
                id_roll,
                nombres,
                apellidos,
                created_at
            ) VALUES (
                nueva_tienda_id,
                (item_json->>'id_roll')::bigint,
                item_json->>'nombres',
                item_json->>'apellidos',
                NOW()
            ) RETURNING id INTO temp_id;
            
            -- Luego asignar a la tabla específica según el rol
            CASE (item_json->>'tipo_rol')
                WHEN 'gerente' THEN
                    INSERT INTO app_dat_gerente (
                        uuid,
                        id_tienda,
                        id_trabajador,
                        created_at
                    ) VALUES (
                        (item_json->>'uuid')::uuid,
                        nueva_tienda_id,
                        temp_id,
                        NOW()
                    );
                    
                WHEN 'supervisor' THEN
                    INSERT INTO app_dat_supervisor (
                        uuid,
                        id_tienda,
                        id_trabajador,
                        created_at
                    ) VALUES (
                        (item_json->>'uuid')::uuid,
                        nueva_tienda_id,
                        temp_id,
                        NOW()
                    );
                    
                WHEN 'almacenero' THEN
                    DECLARE
                        almacen_id_para_almacenero bigint;
                    BEGIN
                        -- Buscar el ID del almacén asignado
                        IF item_json->>'almacen_asignado' IS NOT NULL THEN
                            almacen_id_para_almacenero := (almacen_ids->(item_json->>'almacen_asignado'))::text::bigint;
                        ELSE
                            almacen_id_para_almacenero := primer_almacen_id;
                        END IF;
                        
                        INSERT INTO app_dat_almacenero (
                            uuid,
                            id_almacen,
                            id_trabajador,
                            created_at
                        ) VALUES (
                            (item_json->>'uuid')::uuid,
                            almacen_id_para_almacenero,
                            temp_id,
                            NOW()
                        );
                    END;
                    
                WHEN 'vendedor' THEN
                    DECLARE
                        tpv_id_para_vendedor bigint;
                    BEGIN
                        -- Buscar el ID del TPV asignado
                        IF item_json->>'tpv_asignado' IS NOT NULL THEN
                            tpv_id_para_vendedor := (tpv_ids->(item_json->>'tpv_asignado'))::text::bigint;
                        ELSE
                            -- Si no se especifica, usar el primer TPV disponible
                            SELECT id INTO tpv_id_para_vendedor 
                            FROM app_dat_tpv 
                            WHERE id_tienda = nueva_tienda_id 
                            LIMIT 1;
                        END IF;
                        
                        INSERT INTO app_dat_vendedor (
                            uuid,
                            id_tpv,
                            id_trabajador,
                            numero_confirmacion,
                            created_at
                        ) VALUES (
                            (item_json->>'uuid')::uuid,
                            tpv_id_para_vendedor,
                            temp_id,
                            item_json->>'numero_confirmacion',
                            NOW()
                        );
                    END;
                    
                ELSE
                    -- Rol no reconocido, solo se crea el trabajador
                    NULL;
            END CASE;
            
            resultado := jsonb_set(resultado, ARRAY['personal_creado', (item_json->>'nombres')], to_jsonb(temp_id));
        END LOOP;
    END IF;
    
    -- Retornar resultado con todos los IDs creados
    RETURN jsonb_build_object(
        'success', true,
        'message', 'Estructura de tienda creada correctamente',
        'data', resultado
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Error al crear estructura de tienda: ' || SQLERRM,
            'error_code', SQLSTATE
        );
END;
$$;
