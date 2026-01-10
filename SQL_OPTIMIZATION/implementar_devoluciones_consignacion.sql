-- ============================================================================
-- IMPLEMENTACIÓN COMPLETA: Sistema de Devoluciones en Consignación
-- ============================================================================
-- Fecha: 7 de Enero, 2026
-- Propósito: Agregar campos para mantener trazabilidad del producto original
--            en devoluciones de consignación
-- ============================================================================

-- ============================================================================
-- PASO 1: Agregar columnas a app_dat_consignacion_envio_producto
-- ============================================================================

-- Agregar columnas para mantener referencia al producto original
ALTER TABLE app_dat_consignacion_envio_producto
ADD COLUMN IF NOT EXISTS id_presentacion_original bigint,
ADD COLUMN IF NOT EXISTS id_variante_original bigint,
ADD COLUMN IF NOT EXISTS id_ubicacion_original bigint,
ADD COLUMN IF NOT EXISTS id_inventario_original bigint;

-- Agregar comentarios para documentación
COMMENT ON COLUMN app_dat_consignacion_envio_producto.id_presentacion_original IS 
  'Presentación del producto en la tienda consignadora (para devoluciones)';
COMMENT ON COLUMN app_dat_consignacion_envio_producto.id_variante_original IS 
  'Variante del producto en la tienda consignadora (para devoluciones)';
COMMENT ON COLUMN app_dat_consignacion_envio_producto.id_ubicacion_original IS 
  'Ubicación (zona) del producto en la tienda consignadora (para devoluciones)';
COMMENT ON COLUMN app_dat_consignacion_envio_producto.id_inventario_original IS 
  'Referencia al registro de inventario original (para devoluciones)';

-- ============================================================================
-- PASO 2: Agregar Foreign Keys
-- ============================================================================

-- FK para presentación original
ALTER TABLE app_dat_consignacion_envio_producto
DROP CONSTRAINT IF EXISTS fk_envio_producto_presentacion_original;

ALTER TABLE app_dat_consignacion_envio_producto
ADD CONSTRAINT fk_envio_producto_presentacion_original 
  FOREIGN KEY (id_presentacion_original) 
  REFERENCES app_dat_producto_presentacion(id)
  ON DELETE SET NULL;

-- FK para variante original
ALTER TABLE app_dat_consignacion_envio_producto
DROP CONSTRAINT IF EXISTS fk_envio_producto_variante_original;

ALTER TABLE app_dat_consignacion_envio_producto
ADD CONSTRAINT fk_envio_producto_variante_original 
  FOREIGN KEY (id_variante_original) 
  REFERENCES app_dat_variantes(id)
  ON DELETE SET NULL;

-- FK para ubicación original
ALTER TABLE app_dat_consignacion_envio_producto
DROP CONSTRAINT IF EXISTS fk_envio_producto_ubicacion_original;

ALTER TABLE app_dat_consignacion_envio_producto
ADD CONSTRAINT fk_envio_producto_ubicacion_original 
  FOREIGN KEY (id_ubicacion_original) 
  REFERENCES app_dat_layout_almacen(id)
  ON DELETE SET NULL;

-- FK para inventario original
ALTER TABLE app_dat_consignacion_envio_producto
DROP CONSTRAINT IF EXISTS fk_envio_producto_inventario_original;

ALTER TABLE app_dat_consignacion_envio_producto
ADD CONSTRAINT fk_envio_producto_inventario_original 
  FOREIGN KEY (id_inventario_original) 
  REFERENCES app_dat_inventario_productos(id)
  ON DELETE SET NULL;

-- ============================================================================
-- PASO 3: Crear índices para optimizar consultas
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_envio_producto_presentacion_original 
  ON app_dat_consignacion_envio_producto(id_presentacion_original);

CREATE INDEX IF NOT EXISTS idx_envio_producto_ubicacion_original 
  ON app_dat_consignacion_envio_producto(id_ubicacion_original);

CREATE INDEX IF NOT EXISTS idx_envio_producto_inventario_original 
  ON app_dat_consignacion_envio_producto(id_inventario_original);

