-- ============================================================================
-- MAPEO DE CATEGORÍAS PARA PRODUCTOS DE CONSIGNACIÓN
-- ============================================================================
-- Problema: Productos de consignación tienen categorías que no existen en la tienda receptora
-- Solución: Mapear automáticamente a categorías existentes o crear equivalentes
--
-- ============================================================================

-- 1. Tabla de mapeo de categorías entre tiendas
CREATE TABLE IF NOT EXISTS app_dat_mapeo_categoria_tienda (
  id SERIAL PRIMARY KEY,
  id_tienda_origen INT NOT NULL,
  id_categoria_origen INT NOT NULL,
  id_tienda_destino INT NOT NULL,
  id_categoria_destino INT NOT NULL,
  id_subcategoria_origen INT,
  id_subcategoria_destino INT,
  activo BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  
  FOREIGN KEY (id_tienda_origen) REFERENCES app_dat_tienda(id),
  FOREIGN KEY (id_categoria_origen) REFERENCES app_dat_categoria(id),
  FOREIGN KEY (id_tienda_destino) REFERENCES app_dat_tienda(id),
  FOREIGN KEY (id_categoria_destino) REFERENCES app_dat_categoria(id),
  FOREIGN KEY (id_subcategoria_origen) REFERENCES app_dat_subcategorias(id),
  FOREIGN KEY (id_subcategoria_destino) REFERENCES app_dat_subcategorias(id),
  
  UNIQUE(id_tienda_origen, id_categoria_origen, id_tienda_destino, id_subcategoria_origen)
);

