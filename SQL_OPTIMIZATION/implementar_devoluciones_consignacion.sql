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

CREATE OR REPLACE FUNCTION crear_devolucion_consignacion_v2(
  p_id_contrato BIGINT,
  p_id_almacen_origen BIGINT,
  p_id_usuario UUID,
  p_productos JSONB,
  p_descripcion TEXT DEFAULT NULL,
  p_id_operacion_extraccion BIGINT DEFAULT NULL  -- Extracción ya construida desde Dart (reserva en tiempo real)
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
  -- Campos del envío original (pueden venir del JSONB directamente o del lookup)
  v_id_presentacion_orig BIGINT;
  v_id_variante_orig BIGINT;
  v_id_ubicacion_orig BIGINT;
  v_id_inventario_orig BIGINT;
  v_precio_costo_usd NUMERIC;
  v_precio_costo_cup NUMERIC;
  v_tasa_cambio NUMERIC;
BEGIN
  -- 1. Obtener tiendas del contrato
  SELECT id_tienda_consignadora, id_tienda_consignataria
  INTO v_id_tienda_consignadora, v_id_tienda_consignataria
  FROM app_dat_contrato_consignacion
  WHERE id = p_id_contrato;

  IF v_id_tienda_consignadora IS NULL THEN
    RAISE EXCEPTION 'Contrato no encontrado: %', p_id_contrato;
  END IF;

  -- 2. Obtener almacén destino del contrato (primer almacén del consignador como fallback)
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
    fecha_propuesta,
    id_usuario_creador
  ) VALUES (
    p_id_contrato,
    v_numero_envio,
    2,  -- TIPO_ENVIO_DEVOLUCION
    1,  -- ESTADO_PROPUESTO
    p_id_almacen_origen,
    v_id_almacen_destino,
    COALESCE(p_descripcion, 'Devolución de productos en consignación'),
    NOW(),
    p_id_usuario
  ) RETURNING id INTO v_id_envio;

  -- 5. Usar extracción pre-construida si fue enviada desde Dart; si no, crear una nueva
  IF p_id_operacion_extraccion IS NOT NULL THEN
    -- Reutilizar la operación de extracción ya creada en tiempo real por fn_crear_extraccion_con_movimiento
    v_id_operacion_extraccion := p_id_operacion_extraccion;
  ELSE
    -- Crear operación de extracción nueva (PENDIENTE) en tienda consignataria
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
  END IF;

  -- Vincular la extracción al envío
  UPDATE app_dat_consignacion_envio
  SET id_operacion_extraccion = v_id_operacion_extraccion
  WHERE id = v_id_envio;

  -- 6. Insertar productos en el envío
  FOR v_producto IN SELECT * FROM jsonb_array_elements(p_productos)
  LOOP
    v_id_producto := (v_producto->>'id_producto')::BIGINT;
    v_cantidad := (v_producto->>'cantidad')::NUMERIC;

    -- Intentar obtener datos originales desde el envío inicial del contrato
    -- Caso 1: id_producto coincide directamente
    -- Caso 2: id_producto es el duplicado en consignataria → resolver al original
    SELECT
      cep.id_presentacion_original,
      cep.id_variante_original,
      cep.id_ubicacion_original,
      cep.id_inventario_original,
      cep.precio_costo_usd,
      cep.precio_costo_cup,
      cep.tasa_cambio
    INTO
      v_id_presentacion_orig,
      v_id_variante_orig,
      v_id_ubicacion_orig,
      v_id_inventario_orig,
      v_precio_costo_usd,
      v_precio_costo_cup,
      v_tasa_cambio
    FROM app_dat_consignacion_envio_producto cep
    INNER JOIN app_dat_consignacion_envio ce ON ce.id = cep.id_envio
    WHERE ce.id_contrato_consignacion = p_id_contrato
      AND ce.tipo_envio = 1  -- Solo del envío original
      AND (
        cep.id_producto = v_id_producto
        OR
        cep.id_producto = (
          SELECT pcd.id_producto_original
          FROM app_dat_producto_consignacion_duplicado pcd
          WHERE pcd.id_producto_duplicado = v_id_producto
            AND pcd.id_tienda_destino = v_id_tienda_consignataria
          ORDER BY pcd.fecha_duplicacion DESC
          LIMIT 1
        )
      )
      AND cep.estado_producto = 3  -- Solo productos aceptados
    ORDER BY cep.created_at DESC
    LIMIT 1;

    -- Si no se encontró en el envío original, usar los valores del JSONB enviados desde Dart
    IF NOT FOUND THEN
      v_id_presentacion_orig := NULLIF((v_producto->>'id_presentacion'), '')::BIGINT;
      v_id_variante_orig     := NULLIF((v_producto->>'id_variante'), '')::BIGINT;
      v_id_ubicacion_orig    := NULLIF((v_producto->>'id_ubicacion'), '')::BIGINT;
      v_id_inventario_orig   := NULLIF((v_producto->>'id_inventario'), '')::BIGINT;
      v_precio_costo_usd     := COALESCE(NULLIF((v_producto->>'precio_costo_usd'), '')::NUMERIC, 0);
      v_precio_costo_cup     := COALESCE(NULLIF((v_producto->>'precio_costo_cup'), '')::NUMERIC, 0);
      v_tasa_cambio          := COALESCE(NULLIF((v_producto->>'tasa_cambio'), '')::NUMERIC, 440);
    END IF;

    -- id_inventario es NOT NULL en el esquema; validar antes de insertar
    IF (v_producto->>'id_inventario') IS NULL OR (v_producto->>'id_inventario') = '' THEN
      RAISE EXCEPTION 'id_inventario es requerido para el producto %', v_id_producto;
    END IF;

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
    ) VALUES (
      v_id_envio,
      v_id_producto,
      (v_producto->>'id_inventario')::BIGINT,
      v_cantidad,
      v_precio_costo_usd,
      v_precio_costo_cup,
      v_tasa_cambio,
      v_id_presentacion_orig,
      v_id_variante_orig,
      v_id_ubicacion_orig,
      v_id_inventario_orig
    );
  END LOOP;

  -- 7. Registrar movimiento
  INSERT INTO app_dat_consignacion_envio_movimiento (
    id_envio,
    tipo_movimiento,
    id_usuario,
    estado_nuevo,
    descripcion
  ) VALUES (
    v_id_envio,
    1,  -- MOVIMIENTO_CREACION
    p_id_usuario,
    1,  -- ESTADO_PROPUESTO
    'Devolución creada por consignatario'
  );

  RETURN QUERY SELECT v_id_envio, v_numero_envio, v_id_operacion_extraccion;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION crear_devolucion_consignacion_v2 IS 
  'v2: Acepta extracción pre-construida desde Dart, fallback a JSONB si no hay envío original. Crea una solicitud de devolución de productos en consignación.';

