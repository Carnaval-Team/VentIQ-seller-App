-- ============================================================================
-- 08 — Lotes en lecturas, rebalanceo y egresos
-- ============================================================================
-- Problema: rebalanceo (origen 20) y egresos v2 leían/escribían inventario
-- SIN particionar por id_lote → mezclaban cadenas (p.ej. inicial=400 sobre
-- cadena SIN_LOTE que tenía 50).
--
-- Este script:
--   A) fn_stock_saldos_presentacion: SUM del último saldo por lote
--   B) fn_registrar_conversion_presentacion: acepta p_id_lote y lo escribe
--   C) fn_descontar_fefo_en_ubicacion: egreso FEFO (+ abrir presentación
--      preservando id_lote)
--   D) fn_descontar_con_rebalanceo: si es_por_lotes → FEFO; si no → rebalanceo
--   E) fn_rebalancear_presentaciones: si es_por_lotes → error (no contaminar)
--
-- Aplicar en newa. NO incluye ajuste correctivo de datos históricos.
-- Requiere 01–04 (app_dat_lote, fn_fefo_saldos_en_ubicacion).
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'app_dat_inventario_productos'
      AND column_name = 'id_lote'
  ) THEN
    RAISE EXCEPTION
      'Falta id_lote. Aplica 01_lotes_vencimiento_schema.sql en newa primero.';
  END IF;
END $$;


-- ============================================================================
-- A) Lectura de saldos: último por lote → SUM
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_stock_saldos_presentacion(
    p_id_producto bigint,
    p_id_almacen bigint DEFAULT NULL::bigint,
    p_id_ubicacion bigint DEFAULT NULL::bigint,
    p_incluir_cero boolean DEFAULT false
)
RETURNS TABLE(
    id_ubicacion bigint,
    id_almacen bigint,
    id_variante bigint,
    id_opcion_variante bigint,
    id_presentacion bigint,
    presentacion_nombre character varying,
    sku_codigo character varying,
    factor_rel numeric,
    es_base boolean,
    nivel integer,
    saldo numeric,
    equivalente_base numeric,
    sku_producto character varying,
    sku_ubicacion character varying
)
LANGUAGE sql
STABLE
AS $function$
    WITH vigente_lote AS (
        SELECT DISTINCT ON (
                   ip.id_ubicacion,
                   COALESCE(ip.id_variante, 0),
                   COALESCE(ip.id_opcion_variante, 0),
                   ip.id_presentacion,
                   COALESCE(ip.id_lote, 0)
               )
               ip.id_ubicacion,
               la.id_almacen,
               ip.id_variante,
               ip.id_opcion_variante,
               ip.id_presentacion,
               ip.id_lote,
               COALESCE(ip.cantidad_final, 0) AS saldo,
               ip.sku_producto,
               ip.sku_ubicacion
          FROM public.app_dat_inventario_productos ip
          JOIN public.app_dat_layout_almacen la ON la.id = ip.id_ubicacion
         WHERE ip.id_producto = p_id_producto
           AND la.deleted_at IS NULL
           AND (p_id_ubicacion IS NULL OR ip.id_ubicacion = p_id_ubicacion)
           AND (p_id_almacen   IS NULL OR la.id_almacen   = p_id_almacen)
         ORDER BY
               ip.id_ubicacion,
               COALESCE(ip.id_variante, 0),
               COALESCE(ip.id_opcion_variante, 0),
               ip.id_presentacion,
               COALESCE(ip.id_lote, 0),
               ip.id DESC
    ),
    vigente AS (
        SELECT
               v.id_ubicacion,
               v.id_almacen,
               v.id_variante,
               v.id_opcion_variante,
               v.id_presentacion,
               SUM(v.saldo) AS saldo,
               MIN(v.sku_producto) AS sku_producto,
               MIN(v.sku_ubicacion) AS sku_ubicacion
          FROM vigente_lote v
         GROUP BY
               v.id_ubicacion,
               v.id_almacen,
               v.id_variante,
               v.id_opcion_variante,
               v.id_presentacion
    )
    SELECT
        v.id_ubicacion,
        v.id_almacen,
        v.id_variante,
        v.id_opcion_variante,
        v.id_presentacion,
        c.nombre                        AS presentacion_nombre,
        c.sku_codigo,
        c.factor_rel,
        c.es_base,
        c.nivel,
        v.saldo,
        (v.saldo * COALESCE(c.factor_rel, 1)) AS equivalente_base,
        v.sku_producto,
        v.sku_ubicacion
      FROM vigente v
      LEFT JOIN public.fn_presentaciones_producto(p_id_producto) c
             ON c.id_presentacion = v.id_presentacion
     WHERE p_incluir_cero OR v.saldo <> 0
     ORDER BY v.id_ubicacion, COALESCE(c.nivel, 999), v.id_presentacion;
