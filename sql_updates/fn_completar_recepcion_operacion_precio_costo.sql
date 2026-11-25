-- ============================================================================
-- fn_completar_recepcion_operacion: actualiza precio_promedio al completar
-- ----------------------------------------------------------------------------
-- REGLA (registrada en AGENTS.md):
--   Completar una recepción MANUALMENTE debe actualizar el precio promedio
--   (costo) del producto, en la MISMA transacción que contabiliza el
--   inventario y marca estado=2.
--
--   Excepciones (NO actualizan costo):
--     · motivo = 2 (recepción que entra por transferencia)
--     · envíos de consignación tipo_envio = 2 (devolución)
--     · operaciones vinculadas en app_dat_operacion_transferencia
--   Todo eso lo decide fn_es_operacion_sin_actualizar_precio_costo.
--
-- ANTES: el traslado de precio_unitario -> precio_promedio lo hacía el
-- CLIENTE después de completar (updateAveragePriceAfterReception ->
-- fn_actualizar_precio_promedio_recepcion_v2[_m01]), dentro de un try/catch
-- que se tragaba cualquier fallo. Resultado medido en producción: recepciones
-- completadas con inventario contabilizado y precio_promedio NULL
-- (24 productos en tienda 196, p. ej. op 192359 / FER-EL-67457).
--
-- AHORA: la actualización ocurre en el servidor dentro de esta función.
-- Si el precio no se puede actualizar, la operación sigue completada pero la
-- respuesta incluye 'precio_costo' con success=false y el mensaje — ya no se
-- pierde en silencio. La app puede conservar su llamada a
-- fn_actualizar_precio_promedio_recepcion_v2[_m01] (idempotente: si el
-- promedio ya quedó igual, no escribe).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_completar_recepcion_operacion(
  p_id_operacion bigint,
  p_uuid_usuario uuid DEFAULT NULL::uuid,
  p_comentario text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_estado_actual smallint;
  v_contab jsonb;
  v_id_tienda bigint;
  v_cambiar_fecha boolean;
  v_productos jsonb;
  v_precio record;
  v_precio_result jsonb;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM app_dat_operacion_recepcion orp
    WHERE orp.id_operacion = p_id_operacion
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'status', 'error',
      'error', 'NOT_A_RECEPTION',
      'message', 'La operación no es una recepción',
      'id_operacion', p_id_operacion
    );
  END IF;

  SELECT eo.estado
  INTO v_estado_actual
  FROM app_dat_estado_operacion eo
  WHERE eo.id_operacion = p_id_operacion
  ORDER BY eo.id DESC
  LIMIT 1;

  IF v_estado_actual = 2 THEN
    RETURN jsonb_build_object(
      'success', true,
      'status', 'success',
      'message', 'La operación ya estaba completada',
      'id_operacion', p_id_operacion
    );
  END IF;

  IF v_estado_actual IS NOT NULL AND v_estado_actual NOT IN (1) THEN
    RETURN jsonb_build_object(
      'success', false,
      'status', 'error',
      'error', 'INVALID_STATE',
      'message', format(
        'No se puede completar desde el estado actual (%s)',
        v_estado_actual
      ),
      'id_operacion', p_id_operacion
    );
  END IF;

  -- Contabilizar TODAS las líneas de forma atómica (validar antes de insertar)
  BEGIN
    v_contab := fn_contabilizar_recepcion_inventario(
      p_id_operacion,
      false,
      true
    );
  EXCEPTION
    WHEN OTHERS THEN
      RETURN jsonb_build_object(
        'success', false,
        'status', 'error',
        'error', 'INVENTORY_PARTIAL_FAILURE',
        'message',
          'Error al contabilizar inventario. La operación no fue completada '
          'y no se aplicaron cambios parciales.',
        'id_operacion', p_id_operacion,
        'detalle_contabilizacion', '[]'::jsonb,
        'detalle_error', SQLERRM
      );
  END;

  IF COALESCE((v_contab->>'success')::boolean, false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'success', false,
      'status', 'error',
      'error', 'INVENTORY_PARTIAL_FAILURE',
      'message', COALESCE(
        v_contab->>'message',
        'No se pudo contabilizar el inventario. La operación no fue completada.'
      ),
      'id_operacion', p_id_operacion,
      'detalle_contabilizacion', COALESCE(v_contab->'detalle', '[]'::jsonb),
      'exitosas', COALESCE((v_contab->>'exitosas')::int, 0),
      'omitidas', COALESCE((v_contab->>'omitidas')::int, 0),
      'fallidas', COALESCE((v_contab->>'fallidas')::int, 0),
      'total_lineas', COALESCE((v_contab->>'total_lineas')::int, 0)
    );
  END IF;

  -- ---------------------------------------------------------------------
  -- Actualización del costo promedio EN LA MISMA TRANSACCIÓN.
  -- Solo recepciones manuales: transferencias y devoluciones de
  -- consignación quedan excluidas por fn_es_operacion_sin_actualizar_precio_costo
  -- (también lo verifica la propia v2_m01 por dentro).
  -- ---------------------------------------------------------------------
  v_precio_result := NULL;

  IF NOT public.fn_es_operacion_sin_actualizar_precio_costo(p_id_operacion) THEN
    -- Reconstruir el payload desde las líneas reales de la recepción
    -- (id_presentacion = id de app_dat_producto_presentacion, como espera la
    -- v2). Los costos adicionales persistidos viajan en 'costos' por línea.
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
      WHERE rp.id_operacion = p_id_operacion
    ) t;

    BEGIN
      SELECT *
      INTO v_precio
      FROM public.fn_actualizar_precio_promedio_recepcion_v2_m01(
        p_id_operacion,
        v_productos
      )
      LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
      v_precio := NULL;
      v_precio_result := jsonb_build_object(
        'success', false,
        'mensaje', format('Error actualizando costo promedio [%s]: %s',
                          SQLSTATE, SQLERRM)
      );
    END;

    IF v_precio_result IS NULL THEN
      IF v_precio IS NULL THEN
        v_precio_result := jsonb_build_object(
          'success', false,
          'mensaje', 'fn_actualizar_precio_promedio_recepcion_v2_m01 sin filas'
        );
      ELSE
        v_precio_result := jsonb_build_object(
          'success', COALESCE(v_precio.success, false),
          'mensaje', v_precio.mensaje,
          'productos_actualizados', COALESCE(v_precio.productos_actualizados, 0),
          'tiempo_ms', COALESCE(v_precio.tiempo_ms, 0)
        );
      END IF;
    END IF;
  ELSE
    v_precio_result := jsonb_build_object(
      'success', true,
      'mensaje', 'Operación de transferencia/devolución: costo no actualizado',
      'productos_actualizados', 0,
      'omitida', true
    );
  END IF;

  INSERT INTO app_dat_estado_operacion (
    id_operacion, estado, uuid, comentario, created_at
  ) VALUES (
    p_id_operacion,
    2,
    p_uuid_usuario,
    p_comentario,
    NOW()
  );

  SELECT id_tienda INTO v_id_tienda
  FROM app_dat_operaciones
  WHERE id = p_id_operacion;

  IF v_id_tienda IS NOT NULL THEN
    SELECT COALESCE(cambiar_fecha_creacion_operacion_al_cierre, false)
    INTO v_cambiar_fecha
    FROM app_dat_configuracion_tienda
    WHERE id_tienda = v_id_tienda;

    IF v_cambiar_fecha THEN
      UPDATE app_dat_operaciones
      SET created_at = NOW()
      WHERE id = p_id_operacion;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'status', 'success',
    'message', COALESCE(
      v_contab->>'message',
      'Recepción completada e inventario contabilizado'
    ),
    'id_operacion', p_id_operacion,
    'detalle_contabilizacion', COALESCE(v_contab->'detalle', '[]'::jsonb),
    'exitosas', COALESCE((v_contab->>'exitosas')::int, 0),
    'omitidas', COALESCE((v_contab->>'omitidas')::int, 0),
    'fallidas', 0,
    'total_lineas', COALESCE((v_contab->>'total_lineas')::int, 0),
    'precio_costo', v_precio_result
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_completar_recepcion_operacion(bigint, uuid, text)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_completar_recepcion_operacion(bigint, uuid, text) IS
'Completa una recepción: contabiliza inventario, marca estado=2 y —solo si NO es
transferencia ni devolución de consignación— actualiza precio_promedio en la
misma transacción llamando fn_actualizar_precio_promedio_recepcion_v2_m01 con el
payload reconstruido desde app_dat_recepcion_productos. El resultado del precio
viaja en el campo "precio_costo" de la respuesta (nunca se traga el error).';
