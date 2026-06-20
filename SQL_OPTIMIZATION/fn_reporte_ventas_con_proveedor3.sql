-- =============================================================================
-- fn_reporte_ventas_con_proveedor4
-- Versión 3: usa historial de precios de venta (app_dat_precio_venta) y
-- historial de tasas de cambio (tasa_cambio_extraoficial) vigentes en la
-- fecha exacta de cada operación para calcular ingresos y costos correctamente.
--
-- Cambios respecto a v2:
--   - precio_venta_cup: precio vigente en app_dat_precio_venta en la fecha
--     de la operación (no el precio actual).
--   - tasa_usd: tasa vigente en tasa_cambio_extraoficial en la fecha de la
--     operación (no la tasa actual).
--   - precio_costo_cup: precio_promedio (USD) × tasa vigente en esa fecha.
--   - ingresos_totales: SUM(precio_venta_vigente × cantidad) por operación.
--   - costo_total_vendido: SUM(precio_costo_usd_vigente × tasa_vigente × cantidad).
--   - Un mismo producto aparece en MÚLTIPLES filas si tuvo precios de venta distintos
--     O costos CUP distintos (por cambio de tasa o de costo USD) durante el período.
--     Cada fila representa ventas con el mismo (precio_venta_cup, precio_costo_cup).
-- =============================================================================

DROP FUNCTION IF EXISTS public.fn_reporte_ventas_con_proveedor4(BIGINT, DATE, DATE, BIGINT);

