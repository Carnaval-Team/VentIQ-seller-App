-- ============================================================================
-- FUNCIÓN RPC: get_contratos_pendientes_confirmacion
-- ============================================================================
-- Propósito: Obtener contratos pendientes de confirmación para una tienda
--           consignataria con datos de tienda consignadora en UNA sola query
-- 
-- Beneficios:
--   ✅ Una sola query en lugar de N+1 queries
--   ✅ Reduce tiempo de carga significativamente
--   ✅ Mejor rendimiento en la BD
--   ✅ Menos transferencia de datos
--
-- Parámetro:
--   p_id_tienda: ID de la tienda consignataria
--
-- Retorna:
--   JSON con contratos y datos de tienda consignadora
--
-- ============================================================================

CREATE OR REPLACE FUNCTION get_contratos_pendientes_confirmacion(p_id_tienda INT)
RETURNS TABLE (
  id INT,
  id_tienda_consignadora INT,
  id_tienda_consignataria INT,
  estado INT,
  estado_confirmacion INT,
  porcentaje_comision NUMERIC,
  fecha_inicio DATE,
  fecha_fin DATE,
  plazo_dias INT,
  condiciones TEXT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  tienda_consignadora JSONB
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    cc.id,
    cc.id_tienda_consignadora,
    cc.id_tienda_consignataria,
    cc.estado,
    cc.estado_confirmacion,
    cc.porcentaje_comision,
    cc.fecha_inicio,
    cc.fecha_fin,
    cc.plazo_dias,
    cc.condiciones,
    cc.created_at,
    cc.updated_at,
    -- Datos de tienda consignadora como JSONB
    jsonb_build_object(
      'id', t.id,
      'denominacion', t.denominacion,
      'direccion', t.direccion
    ) AS tienda_consignadora
  FROM app_dat_contrato_consignacion cc
  INNER JOIN app_dat_tienda t ON cc.id_tienda_consignadora = t.id
  WHERE cc.id_tienda_consignataria = p_id_tienda
    AND cc.estado_confirmacion = 0  -- Pendiente
    AND cc.estado = 1               -- Activo
  ORDER BY cc.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- NOTAS DE IMPLEMENTACIÓN:
-- ============================================================================
-- 1. Ejecuta este SQL en tu editor de Supabase (SQL Editor)
-- 2. La función usa INNER JOIN para obtener datos de tienda en una sola query
-- 3. Retorna JSONB para mantener compatibilidad con el código Flutter
-- 4. El fallback en Flutter usa .select() con relaciones si RPC no está disponible
-- 5. Puedes verificar que funciona ejecutando:
--    SELECT * FROM get_contratos_pendientes_confirmacion(1);
--
-- ============================================================================
-- ALTERNATIVA: Si prefieres usar relaciones de Supabase (sin RPC)
-- ============================================================================
-- En lugar de RPC, puedes usar:
-- 
-- SELECT *, 
--   tienda_consignadora:id_tienda_consignadora(id, denominacion, direccion)
-- FROM app_dat_contrato_consignacion
-- WHERE id_tienda_consignataria = 1
--   AND estado_confirmacion = 0
--   AND estado = 1
-- ORDER BY created_at DESC
--
-- Esto también optimiza la query con relaciones en lugar de N+1 queries
-- ============================================================================
