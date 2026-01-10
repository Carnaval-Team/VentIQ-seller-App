-- ============================================================================
-- COMPLETAR OPERACIONES DE AUDITORÍA DE CONSIGNACIÓN
-- ============================================================================
-- Completa las operaciones de extracción y recepción para que el inventario
-- se actualice correctamente en la zona de consignación
-- ============================================================================

-- PASO 1: Identificar las operaciones pendientes
-- Reemplaza los IDs con los de tus operaciones

-- Ver operaciones pendientes de consignación
SELECT 
  op.id,
  op.id_tienda,
  t.denominacion as tienda,
  nto.denominacion as tipo_operacion,
  eo.estado,
  CASE 
    WHEN eo.estado = 1 THEN 'PENDIENTE'
    WHEN eo.estado = 2 THEN 'COMPLETADA'
    ELSE 'OTRO'
  END as estado_texto,
  op.created_at
FROM app_dat_operaciones op
INNER JOIN app_dat_tienda t ON t.id = op.id_tienda
INNER JOIN app_nom_tipo_operacion nto ON nto.id = op.id_tipo_operacion
INNER JOIN app_dat_estado_operacion eo ON eo.id_operacion = op.id
WHERE nto.denominacion IN ('Extracción', 'Recepción')
  AND eo.estado = 1  -- PENDIENTE
ORDER BY op.created_at DESC
LIMIT 20;

-- ============================================================================
-- PASO 2: Completar operación de EXTRACCIÓN (tienda consignadora)
-- ============================================================================
-- Reemplaza 42829 con el ID de tu operación de extracción

INSERT INTO app_dat_estado_operacion (
  id_operacion,
  estado,
  comentario,
  created_at
) VALUES (
  42829,  -- ⚠️ REEMPLAZAR con ID de operación de extracción
  2,      -- Estado 2 = COMPLETADA
  'Operación de extracción completada - Consignación',
  CURRENT_TIMESTAMP
);

-- ============================================================================
-- PASO 3: Completar operación de RECEPCIÓN (tienda consignataria)
-- ============================================================================
-- Reemplaza 42830 con el ID de tu operación de recepción

INSERT INTO app_dat_estado_operacion (
  id_operacion,
  estado,
  comentario,
  created_at
) VALUES (
  42830,  -- ⚠️ REEMPLAZAR con ID de operación de recepción
  2,      -- Estado 2 = COMPLETADA
  'Operación de recepción completada - Consignación',
  CURRENT_TIMESTAMP
);

-- ============================================================================
-- PASO 4: Verificar que se completaron correctamente
-- ============================================================================

SELECT 
  op.id,
  t.denominacion as tienda,
  nto.denominacion as tipo_operacion,
  eo.estado,
  CASE 
    WHEN eo.estado = 1 THEN 'PENDIENTE'
    WHEN eo.estado = 2 THEN 'COMPLETADA'
    ELSE 'OTRO'
  END as estado_texto,
  eo.created_at as fecha_cambio_estado
FROM app_dat_operaciones op
INNER JOIN app_dat_tienda t ON t.id = op.id_tienda
INNER JOIN app_nom_tipo_operacion nto ON nto.id = op.id_tipo_operacion
INNER JOIN app_dat_estado_operacion eo ON eo.id_operacion = op.id
WHERE op.id IN (42829, 42830)  -- ⚠️ REEMPLAZAR con tus IDs
ORDER BY eo.created_at DESC;

-- ============================================================================
-- PASO 5: Verificar inventario en zona de consignación
-- ============================================================================

SELECT 
  ip.id as id_inventario,
  p.denominacion as producto,
  ip.cantidad_disponible,
  u.denominacion as ubicacion,
  t.denominacion as tienda
FROM app_dat_inventario_productos ip
INNER JOIN app_dat_producto p ON p.id = ip.id_producto
INNER JOIN app_dat_ubicacion u ON u.id = ip.id_ubicacion
INNER JOIN app_dat_tienda t ON t.id = ip.id_tienda
WHERE u.denominacion ILIKE '%consignación%'
  AND ip.cantidad_disponible > 0
ORDER BY ip.created_at DESC
LIMIT 20;
