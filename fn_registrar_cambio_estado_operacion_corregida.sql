CREATE OR REPLACE FUNCTION fn_registrar_cambio_estado_operacion(
    p_id_operacion BIGINT,
    p_nuevo_estado SMALLINT,
    p_uuid_usuario UUID
) RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE 
    v_productos_extraidos RECORD;
    v_existente_estado RECORD;
    v_inventario_actual RECORD;
BEGIN
    -- Primero, validar que el estado sea válido
    IF p_nuevo_estado NOT IN (1, 2, 3, 4) THEN
        RAISE EXCEPTION 'Estado de operación inválido. Solo se permiten 1 (Pendiente), 2 (Completada), 3 (Devuelta), 4 (Cancelada)';
    END IF;

    -- Verificar si ya existe un estado para esta operación
    SELECT * INTO v_existente_estado 
    FROM app_dat_estado_operacion 
    WHERE id_operacion = p_id_operacion 
    ORDER BY created_at DESC 
    LIMIT 1;

    -- Si el estado es el mismo que el último registrado, no hacer nada
    IF v_existente_estado.estado = p_nuevo_estado THEN
        RETURN;
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
            
            -- Obtener el inventario actual más reciente para este producto
            SELECT 
                cantidad_final
            INTO v_inventario_actual
            FROM app_dat_inventario_productos
            WHERE id_producto = v_productos_extraidos.id_producto
              AND COALESCE(id_variante, 0) = COALESCE(v_productos_extraidos.id_variante, 0)
              AND COALESCE(id_opcion_variante, 0) = COALESCE(v_productos_extraidos.id_opcion_variante, 0)
              AND COALESCE(id_presentacion, 0) = COALESCE(v_productos_extraidos.id_presentacion, 0)
              AND COALESCE(id_ubicacion, 0) = COALESCE(v_productos_extraidos.id_ubicacion, 0)
            ORDER BY created_at DESC
            LIMIT 1;

            -- Si no existe inventario previo, usar 0 como cantidad inicial
            IF v_inventario_actual IS NULL THEN
                v_inventario_actual.cantidad_final := 0;
            END IF;

            -- Insertar registro de devolución en inventario
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
    END IF;
END;
$$;
