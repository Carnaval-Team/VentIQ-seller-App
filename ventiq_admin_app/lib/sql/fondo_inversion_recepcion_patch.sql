-- =============================================================================
-- FONDO DE INVERSIÓN — Parche sobre funciones existentes (plan §4.7)
-- Ejecutar DESPUÉS de fondo_inversion_schema.sql.
--
-- 1) fn_registrar_recepcion_con_inventario: nuevos parámetros opcionales
--    p_id_inversion, p_tasa_inversion, p_confirmar_exceso_inversion.
--    Si llega p_id_inversion, vincula la recepción a la inversión en la misma
--    transacción. Firma anterior sigue funcionando (DEFAULTs).
-- 2) Desvinculación al cancelar/anular una recepción: en lugar de editar
--    fn_registrar_cambio_estado_operacion_mejorado (que solo cubre una ruta),
--    se usa un TRIGGER sobre app_dat_estado_operacion, que cubre TODAS las
--    rutas de cancelación/anulación de recepciones.
-- =============================================================================

-- =============================================================================
-- 1. Recepción con vínculo opcional a inversión
-- =============================================================================

-- Se hace DROP de la firma anterior: crearla como overload con parámetros
-- DEFAULT haría ambiguas todas las llamadas con la aridad vieja.
-- Los nuevos parámetros tienen DEFAULT, así que las llamadas viejas siguen
-- funcionando contra esta única definición.
DROP FUNCTION IF EXISTS public.fn_registrar_recepcion_con_inventario(
    text, bigint, numeric, integer, text, jsonb, text, uuid, text);

CREATE OR REPLACE FUNCTION public.fn_registrar_recepcion_con_inventario(
    p_entregado_por text,
    p_id_tienda bigint,
    p_monto_total numeric DEFAULT NULL::numeric,
    p_motivo integer DEFAULT NULL::integer,
    p_observaciones text DEFAULT NULL::text,
    p_productos jsonb DEFAULT '[]'::jsonb,
    p_recibido_por text DEFAULT NULL::text,
    p_uuid uuid DEFAULT NULL::uuid,
    p_moneda_factura text DEFAULT 'USD'::text,
    -- Fondo de inversión (nuevos, opcionales):
    p_id_inversion bigint DEFAULT NULL::bigint,
    p_tasa_inversion numeric DEFAULT NULL::numeric,
    p_confirmar_exceso_inversion boolean DEFAULT false
)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_id_operacion          BIGINT;
  v_id_tipo_operacion     BIGINT;
  v_producto_record       JSONB;
  v_cantidad_total        NUMERIC := 0;
  v_tienda_exists         BOOLEAN;
  v_moneda_factura        TEXT;
  v_id_recepcion_producto BIGINT;
  v_id_producto           BIGINT;
  v_id_variante           BIGINT;
  v_id_opcion_variante    BIGINT;
  v_id_ubicacion          BIGINT;
  v_id_presentacion       BIGINT;
  v_id_proveedor          BIGINT;
  v_cantidad              NUMERIC;
  v_precio_unitario       NUMERIC;
  v_codigo_lote           TEXT;
  v_fecha_vencimiento     DATE;
  v_fecha_fabricacion     DATE;
  v_es_por_lotes          BOOLEAN;
  v_id_lote               BIGINT;
  v_lote_result           JSONB;
  v_vinculo_result        JSONB;
  v_err_message           TEXT;
  v_err_detail            TEXT;
  v_err_hint              TEXT;
  v_err_context           TEXT;
