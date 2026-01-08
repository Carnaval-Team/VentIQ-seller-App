-- ============================================================================
-- FUNCIÓN: configurar_precios_recepcion_consignacion
-- DESCRIPCIÓN: Configura precios de venta al aceptar envío
-- PASO 1: Actualiza precio_venta SOLO si NO es devolución (CUP)
-- PASO 2: Actualiza precio_unitario en app_dat_recepcion_productos (USD)
-- PASO 3: Actualiza precio_promedio SOLO si NO es devolución
-- NOTA: Si es devolución, SOLO actualiza inventario (no precios)
-- ============================================================================

DROP FUNCTION IF EXISTS public.configurar_precios_recepcion_consignacion(
  p_id_operacion_recepcion BIGINT,
  p_id_tienda_destino BIGINT,
  p_precios_productos JSONB
) CASCADE;

CREATE OR REPLACE FUNCTION public.configurar_precios_recepcion_consignacion(
  p_id_operacion_recepcion BIGINT,
  p_id_tienda_destino BIGINT,
  p_precios_productos JSONB
)
RETURNS TABLE (
  success BOOLEAN,
  precios_configurados INT,
  mensaje TEXT
) AS $$
DECLARE
  v_producto RECORD;
  v_id_presentacion BIGINT;
  v_precio_venta_cup NUMERIC;
  v_precio_costo_usd NUMERIC;
  v_cantidad NUMERIC;
  v_precio_promedio_nuevo NUMERIC;
  v_total_costo_usd NUMERIC;
  v_total_cantidad NUMERIC;
  v_count_precios INT := 0;
  v_precio_promedio_presentacion NUMERIC;
  v_id_tienda_origen BIGINT;
  v_id_envio BIGINT;
  v_es_devolucion BOOLEAN := FALSE;
