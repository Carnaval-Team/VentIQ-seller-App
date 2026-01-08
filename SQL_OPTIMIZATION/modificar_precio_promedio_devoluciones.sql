-- ============================================================================
-- PASO 3: Modificar función de precio promedio para ignorar devoluciones
-- ============================================================================
-- Este script modifica la función que actualiza el precio promedio
-- para que NO actualice cuando es una devolución de consignación
-- ============================================================================

-- ============================================================================
-- OPCIÓN A: Si usas fn_actualizar_precio_promedio_recepcion
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_actualizar_precio_promedio_recepcion(
  p_id_operacion BIGINT,
  p_id_producto BIGINT,
  p_id_presentacion BIGINT,
  p_precio_unitario NUMERIC,
  p_cantidad NUMERIC
) RETURNS VOID AS $$
DECLARE
  v_es_devolucion BOOLEAN;
  v_cantidad_actual NUMERIC;
  v_precio_promedio_actual NUMERIC;
  v_nuevo_precio_promedio NUMERIC;
BEGIN
  -- ⭐ VERIFICAR SI ES DEVOLUCIÓN (usando FK existente)
  SELECT EXISTS (
    SELECT 1 
    FROM app_dat_consignacion_envio
    WHERE id_operacion_recepcion = p_id_operacion
      AND tipo_envio = 2  -- Devolución
  ) INTO v_es_devolucion;

  -- ⭐ SI ES DEVOLUCIÓN, NO ACTUALIZAR PRECIO PROMEDIO
  IF v_es_devolucion THEN
    RAISE NOTICE 'Operación % es devolución - precio promedio NO se actualiza', p_id_operacion;
    RETURN;
  END IF;

  -- Obtener precio promedio actual y cantidad
  SELECT 
    COALESCE(precio_promedio, 0),
    COALESCE((
      SELECT SUM(cantidad_final)
      FROM app_dat_inventario_productos
      WHERE id_producto = p_id_producto
        AND id_presentacion = p_id_presentacion
    ), 0)
  INTO v_precio_promedio_actual, v_cantidad_actual
  FROM app_dat_producto_presentacion
  WHERE id_producto = p_id_producto
    AND id_presentacion = p_id_presentacion;

  -- Calcular nuevo precio promedio ponderado
  IF (v_cantidad_actual + p_cantidad) > 0 THEN
    v_nuevo_precio_promedio := 
      ((v_precio_promedio_actual * v_cantidad_actual) + (p_precio_unitario * p_cantidad)) 
      / (v_cantidad_actual + p_cantidad);
  ELSE
    v_nuevo_precio_promedio := p_precio_unitario;
  END IF;

  -- Actualizar precio promedio
  UPDATE app_dat_producto_presentacion
  SET precio_promedio = v_nuevo_precio_promedio
  WHERE id_producto = p_id_producto
    AND id_presentacion = p_id_presentacion;

  RAISE NOTICE 'Precio promedio actualizado: % → %', v_precio_promedio_actual, v_nuevo_precio_promedio;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- OPCIÓN B: Si usas fn_actualizar_precio_promedio_recepcion_v2
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_actualizar_precio_promedio_recepcion_v2(
  p_id_operacion BIGINT
) RETURNS TABLE (
  productos_actualizados INTEGER,
  tiempo_ejecucion_ms INTEGER
) AS $$
DECLARE
  v_inicio TIMESTAMP;
  v_fin TIMESTAMP;
  v_productos_actualizados INTEGER := 0;
  v_es_devolucion BOOLEAN;
