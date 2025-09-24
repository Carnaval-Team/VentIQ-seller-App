-- CÓDIGO A AGREGAR DESPUÉS DE LA ACTUALIZACIÓN DE INVENTARIO EN fn_registrar_venta
-- Agregar estas variables al inicio de la función (después de las declaraciones existentes):

DECLARE
  -- ... variables existentes ...
  v_es_elaborado BOOLEAN;
  v_ingrediente RECORD;
  v_inventario_ingrediente RECORD;

-- CÓDIGO A INSERTAR DESPUÉS DE LA ACTUALIZACIÓN DE INVENTARIO (después del INSERT en app_dat_inventario_productos):

    -- NUEVO: Verificar si el producto es elaborado y procesar ingredientes
    SELECT es_elaborado INTO v_es_elaborado
    FROM app_dat_producto 
    WHERE id = (v_producto->>'id_producto')::BIGINT;
    
    IF v_es_elaborado = true THEN
      -- Procesar ingredientes recursivamente
      FOR v_ingrediente IN 
        SELECT id_ingrediente, cantidad_total_necesaria
        FROM fn_obtener_ingredientes_recursivos(
          (v_producto->>'id_producto')::BIGINT, 
          (v_producto->>'cantidad')::NUMERIC
        )
      LOOP
        -- Obtener el último registro de inventario del ingrediente
        SELECT 
          id_producto,
          id_variante,
          id_opcion_variante,
          id_ubicacion,
          id_presentacion,
          cantidad_final,
          sku_producto,
          sku_ubicacion
        INTO v_inventario_ingrediente
        FROM app_dat_inventario_productos 
        WHERE id_producto = v_ingrediente.id_ingrediente
          -- Mantener consistencia con variantes y ubicaciones del producto padre si existen
        ORDER BY created_at DESC
        LIMIT 1;
        
        -- Validar stock disponible del ingrediente
        IF v_inventario_ingrediente IS NULL THEN
          -- No existe registro de inventario para este ingrediente
          RETURN jsonb_build_object(
            'status', 'error',
            'message', 'No hay stock disponible para el ingrediente: ' || 
                      (SELECT denominacion FROM app_dat_producto WHERE id = v_ingrediente.id_ingrediente) ||
                      ' (requerido: ' || v_ingrediente.cantidad_total_necesaria || ')',
            'error_code', 'INSUFFICIENT_STOCK_INGREDIENT',
            'id_ingrediente', v_ingrediente.id_ingrediente,
            'cantidad_requerida', v_ingrediente.cantidad_total_necesaria,
            'cantidad_disponible', 0
          );
        END IF;
        
        -- Validar que hay suficiente stock
        IF v_inventario_ingrediente.cantidad_final < v_ingrediente.cantidad_total_necesaria THEN
          RETURN jsonb_build_object(
            'status', 'error',
            'message', 'Stock insuficiente para el ingrediente: ' || 
                      (SELECT denominacion FROM app_dat_producto WHERE id = v_ingrediente.id_ingrediente) ||
                      ' (disponible: ' || v_inventario_ingrediente.cantidad_final || 
                      ', requerido: ' || v_ingrediente.cantidad_total_necesaria || ')',
            'error_code', 'INSUFFICIENT_STOCK_INGREDIENT',
            'id_ingrediente', v_ingrediente.id_ingrediente,
            'cantidad_requerida', v_ingrediente.cantidad_total_necesaria,
            'cantidad_disponible', v_inventario_ingrediente.cantidad_final
          );
        END IF;
        
        -- Insertar nuevo registro de inventario para el ingrediente (descontando stock)
        INSERT INTO app_dat_inventario_productos (
          id_producto,
          id_variante,
          id_opcion_variante,
          id_ubicacion,
          id_presentacion,
          cantidad_inicial,
          cantidad_final,
          sku_producto,
          sku_ubicacion,
          origen_cambio,
          id_extraccion,
          created_at
        ) VALUES (
          v_inventario_ingrediente.id_producto,
          v_inventario_ingrediente.id_variante,
          v_inventario_ingrediente.id_opcion_variante,
          v_inventario_ingrediente.id_ubicacion,
          v_inventario_ingrediente.id_presentacion,
          v_inventario_ingrediente.cantidad_final, -- cantidad_inicial = cantidad_final anterior
          v_inventario_ingrediente.cantidad_final - v_ingrediente.cantidad_total_necesaria, -- nueva cantidad_final
          v_inventario_ingrediente.sku_producto,
          v_inventario_ingrediente.sku_ubicacion,
          4, -- Origen: Elaboración de producto (puedes crear un nuevo tipo)
          v_id_operacion, -- Mismo id_extraccion que el producto elaborado
          NOW()
        );
        
      END LOOP;
    END IF;
    
    -- Continúa con el resto del código existente...