$function$;

COMMENT ON FUNCTION public.fn_stock_saldos_presentacion(bigint, bigint, bigint, boolean) IS
  'Saldo vigente por presentación = SUM del último snapshot por cada id_lote.';


-- ============================================================================
-- B) Conversión de presentación con id_lote opcional
-- ============================================================================
DROP FUNCTION IF EXISTS public.fn_registrar_conversion_presentacion(
  bigint, bigint, bigint, bigint, numeric, numeric, text, numeric, numeric,
  bigint, bigint, bigint, uuid, text, varchar, varchar
);

CREATE OR REPLACE FUNCTION public.fn_registrar_conversion_presentacion(
    p_id_producto             bigint,
    p_id_ubicacion            bigint,
    p_id_presentacion_origen  bigint,
    p_id_presentacion_destino bigint,
    p_cantidad_origen         numeric,
    p_cantidad_destino        numeric,
    p_tipo                    text,
    p_saldo_origen_antes      numeric,
    p_saldo_destino_antes     numeric,
    p_id_variante             bigint DEFAULT NULL,
    p_id_opcion_variante      bigint DEFAULT NULL,
    p_id_operacion            bigint DEFAULT NULL,
    p_uuid                    uuid   DEFAULT NULL,
    p_motivo                  text   DEFAULT NULL,
    p_sku_producto            varchar DEFAULT NULL,
    p_sku_ubicacion           varchar DEFAULT NULL,
    p_id_lote                 bigint DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_conversion bigint;
BEGIN
    INSERT INTO public.app_dat_conversion_presentacion (
        id_operacion, id_producto, id_variante, id_opcion_variante,
        id_ubicacion, id_presentacion_origen, id_presentacion_destino,
        cantidad_origen, cantidad_destino, tipo, motivo, uuid, created_at
    ) VALUES (
        p_id_operacion, p_id_producto, p_id_variante, p_id_opcion_variante,
        p_id_ubicacion, p_id_presentacion_origen, p_id_presentacion_destino,
        p_cantidad_origen, p_cantidad_destino, p_tipo, p_motivo, p_uuid, NOW()
    ) RETURNING id INTO v_id_conversion;

    INSERT INTO public.app_dat_inventario_productos (
        id_producto, id_variante, id_opcion_variante, id_ubicacion,
        id_presentacion, cantidad_inicial, cantidad_final,
        sku_producto, sku_ubicacion, origen_cambio, id_conversion,
        id_lote, created_at
    ) VALUES (
        p_id_producto, p_id_variante, p_id_opcion_variante, p_id_ubicacion,
        p_id_presentacion_origen,
        p_saldo_origen_antes,
        p_saldo_origen_antes - p_cantidad_origen,
        p_sku_producto, p_sku_ubicacion, 20, v_id_conversion,
        p_id_lote, NOW()
    );

    INSERT INTO public.app_dat_inventario_productos (
        id_producto, id_variante, id_opcion_variante, id_ubicacion,
        id_presentacion, cantidad_inicial, cantidad_final,
        sku_producto, sku_ubicacion, origen_cambio, id_conversion,
        id_lote, created_at
    ) VALUES (
        p_id_producto, p_id_variante, p_id_opcion_variante, p_id_ubicacion,
        p_id_presentacion_destino,
        p_saldo_destino_antes,
        p_saldo_destino_antes + p_cantidad_destino,
        p_sku_producto, p_sku_ubicacion, 20, v_id_conversion,
        p_id_lote, NOW()
    );

    RETURN v_id_conversion;
END;
$$;


-- ============================================================================
-- C) Helper: saldo vigente de UN lote concreto
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_saldo_lote_presentacion(
  p_id_producto bigint,
  p_id_ubicacion bigint,
  p_id_presentacion bigint,
  p_id_lote bigint,
  p_id_variante bigint DEFAULT NULL,
  p_id_opcion_variante bigint DEFAULT NULL
)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE((
    SELECT i.cantidad_final
    FROM app_dat_inventario_productos i
    WHERE i.id_producto = p_id_producto
      AND i.id_ubicacion IS NOT DISTINCT FROM p_id_ubicacion
      AND i.id_presentacion IS NOT DISTINCT FROM p_id_presentacion
      AND i.id_variante IS NOT DISTINCT FROM p_id_variante
      AND i.id_opcion_variante IS NOT DISTINCT FROM p_id_opcion_variante
      AND i.id_lote IS NOT DISTINCT FROM p_id_lote
    ORDER BY i.id DESC
    LIMIT 1
  ), 0);