-- ============================================================================
-- PASO 3.5: Verificación de devoluciones (SIN campo adicional)
-- ============================================================================
-- Propósito: Evitar que las recepciones de devolución actualicen el precio promedio
-- 
-- ✅ ENFOQUE EFICIENTE: Verificar directamente en app_dat_consignacion_envio
-- ❌ NO agregar campo es_devolucion_consignacion (redundante)
-- 
-- La tabla app_dat_consignacion_envio YA tiene:
-- - id_operacion_recepcion (FK con índice)
-- - tipo_envio (1 = envío, 2 = devolución)
-- 
-- Verificación en función de precio promedio:
-- SELECT EXISTS (
--   SELECT 1 FROM app_dat_consignacion_envio
--   WHERE id_operacion_recepcion = p_id_operacion
--     AND tipo_envio = 2
-- ) INTO v_es_devolucion;

-- ============================================================================
-- PASO 4: Modificar RPC crear_envio_consignacion
-- ============================================================================
-- NOTA: Este RPC ya existe, se debe modificar para incluir los campos originales
-- Buscar la sección donde se inserta en app_dat_consignacion_envio_producto
-- y agregar los campos: id_presentacion_original, id_variante_original, 
-- id_ubicacion_original, id_inventario_original
-- ============================================================================

-- ============================================================================
-- PASO 5: Crear RPC para crear devolución
-- ============================================================================

CREATE OR REPLACE FUNCTION crear_devolucion_consignacion(
  p_id_contrato BIGINT,
  p_id_almacen_origen BIGINT,
  p_id_usuario UUID,
  p_productos JSONB,
  p_descripcion TEXT DEFAULT NULL
) RETURNS TABLE (
  id_envio BIGINT,
  numero_envio VARCHAR,
  id_operacion_extraccion BIGINT
) AS $$
DECLARE
  v_id_envio BIGINT;
  v_numero_envio VARCHAR;
  v_id_operacion_extraccion BIGINT;
  v_producto JSONB;
  v_id_tienda_consignadora BIGINT;
  v_id_tienda_consignataria BIGINT;
  v_id_almacen_destino BIGINT;
  v_id_producto BIGINT;
  v_cantidad NUMERIC;
