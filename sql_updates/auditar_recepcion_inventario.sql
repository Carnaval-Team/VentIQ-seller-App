-- ============================================================================
-- AUDITORÍA: Recepción vs movimientos de inventario
-- ============================================================================
-- Compara cada línea de app_dat_recepcion_productos contra su movimiento en
-- app_dat_inventario_productos (id_recepcion = línea.id).
--
-- Resultados posibles:
--   OK                        → movimiento existe y cantidad coincide
--   SIN_MOVIMIENTO_INVENTARIO → operación completada pero sin kardex
--   CANTIDAD_NO_COINCIDE      → delta inventario != cantidad recepción
--   MOVIMIENTO_DUPLICADO      → más de un movimiento para la misma línea
--   OPERACION_NO_COMPLETADA   → estado distinto de 2 (Completada)
--
-- Causas probables (causa_codigo):
--   REGISTRO_PARCIAL_INTERRUMPIDO → solo parte de las líneas contabilizadas
--   PRODUCTO_SIN_PRESENTACION     → producto sin presentaciones en catálogo
--   PRESENTACION_NO_ASIGNADA      → línea sin presentación asignada
--   UBICACION_NULA / PRODUCTO_NULO / DELTA_INCORRECTO / etc.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Detalle por línea (cambiar IDs según necesidad)
-- ---------------------------------------------------------------------------
WITH ops AS (
  SELECT unnest(ARRAY[156095, 156098])::bigint AS id_operacion
),
estado_actual AS (
  SELECT DISTINCT ON (eo.id_operacion)
    eo.id_operacion,
    eo.estado,
    neo.denominacion AS estado_nombre,
    eo.created_at AS fecha_estado
  FROM app_dat_estado_operacion eo
  JOIN app_nom_estado_operacion neo ON neo.id = eo.estado
  WHERE eo.id_operacion IN (SELECT id_operacion FROM ops)
  ORDER BY eo.id_operacion, eo.id DESC
),
lineas AS (
  SELECT
    rp.id                AS id_recepcion_producto,
    rp.id_operacion,
    rp.id_producto,
    p.denominacion       AS producto_nombre,
    rp.id_ubicacion,
    rp.id_presentacion,
    rp.cantidad::numeric AS cantidad_recepcion,
    la.denominacion      AS ubicacion,
    a.denominacion       AS almacen
  FROM app_dat_recepcion_productos rp
  JOIN ops o ON o.id_operacion = rp.id_operacion
  LEFT JOIN app_dat_producto p ON p.id = rp.id_producto
  LEFT JOIN app_dat_layout_almacen la ON la.id = rp.id_ubicacion
  LEFT JOIN app_dat_almacen a ON a.id = la.id_almacen
),
movimientos AS (
  SELECT
    inv.id_recepcion,
    COUNT(*)::int AS num_movimientos,
    MIN(inv.id)   AS id_movimiento,
    MIN(inv.cantidad_inicial::numeric) AS cantidad_inicial,
    MAX(inv.cantidad_final::numeric)   AS cantidad_final,
    SUM((inv.cantidad_final - inv.cantidad_inicial)::numeric) AS delta_total
  FROM app_dat_inventario_productos inv
  WHERE inv.id_recepcion IN (SELECT id_recepcion_producto FROM lineas)
  GROUP BY inv.id_recepcion
),
op_stats AS (
  SELECT
    rp.id_operacion,
    COUNT(*)::int AS total_lineas,
    COUNT(inv.id)::int AS lineas_con_movimiento,
    MAX(rp.id) FILTER (WHERE inv.id IS NOT NULL) AS ultimo_id_con_movimiento
  FROM app_dat_recepcion_productos rp
  JOIN ops o ON o.id_operacion = rp.id_operacion
  LEFT JOIN app_dat_inventario_productos inv ON inv.id_recepcion = rp.id
  GROUP BY rp.id_operacion
),
presentacion_stats AS (
  SELECT
    rp.id AS id_recepcion_producto,
    COUNT(pp.id)::int AS num_presentaciones,
    COALESCE(BOOL_OR(pp.es_base), false) AS tiene_presentacion_base
  FROM app_dat_recepcion_productos rp
  JOIN ops o ON o.id_operacion = rp.id_operacion
  LEFT JOIN app_dat_producto_presentacion pp ON pp.id_producto = rp.id_producto
  GROUP BY rp.id
),
audit_base AS (
  SELECT
    l.id_operacion,
    ea.estado,
    ea.estado_nombre,
    ea.fecha_estado,
    l.id_recepcion_producto,
    l.id_producto,
    l.producto_nombre,
    l.almacen,
    l.ubicacion,
    l.id_presentacion,
    l.id_ubicacion,
    l.cantidad_recepcion,
    COALESCE(m.num_movimientos, 0) AS num_movimientos,
    m.id_movimiento,
    m.cantidad_inicial,
    m.cantidad_final,
    m.delta_total AS delta_inventario,
    os.total_lineas,
    os.lineas_con_movimiento,
    os.ultimo_id_con_movimiento,
    ps.num_presentaciones,
    ps.tiene_presentacion_base,
    CASE
      WHEN ea.estado <> 2 THEN 'OPERACION_NO_COMPLETADA'
      WHEN COALESCE(m.num_movimientos, 0) = 0 THEN 'SIN_MOVIMIENTO_INVENTARIO'
      WHEN m.num_movimientos > 1 THEN 'MOVIMIENTO_DUPLICADO'
      WHEN ABS(COALESCE(m.delta_total, 0) - l.cantidad_recepcion) > 0.0001
        THEN 'CANTIDAD_NO_COINCIDE'
      ELSE 'OK'
    END AS resultado_auditoria
  FROM lineas l
  JOIN estado_actual ea ON ea.id_operacion = l.id_operacion
  JOIN op_stats os ON os.id_operacion = l.id_operacion
  LEFT JOIN movimientos m ON m.id_recepcion = l.id_recepcion_producto
  LEFT JOIN presentacion_stats ps ON ps.id_recepcion_producto = l.id_recepcion_producto
)
SELECT
  id_operacion,
  estado,
  estado_nombre,
  fecha_estado,
  id_recepcion_producto,
  id_producto,
  producto_nombre,
  almacen,
  ubicacion,
  id_presentacion,
  cantidad_recepcion,
  num_movimientos,
  id_movimiento,
  cantidad_inicial,
  cantidad_final,
  delta_inventario,
  resultado_auditoria,
  CASE
    WHEN resultado_auditoria = 'OK' THEN 'OK'
    WHEN resultado_auditoria = 'OPERACION_NO_COMPLETADA' THEN 'ESTADO_NO_COMPLETADA'
    WHEN resultado_auditoria = 'MOVIMIENTO_DUPLICADO' THEN 'DOBLE_CONTABILIZACION'
    WHEN resultado_auditoria = 'CANTIDAD_NO_COINCIDE' THEN 'DELTA_INCORRECTO'
    WHEN l.id_producto IS NULL THEN 'PRODUCTO_NULO'
    WHEN l.id_ubicacion IS NULL THEN 'UBICACION_NULA'
    WHEN l.id_presentacion IS NULL AND l.num_presentaciones = 0 THEN 'PRODUCTO_SIN_PRESENTACION'
    WHEN l.id_presentacion IS NULL THEN 'PRESENTACION_NO_ASIGNADA'
    WHEN l.lineas_con_movimiento > 0
      AND l.lineas_con_movimiento < l.total_lineas
      AND l.id_recepcion_producto > COALESCE(l.ultimo_id_con_movimiento, 0)
      THEN 'REGISTRO_PARCIAL_INTERRUMPIDO'
    WHEN l.lineas_con_movimiento > 0 AND l.lineas_con_movimiento < l.total_lineas
      THEN 'REGISTRO_PARCIAL_KARDEX'
    ELSE 'MOVIMIENTO_NO_GENERADO'
  END AS causa_codigo,
  CASE
    WHEN resultado_auditoria = 'OK' THEN 'Inventario contabilizado correctamente.'
    WHEN resultado_auditoria = 'OPERACION_NO_COMPLETADA' THEN
      'La operación no está completada; el kardex no debería haberse aplicado.'
    WHEN resultado_auditoria = 'MOVIMIENTO_DUPLICADO' THEN
      format('Existen %s movimientos de inventario para la misma línea.', num_movimientos)
    WHEN resultado_auditoria = 'CANTIDAD_NO_COINCIDE' THEN
      format(
        'Se recibieron %s unidades pero el kardex registró delta %s.',
        cantidad_recepcion,
        COALESCE(delta_inventario, 0)
      )
    WHEN l.id_producto IS NULL THEN
      'La línea no tiene producto asociado (id_producto nulo).'
    WHEN l.id_ubicacion IS NULL THEN
      'La línea no tiene ubicación asignada.'
    WHEN l.id_presentacion IS NULL AND l.num_presentaciones = 0 THEN
      'El producto no tiene presentaciones en catálogo.'
    WHEN l.id_presentacion IS NULL AND l.tiene_presentacion_base THEN
      'La línea quedó sin presentación aunque el producto tiene presentación base.'
    WHEN l.id_presentacion IS NULL THEN
      'La línea no tiene presentación asignada.'
    WHEN l.lineas_con_movimiento > 0
      AND l.lineas_con_movimiento < l.total_lineas
      AND l.id_recepcion_producto > COALESCE(l.ultimo_id_con_movimiento, 0) THEN
      format(
        'Completación parcial: %s/%s líneas contabilizadas. Esta línea quedó después del último movimiento (id %s).',
        l.lineas_con_movimiento,
        l.total_lineas,
        l.ultimo_id_con_movimiento
      )
    WHEN l.lineas_con_movimiento > 0 AND l.lineas_con_movimiento < l.total_lineas THEN
      format(
        'Completación parcial: solo %s de %s líneas tienen movimiento de inventario.',
        l.lineas_con_movimiento,
        l.total_lineas
      )
    ELSE
      'Operación completada con datos válidos, pero sin movimiento de inventario.'
  END AS causa_descripcion
