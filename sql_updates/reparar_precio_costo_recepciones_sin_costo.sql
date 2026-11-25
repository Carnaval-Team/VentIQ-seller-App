-- ============================================================================
-- Reparación: recepciones completadas cuyo precio_promedio nunca se actualizó
-- ----------------------------------------------------------------------------
-- Recorre las líneas de recepción (motivo <> transferencia/devolución) cuya
-- presentación quedó con precio_promedio NULL/0 y vuelve a llamar
-- fn_actualizar_precio_promedio_recepcion_v2_m01 con el payload reconstruido
-- desde app_dat_recepcion_productos.
--
-- Es idempotente y seguro de re-ejecutar:
--   · La función pondera restando la cantidad recibida del saldo actual, así
--     que reconstruye el saldo previo a la recepción aunque se ejecute hoy.
--   · Solo toca presentaciones cuyo precio_promedio está NULL o en 0
--     (no pisa costos ya calculados por recepciones posteriores).
--
-- Por defecto filtra id_tienda = 196 (donde se midió el problema).
-- Para auditar antes de ejecutar, correr solo el SELECT del CTE `faltantes`.
-- ============================================================================

-- 1) AUDITORÍA PREVIA (solo lectura): líneas afectadas
SELECT rp.id_operacion, p.sku, p.denominacion, rp.cantidad, rp.precio_unitario,
       pp.precio_promedio
FROM app_dat_recepcion_productos rp
JOIN app_dat_operaciones o
  ON o.id = rp.id_operacion AND o.id_tipo_operacion = 1 AND o.id_tienda = 196
JOIN app_dat_producto p ON p.id = rp.id_producto
JOIN app_dat_producto_presentacion pp
  ON pp.id_producto = rp.id_producto AND pp.es_base = true
WHERE (pp.precio_promedio IS NULL OR pp.precio_promedio <= 0)
  AND rp.precio_unitario > 0
  AND NOT public.fn_es_operacion_sin_actualizar_precio_costo(rp.id_operacion)
  AND NOT EXISTS (
    -- el producto ya recibió costo por otra recepción posterior: no tocar
    SELECT 1
    FROM app_dat_recepcion_productos rp2
    JOIN app_dat_operaciones o2
      ON o2.id = rp2.id_operacion AND o2.id_tipo_operacion = 1
    WHERE rp2.id_producto = rp.id_producto
      AND rp2.id > rp.id
      AND rp2.precio_unitario > 0
  )
ORDER BY rp.id_operacion, p.sku;

-- 2) REPARACIÓN: una llamada por operación afectada
DO $$
DECLARE
  v_op bigint;
  v_productos jsonb;
  v_res record;
  v_ok int := 0;
  v_fail int := 0;
BEGIN
  FOR v_op IN
    SELECT DISTINCT rp.id_operacion
    FROM app_dat_recepcion_productos rp
    JOIN app_dat_operaciones o
      ON o.id = rp.id_operacion AND o.id_tipo_operacion = 1 AND o.id_tienda = 196
    JOIN app_dat_producto_presentacion pp
      ON pp.id_producto = rp.id_producto AND pp.es_base = true
    WHERE (pp.precio_promedio IS NULL OR pp.precio_promedio <= 0)
      AND rp.precio_unitario > 0
      AND NOT public.fn_es_operacion_sin_actualizar_precio_costo(rp.id_operacion)
  LOOP
    SELECT COALESCE(jsonb_agg(linea ORDER BY linea->>'id'), '[]'::jsonb)
    INTO v_productos
    FROM (
      SELECT jsonb_build_object(
        'id', rp.id,
        'id_presentacion', rp.id_presentacion,
        'precio_unitario', rp.precio_unitario,
        'cantidad', rp.cantidad,
        'costos', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'id_tipo_costo', rpc.id_tipo_costo,
            'monto_usd', rpc.monto_usd
          ))
          FROM app_dat_recepcion_producto_costo rpc
          WHERE rpc.id_recepcion_producto = rp.id
            AND rpc.revertido_at IS NULL
        ), '[]'::jsonb)
      ) AS linea
      FROM app_dat_recepcion_productos rp
      WHERE rp.id_operacion = v_op
    ) t;

    SELECT *
    INTO v_res
    FROM public.fn_actualizar_precio_promedio_recepcion_v2_m01(v_op, v_productos)
    LIMIT 1;

    IF COALESCE(v_res.success, false) THEN
      v_ok := v_ok + 1;
      RAISE NOTICE 'op %: % (actualizados: %)', v_op, v_res.mensaje,
        v_res.productos_actualizados;
    ELSE
      v_fail := v_fail + 1;
      RAISE WARNING 'op % FALLÓ: %', v_op, v_res.mensaje;
    END IF;
  END LOOP;

  RAISE NOTICE 'Reparación terminada: % operaciones OK, % con error', v_ok, v_fail;
END $$;

-- 3) VERIFICACIÓN POSTERIOR: debe devolver 0 filas
SELECT rp.id_operacion, p.sku, pp.precio_promedio
FROM app_dat_recepcion_productos rp
JOIN app_dat_operaciones o
  ON o.id = rp.id_operacion AND o.id_tipo_operacion = 1 AND o.id_tienda = 196
JOIN app_dat_producto p ON p.id = rp.id_producto
JOIN app_dat_producto_presentacion pp
  ON pp.id_producto = rp.id_producto AND pp.es_base = true
WHERE (pp.precio_promedio IS NULL OR pp.precio_promedio <= 0)
  AND rp.precio_unitario > 0
  AND NOT public.fn_es_operacion_sin_actualizar_precio_costo(rp.id_operacion);