CREATE OR REPLACE FUNCTION public.fn_reporte_ventas_con_proveedor4(
    p_id_tienda  BIGINT,
    p_fecha_desde DATE DEFAULT NULL,
    p_fecha_hasta DATE DEFAULT NULL,
    p_id_almacen  BIGINT DEFAULT NULL
)
RETURNS TABLE (
    id_tienda           BIGINT,
    id_producto         BIGINT,
    nombre_producto     VARCHAR,
    id_proveedor        BIGINT,
    nombre_proveedor    VARCHAR,
    precio_venta_cup    NUMERIC,   -- precio unitario vigente promedio ponderado
    precio_costo        NUMERIC,   -- costo unitario en USD (precio_promedio actual)
    valor_usd           NUMERIC,   -- tasa promedio ponderada usada en el período
    precio_costo_cup    NUMERIC,   -- costo unitario en CUP (promedio ponderado)
    total_vendido       NUMERIC,
    ingresos_totales    NUMERIC,   -- SUM(precio_venta_vigente × cantidad)
    costo_total_vendido NUMERIC,   -- SUM(costo_usd_vigente × tasa_vigente × cantidad)
    ganancia_unitaria   NUMERIC,   -- precio_venta_cup - precio_costo_cup (promedios)
    ganancia_total      NUMERIC,   -- ingresos_totales - costo_total_vendido
    es_elaborado        BOOLEAN,
    es_servicio         BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    WITH

    -- -------------------------------------------------------------------------
    -- 1. Cada línea de venta con su fecha de operación
    -- -------------------------------------------------------------------------
    ventas_detalle AS (
        SELECT
            ep.id_producto,
            ep.id_variante,
            ep.id_presentacion,
            ep.cantidad,
            ep.importe,                          -- importe registrado en la venta
            o.created_at::DATE AS fecha_op
        FROM app_dat_operaciones o
        JOIN app_dat_operacion_venta  ov  ON o.id = ov.id_operacion
        JOIN app_dat_extraccion_productos ep ON o.id = ep.id_operacion
        JOIN app_dat_estado_operacion eo ON o.id = eo.id_operacion
        WHERE o.id_tienda = p_id_tienda
          AND eo.estado = 2   -- solo completadas
          AND eo.id = (SELECT MAX(id) FROM app_dat_estado_operacion WHERE id_operacion = o.id)
          AND ov.es_pagada = true
          AND o.id_tipo_operacion = (
                SELECT id FROM app_nom_tipo_operacion
                WHERE LOWER(denominacion) = 'venta'
              )
          AND (p_fecha_desde IS NULL OR o.created_at::DATE >= p_fecha_desde)
          AND (p_fecha_hasta IS NULL OR o.created_at::DATE <= p_fecha_hasta)
          AND (p_id_almacen IS NULL OR ep.id_ubicacion IN (
                SELECT id FROM app_dat_layout_almacen WHERE id_almacen = p_id_almacen
              ))
          AND ep.cantidad > 0
    ),

    -- -------------------------------------------------------------------------
    -- 2. Para cada línea: precio de venta vigente en la fecha de la operación
    --    Se toma el registro de app_dat_precio_venta cuyo rango de fechas
    --    engloba la fecha de la operación.  Si no hay, se usa NULL (se
    --    resolverá con el importe registrado como fallback).
    --    Nota: el precio se redondea a 2 decimales para evitar fragmentación
    --    de grupos por diferencias de punto flotante en el fallback.
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
            pv.created_at DESC   -- en caso de solapamiento, el más reciente
    ),

    -- -------------------------------------------------------------------------
    -- 3. Tasa de cambio USD→CUP vigente en cada fecha de operación
    --    Se busca en tasa_cambio_extraoficial la tasa activa más reciente
    --    que no supere la fecha de la operación.
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
    -- 4. Costo unitario en USD por producto/presentación
    --    Se usa precio_promedio de app_dat_producto_presentacion (costo
    --    promedio ponderado acumulado, en USD).
    --    Fallback: último costo de recepción.
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
    -- 5. Enriquecer cada línea de venta con precio y tasa históricos
    -- -------------------------------------------------------------------------
    ventas_enriquecidas AS (
        SELECT
            vd.id_producto,
            vd.id_variante,
            vd.id_presentacion,
            vd.cantidad,
            vd.importe,
            vd.fecha_op,

            -- Precio de venta CUP vigente en la fecha; fallback: importe/cantidad
            -- Redondeado a 2 decimales para evitar fragmentación por punto flotante.
            ROUND(COALESCE(
                pvh.precio_cup_historico,
                CASE WHEN vd.cantidad > 0 THEN (vd.importe / vd.cantidad)::NUMERIC ELSE 0 END
            ), 2) AS precio_venta_cup_op,

            -- Tasa vigente en la fecha; fallback: tasa actual de tasas_conversion
            COALESCE(
                th.tasa_cup,
                (SELECT tasa FROM tasas_conversion
                 WHERE moneda_origen = 'USD' AND moneda_destino = 'CUP'
                 ORDER BY fecha_actualizacion DESC LIMIT 1)
            ) AS tasa_op,

            -- Costo unitario en USD (precio_promedio de presentacion > recepción)
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
    -- 5b. Costo por receta para productos elaborados/servicios.
    --     Costo unitario del ingrediente = precio_promedio de
    --     app_dat_producto_presentacion (precio promedio ponderado acumulado, USD),
    --     dividido por cantidad_um de app_dat_presentacion_unidad_medida para
    --     obtener el costo por unidad base, multiplicado por cantidad_necesaria.
    -- -------------------------------------------------------------------------
    costo_receta_usd AS (
        SELECT
            pi.id_producto_elaborado AS id_producto,
            SUM(
                COALESCE(pi.cantidad_necesaria, 0) *
                -- costo por unidad base = precio_promedio / cantidad_por_presentacion
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
    --    Cada combinación distinta de (precio_venta, costo_cup) genera una fila
    --    separada, capturando tanto cambios de precio de venta como cambios de
    --    tasa o de costo USD que resulten en un costo CUP diferente.
    -- -------------------------------------------------------------------------
    agregado AS (
        SELECT
            ve.id_producto,
            ve.id_variante,
            ve.id_presentacion,
            ve.precio_venta_cup_op,                                          -- clave 1: precio de venta
            ROUND((ve.costo_usd_op * ve.tasa_op)::NUMERIC, 2) AS costo_cup_op, -- clave 2: costo CUP unitario
            ve.costo_usd_op,                                                 -- para exponer en resultado
            ve.tasa_op,                                                      -- para exponer en resultado
            SUM(ve.cantidad)                                          AS total_vendido,

            -- Ingresos: precio × cantidad (mismo precio en todo el grupo)
            SUM(ve.precio_venta_cup_op * ve.cantidad)                AS ingresos_totales,

            -- Costo total: costo_cup_op × cantidad (mismo costo CUP en todo el grupo)
            SUM(ve.costo_usd_op * ve.tasa_op * ve.cantidad)          AS costo_total_vendido,

            AVG(ve.tasa_op)                                           AS tasa_promedio

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
    -- 7. Resultado final con datos del producto y proveedor
    -- -------------------------------------------------------------------------
    SELECT
        p.id_tienda,
        p.id                                              AS id_producto,
        p.denominacion::VARCHAR                           AS nombre_producto,
        COALESCE(p.id_proveedor, 0)::BIGINT               AS id_proveedor,
        COALESCE(prov.denominacion, 'Sin Proveedor')::VARCHAR AS nombre_proveedor,

        -- Precio de venta CUP exacto de este grupo
        ROUND(ag.precio_venta_cup_op::NUMERIC, 2)                  AS precio_venta_cup,

        -- Costo unitario en USD: para elaborados/servicios usar receta; si no, precio_promedio
        ROUND(COALESCE(
            CASE WHEN (p.es_elaborado OR p.es_servicio) THEN cr.costo_receta_usd END,
            ag.costo_usd_op
        )::NUMERIC, 4)                                             AS precio_costo,

        -- Tasa exacta del grupo
        ROUND(ag.tasa_op::NUMERIC, 2)                              AS valor_usd,

        -- Costo unitario en CUP: para elaborados/servicios usar receta × tasa; si no, costo_cup_op
        ROUND(COALESCE(
            CASE WHEN (p.es_elaborado OR p.es_servicio)
                THEN cr.costo_receta_usd * ag.tasa_promedio
            END,
            ag.costo_cup_op
        )::NUMERIC, 2)                                             AS precio_costo_cup,

        ag.total_vendido,
        ROUND(ag.ingresos_totales::NUMERIC, 2)                     AS ingresos_totales,

        -- Costo total vendido: para elaborados/servicios recalcular con receta
        ROUND(COALESCE(
            CASE WHEN (p.es_elaborado OR p.es_servicio)
                THEN cr.costo_receta_usd * ag.tasa_promedio * ag.total_vendido
            END,
            ag.costo_total_vendido
        )::NUMERIC, 2)                                             AS costo_total_vendido,

        -- Ganancia unitaria
        ROUND((
            ag.precio_venta_cup_op - COALESCE(
                CASE WHEN (p.es_elaborado OR p.es_servicio)
                    THEN cr.costo_receta_usd * ag.tasa_promedio
                END,
                ag.costo_cup_op
            )
        )::NUMERIC, 2)                                             AS ganancia_unitaria,

        -- Ganancia total
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

-- Permisos
GRANT EXECUTE ON FUNCTION public.fn_reporte_ventas_con_proveedor4(BIGINT, DATE, DATE, BIGINT)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_reporte_ventas_con_proveedor4(BIGINT, DATE, DATE, BIGINT)
    TO service_role;
