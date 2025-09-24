-- Función recursiva para obtener todos los ingredientes de un producto elaborado
CREATE OR REPLACE FUNCTION fn_obtener_ingredientes_recursivos(
  p_id_producto_elaborado BIGINT,
  p_cantidad_producto NUMERIC DEFAULT 1
)
RETURNS TABLE (
  id_ingrediente BIGINT,
  cantidad_total_necesaria NUMERIC,
  nivel_recursion INTEGER
) AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE ingredientes_recursivos AS (
    -- Caso base: ingredientes directos del producto
    SELECT 
      pi.id_ingrediente,
      pi.cantidad_necesaria * p_cantidad_producto as cantidad_total,
      1 as nivel,
      ARRAY[p_id_producto_elaborado] as ruta_productos
    FROM app_dat_producto_ingredientes pi
    WHERE pi.id_producto_elaborado = p_id_producto_elaborado
    
    UNION ALL
    
    -- Caso recursivo: ingredientes de ingredientes que también son elaborados
    SELECT 
      pi.id_ingrediente,
      pi.cantidad_necesaria * ir.cantidad_total as cantidad_total,
      ir.nivel + 1 as nivel,
      ir.ruta_productos || pi.id_producto_elaborado as ruta_productos
    FROM app_dat_producto_ingredientes pi
    INNER JOIN ingredientes_recursivos ir ON pi.id_producto_elaborado = ir.id_ingrediente
    INNER JOIN app_dat_producto p ON p.id = pi.id_producto_elaborado
    WHERE p.es_elaborado = true
      AND NOT (pi.id_producto_elaborado = ANY(ir.ruta_productos)) -- Evitar ciclos infinitos
      AND ir.nivel < 10 -- Límite de seguridad
  )
  -- Agrupar y sumar cantidades de ingredientes duplicados
  SELECT 
    ir.id_ingrediente,
    SUM(ir.cantidad_total) as cantidad_total_necesaria,
    MAX(ir.nivel) as nivel_recursion
  FROM ingredientes_recursivos ir
  INNER JOIN app_dat_producto p ON p.id = ir.id_ingrediente
  WHERE p.es_elaborado = false -- Solo ingredientes finales (no elaborados)
  GROUP BY ir.id_ingrediente;
END;
$$ LANGUAGE plpgsql;