-- 2. Función para obtener categoría mapeada
CREATE OR REPLACE FUNCTION get_categoria_mapeada(
  p_id_tienda_origen INT,
  p_id_categoria_origen INT,
  p_id_subcategoria_origen INT,
  p_id_tienda_destino INT
)
RETURNS TABLE (
  id_categoria_destino INT,
  id_subcategoria_destino INT,
  categoria_nombre VARCHAR,
  subcategoria_nombre VARCHAR
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    mct.id_categoria_destino,
    mct.id_subcategoria_destino,
    cat.denominacion,
    subcat.denominacion
  FROM app_dat_mapeo_categoria_tienda mct
  LEFT JOIN app_dat_categoria cat ON mct.id_categoria_destino = cat.id
  LEFT JOIN app_dat_subcategorias subcat ON mct.id_subcategoria_destino = subcat.id
  WHERE mct.id_tienda_origen = p_id_tienda_origen
    AND mct.id_categoria_origen = p_id_categoria_origen
    AND mct.id_tienda_destino = p_id_tienda_destino
    AND (p_id_subcategoria_origen IS NULL OR mct.id_subcategoria_origen = p_id_subcategoria_origen)
    AND mct.activo = true
  LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- 3. Función para obtener productos de consignación sin categoría mapeada
CREATE OR REPLACE FUNCTION get_productos_consignacion_sin_mapeo(
  p_id_tienda_destino INT
)
RETURNS TABLE (
  id_producto_consignacion INT,
  id_producto INT,
  denominacion_producto VARCHAR,
  sku_producto VARCHAR,
  id_categoria_origen INT,
  categoria_origen VARCHAR,
  id_subcategoria_origen INT,
  subcategoria_origen VARCHAR,
  id_tienda_origen INT,
  tienda_origen VARCHAR,
  cantidad_disponible NUMERIC
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    pc.id,
    p.id,
    p.denominacion,
    p.sku,
    cat.id,
    cat.denominacion,
    subcat.id,
    subcat.denominacion,
    cc.id_tienda_consignadora,
    t.denominacion,
    (pc.cantidad_enviada - pc.cantidad_vendida - pc.cantidad_devuelta) as cantidad_disponible
  FROM app_dat_producto_consignacion pc
  INNER JOIN app_dat_contrato_consignacion cc ON pc.id_contrato = cc.id
  INNER JOIN app_dat_producto p ON pc.id_producto = p.id
  LEFT JOIN app_dat_categoria cat ON p.id_categoria = cat.id
  LEFT JOIN app_dat_subcategorias subcat ON p.id_subcategoria = subcat.id
  INNER JOIN app_dat_tienda t ON cc.id_tienda_consignadora = t.id
  WHERE cc.id_tienda_consignataria = p_id_tienda_destino
    AND pc.estado = 1  -- Confirmados
    AND pc.id NOT IN (
      SELECT DISTINCT id_producto_consignacion 
      FROM app_dat_producto_consignacion_categoria_tienda
      WHERE id_tienda_destino = p_id_tienda_destino
    )
  ORDER BY t.denominacion, cat.denominacion, subcat.denominacion;
END;
$$ LANGUAGE plpgsql;

-- 4. Tabla para registrar qué categoría destino se asignó a cada producto de consignación
CREATE TABLE IF NOT EXISTS app_dat_producto_consignacion_categoria_tienda (
  id SERIAL PRIMARY KEY,
  id_producto_consignacion INT NOT NULL,
  id_tienda_destino INT NOT NULL,
  id_categoria_destino INT NOT NULL,
  id_subcategoria_destino INT,
  asignado_por INT,
  asignado_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  
  FOREIGN KEY (id_producto_consignacion) REFERENCES app_dat_producto_consignacion(id),
  FOREIGN KEY (id_tienda_destino) REFERENCES app_dat_tienda(id),
  FOREIGN KEY (id_categoria_destino) REFERENCES app_dat_categoria(id),
  FOREIGN KEY (id_subcategoria_destino) REFERENCES app_dat_subcategorias(id),
  
  UNIQUE(id_producto_consignacion, id_tienda_destino)
);

-- 5. Función para asignar categoría a producto de consignación
CREATE OR REPLACE FUNCTION asignar_categoria_producto_consignacion(
  p_id_producto_consignacion INT,
  p_id_tienda_destino INT,
  p_id_categoria_destino INT,
  p_id_subcategoria_destino INT DEFAULT NULL,
  p_asignado_por INT DEFAULT NULL
)
RETURNS TABLE (
  success BOOLEAN,
  message VARCHAR
) AS $$
BEGIN
  INSERT INTO app_dat_producto_consignacion_categoria_tienda (
    id_producto_consignacion,
    id_tienda_destino,
    id_categoria_destino,
    id_subcategoria_destino,
    asignado_por
  ) VALUES (
    p_id_producto_consignacion,
    p_id_tienda_destino,
    p_id_categoria_destino,
    p_id_subcategoria_destino,
    p_asignado_por
  )
  ON CONFLICT (id_producto_consignacion, id_tienda_destino) 
  DO UPDATE SET
    id_categoria_destino = EXCLUDED.id_categoria_destino,
    id_subcategoria_destino = EXCLUDED.id_subcategoria_destino,
    asignado_en = CURRENT_TIMESTAMP;
  
  RETURN QUERY SELECT true::BOOLEAN, 'Categoría asignada exitosamente'::VARCHAR;
EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT false::BOOLEAN, 'Error: ' || SQLERRM;
END;
$$ LANGUAGE plpgsql;

-- 6. Función para obtener productos de consignación CON categoría asignada (para venta)
CREATE OR REPLACE FUNCTION get_productos_consignacion_para_venta(
  p_id_tienda_destino INT,
  p_id_categoria_destino INT DEFAULT NULL
)
RETURNS TABLE (
  id_producto_consignacion INT,
  id_producto INT,
  denominacion_producto VARCHAR,
  sku_producto VARCHAR,
  id_categoria_destino INT,
  categoria_destino VARCHAR,
  id_subcategoria_destino INT,
  subcategoria_destino VARCHAR,
  cantidad_disponible NUMERIC,
  precio_venta_sugerido NUMERIC,
  tienda_origen VARCHAR
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    pc.id,
    p.id,
    p.denominacion,
    p.sku,
    pct.id_categoria_destino,
    cat.denominacion,
    pct.id_subcategoria_destino,
    subcat.denominacion,
    (pc.cantidad_enviada - pc.cantidad_vendida - pc.cantidad_devuelta),
    pc.precio_venta_sugerido,
    t.denominacion
  FROM app_dat_producto_consignacion pc
  INNER JOIN app_dat_contrato_consignacion cc ON pc.id_contrato = cc.id
  INNER JOIN app_dat_producto p ON pc.id_producto = p.id
  INNER JOIN app_dat_producto_consignacion_categoria_tienda pct ON pc.id = pct.id_producto_consignacion
  INNER JOIN app_dat_categoria cat ON pct.id_categoria_destino = cat.id
  LEFT JOIN app_dat_subcategorias subcat ON pct.id_subcategoria_destino = subcat.id
  INNER JOIN app_dat_tienda t ON cc.id_tienda_consignadora = t.id
  WHERE cc.id_tienda_consignataria = p_id_tienda_destino
    AND pc.estado = 1  -- Confirmados
    AND pct.id_tienda_destino = p_id_tienda_destino
    AND (p_id_categoria_destino IS NULL OR pct.id_categoria_destino = p_id_categoria_destino)
  ORDER BY cat.denominacion, subcat.denominacion, p.denominacion;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- ÍNDICES PARA OPTIMIZACIÓN
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_mapeo_categoria_tienda_origen_destino 
ON app_dat_mapeo_categoria_tienda(id_tienda_origen, id_tienda_destino, id_categoria_origen);

CREATE INDEX IF NOT EXISTS idx_producto_consignacion_categoria_tienda 
ON app_dat_producto_consignacion_categoria_tienda(id_tienda_destino, id_categoria_destino);

-- ============================================================================
-- NOTAS:
-- ============================================================================
-- 1. Ejecuta todo este SQL en Supabase SQL Editor
-- 2. Crea tablas para mapear categorías entre tiendas
-- 3. Permite asignar categorías destino a productos de consignación
-- 4. Funciones RPC para obtener productos sin mapeo y con mapeo
-- 5. Soluciona el problema de categorías faltantes
-- ============================================================================