$$;


-- ============================================================================
-- D) Descuento FEFO en una ubicación (con apertura de presentación si hace falta)
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
        'despues', v_lote.cantidad_final - v_a_descontar
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
        ORDER BY c.nivel ASC  -- de la más grande hacia la pedida
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
          -- Cuántas unidades del origen abrir para cubrir lo pendiente
          -- (aprox: pendiente / factor acumulado entre src y obj).
          -- Simplificación: abrir de nivel en nivel hacia el hijo inmediato.
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

            -- Descontar de lo recién abierto (mismo lote)
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
    -- Ej.: pedir Cajas con stock en Blísteres. Ver también 10_lotes_fefo_empaquetar.sql
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

GRANT EXECUTE ON FUNCTION public.fn_descontar_fefo_en_ubicacion(
  bigint, bigint, bigint, numeric, integer, bigint, bigint, bigint, bigint, uuid, text
) TO authenticated, service_role;


-- ============================================================================
-- E) fn_descontar_con_rebalanceo: bifurca por es_por_lotes
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_descontar_con_rebalanceo(
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
AS $$
DECLARE
    v_rebal        jsonb;
    v_saldo        numeric;
    v_sku_producto  varchar;
    v_sku_ubicacion varchar;
    v_es_por_lotes boolean := false;
BEGIN
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La cantidad a descontar debe ser mayor que cero',
            'error_code', 'INVALID_QUANTITY'
        );
    END IF;

    SELECT COALESCE(es_por_lotes, false) INTO v_es_por_lotes
    FROM app_dat_producto WHERE id = p_id_producto;

    IF v_es_por_lotes THEN
      RETURN public.fn_descontar_fefo_en_ubicacion(
        p_id_producto, p_id_ubicacion, p_id_presentacion, p_cantidad,
        p_origen_cambio, p_id_extraccion, p_id_variante, p_id_opcion_variante,
        p_id_operacion, p_uuid, p_motivo
      );
    END IF;

    v_rebal := public.fn_rebalancear_presentaciones(
        p_id_producto        := p_id_producto,
        p_id_ubicacion       := p_id_ubicacion,
        p_id_presentacion    := p_id_presentacion,
        p_cantidad           := p_cantidad,
        p_id_variante        := p_id_variante,
        p_id_opcion_variante := p_id_opcion_variante,
        p_id_operacion       := p_id_operacion,
        p_uuid               := p_uuid,
        p_motivo             := COALESCE(p_motivo, 'egreso')
    );

    IF (v_rebal->>'status') <> 'success' THEN
        RETURN v_rebal;
    END IF;

    SELECT COALESCE(SUM(s.saldo), 0),
           MIN(s.sku_producto), MIN(s.sku_ubicacion)
      INTO v_saldo, v_sku_producto, v_sku_ubicacion
      FROM public.fn_stock_saldos_presentacion(
               p_id_producto, NULL, p_id_ubicacion, true) s
     WHERE s.id_presentacion = p_id_presentacion
       AND (p_id_variante        IS NULL OR s.id_variante        IS NOT DISTINCT FROM p_id_variante)
       AND (p_id_opcion_variante IS NULL OR s.id_opcion_variante IS NOT DISTINCT FROM p_id_opcion_variante);

    IF v_saldo < p_cantidad THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    format('El rebalanceo no dejo saldo suficiente: hay %s, se piden %s',
                                 v_saldo, p_cantidad),
            'error_code', 'REBALANCE_INCONSISTENT',
            'rebalanceo', v_rebal
        );
    END IF;

    INSERT INTO public.app_dat_inventario_productos (
        id_producto, id_variante, id_opcion_variante, id_ubicacion,
        id_presentacion, cantidad_inicial, cantidad_final,
        sku_producto, sku_ubicacion, origen_cambio, id_extraccion, created_at
    ) VALUES (
        p_id_producto, p_id_variante, p_id_opcion_variante, p_id_ubicacion,
        p_id_presentacion, v_saldo, v_saldo - p_cantidad,
        v_sku_producto, v_sku_ubicacion, p_origen_cambio, p_id_extraccion, NOW()
    );

    RETURN jsonb_build_object(
        'status',         'success',
        'id_producto',    p_id_producto,
        'id_ubicacion',   p_id_ubicacion,
        'id_presentacion',p_id_presentacion,
        'descontado',     p_cantidad,
        'saldo_previo',   v_saldo,
        'saldo_nuevo',    v_saldo - p_cantidad,
        'estrategia',     v_rebal->>'estrategia',
        'conversiones',   COALESCE(v_rebal->'conversiones', '[]'::jsonb)
    );