BEGIN
  -- 1. Obtener tiendas del contrato
  SELECT id_tienda_consignadora, id_tienda_consignataria
  INTO v_id_tienda_consignadora, v_id_tienda_consignataria
  FROM app_dat_contrato_consignacion
  WHERE id = p_id_contrato;

  IF v_id_tienda_consignadora IS NULL THEN
    RAISE EXCEPTION 'Contrato no encontrado: %', p_id_contrato;
  END IF;

  -- 2. Obtener almacén destino (primer almacén del consignador)
  SELECT id INTO v_id_almacen_destino
  FROM app_dat_almacen
  WHERE id_tienda = v_id_tienda_consignadora
  LIMIT 1;

  IF v_id_almacen_destino IS NULL THEN
    RAISE EXCEPTION 'No se encontró almacén para la tienda consignadora';
  END IF;

  -- 3. Generar número de envío
  v_numero_envio := 'DEV-' || p_id_contrato || '-' || 
                    TO_CHAR(NOW(), 'YYYYMMDD-HH24MISS');

  -- 4. Crear envío de devolución (tipo_envio = 2)
  INSERT INTO app_dat_consignacion_envio (
    id_contrato_consignacion,
    numero_envio,
    tipo_envio,
    estado_envio,
    id_almacen_origen,
    id_almacen_destino,
    descripcion,
    fecha_propuesta
  ) VALUES (
    p_id_contrato,
    v_numero_envio,
    2,  -- TIPO_ENVIO_DEVOLUCION
    1,  -- ESTADO_PROPUESTO
    p_id_almacen_origen,
    v_id_almacen_destino,
    COALESCE(p_descripcion, 'Devolución de productos en consignación'),
    NOW()
  ) RETURNING id INTO v_id_envio;

  -- 5. Crear operación de extracción (PENDIENTE) en tienda consignataria
  INSERT INTO app_dat_operaciones (
    id_tienda,
    id_tipo_operacion,
    observaciones
  ) VALUES (
    v_id_tienda_consignataria,
    7,  -- Tipo: Extracción de consignación
    'Extracción por devolución - ' || v_numero_envio
  ) RETURNING id INTO v_id_operacion_extraccion;

  -- Registrar estado inicial de la operación
  INSERT INTO app_dat_estado_operacion (id_operacion, estado, comentario)
  VALUES (v_id_operacion_extraccion, 1, 'Operación de extracción creada para devolución');

  -- 6. Insertar productos en el envío
  FOR v_producto IN SELECT * FROM jsonb_array_elements(p_productos)
  LOOP
    v_id_producto := (v_producto->>'id_producto')::BIGINT;
    v_cantidad := (v_producto->>'cantidad')::NUMERIC;

    -- CLAVE: Obtener información del producto ORIGINAL desde el envío inicial
    -- y copiarla a la devolución
    INSERT INTO app_dat_consignacion_envio_producto (
      id_envio,
      id_producto,
      id_inventario,
      cantidad_propuesta,
      precio_costo_usd,
      precio_costo_cup,
      tasa_cambio,
      id_presentacion_original,
      id_variante_original,
      id_ubicacion_original,
      id_inventario_original
    )
    SELECT
      v_id_envio,
      cep.id_producto,
      (v_producto->>'id_inventario')::BIGINT,
      v_cantidad,
      cep.precio_costo_usd,
      cep.precio_costo_cup,
      cep.tasa_cambio,
      -- ⭐ COPIAR datos originales del envío inicial
      cep.id_presentacion_original,
      cep.id_variante_original,
      cep.id_ubicacion_original,
      cep.id_inventario_original
    FROM app_dat_consignacion_envio_producto cep
    INNER JOIN app_dat_consignacion_envio ce ON ce.id = cep.id_envio
    WHERE ce.id_contrato_consignacion = p_id_contrato
      AND ce.tipo_envio = 1  -- Solo del envío original (no de otras devoluciones)
      AND cep.id_producto = v_id_producto
      AND cep.estado_producto = 3  -- Solo productos aceptados
    ORDER BY cep.created_at DESC
    LIMIT 1;

    -- Verificar que se insertó el producto
    IF NOT FOUND THEN
      RAISE EXCEPTION 'No se encontró información del producto % en el envío original', v_id_producto;
    END IF;
  END LOOP;

  -- 7. Registrar movimiento
  INSERT INTO app_dat_consignacion_envio_movimiento (
    id_envio,
    tipo_movimiento,
    id_usuario,
    descripcion
  ) VALUES (
    v_id_envio,
    1,  -- MOVIMIENTO_CREACION
    p_id_usuario,
    'Devolución creada por consignatario'
  );

  RETURN QUERY SELECT v_id_envio, v_numero_envio, v_id_operacion_extraccion;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION crear_devolucion_consignacion IS 
  'Crea una solicitud de devolución de productos en consignación, copiando los datos originales del envío inicial';

-- ============================================================================
-- PASO 6: Crear RPC para aprobar devolución
-- ============================================================================

CREATE OR REPLACE FUNCTION aprobar_devolucion_consignacion(
  p_id_envio BIGINT,
  p_id_almacen_recepcion BIGINT,
  p_id_usuario UUID
) RETURNS TABLE (
  success BOOLEAN,
  id_operacion_recepcion BIGINT,
  mensaje TEXT
) AS $$
DECLARE
  v_id_operacion_recepcion BIGINT;
  v_id_operacion_extraccion BIGINT;
  v_id_tienda_consignadora BIGINT;
  v_id_tienda_consignataria BIGINT;
  v_numero_envio VARCHAR;
  v_producto RECORD;
  v_id_zona_consignacion BIGINT;
