-- ============================================================================
-- DUPLICACIÓN DE PRODUCTOS PARA CONSIGNACIÓN
-- ============================================================================
-- Cuando se confirma un contrato de consignación, los productos se duplican
-- en la tienda destino para que puedan ser vendidos inmediatamente.
--
-- ============================================================================

-- 1. Tabla de Trazabilidad
CREATE TABLE IF NOT EXISTS app_dat_producto_consignacion_duplicado (
  id SERIAL PRIMARY KEY,
  id_producto_original BIGINT NOT NULL,
  id_producto_duplicado BIGINT NOT NULL,
  id_presentacion_original BIGINT,
  id_presentacion_duplicada BIGINT,
  id_contrato_consignacion INT NOT NULL,
  id_tienda_origen INT NOT NULL,
  id_tienda_destino INT NOT NULL,
  fecha_duplicacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  duplicado_por UUID,
  
  FOREIGN KEY (id_producto_original) REFERENCES app_dat_producto(id) ON DELETE CASCADE,
  FOREIGN KEY (id_producto_duplicado) REFERENCES app_dat_producto(id) ON DELETE CASCADE,
  FOREIGN KEY (id_presentacion_original) REFERENCES app_dat_producto_presentacion(id) ON DELETE SET NULL,
  FOREIGN KEY (id_presentacion_duplicada) REFERENCES app_dat_producto_presentacion(id) ON DELETE SET NULL,
  FOREIGN KEY (id_contrato_consignacion) REFERENCES app_dat_contrato_consignacion(id) ON DELETE CASCADE,
  FOREIGN KEY (id_tienda_origen) REFERENCES app_dat_tienda(id),
  FOREIGN KEY (id_tienda_destino) REFERENCES app_dat_tienda(id),
  
  UNIQUE(id_producto_original, id_tienda_destino)
);

-- 2. Índices para optimización
CREATE INDEX IF NOT EXISTS idx_producto_consignacion_duplicado_original 
ON app_dat_producto_consignacion_duplicado(id_producto_original);

CREATE INDEX IF NOT EXISTS idx_producto_consignacion_duplicado_nuevo 
ON app_dat_producto_consignacion_duplicado(id_producto_duplicado);

CREATE INDEX IF NOT EXISTS idx_producto_consignacion_duplicado_contrato 
ON app_dat_producto_consignacion_duplicado(id_contrato_consignacion);

CREATE INDEX IF NOT EXISTS idx_producto_consignacion_duplicado_tiendas 
ON app_dat_producto_consignacion_duplicado(id_tienda_origen, id_tienda_destino);

-- ============================================================================
-- FUNCIÓN AUXILIAR: Verificar si producto existe en tienda
-- ============================================================================
CREATE OR REPLACE FUNCTION producto_existe_en_tienda(
  p_id_producto BIGINT,
  p_id_tienda BIGINT
)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM app_dat_producto
    WHERE id = p_id_producto AND id_tienda = p_id_tienda
  );
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCIÓN RPC: Duplicar Producto SOLO si no existe (Bajo Demanda)
-- ============================================================================
CREATE OR REPLACE FUNCTION duplicar_producto_si_necesario(
  p_id_producto_original BIGINT,
  p_id_tienda_destino BIGINT,
  p_id_contrato_consignacion INT,
  p_id_tienda_origen BIGINT,
  p_uuid_usuario UUID DEFAULT NULL
)
RETURNS TABLE (
  success BOOLEAN,
  id_producto_resultado BIGINT,
  fue_duplicado BOOLEAN,
  message VARCHAR
) AS $$
DECLARE
  v_id_producto_existente BIGINT;
  v_id_categoria_destino BIGINT;
  v_id_producto_nuevo BIGINT;
  v_categoria_origen BIGINT;
  v_categoria_nombre VARCHAR;
  v_count_subcategorias INT;
  v_count_presentaciones INT;
  v_count_multimedias INT;
  v_count_etiquetas INT;
  v_count_unidades INT;
  v_id_presentacion_original BIGINT;
  v_id_presentacion_duplicada BIGINT;