END;
$$;


-- ============================================================================
-- F) Rebalanceo puro: bloquear en productos por lotes (evita origen 20 sin lote)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_rebalancear_presentaciones(
    p_id_producto        bigint,
    p_id_ubicacion       bigint,
    p_id_presentacion    bigint,
    p_cantidad           numeric,
    p_id_variante        bigint DEFAULT NULL,
    p_id_opcion_variante bigint DEFAULT NULL,
    p_id_operacion       bigint DEFAULT NULL,
    p_uuid               uuid   DEFAULT NULL,
    p_motivo             text   DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_es_por_lotes boolean := false;
    -- resto de variables del original
    v_n              integer;
    v_t              integer;
    v_ids            bigint[]  := '{}';
    v_nombres        text[]    := '{}';
    v_factor_rel     numeric[] := '{}';
    v_fhijo          numeric[] := '{}';
    v_s              numeric[] := '{}';
    v_abrir          numeric[] := '{}';
    v_req            numeric[] := '{}';
    v_falta          numeric[] := '{}';
    v_consumo        numeric[] := '{}';
    v_i              integer;
    v_j              integer;
    v_nivel_top      integer;
    v_nivel_deep     integer;
    v_pendiente      numeric;
    v_viable         boolean := false;
    v_conversiones   jsonb := '[]'::jsonb;
    v_id_conv        bigint;
    v_prod_hijos     numeric;
    v_consumo_hijos  numeric;
    v_sku_producto   varchar;
    v_sku_ubicacion  varchar;
    v_equiv          numeric;
    v_estrategia     text := 'ninguna';
    v_saldo_antes    numeric;
    r                RECORD;
BEGIN
    SELECT COALESCE(es_por_lotes, false) INTO v_es_por_lotes
    FROM app_dat_producto WHERE id = p_id_producto;

    IF v_es_por_lotes THEN
      RETURN jsonb_build_object(
        'status', 'error',
        'message',
          'Producto por lotes: no usar rebalanceo genérico. '
          || 'Usar fn_descontar_fefo_en_ubicacion / extracción FEFO.',
        'error_code', 'LOTES_REQUIRE_FEFO'
      );
    END IF;

    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La cantidad a rebalancear debe ser mayor que cero',
            'error_code', 'INVALID_QUANTITY'
        );
    END IF;

    IF p_id_ubicacion IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El rebalanceo necesita una ubicacion concreta',
            'error_code', 'MISSING_LOCATION'
        );
    END IF;

    PERFORM public.fn_validar_id_presentacion(p_id_producto, p_id_presentacion);

    FOR r IN
        SELECT c.nivel, c.id_presentacion, c.nombre, c.factor_rel, c.factor_hijo
          FROM public.fn_presentaciones_producto(p_id_producto) c
         ORDER BY c.nivel
    LOOP
        v_ids[r.nivel]        := r.id_presentacion;
        v_nombres[r.nivel]    := r.nombre;
        v_factor_rel[r.nivel] := r.factor_rel;
        v_fhijo[r.nivel]      := r.factor_hijo;
        v_s[r.nivel]          := 0;
        IF r.id_presentacion = p_id_presentacion THEN
            v_t := r.nivel;
        END IF;
    END LOOP;

    v_n := COALESCE(array_length(v_ids, 1), 0);

    IF v_n = 0 OR v_t IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', format('El producto %s no tiene la presentacion %s en su cadena',
                              p_id_producto, p_id_presentacion),
            'error_code', 'PRESENTATION_NOT_IN_CHAIN'
        );
    END IF;

    FOR r IN
        SELECT s.id_presentacion, SUM(s.saldo) AS saldo,
               MIN(s.sku_producto) AS sku_producto, MIN(s.sku_ubicacion) AS sku_ubicacion
          FROM public.fn_stock_saldos_presentacion(
                   p_id_producto, NULL, p_id_ubicacion, true) s
         WHERE (p_id_variante        IS NULL OR s.id_variante        IS NOT DISTINCT FROM p_id_variante)
           AND (p_id_opcion_variante IS NULL OR s.id_opcion_variante IS NOT DISTINCT FROM p_id_opcion_variante)
         GROUP BY s.id_presentacion
    LOOP
        FOR v_i IN 1 .. v_n LOOP
            IF v_ids[v_i] = r.id_presentacion THEN
                v_s[v_i] := COALESCE(r.saldo, 0);
                v_sku_producto  := COALESCE(v_sku_producto,  r.sku_producto);
                v_sku_ubicacion := COALESCE(v_sku_ubicacion, r.sku_ubicacion);
            END IF;
        END LOOP;
    END LOOP;

    v_saldo_antes := v_s[v_t];

    IF v_s[v_t] >= p_cantidad THEN
        RETURN jsonb_build_object(
            'status',        'success',
            'estrategia',    'ninguna',
            'saldo_antes',   v_saldo_antes,
            'saldo_despues', v_s[v_t],
            'conversiones',  '[]'::jsonb
        );
    END IF;

    -- INTENTO 1 · ABRIR
    IF v_t > 1 THEN
        v_pendiente := p_cantidad - v_s[v_t];
        v_req := '{}';
        v_abrir := '{}';
        v_req[v_t] := v_pendiente;
        v_nivel_top := NULL;

        FOR v_i IN REVERSE (v_t - 1) .. 1 LOOP
            IF COALESCE(v_fhijo[v_i], 0) <= 0 THEN
                EXIT;
            END IF;
            v_abrir[v_i] := CEIL(v_req[v_i + 1] / v_fhijo[v_i]);
            IF v_s[v_i] >= v_abrir[v_i] THEN
                v_nivel_top := v_i;
                EXIT;
            END IF;
            v_req[v_i] := v_abrir[v_i] - v_s[v_i];
            v_abrir[v_i] := v_s[v_i];
        END LOOP;

        IF v_nivel_top IS NOT NULL THEN
            v_viable     := true;
            v_estrategia := 'abrir';

            FOR v_i IN v_nivel_top .. (v_t - 1) LOOP
                v_prod_hijos := v_abrir[v_i] * v_fhijo[v_i];

                v_id_conv := public.fn_registrar_conversion_presentacion(
                    p_id_producto             := p_id_producto,
                    p_id_ubicacion            := p_id_ubicacion,
                    p_id_presentacion_origen  := v_ids[v_i],
                    p_id_presentacion_destino := v_ids[v_i + 1],
                    p_cantidad_origen         := v_abrir[v_i],
                    p_cantidad_destino        := v_prod_hijos,
                    p_tipo                    := 'abrir',
                    p_saldo_origen_antes      := v_s[v_i],
                    p_saldo_destino_antes     := v_s[v_i + 1],
                    p_id_variante             := p_id_variante,
                    p_id_opcion_variante      := p_id_opcion_variante,
                    p_id_operacion            := p_id_operacion,
                    p_uuid                    := p_uuid,
                    p_motivo                  := p_motivo,
                    p_sku_producto            := v_sku_producto,
                    p_sku_ubicacion           := v_sku_ubicacion,
                    p_id_lote                 := NULL
                );

                v_s[v_i]     := v_s[v_i]     - v_abrir[v_i];
                v_s[v_i + 1] := v_s[v_i + 1] + v_prod_hijos;

                v_conversiones := v_conversiones || jsonb_build_object(
                    'id_conversion',    v_id_conv,
                    'tipo',             'abrir',
                    'origen_nombre',    v_nombres[v_i],
                    'destino_nombre',   v_nombres[v_i + 1],
                    'cantidad_origen',  v_abrir[v_i],
                    'cantidad_destino', v_prod_hijos
                );
            END LOOP;
        END IF;
    END IF;

    -- INTENTO 2 · EMPAQUETAR
    IF NOT v_viable AND v_t < v_n THEN
        v_falta   := '{}';
        v_consumo := '{}';
        v_falta[v_t] := p_cantidad - v_s[v_t];

        v_nivel_deep := NULL;
        FOR v_j IN v_t .. (v_n - 1) LOOP
            IF COALESCE(v_fhijo[v_j], 0) <= 0 THEN
                EXIT;
            END IF;
            v_consumo[v_j + 1] := v_falta[v_j] * v_fhijo[v_j];
            v_falta[v_j + 1]   := GREATEST(0, v_consumo[v_j + 1] - v_s[v_j + 1]);
            IF v_falta[v_j + 1] = 0 THEN
                v_nivel_deep := v_j + 1;
                EXIT;
            END IF;
        END LOOP;

        IF v_nivel_deep IS NOT NULL THEN
            v_viable     := true;
            v_estrategia := 'empaquetar';

            FOR v_j IN REVERSE (v_nivel_deep - 1) .. v_t LOOP
                v_consumo_hijos := v_falta[v_j] * v_fhijo[v_j];

                v_id_conv := public.fn_registrar_conversion_presentacion(
                    p_id_producto             := p_id_producto,
                    p_id_ubicacion            := p_id_ubicacion,
                    p_id_presentacion_origen  := v_ids[v_j + 1],
                    p_id_presentacion_destino := v_ids[v_j],
                    p_cantidad_origen         := v_consumo_hijos,
                    p_cantidad_destino        := v_falta[v_j],
                    p_tipo                    := 'empaquetar',
                    p_saldo_origen_antes      := v_s[v_j + 1],
                    p_saldo_destino_antes     := v_s[v_j],
                    p_id_variante             := p_id_variante,
                    p_id_opcion_variante      := p_id_opcion_variante,
                    p_id_operacion            := p_id_operacion,
                    p_uuid                    := p_uuid,
                    p_motivo                  := p_motivo,
                    p_sku_producto            := v_sku_producto,
                    p_sku_ubicacion           := v_sku_ubicacion,
                    p_id_lote                 := NULL
                );

                v_s[v_j + 1] := v_s[v_j + 1] - v_consumo_hijos;
                v_s[v_j]     := v_s[v_j]     + v_falta[v_j];

                v_conversiones := v_conversiones || jsonb_build_object(
                    'id_conversion',    v_id_conv,
                    'tipo',             'empaquetar',
                    'origen_nombre',    v_nombres[v_j + 1],
                    'destino_nombre',   v_nombres[v_j],
                    'cantidad_origen',  v_consumo_hijos,
                    'cantidad_destino', v_falta[v_j]
                );
            END LOOP;
        END IF;
    END IF;

    IF NOT v_viable THEN
        v_equiv := 0;
        FOR v_i IN 1 .. v_n LOOP
            v_equiv := v_equiv + (v_s[v_i] * COALESCE(v_factor_rel[v_i], 1));
        END LOOP;

        RETURN jsonb_build_object(
            'status',              'error',
            'message',             format(
                'Stock insuficiente de %s: se piden %s y el convertible alcanza para %s',
                v_nombres[v_t], p_cantidad,
                TRUNC(v_equiv / NULLIF(v_factor_rel[v_t], 0), 3)),
            'error_code',          'INSUFFICIENT_STOCK_CONVERTIBLE',
            'id_producto',         p_id_producto,
            'id_ubicacion',        p_id_ubicacion,
            'id_presentacion',     p_id_presentacion,
            'cantidad_solicitada', p_cantidad,
            'saldo_propio',        v_s[v_t],
            'equivalente_base',    v_equiv,
            'maximo_convertible',  TRUNC(v_equiv / NULLIF(v_factor_rel[v_t], 0), 3)
        );
    END IF;

    RETURN jsonb_build_object(
        'status',        'success',
        'estrategia',    v_estrategia,
        'saldo_antes',   v_saldo_antes,
        'saldo_despues', v_s[v_t],
        'conversiones',  v_conversiones
    );
