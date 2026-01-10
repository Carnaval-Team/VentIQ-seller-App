-- ============================================================================
-- MODIFICACIÓN: Ignorar actualización de precio promedio en devoluciones
-- ============================================================================
-- Fecha: 7 de Enero, 2026
-- Propósito: Evitar que las recepciones de devolución actualicen el precio promedio
-- ============================================================================

-- ============================================================================
-- OPCIÓN 1: Modificar función existente de actualización de precio promedio
-- ============================================================================
-- NOTA: Si existe una función que actualiza el precio promedio después de recepciones,
-- debe modificarse para detectar si es una devolución y omitir la actualización

-- Ejemplo de modificación (ajustar según la función real):
/*
CREATE OR REPLACE FUNCTION fn_actualizar_precio_promedio_recepcion_v2(
  p_id_operacion BIGINT
) RETURNS VOID AS $$
DECLARE
  v_es_devolucion BOOLEAN;
BEGIN
  -- ⭐ NUEVO: Verificar si la operación es una devolución de consignación
  SELECT EXISTS (
    SELECT 1 
    FROM app_dat_consignacion_envio ce
    WHERE ce.id_operacion_recepcion = p_id_operacion
      AND ce.tipo_envio = 2  -- Tipo devolución
  ) INTO v_es_devolucion;

  -- ⭐ Si es devolución, NO actualizar precio promedio
  IF v_es_devolucion THEN
    RAISE NOTICE 'Operación % es una devolución - precio promedio NO se actualiza', p_id_operacion;
    RETURN;
  END IF;

  -- Continuar con la lógica normal de actualización de precio promedio
  -- ... (código existente)
END;
$$ LANGUAGE plpgsql;
*/

-- ============================================================================
-- OPCIÓN 2: Crear trigger que detecte devoluciones
-- ============================================================================

-- Función para verificar si una operación es de devolución
CREATE OR REPLACE FUNCTION es_operacion_devolucion_consignacion(
  p_id_operacion BIGINT
) RETURNS BOOLEAN AS $$
DECLARE
  v_es_devolucion BOOLEAN;
BEGIN
  -- Verificar si la operación está relacionada con un envío de devolución
  SELECT EXISTS (
    SELECT 1 
    FROM app_dat_consignacion_envio ce
    INNER JOIN app_dat_operaciones op ON op.id = p_id_operacion
    WHERE (ce.id_operacion_recepcion = p_id_operacion 
           OR ce.id_operacion_extraccion = p_id_operacion)
      AND ce.tipo_envio = 2  -- Tipo devolución
  ) INTO v_es_devolucion;

  RETURN v_es_devolucion;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION es_operacion_devolucion_consignacion IS 
  'Verifica si una operación está relacionada con una devolución de consignación';

-- ============================================================================
-- OPCIÓN 3: Agregar campo a tabla de operaciones (NO RECOMENDADO - REDUNDANTE)
-- ============================================================================
-- ❌ Este enfoque agrega redundancia ya que la información existe en app_dat_consignacion_envio
-- ✅ MEJOR: Usar OPCIÓN 2 (verificar en app_dat_consignacion_envio)

-- Agregar campo booleano para marcar devoluciones
-- ALTER TABLE app_dat_operaciones
-- ADD COLUMN IF NOT EXISTS es_devolucion_consignacion BOOLEAN DEFAULT FALSE;

-- Crear índice para mejorar performance
-- CREATE INDEX IF NOT EXISTS idx_operaciones_es_devolucion 
--   ON app_dat_operaciones(es_devolucion_consignacion) 
--   WHERE es_devolucion_consignacion = TRUE;

-- COMMENT ON COLUMN app_dat_operaciones.es_devolucion_consignacion IS 
--   'Indica si la operación es una devolución de consignación (NO actualiza precio promedio)';

-- ============================================================================
-- OPCIÓN 4: Modificar RPC aprobar_devolucion_consignacion
-- ============================================================================
-- Agregar marca en la operación al crearla

-- Reemplazar la sección de creación de operación de recepción:
/*
-- 3. Crear operación de recepción en tienda consignadora
INSERT INTO app_dat_operaciones (
  id_tienda,
  id_tipo_operacion,
  observaciones,
  es_devolucion_consignacion  -- ⭐ AGREGAR ESTE CAMPO
) VALUES (
  v_id_tienda_consignadora,
  1,  -- Tipo: Recepción
  'Recepción de devolución - ' || v_numero_envio,
  TRUE  -- ⭐ MARCAR COMO DEVOLUCIÓN
) RETURNING id INTO v_id_operacion_recepcion;
*/

-- ============================================================================
-- OPCIÓN 5: Modificar trigger/función que actualiza precio promedio
-- ============================================================================

-- Si existe un trigger AFTER INSERT en app_dat_recepcion_productos,
-- modificarlo para verificar si es devolución:

/*
CREATE OR REPLACE FUNCTION trg_actualizar_precio_promedio_recepcion()
RETURNS TRIGGER AS $$
DECLARE
  v_es_devolucion BOOLEAN;
BEGIN
  -- ⭐ Verificar si la operación es una devolución
  SELECT COALESCE(es_devolucion_consignacion, FALSE)
  INTO v_es_devolucion
  FROM app_dat_operaciones
  WHERE id = NEW.id_operacion;

  -- ⭐ Si es devolución, NO actualizar precio promedio
  IF v_es_devolucion THEN
    RAISE NOTICE 'Recepción de devolución detectada - precio promedio NO se actualiza';
    RETURN NEW;
  END IF;

  -- Continuar con actualización normal de precio promedio
  -- ... (código existente)
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
*/

