-- ============================================================================
-- fn_reporte_ventas_producto_por_moneda
-- ----------------------------------------------------------------------------
-- Reporte de ventas por producto × moneda de venta (CUP / USD).
--
-- Función NUEVA y aditiva: no sustituye fn_reporte_ventas_con_proveedor5 ni
-- fn_reporte_ventas_con_proveedor_por_turno_v2. El admin la prefiere en Tiempo
-- real; si no existe, cae al reporte CUP consolidado.
--
-- Regla de utilidad (confirmada):
--   · CUP (y legacy sin moneda_venta):
--       ingresos = neto CUP de la línea
--       costo    = costo_usd × tasa_del_día × cantidad
--       ganancia = ingresos − costo   (en CUP)
--   · USD:
--       ingresos = neto nativo USD
--       costo    = costo_usd × cantidad
--       ganancia = ingresos − costo   (en USD)
--   La tasa del costo CUP es la del DÍA DE LA VENTA
--   (tasa_cambio_extraoficial vigente ese día; fallback tasas_conversion).
--   NO usar tasa_cambio_cup de la línea cuando moneda=CUP: ahí se guarda 1
--   (correcto para el equivalente CUP de la línea, inútil para el costo USD).
--   Validado en newa tienda 8: USD líneas guardan 950 (= tasa del día);
--   CUP líneas guardan 1.00.
--   Las magnitudes NO se mezclan entre monedas.
--   Sin costo demostrable, o sin tasa del día: utilidad_disponible = false.
--
-- Aplicar en newa antes de publicar el admin; en main durante el pase.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_reporte_ventas_producto_por_moneda(
    p_id_tienda    bigint,
    p_fecha_desde  date    DEFAULT NULL::date,
    p_fecha_hasta  date    DEFAULT NULL::date,
    p_id_almacen   bigint  DEFAULT NULL::bigint,
    p_filtro_fecha text    DEFAULT 'creacion'::text
)
RETURNS TABLE (
    id_tienda            bigint,
    id_producto          bigint,
    nombre_producto      character varying,
    id_proveedor         bigint,
    nombre_proveedor     character varying,
    moneda               text,
    precio_venta_nativo  numeric,
    precio_costo_usd     numeric,
    precio_costo_nativo  numeric,
    tasa_promedio        numeric,
    total_vendido        numeric,
    equiv_unidades_base  numeric,
    cantidad_formateada  text,
    ingresos_nativos     numeric,
    costo_nativo         numeric,
    ganancia_nativa      numeric,
    ganancia_unitaria    numeric,
    utilidad_disponible  boolean,
    es_elaborado         boolean,
    es_servicio          boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_filtro_fecha  text := lower(coalesce(nullif(trim(p_filtro_fecha), ''), 'creacion'));
    v_es_completado boolean;
    v_id_tipo_venta bigint;
    v_tasa_fallback numeric;
    v_fecha_inicio  timestamptz;
    v_fecha_fin     timestamptz;
BEGIN
    PERFORM public.check_user_has_access_to_tienda(p_id_tienda);

    IF v_filtro_fecha NOT IN ('creacion', 'completado') THEN
        v_filtro_fecha := 'creacion';
    END IF;
    v_es_completado := (v_filtro_fecha = 'completado');

    v_fecha_inicio := COALESCE(p_fecha_desde, CURRENT_DATE)::timestamptz;
    v_fecha_fin    := (COALESCE(p_fecha_hasta, CURRENT_DATE) + INTERVAL '1 day')::timestamptz;

    SELECT id INTO v_id_tipo_venta
      FROM app_nom_tipo_operacion
     WHERE lower(denominacion) = 'venta'
     LIMIT 1;

    IF v_id_tipo_venta IS NULL THEN
        RETURN;
    END IF;

    SELECT tc.tasa INTO v_tasa_fallback
      FROM tasas_conversion tc
     WHERE tc.moneda_origen = 'USD' AND tc.moneda_destino = 'CUP'
     ORDER BY tc.fecha_actualizacion DESC
     LIMIT 1;

    RETURN QUERY
    WITH
    ops AS MATERIALIZED (
        SELECT DISTINCT
            o.id,
            CASE
                WHEN v_es_completado THEN e.ts_estado
                ELSE o.created_at
            END AS ts_op
        FROM app_dat_operaciones o
        JOIN app_dat_operacion_venta ov
          ON ov.id_operacion = o.id
         AND ov.es_pagada = true
        CROSS JOIN LATERAL (
            SELECT eo.estado, eo.created_at AS ts_estado
              FROM app_dat_estado_operacion eo
             WHERE eo.id_operacion = o.id
             ORDER BY eo.id DESC
             LIMIT 1
        ) e
        WHERE o.id_tipo_operacion = v_id_tipo_venta
          AND o.id_tienda = p_id_tienda
          AND (
                CASE
                    WHEN v_es_completado THEN e.ts_estado
                    ELSE o.created_at
                END
              ) >= v_fecha_inicio
          AND (
                CASE
                    WHEN v_es_completado THEN e.ts_estado
                    ELSE o.created_at
                END
              ) < v_fecha_fin
          AND e.estado = 2
    ),

    ventas_detalle AS MATERIALIZED (
        SELECT
            ep.id_producto,
            ep.id_variante,
            COALESCE(ep.id_variante, 0) AS variante_key,
            ep.id_presentacion,
            ep.cantidad,
            ep.importe,
            ep.precio_unitario,
            COALESCE(NULLIF(upper(trim(ep.moneda_venta)), ''), 'CUP') AS moneda_venta,
            ep.version_monetaria,
            ep.importe_neto_nativo,
            ep.importe_neto_cup_equivalente,
            ep.precio_unitario_neto_nativo,
            ep.tasa_cambio_cup,
            op.ts_op::date AS fecha_op,
            op.ts_op
        FROM ops op
        JOIN app_dat_extraccion_productos ep ON ep.id_operacion = op.id
        WHERE ep.cantidad > 0
          AND (p_id_almacen IS NULL OR EXISTS (
                SELECT 1 FROM app_dat_layout_almacen la
                WHERE la.id_almacen = p_id_almacen
                  AND la.id = ep.id_ubicacion
              ))
    ),

    prod_var AS MATERIALIZED (
        SELECT DISTINCT vd.id_producto, vd.variante_key
        FROM ventas_detalle vd
    ),

    -- Tasa del DÍA DE LA VENTA (fuente para pasar costo USD → CUP).
    tasa_historica_venta AS MATERIALIZED (
        SELECT f.fecha_op, x.valor_cambio AS tasa_cup
        FROM (SELECT DISTINCT vd.fecha_op FROM ventas_detalle vd) f
        CROSS JOIN LATERAL (
            SELECT tc.valor_cambio
            FROM tasa_cambio_extraoficial tc
            WHERE tc.id_tienda = p_id_tienda
              AND tc.activo = true
              AND tc.created_at::date <= f.fecha_op
            ORDER BY tc.created_at DESC
            LIMIT 1
        ) x
    ),

    costo_historico AS MATERIALIZED (
        SELECT k.id_presentacion, k.ts_op, x.precio_costo_usd
        FROM (SELECT DISTINCT vd.id_presentacion, vd.ts_op FROM ventas_detalle vd) k
        CROSS JOIN LATERAL (
            SELECT pc.precio_costo_usd
            FROM app_dat_precio_costo pc
            WHERE pc.id_presentacion = k.id_presentacion
              AND pc.created_at <= k.ts_op
            ORDER BY pc.created_at DESC
            LIMIT 1
        ) x
    ),

    costo_usd AS MATERIALIZED (
        SELECT
            pp.id_producto,
            pp.id AS id_presentacion,
            pp.precio_promedio AS costo_unitario_usd
        FROM app_dat_producto_presentacion pp
        WHERE pp.precio_promedio > 0
          AND EXISTS (SELECT 1 FROM prod_var k WHERE k.id_producto = pp.id_producto)
    ),

    costo_usd_recepcion AS MATERIALIZED (
        SELECT k.id_producto, k.variante_key, x.costo_unitario_usd
        FROM prod_var k
        CROSS JOIN LATERAL (
            SELECT COALESCE(rp.costo_real, rp.precio_unitario, 0) AS costo_unitario_usd
            FROM app_dat_recepcion_productos rp
            JOIN app_dat_operaciones o2 ON o2.id = rp.id_operacion
            WHERE o2.id_tienda = p_id_tienda
              AND rp.id_producto = k.id_producto
              AND COALESCE(rp.id_variante, 0) = k.variante_key
            ORDER BY o2.created_at DESC
            LIMIT 1
        ) x
    ),

    recetas_fechas AS MATERIALIZED (
        SELECT DISTINCT vd.id_producto, vd.ts_op
        FROM ventas_detalle vd
        JOIN app_dat_producto p ON p.id = vd.id_producto
        WHERE COALESCE(p.es_elaborado, FALSE) OR COALESCE(p.es_servicio, FALSE)
    ),

    ing_meta AS MATERIALIZED (
        SELECT
            i.id_ingrediente,
            pp2.id AS id_presentacion,
            pp2.precio_promedio,
            NULLIF(COALESCE((
                SELECT pum.cantidad_um
                FROM app_dat_presentacion_unidad_medida pum
                WHERE pum.id_producto = i.id_ingrediente
                LIMIT 1
            ), 1), 0) AS divisor
        FROM (
            SELECT DISTINCT pi.id_ingrediente
            FROM app_dat_producto_ingredientes pi
            WHERE EXISTS (SELECT 1 FROM recetas_fechas rf
                          WHERE rf.id_producto = pi.id_producto_elaborado)
        ) i
        LEFT JOIN LATERAL (
            SELECT pp.id, pp.precio_promedio
            FROM app_dat_producto_presentacion pp
            WHERE pp.id_producto = i.id_ingrediente
              AND pp.precio_promedio > 0
            ORDER BY pp.es_base DESC NULLS LAST, pp.id ASC
            LIMIT 1
        ) pp2 ON TRUE
    ),

    costo_receta_hist AS MATERIALIZED (
        SELECT
            rf.id_producto,
            rf.ts_op,
            SUM(
                COALESCE(pi.cantidad_necesaria, 0) *
                COALESCE(
                    COALESCE(
                        (SELECT pc.precio_costo_usd
                         FROM app_dat_precio_costo pc
                         WHERE pc.id_presentacion = im.id_presentacion
                           AND pc.created_at <= rf.ts_op
                         ORDER BY pc.created_at DESC
                         LIMIT 1),
                        im.precio_promedio::NUMERIC
                    ) / im.divisor,
                    0
                )
            ) AS costo_receta_usd
        FROM recetas_fechas rf
        JOIN app_dat_producto_ingredientes pi ON pi.id_producto_elaborado = rf.id_producto
        LEFT JOIN ing_meta im ON im.id_ingrediente = pi.id_ingrediente
        GROUP BY rf.id_producto, rf.ts_op
    ),

    ventas_enriquecidas AS MATERIALIZED (
        SELECT
            vd.id_producto,
            vd.variante_key,
            vd.id_presentacion,
            vd.cantidad,
            CASE
                WHEN vd.moneda_venta = 'USD' THEN 'USD'
                ELSE 'CUP'
            END AS moneda,
            -- Ingresos nativos de la línea
            CASE
                WHEN vd.moneda_venta = 'USD'
                     AND vd.version_monetaria = 'producto-v1'
                     AND vd.importe_neto_nativo IS NOT NULL
                    THEN vd.importe_neto_nativo
                WHEN vd.moneda_venta = 'USD'
                     AND vd.precio_unitario_neto_nativo IS NOT NULL
                    THEN vd.precio_unitario_neto_nativo * vd.cantidad
                WHEN vd.version_monetaria = 'producto-v1'
                     AND vd.importe_neto_cup_equivalente IS NOT NULL
                    THEN vd.importe_neto_cup_equivalente
                WHEN vd.version_monetaria = 'producto-v1'
                     AND vd.importe_neto_nativo IS NOT NULL
                     AND vd.moneda_venta = 'CUP'
                    THEN vd.importe_neto_nativo
                ELSE COALESCE(
                    vd.importe,
                    CASE
                        WHEN vd.cantidad > 0 AND COALESCE(vd.precio_unitario, 0) > 0
                            THEN vd.cantidad * vd.precio_unitario
                        ELSE NULL
                    END
                )
            END AS ingresos_linea,
            -- Precio unitario nativo (para mostrar)
            CASE
                WHEN vd.precio_unitario_neto_nativo IS NOT NULL
                     AND vd.precio_unitario_neto_nativo > 0
                    THEN vd.precio_unitario_neto_nativo
                WHEN vd.version_monetaria = 'producto-v1'
                     AND vd.importe_neto_nativo IS NOT NULL
                     AND vd.cantidad > 0
                    THEN vd.importe_neto_nativo / vd.cantidad
                ELSE ROUND(COALESCE(
                    NULLIF(vd.precio_unitario, 0),
                    CASE WHEN vd.cantidad > 0 AND vd.importe IS NOT NULL
                         THEN (vd.importe / vd.cantidad)::NUMERIC END,
                    (
                        SELECT pv.precio_venta_cup
                        FROM app_dat_precio_venta pv
                        WHERE pv.id_producto = vd.id_producto
                          AND (pv.id_variante IS NULL OR pv.id_variante = 0
                               OR pv.id_variante = vd.variante_key)
                          AND pv.fecha_desde <= vd.fecha_op
                          AND (pv.fecha_hasta IS NULL OR pv.fecha_hasta >= vd.fecha_op)
                        ORDER BY pv.id DESC
                        LIMIT 1
                    )
                ), 2)
            END AS precio_venta_nativo_op,
            ROUND(CASE
                WHEN (COALESCE(p.es_elaborado, FALSE) OR COALESCE(p.es_servicio, FALSE))
                     AND crh.costo_receta_usd IS NOT NULL
                    THEN crh.costo_receta_usd
                ELSE COALESCE(
                        ch.precio_costo_usd,
                        cu.costo_unitario_usd::NUMERIC,
                        cur.costo_unitario_usd::NUMERIC,
                        0
                     )
            END::NUMERIC, 4) AS costo_usd_op,
            -- Tasa del DÍA DE LA VENTA para pasar costo USD → CUP.
            -- No usar ep.tasa_cambio_cup: en líneas CUP vale 1 por diseño.
            COALESCE(thv.tasa_cup, v_tasa_fallback) AS tasa_dia,
            (COALESCE(thv.tasa_cup, v_tasa_fallback) IS NOT NULL) AS tiene_tasa,
            (
                CASE
                    WHEN (COALESCE(p.es_elaborado, FALSE) OR COALESCE(p.es_servicio, FALSE))
                         AND crh.costo_receta_usd IS NOT NULL
                         AND crh.costo_receta_usd > 0
                        THEN TRUE
                    WHEN COALESCE(
                            ch.precio_costo_usd,
                            cu.costo_unitario_usd::NUMERIC,
                            cur.costo_unitario_usd::NUMERIC,
                            0
                         ) > 0
                        THEN TRUE
                    ELSE FALSE
                END
            ) AS tiene_costo,
            COALESCE(p.es_elaborado, FALSE) AS es_elaborado,
            COALESCE(p.es_servicio, FALSE) AS es_servicio
        FROM ventas_detalle vd
        JOIN app_dat_producto p ON p.id = vd.id_producto
        LEFT JOIN tasa_historica_venta thv ON thv.fecha_op = vd.fecha_op
        LEFT JOIN costo_historico ch
               ON ch.id_presentacion = vd.id_presentacion
              AND ch.ts_op = vd.ts_op
        LEFT JOIN costo_usd cu
               ON cu.id_producto = vd.id_producto
              AND cu.id_presentacion = vd.id_presentacion
        LEFT JOIN costo_usd_recepcion cur
               ON cur.id_producto = vd.id_producto
              AND cur.variante_key = vd.variante_key
        LEFT JOIN costo_receta_hist crh
               ON crh.id_producto = vd.id_producto
              AND crh.ts_op = vd.ts_op
    ),

    agregadas AS (
        SELECT
            ve.id_producto,
            ve.moneda,
            SUM(ve.cantidad) AS total_vendido,
            SUM(COALESCE(ve.ingresos_linea, 0)) AS ingresos_nativos,
            -- Costo en la moneda de la fila (CUP usa tasa del día de la venta)
            SUM(
                CASE
                    WHEN ve.moneda = 'USD'
                        THEN ve.costo_usd_op * ve.cantidad
                    ELSE ve.costo_usd_op * COALESCE(ve.tasa_dia, 0) * ve.cantidad
                END
            ) AS costo_nativo,
            CASE WHEN SUM(ve.cantidad) > 0
                 THEN ROUND(
                     (SUM(COALESCE(ve.precio_venta_nativo_op, 0) * ve.cantidad)
                      / SUM(ve.cantidad))::numeric, 4)
                 ELSE 0 END AS precio_venta_nativo,
            CASE WHEN SUM(ve.cantidad) > 0
                 THEN ROUND(
                     (SUM(ve.costo_usd_op * ve.cantidad) / SUM(ve.cantidad))::numeric, 4)
                 ELSE 0 END AS precio_costo_usd,
            CASE WHEN SUM(ve.cantidad) > 0
                 THEN ROUND(
                     (SUM(
                         CASE
                             WHEN ve.moneda = 'USD'
                                 THEN ve.costo_usd_op * ve.cantidad
                             ELSE ve.costo_usd_op * COALESCE(ve.tasa_dia, 0) * ve.cantidad
                         END
                      ) / SUM(ve.cantidad))::numeric, 4)
                 ELSE 0 END AS precio_costo_nativo,
            CASE WHEN SUM(ve.cantidad) > 0
                 THEN ROUND(
                     (SUM(COALESCE(ve.tasa_dia, 0) * ve.cantidad)
                      / SUM(ve.cantidad))::numeric, 4)
                 ELSE NULL END AS tasa_promedio,
            bool_and(ve.tiene_costo) AS todos_con_costo,
            bool_and(
                CASE
                    WHEN ve.moneda = 'USD' THEN TRUE
                    ELSE ve.tiene_tasa
                END
            ) AS todos_con_tasa,
            bool_or(ve.es_elaborado) AS es_elaborado,
            bool_or(ve.es_servicio) AS es_servicio
        FROM ventas_enriquecidas ve
        WHERE ve.ingresos_linea IS NOT NULL
        GROUP BY ve.id_producto, ve.moneda
        HAVING SUM(ve.cantidad) > 0
    )

    SELECT
        p.id_tienda,
        p.id AS id_producto,
        p.denominacion::VARCHAR AS nombre_producto,
        COALESCE(p.id_proveedor, 0)::BIGINT AS id_proveedor,
        COALESCE(prov.denominacion, 'Sin Proveedor')::VARCHAR AS nombre_proveedor,
        a.moneda,
        ROUND(a.precio_venta_nativo::numeric, 4) AS precio_venta_nativo,
        ROUND(a.precio_costo_usd::numeric, 4) AS precio_costo_usd,
        ROUND(a.precio_costo_nativo::numeric, 4) AS precio_costo_nativo,
        ROUND(a.tasa_promedio::numeric, 4) AS tasa_promedio,
        a.total_vendido,
        a.total_vendido AS equiv_unidades_base,
        public.fn_fmt_cantidad(a.total_vendido) AS cantidad_formateada,
        ROUND(a.ingresos_nativos::numeric, 4) AS ingresos_nativos,
        CASE
            WHEN a.todos_con_costo AND a.todos_con_tasa
                THEN ROUND(a.costo_nativo::numeric, 4)
            ELSE NULL
        END AS costo_nativo,
        CASE
            WHEN a.todos_con_costo AND a.todos_con_tasa
                THEN ROUND((a.ingresos_nativos - a.costo_nativo)::numeric, 4)
            ELSE NULL
        END AS ganancia_nativa,
        CASE
            WHEN a.todos_con_costo AND a.todos_con_tasa AND a.total_vendido > 0
                THEN ROUND(
                    ((a.ingresos_nativos - a.costo_nativo) / a.total_vendido)::numeric, 4)
            ELSE NULL
        END AS ganancia_unitaria,
        (a.todos_con_costo AND a.todos_con_tasa) AS utilidad_disponible,
        a.es_elaborado,
        a.es_servicio
    FROM agregadas a
    JOIN app_dat_producto p ON p.id = a.id_producto
    LEFT JOIN app_dat_proveedor prov ON p.id_proveedor = prov.id
    WHERE p.id_tienda = p_id_tienda
    ORDER BY p.denominacion, a.moneda;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_reporte_ventas_producto_por_moneda(bigint, date, date, bigint, text)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_reporte_ventas_producto_por_moneda(bigint, date, date, bigint, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_reporte_ventas_producto_por_moneda(bigint, date, date, bigint, text)
  TO service_role;

COMMENT ON FUNCTION public.fn_reporte_ventas_producto_por_moneda(bigint, date, date, bigint, text) IS
  'Ventas por producto × moneda. CUP: neto CUP − costo_usd×tasa_del_día; USD: neto USD − costo_usd. No mezcla monedas.';