BEGIN
  SELECT EXISTS(SELECT 1 FROM app_dat_tienda WHERE id = p_id_tienda)
  INTO v_tienda_exists;

  IF NOT v_tienda_exists THEN
    RETURN jsonb_build_object(
      'status',   'error',
      'message',  format('La tienda con ID %s no existe', p_id_tienda),
      'sqlstate', 'V0001',
      'etapa',    'validacion_tienda'
    );
  END IF;

  IF p_productos IS NULL OR jsonb_array_length(p_productos) = 0 THEN
    RETURN jsonb_build_object(
      'status',   'error',
      'message',  'Debe incluir al menos un producto',
      'sqlstate', 'V0002',
      'etapa',    'validacion_productos'
    );
  END IF;

  v_moneda_factura := COALESCE(NULLIF(TRIM(p_moneda_factura), ''), 'USD');
  IF v_moneda_factura NOT IN ('USD', 'EUR', 'CUP') THEN
    RETURN jsonb_build_object(
      'status',   'error',
      'message',  format('Moneda no válida: "%s". Use USD, EUR o CUP', v_moneda_factura),
      'sqlstate', 'V0003',
      'etapa',    'validacion_moneda'
    );
  END IF;

  SELECT id_tipo_operacion
  INTO v_id_tipo_operacion
  FROM app_nom_motivo_recepcion
  WHERE id = p_motivo::BIGINT;

  IF v_id_tipo_operacion IS NULL THEN
    RETURN jsonb_build_object(
      'status',   'error',
      'message',  format('No se encontró tipo de operación para el motivo %s', p_motivo),
      'sqlstate', 'V0004',
      'etapa',    'validacion_motivo'
    );
  END IF;

  INSERT INTO app_dat_operaciones (
    id_tipo_operacion, uuid, id_tienda, observaciones, created_at
  ) VALUES (
    v_id_tipo_operacion, p_uuid, p_id_tienda, p_observaciones, NOW()
  ) RETURNING id INTO v_id_operacion;

  INSERT INTO app_dat_operacion_recepcion (
    id_operacion, entregado_por, recibido_por, monto_total,
    observaciones, motivo, created_at, moneda_factura,
    tasa_cambio_aplicada, fecha_tasa_aplicada
  ) VALUES (
    v_id_operacion, p_entregado_por, p_recibido_por, p_monto_total,
    p_observaciones, p_motivo, NOW(), v_moneda_factura,
    CASE WHEN p_id_inversion IS NOT NULL
         THEN COALESCE(p_tasa_inversion, 1) END,
    CASE WHEN p_id_inversion IS NOT NULL THEN NOW() END
  );

  FOR v_producto_record IN SELECT * FROM jsonb_array_elements(p_productos)
  LOOP
    IF v_producto_record->>'id_producto' IS NULL
    OR v_producto_record->>'cantidad'    IS NULL THEN
      RETURN jsonb_build_object(
        'status',               'error',
        'message',              'Cada producto debe tener id_producto y cantidad',
        'sqlstate',             'V0005',
        'etapa',                'validacion_producto_item',
        'producto_recibido',    v_producto_record,
        'id_operacion_parcial', v_id_operacion
      );
    END IF;

    v_id_producto        := (v_producto_record->>'id_producto')::BIGINT;
    v_id_variante        := NULLIF(v_producto_record->>'id_variante',        '')::BIGINT;
    v_id_opcion_variante := NULLIF(v_producto_record->>'id_opcion_variante', '')::BIGINT;
    v_id_proveedor       := NULLIF(v_producto_record->>'id_proveedor',       '')::BIGINT;
    v_id_ubicacion       := NULLIF(v_producto_record->>'id_ubicacion',       '')::BIGINT;
    v_id_presentacion    := NULLIF(v_producto_record->>'id_presentacion',    '')::BIGINT;
    v_cantidad           := (v_producto_record->>'cantidad')::NUMERIC;
    v_precio_unitario    := NULLIF(v_producto_record->>'precio_unitario',    '')::NUMERIC;

    -- Lote (aliases: codigo_lote | lote | nro_lote)
    v_codigo_lote := NULLIF(TRIM(COALESCE(
      v_producto_record->>'codigo_lote',
      v_producto_record->>'lote',
      v_producto_record->>'nro_lote',
      ''
    )), '');
    v_fecha_vencimiento := NULLIF(COALESCE(
      v_producto_record->>'fecha_vencimiento',
      v_producto_record->>'fecha_vencimiento_lote',
      ''
    ), '')::DATE;
    v_fecha_fabricacion := NULLIF(COALESCE(
      v_producto_record->>'fecha_fabricacion',
      ''
    ), '')::DATE;

    SELECT COALESCE(p.es_por_lotes, false)
      INTO v_es_por_lotes
      FROM app_dat_producto p
     WHERE p.id = v_id_producto;

    v_id_lote := NULL;

    IF COALESCE(v_es_por_lotes, false) THEN
      IF v_codigo_lote IS NULL OR v_fecha_vencimiento IS NULL THEN
        RETURN jsonb_build_object(
          'status',               'error',
          'message',              format(
            'El producto %s es por lotes: codigo_lote y fecha_vencimiento son obligatorios',
            v_id_producto
          ),
          'sqlstate',             'V0006',
          'etapa',                'validacion_lote',
          'producto_recibido',    v_producto_record,
          'id_operacion_parcial', v_id_operacion
        );
      END IF;

      v_lote_result := public.fn_obtener_o_crear_lote(
        p_id_tienda         := p_id_tienda,
        p_id_producto       := v_id_producto,
        p_codigo            := v_codigo_lote,
        p_fecha_vencimiento := v_fecha_vencimiento,
        p_fecha_fabricacion := v_fecha_fabricacion,
        p_observaciones     := NULL
      );

      IF COALESCE(v_lote_result->>'status', '') <> 'success' THEN
        RETURN jsonb_build_object(
          'status',               'error',
          'message',              COALESCE(
            v_lote_result->>'message',
            'No se pudo obtener/crear el lote'
          ),
          'sqlstate',             'V0007',
          'etapa',                'crear_lote',
          'lote_result',          v_lote_result,
          'producto_recibido',    v_producto_record,
          'id_operacion_parcial', v_id_operacion
        );
      END IF;

      v_id_lote := (v_lote_result->>'id_lote')::BIGINT;
    END IF;

    INSERT INTO app_dat_recepcion_productos (
      id_operacion, id_producto, id_variante, id_opcion_variante,
      id_proveedor, id_ubicacion, id_presentacion, cantidad,
      precio_unitario, sku_producto, sku_ubicacion, id_lote, created_at
    ) VALUES (
      v_id_operacion, v_id_producto, v_id_variante, v_id_opcion_variante,
      v_id_proveedor, v_id_ubicacion, v_id_presentacion, v_cantidad,
      v_precio_unitario,
      v_producto_record->>'sku_producto',
      v_producto_record->>'sku_ubicacion',
      v_id_lote,
      NOW()
    ) RETURNING id INTO v_id_recepcion_producto;

    v_cantidad_total := v_cantidad_total + (v_cantidad * COALESCE(v_precio_unitario, 0));
  END LOOP;

  INSERT INTO app_dat_estado_operacion (id_operacion, estado, uuid, created_at)
  VALUES (v_id_operacion, 1, p_uuid, NOW());

  IF p_monto_total IS NULL THEN
    UPDATE app_dat_operacion_recepcion
    SET monto_total = v_cantidad_total
    WHERE id_operacion = v_id_operacion;
  END IF;

  -- ---------------------------------------------------------------------------
  -- FONDO DE INVERSIÓN: vincular la recepción a una inversión.
  -- Si el vínculo necesita confirmación por exceso, devolvemos el código
  -- 'requires_confirmation' CON la recepción ya creada; la app reintenta solo
  -- el vínculo llamando fn_fdi_vincular_recepcion con p_confirmar_exceso=true
  -- (NO vuelve a llamar a esta función, evitando una recepción duplicada).
  -- ---------------------------------------------------------------------------
  IF p_id_inversion IS NOT NULL THEN
    v_vinculo_result := public.fn_fdi_vincular_recepcion(
      p_id_operacion     := v_id_operacion,
      p_id_inversion     := p_id_inversion,
      p_monto            := COALESCE(p_monto_total, v_cantidad_total),
      p_moneda           := v_moneda_factura,
      p_tasa_a_ref       := COALESCE(p_tasa_inversion, 1),
      p_confirmar_exceso := p_confirmar_exceso_inversion
    );

    IF COALESCE(v_vinculo_result->>'status', '') <> 'ok' THEN
      RETURN jsonb_build_object(
        'status',           'requires_confirmation',
        'id_operacion',     v_id_operacion,
        'vinculo',          v_vinculo_result,
        'mensaje',          'Recepción registrada; el vínculo con la inversión requiere confirmación por exceso.'
      );
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'status',           'success',
    'id_operacion',     v_id_operacion,
    'total_productos',  jsonb_array_length(p_productos),
    'monto_total',      COALESCE(p_monto_total, v_cantidad_total),
    'moneda_utilizada', v_moneda_factura,
    'id_inversion',     p_id_inversion,
    'mensaje',          'Recepción pendiente registrada. El inventario se aplicará al completar.'
  );

