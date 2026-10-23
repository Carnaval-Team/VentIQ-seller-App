-- ============================================================================
-- 04 · Lotes — FEFO en extracción / venta / transferencias ligeras
-- ============================================================================
-- Plan: docs/PLAN_VENCIMIENTOS_LOTES.md  (Fase 4)
-- Prerrequisito: 01–03 en newa. NO aplicar en main hasta cerrar el proyecto.
-- ============================================================================

-- ============================================================================
-- A) Helper: saldos por lote FEFO en una ubicación
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_fefo_saldos_en_ubicacion(
  p_id_producto     BIGINT,
  p_id_ubicacion    BIGINT,
  p_id_presentacion BIGINT DEFAULT NULL,
  p_id_variante     BIGINT DEFAULT NULL,
  p_id_opcion_variante BIGINT DEFAULT NULL
)
RETURNS TABLE (
  id_lote BIGINT,
  codigo_lote TEXT,
  fecha_vencimiento DATE,
  id_presentacion BIGINT,
  id_variante BIGINT,
  id_opcion_variante BIGINT,
  cantidad_final NUMERIC,
  sku_producto TEXT,
  sku_ubicacion TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH latest AS (
    SELECT DISTINCT ON (
      COALESCE(i.id_lote, 0),
      COALESCE(i.id_presentacion, 0),
      COALESCE(i.id_variante, 0),
      COALESCE(i.id_opcion_variante, 0)
    )
      i.id_lote,
      i.id_presentacion,
      i.id_variante,
      i.id_opcion_variante,
      i.cantidad_final,
      i.sku_producto,
      i.sku_ubicacion
    FROM app_dat_inventario_productos i
    WHERE i.id_producto = p_id_producto
      AND i.id_ubicacion IS NOT DISTINCT FROM p_id_ubicacion
      AND (p_id_presentacion IS NULL OR i.id_presentacion IS NOT DISTINCT FROM p_id_presentacion)
      AND (p_id_variante IS NULL OR i.id_variante IS NOT DISTINCT FROM p_id_variante)
      AND (p_id_opcion_variante IS NULL OR i.id_opcion_variante IS NOT DISTINCT FROM p_id_opcion_variante)
      AND i.id_lote IS NOT NULL
    ORDER BY
      COALESCE(i.id_lote, 0),
      COALESCE(i.id_presentacion, 0),
      COALESCE(i.id_variante, 0),
      COALESCE(i.id_opcion_variante, 0),
      i.id DESC
  )
  SELECT
    l.id_lote,
    lote.codigo::TEXT,
    lote.fecha_vencimiento,
    l.id_presentacion,
    l.id_variante,
    l.id_opcion_variante,
    l.cantidad_final,
    l.sku_producto::TEXT,
    l.sku_ubicacion::TEXT
  FROM latest l
  JOIN app_dat_lote lote ON lote.id = l.id_lote
  WHERE l.cantidad_final > 0
  ORDER BY lote.fecha_vencimiento ASC, l.id_lote ASC;
$$;

GRANT EXECUTE ON FUNCTION public.fn_fefo_saldos_en_ubicacion(BIGINT, BIGINT, BIGINT, BIGINT, BIGINT)
  TO authenticated, service_role;


-- ============================================================================
-- B) Extracción admin: FEFO + id_lote en extracción e inventario
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_crear_extraccion_con_movimiento(
  p_autorizado_por      TEXT,
  p_estado_inicial      SMALLINT,
  p_id_motivo_operacion BIGINT,
  p_id_tienda           BIGINT,
  p_observaciones       TEXT,
  p_productos           JSONB,
  p_uuid                UUID
) RETURNS JSONB AS $$
DECLARE
  v_id_operacion        BIGINT;
  v_id_extraccion_prod  BIGINT;
  v_id_tipo_operacion   BIGINT;
  v_producto_record     JSONB;
  v_cantidad_total      NUMERIC := 0;
  v_result              JSONB;
  v_tienda_exists       BOOLEAN;
  v_motivo_exists       BOOLEAN;
  v_id_producto         BIGINT;
  v_id_variante         BIGINT;
  v_id_opcion_variante  BIGINT;
  v_id_ubicacion        BIGINT;
  v_id_presentacion     BIGINT;
  v_cantidad            NUMERIC;
  v_precio_unitario     NUMERIC;
  v_sku_producto        TEXT;
  v_sku_ubicacion       TEXT;
  v_cantidad_inicial    NUMERIC;
  v_cantidad_final      NUMERIC;
  v_es_por_lotes        BOOLEAN;
  v_pendiente           NUMERIC;
  v_a_descontar         NUMERIC;
  v_lote                RECORD;
  v_id_lote             BIGINT;
  v_id_lote_explicit    BIGINT;