BEGIN
  v_inicio := clock_timestamp();

  -- ⭐ VERIFICAR SI ES DEVOLUCIÓN
  SELECT EXISTS (
    SELECT 1 
    FROM app_dat_consignacion_envio
    WHERE id_operacion_recepcion = p_id_operacion
      AND tipo_envio = 2  -- Devolución
  ) INTO v_es_devolucion;

  -- ⭐ SI ES DEVOLUCIÓN, NO ACTUALIZAR PRECIO PROMEDIO
  IF v_es_devolucion THEN
    RAISE NOTICE 'Operación % es devolución - precio promedio NO se actualiza', p_id_operacion;
    v_fin := clock_timestamp();
    RETURN QUERY SELECT 0, EXTRACT(MILLISECONDS FROM (v_fin - v_inicio))::INTEGER;
    RETURN;
  END IF;

  -- Actualizar precios promedio en bulk
  WITH productos_recepcion AS (
    SELECT 
      rp.id_producto,
      rp.id_presentacion,
      SUM(rp.cantidad) as cantidad_recibida,
      AVG(rp.precio_unitario) as precio_unitario_promedio
    FROM app_dat_recepcion_productos rp
    WHERE rp.id_operacion = p_id_operacion
    GROUP BY rp.id_producto, rp.id_presentacion
  ),
  inventario_actual AS (
    SELECT 
      pr.id_producto,
      pr.id_presentacion,
      pr.cantidad_recibida,
      pr.precio_unitario_promedio,
      pp.precio_promedio as precio_promedio_actual,
      COALESCE(SUM(ip.cantidad_final), 0) as cantidad_actual
    FROM productos_recepcion pr
    LEFT JOIN app_dat_producto_presentacion pp 
      ON pp.id_producto = pr.id_producto 
      AND pp.id_presentacion = pr.id_presentacion
    LEFT JOIN app_dat_inventario_productos ip 
      ON ip.id_producto = pr.id_producto 
      AND ip.id_presentacion = pr.id_presentacion
    GROUP BY 
      pr.id_producto, 
      pr.id_presentacion, 
      pr.cantidad_recibida, 
      pr.precio_unitario_promedio,
      pp.precio_promedio
  ),
  actualizacion AS (
    UPDATE app_dat_producto_presentacion pp
    SET precio_promedio = CASE
      WHEN (ia.cantidad_actual + ia.cantidad_recibida) > 0 THEN
        ((COALESCE(ia.precio_promedio_actual, 0) * ia.cantidad_actual) + 
         (ia.precio_unitario_promedio * ia.cantidad_recibida)) 
        / (ia.cantidad_actual + ia.cantidad_recibida)
      ELSE
        ia.precio_unitario_promedio
    END
    FROM inventario_actual ia
    WHERE pp.id_producto = ia.id_producto
      AND pp.id_presentacion = ia.id_presentacion
    RETURNING 1
  )
  SELECT COUNT(*)::INTEGER INTO v_productos_actualizados FROM actualizacion;

  v_fin := clock_timestamp();
  
  RAISE NOTICE 'Precios promedio actualizados: % productos en % ms', 
    v_productos_actualizados, 
    EXTRACT(MILLISECONDS FROM (v_fin - v_inicio))::INTEGER;

  RETURN QUERY SELECT 
    v_productos_actualizados, 
    EXTRACT(MILLISECONDS FROM (v_fin - v_inicio))::INTEGER;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- OPCIÓN C: Si usas un TRIGGER en app_dat_recepcion_productos
-- ============================================================================

CREATE OR REPLACE FUNCTION trg_actualizar_precio_promedio_recepcion()
RETURNS TRIGGER AS $$
DECLARE
  v_es_devolucion BOOLEAN;
  v_cantidad_actual NUMERIC;
  v_precio_promedio_actual NUMERIC;
  v_nuevo_precio_promedio NUMERIC;
BEGIN
  -- ⭐ VERIFICAR SI ES DEVOLUCIÓN
  SELECT EXISTS (
    SELECT 1 
    FROM app_dat_consignacion_envio
    WHERE id_operacion_recepcion = NEW.id_operacion
      AND tipo_envio = 2  -- Devolución
  ) INTO v_es_devolucion;

  -- ⭐ SI ES DEVOLUCIÓN, NO ACTUALIZAR PRECIO PROMEDIO
  IF v_es_devolucion THEN
    RAISE NOTICE 'Operación % es devolución - precio promedio NO se actualiza', NEW.id_operacion;
    RETURN NEW;
  END IF;

  -- Obtener precio promedio actual y cantidad
  SELECT 
    COALESCE(precio_promedio, 0),
    COALESCE((
      SELECT SUM(cantidad_final)
      FROM app_dat_inventario_productos
      WHERE id_producto = NEW.id_producto
        AND id_presentacion = NEW.id_presentacion
    ), 0)
  INTO v_precio_promedio_actual, v_cantidad_actual
  FROM app_dat_producto_presentacion
  WHERE id_producto = NEW.id_producto
    AND id_presentacion = NEW.id_presentacion;

  -- Calcular nuevo precio promedio ponderado
  IF (v_cantidad_actual + NEW.cantidad) > 0 THEN
    v_nuevo_precio_promedio := 
      ((v_precio_promedio_actual * v_cantidad_actual) + (NEW.precio_unitario * NEW.cantidad)) 
      / (v_cantidad_actual + NEW.cantidad);
  ELSE
    v_nuevo_precio_promedio := NEW.precio_unitario;
  END IF;

  -- Actualizar precio promedio
  UPDATE app_dat_producto_presentacion
  SET precio_promedio = v_nuevo_precio_promedio
  WHERE id_producto = NEW.id_producto
    AND id_presentacion = NEW.id_presentacion;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Si el trigger no existe, crearlo:
-- DROP TRIGGER IF EXISTS trg_actualizar_precio_promedio ON app_dat_recepcion_productos;
-- CREATE TRIGGER trg_actualizar_precio_promedio
--   AFTER INSERT ON app_dat_recepcion_productos
--   FOR EACH ROW
--   EXECUTE FUNCTION trg_actualizar_precio_promedio_recepcion();

-- ============================================================================
-- MENSAJE DE CONFIRMACIÓN
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Función de precio promedio modificada correctamente';
  RAISE NOTICE '🛡️ Ahora verifica si la operación es una devolución';
  RAISE NOTICE '📋 Si es devolución (tipo_envio = 2), NO actualiza precio promedio';
  RAISE NOTICE '';
  RAISE NOTICE '✅ VENTAJAS:';
  RAISE NOTICE '   - Sin redundancia de datos';
  RAISE NOTICE '   - Usa FK e índice existente';
  RAISE NOTICE '   - Performance O(1)';
  RAISE NOTICE '';
  RAISE NOTICE '📝 PRÓXIMO PASO: Modificar servicios Dart';
END $$;