EXCEPTION
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      v_err_message = MESSAGE_TEXT,
      v_err_detail  = PG_EXCEPTION_DETAIL,
      v_err_hint    = PG_EXCEPTION_HINT,
      v_err_context = PG_EXCEPTION_CONTEXT;

    RETURN jsonb_build_object(
      'status',               'error',
      'message',              v_err_message,
      'detail',               COALESCE(v_err_detail,  ''),
      'hint',                 COALESCE(v_err_hint,    ''),
      'context',              COALESCE(v_err_context, ''),
      'id_operacion_parcial', v_id_operacion
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_registrar_recepcion_con_inventario(
    text, bigint, numeric, integer, text, jsonb, text, uuid, text,
    bigint, numeric, boolean
) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_registrar_recepcion_con_inventario(
    text, bigint, numeric, integer, text, jsonb, text, uuid, text,
    bigint, numeric, boolean
) TO anon;
GRANT EXECUTE ON FUNCTION public.fn_registrar_recepcion_con_inventario(
    text, bigint, numeric, integer, text, jsonb, text, uuid, text,
    bigint, numeric, boolean
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_registrar_recepcion_con_inventario(
    text, bigint, numeric, integer, text, jsonb, text, uuid, text,
    bigint, numeric, boolean
) TO service_role;

-- =============================================================================
-- 2. Desvinculación automática al cancelar/anular una recepción.
--    Cubre fn_registrar_cambio_estado_operacion_mejorado y cualquier otra
--    ruta que inserte un estado Cancelada (3, 4) o Anulada (5).
-- =============================================================================

CREATE OR REPLACE FUNCTION public._fdi_trg_desvincular_recepcion()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.estado IN (3, 4, 5)                       -- Cancelada / Anulada
       AND EXISTS (SELECT 1 FROM public.app_dat_operacion_recepcion r
                   WHERE r.id_operacion = NEW.id_operacion)
       AND EXISTS (SELECT 1 FROM public.fdi_dat_inversion_recepcion ir
                   WHERE ir.id_operacion = NEW.id_operacion) THEN
        PERFORM public.fn_fdi_desvincular_recepcion(NEW.id_operacion);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_fdi_desvincular_recepcion ON public.app_dat_estado_operacion;
CREATE TRIGGER trg_fdi_desvincular_recepcion
    AFTER INSERT ON public.app_dat_estado_operacion
    FOR EACH ROW
    EXECUTE FUNCTION public._fdi_trg_desvincular_recepcion();