BEGIN
  SELECT EXISTS(SELECT 1 FROM app_dat_tienda WHERE id = p_id_tienda)
  INTO v_tienda_exists;

  SELECT EXISTS(SELECT 1 FROM app_nom_motivo_extraccion WHERE id = p_id_motivo_operacion)
  INTO v_motivo_exists;

  IF NOT v_tienda_exists THEN
    RAISE EXCEPTION 'La tienda con ID % no existe', p_id_tienda;
  END IF;

  IF NOT v_motivo_exists THEN
    RAISE EXCEPTION 'El motivo de extracción con ID % no existe', p_id_motivo_operacion;
  END IF;

  IF jsonb_array_length(p_productos) = 0 THEN
    RAISE EXCEPTION 'Debe incluir al menos un producto';
  END IF;

  SELECT id INTO v_id_tipo_operacion
  FROM app_nom_tipo_operacion
  WHERE denominacion ILIKE '%extraccion%' OR denominacion ILIKE '%extracción%'
  LIMIT 1;

  IF v_id_tipo_operacion IS NULL THEN
    RAISE EXCEPTION 'No se encontró tipo de operación para extracción';
  END IF;

  INSERT INTO app_dat_operaciones (
    id_tipo_operacion, uuid, id_tienda, observaciones, created_at
  ) VALUES (
    v_id_tipo_operacion, p_uuid, p_id_tienda, p_observaciones, NOW()
  ) RETURNING id INTO v_id_operacion;

  INSERT INTO app_dat_operacion_extraccion (
    id_operacion, id_motivo_operacion, observaciones, autorizado_por, created_at
  ) VALUES (
    v_id_operacion, p_id_motivo_operacion, p_observaciones, p_autorizado_por, NOW()
  );

  FOR v_producto_record IN SELECT * FROM jsonb_array_elements(p_productos)
  LOOP
    IF v_producto_record->>'id_producto' IS NULL OR v_producto_record->>'cantidad' IS NULL THEN
      RAISE EXCEPTION 'Cada producto debe tener id_producto y cantidad';
    END IF;

    v_id_producto        := (v_producto_record->>'id_producto')::BIGINT;
    v_id_variante        := NULLIF(v_producto_record->>'id_variante', '')::BIGINT;
    v_id_opcion_variante := NULLIF(v_producto_record->>'id_opcion_variante', '')::BIGINT;
    v_id_ubicacion       := NULLIF(v_producto_record->>'id_ubicacion', '')::BIGINT;
    v_id_presentacion    := NULLIF(v_producto_record->>'id_presentacion', '')::BIGINT;
    v_cantidad           := (v_producto_record->>'cantidad')::NUMERIC;
    v_precio_unitario    := NULLIF(v_producto_record->>'precio_unitario', '')::NUMERIC;
    v_sku_producto       := v_producto_record->>'sku_producto';
    v_sku_ubicacion      := v_producto_record->>'sku_ubicacion';
    v_id_lote_explicit   := NULLIF(v_producto_record->>'id_lote', '')::BIGINT;

    SELECT COALESCE(es_por_lotes, false) INTO v_es_por_lotes
    FROM app_dat_producto WHERE id = v_id_producto;

    IF v_es_por_lotes AND v_id_ubicacion IS NOT NULL THEN
      v_pendiente := v_cantidad;
      v_id_lote := NULL;

      -- Lote explícito o FEFO multi-lote
      IF v_id_lote_explicit IS NOT NULL THEN
        SELECT COALESCE((
          SELECT i.cantidad_final FROM app_dat_inventario_productos i
          WHERE i.id_producto = v_id_producto
            AND i.id_ubicacion IS NOT DISTINCT FROM v_id_ubicacion
            AND i.id_presentacion IS NOT DISTINCT FROM v_id_presentacion
            AND i.id_variante IS NOT DISTINCT FROM v_id_variante
            AND i.id_opcion_variante IS NOT DISTINCT FROM v_id_opcion_variante
            AND i.id_lote = v_id_lote_explicit
          ORDER BY i.id DESC LIMIT 1
        ), 0) INTO v_cantidad_inicial;

        IF v_cantidad_inicial < v_cantidad THEN
          RAISE EXCEPTION 'Stock insuficiente en lote % (disp: %, req: %)',
            v_id_lote_explicit, v_cantidad_inicial, v_cantidad;
        END IF;

        INSERT INTO app_dat_extraccion_productos (
          id_operacion, id_producto, id_variante, id_opcion_variante,
          id_ubicacion, id_presentacion, cantidad, precio_unitario,
          sku_producto, sku_ubicacion, id_lote, created_at
        ) VALUES (
          v_id_operacion, v_id_producto, v_id_variante, v_id_opcion_variante,
          v_id_ubicacion, v_id_presentacion, v_cantidad, v_precio_unitario,
          v_sku_producto, v_sku_ubicacion, v_id_lote_explicit, NOW()
        ) RETURNING id INTO v_id_extraccion_prod;

        INSERT INTO app_dat_inventario_productos (
          id_producto, id_variante, id_opcion_variante, id_ubicacion,
          id_presentacion, cantidad_inicial, cantidad_final,
          sku_producto, sku_ubicacion, origen_cambio, id_extraccion,
          id_lote, created_at
        ) VALUES (
          v_id_producto, v_id_variante, v_id_opcion_variante, v_id_ubicacion,
          v_id_presentacion, v_cantidad_inicial, v_cantidad_inicial - v_cantidad,
          v_sku_producto, v_sku_ubicacion, 2, v_id_extraccion_prod,
          v_id_lote_explicit, NOW()
        );
      ELSE
        -- FEFO completo (directo + abrir + empaquetar). No reimplementar
        -- aquí el loop solo sobre la presentación pedida: falla si el stock
        -- físico está en otra presentación (p.ej. Blísteres → Cajas).
        INSERT INTO app_dat_extraccion_productos (
          id_operacion, id_producto, id_variante, id_opcion_variante,
          id_ubicacion, id_presentacion, cantidad, precio_unitario,
          sku_producto, sku_ubicacion, id_lote, created_at
        ) VALUES (
          v_id_operacion, v_id_producto, v_id_variante, v_id_opcion_variante,
          v_id_ubicacion, v_id_presentacion, v_cantidad, v_precio_unitario,
          v_sku_producto, v_sku_ubicacion, NULL, NOW()
        ) RETURNING id INTO v_id_extraccion_prod;

        v_result := public.fn_descontar_fefo_en_ubicacion(
          p_id_producto        := v_id_producto,
          p_id_ubicacion       := v_id_ubicacion,
          p_id_presentacion    := v_id_presentacion,
          p_cantidad           := v_cantidad,
          p_origen_cambio      := 2,
          p_id_extraccion      := v_id_extraccion_prod,
          p_id_variante        := v_id_variante,
          p_id_opcion_variante := v_id_opcion_variante,
          p_id_operacion       := v_id_operacion,
          p_uuid               := p_uuid,
          p_motivo             := 'extraccion'
        );

        IF COALESCE(v_result->>'status', '') <> 'success' THEN
          RAISE EXCEPTION '%',
            COALESCE(
              v_result->>'message',
              format(
                'Stock por lotes insuficiente para producto %s',
                v_id_producto
              )
            );
        END IF;
      END IF;
    ELSE
      -- Legacy sin lotes
      INSERT INTO app_dat_extraccion_productos (
        id_operacion, id_producto, id_variante, id_opcion_variante,
        id_ubicacion, id_presentacion, cantidad, precio_unitario,
        sku_producto, sku_ubicacion, created_at
      ) VALUES (
        v_id_operacion, v_id_producto, v_id_variante, v_id_opcion_variante,
        v_id_ubicacion, v_id_presentacion, v_cantidad, v_precio_unitario,
        v_sku_producto, v_sku_ubicacion, NOW()
      ) RETURNING id INTO v_id_extraccion_prod;

      SELECT COALESCE(cantidad_final, 0)
      INTO v_cantidad_inicial
      FROM app_dat_inventario_productos
      WHERE id_producto = v_id_producto
        AND (id_variante IS NOT DISTINCT FROM v_id_variante)
        AND (id_opcion_variante IS NOT DISTINCT FROM v_id_opcion_variante)
        AND (id_ubicacion IS NOT DISTINCT FROM v_id_ubicacion)
        AND (id_presentacion IS NOT DISTINCT FROM v_id_presentacion)
      ORDER BY created_at DESC
      LIMIT 1;

      IF v_cantidad_inicial IS NULL THEN
        v_cantidad_inicial := 0;
      END IF;

      v_cantidad_final := v_cantidad_inicial - v_cantidad;

      INSERT INTO app_dat_inventario_productos (
        id_producto, id_variante, id_opcion_variante, id_ubicacion,
        id_presentacion, cantidad_inicial, cantidad_final,
        sku_producto, sku_ubicacion, origen_cambio, id_extraccion, created_at
      ) VALUES (
        v_id_producto, v_id_variante, v_id_opcion_variante, v_id_ubicacion,
        v_id_presentacion, v_cantidad_inicial, v_cantidad_final,
        v_sku_producto, v_sku_ubicacion, 2, v_id_extraccion_prod, NOW()
      );
    END IF;

    v_cantidad_total := v_cantidad_total + v_cantidad;
  END LOOP;

  INSERT INTO app_dat_estado_operacion (
    id_operacion, estado, uuid, created_at
  ) VALUES (
    v_id_operacion, p_estado_inicial, p_uuid, NOW()
  );

  v_result := jsonb_build_object(
    'status',          'success',
    'id_operacion',    v_id_operacion,
    'total_productos', jsonb_array_length(p_productos),
    'cantidad_total',  v_cantidad_total,
    'message',         'Extracción creada y movimiento de inventario registrado'
  );

  RETURN v_result;

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'status', 'error',
    'message', SQLERRM,
    'error_detail', SQLSTATE
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.fn_crear_extraccion_con_movimiento(
  TEXT, SMALLINT, BIGINT, BIGINT, TEXT, JSONB, UUID
) TO authenticated, service_role;