BEGIN
  -- 1. Validar que el envío es de tipo devolución y está en estado PROPUESTO
  IF NOT EXISTS (
    SELECT 1 FROM app_dat_consignacion_envio
    WHERE id = p_id_envio 
      AND tipo_envio = 2 
      AND estado_envio = 1
  ) THEN
    RETURN QUERY SELECT FALSE, NULL::BIGINT, 
      'El envío no es una devolución válida o ya fue procesado'::TEXT;
    RETURN;
  END IF;

  -- 2. Obtener información del envío
  SELECT 
    ce.numero_envio, 
    cc.id_tienda_consignadora,
    cc.id_tienda_consignataria
  INTO v_numero_envio, v_id_tienda_consignadora, v_id_tienda_consignataria
  FROM app_dat_consignacion_envio ce
  INNER JOIN app_dat_contrato_consignacion cc ON cc.id = ce.id_contrato_consignacion
  WHERE ce.id = p_id_envio;

  -- 3. Crear operación de EXTRACCIÓN en tienda consignataria (completarla)
  -- Obtener la operación de extracción creada al solicitar la devolución
  SELECT id_operacion_extraccion INTO v_id_operacion_extraccion
  FROM app_dat_consignacion_envio
  WHERE id = p_id_envio;

  -- Completar la operación de extracción
  IF v_id_operacion_extraccion IS NOT NULL THEN
    -- Para cada producto, registrar la extracción
    FOR v_producto IN 
      SELECT 
        cep.id_producto,
        cep.cantidad_propuesta,
        cep.id_presentacion_original,
        cep.id_variante_original,
        cep.id_ubicacion_original,
        cep.precio_costo_usd
      FROM app_dat_consignacion_envio_producto cep
      WHERE cep.id_envio = p_id_envio
    LOOP
      -- Buscar la zona de consignación en la tienda consignataria
      SELECT id INTO v_id_zona_consignacion
      FROM app_dat_consignacion_zona
      WHERE id_tienda = v_id_tienda_consignataria
      LIMIT 1;

      -- Registrar extracción del producto
      INSERT INTO app_dat_extraccion_productos (
        id_operacion,
        id_producto,
        id_presentacion,
        id_variante,
        id_ubicacion,
        cantidad,
        precio_unitario
      ) VALUES (
        v_id_operacion_extraccion,
        v_producto.id_producto,
        v_producto.id_presentacion_original,
        v_producto.id_variante_original,
        COALESCE(v_id_zona_consignacion, v_producto.id_ubicacion_original),
        v_producto.cantidad_propuesta,
        v_producto.precio_costo_usd
      );

      -- Reducir inventario en la tienda consignataria
      UPDATE app_dat_inventario_productos
      SET cantidad_final = GREATEST(0, cantidad_final - v_producto.cantidad_propuesta)
      WHERE id_producto = v_producto.id_producto
        AND id_presentacion = v_producto.id_presentacion_original
        AND id_tienda = v_id_tienda_consignataria
        AND COALESCE(id_variante, 0) = COALESCE(v_producto.id_variante_original, 0);
    END LOOP;

    -- Completar operación de extracción
    UPDATE app_dat_estado_operacion
    SET estado = 2, comentario = 'Extracción completada para devolución'
    WHERE id_operacion = v_id_operacion_extraccion;
  END IF;

  -- 4. Crear operación de RECEPCIÓN en tienda consignadora
  -- ⭐ IMPORTANTE: La función de precio promedio verificará si es devolución
  --    consultando app_dat_consignacion_envio.tipo_envio = 2
  INSERT INTO app_dat_operaciones (
    id_tienda,
    id_tipo_operacion,
    observaciones
  ) VALUES (
    v_id_tienda_consignadora,
    1,  -- Tipo: Recepción
    'Recepción de devolución - ' || v_numero_envio
  ) RETURNING id INTO v_id_operacion_recepcion;

  -- 5. Para cada producto, restaurar al inventario ORIGINAL
  FOR v_producto IN 
    SELECT 
      cep.id_producto,
      cep.cantidad_propuesta,
      cep.id_presentacion_original,
      cep.id_variante_original,
      cep.id_ubicacion_original,
      cep.id_inventario_original,
      cep.precio_costo_usd
    FROM app_dat_consignacion_envio_producto cep
    WHERE cep.id_envio = p_id_envio
  LOOP
    -- ⭐ CLAVE: Restaurar al inventario ORIGINAL con presentación ORIGINAL
    INSERT INTO app_dat_recepcion_productos (
      id_operacion,
      id_producto,
      id_presentacion,
      id_variante,
      id_ubicacion,
      cantidad,
      precio_unitario
    ) VALUES (
      v_id_operacion_recepcion,
      v_producto.id_producto,
      v_producto.id_presentacion_original,  -- ⭐ USAR ORIGINAL
      v_producto.id_variante_original,      -- ⭐ USAR ORIGINAL
      v_producto.id_ubicacion_original,     -- ⭐ USAR ORIGINAL
      v_producto.cantidad_propuesta,
      v_producto.precio_costo_usd
    );

    -- Actualizar inventario en la ubicación ORIGINAL
    -- Si el registro existe, incrementar; si no, crear
    INSERT INTO app_dat_inventario_productos (
      id_producto,
      id_presentacion,
      id_variante,
      id_ubicacion,
      id_tienda,
      cantidad_final,
      created_at
    ) VALUES (
      v_producto.id_producto,
      v_producto.id_presentacion_original,
      v_producto.id_variante_original,
      v_producto.id_ubicacion_original,
      v_id_tienda_consignadora,
      v_producto.cantidad_propuesta,
      NOW()
    )
    ON CONFLICT (id_producto, id_presentacion, id_ubicacion, id_tienda, COALESCE(id_variante, 0))
    DO UPDATE SET 
      cantidad_final = app_dat_inventario_productos.cantidad_final + EXCLUDED.cantidad_final;
  END LOOP;

  -- 6. Actualizar estado del envío
  UPDATE app_dat_consignacion_envio
  SET 
    estado_envio = 4,  -- ESTADO_ACEPTADO
    fecha_aceptacion = NOW(),
    id_almacen_destino = p_id_almacen_recepcion
  WHERE id = p_id_envio;

  -- 7. Completar operación de recepción
  INSERT INTO app_dat_estado_operacion (id_operacion, estado, comentario)
  VALUES (v_id_operacion_recepcion, 2, 'Devolución recibida y productos restaurados');

  -- 8. Registrar movimiento
  INSERT INTO app_dat_consignacion_envio_movimiento (
    id_envio,
    tipo_movimiento,
    id_usuario,
    descripcion
  ) VALUES (
    p_id_envio,
    4,  -- MOVIMIENTO_ACEPTACION
    p_id_usuario,
    'Devolución aprobada y recibida por consignador'
  );

  RETURN QUERY SELECT TRUE, v_id_operacion_recepcion, 
    'Devolución aprobada exitosamente. Productos restaurados a ubicación original.'::TEXT;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION aprobar_devolucion_consignacion IS 
  'Aprueba una devolución, completa la extracción en consignatario y crea recepción en consignador restaurando productos a su ubicación original';

