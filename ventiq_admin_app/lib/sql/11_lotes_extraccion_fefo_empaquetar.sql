-- ============================================================================
-- 11 · Extracción admin: usar FEFO con abrir/empaquetar
-- ============================================================================
-- Causa del error "Stock por lotes insuficiente para producto X (faltó Y)"
-- al extraer Cajas con stock en Blísteres:
--   fn_crear_extraccion_con_movimiento hacía FEFO SOLO sobre la presentación
--   pedida (Cajas=0) y NUNCA llamaba a fn_descontar_fefo_en_ubicacion
--   (que ya empaqueta Blíster→Caja con id_lote — script 10).
--
-- Prerrequisito: 10_lotes_fefo_empaquetar.sql aplicado en newa.
-- Aplicar este script en newa (SQL editor).
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

COMMENT ON FUNCTION public.fn_crear_extraccion_con_movimiento(
  TEXT, SMALLINT, BIGINT, BIGINT, TEXT, JSONB, UUID
) IS
  'Extracción admin. Productos es_por_lotes → fn_descontar_fefo_en_ubicacion '
  '(directo/abrir/empaquetar).';

GRANT EXECUTE ON FUNCTION public.fn_crear_extraccion_con_movimiento(
  TEXT, SMALLINT, BIGINT, BIGINT, TEXT, JSONB, UUID
) TO authenticated, service_role;