-- ============================================================================
-- C) Venta TPV: FEFO al descontar SKU propio por almacén
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_descontar_venta_enrutada(
  p_id_producto bigint,
  p_cantidad numeric,
  p_id_tpv bigint,
  p_id_extraccion bigint DEFAULT NULL::bigint,
  p_origen_cambio integer DEFAULT 4,
  p_ya_descontado_sku boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_ruta        jsonb;
    v_origen      text;
    v_descontar   text;
    v_id_almacen  bigint;
    v_resultado   jsonb;
    v_ubic        RECORD;
    v_lote        RECORD;
    v_pendiente   numeric;
    v_a_descontar numeric;
    v_movimientos jsonb := '[]'::jsonb;
    v_disponible  numeric;
    v_es_por_lotes boolean := false;
    v_id_lote_first bigint;
BEGIN
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La cantidad debe ser mayor que cero',
            'error_code', 'INVALID_QUANTITY'
        );
    END IF;

    v_ruta := fn_resolver_origen_venta(p_id_producto, p_id_tpv);

    IF (v_ruta->>'status') <> 'success' THEN
        RETURN v_ruta;
    END IF;

    v_origen     := v_ruta->>'origen';
    v_descontar  := v_ruta->>'descontar';
    v_id_almacen := (v_ruta->>'id_almacen')::bigint;

    IF v_descontar = 'nada' THEN
        RETURN v_ruta || jsonb_build_object(
            'descontado', false,
            'message',    'Servicio: sin movimiento de inventario'
        );
    END IF;

    IF v_descontar = 'ingredientes' THEN
        v_resultado := fn_descontar_ingredientes_elaborado(
            p_id_producto_elaborado := p_id_producto,
            p_cantidad              := p_cantidad,
            p_id_almacen            := v_id_almacen,
            p_id_extraccion         := p_id_extraccion,
            p_origen_cambio         := p_origen_cambio
        );

        IF (v_resultado->>'status') <> 'success' THEN
            RETURN v_resultado || jsonb_build_object(
                'origen',     v_origen,
                'id_almacen', v_id_almacen,
                'id_cocina',  v_ruta->'id_cocina',
                'cocina',     v_ruta->'cocina'
            );
        END IF;

        RETURN v_resultado || jsonb_build_object(
            'origen',     v_origen,
            'id_almacen', v_id_almacen,
            'id_cocina',  v_ruta->'id_cocina',
            'cocina',     v_ruta->'cocina',
            'descontado', true
        );
    END IF;

    IF v_origen = 'barra' AND p_ya_descontado_sku THEN
        RETURN v_ruta || jsonb_build_object(
            'descontado', false,
            'message',    'Producto de barra: descontado por la funcion de venta'
        );
    END IF;

    v_disponible := fn_stock_producto_almacen(p_id_producto, v_id_almacen);

    IF COALESCE(v_disponible, 0) < p_cantidad THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    CASE
                WHEN v_origen = 'cocina_por_tanda' THEN
                    'No hay suficientes porciones preparadas en "'
                    || COALESCE(v_ruta->>'cocina', 'la cocina')
                    || '" (disponibles: ' || COALESCE(v_disponible, 0)
                    || ', requeridas: ' || p_cantidad || ')'
                ELSE
                    'Stock insuficiente (disponible: ' || COALESCE(v_disponible, 0)
                    || ', requerido: ' || p_cantidad || ')'
            END,
            'error_code',          CASE WHEN v_origen = 'cocina_por_tanda'
                                        THEN 'INSUFFICIENT_PORTIONS'
                                        ELSE 'INSUFFICIENT_STOCK' END,
            'origen',              v_origen,
            'id_almacen',          v_id_almacen,
            'id_cocina',           v_ruta->'id_cocina',
            'cocina',              v_ruta->'cocina',
            'cantidad_disponible', COALESCE(v_disponible, 0),
            'cantidad_requerida',  p_cantidad
        );
    END IF;

    SELECT COALESCE(es_por_lotes, false) INTO v_es_por_lotes
    FROM app_dat_producto WHERE id = p_id_producto;

    v_pendiente := p_cantidad;

    IF v_es_por_lotes THEN
      -- FEFO por ubicaciones del almacén
      FOR v_ubic IN
          SELECT * FROM fn_stock_producto_almacen_detalle(p_id_producto, v_id_almacen)
      LOOP
          EXIT WHEN v_pendiente <= 0;

          FOR v_lote IN
            SELECT * FROM public.fn_fefo_saldos_en_ubicacion(
              p_id_producto,
              v_ubic.id_ubicacion,
              v_ubic.id_presentacion,
              v_ubic.id_variante,
              v_ubic.id_opcion_variante
            )
          LOOP
            EXIT WHEN v_pendiente <= 0;
            v_a_descontar := LEAST(v_lote.cantidad_final, v_pendiente);

            INSERT INTO app_dat_inventario_productos (
                id_producto, id_variante, id_opcion_variante, id_ubicacion,
                id_presentacion, cantidad_inicial, cantidad_final,
                sku_producto, sku_ubicacion, origen_cambio, id_extraccion,
                id_lote, created_at
            ) VALUES (
                p_id_producto,
                COALESCE(v_lote.id_variante, v_ubic.id_variante),
                COALESCE(v_lote.id_opcion_variante, v_ubic.id_opcion_variante),
                v_ubic.id_ubicacion,
                COALESCE(v_lote.id_presentacion, v_ubic.id_presentacion),
                v_lote.cantidad_final,
                v_lote.cantidad_final - v_a_descontar,
                COALESCE(v_lote.sku_producto, v_ubic.sku_producto),
                COALESCE(v_lote.sku_ubicacion, v_ubic.sku_ubicacion),
                p_origen_cambio,
                p_id_extraccion,
                v_lote.id_lote,
                NOW()
            );

            IF v_id_lote_first IS NULL THEN
              v_id_lote_first := v_lote.id_lote;
            END IF;

            v_movimientos := v_movimientos || jsonb_build_object(
                'id_ubicacion', v_ubic.id_ubicacion,
                'id_lote',      v_lote.id_lote,
                'codigo_lote',  v_lote.codigo_lote,
                'antes',        v_lote.cantidad_final,
                'descontado',   v_a_descontar,
                'despues',      v_lote.cantidad_final - v_a_descontar
            );

            v_pendiente := v_pendiente - v_a_descontar;
          END LOOP;
      END LOOP;

      IF p_id_extraccion IS NOT NULL AND v_id_lote_first IS NOT NULL THEN
        UPDATE app_dat_extraccion_productos
        SET id_lote = COALESCE(id_lote, v_id_lote_first)
        WHERE id = p_id_extraccion;
      END IF;
    ELSE
      FOR v_ubic IN
          SELECT * FROM fn_stock_producto_almacen_detalle(p_id_producto, v_id_almacen)
      LOOP
          EXIT WHEN v_pendiente <= 0;

          v_a_descontar := LEAST(v_ubic.cantidad_final, v_pendiente);

          INSERT INTO app_dat_inventario_productos (
              id_producto, id_variante, id_opcion_variante, id_ubicacion,
              id_presentacion, cantidad_inicial, cantidad_final,
              sku_producto, sku_ubicacion, origen_cambio, id_extraccion, created_at
          ) VALUES (
              p_id_producto, v_ubic.id_variante, v_ubic.id_opcion_variante,
              v_ubic.id_ubicacion, v_ubic.id_presentacion,
              v_ubic.cantidad_final, v_ubic.cantidad_final - v_a_descontar,
              v_ubic.sku_producto, v_ubic.sku_ubicacion,
              p_origen_cambio, p_id_extraccion, NOW()
          );

          v_movimientos := v_movimientos || jsonb_build_object(
              'id_ubicacion', v_ubic.id_ubicacion,
              'antes',        v_ubic.cantidad_final,
              'descontado',   v_a_descontar,
              'despues',      v_ubic.cantidad_final - v_a_descontar
          );

          v_pendiente := v_pendiente - v_a_descontar;
      END LOOP;
    END IF;

    IF v_pendiente > 0 THEN
        RAISE EXCEPTION
            'No se pudo descontar la cantidad completa del producto % en el almacen % (falto %)',
            p_id_producto, v_id_almacen, v_pendiente;
    END IF;

    RETURN jsonb_build_object(
        'status',      'success',
        'origen',      v_origen,
        'id_almacen',  v_id_almacen,
        'id_cocina',   v_ruta->'id_cocina',
        'cocina',      v_ruta->'cocina',
        'id_producto', p_id_producto,
        'cantidad',    p_cantidad,
        'descontado',  true,
        'id_lote',     v_id_lote_first,
        'movimientos', v_movimientos
    );
