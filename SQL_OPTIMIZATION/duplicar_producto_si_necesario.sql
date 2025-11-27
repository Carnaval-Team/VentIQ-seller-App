-- ============================================================================
-- FUNCIÓN: duplicar_producto_si_necesario
-- DESCRIPCIÓN: Duplica un producto SOLO si no existe en la tienda destino
-- RETORNA: ID del producto (duplicado o existente)
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
BEGIN
  -- 1. Verificar si ya existe en tienda destino (buscar por SKU)
  -- IMPORTANTE: Buscar SOLO por SKU, no por ID (el ID es diferente en cada tienda)
  SELECT id INTO v_id_producto_existente
  FROM app_dat_producto
  WHERE id_tienda = p_id_tienda_destino
    AND sku = (SELECT sku FROM app_dat_producto WHERE id = p_id_producto_original)
  LIMIT 1;
  
  IF v_id_producto_existente IS NOT NULL THEN
    RETURN QUERY SELECT 
      true::BOOLEAN, 
      v_id_producto_existente::BIGINT,  -- Retornar el ID del producto existente, NO el original
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
  -- Nota: Usamos directamente v_categoria_origen como id_categoria
  -- No necesitamos app_dat_categoria_tienda para el INSERT
  v_id_categoria_destino := v_categoria_origen;
  
  -- 5. Validar que tenemos categoría válida
  IF v_id_categoria_destino IS NULL THEN
    RETURN QUERY SELECT false::BOOLEAN, NULL::BIGINT, false::BOOLEAN, 'Error: Categoría origen no válida'::VARCHAR;
    RETURN;
  END IF;
  
  -- 7. Duplicar producto base
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
  
  -- 9. Duplicar presentaciones
  INSERT INTO app_dat_producto_presentacion (id_producto, id_presentacion, cantidad, es_base, precio_promedio, created_at)
  SELECT v_id_producto_nuevo, id_presentacion, cantidad, es_base, precio_promedio, CURRENT_TIMESTAMP
  FROM app_dat_producto_presentacion
  WHERE id_producto = p_id_producto_original
  ON CONFLICT DO NOTHING;
  
  GET DIAGNOSTICS v_count_presentaciones = ROW_COUNT;
  
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
  
  -- 14. Registrar trazabilidad
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
    true::BOOLEAN,
    format('Producto duplicado exitosamente. Subcategorías: %s, Presentaciones: %s, Multimedias: %s, Etiquetas: %s, Unidades: %s', 
      v_count_subcategorias, v_count_presentaciones, v_count_multimedias, v_count_etiquetas, v_count_unidades)::VARCHAR;
  
EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT false::BOOLEAN, NULL::BIGINT, false::BOOLEAN, ('Error: ' || SQLERRM)::VARCHAR;
END;
$$ LANGUAGE plpgsql;