-- ============================================================================
-- RECOMENDACIÓN: Usar OPCIÓN 2 (Verificar en app_dat_consignacion_envio)
-- ============================================================================
-- Es la solución más eficiente y sin redundancia:
-- 1. NO agregar campo nuevo a app_dat_operaciones
-- 2. Verificar directamente en app_dat_consignacion_envio usando FK existente
-- 3. Aprovechar índice ya existente en id_operacion_recepcion
-- 4. Fuente única de verdad (tipo_envio = 2)

-- ============================================================================
-- SCRIPT COMPLETO RECOMENDADO (SIN REDUNDANCIA)
-- ============================================================================

-- ✅ NO agregar campo a app_dat_operaciones (evitar redundancia)
-- ✅ Usar función es_operacion_devolucion_consignacion() ya creada arriba
-- ✅ Aprovechar FK e índice existente en app_dat_consignacion_envio

-- Modificar función de actualización de precio promedio
-- Ejemplo genérico (ajustar según implementación real):

CREATE OR REPLACE FUNCTION actualizar_precio_promedio_con_validacion_devolucion(
  p_id_operacion BIGINT,
  p_id_producto BIGINT,
  p_id_presentacion BIGINT,
  p_precio_unitario NUMERIC,
  p_cantidad NUMERIC
) RETURNS VOID AS $$
DECLARE
  v_es_devolucion BOOLEAN;
  v_cantidad_actual NUMERIC;
  v_precio_promedio_actual NUMERIC;
  v_nuevo_precio_promedio NUMERIC;
BEGIN
  -- ⭐ Verificar si es devolución (SIN campo adicional, usando FK existente)
  SELECT EXISTS (
    SELECT 1 
    FROM app_dat_consignacion_envio
    WHERE id_operacion_recepcion = p_id_operacion
      AND tipo_envio = 2  -- Devolución
  ) INTO v_es_devolucion;

  -- ⭐ Si es devolución, NO actualizar precio promedio
  IF v_es_devolucion THEN
    RAISE NOTICE 'Operación % es devolución - precio promedio NO se actualiza', p_id_operacion;
    RETURN;
  END IF;

  -- Obtener precio promedio actual y cantidad
  SELECT 
    COALESCE(precio_promedio, 0),
    COALESCE(
      (SELECT SUM(cantidad_final) 
       FROM app_dat_inventario_productos 
       WHERE id_producto = p_id_producto 
         AND id_presentacion = p_id_presentacion), 
      0
    )
  INTO v_precio_promedio_actual, v_cantidad_actual
  FROM app_dat_producto_presentacion
  WHERE id_producto = p_id_producto
    AND id_presentacion = p_id_presentacion;

  -- Calcular nuevo precio promedio ponderado
  IF v_cantidad_actual > 0 THEN
    v_nuevo_precio_promedio := 
      ((v_precio_promedio_actual * v_cantidad_actual) + (p_precio_unitario * p_cantidad)) 
      / (v_cantidad_actual + p_cantidad);
  ELSE
    v_nuevo_precio_promedio := p_precio_unitario;
  END IF;

  -- Actualizar precio promedio
  UPDATE app_dat_producto_presentacion
  SET precio_promedio = v_nuevo_precio_promedio
  WHERE id_producto = p_id_producto
    AND id_presentacion = p_id_presentacion;

  RAISE NOTICE 'Precio promedio actualizado: % -> %', v_precio_promedio_actual, v_nuevo_precio_promedio;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION actualizar_precio_promedio_con_validacion_devolucion IS 
  'Actualiza el precio promedio de una presentación, ignorando devoluciones de consignación';

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================

-- Consulta para verificar operaciones de devolución
CREATE OR REPLACE VIEW v_operaciones_devolucion_consignacion AS
SELECT 
  op.id AS id_operacion,
  op.id_tienda,
  op.id_tipo_operacion,
  op.observaciones,
  op.es_devolucion_consignacion,
  ce.numero_envio,
  ce.tipo_envio,
  ce.estado_envio,
  t.denominacion AS tienda
FROM app_dat_operaciones op
LEFT JOIN app_dat_consignacion_envio ce ON (
  ce.id_operacion_recepcion = op.id 
  OR ce.id_operacion_extraccion = op.id
)
LEFT JOIN app_dat_tienda t ON t.id = op.id_tienda
WHERE op.es_devolucion_consignacion = TRUE
   OR ce.tipo_envio = 2;

COMMENT ON VIEW v_operaciones_devolucion_consignacion IS 
  'Vista de todas las operaciones relacionadas con devoluciones de consignación';

-- ============================================================================
-- FINALIZACIÓN
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Modificaciones para ignorar precio promedio en devoluciones implementadas';
  RAISE NOTICE '� Función helper creada: es_operacion_devolucion_consignacion()';
  RAISE NOTICE '⚙️ Función ejemplo creada: actualizar_precio_promedio_con_validacion_devolucion()';
  RAISE NOTICE '👁️ Vista creada: v_operaciones_devolucion_consignacion';
  RAISE NOTICE '';
  RAISE NOTICE '✅ VENTAJAS DEL ENFOQUE:';
  RAISE NOTICE '  - Sin redundancia de datos';
  RAISE NOTICE '  - Sin ALTER TABLE necesario';
  RAISE NOTICE '  - Usa FK e índice existente';
  RAISE NOTICE '  - Fuente única de verdad (tipo_envio)';
  RAISE NOTICE '';
  RAISE NOTICE '📝 PRÓXIMOS PASOS:';
  RAISE NOTICE '1. Modificar función/trigger existente de precio promedio para verificar devolución';
  RAISE NOTICE '2. Usar es_operacion_devolucion_consignacion() o query directa';
  RAISE NOTICE '3. Probar que devoluciones NO actualizan precio promedio';
  RAISE NOTICE '4. Probar que recepciones normales SÍ actualizan precio promedio';
END $$;