END;
$function$;


-- ============================================================================
-- D) Transferencia entre layouts: propagar id_lote FEFO origen → destino
--     (parche mínimo: si el JSON trae id_lote se respeta; si no y es_por_lotes, FEFO)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_transfer_asignar_lote_fefo(
  p_id_producto BIGINT,
  p_id_ubicacion_origen BIGINT,
  p_id_presentacion BIGINT,
  p_cantidad NUMERIC
)
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id_lote BIGINT;
  v_es_por_lotes BOOLEAN;
BEGIN
  SELECT COALESCE(es_por_lotes, false) INTO v_es_por_lotes
  FROM app_dat_producto WHERE id = p_id_producto;

  IF NOT COALESCE(v_es_por_lotes, false) THEN
    RETURN NULL;
  END IF;

  SELECT f.id_lote INTO v_id_lote
  FROM public.fn_fefo_saldos_en_ubicacion(
    p_id_producto, p_id_ubicacion_origen, p_id_presentacion
  ) f
  WHERE f.cantidad_final > 0
  LIMIT 1;

  RETURN v_id_lote;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_transfer_asignar_lote_fefo(BIGINT, BIGINT, BIGINT, NUMERIC)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_transfer_asignar_lote_fefo IS
  'Helper FEFO para transferencias: callers pueden setear id_lote en egreso/ingreso.';