FROM audit_base l
ORDER BY
  id_operacion,
  CASE resultado_auditoria
    WHEN 'OK' THEN 5
    ELSE 1
  END,
  producto_nombre;


-- ---------------------------------------------------------------------------
-- 2) Resumen por operación
-- ---------------------------------------------------------------------------
WITH ops AS (
  SELECT unnest(ARRAY[156095, 156098])::bigint AS id_operacion
),
detalle AS (
  SELECT * FROM (
    -- reutilizar la consulta anterior empaquetada
    WITH estado_actual AS (
      SELECT DISTINCT ON (eo.id_operacion)
        eo.id_operacion, eo.estado, neo.denominacion AS estado_nombre
      FROM app_dat_estado_operacion eo
      JOIN app_nom_estado_operacion neo ON neo.id = eo.estado
      WHERE eo.id_operacion IN (SELECT id_operacion FROM ops)
      ORDER BY eo.id_operacion, eo.id DESC
    ),
    lineas AS (
      SELECT rp.id AS id_recepcion_producto, rp.id_operacion, rp.cantidad::numeric AS cantidad
      FROM app_dat_recepcion_productos rp
      WHERE rp.id_operacion IN (SELECT id_operacion FROM ops)
    ),
    movimientos AS (
      SELECT inv.id_recepcion,
             COUNT(*)::int AS num_movimientos,
             SUM((inv.cantidad_final - inv.cantidad_inicial)::numeric) AS delta_total
      FROM app_dat_inventario_productos inv
      WHERE inv.id_recepcion IN (SELECT id_recepcion_producto FROM lineas)
      GROUP BY inv.id_recepcion
    ),
    audit AS (
      SELECT
        l.id_operacion,
        ea.estado_nombre,
        l.cantidad,
        CASE
          WHEN ea.estado <> 2 THEN 'OPERACION_NO_COMPLETADA'
          WHEN COALESCE(m.num_movimientos, 0) = 0 THEN 'SIN_MOVIMIENTO_INVENTARIO'
          WHEN m.num_movimientos > 1 THEN 'MOVIMIENTO_DUPLICADO'
          WHEN ABS(COALESCE(m.delta_total, 0) - l.cantidad) > 0.0001 THEN 'CANTIDAD_NO_COINCIDE'
          ELSE 'OK'
        END AS resultado
      FROM lineas l
      JOIN estado_actual ea ON ea.id_operacion = l.id_operacion
      LEFT JOIN movimientos m ON m.id_recepcion = l.id_recepcion_producto
    )
    SELECT * FROM audit
  ) x
)
SELECT
  id_operacion,
  MAX(estado_nombre) AS estado,
  COUNT(*) AS total_lineas,
  COUNT(*) FILTER (WHERE resultado = 'OK') AS lineas_ok,
  COUNT(*) FILTER (WHERE resultado <> 'OK') AS lineas_con_problema,
  SUM(cantidad) FILTER (WHERE resultado = 'OK') AS unidades_ok,
  SUM(cantidad) FILTER (WHERE resultado = 'SIN_MOVIMIENTO_INVENTARIO') AS unidades_sin_movimiento,
  jsonb_object_agg(resultado, cnt) AS conteo_por_resultado