END;
$$;

COMMENT ON FUNCTION public.fn_rebalancear_presentaciones(
    bigint, bigint, bigint, numeric, bigint, bigint, bigint, uuid, text) IS
  'Rebalanceo por presentación. Bloqueado si es_por_lotes (usar FEFO).';


-- ============================================================================
-- G) Guardia en extracción v2: rechazar productos por lotes
--     (la app ya enruta a v1 FEFO; esto cubre otros callers)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_extraccion_v2_assert_no_lotes(p_productos jsonb)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT DISTINCT (e->>'id_producto')::bigint AS id_producto
    FROM jsonb_array_elements(p_productos) e
    WHERE e->>'id_producto' IS NOT NULL
  LOOP
    IF EXISTS (
      SELECT 1 FROM app_dat_producto p
      WHERE p.id = r.id_producto AND COALESCE(p.es_por_lotes, false)
    ) THEN
      RAISE EXCEPTION
        'Producto % es por lotes: use fn_crear_extraccion_con_movimiento (FEFO), no la v2',
        r.id_producto
        USING ERRCODE = 'P0001';
    END IF;
  END LOOP;
END;
$$;

-- Envolver el inicio de v2 es frágil (función enorme). La app ya enruta a FEFO.
-- Documentamos el helper para quien parchee v2 manualmente:
COMMENT ON FUNCTION public.fn_extraccion_v2_assert_no_lotes(jsonb) IS
  'Llamar al inicio de fn_crear_extraccion_con_movimiento_v2 si se regenera esa RPC.';
