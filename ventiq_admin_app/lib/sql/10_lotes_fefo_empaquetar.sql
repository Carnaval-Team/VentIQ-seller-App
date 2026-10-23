-- ============================================================================
-- 10 · FEFO: empaquetar presentaciones menores → pedida (con id_lote)
-- ============================================================================
-- Caso: stock en Blísteres, extracción en Cajas → "Stock por lotes insuficiente"
-- aunque el equivalente en base alcance. El FEFO de 08 solo ABRÍA empaques
-- mayores; faltaba EMPAQUETAR desde el hijo inmediato (mismo id_lote).
--
-- Prerrequisito: 08 en newa. Aplicar en newa.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_descontar_fefo_en_ubicacion(
    p_id_producto        bigint,
    p_id_ubicacion       bigint,
    p_id_presentacion    bigint,
    p_cantidad           numeric,
    p_origen_cambio      integer DEFAULT 2,
    p_id_extraccion      bigint  DEFAULT NULL,
    p_id_variante        bigint  DEFAULT NULL,
    p_id_opcion_variante bigint  DEFAULT NULL,
    p_id_operacion       bigint  DEFAULT NULL,
    p_uuid               uuid    DEFAULT NULL,
    p_motivo             text    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_pendiente     numeric := p_cantidad;
    v_lote          RECORD;
    v_a_descontar   numeric;
    v_movimientos   jsonb := '[]'::jsonb;
    v_sku_producto  varchar;
    v_sku_ubicacion varchar;
    v_nivel_obj     integer;
    v_nivel_src     integer;
    v_id_pres_src   bigint;
    v_factor_hijo   numeric;
    v_abrir         numeric;
    v_hijos         numeric;
    v_saldo_src     numeric;
    v_saldo_dst     numeric;
    v_id_conv       bigint;
    r               RECORD;
BEGIN
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La cantidad a descontar debe ser mayor que cero',
            'error_code', 'INVALID_QUANTITY'
        );
    END IF;

    SELECT c.nivel INTO v_nivel_obj
    FROM public.fn_presentaciones_producto(p_id_producto) c
    WHERE c.id_presentacion = p_id_presentacion
    LIMIT 1;

    -- Intento 1: FEFO directo en la presentación pedida
    FOR v_lote IN
      SELECT * FROM public.fn_fefo_saldos_en_ubicacion(
        p_id_producto, p_id_ubicacion, p_id_presentacion,
        p_id_variante, p_id_opcion_variante
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
        COALESCE(v_lote.id_variante, p_id_variante),
        COALESCE(v_lote.id_opcion_variante, p_id_opcion_variante),
        p_id_ubicacion,
        p_id_presentacion,
        v_lote.cantidad_final,
        v_lote.cantidad_final - v_a_descontar,
        v_lote.sku_producto, v_lote.sku_ubicacion,
        p_origen_cambio, p_id_extraccion,
        v_lote.id_lote, NOW()
      );

      v_movimientos := v_movimientos || jsonb_build_object(
        'id_lote', v_lote.id_lote,
        'codigo_lote', v_lote.codigo_lote,
        'antes', v_lote.cantidad_final,
        'descontado', v_a_descontar,
        'despues', v_lote.cantidad_final - v_a_descontar,
        'modo', 'directo'
      );
      v_pendiente := v_pendiente - v_a_descontar;
      v_sku_producto := COALESCE(v_sku_producto, v_lote.sku_producto);
      v_sku_ubicacion := COALESCE(v_sku_ubicacion, v_lote.sku_ubicacion);
    END LOOP;

    -- Intento 2: abrir presentaciones mayores (FEFO), preservando id_lote
    IF v_pendiente > 0 AND v_nivel_obj IS NOT NULL THEN
      FOR r IN
        SELECT c.nivel, c.id_presentacion, c.factor_hijo
        FROM public.fn_presentaciones_producto(p_id_producto) c
        WHERE c.nivel < v_nivel_obj
          AND COALESCE(c.factor_hijo, 0) > 0
        ORDER BY c.nivel ASC
      LOOP
        EXIT WHEN v_pendiente <= 0;
        v_nivel_src := r.nivel;
        v_id_pres_src := r.id_presentacion;
        v_factor_hijo := r.factor_hijo;

        FOR v_lote IN
          SELECT * FROM public.fn_fefo_saldos_en_ubicacion(
            p_id_producto, p_id_ubicacion, v_id_pres_src,
            p_id_variante, p_id_opcion_variante
          )
        LOOP
          EXIT WHEN v_pendiente <= 0;
          IF v_nivel_src = v_nivel_obj - 1 THEN
            v_abrir := CEIL(v_pendiente / v_factor_hijo);
            v_abrir := LEAST(v_abrir, v_lote.cantidad_final);
            IF v_abrir <= 0 THEN CONTINUE; END IF;
            v_hijos := v_abrir * v_factor_hijo;

            v_saldo_src := public.fn_saldo_lote_presentacion(
              p_id_producto, p_id_ubicacion, v_id_pres_src, v_lote.id_lote,
              p_id_variante, p_id_opcion_variante);
            v_saldo_dst := public.fn_saldo_lote_presentacion(
              p_id_producto, p_id_ubicacion, p_id_presentacion, v_lote.id_lote,
              p_id_variante, p_id_opcion_variante);

            v_id_conv := public.fn_registrar_conversion_presentacion(
              p_id_producto             := p_id_producto,
              p_id_ubicacion            := p_id_ubicacion,
              p_id_presentacion_origen  := v_id_pres_src,
              p_id_presentacion_destino := p_id_presentacion,
              p_cantidad_origen         := v_abrir,
              p_cantidad_destino        := v_hijos,
              p_tipo                    := 'abrir',
              p_saldo_origen_antes      := v_saldo_src,
              p_saldo_destino_antes     := v_saldo_dst,
              p_id_variante             := p_id_variante,
              p_id_opcion_variante      := p_id_opcion_variante,
              p_id_operacion            := p_id_operacion,
              p_uuid                    := p_uuid,
              p_motivo                  := COALESCE(p_motivo, 'egreso_fefo'),
              p_sku_producto            := v_lote.sku_producto,
              p_sku_ubicacion           := v_lote.sku_ubicacion,
              p_id_lote                 := v_lote.id_lote
            );

            v_a_descontar := LEAST(v_hijos, v_pendiente);
            v_saldo_dst := v_saldo_dst + v_hijos;

            INSERT INTO app_dat_inventario_productos (
              id_producto, id_variante, id_opcion_variante, id_ubicacion,
              id_presentacion, cantidad_inicial, cantidad_final,
              sku_producto, sku_ubicacion, origen_cambio, id_extraccion,
              id_lote, created_at
            ) VALUES (
              p_id_producto, p_id_variante, p_id_opcion_variante, p_id_ubicacion,
              p_id_presentacion, v_saldo_dst, v_saldo_dst - v_a_descontar,
              v_lote.sku_producto, v_lote.sku_ubicacion,
              p_origen_cambio, p_id_extraccion, v_lote.id_lote, NOW()
            );

            v_movimientos := v_movimientos || jsonb_build_object(
              'id_lote', v_lote.id_lote,
              'abrir', v_abrir,
              'id_conversion', v_id_conv,
              'descontado', v_a_descontar,
              'modo', 'abrir'
            );
            v_pendiente := v_pendiente - v_a_descontar;
          END IF;
        END LOOP;
      END LOOP;
    END IF;

    -- Intento 3: empaquetar desde el hijo inmediato (FEFO), preservando id_lote
    -- Ej.: pedir 5 Cajas con stock en Blísteres (1 caja = 10 blísteres).
    IF v_pendiente > 0 THEN
      SELECT c.id_presentacion_hijo, c.factor_hijo
        INTO v_id_pres_src, v_factor_hijo
        FROM public.fn_presentaciones_producto(p_id_producto) c
       WHERE c.id_presentacion = p_id_presentacion
         AND c.id_presentacion_hijo IS NOT NULL
         AND COALESCE(c.factor_hijo, 0) > 0
       LIMIT 1;

      IF v_id_pres_src IS NOT NULL AND v_factor_hijo > 0 THEN
        FOR v_lote IN
          SELECT * FROM public.fn_fefo_saldos_en_ubicacion(
            p_id_producto, p_id_ubicacion, v_id_pres_src,
            p_id_variante, p_id_opcion_variante
          )
        LOOP
          EXIT WHEN v_pendiente <= 0;

          v_saldo_src := public.fn_saldo_lote_presentacion(
            p_id_producto, p_id_ubicacion, v_id_pres_src, v_lote.id_lote,
            p_id_variante, p_id_opcion_variante);
          v_saldo_dst := public.fn_saldo_lote_presentacion(
            p_id_producto, p_id_ubicacion, p_id_presentacion, v_lote.id_lote,
            p_id_variante, p_id_opcion_variante);

          -- Packs enteros disponibles en este lote
          v_abrir := FLOOR(GREATEST(v_saldo_src, 0) / v_factor_hijo);
          v_abrir := LEAST(v_abrir, v_pendiente);
          IF v_abrir <= 0 THEN
            CONTINUE;
          END IF;
          v_hijos := v_abrir * v_factor_hijo;

          v_id_conv := public.fn_registrar_conversion_presentacion(
            p_id_producto             := p_id_producto,
            p_id_ubicacion            := p_id_ubicacion,
            p_id_presentacion_origen  := v_id_pres_src,
            p_id_presentacion_destino := p_id_presentacion,
            p_cantidad_origen         := v_hijos,
            p_cantidad_destino        := v_abrir,
            p_tipo                    := 'empaquetar',
            p_saldo_origen_antes      := v_saldo_src,
            p_saldo_destino_antes     := v_saldo_dst,
            p_id_variante             := p_id_variante,
            p_id_opcion_variante      := p_id_opcion_variante,
            p_id_operacion            := p_id_operacion,
            p_uuid                    := p_uuid,
            p_motivo                  := COALESCE(p_motivo, 'egreso_fefo'),
            p_sku_producto            := v_lote.sku_producto,
            p_sku_ubicacion           := v_lote.sku_ubicacion,
            p_id_lote                 := v_lote.id_lote
          );

          v_a_descontar := v_abrir;
          v_saldo_dst := v_saldo_dst + v_abrir;

          INSERT INTO app_dat_inventario_productos (
            id_producto, id_variante, id_opcion_variante, id_ubicacion,
            id_presentacion, cantidad_inicial, cantidad_final,
            sku_producto, sku_ubicacion, origen_cambio, id_extraccion,
            id_lote, created_at
          ) VALUES (
            p_id_producto, p_id_variante, p_id_opcion_variante, p_id_ubicacion,
            p_id_presentacion, v_saldo_dst, v_saldo_dst - v_a_descontar,
            v_lote.sku_producto, v_lote.sku_ubicacion,
            p_origen_cambio, p_id_extraccion, v_lote.id_lote, NOW()
          );

          v_movimientos := v_movimientos || jsonb_build_object(
            'id_lote', v_lote.id_lote,
            'codigo_lote', v_lote.codigo_lote,
            'empaquetar_origen', v_hijos,
            'empaquetar_destino', v_abrir,
            'id_conversion', v_id_conv,
            'descontado', v_a_descontar,
            'modo', 'empaquetar'
          );
          v_pendiente := v_pendiente - v_a_descontar;
        END LOOP;
      END IF;
    END IF;

    IF v_pendiente > 0 THEN
      RETURN jsonb_build_object(
        'status', 'error',
        'message', format(
          'Stock por lotes insuficiente (faltó %s de %s). '
          || 'Si el stock está en otra presentación o sin lote etiquetado, '
          || 'asigne lote o use la presentación con saldo.',
          v_pendiente, p_cantidad),
        'error_code', 'INSUFFICIENT_LOTE_STOCK',
        'movimientos', v_movimientos
      );
    END IF;

    IF p_id_extraccion IS NOT NULL THEN
      UPDATE app_dat_extraccion_productos ep
      SET id_lote = COALESCE(
        ep.id_lote,
        (v_movimientos->0->>'id_lote')::bigint
      )
      WHERE ep.id = p_id_extraccion
        AND ep.id_lote IS NULL;
    END IF;

    RETURN jsonb_build_object(
      'status', 'success',
      'descontado', p_cantidad,
      'estrategia', 'fefo',
      'movimientos', v_movimientos
    );
END;
$$;

COMMENT ON FUNCTION public.fn_descontar_fefo_en_ubicacion(
  bigint, bigint, bigint, numeric, integer, bigint, bigint, bigint, bigint, uuid, text
) IS
  'Egreso FEFO: directo → abrir mayor → empaquetar hijo (mismo id_lote).';

GRANT EXECUTE ON FUNCTION public.fn_descontar_fefo_en_ubicacion(
  bigint, bigint, bigint, numeric, integer, bigint, bigint, bigint, bigint, uuid, text
) TO authenticated, service_role;