FROM (
  SELECT id_operacion, estado_nombre, cantidad, resultado, COUNT(*) AS cnt
  FROM detalle
  GROUP BY id_operacion, estado_nombre, cantidad, resultado
) s
GROUP BY id_operacion
ORDER BY id_operacion;


-- ---------------------------------------------------------------------------
-- 3) RPC reutilizable desde la app (opcional)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_auditar_recepcion_inventario(
  p_id_operacion bigint
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_estado int;
  v_estado_nombre text;
  v_items jsonb;
  v_ok int;
  v_problemas int;
  v_lineas_con_mov int;
  v_total_lineas int;
  v_ultimo_id_con_mov bigint;
  v_diagnostico jsonb;
BEGIN
  SELECT eo.estado, neo.denominacion
  INTO v_estado, v_estado_nombre
  FROM app_dat_estado_operacion eo
  JOIN app_nom_estado_operacion neo ON neo.id = eo.estado
  WHERE eo.id_operacion = p_id_operacion
  ORDER BY eo.id DESC
  LIMIT 1;

  IF v_estado IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Operación no encontrada',
      'id_operacion', p_id_operacion
    );
  END IF;

  WITH lineas AS (
    SELECT
      rp.id AS id_recepcion_producto,
      rp.id_producto,
      p.denominacion AS producto_nombre,
      rp.id_ubicacion,
      rp.id_presentacion,
      rp.cantidad::numeric AS cantidad_recepcion,
      la.denominacion AS ubicacion,
      a.denominacion AS almacen
    FROM app_dat_recepcion_productos rp
    LEFT JOIN app_dat_producto p ON p.id = rp.id_producto
    LEFT JOIN app_dat_layout_almacen la ON la.id = rp.id_ubicacion
    LEFT JOIN app_dat_almacen a ON a.id = la.id_almacen
    WHERE rp.id_operacion = p_id_operacion
  ),
  movimientos AS (
    SELECT
      inv.id_recepcion,
      COUNT(*)::int AS num_movimientos,
      MIN(inv.id) AS id_movimiento,
      MIN(inv.cantidad_inicial::numeric) AS cantidad_inicial,
      MAX(inv.cantidad_final::numeric) AS cantidad_final,
      SUM((inv.cantidad_final - inv.cantidad_inicial)::numeric) AS delta_inventario
    FROM app_dat_inventario_productos inv
    WHERE inv.id_recepcion IN (SELECT id_recepcion_producto FROM lineas)
    GROUP BY inv.id_recepcion
  ),
  op_stats AS (
    SELECT
      COUNT(*)::int AS total_lineas,
      COUNT(inv.id)::int AS lineas_con_movimiento,
      MAX(rp.id) FILTER (WHERE inv.id IS NOT NULL) AS ultimo_id_con_movimiento
    FROM app_dat_recepcion_productos rp
    LEFT JOIN app_dat_inventario_productos inv ON inv.id_recepcion = rp.id
    WHERE rp.id_operacion = p_id_operacion
  ),
  presentacion_stats AS (
    SELECT
      rp.id AS id_recepcion_producto,
      COUNT(pp.id)::int AS num_presentaciones,
      COALESCE(BOOL_OR(pp.es_base), false) AS tiene_presentacion_base
    FROM app_dat_recepcion_productos rp
    LEFT JOIN app_dat_producto_presentacion pp ON pp.id_producto = rp.id_producto
    WHERE rp.id_operacion = p_id_operacion
    GROUP BY rp.id
  ),
  audit AS (
    SELECT
      l.id_recepcion_producto,
      l.id_producto,
      l.producto_nombre,
      l.almacen,
      l.ubicacion,
      l.id_presentacion,
      l.cantidad_recepcion,
      COALESCE(m.num_movimientos, 0) AS num_movimientos,
      m.id_movimiento,
      m.cantidad_inicial,
      m.cantidad_final,
      m.delta_inventario,
      os.total_lineas,
      os.lineas_con_movimiento,
      os.ultimo_id_con_movimiento,
      ps.num_presentaciones,
      ps.tiene_presentacion_base,
      CASE
        WHEN v_estado <> 2 THEN 'OPERACION_NO_COMPLETADA'
        WHEN COALESCE(m.num_movimientos, 0) = 0 THEN 'SIN_MOVIMIENTO_INVENTARIO'
        WHEN m.num_movimientos > 1 THEN 'MOVIMIENTO_DUPLICADO'
        WHEN ABS(COALESCE(m.delta_inventario, 0) - l.cantidad_recepcion) > 0.0001
          THEN 'CANTIDAD_NO_COINCIDE'
        ELSE 'OK'
      END AS resultado_auditoria,
      CASE
        WHEN v_estado <> 2 THEN 'ESTADO_NO_COMPLETADA'
        WHEN COALESCE(m.num_movimientos, 0) > 1 THEN 'DOBLE_CONTABILIZACION'
        WHEN ABS(COALESCE(m.delta_inventario, 0) - l.cantidad_recepcion) > 0.0001
          THEN 'DELTA_INCORRECTO'
        WHEN l.id_producto IS NULL THEN 'PRODUCTO_NULO'
        WHEN l.id_ubicacion IS NULL THEN 'UBICACION_NULA'
        WHEN l.id_presentacion IS NULL AND ps.num_presentaciones = 0
          THEN 'PRODUCTO_SIN_PRESENTACION'
        WHEN l.id_presentacion IS NULL THEN 'PRESENTACION_NO_ASIGNADA'
        WHEN os.lineas_con_movimiento > 0
          AND os.lineas_con_movimiento < os.total_lineas
          AND l.id_recepcion_producto > COALESCE(os.ultimo_id_con_movimiento, 0)
          THEN 'REGISTRO_PARCIAL_INTERRUMPIDO'
        WHEN os.lineas_con_movimiento > 0 AND os.lineas_con_movimiento < os.total_lineas
          THEN 'REGISTRO_PARCIAL_KARDEX'
        WHEN COALESCE(m.num_movimientos, 0) = 0 THEN 'MOVIMIENTO_NO_GENERADO'
        ELSE 'OK'
      END AS causa_codigo,
      CASE
        WHEN v_estado <> 2 THEN
          'La operación no está completada; el kardex no debería haberse aplicado.'
        WHEN COALESCE(m.num_movimientos, 0) > 1 THEN
          format('Existen %s movimientos de inventario para la misma línea.', m.num_movimientos)
        WHEN ABS(COALESCE(m.delta_inventario, 0) - l.cantidad_recepcion) > 0.0001 THEN
          format(
            'Se recibieron %s unidades pero el kardex registró delta %s.',
            l.cantidad_recepcion,
            COALESCE(m.delta_inventario, 0)
          )
        WHEN l.id_producto IS NULL THEN
          'La línea no tiene producto asociado (id_producto nulo).'
        WHEN l.id_ubicacion IS NULL THEN
          'La línea no tiene ubicación asignada.'
        WHEN l.id_presentacion IS NULL AND ps.num_presentaciones = 0 THEN
          'El producto no tiene presentaciones en catálogo.'
        WHEN l.id_presentacion IS NULL AND ps.tiene_presentacion_base THEN
          'La línea quedó sin presentación aunque el producto tiene presentación base.'
        WHEN l.id_presentacion IS NULL THEN
          'La línea no tiene presentación asignada.'
        WHEN os.lineas_con_movimiento > 0
          AND os.lineas_con_movimiento < os.total_lineas
          AND l.id_recepcion_producto > COALESCE(os.ultimo_id_con_movimiento, 0) THEN
          format(
            'Completación parcial: %s/%s líneas contabilizadas. Esta línea quedó después del último movimiento (id %s).',
            os.lineas_con_movimiento,
            os.total_lineas,
            os.ultimo_id_con_movimiento
          )
        WHEN os.lineas_con_movimiento > 0 AND os.lineas_con_movimiento < os.total_lineas THEN
          format(
            'Completación parcial: solo %s de %s líneas tienen movimiento de inventario.',
            os.lineas_con_movimiento,
            os.total_lineas
          )
        WHEN COALESCE(m.num_movimientos, 0) = 0 THEN
          'Operación completada con datos válidos, pero sin movimiento de inventario.'
        ELSE 'Inventario contabilizado correctamente.'
      END AS causa_descripcion
    FROM lineas l
    CROSS JOIN op_stats os
    LEFT JOIN movimientos m ON m.id_recepcion = l.id_recepcion_producto
    LEFT JOIN presentacion_stats ps ON ps.id_recepcion_producto = l.id_recepcion_producto
  )
  SELECT
    COALESCE(jsonb_agg(to_jsonb(audit) ORDER BY
      CASE audit.resultado_auditoria
        WHEN 'OK' THEN 5 ELSE 1
      END,
      audit.producto_nombre
    ), '[]'::jsonb),
    COUNT(*) FILTER (WHERE resultado_auditoria = 'OK'),
    COUNT(*) FILTER (WHERE resultado_auditoria <> 'OK'),
    MAX(total_lineas),
    MAX(lineas_con_movimiento),
    MAX(ultimo_id_con_movimiento)
  INTO v_items, v_ok, v_problemas, v_total_lineas, v_lineas_con_mov, v_ultimo_id_con_mov
  FROM audit;

  v_diagnostico := jsonb_build_object(
    'es_registro_parcial',
      v_estado = 2 AND v_lineas_con_mov > 0 AND v_lineas_con_mov < v_total_lineas,
    'lineas_contabilizadas', v_lineas_con_mov,
    'lineas_sin_movimiento', v_total_lineas - v_lineas_con_mov,
    'ultimo_id_linea_con_movimiento', v_ultimo_id_con_mov,
    'causa_principal',
      CASE
        WHEN v_problemas = 0 THEN NULL
        WHEN v_estado = 2 AND v_lineas_con_mov > 0 AND v_lineas_con_mov < v_total_lineas
          THEN 'REGISTRO_PARCIAL_INTERRUMPIDO'
        WHEN v_estado <> 2 THEN 'ESTADO_NO_COMPLETADA'
        ELSE NULL
      END,
    'resumen',
      CASE
        WHEN v_problemas = 0 THEN 'Todas las líneas están contabilizadas en inventario.'
        WHEN v_estado = 2 AND v_lineas_con_mov > 0 AND v_lineas_con_mov < v_total_lineas THEN
          format(
            'La operación se marcó completada pero solo %s de %s líneas generaron kardex. Causa probable: interrupción o error al completar desde la app.',
            v_lineas_con_mov,
            v_total_lineas
          )
        ELSE format('Hay %s línea(s) con problemas de contabilización.', v_problemas)
      END
  );

  RETURN jsonb_build_object(
    'success', true,
    'id_operacion', p_id_operacion,
    'estado', v_estado,
    'estado_nombre', v_estado_nombre,
    'total_lineas', COALESCE(jsonb_array_length(v_items), 0),
    'lineas_ok', COALESCE(v_ok, 0),
    'lineas_con_problema', COALESCE(v_problemas, 0),
    'diagnostico_operacion', v_diagnostico,
    'items', v_items
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_auditar_recepcion_inventario(bigint)
  TO PUBLIC, anon, authenticated, service_role;