-- ============================================================================
-- PASO 7: Crear vista para consultar devoluciones con datos originales
-- ============================================================================

CREATE OR REPLACE VIEW v_devoluciones_consignacion AS
SELECT 
  ce.id AS id_envio,
  ce.numero_envio,
  ce.estado_envio,
  ce.fecha_propuesta,
  ce.fecha_aceptacion,
  cc.id AS id_contrato,
  tc.denominacion AS tienda_consignadora,
  td.denominacion AS tienda_consignataria,
  cep.id_producto,
  p.denominacion AS producto_denominacion,
  p.sku AS producto_sku,
  cep.cantidad_propuesta,
  cep.id_presentacion_original,
  pp_orig.denominacion AS presentacion_original,
  cep.id_ubicacion_original,
  la_orig.denominacion AS ubicacion_original,
  cep.precio_costo_usd,
  cep.precio_costo_cup
FROM app_dat_consignacion_envio ce
INNER JOIN app_dat_contrato_consignacion cc ON cc.id = ce.id_contrato_consignacion
INNER JOIN app_dat_tienda tc ON tc.id = cc.id_tienda_consignadora
INNER JOIN app_dat_tienda td ON td.id = cc.id_tienda_consignataria
INNER JOIN app_dat_consignacion_envio_producto cep ON cep.id_envio = ce.id
INNER JOIN app_dat_producto p ON p.id = cep.id_producto
LEFT JOIN app_dat_producto_presentacion pp ON pp.id = cep.id_presentacion_original
LEFT JOIN app_nom_presentacion pp_orig ON pp_orig.id = pp.id_presentacion
LEFT JOIN app_dat_layout_almacen la_orig ON la_orig.id = cep.id_ubicacion_original
WHERE ce.tipo_envio = 2;  -- Solo devoluciones

