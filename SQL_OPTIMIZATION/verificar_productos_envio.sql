-- ============================================================================
-- VERIFICACIÓN: Productos guardados en app_dat_consignacion_envio_producto
-- ============================================================================

-- 1. Ver todos los envíos creados recientemente
SELECT 
  id,
  numero_envio,
  estado_envio,
  created_at
FROM app_dat_consignacion_envio
ORDER BY created_at DESC
LIMIT 10;

-- 2. Ver productos del envío más reciente
SELECT 
  cep.id,
  cep.id_envio,
  cep.id_producto,
  cep.id_inventario,
  cep.cantidad_propuesta,
  cep.precio_costo_cup,
  p.denominacion,
  p.sku
FROM app_dat_consignacion_envio_producto cep
INNER JOIN app_dat_producto p ON cep.id_producto = p.id
WHERE cep.id_envio = (
  SELECT id FROM app_dat_consignacion_envio 
  ORDER BY created_at DESC LIMIT 1
)
ORDER BY cep.id;

-- 3. Probar el RPC obtener_productos_envio directamente
SELECT * FROM obtener_productos_envio(
  (SELECT id FROM app_dat_consignacion_envio ORDER BY created_at DESC LIMIT 1)
);

-- 4. Contar productos por envío
SELECT 
  ce.id,
  ce.numero_envio,
  COUNT(cep.id) as cantidad_productos
FROM app_dat_consignacion_envio ce
LEFT JOIN app_dat_consignacion_envio_producto cep ON ce.id = cep.id_envio
GROUP BY ce.id, ce.numero_envio
ORDER BY ce.created_at DESC
LIMIT 10;