BEGIN
  -- 1. Verificar si ya existe en tienda destino (buscar por SKU o ID)
  SELECT id INTO v_id_producto_existente
  FROM app_dat_producto
  WHERE id_tienda = p_id_tienda_destino
    AND (id = p_id_producto_original OR sku = (SELECT sku FROM app_dat_producto WHERE id = p_id_producto_original))
  LIMIT 1;
  
  IF v_id_producto_existente IS NOT NULL THEN
    RETURN QUERY SELECT 
      true::BOOLEAN, 
      v_id_producto_existente::BIGINT, 
      false::BOOLEAN,
      'Producto ya existe en tienda destino - reutilizando'::VARCHAR;
    RETURN;
  END IF;
  
  -- 2. Obtener categoría original
  SELECT id_categoria INTO v_categoria_origen
  FROM app_dat_producto
  WHERE id = p_id_producto_original;
  
  IF v_categoria_origen IS NULL THEN
    RETURN QUERY SELECT false::BOOLEAN, NULL::BIGINT, false::BOOLEAN, 'Producto original no encontrado'::VARCHAR;
    RETURN;
  END IF;
  
  -- 3. Obtener nombre de categoría
  SELECT denominacion INTO v_categoria_nombre
  FROM app_dat_categoria
  WHERE id = v_categoria_origen;
  
  -- 4. Verificar si categoría existe en tienda destino
  SELECT id_categoria INTO v_id_categoria_destino
  FROM app_dat_categoria_tienda
  WHERE id_tienda = p_id_tienda_destino
    AND id_categoria = v_categoria_origen
  LIMIT 1;
  
  -- 5. Si no existe, crear asociación de categoría en tienda destino
  IF v_id_categoria_destino IS NULL THEN
    INSERT INTO app_dat_categoria_tienda (id_tienda, id_categoria)
    VALUES (p_id_tienda_destino, v_categoria_origen)
    ON CONFLICT DO NOTHING;
    
    -- Usar la categoría origen como destino (es la misma categoría, solo se asocia a otra tienda)
    v_id_categoria_destino := v_categoria_origen;
  END IF;
  
  -- 6. Validar que tenemos categoría válida
  IF v_id_categoria_destino IS NULL THEN
    RETURN QUERY SELECT false::BOOLEAN, NULL::BIGINT, false::BOOLEAN, 'Error: No se pudo asignar categoría en tienda destino'::VARCHAR;
    RETURN;
  END IF;
  
  -- 7. Duplicar producto base (usar v_id_categoria_destino que ahora contiene el ID de categoría correcto)
  -- NOTA: Se excluyen id_vendedor_app (NULL) y mostrar_en_catalogo (false) de la duplicación
  INSERT INTO app_dat_producto (
    id_tienda, sku, id_categoria, denominacion, nombre_comercial,
    denominacion_corta, descripcion, descripcion_corta, um,
    es_refrigerado, es_fragil, es_peligroso, es_vendible, es_comprable,
    es_inventariable, es_por_lotes, dias_alert_caducidad, codigo_barras,
    imagen, es_elaborado, es_servicio, created_at
  )
  SELECT
    p_id_tienda_destino, sku, v_id_categoria_destino, denominacion, nombre_comercial,
    denominacion_corta, descripcion, descripcion_corta, um,
    es_refrigerado, es_fragil, es_peligroso, es_vendible, es_comprable,
    es_inventariable, es_por_lotes, dias_alert_caducidad, codigo_barras,
    imagen, es_elaborado, es_servicio, CURRENT_TIMESTAMP
  FROM app_dat_producto
  WHERE id = p_id_producto_original
  RETURNING id INTO v_id_producto_nuevo;
  
  IF v_id_producto_nuevo IS NULL THEN
    RETURN QUERY SELECT false::BOOLEAN, NULL::BIGINT, false::BOOLEAN, 'Error al duplicar producto base'::VARCHAR;
    RETURN;
  END IF;
  
  -- 8. Duplicar subcategorías
  INSERT INTO app_dat_productos_subcategorias (id_producto, id_sub_categoria, created_at)
  SELECT v_id_producto_nuevo, id_sub_categoria, CURRENT_TIMESTAMP
  FROM app_dat_productos_subcategorias
  WHERE id_producto = p_id_producto_original
  ON CONFLICT DO NOTHING;
  
  GET DIAGNOSTICS v_count_subcategorias = ROW_COUNT;
  
  -- 9. Duplicar presentaciones y guardar mapeo de la presentación base
  INSERT INTO app_dat_producto_presentacion (id_producto, id_presentacion, cantidad, es_base, precio_promedio, created_at)
  SELECT v_id_producto_nuevo, id_presentacion, cantidad, es_base, precio_promedio, CURRENT_TIMESTAMP
  FROM app_dat_producto_presentacion
  WHERE id_producto = p_id_producto_original
  ON CONFLICT DO NOTHING;
  
  GET DIAGNOSTICS v_count_presentaciones = ROW_COUNT;
  
  -- 9.1. Obtener ID de presentación original (la base)
  SELECT id INTO v_id_presentacion_original
  FROM app_dat_producto_presentacion
  WHERE id_producto = p_id_producto_original
    AND es_base = true
  LIMIT 1;
  
  -- 9.2. Obtener ID de presentación duplicada (la base)
  SELECT id INTO v_id_presentacion_duplicada
  FROM app_dat_producto_presentacion
  WHERE id_producto = v_id_producto_nuevo
    AND es_base = true
  LIMIT 1;
  
  -- 10. Duplicar multimedias
  INSERT INTO app_dat_producto_multimedias (id_producto, media, created_at)
  SELECT v_id_producto_nuevo, media, CURRENT_TIMESTAMP
  FROM app_dat_producto_multimedias
  WHERE id_producto = p_id_producto_original
  ON CONFLICT DO NOTHING;
  
  GET DIAGNOSTICS v_count_multimedias = ROW_COUNT;
  
  -- 11. Duplicar etiquetas
  INSERT INTO app_dat_producto_etiquetas (id_producto, etiqueta, created_at)
  SELECT v_id_producto_nuevo, etiqueta, CURRENT_TIMESTAMP
  FROM app_dat_producto_etiquetas
  WHERE id_producto = p_id_producto_original
  ON CONFLICT DO NOTHING;
  
  GET DIAGNOSTICS v_count_etiquetas = ROW_COUNT;
  
  -- 12. Duplicar unidades
  INSERT INTO app_dat_producto_unidades (id_producto, id_unidad_medida, factor_producto, es_unidad_compra, es_unidad_venta, es_unidad_inventario, observaciones, created_at)
  SELECT v_id_producto_nuevo, id_unidad_medida, factor_producto, es_unidad_compra, es_unidad_venta, es_unidad_inventario, observaciones, CURRENT_TIMESTAMP
  FROM app_dat_producto_unidades
  WHERE id_producto = p_id_producto_original
  ON CONFLICT DO NOTHING;
  
  GET DIAGNOSTICS v_count_unidades = ROW_COUNT;
  
  -- 13. Duplicar garantía (si existe)
  INSERT INTO app_dat_producto_garantia (id_producto, id_tipo_garantia, condiciones_especificas, es_activo)
  SELECT v_id_producto_nuevo, id_tipo_garantia, condiciones_especificas, es_activo
  FROM app_dat_producto_garantia
  WHERE id_producto = p_id_producto_original
  ON CONFLICT DO NOTHING;
  
  -- 14. Registrar trazabilidad con mapeo de presentaciones
  INSERT INTO app_dat_producto_consignacion_duplicado (
    id_producto_original, id_producto_duplicado, 
    id_presentacion_original, id_presentacion_duplicada,
    id_contrato_consignacion,
    id_tienda_origen, id_tienda_destino, duplicado_por, fecha_duplicacion
  ) VALUES (
    p_id_producto_original, v_id_producto_nuevo,
    v_id_presentacion_original, v_id_presentacion_duplicada,
    p_id_contrato_consignacion,
    p_id_tienda_origen, p_id_tienda_destino, p_uuid_usuario, CURRENT_TIMESTAMP
  )
  ON CONFLICT (id_producto_original, id_tienda_destino) 
  DO UPDATE SET
    id_producto_duplicado = EXCLUDED.id_producto_duplicado,
    id_presentacion_original = EXCLUDED.id_presentacion_original,
    id_presentacion_duplicada = EXCLUDED.id_presentacion_duplicada,
    id_contrato_consignacion = EXCLUDED.id_contrato_consignacion,
    duplicado_por = EXCLUDED.duplicado_por,
    fecha_duplicacion = CURRENT_TIMESTAMP;
  
  RETURN QUERY SELECT 
    true::BOOLEAN, 
    v_id_producto_nuevo::BIGINT, 
    true::BOOLEAN,
    format('Producto duplicado exitosamente. Subcategorías: %s, Presentaciones: %s, Multimedias: %s, Etiquetas: %s, Unidades: %s', 
      v_count_subcategorias, v_count_presentaciones, v_count_multimedias, v_count_etiquetas, v_count_unidades)::VARCHAR;
  
EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT false::BOOLEAN, NULL::BIGINT, false::BOOLEAN, ('Error: ' || SQLERRM)::VARCHAR;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCIÓN RPC: Duplicar Producto Completo (Versión Original)
-- ============================================================================
CREATE OR REPLACE FUNCTION duplicar_producto_consignacion(
  p_id_producto_original BIGINT,
  p_id_tienda_destino BIGINT,
  p_id_contrato_consignacion INT,
  p_id_tienda_origen BIGINT,
  p_uuid_usuario UUID DEFAULT NULL
)
RETURNS TABLE (
  success BOOLEAN,
  id_producto_nuevo BIGINT,
  message VARCHAR
) AS $$
DECLARE
  v_id_categoria_destino BIGINT;
  v_id_producto_nuevo BIGINT;
  v_categoria_origen BIGINT;
  v_categoria_nombre VARCHAR;
  v_count_subcategorias INT;
  v_count_presentaciones INT;
  v_count_multimedias INT;
  v_count_etiquetas INT;
  v_count_unidades INT;
BEGIN
  -- 1. Obtener categoría original
  SELECT id_categoria INTO v_categoria_origen
  FROM app_dat_producto
  WHERE id = p_id_producto_original;
  
  IF v_categoria_origen IS NULL THEN
    RETURN QUERY SELECT false::BOOLEAN, NULL::BIGINT, 'Producto original no encontrado'::VARCHAR;
    RETURN;
  END IF;
  
  -- 2. Obtener nombre de categoría
  SELECT denominacion INTO v_categoria_nombre
  FROM app_dat_categoria
  WHERE id = v_categoria_origen;
  
  -- 3. Verificar si categoría existe en tienda destino
  SELECT id INTO v_id_categoria_destino
  FROM app_dat_categoria_tienda
  WHERE id_tienda = p_id_tienda_destino
    AND id_categoria = v_categoria_origen
  LIMIT 1;
  
  -- 4. Si no existe, crear asociación de categoría en tienda destino
  IF v_id_categoria_destino IS NULL THEN
    INSERT INTO app_dat_categoria_tienda (id_tienda, id_categoria)
    VALUES (p_id_tienda_destino, v_categoria_origen)
    ON CONFLICT DO NOTHING;
    v_id_categoria_destino := v_categoria_origen;
  END IF;
  
  -- 5. Duplicar producto base
  INSERT INTO app_dat_producto (
    id_tienda, sku, id_categoria, denominacion, nombre_comercial,
    denominacion_corta, descripcion, descripcion_corta, um,
    es_refrigerado, es_fragil, es_peligroso, es_vendible, es_comprable,
    es_inventariable, es_por_lotes, dias_alert_caducidad, codigo_barras,
    imagen, es_elaborado, es_servicio, id_vendedor_app, mostrar_en_catalogo, created_at
  )
  SELECT
    p_id_tienda_destino, sku, v_id_categoria_destino, denominacion, nombre_comercial,
    denominacion_corta, descripcion, descripcion_corta, um,
    es_refrigerado, es_fragil, es_peligroso, es_vendible, es_comprable,
    es_inventariable, es_por_lotes, dias_alert_caducidad, codigo_barras,
    imagen, es_elaborado, es_servicio, NULL, false, CURRENT_TIMESTAMP
  FROM app_dat_producto
  WHERE id = p_id_producto_original
  RETURNING id INTO v_id_producto_nuevo;
  
  IF v_id_producto_nuevo IS NULL THEN
    RETURN QUERY SELECT false::BOOLEAN, NULL::BIGINT, 'Error al duplicar producto base'::VARCHAR;
    RETURN;
  END IF;
  
  -- 6. Duplicar subcategorías
  INSERT INTO app_dat_productos_subcategorias (id_producto, id_sub_categoria, created_at)
  SELECT v_id_producto_nuevo, id_sub_categoria, CURRENT_TIMESTAMP
  FROM app_dat_productos_subcategorias
  WHERE id_producto = p_id_producto_original
  ON CONFLICT DO NOTHING;
  
  GET DIAGNOSTICS v_count_subcategorias = ROW_COUNT;
  
  -- 7. Duplicar presentaciones
  INSERT INTO app_dat_producto_presentacion (id_producto, id_presentacion, cantidad, es_base, precio_promedio, created_at)
  SELECT v_id_producto_nuevo, id_presentacion, cantidad, es_base, precio_promedio, CURRENT_TIMESTAMP
  FROM app_dat_producto_presentacion
  WHERE id_producto = p_id_producto_original
  ON CONFLICT DO NOTHING;
  
  GET DIAGNOSTICS v_count_presentaciones = ROW_COUNT;
  
  -- 8. Duplicar multimedias
  INSERT INTO app_dat_producto_multimedias (id_producto, media, created_at)
  SELECT v_id_producto_nuevo, media, CURRENT_TIMESTAMP
  FROM app_dat_producto_multimedias
  WHERE id_producto = p_id_producto_original
  ON CONFLICT DO NOTHING;
  
  GET DIAGNOSTICS v_count_multimedias = ROW_COUNT;
  
  -- 9. Duplicar etiquetas
  INSERT INTO app_dat_producto_etiquetas (id_producto, etiqueta, created_at)
  SELECT v_id_producto_nuevo, etiqueta, CURRENT_TIMESTAMP
  FROM app_dat_producto_etiquetas
  WHERE id_producto = p_id_producto_original
  ON CONFLICT DO NOTHING;
  
  GET DIAGNOSTICS v_count_etiquetas = ROW_COUNT;
  
  -- 10. Duplicar unidades
  INSERT INTO app_dat_producto_unidades (id_producto, id_unidad_medida, factor_producto, es_unidad_compra, es_unidad_venta, es_unidad_inventario, observaciones, created_at)
  SELECT v_id_producto_nuevo, id_unidad_medida, factor_producto, es_unidad_compra, es_unidad_venta, es_unidad_inventario, observaciones, CURRENT_TIMESTAMP
  FROM app_dat_producto_unidades
  WHERE id_producto = p_id_producto_original
  ON CONFLICT DO NOTHING;
  
  GET DIAGNOSTICS v_count_unidades = ROW_COUNT;
  
  -- 11. Duplicar garantía (si existe)
  INSERT INTO app_dat_producto_garantia (id_producto, id_tipo_garantia, condiciones_especificas, es_activo)
  SELECT v_id_producto_nuevo, id_tipo_garantia, condiciones_especificas, es_activo
  FROM app_dat_producto_garantia
  WHERE id_producto = p_id_producto_original
  ON CONFLICT DO NOTHING;
  
  -- 12. Registrar trazabilidad
  INSERT INTO app_dat_producto_consignacion_duplicado (
    id_producto_original, id_producto_duplicado, id_contrato_consignacion,
    id_tienda_origen, id_tienda_destino, duplicado_por, fecha_duplicacion
  ) VALUES (
    p_id_producto_original, v_id_producto_nuevo, p_id_contrato_consignacion,
    p_id_tienda_origen, p_id_tienda_destino, p_uuid_usuario, CURRENT_TIMESTAMP
  )
  ON CONFLICT (id_producto_original, id_tienda_destino) 
  DO UPDATE SET
    id_producto_duplicado = EXCLUDED.id_producto_duplicado,
    id_contrato_consignacion = EXCLUDED.id_contrato_consignacion,
    duplicado_por = EXCLUDED.duplicado_por,
    fecha_duplicacion = CURRENT_TIMESTAMP;
  
  RETURN QUERY SELECT 
    true::BOOLEAN, 
    v_id_producto_nuevo::BIGINT, 
    format('Producto duplicado exitosamente. Subcategorías: %s, Presentaciones: %s, Multimedias: %s, Etiquetas: %s, Unidades: %s', 
      v_count_subcategorias, v_count_presentaciones, v_count_multimedias, v_count_etiquetas, v_count_unidades)::VARCHAR;
  
EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT false::BOOLEAN, NULL::BIGINT, ('Error: ' || SQLERRM)::VARCHAR;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCIÓN RPC: Duplicar Múltiples Productos de un Contrato
-- ============================================================================
CREATE OR REPLACE FUNCTION duplicar_productos_contrato_consignacion(
  p_id_contrato INT,
  p_id_tienda_destino BIGINT,
  p_id_tienda_origen BIGINT,
  p_uuid_usuario UUID DEFAULT NULL
)
RETURNS TABLE (
  success BOOLEAN,
  total_productos INT,
  productos_duplicados INT,
  productos_fallidos INT,
  message VARCHAR
) AS $$
DECLARE
  v_producto RECORD;
  v_total INT := 0;
  v_exitosos INT := 0;
  v_fallidos INT := 0;
  v_resultado RECORD;
BEGIN
  -- Obtener productos del contrato
  FOR v_producto IN
    SELECT DISTINCT pc.id_producto
    FROM app_dat_producto_consignacion pc
    WHERE pc.id_contrato = p_id_contrato
      AND pc.estado = 1
  LOOP
    v_total := v_total + 1;
    
    -- Intentar duplicar producto
    FOR v_resultado IN
      SELECT * FROM duplicar_producto_consignacion(
        v_producto.id_producto,
        p_id_tienda_destino,
        p_id_contrato,
        p_id_tienda_origen,
        p_uuid_usuario
      )
    LOOP
      IF v_resultado.success THEN
        v_exitosos := v_exitosos + 1;
      ELSE
        v_fallidos := v_fallidos + 1;
      END IF;
    END LOOP;
  END LOOP;
  
  RETURN QUERY SELECT 
    (v_fallidos = 0)::BOOLEAN,
    v_total::INT,
    v_exitosos::INT,
    v_fallidos::INT,
    format('Duplicación completada. Total: %s, Exitosos: %s, Fallidos: %s', v_total, v_exitosos, v_fallidos)::VARCHAR;
  
EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT false::BOOLEAN, 0::INT, 0::INT, 0::INT, ('Error: ' || SQLERRM)::VARCHAR;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCIÓN RPC: Obtener Producto Duplicado
-- ============================================================================
CREATE OR REPLACE FUNCTION get_producto_duplicado(
  p_id_producto_original BIGINT,
  p_id_tienda_destino BIGINT
)
RETURNS TABLE (
  id_producto_duplicado BIGINT,
  id_contrato_consignacion INT,
  fecha_duplicacion TIMESTAMP,
  duplicado_por UUID
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    pcd.id_producto_duplicado,
    pcd.id_contrato_consignacion,
    pcd.fecha_duplicacion,
    pcd.duplicado_por
  FROM app_dat_producto_consignacion_duplicado pcd
  WHERE pcd.id_producto_original = p_id_producto_original
    AND pcd.id_tienda_destino = p_id_tienda_destino
  LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCIÓN RPC: Obtener Historial de Duplicaciones por Contrato
-- ============================================================================
CREATE OR REPLACE FUNCTION get_historial_duplicaciones_contrato(
  p_id_contrato INT
)
RETURNS TABLE (
  id_producto_original BIGINT,
  denominacion_original VARCHAR,
  id_producto_duplicado BIGINT,
  denominacion_duplicada VARCHAR,
  id_tienda_origen BIGINT,
  tienda_origen VARCHAR,
  id_tienda_destino BIGINT,
  tienda_destino VARCHAR,
  fecha_duplicacion TIMESTAMP
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    pcd.id_producto_original,
    po.denominacion,
    pcd.id_producto_duplicado,
    pd.denominacion,
    pcd.id_tienda_origen,
    to_tienda.denominacion,
    pcd.id_tienda_destino,
    td_tienda.denominacion,
    pcd.fecha_duplicacion
  FROM app_dat_producto_consignacion_duplicado pcd
  INNER JOIN app_dat_producto po ON pcd.id_producto_original = po.id
  INNER JOIN app_dat_producto pd ON pcd.id_producto_duplicado = pd.id
  INNER JOIN app_dat_tienda to_tienda ON pcd.id_tienda_origen = to_tienda.id
  INNER JOIN app_dat_tienda td_tienda ON pcd.id_tienda_destino = td_tienda.id
  WHERE pcd.id_contrato_consignacion = p_id_contrato
  ORDER BY pcd.fecha_duplicacion DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- NOTAS:
-- ============================================================================
-- 1. Ejecuta todo este SQL en Supabase SQL Editor
-- 2. Crea tabla de trazabilidad para registrar duplicaciones
-- 3. Función RPC para duplicar un producto completo
-- 4. Función RPC para duplicar múltiples productos de un contrato
-- 5. Funciones RPC para consultar historial de duplicaciones
-- 6. Todos los campos relacionados se copian automáticamente
-- 7. Se registra quién duplicó y cuándo
-- 8. Índices optimizados para búsquedas rápidas
-- ============================================================================