BEGIN
  -- ⭐ VERIFICAR SI ES DEVOLUCIÓN
  SELECT EXISTS (
    SELECT 1 
    FROM app_dat_consignacion_envio
    WHERE id_operacion_recepcion = p_id_operacion_recepcion
      AND tipo_envio = 2  -- Devolución
  ) INTO v_es_devolucion;
  
  IF v_es_devolucion THEN
    RAISE NOTICE '⚠️ Operación % es devolución - precio promedio NO se actualizará', p_id_operacion_recepcion;
  END IF;
  -- 1. Para cada producto en la recepción, procesar precios desde parámetro JSON
  FOR v_producto IN
    SELECT 
      rp.id_producto,
      rp.id_presentacion,
      rp.cantidad,
      (precio_data->>'precio_venta_cup')::NUMERIC AS precio_venta_cup,
      (precio_data->>'precio_costo_usd')::NUMERIC AS precio_costo_usd
    FROM app_dat_recepcion_productos rp,
    LATERAL jsonb_array_elements(p_precios_productos) AS precio_data
    WHERE rp.id_operacion = p_id_operacion_recepcion
      AND (precio_data->>'id_producto')::BIGINT = rp.id_producto
  LOOP
    -- 1a. Obtener datos del envío
    v_id_presentacion := v_producto.id_presentacion;
    v_cantidad := v_producto.cantidad;
    -- El precio_venta_cup viene del envío, es lo que el consignador configuró para vender
    v_precio_venta_cup := COALESCE(v_producto.precio_venta_cup, 0);
    -- El precio_costo_usd viene del envío, es lo que el consignador configura como costo
    v_precio_costo_usd := COALESCE(v_producto.precio_costo_usd, 0);
    
    -- 1b. Actualizar precio_venta en tienda CONSIGNATARIA (destino)
    -- ⭐ SOLO si NO es devolución
    -- Los precios de la tienda consignadora NO se tocan
    IF NOT v_es_devolucion THEN
      -- Solo insertar si precio_venta_cup > 0, si no usar 0 como valor por defecto
      IF v_precio_venta_cup IS NULL OR v_precio_venta_cup <= 0 THEN
        v_precio_venta_cup := 0;
      END IF;
      
      -- Primero cerrar el precio anterior (si existe)
      UPDATE app_dat_precio_venta
      SET fecha_hasta = CURRENT_DATE - INTERVAL '1 day'
      WHERE id_producto = v_producto.id_producto
        AND fecha_hasta IS NULL;
      
      -- Luego insertar el nuevo precio (siempre, incluso si es 0)
      INSERT INTO app_dat_precio_venta (
        id_producto,
        precio_venta_cup,
        fecha_desde,
        created_at
      ) VALUES (
        v_producto.id_producto,
        v_precio_venta_cup,
        CURRENT_DATE,
        CURRENT_TIMESTAMP
      );
      
      RAISE NOTICE '✅ Precio de venta actualizado para producto %: %', v_producto.id_producto, v_precio_venta_cup;
    ELSE
      RAISE NOTICE '⚠️ Devolución detectada - precio de venta NO actualizado para producto %', v_producto.id_producto;
    END IF;
    
    -- 1c. Actualizar precio_unitario en app_dat_recepcion_productos
    -- El precio_costo_usd se guarda como precio_unitario en USD
    UPDATE app_dat_recepcion_productos
    SET 
      precio_unitario = v_precio_costo_usd
    WHERE id_operacion = p_id_operacion_recepcion
      AND id_producto = v_producto.id_producto;
    
    -- 1d. Calcular y actualizar precio_promedio en app_dat_producto_presentacion
    -- ⭐ SOLO si NO es devolución, tenemos presentación y precio_costo_usd válido
    IF NOT v_es_devolucion AND v_id_presentacion IS NOT NULL AND v_precio_costo_usd > 0 THEN
      -- Obtener el precio_promedio actual de la presentación
      SELECT COALESCE(pp.precio_promedio, 0)
      INTO v_precio_promedio_presentacion
      FROM app_dat_producto_presentacion pp
      WHERE pp.id_producto = v_producto.id_producto
        AND pp.id_presentacion = v_id_presentacion
      LIMIT 1;
      
      -- Obtener cantidad total anterior de esta presentación (de todas las recepciones)
      SELECT COALESCE(SUM(rp2.cantidad), 0)
      INTO v_total_cantidad
      FROM app_dat_recepcion_productos rp2
      WHERE rp2.id_producto = v_producto.id_producto
        AND rp2.id_presentacion = v_id_presentacion
        AND rp2.id_operacion != p_id_operacion_recepcion; -- Excluir la actual
      
      -- Calcular nuevo promedio ponderado
      -- Fórmula: (precio_promedio_anterior * cantidad_anterior + precio_costo_usd * cantidad_nueva) / (cantidad_anterior + cantidad_nueva)
      IF v_total_cantidad > 0 THEN
        v_total_costo_usd := (v_precio_promedio_presentacion * v_total_cantidad) + (v_precio_costo_usd * v_cantidad);
        v_precio_promedio_nuevo := v_total_costo_usd / (v_total_cantidad + v_cantidad);
      ELSE
        -- Primera recepción: el promedio es el precio actual
        v_precio_promedio_nuevo := v_precio_costo_usd;
      END IF;
      
      -- Actualizar precio_promedio en app_dat_producto_presentacion
      UPDATE app_dat_producto_presentacion
      SET 
        precio_promedio = v_precio_promedio_nuevo,
        updated_at = CURRENT_TIMESTAMP
      WHERE id_producto = v_producto.id_producto
        AND id_presentacion = v_id_presentacion;
      
      RAISE NOTICE '✅ Precio promedio actualizado para producto %: % → %', 
        v_producto.id_producto, v_precio_promedio_presentacion, v_precio_promedio_nuevo;
    ELSIF v_es_devolucion THEN
      RAISE NOTICE '⚠️ Devolución detectada - precio promedio NO actualizado para producto %', v_producto.id_producto;
    END IF;
    
    v_count_precios := v_count_precios + 1;
  END LOOP;
  
  -- 2. Retornar resultado
  RETURN QUERY SELECT 
    true::BOOLEAN AS success,
    v_count_precios::INT AS precios_configurados,
    format('Precios configurados para %s productos', v_count_precios)::TEXT AS mensaje;

EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT 
    false::BOOLEAN AS success,
    0::INT AS precios_configurados,
    ('Error: ' || SQLERRM)::TEXT AS mensaje;
END;
$$ LANGUAGE plpgsql;