COMMENT ON VIEW v_devoluciones_consignacion IS 
  'Vista que muestra todas las devoluciones con información del producto original';

-- ============================================================================
-- PASO 8: Crear función helper para obtener datos originales de un producto
-- ============================================================================

CREATE OR REPLACE FUNCTION obtener_datos_originales_producto(
  p_id_contrato BIGINT,
  p_id_producto BIGINT
) RETURNS TABLE (
  id_presentacion_original BIGINT,
  id_variante_original BIGINT,
  id_ubicacion_original BIGINT,
  id_inventario_original BIGINT,
  precio_costo_usd NUMERIC,
  precio_costo_cup NUMERIC
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    cep.id_presentacion_original,
    cep.id_variante_original,
    cep.id_ubicacion_original,
    cep.id_inventario_original,
    cep.precio_costo_usd,
    cep.precio_costo_cup
  FROM app_dat_consignacion_envio_producto cep
  INNER JOIN app_dat_consignacion_envio ce ON ce.id = cep.id_envio
  WHERE ce.id_contrato_consignacion = p_id_contrato
    AND ce.tipo_envio = 1  -- Solo envío original
    AND cep.id_producto = p_id_producto
    AND cep.estado_producto = 3  -- Solo productos aceptados
  ORDER BY cep.created_at DESC
  LIMIT 1;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION obtener_datos_originales_producto IS 
  'Obtiene los datos originales de un producto desde el envío inicial para usar en devoluciones';

-- ============================================================================
-- FINALIZACIÓN
-- ============================================================================

-- Mensaje de confirmación
DO $$
BEGIN
  RAISE NOTICE '✅ Sistema de devoluciones implementado correctamente';
  RAISE NOTICE '📋 Columnas agregadas a app_dat_consignacion_envio_producto';
  RAISE NOTICE '🔗 Foreign keys y índices creados';
  RAISE NOTICE '⚙️ RPCs creados: crear_devolucion_consignacion, aprobar_devolucion_consignacion';
  RAISE NOTICE '👁️ Vista creada: v_devoluciones_consignacion';
  RAISE NOTICE '🔧 Función helper creada: obtener_datos_originales_producto';
  RAISE NOTICE '';
  RAISE NOTICE '⚠️ IMPORTANTE: Las recepciones de devolución NO actualizan precio promedio';
  RAISE NOTICE '✅ Verificación eficiente usando app_dat_consignacion_envio.tipo_envio';
  RAISE NOTICE '✅ Sin redundancia - usa FK e índice existente';
  RAISE NOTICE '';
  RAISE NOTICE '📝 PRÓXIMOS PASOS:';
  RAISE NOTICE '1. Modificar RPC crear_envio_consignacion para guardar datos originales';
  RAISE NOTICE '2. Modificar función/trigger de precio promedio para verificar tipo_envio = 2';
  RAISE NOTICE '3. Ver archivo ignorar_precio_promedio_devoluciones.sql para ejemplos';
  RAISE NOTICE '4. Modificar servicios Dart según PROPUESTA_DEVOLUCIONES_CONSIGNACION.md';
  RAISE NOTICE '5. Probar flujo completo de devolución';
  RAISE NOTICE '6. Verificar que precio promedio NO se actualiza en devoluciones';
END $$;
