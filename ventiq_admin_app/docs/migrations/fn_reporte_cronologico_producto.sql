CREATE OR REPLACE FUNCTION public.fn_reporte_cronologico_producto(
    p_id_tienda BIGINT,
    p_id_producto BIGINT,
    p_fecha_desde DATE DEFAULT NULL,
    p_fecha_hasta DATE DEFAULT NULL,
    p_filtro_fecha TEXT DEFAULT 'creacion'
)
RETURNS TABLE (
    evento_fecha TIMESTAMPTZ,
    tipo_evento TEXT,
    id_operacion BIGINT,
    cantidad NUMERIC,
    precio_venta_cup NUMERIC,
    precio_costo_usd NUMERIC,
    tasa_cambio NUMERIC,
    precio_costo_cup NUMERIC,
    ingreso_total NUMERIC,
    costo_total NUMERIC,
    ganancia_total NUMERIC,
    valor_anterior NUMERIC,
    valor_nuevo NUMERIC,
    descripcion TEXT
)
LANGUAGE sql
SECURITY DEFINER
AS $$
WITH ventas_base AS (
    SELECT
        CASE
            WHEN LOWER(COALESCE(p_filtro_fecha, 'creacion')) = 'completado'
                THEN estado_actual.created_at
            ELSE o.created_at
        END AS fecha_evento,
        o.id AS operacion_id,
        ep.id_presentacion,
        SUM(ep.cantidad)::NUMERIC AS cantidad,
        SUM(ep.importe)::NUMERIC AS importe
    FROM app_dat_operaciones o
    JOIN app_dat_operacion_venta ov
      ON ov.id_operacion = o.id
     AND ov.es_pagada = TRUE
    JOIN app_dat_extraccion_productos ep
      ON ep.id_operacion = o.id
     AND ep.id_producto = p_id_producto
    CROSS JOIN LATERAL (
        SELECT eo.estado, eo.created_at
        FROM app_dat_estado_operacion eo
        WHERE eo.id_operacion = o.id
        ORDER BY eo.id DESC
        LIMIT 1
    ) estado_actual
    WHERE o.id_tienda = p_id_tienda
      AND estado_actual.estado = 2
      AND ep.cantidad > 0
      AND (p_fecha_desde IS NULL OR
           (CASE WHEN LOWER(COALESCE(p_filtro_fecha, 'creacion')) = 'completado'
                 THEN estado_actual.created_at ELSE o.created_at END)::DATE >= p_fecha_desde)
      AND (p_fecha_hasta IS NULL OR
           (CASE WHEN LOWER(COALESCE(p_filtro_fecha, 'creacion')) = 'completado'
                 THEN estado_actual.created_at ELSE o.created_at END)::DATE <= p_fecha_hasta)
    GROUP BY
        CASE
            WHEN LOWER(COALESCE(p_filtro_fecha, 'creacion')) = 'completado'
                THEN estado_actual.created_at
            ELSE o.created_at
        END,
        o.id,
        ep.id_presentacion
),
ventas AS (
    SELECT
        vb.fecha_evento,
        vb.operacion_id,
        vb.cantidad,
        CASE WHEN vb.cantidad > 0 THEN vb.importe / vb.cantidad ELSE 0 END AS precio_venta,
        CASE
            WHEN (COALESCE(p.es_elaborado, FALSE) OR COALESCE(p.es_servicio, FALSE))
                 AND receta.costo_usd IS NOT NULL
                THEN receta.costo_usd
            ELSE COALESCE(costo.precio_costo_usd, pp.precio_promedio, 0)::NUMERIC
        END AS costo_usd,
        COALESCE(tasa.valor_cambio, tasa_fallback.tasa, 1)::NUMERIC AS tasa
    FROM ventas_base vb
    JOIN app_dat_producto p ON p.id = p_id_producto
    LEFT JOIN app_dat_producto_presentacion pp ON pp.id = vb.id_presentacion
    LEFT JOIN LATERAL (
        SELECT pc.precio_costo_usd
        FROM app_dat_precio_costo pc
        WHERE pc.id_presentacion = vb.id_presentacion
          AND pc.created_at <= vb.fecha_evento
        ORDER BY pc.created_at DESC
        LIMIT 1
    ) costo ON TRUE
    LEFT JOIN LATERAL (
        SELECT SUM(
            COALESCE(pi.cantidad_necesaria, 0) *
            COALESCE(ingrediente.costo_usd / NULLIF(ingrediente.cantidad_um, 0), 0)
        )::NUMERIC AS costo_usd
        FROM app_dat_producto_ingredientes pi
        LEFT JOIN LATERAL (
            SELECT
                COALESCE(historial.precio_costo_usd, ipp.precio_promedio, 0)::NUMERIC AS costo_usd,
                COALESCE((
                    SELECT pum.cantidad_um
                    FROM app_dat_presentacion_unidad_medida pum
                    WHERE pum.id_producto = pi.id_ingrediente
                    LIMIT 1
                ), 1)::NUMERIC AS cantidad_um
            FROM app_dat_producto_presentacion ipp
            LEFT JOIN LATERAL (
                SELECT ipc.precio_costo_usd
                FROM app_dat_precio_costo ipc
                WHERE ipc.id_presentacion = ipp.id
                  AND ipc.created_at <= vb.fecha_evento
                ORDER BY ipc.created_at DESC
                LIMIT 1
            ) historial ON TRUE
            WHERE ipp.id_producto = pi.id_ingrediente
            ORDER BY ipp.es_base DESC NULLS LAST, ipp.id ASC
            LIMIT 1
        ) ingrediente ON TRUE
        WHERE pi.id_producto_elaborado = p_id_producto
    ) receta ON TRUE
    LEFT JOIN LATERAL (
        SELECT tc.valor_cambio
        FROM tasa_cambio_extraoficial tc
        WHERE tc.id_tienda = p_id_tienda
          AND tc.activo = TRUE
          AND tc.created_at <= vb.fecha_evento
        ORDER BY tc.created_at DESC
        LIMIT 1
    ) tasa ON TRUE
    LEFT JOIN LATERAL (
        SELECT tc.tasa
        FROM tasas_conversion tc
        WHERE tc.moneda_origen = 'USD'
          AND tc.moneda_destino = 'CUP'
          AND tc.fecha_actualizacion <= vb.fecha_evento
        ORDER BY tc.fecha_actualizacion DESC
        LIMIT 1
    ) tasa_fallback ON TRUE
),
precios_venta AS (
    SELECT
        pv.created_at AS fecha_evento,
        pv.precio_venta_cup::NUMERIC AS valor_nuevo,
        LAG(pv.precio_venta_cup::NUMERIC) OVER (
            PARTITION BY pv.id_producto, COALESCE(pv.id_variante, 0)
            ORDER BY pv.created_at, pv.id
        ) AS valor_anterior
    FROM app_dat_precio_venta pv
    WHERE pv.id_producto = p_id_producto
),
costos_base AS (
    SELECT
        pc.created_at AS fecha_evento,
        pc.precio_costo_usd::NUMERIC AS valor_nuevo,
        LAG(pc.precio_costo_usd::NUMERIC) OVER (
            PARTITION BY pc.id_presentacion
            ORDER BY pc.created_at, pc.id
        ) AS valor_anterior,
        pp.id_producto = p_id_producto AS es_costo_directo,
        ingrediente.denominacion::TEXT AS ingrediente,
        COALESCE(np.denominacion, 'Presentación #' || pp.id)::TEXT AS presentacion,
        pi.cantidad_necesaria::NUMERIC AS cantidad_necesaria,
        COALESCE((
            SELECT pum.cantidad_um
            FROM app_dat_presentacion_unidad_medida pum
            WHERE pum.id_producto = pp.id_producto
            LIMIT 1
        ), 1)::NUMERIC AS cantidad_um
    FROM app_dat_precio_costo pc
    JOIN app_dat_producto_presentacion pp ON pp.id = pc.id_presentacion
    LEFT JOIN app_nom_presentacion np ON np.id = pp.id_presentacion
    LEFT JOIN app_dat_producto_ingredientes pi
      ON pi.id_ingrediente = pp.id_producto
     AND pi.id_producto_elaborado = p_id_producto
    LEFT JOIN app_dat_producto ingrediente ON ingrediente.id = pi.id_ingrediente
    WHERE pp.id_producto = p_id_producto
       OR (
            pi.id_producto_elaborado IS NOT NULL
            AND pp.id = (
                SELECT pp_base.id
                FROM app_dat_producto_presentacion pp_base
                WHERE pp_base.id_producto = pi.id_ingrediente
                ORDER BY pp_base.es_base DESC NULLS LAST, pp_base.id ASC
                LIMIT 1
            )
       )
),
costos AS (
    SELECT
        cb.fecha_evento,
        cb.valor_nuevo,
        cb.valor_anterior,
        CASE
            WHEN cb.es_costo_directo THEN
                'Costo unitario del producto. Presentación: ' || cb.presentacion ||
                '. Costo USD: ' || COALESCE(ROUND(cb.valor_anterior, 4)::TEXT, 'Sin anterior') ||
                ' → ' || ROUND(cb.valor_nuevo, 4)::TEXT
            ELSE
                'Ingrediente: ' || cb.ingrediente ||
                '. Presentación usada: ' || cb.presentacion ||
                '. Cantidad en receta: ' || COALESCE(cb.cantidad_necesaria::TEXT, '0') ||
                '. Contenido de la presentación (cantidad_um): ' || cb.cantidad_um::TEXT ||
                '. Fórmula: cantidad receta × (costo presentación ÷ cantidad_um). ' ||
                'Aporte anterior: ' ||
                COALESCE(ROUND(cb.cantidad_necesaria * cb.valor_anterior / NULLIF(cb.cantidad_um, 0), 4)::TEXT, 'Sin anterior') ||
                ' USD. Aporte nuevo: ' ||
                COALESCE(ROUND(cb.cantidad_necesaria * cb.valor_nuevo / NULLIF(cb.cantidad_um, 0), 4)::TEXT, '0') ||
                ' USD.'
        END::TEXT AS descripcion
    FROM costos_base cb
),
eventos AS (
    SELECT
        v.fecha_evento AS evento_fecha,
        'venta'::TEXT AS tipo_evento,
        v.operacion_id::BIGINT AS id_operacion,
        ROUND(v.cantidad, 4) AS cantidad,
        ROUND(v.precio_venta, 2) AS precio_venta_cup,
        ROUND(v.costo_usd, 4) AS precio_costo_usd,
        ROUND(v.tasa, 2) AS tasa_cambio,
        ROUND(v.costo_usd * v.tasa, 2) AS precio_costo_cup,
        ROUND(v.precio_venta * v.cantidad, 2) AS ingreso_total,
        ROUND(v.costo_usd * v.tasa * v.cantidad, 2) AS costo_total,
        ROUND((v.precio_venta - v.costo_usd * v.tasa) * v.cantidad, 2) AS ganancia_total,
        NULL::NUMERIC AS valor_anterior,
        NULL::NUMERIC AS valor_nuevo,
        ('Venta #' || v.operacion_id)::TEXT AS descripcion
    FROM ventas v

    UNION ALL

    SELECT
        pv.fecha_evento,
        'cambio_precio_venta'::TEXT,
        NULL::BIGINT,
        NULL::NUMERIC,
        ROUND(pv.valor_nuevo, 2),
        NULL::NUMERIC,
        NULL::NUMERIC,
        NULL::NUMERIC,
        NULL::NUMERIC,
        NULL::NUMERIC,
        NULL::NUMERIC,
        ROUND(pv.valor_anterior, 2),
        ROUND(pv.valor_nuevo, 2),
        'Cambio de precio de venta'::TEXT
    FROM precios_venta pv
    WHERE (p_fecha_desde IS NULL OR pv.fecha_evento::DATE >= p_fecha_desde)
      AND (p_fecha_hasta IS NULL OR pv.fecha_evento::DATE <= p_fecha_hasta)

    UNION ALL

    SELECT
        c.fecha_evento,
        'cambio_precio_costo'::TEXT,
        NULL::BIGINT,
        NULL::NUMERIC,
        NULL::NUMERIC,
        ROUND(c.valor_nuevo, 4),
        NULL::NUMERIC,
        NULL::NUMERIC,
        NULL::NUMERIC,
        NULL::NUMERIC,
        NULL::NUMERIC,
        ROUND(c.valor_anterior, 4),
        ROUND(c.valor_nuevo, 4),
        c.descripcion
    FROM costos c
    WHERE (p_fecha_desde IS NULL OR c.fecha_evento::DATE >= p_fecha_desde)
      AND (p_fecha_hasta IS NULL OR c.fecha_evento::DATE <= p_fecha_hasta)
)
SELECT
    e.evento_fecha,
    e.tipo_evento,
    e.id_operacion,
    e.cantidad,
    e.precio_venta_cup,
    e.precio_costo_usd,
    e.tasa_cambio,
    e.precio_costo_cup,
    e.ingreso_total,
    e.costo_total,
    e.ganancia_total,
    e.valor_anterior,
    e.valor_nuevo,
    e.descripcion
FROM eventos e
ORDER BY e.evento_fecha ASC, e.tipo_evento ASC;
$$;

GRANT EXECUTE ON FUNCTION public.fn_reporte_cronologico_producto(BIGINT, BIGINT, DATE, DATE, TEXT)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_reporte_cronologico_producto(BIGINT, BIGINT, DATE, DATE, TEXT)
    TO service_role;
