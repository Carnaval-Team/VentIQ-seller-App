-- =============================================================================
-- fn_reporte_ventas_con_proveedor4
-- Agrega p_filtro_fecha:
--   'creacion'   (default) -> filtra por o.created_at
--   'completado'           -> filtra por eo.created_at del estado 2
--                            (historial de app_dat_estado_operacion)
-- =============================================================================

DROP FUNCTION IF EXISTS public.fn_reporte_ventas_con_proveedor4(BIGINT, DATE, DATE, BIGINT);
DROP FUNCTION IF EXISTS public.fn_reporte_ventas_con_proveedor4(BIGINT, DATE, DATE, BIGINT, TEXT);

CREATE OR REPLACE FUNCTION public.fn_reporte_ventas_con_proveedor4(
    p_id_tienda    BIGINT,
    p_fecha_desde  DATE DEFAULT NULL,
    p_fecha_hasta  DATE DEFAULT NULL,
    p_id_almacen   BIGINT DEFAULT NULL,
    p_filtro_fecha TEXT DEFAULT 'creacion'
)
RETURNS TABLE (
    id_tienda           BIGINT,
    id_producto         BIGINT,
    nombre_producto     VARCHAR,
    id_proveedor        BIGINT,
    nombre_proveedor    VARCHAR,
    precio_venta_cup    NUMERIC,
    precio_costo        NUMERIC,
    valor_usd           NUMERIC,
    precio_costo_cup    NUMERIC,
    total_vendido       NUMERIC,
    ingresos_totales    NUMERIC,
    costo_total_vendido NUMERIC,
    ganancia_unitaria   NUMERIC,
    ganancia_total      NUMERIC,
    es_elaborado        BOOLEAN,
    es_servicio         BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_filtro_fecha TEXT := LOWER(COALESCE(NULLIF(TRIM(p_filtro_fecha), ''), 'creacion'));
BEGIN
    IF v_filtro_fecha NOT IN ('creacion', 'completado') THEN
        v_filtro_fecha := 'creacion';
    END IF;

    RETURN QUERY
    WITH

    -- -------------------------------------------------------------------------
    -- 1. Cada línea de venta con su fecha de criterio (creación o completado)
    -- -------------------------------------------------------------------------
    ventas_detalle AS (
        SELECT
            ep.id_producto,
            ep.id_variante,
            ep.id_presentacion,
            ep.cantidad,
            ep.importe,
            CASE
                WHEN v_filtro_fecha = 'completado' THEN eo.created_at::DATE
                ELSE o.created_at::DATE
            END AS fecha_op
        FROM app_dat_operaciones o
        JOIN app_dat_operacion_venta  ov  ON o.id = ov.id_operacion
        JOIN app_dat_extraccion_productos ep ON o.id = ep.id_operacion
        JOIN app_dat_estado_operacion eo ON o.id = eo.id_operacion
        WHERE o.id_tienda = p_id_tienda
          AND eo.estado = 2
          AND eo.id = (SELECT MAX(id) FROM app_dat_estado_operacion WHERE id_operacion = o.id)
          AND ov.es_pagada = true
          AND o.id_tipo_operacion = (
                SELECT id FROM app_nom_tipo_operacion
                WHERE LOWER(denominacion) = 'venta'
              )
          AND (
                p_fecha_desde IS NULL
                OR CASE
                    WHEN v_filtro_fecha = 'completado' THEN eo.created_at::DATE
                    ELSE o.created_at::DATE
                   END >= p_fecha_desde
              )
          AND (
                p_fecha_hasta IS NULL
                OR CASE
                    WHEN v_filtro_fecha = 'completado' THEN eo.created_at::DATE
                    ELSE o.created_at::DATE
                   END <= p_fecha_hasta
              )
          AND (p_id_almacen IS NULL OR ep.id_ubicacion IN (
                SELECT id FROM app_dat_layout_almacen WHERE id_almacen = p_id_almacen
              ))
          AND ep.cantidad > 0
    ),

    -- -------------------------------------------------------------------------
    -- 2. Precio de venta vigente en la fecha de criterio
    -- -------------------------------------------------------------------------
    precio_venta_historico AS (
        SELECT DISTINCT ON (vd.id_producto, COALESCE(vd.id_variante, 0), vd.fecha_op)
            vd.id_producto,
            vd.id_variante,
            vd.fecha_op,
            ROUND(pv.precio_venta_cup::NUMERIC, 2) AS precio_cup_historico
        FROM ventas_detalle vd
        JOIN app_dat_precio_venta pv
          ON pv.id_producto = vd.id_producto
         AND (pv.id_variante IS NULL OR pv.id_variante = 0
              OR pv.id_variante = vd.id_variante)
         AND pv.fecha_desde <= vd.fecha_op
         AND (pv.fecha_hasta IS NULL OR pv.fecha_hasta >= vd.fecha_op)
        ORDER BY
            vd.id_producto,
            COALESCE(vd.id_variante, 0),
            vd.fecha_op,
            pv.created_at DESC
    ),

    -- -------------------------------------------------------------------------
    -- 3. Tasa USD→CUP vigente en cada fecha de criterio
    -- -------------------------------------------------------------------------
    tasa_historica AS (
        SELECT DISTINCT ON (vd.fecha_op)
            vd.fecha_op,
            tc.valor_cambio AS tasa_cup
        FROM (SELECT DISTINCT fecha_op FROM ventas_detalle) vd
        JOIN tasa_cambio_extraoficial tc
          ON tc.id_tienda = p_id_tienda
         AND tc.activo = true
         AND tc.created_at::DATE <= vd.fecha_op
        ORDER BY vd.fecha_op, tc.created_at DESC
    ),

    -- -------------------------------------------------------------------------
    -- 4. Costo unitario en USD
    -- -------------------------------------------------------------------------
    costo_usd AS (
        SELECT
            pp.id_producto,
            pp.id AS id_presentacion,
            pp.precio_promedio AS costo_unitario_usd
        FROM app_dat_producto_presentacion pp
        WHERE pp.precio_promedio > 0
    ),

    costo_usd_recepcion AS (
        SELECT DISTINCT ON (rp.id_producto, COALESCE(rp.id_variante, 0))
            rp.id_producto,
            rp.id_variante,
            COALESCE(rp.costo_real, rp.precio_unitario, 0) AS costo_unitario_usd
        FROM app_dat_recepcion_productos rp
        JOIN app_dat_operaciones o ON rp.id_operacion = o.id
        WHERE o.id_tienda = p_id_tienda
        ORDER BY rp.id_producto, COALESCE(rp.id_variante, 0), o.created_at DESC
    ),

    -- -------------------------------------------------------------------------
    -- 5. Enriquecer cada línea
    -- -------------------------------------------------------------------------
    ventas_enriquecidas AS (
        SELECT
            vd.id_producto,
            vd.id_variante,
            vd.id_presentacion,
            vd.cantidad,
            vd.importe,
            vd.fecha_op,
            ROUND(COALESCE(
                pvh.precio_cup_historico,
                CASE WHEN vd.cantidad > 0 THEN (vd.importe / vd.cantidad)::NUMERIC ELSE 0 END
            ), 2) AS precio_venta_cup_op,
            COALESCE(
                th.tasa_cup,
                (SELECT tasa FROM tasas_conversion
                 WHERE moneda_origen = 'USD' AND moneda_destino = 'CUP'
                 ORDER BY fecha_actualizacion DESC LIMIT 1)
            ) AS tasa_op,
            COALESCE(
                cu.costo_unitario_usd,
                cur.costo_unitario_usd,
                0
            ) AS costo_usd_op
        FROM ventas_detalle vd
        LEFT JOIN precio_venta_historico pvh
               ON pvh.id_producto = vd.id_producto
              AND COALESCE(pvh.id_variante, 0) = COALESCE(vd.id_variante, 0)
              AND pvh.fecha_op = vd.fecha_op
        LEFT JOIN tasa_historica th ON th.fecha_op = vd.fecha_op
        LEFT JOIN costo_usd cu
               ON cu.id_producto = vd.id_producto
              AND cu.id_presentacion = vd.id_presentacion
        LEFT JOIN costo_usd_recepcion cur
               ON cur.id_producto = vd.id_producto
              AND COALESCE(cur.id_variante, 0) = COALESCE(vd.id_variante, 0)
    ),

    -- -------------------------------------------------------------------------
    -- 5b. Costo por receta para elaborados/servicios
    -- -------------------------------------------------------------------------
    costo_receta_usd AS (
        SELECT
            pi.id_producto_elaborado AS id_producto,
            SUM(
                COALESCE(pi.cantidad_necesaria, 0) *
                COALESCE((
                    SELECT pp2.precio_promedio /
                           NULLIF(COALESCE((
                               SELECT pum.cantidad_um
                               FROM app_dat_presentacion_unidad_medida pum
                               WHERE pum.id_producto = pi.id_ingrediente
                               LIMIT 1
                           ), 1), 0)
                    FROM app_dat_producto_presentacion pp2
                    WHERE pp2.id_producto = pi.id_ingrediente
                      AND pp2.precio_promedio > 0
                    ORDER BY pp2.es_base DESC NULLS LAST, pp2.id ASC
                    LIMIT 1
                ), 0)
            ) AS costo_receta_usd
        FROM app_dat_producto_ingredientes pi
        GROUP BY pi.id_producto_elaborado
    ),

    -- -------------------------------------------------------------------------
    -- 6. Agregar por producto/presentación/precio_venta/costo_cup
    -- -------------------------------------------------------------------------
    agregado AS (
        SELECT
            ve.id_producto,
            ve.id_variante,
            ve.id_presentacion,
            ve.precio_venta_cup_op,
            ROUND((ve.costo_usd_op * ve.tasa_op)::NUMERIC, 2) AS costo_cup_op,
            ve.costo_usd_op,
            ve.tasa_op,
            SUM(ve.cantidad)                                 AS total_vendido,
            SUM(ve.precio_venta_cup_op * ve.cantidad)       AS ingresos_totales,
            SUM(ve.costo_usd_op * ve.tasa_op * ve.cantidad) AS costo_total_vendido,
            AVG(ve.tasa_op)                                  AS tasa_promedio
        FROM ventas_enriquecidas ve
        GROUP BY
            ve.id_producto,
            ve.id_variante,
            ve.id_presentacion,
            ve.precio_venta_cup_op,
            ROUND((ve.costo_usd_op * ve.tasa_op)::NUMERIC, 2),
            ve.costo_usd_op,
            ve.tasa_op
        HAVING SUM(ve.cantidad) > 0
    )

    -- -------------------------------------------------------------------------
    -- 7. Resultado final
    -- -------------------------------------------------------------------------
    SELECT
        p.id_tienda,
        p.id                                              AS id_producto,
        p.denominacion::VARCHAR                           AS nombre_producto,
        COALESCE(p.id_proveedor, 0)::BIGINT               AS id_proveedor,
        COALESCE(prov.denominacion, 'Sin Proveedor')::VARCHAR AS nombre_proveedor,
        ROUND(ag.precio_venta_cup_op::NUMERIC, 2)                  AS precio_venta_cup,
        ROUND(COALESCE(
            CASE WHEN (p.es_elaborado OR p.es_servicio) THEN cr.costo_receta_usd END,
            ag.costo_usd_op
        )::NUMERIC, 4)                                             AS precio_costo,
        ROUND(ag.tasa_op::NUMERIC, 2)                              AS valor_usd,
        ROUND(COALESCE(
            CASE WHEN (p.es_elaborado OR p.es_servicio)
                THEN cr.costo_receta_usd * ag.tasa_promedio
            END,
            ag.costo_cup_op
        )::NUMERIC, 2)                                             AS precio_costo_cup,
        ag.total_vendido,
        ROUND(ag.ingresos_totales::NUMERIC, 2)                     AS ingresos_totales,
        ROUND(COALESCE(
            CASE WHEN (p.es_elaborado OR p.es_servicio)
                THEN cr.costo_receta_usd * ag.tasa_promedio * ag.total_vendido
            END,
            ag.costo_total_vendido
        )::NUMERIC, 2)                                             AS costo_total_vendido,
        ROUND((
            ag.precio_venta_cup_op - COALESCE(
                CASE WHEN (p.es_elaborado OR p.es_servicio)
                    THEN cr.costo_receta_usd * ag.tasa_promedio
                END,
                ag.costo_cup_op
            )
        )::NUMERIC, 2)                                             AS ganancia_unitaria,
        ROUND((
            ag.ingresos_totales - COALESCE(
                CASE WHEN (p.es_elaborado OR p.es_servicio)
                    THEN cr.costo_receta_usd * ag.tasa_promedio * ag.total_vendido
                END,
                ag.costo_total_vendido
            )
        )::NUMERIC, 2)                                             AS ganancia_total,
        COALESCE(p.es_elaborado, FALSE)                            AS es_elaborado,
        COALESCE(p.es_servicio, FALSE)                             AS es_servicio
    FROM agregado ag
    JOIN app_dat_producto p ON ag.id_producto = p.id
    LEFT JOIN app_dat_proveedor prov ON p.id_proveedor = prov.id
    LEFT JOIN costo_receta_usd cr ON cr.id_producto = p.id
    WHERE p.id_tienda = p_id_tienda
    ORDER BY p.denominacion, ag.precio_venta_cup_op DESC, ag.costo_cup_op DESC;

END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_reporte_ventas_con_proveedor4(BIGINT, DATE, DATE, BIGINT, TEXT)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_reporte_ventas_con_proveedor4(BIGINT, DATE, DATE, BIGINT, TEXT)
    TO service_role;
