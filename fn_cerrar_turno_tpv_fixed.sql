-- =====================================================
-- FUNCIÓN CORREGIDA: fn_cerrar_turno_tpv
-- =====================================================
-- Versión mejorada con mejor manejo de errores y logging

CREATE OR REPLACE FUNCTION fn_cerrar_turno_tpv(
  p_efectivo_real NUMERIC,
  p_id_tpv INTEGER,
  p_observaciones TEXT DEFAULT NULL,
  p_productos JSONB DEFAULT '[]'::jsonb,
  p_usuario UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
  v_id_turno bigint;
  v_id_operacion_apertura bigint;
  v_id_tienda bigint;
  v_id_operacion_cierre bigint;
  v_producto jsonb;
  v_turno_count integer;
BEGIN
  -- Debug: Log parámetros de entrada
  RAISE NOTICE 'Iniciando cierre de turno - TPV: %, Usuario: %, Efectivo: %', p_id_tpv, p_usuario, p_efectivo_real;

  -- Verificar si existe turno abierto (sin JOIN primero)
  SELECT COUNT(*) INTO v_turno_count
  FROM app_dat_caja_turno ct
  WHERE ct.id_tpv = p_id_tpv AND ct.estado = 1;
  
  RAISE NOTICE 'Turnos abiertos encontrados: %', v_turno_count;

  IF v_turno_count = 0 THEN
    RAISE EXCEPTION 'No se encontró un turno abierto para el TPV %', p_id_tpv;
  END IF;

  -- Obtener turno abierto con manejo de errores mejorado
  SELECT ct.id, ct.id_operacion_apertura
  INTO v_id_turno, v_id_operacion_apertura
  FROM app_dat_caja_turno ct
  WHERE ct.id_tpv = p_id_tpv AND ct.estado = 1
  LIMIT 1;

  RAISE NOTICE 'Turno encontrado - ID: %, Operación apertura: %', v_id_turno, v_id_operacion_apertura;

  -- Obtener id_tienda desde la operación de apertura
  IF v_id_operacion_apertura IS NOT NULL THEN
    SELECT op.id_tienda INTO v_id_tienda
    FROM app_dat_operaciones op
    WHERE op.id = v_id_operacion_apertura;
    
    RAISE NOTICE 'ID Tienda obtenido: %', v_id_tienda;
  ELSE
    -- Fallback: obtener tienda desde TPV
    SELECT tpv.id_tienda INTO v_id_tienda
    FROM app_dat_tpv tpv
    WHERE tpv.id = p_id_tpv;
    
    RAISE NOTICE 'ID Tienda desde TPV: %', v_id_tienda;
  END IF;

  IF v_id_tienda IS NULL THEN
    RAISE EXCEPTION 'No se pudo determinar la tienda para el TPV %', p_id_tpv;
  END IF;

  -- Crear operación de cierre
  INSERT INTO app_dat_operaciones (id_tipo_operacion, uuid, id_tienda, observaciones)
  VALUES (
    17, -- ID fijo para 'Cierre de Caja'
    p_usuario,
    v_id_tienda,
    COALESCE(p_observaciones, 'Cierre de turno con entrega de productos')
  )
  RETURNING id INTO v_id_operacion_cierre;

  RAISE NOTICE 'Operación de cierre creada - ID: %', v_id_operacion_cierre;

  -- Registrar productos entregados (solo si hay productos)
  IF jsonb_array_length(p_productos) > 0 THEN
    FOR v_producto IN SELECT * FROM jsonb_array_elements(p_productos)
    LOOP
      BEGIN
        INSERT INTO app_dat_control_productos (
          id_operacion,
          id_producto,
          id_variante,
          id_ubicacion,
          cantidad,
          sku_producto,
          sku_ubicacion
        )
        SELECT
          v_id_operacion_cierre,
          (v_producto->>'id_producto')::bigint,
          NULLIF((v_producto->>'id_variante')::text, 'null')::bigint,
          (v_producto->>'id_ubicacion')::bigint,
          (v_producto->>'cantidad')::numeric,
          p.sku,
          l.sku_codigo
        FROM app_dat_producto p
        JOIN app_dat_layout_almacen l ON l.id = (v_producto->>'id_ubicacion')::bigint
        WHERE p.id = (v_producto->>'id_producto')::bigint;
        
        RAISE NOTICE 'Producto registrado - ID: %', (v_producto->>'id_producto')::bigint;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE NOTICE 'Error registrando producto %: %', (v_producto->>'id_producto')::bigint, SQLERRM;
          -- Continuar con el siguiente producto
      END;
    END LOOP;
  ELSE
    RAISE NOTICE 'No hay productos para registrar';
  END IF;

  -- Registrar estado: Ejecutada
  INSERT INTO app_dat_estado_operacion (id_operacion, estado, uuid)
  VALUES (v_id_operacion_cierre, 2, p_usuario);

  RAISE NOTICE 'Estado de operación registrado';

  -- Calcular diferencia para logging
  DECLARE
    v_diferencia NUMERIC;
  BEGIN
    SELECT (p_efectivo_real - ct.efectivo_inicial) INTO v_diferencia
    FROM app_dat_caja_turno ct
    WHERE ct.id = v_id_turno;
    
    RAISE NOTICE 'Diferencia calculada: %', v_diferencia;
  END;

  -- ACTUALIZAR TURNO (paso crítico)
  UPDATE app_dat_caja_turno
  SET
    id_operacion_cierre = v_id_operacion_cierre,
    efectivo_real = p_efectivo_real,
    fecha_cierre = now(),
    estado = 2, -- Cerrado
    diferencia = p_efectivo_real - efectivo_inicial,
    observaciones = p_observaciones,
    cerrado_por = p_usuario,
    updated_at = now()
  WHERE id = v_id_turno;

  -- Verificar que el UPDATE fue exitoso
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Error: No se pudo actualizar el turno con ID %', v_id_turno;
  END IF;

  RAISE NOTICE 'Turno actualizado exitosamente - ID: %', v_id_turno;

  -- Verificación final
  DECLARE
    v_estado_final INTEGER;
  BEGIN
    SELECT estado INTO v_estado_final
    FROM app_dat_caja_turno
    WHERE id = v_id_turno;
    
    RAISE NOTICE 'Estado final del turno: %', v_estado_final;
    
    IF v_estado_final != 2 THEN
      RAISE EXCEPTION 'Error: El turno no se cerró correctamente. Estado actual: %', v_estado_final;
    END IF;
  END;

  RETURN true;

EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Error en fn_cerrar_turno_tpv: %', SQLERRM;
    RAISE;
END;
$$;

-- =====================================================
-- NOTAS IMPORTANTES:
-- =====================================================

/*
MEJORAS IMPLEMENTADAS:

1. LOGGING EXTENSIVO: Usa RAISE NOTICE para debug en cada paso
2. VALIDACIÓN MEJORADA: Verifica existencia de turno antes del JOIN
3. FALLBACK PARA TIENDA: Si no hay operación de apertura, usa TPV
4. MANEJO DE ERRORES: Try-catch en productos individuales
5. VERIFICACIÓN FINAL: Confirma que el UPDATE fue exitoso
6. CÁLCULO DE DIFERENCIA: Incluye diferencia en el UPDATE

PARA DEBUGGEAR:
1. Ejecutar la función y revisar los logs con RAISE NOTICE
2. Verificar que todos los pasos se ejecuten correctamente
3. Si falla, el error específico se mostrará

CAMPOS ACTUALIZADOS EN app_dat_caja_turno:
- id_operacion_cierre
- efectivo_real
- fecha_cierre
- estado (1 -> 2)
- diferencia (calculada)
- observaciones
- cerrado_por
- updated_at
*/
