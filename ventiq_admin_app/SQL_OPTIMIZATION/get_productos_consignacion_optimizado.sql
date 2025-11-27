-- ============================================================================
-- FUNCIÓN RPC: get_productos_consignacion_optimizado
-- ============================================================================
-- Propósito: Obtener productos de consignación con datos de producto en UNA query
--
-- Beneficios:
--   ✅ Una sola query en lugar de N+1 queries
--   ✅ Incluye datos de producto directamente
--   ✅ Mejor rendimiento
--   ✅ Menos transferencia de datos
--
-- Parámetro:
--   p_id_contrato: ID del contrato
--
-- Retorna:
--   JSON con productos y datos completos
--
-- ============================================================================

CREATE OR REPLACE FUNCTION get_productos_consignacion_optimizado(p_id_contrato INT)
RETURNS TABLE (
  id INT,
  id_contrato INT,
  id_producto INT,
  cantidad_enviada NUMERIC,
  cantidad_vendida NUMERIC,
  cantidad_devuelta NUMERIC,
  precio_venta_sugerido NUMERIC,
  estado INT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  producto JSONB
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    pc.id,
    pc.id_contrato,
    pc.id_producto,
    pc.cantidad_enviada,
    pc.cantidad_vendida,
    pc.cantidad_devuelta,
    pc.precio_venta_sugerido,
    pc.estado,
    pc.created_at,
    pc.updated_at,
    -- Datos de producto como JSONB
    jsonb_build_object(
      'id', p.id,
      'denominacion', p.denominacion,
      'sku', p.sku,
      'descripcion', p.descripcion
    ) AS producto
  FROM app_dat_producto_consignacion pc
  INNER JOIN app_dat_producto p ON pc.id_producto = p.id
  WHERE pc.id_contrato = p_id_contrato
    AND pc.estado = 1  -- CONFIRMADOS
  ORDER BY pc.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCIÓN RPC: get_productos_pendientes_consignacion_optimizado
-- ============================================================================
-- Propósito: Obtener productos pendientes de consignación con datos de producto
--
-- Parámetro:
--   p_id_contrato: ID del contrato
--
-- Retorna:
--   JSON con productos pendientes y datos completos
--
-- ============================================================================

CREATE OR REPLACE FUNCTION get_productos_pendientes_consignacion_optimizado(p_id_contrato INT)
RETURNS TABLE (
  id INT,
  id_contrato INT,
  id_producto INT,
  cantidad_enviada NUMERIC,
  cantidad_vendida NUMERIC,
  cantidad_devuelta NUMERIC,
  precio_venta_sugerido NUMERIC,
  estado INT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  producto JSONB
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    pc.id,
    pc.id_contrato,
    pc.id_producto,
    pc.cantidad_enviada,
    pc.cantidad_vendida,
    pc.cantidad_devuelta,
    pc.precio_venta_sugerido,
    pc.estado,
    pc.created_at,
    pc.updated_at,
    -- Datos de producto como JSONB
    jsonb_build_object(
      'id', p.id,
      'denominacion', p.denominacion,
      'sku', p.sku,
      'descripcion', p.descripcion
    ) AS producto
  FROM app_dat_producto_consignacion pc
  INNER JOIN app_dat_producto p ON pc.id_producto = p.id
  WHERE pc.id_contrato = p_id_contrato
    AND pc.estado = 0  -- PENDIENTE
  ORDER BY pc.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- NOTAS:
-- ============================================================================
-- 1. Ejecuta ambas funciones en Supabase SQL Editor
-- 2. Reemplaza N+1 queries por 1 query
-- 3. Incluye datos de producto directamente
-- 4. Usa JSONB para compatibilidad con Flutter
-- ============================================================================