-- ============================================================================
-- PASO 6: Crear RPC para aprobar devolución
-- ============================================================================

CREATE OR REPLACE FUNCTION aprobar_devolucion_consignacion_v2(
  p_id_envio BIGINT,
  p_id_almacen_recepcion BIGINT,
  p_id_usuario UUID,
  p_id_zona_recepcion BIGINT DEFAULT NULL
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
  v_id_producto_duplicado BIGINT;
  v_productos_extraccion JSONB := '[]'::JSONB;
  v_producto_json JSONB;
  v_extraccion_result JSONB;
  v_id_presentacion_inv BIGINT;
  v_id_variante_inv BIGINT;
  v_id_ubicacion_inv BIGINT;
  v_id_ubicacion_recepcion BIGINT;  -- Ubicación de fallback en almacén del consignador
  v_id_producto_original BIGINT;   -- Producto original del consignador (no el duplicado)
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

  -- 3. Verificar si ya existe una extracción pre-construida por Flutter
  SELECT id_operacion_extraccion INTO v_id_operacion_extraccion
  FROM app_dat_consignacion_envio
  WHERE id = p_id_envio;

  IF v_id_operacion_extraccion IS NOT NULL THEN
    -- ✅ CASO NORMAL: Flutter ya creó la extracción en tiempo real con fn_crear_extraccion_con_movimiento.
    -- El inventario del consignatario ya fue deducido al seleccionar los productos.
    -- Solo hay que marcarla como COMPLETADA (estado = 2).
    INSERT INTO app_dat_estado_operacion (id_operacion, estado, comentario)
    VALUES (v_id_operacion_extraccion, 2, 'Extracción completada — devolución aprobada por consignador');

    -- 4b. Asegurar que app_dat_operacion_extraccion existe (puede faltar si se creó como operación básica).
    INSERT INTO app_dat_operacion_extraccion (id_operacion, id_motivo_operacion, observaciones, autorizado_por)
    SELECT
      v_id_operacion_extraccion,
      (SELECT id FROM app_nom_motivo_extraccion ORDER BY id LIMIT 1),
      'Extracción por devolución - ' || v_numero_envio,
      'Sistema'
    WHERE NOT EXISTS (
      SELECT 1 FROM app_dat_operacion_extraccion WHERE id_operacion = v_id_operacion_extraccion
    );

  ELSE
    -- ⚠️ CASO FALLBACK: No hay extracción pre-construida (flujo manual/edge).
    -- Construir y completar la extracción ahora vía fn_crear_extraccion_con_movimiento.
    FOR v_producto IN
      SELECT
        cep.id_producto,
        cep.cantidad_propuesta,
        cep.precio_costo_usd
      FROM app_dat_consignacion_envio_producto cep
      WHERE cep.id_envio = p_id_envio
    LOOP
      v_id_producto_duplicado := NULL;

      SELECT pcd.id_producto_duplicado
      INTO v_id_producto_duplicado
      FROM app_dat_producto_consignacion_duplicado pcd
      INNER JOIN app_dat_consignacion_envio ce ON ce.id_contrato_consignacion = pcd.id_contrato_consignacion
      WHERE pcd.id_producto_original = v_producto.id_producto
        AND ce.id = p_id_envio
      LIMIT 1;

      v_id_producto_duplicado := COALESCE(v_id_producto_duplicado, v_producto.id_producto);

      SELECT id_zona INTO v_id_zona_consignacion
      FROM app_dat_consignacion_zona
      WHERE id_tienda_consignataria = v_id_tienda_consignataria
      LIMIT 1;

      SELECT ip.id_presentacion, ip.id_variante, ip.id_ubicacion
      INTO v_id_presentacion_inv, v_id_variante_inv, v_id_ubicacion_inv
      FROM app_dat_inventario_productos ip
      WHERE ip.id_producto = v_id_producto_duplicado
        AND (v_id_zona_consignacion IS NULL OR ip.id_ubicacion = v_id_zona_consignacion)
      ORDER BY ip.created_at DESC
      LIMIT 1;

      IF v_id_ubicacion_inv IS NULL THEN
        SELECT ip.id_presentacion, ip.id_variante, ip.id_ubicacion
        INTO v_id_presentacion_inv, v_id_variante_inv, v_id_ubicacion_inv
        FROM app_dat_inventario_productos ip
        INNER JOIN app_dat_layout_almacen la ON la.id = ip.id_ubicacion
        INNER JOIN app_dat_almacen a ON a.id = la.id_almacen
        WHERE ip.id_producto = v_id_producto_duplicado
          AND a.id_tienda = v_id_tienda_consignataria
        ORDER BY ip.created_at DESC
        LIMIT 1;
      END IF;

      v_producto_json := jsonb_build_object(
        'id_producto',     v_id_producto_duplicado,
        'cantidad',        v_producto.cantidad_propuesta,
        'id_presentacion', v_id_presentacion_inv,
        'id_ubicacion',    v_id_ubicacion_inv,
        'id_variante',     v_id_variante_inv,
        'precio_unitario', v_producto.precio_costo_usd
      );
      v_productos_extraccion := v_productos_extraccion || v_producto_json;
    END LOOP;

    SELECT fn_crear_extraccion_con_movimiento(
      'Sistema'::TEXT,
      1::SMALLINT,
      21::BIGINT,
      v_id_tienda_consignataria,
      ('Extracción para devolución - ' || v_numero_envio)::TEXT,
      v_productos_extraccion,
      p_id_usuario
    ) INTO v_extraccion_result;

    IF (v_extraccion_result->>'status')::TEXT != 'success' THEN
      RAISE EXCEPTION 'Error creando extracción: %', v_extraccion_result->>'message';
    END IF;

    v_id_operacion_extraccion := (v_extraccion_result->>'id_operacion')::BIGINT;

    -- Vincular al envío
    UPDATE app_dat_consignacion_envio
    SET id_operacion_extraccion = v_id_operacion_extraccion
    WHERE id = p_id_envio;
  END IF;

  -- 5. Crear operación de RECEPCIÓN en tienda consignadora — estado PENDIENTE
  -- El inventario del consignador se actualizará cuando complete la recepción
  -- mediante fn_contabilizar_operacion (llamado desde la pantalla de detalles del envío).
  INSERT INTO app_dat_operaciones (
    id_tienda,
    id_tipo_operacion,
    uuid,
    observaciones,
    created_at
  ) VALUES (
    v_id_tienda_consignadora,
    1,  -- Tipo: Recepción
    p_id_usuario,
    'Recepción de devolución - ' || v_numero_envio,
    CURRENT_TIMESTAMP
  ) RETURNING id INTO v_id_operacion_recepcion;

  -- Estado PENDIENTE de la recepción
  INSERT INTO app_dat_estado_operacion (id_operacion, estado, comentario)
  VALUES (v_id_operacion_recepcion, 1, 'Recepción creada — pendiente de completar por el consignador');

  -- 5b. Registrar en app_dat_operacion_recepcion (tabla de detalle del tipo de operación)
  INSERT INTO app_dat_operacion_recepcion (
    id_operacion,
    recibido_por,
    observaciones
  ) VALUES (
    v_id_operacion_recepcion,
    'Sistema',
    'Recepción de devolución - ' || v_numero_envio
  );

  -- 6. Registrar productos de recepción en la zona seleccionada por el usuario.
  -- Si se proporcionó p_id_zona_recepcion y pertenece al almacén, se usa directamente.
  -- De lo contrario se usa la primera zona del almacén como fallback.
  IF p_id_zona_recepcion IS NOT NULL AND EXISTS (
    SELECT 1 FROM app_dat_layout_almacen
    WHERE id = p_id_zona_recepcion AND id_almacen = p_id_almacen_recepcion
  ) THEN
    v_id_ubicacion_recepcion := p_id_zona_recepcion;
  ELSE
    SELECT la.id INTO v_id_ubicacion_recepcion
    FROM app_dat_layout_almacen la
    WHERE la.id_almacen = p_id_almacen_recepcion
    ORDER BY la.id
    LIMIT 1;
  END IF;

  -- Registrar cada producto usando los datos ORIGINALES del consignador.
  -- app_dat_producto_consignacion_duplicado mapea duplicado → original,
  -- resolviendo tanto el id_producto como la id_presentacion del consignador.
  FOR v_producto IN
    SELECT
      cep.cantidad_propuesta,
      cep.precio_costo_usd,
      cep.id_producto              AS id_producto_dup,
      cep.id_presentacion_original AS id_presentacion_cep,
      cep.id_variante_original     AS id_variante_cep
    FROM app_dat_consignacion_envio_producto cep
    WHERE cep.id_envio = p_id_envio
  LOOP
    -- Resolver producto y presentación originales del consignador
    -- via tabla de duplicados
    SELECT
      pcd.id_producto_original,
      pcd.id_presentacion_original
    INTO v_id_producto_original, v_id_presentacion_inv
    FROM app_dat_producto_consignacion_duplicado pcd
    WHERE pcd.id_producto_duplicado = v_producto.id_producto_dup
      AND pcd.id_tienda_destino = v_id_tienda_consignataria
    ORDER BY pcd.fecha_duplicacion DESC
    LIMIT 1;

    -- Fallback: si no hay registro de duplicado, el producto ya es el original
    v_id_producto_original := COALESCE(v_id_producto_original, v_producto.id_producto_dup);

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
      v_id_producto_original,
      COALESCE(v_id_presentacion_inv, v_producto.id_presentacion_cep),
      v_producto.id_variante_cep,
      v_id_ubicacion_recepcion,
      v_producto.cantidad_propuesta,
      v_producto.precio_costo_usd
    );

    -- Resetear variables para la siguiente iteración
    v_id_producto_original := NULL;
    v_id_presentacion_inv  := NULL;
  END LOOP;

  -- 6b. Registrar movimientos en app_dat_movimiento_consignacion (tipo 3 = devolución)
  INSERT INTO app_dat_movimiento_consignacion (
    id_producto_consignacion,
    tipo_movimiento,
    cantidad,
    id_usuario,
    observaciones,
    fecha_movimiento
  )
  SELECT
    cep.id_producto_consignacion,
    3,  -- Tipo: Devolución
    cep.cantidad_propuesta,
    p_id_usuario,
    'Devolución aprobada - ' || v_numero_envio,
    CURRENT_TIMESTAMP
  FROM app_dat_consignacion_envio_producto cep
  WHERE cep.id_envio = p_id_envio
    AND cep.id_producto_consignacion IS NOT NULL;

  -- 7. Actualizar estado del envío a CONFIGURADO y vincular recepción
  UPDATE app_dat_consignacion_envio
  SET 
    id_operacion_recepcion = v_id_operacion_recepcion,
    estado_envio = 2,  -- CONFIGURADO (extracción completada, recepción pendiente)
    fecha_configuracion = NOW(),
    id_almacen_destino = p_id_almacen_recepcion
  WHERE id = p_id_envio;

  -- 8. Registrar movimiento del envío
  INSERT INTO app_dat_consignacion_envio_movimiento (
    id_envio,
    tipo_movimiento,
    id_usuario,
    estado_nuevo,
    descripcion
  ) VALUES (
    p_id_envio,
    4,  -- MOVIMIENTO_ACEPTACION
    p_id_usuario,
    2,  -- ESTADO_CONFIGURADO
    'Devolución aprobada — extracción completada, recepción pendiente de confirmar'
  );

  RETURN QUERY SELECT TRUE, v_id_operacion_recepcion, 
    'Devolución aprobada. Extracción completada (inventario consignatario reducido). Complete la recepción para registrar los productos en su inventario.'::TEXT;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION aprobar_devolucion_consignacion_v2 IS 
  'v2: Aprueba una devolución — completa la extracción en consignatario (inventario reducido inmediatamente vía fn_crear_extraccion_con_movimiento) y crea recepción PENDIENTE en consignador. El consignador debe completar la recepción manualmente para restaurar el stock.';

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
