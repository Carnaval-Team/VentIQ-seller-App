CREATE OR REPLACE FUNCTION fn_registrar_cambio_estado_operacion_mejorado(
    p_id_operacion BIGINT,
    p_nuevo_estado SMALLINT,
    p_uuid_usuario UUID DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE 
    v_productos_extraidos RECORD;
    v_existente_estado RECORD;
    v_inventario_actual RECORD;
    v_ingrediente RECORD;
    v_cantidad_ingrediente_devolver NUMERIC;
    v_ultimo_inventario RECORD;
    v_response jsonb;
BEGIN
    -- Inicializar respuesta
    v_response := jsonb_build_object(
        'success', false,
        'message', '',
        'operation_id', p_id_operacion,
        'new_state', p_nuevo_estado
    );

    -- Primero, validar que el estado sea válido
    IF p_nuevo_estado NOT IN (1, 2, 3, 4) THEN
        v_response := jsonb_set(v_response, '{success}', 'false');
        v_response := jsonb_set(v_response, '{message}', '"Estado de operación inválido. Solo se permiten 1 (Pendiente), 2 (Completada), 3 (Devuelta), 4 (Cancelada)"');
        RETURN v_response;
    END IF;

    -- Verificar si ya existe un estado para esta operación
    SELECT * INTO v_existente_estado 
    FROM app_dat_estado_operacion 
    WHERE id_operacion = p_id_operacion 
    ORDER BY created_at DESC 
    LIMIT 1;

    -- Si el estado es el mismo que el último registrado, no hacer nada
    IF v_existente_estado.estado = p_nuevo_estado THEN
        v_response := jsonb_set(v_response, '{success}', 'true');
        v_response := jsonb_set(v_response, '{message}', '"La operación ya tiene este estado"');
        RETURN v_response;
    END IF;

    -- Insertar nuevo estado de operación
    INSERT INTO app_dat_estado_operacion (
        id_operacion, 
        estado, 
        uuid,
        created_at
    ) VALUES (
        p_id_operacion, 
        p_nuevo_estado, 
        p_uuid_usuario,
        NOW()
    );

    -- Si es una devolución o cancelación, devolver productos al inventario
    IF p_nuevo_estado IN (3, 4) THEN
        -- Recuperar los productos extraídos originalmente
        FOR v_productos_extraidos IN (
            SELECT 
                id_producto, 
                id_variante, 
                id_opcion_variante, 
                id_presentacion, 
                id_ubicacion,
                cantidad,
                sku_producto,
                sku_ubicacion
            FROM app_dat_extraccion_productos
            WHERE id_operacion = p_id_operacion
        ) LOOP
            
            -- Obtener inventario actual más reciente
            SELECT * INTO v_inventario_actual
            FROM app_dat_inventario_productos
            WHERE id_producto = v_productos_extraidos.id_producto
              AND COALESCE(id_variante, 0) = COALESCE(v_productos_extraidos.id_variante, 0)
              AND COALESCE(id_opcion_variante, 0) = COALESCE(v_productos_extraidos.id_opcion_variante, 0)
              AND COALESCE(id_presentacion, 0) = COALESCE(v_productos_extraidos.id_presentacion, 0)
              AND COALESCE(id_ubicacion, 0) = COALESCE(v_productos_extraidos.id_ubicacion, 0)
            ORDER BY created_at DESC
            LIMIT 1;
            
            -- Si no existe inventario previo, usar 0
            IF v_inventario_actual.cantidad_final IS NULL THEN
                v_inventario_actual.cantidad_final := 0;
            END IF;
            
            -- Actualizar inventario para devolver los productos
            INSERT INTO app_dat_inventario_productos (
                id_producto,
                id_variante,
                id_opcion_variante,
                id_presentacion,
                id_ubicacion,
                cantidad_inicial,
                cantidad_final,
                sku_producto,
                sku_ubicacion,
                origen_cambio,
                created_at
            ) VALUES (
                v_productos_extraidos.id_producto,
                v_productos_extraidos.id_variante,
                v_productos_extraidos.id_opcion_variante,
                v_productos_extraidos.id_presentacion,
                v_productos_extraidos.id_ubicacion,
                v_inventario_actual.cantidad_final,
                v_inventario_actual.cantidad_final + v_productos_extraidos.cantidad,
                v_productos_extraidos.sku_producto,
                v_productos_extraidos.sku_ubicacion,
                CASE 
                    WHEN p_nuevo_estado = 3 THEN 4  -- Devolución
                    WHEN p_nuevo_estado = 4 THEN 5  -- Cancelación
                END,
                NOW()
            );
        END LOOP;
        
        -- Procesar productos elaborados para devolver ingredientes
        FOR v_productos_extraidos IN (
            SELECT 
                ep.id_producto, 
                ep.cantidad
            FROM app_dat_extraccion_productos ep
            INNER JOIN app_dat_producto p ON ep.id_producto = p.id
            WHERE ep.id_operacion = p_id_operacion
              AND p.es_elaborado = true
        ) LOOP
            
            -- Para cada producto elaborado, devolver sus ingredientes
            FOR v_ingrediente IN (
                SELECT 
                    id_ingrediente,
                    cantidad_necesaria
                FROM app_dat_producto_ingredientes
                WHERE id_producto_elaborado = v_productos_extraidos.id_producto
            ) LOOP
                
                -- Calcular cantidad total de ingrediente a devolver
                v_cantidad_ingrediente_devolver := v_ingrediente.cantidad_necesaria * v_productos_extraidos.cantidad;
                
                -- Obtener el ÚLTIMO registro de inventario del ingrediente para obtener el id_presentacion
                SELECT * INTO v_ultimo_inventario
                FROM app_dat_inventario_productos
                WHERE id_producto = v_ingrediente.id_ingrediente
                ORDER BY created_at DESC
                LIMIT 1;
                
                -- Si no existe inventario previo del ingrediente, usar valores por defecto
                IF v_ultimo_inventario IS NULL THEN
                    v_ultimo_inventario.cantidad_final := 0;
                    v_ultimo_inventario.id_presentacion := NULL;
                    v_ultimo_inventario.id_ubicacion := NULL;
                    v_ultimo_inventario.sku_producto := NULL;
                    v_ultimo_inventario.sku_ubicacion := NULL;
                END IF;
                
                -- Devolver ingrediente al inventario usando el id_presentacion del último registro
                INSERT INTO app_dat_inventario_productos (
                    id_producto,
                    id_variante,
                    id_opcion_variante,
                    id_presentacion,
                    id_ubicacion,
                    cantidad_inicial,
                    cantidad_final,
                    sku_producto,
                    sku_ubicacion,
                    origen_cambio,
                    created_at
                ) VALUES (
                    v_ingrediente.id_ingrediente,
                    COALESCE(v_ultimo_inventario.id_variante, NULL),
                    COALESCE(v_ultimo_inventario.id_opcion_variante, NULL),
                    v_ultimo_inventario.id_presentacion,
                    COALESCE(v_ultimo_inventario.id_ubicacion, NULL),
                    COALESCE(v_ultimo_inventario.cantidad_final, 0),
                    COALESCE(v_ultimo_inventario.cantidad_final, 0) + v_cantidad_ingrediente_devolver,
                    COALESCE(v_ultimo_inventario.sku_producto, NULL),
                    COALESCE(v_ultimo_inventario.sku_ubicacion, NULL),
                    CASE 
                        WHEN p_nuevo_estado = 3 THEN 6  -- Devolución de ingredientes
                        WHEN p_nuevo_estado = 4 THEN 7  -- Cancelación de ingredientes
                    END,
                    NOW()
                );
            END LOOP;
        END LOOP;
    END IF;

    -- Retornar respuesta exitosa
    v_response := jsonb_set(v_response, '{success}', 'true');
    v_response := jsonb_set(v_response, '{message}', '"Operación actualizada exitosamente"');
    
    RETURN v_response;
EXCEPTION WHEN OTHERS THEN
    v_response := jsonb_set(v_response, '{success}', 'false');
    v_response := jsonb_set(v_response, '{message}', to_jsonb(SQLERRM));
    RETURN v_response;
END;
$$;
