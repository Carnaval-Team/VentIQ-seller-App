-- Función para descuento automático de inventario al vender platos elaborados
CREATE OR REPLACE FUNCTION fn_descontar_inventario_plato(
  p_id_venta_plato bigint,
  p_id_tienda bigint,
  p_uuid_usuario uuid
) RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_resultado jsonb := '{"success": true, "descuentos": [], "operacion_id": null}'::jsonb;
  v_plato record;
  v_ingrediente record;
  v_cantidad_plato integer;
  v_cantidad_necesaria numeric;
  v_cantidad_convertida numeric;
  v_descuentos jsonb := '[]'::jsonb;
  v_ubicacion_id bigint;
  v_operacion_id bigint;
  v_stock_ubicacion numeric;
  v_precio_costo numeric;
  v_unidad_inventario bigint;
  v_cantidad_restante numeric;
  v_ubicacion_record record;
BEGIN
  -- Verificar que la venta del plato existe
  SELECT vp.id_plato, vp.cantidad, pe.nombre, vp.id_operacion_venta
  INTO v_plato
  FROM app_rest_venta_platos vp
  JOIN app_rest_platos_elaborados pe ON vp.id_plato = pe.id
  WHERE vp.id = p_id_venta_plato;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Venta de plato no encontrada'
    );
  END IF;
  
  -- Crear operación de extracción para el descuento automático
  INSERT INTO app_dat_operaciones (id_tipo_operacion, uuid, id_tienda, observaciones)
  VALUES (2, p_uuid_usuario, p_id_tienda, 'Descuento automático por venta de plato: ' || v_plato.nombre)
  RETURNING id INTO v_operacion_id;
  
  -- Crear registro de operación de extracción
  INSERT INTO app_dat_operacion_extraccion (id_operacion, id_motivo_operacion, observaciones, autorizado_por)
  VALUES (v_operacion_id, 1, 'Descuento automático por elaboración', 'SISTEMA');
  
  -- Procesar cada ingrediente de la receta
  FOR v_ingrediente IN 
    SELECT r.id_producto_inventario, r.cantidad_requerida, r.um, r.id as receta_id,
           p.denominacion as nombre_producto, p.sku,
           um_receta.id as id_unidad_receta
    FROM app_rest_recetas r
    JOIN app_dat_producto p ON r.id_producto_inventario = p.id
    LEFT JOIN app_nom_unidades_medida um_receta ON um_receta.abreviatura = r.um
    WHERE r.id_plato = v_plato.id_plato
    ORDER BY r.orden
  LOOP
    -- Calcular cantidad total necesaria
    v_cantidad_necesaria := v_ingrediente.cantidad_requerida * v_plato.cantidad;
    v_cantidad_restante := v_cantidad_necesaria;
    
    -- Obtener unidad de inventario del producto
    SELECT pu.id_unidad_medida INTO v_unidad_inventario
    FROM app_dat_producto_unidades pu
    WHERE pu.id_producto = v_ingrediente.id_producto_inventario
      AND pu.es_unidad_inventario = true
    LIMIT 1;
    
    -- Si no hay unidad específica, usar la primera disponible
    IF v_unidad_inventario IS NULL THEN
      SELECT um.id INTO v_unidad_inventario
      FROM app_nom_unidades_medida um
      WHERE um.abreviatura = (
        SELECT p.um FROM app_dat_producto p 
        WHERE p.id = v_ingrediente.id_producto_inventario
      )
      LIMIT 1;
    END IF;
    
    -- Convertir cantidad de receta a unidad de inventario
    IF v_ingrediente.id_unidad_receta IS NOT NULL AND v_unidad_inventario IS NOT NULL 
       AND v_ingrediente.id_unidad_receta != v_unidad_inventario THEN
      
      SELECT fn_convertir_unidades(
        v_cantidad_necesaria,
        v_ingrediente.id_unidad_receta,
        v_unidad_inventario,
        v_ingrediente.id_producto_inventario
      ) INTO v_cantidad_convertida;
      
    ELSE
      v_cantidad_convertida := v_cantidad_necesaria;
    END IF;
    
    v_cantidad_restante := v_cantidad_convertida;
    
    -- Buscar ubicaciones con stock disponible (FIFO - First In, First Out)
    FOR v_ubicacion_record IN
      SELECT l.id as ubicacion_id, l.sku_codigo,
             CASE 
               WHEN i.cantidad_final IS NOT NULL THEN i.cantidad_final
               ELSE i.cantidad_inicial
             END as stock_disponible,
             i.id as inventario_id
      FROM app_dat_inventario_productos i
      JOIN app_dat_layout_almacen l ON i.id_ubicacion = l.id
      JOIN app_dat_almacen a ON l.id_almacen = a.id
      WHERE i.id_producto = v_ingrediente.id_producto_inventario
        AND a.id_tienda = p_id_tienda
        AND (
          (i.cantidad_final IS NOT NULL AND i.cantidad_final > 0) OR
          (i.cantidad_final IS NULL AND i.cantidad_inicial > 0)
        )
      ORDER BY i.created_at ASC -- FIFO
    LOOP
      EXIT WHEN v_cantidad_restante <= 0;
      
      -- Determinar cuánto descontar de esta ubicación
      v_stock_ubicacion := LEAST(v_ubicacion_record.stock_disponible, v_cantidad_restante);
      
      -- Obtener precio de costo más reciente
      SELECT COALESCE(costo_real, precio_unitario, 0) INTO v_precio_costo
      FROM app_dat_recepcion_productos
      WHERE id_producto = v_ingrediente.id_producto_inventario
      ORDER BY created_at DESC
      LIMIT 1;
      
      -- Registrar extracción en inventario
      INSERT INTO app_dat_extraccion_productos (
        id_operacion, id_producto, id_variante, id_opcion_variante,
        id_ubicacion, id_presentacion, cantidad, precio_unitario,
        sku_producto, sku_ubicacion, importe, importe_real
      ) VALUES (
        v_operacion_id, v_ingrediente.id_producto_inventario, NULL, NULL,
        v_ubicacion_record.ubicacion_id, NULL, v_stock_ubicacion, v_precio_costo,
        v_ingrediente.sku, v_ubicacion_record.sku_codigo,
        v_stock_ubicacion * v_precio_costo, v_stock_ubicacion * v_precio_costo
      );
      
      -- Actualizar inventario
      UPDATE app_dat_inventario_productos 
      SET cantidad_final = CASE 
        WHEN cantidad_final IS NOT NULL THEN cantidad_final - v_stock_ubicacion
        ELSE cantidad_inicial - v_stock_ubicacion
      END
      WHERE id = v_ubicacion_record.inventario_id;
      
      -- Registrar en log de descuentos específico del restaurante
      INSERT INTO app_rest_descuentos_inventario (
        id_venta_plato, id_producto_inventario, cantidad_descontada,
        id_unidad_medida, id_ubicacion, precio_costo, 
        fecha_descuento, procesado_por, observaciones
      ) VALUES (
        p_id_venta_plato, v_ingrediente.id_producto_inventario, v_stock_ubicacion,
        COALESCE(v_unidad_inventario, 1), v_ubicacion_record.ubicacion_id, v_precio_costo,
        now(), p_uuid_usuario, 
        'Descuento automático - Receta: ' || v_ingrediente.receta_id
      );
      
      -- Agregar al resultado
      v_descuentos := v_descuentos || jsonb_build_object(
        'producto', v_ingrediente.nombre_producto,
        'sku', v_ingrediente.sku,
        'cantidad_descontada', v_stock_ubicacion,
        'ubicacion_id', v_ubicacion_record.ubicacion_id,
        'precio_costo', v_precio_costo,
        'importe', v_stock_ubicacion * v_precio_costo
      );
      
      -- Reducir cantidad restante
      v_cantidad_restante := v_cantidad_restante - v_stock_ubicacion;
    END LOOP;
    
    -- Verificar si se pudo descontar toda la cantidad necesaria
    IF v_cantidad_restante > 0 THEN
      -- Registrar desperdicio por falta de stock
      INSERT INTO app_rest_desperdicios (
        id_producto_inventario, id_plato, cantidad_desperdiciada,
        id_unidad_medida, motivo_desperdicio, registrado_por, observaciones
      ) VALUES (
        v_ingrediente.id_producto_inventario, v_plato.id_plato, v_cantidad_restante,
        COALESCE(v_unidad_inventario, 1), 'Stock insuficiente para descuento automático',
        p_uuid_usuario, 'Faltante en venta plato ID: ' || p_id_venta_plato
      );
      
      v_resultado := jsonb_set(v_resultado, '{success}', 'false');
      v_resultado := jsonb_set(v_resultado, '{warning}', 
        '"Stock insuficiente para ingrediente: ' || v_ingrediente.nombre_producto || 
        '. Faltante: ' || v_cantidad_restante || '"');
    END IF;
  END LOOP;
  
  -- Completar operación de extracción
  INSERT INTO app_dat_estado_operacion (id_operacion, estado, uuid, comentario)
  VALUES (v_operacion_id, 3, p_uuid_usuario, 'Descuento automático completado para plato: ' || v_plato.nombre);
  
  -- Actualizar estado de preparación del plato
  INSERT INTO app_rest_estados_preparacion (
    id_venta_plato, estado, tiempo_estimado, fecha_cambio_estado, cambiado_por
  ) VALUES (
    p_id_venta_plato, 2, -- Estado: En preparación
    (SELECT tiempo_preparacion FROM app_rest_platos_elaborados WHERE id = v_plato.id_plato),
    now(), p_uuid_usuario
  );
  
  -- Actualizar resultado final
  v_resultado := jsonb_set(v_resultado, '{descuentos}', v_descuentos);
  v_resultado := jsonb_set(v_resultado, '{operacion_id}', to_jsonb(v_operacion_id));
  v_resultado := jsonb_set(v_resultado, '{plato}', to_jsonb(v_plato.nombre));
  v_resultado := jsonb_set(v_resultado, '{cantidad_platos}', to_jsonb(v_plato.cantidad));
  
  -- Log de la operación
  INSERT INTO app_mkt_function_logs (
    function_name, parametros, resultado, fecha_acceso
  ) VALUES (
    'fn_descontar_inventario_plato',
    jsonb_build_object(
      'id_venta_plato', p_id_venta_plato,
      'id_tienda', p_id_tienda,
      'uuid_usuario', p_uuid_usuario,
      'operacion_id', v_operacion_id
    ),
    'SUCCESS - Operación: ' || v_operacion_id || ', Descuentos: ' || jsonb_array_length(v_descuentos),
    now()
  );
  
  RETURN v_resultado;
  
EXCEPTION
  WHEN OTHERS THEN
    -- Rollback de la operación si existe
    IF v_operacion_id IS NOT NULL THEN
      UPDATE app_dat_estado_operacion 
      SET estado = 4, comentario = 'ERROR: ' || SQLERRM
      WHERE id_operacion = v_operacion_id;
    END IF;
    
    -- Log del error
    INSERT INTO app_mkt_function_logs (
      function_name, parametros, mensaje_error, fecha_acceso
    ) VALUES (
      'fn_descontar_inventario_plato',
      jsonb_build_object(
        'id_venta_plato', p_id_venta_plato,
        'id_tienda', p_id_tienda,
        'uuid_usuario', p_uuid_usuario
      ),
      SQLERRM,
      now()
    );
    
    RETURN jsonb_build_object(
      'success', false,
      'error', SQLERRM,
      'operacion_id', v_operacion_id
    );
END;
$$;
