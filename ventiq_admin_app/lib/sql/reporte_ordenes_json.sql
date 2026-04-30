-- =============================================================================
-- FUNCIÓN: reporte_ordenes_json (versión optimizada)
-- Técnicas aplicadas:
--   · LANGUAGE sql + STABLE  → el planner puede optimizar/inlinear
--   · CTEs pre-agregadas      → un solo scan por tabla (items, pagos, descuentos)
--   · DISTINCT ON             → último estado/descuento sin subquery correlacionado
--   · FILTER clause           → un único jsonb_agg produce ambos arrays en un paso
--   · Flag booleano es_completa calculado una sola vez en la CTE base
--   · VALUES + jsonb_agg      → razones de incompletitud sin UNION ALL
-- =============================================================================
CREATE OR REPLACE FUNCTION public.reporte_ordenes_json(
    p_id_tienda   bigint,                          -- OBLIGATORIO
    p_fecha_desde timestamptz DEFAULT NULL,
    p_fecha_hasta timestamptz DEFAULT NULL,
    p_id_tpv      bigint      DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
WITH

-- ── 1. Parámetros resueltos (referenciados una sola vez) ────────────────────
params AS MATERIALIZED (
    SELECT
        COALESCE($2, CURRENT_TIMESTAMP - INTERVAL '30 days') AS fecha_desde,
        COALESCE($3, CURRENT_TIMESTAMP)                       AS fecha_hasta
),

-- ── 2. ID del tipo operación "Venta" ───────────────────────────────────────
tipo_venta AS (
    SELECT id
    FROM   app_nom_tipo_operacion
    WHERE  LOWER(denominacion) = 'venta'
    LIMIT  1
),

-- ── 3. Base filtrada (MUY IMPORTANTE PARA RENDIMIENTO) ──────────────────────
base_ops AS (
    SELECT 
        o.id,
        o.created_at,
        o.uuid,
        o.id_tienda,
        ov.id_operacion AS id_operacion_venta,
        ov.id_tpv,
        ov.id_cliente,
        ov.importe_total,
        ov.es_pagada
    FROM app_dat_operaciones o
    CROSS JOIN tipo_venta tv
    LEFT JOIN app_dat_operacion_venta ov ON ov.id_operacion = o.id
    WHERE o.id_tipo_operacion = tv.id
      AND o.id_tienda = $1
      AND o.created_at >= COALESCE($2, CURRENT_TIMESTAMP - INTERVAL '30 days')
      AND o.created_at <= COALESCE($3, CURRENT_TIMESTAMP)
      AND ($4 IS NULL OR ov.id_tpv = $4)
),

-- ── 4. Último estado por operación  ─────────────────────────────────────────
ultimo_estado AS (
    SELECT DISTINCT ON (eo.id_operacion)
        eo.id_operacion,
        eo.estado
    FROM  app_dat_estado_operacion eo
    JOIN  base_ops bo ON eo.id_operacion = bo.id
    ORDER BY eo.id_operacion, eo.id DESC
),

-- ── 5. Nombre completo del trabajador por UUID ──────────────────────────────
trabajadores AS (
    SELECT uuid, nombres || ' ' || apellidos AS nombre_completo
    FROM   app_dat_trabajadores
    WHERE  uuid IN (SELECT DISTINCT uuid FROM base_ops WHERE uuid IS NOT NULL)
),

-- ── 6. Descuento más reciente por operación ─────────────────────────────────
descuento_reciente AS (
    SELECT DISTINCT ON (dv.id_operacion)
        dv.id_operacion,
        jsonb_build_object(
            'monto_real',       dv.monto_real,
            'monto_descontado', dv.monto_descontado,
            'tipo_descuento',   dv.tipo_descuento,
            'valor_descuento',  dv.valor_descuento
        ) AS descuento_json
    FROM  app_dat_descuentos_vendedor dv
    JOIN  base_ops bo ON dv.id_operacion = bo.id
    ORDER BY dv.id_operacion, dv.created_at DESC
),

-- ── 7. Items pre-agregados por operación ────────────────────────────────────
items_agg AS (
    SELECT
        ep.id_operacion,
        COUNT(*)::integer                                        AS cantidad_items,
        COALESCE(SUM(ep.importe), 0)                             AS total_operacion,
        -- Cuántos items NO tienen inventario_producto
        COUNT(*) FILTER (WHERE ip.id IS NULL)::integer           AS items_sin_inventario,
        jsonb_agg(
            jsonb_build_object(
                'id_extraccion',    ep.id,
                'id_producto',      ep.id_producto,
                'producto_nombre',  p.denominacion,
                'cantidad',         ep.cantidad,
                'precio_unitario',  ep.precio_unitario,
                'importe',          ep.importe,
                'es_elaborado',     p.es_elaborado,
                'tiene_inventario', (ip.id IS NOT NULL),
                'inventario', CASE
                    WHEN ip.id IS NOT NULL THEN jsonb_build_object(
                        'id_inventario',    ip.id,
                        'cantidad_inicial', ip.cantidad_inicial,
                        'cantidad_final',   ip.cantidad_final,
                        'origen_cambio',    ip.origen_cambio,
                        'created_at',       ip.created_at
                    )
                    ELSE NULL
                END,
                'variante', CASE
                    WHEN ep.id_variante IS NOT NULL THEN jsonb_build_object(
                        'id',      ep.id_variante,
                        'atributo', atr.denominacion,
                        'opcion',   aop.valor
                    )
                    ELSE NULL
                END,
                'presentacion', np.denominacion
            ) ORDER BY ep.id
        ) AS items_json
    FROM  base_ops bo
    JOIN  app_dat_extraccion_productos ep ON ep.id_operacion = bo.id
    JOIN  app_dat_producto              p   ON ep.id_producto        = p.id
    LEFT JOIN app_dat_inventario_productos ip  ON ip.id_extraccion   = ep.id
    LEFT JOIN app_dat_variantes            var ON ep.id_variante      = var.id
    LEFT JOIN app_dat_atributos            atr ON var.id_atributo     = atr.id
    LEFT JOIN app_dat_atributo_opcion      aop ON ep.id_opcion_variante = aop.id
    LEFT JOIN app_dat_producto_presentacion pp  ON ep.id_presentacion = pp.id
    LEFT JOIN app_nom_presentacion          np  ON pp.id_presentacion  = np.id
    GROUP BY ep.id_operacion
),

-- ── 8. Pagos pre-agregados por operación ────────────────────────────────────
pagos_agg AS (
    SELECT
        pv.id_operacion_venta,
        jsonb_agg(
            jsonb_build_object(
                'medio_pago',            mp.denominacion,
                'monto',                 pv.monto,
                'importe_sin_descuento', pv.importe_sin_descuento,
                'referencia_pago',       pv.referencia_pago,
                'fecha_pago',            pv.fecha_pago,
                'es_digital',            mp.es_digital,
                'es_efectivo',           mp.es_efectivo
            )
        ) AS pagos_json
    FROM  base_ops bo
    JOIN  app_dat_pago_venta pv ON pv.id_operacion_venta = bo.id_operacion_venta
    JOIN  app_nom_medio_pago mp ON pv.id_medio_pago = mp.id
    WHERE mp.es_activo = true
    GROUP BY pv.id_operacion_venta
),

-- ── 8. Consulta base: UN solo scan sobre app_dat_operaciones ─────────────────
-- ── 9. Consulta base final ──────────────────────────────────────────────────
base AS (
    SELECT
        o.id,
        o.created_at,
        o.uuid,
        o.id_tienda,
        t.denominacion                                              AS tienda_nombre,
        COALESCE(tr.nombre_completo, u.email, 'Sistema')           AS vendedor_nombre,
        u.email                                                     AS vendedor_email,
        ue.estado                                                   AS ultimo_estado,
        -- Venta
        (o.id_operacion_venta IS NOT NULL)                          AS tiene_venta,
        o.id_tpv,
        tpv.denominacion                                            AS tpv_nombre,
        o.id_cliente,
        cli.nombre_completo                                         AS cliente_nombre,
        cli.telefono                                                AS cliente_telefono,
        o.importe_total,
        o.es_pagada,
        -- Items y pagos pre-agregados
        COALESCE(ia.cantidad_items,      0)                         AS cantidad_items,
        COALESCE(ia.total_operacion,     0)                         AS total_operacion,
        COALESCE(ia.items_sin_inventario,0)                         AS items_sin_inventario,
        ia.items_json,
        pa.pagos_json,
        dr.descuento_json,
        -- ── Flag de completitud (calculado una sola vez) ──────────────────
        (
            o.id_operacion_venta IS NOT NULL              -- tiene operacion_venta
            AND COALESCE(ia.cantidad_items,      0) > 0   -- tiene items
            AND COALESCE(ia.items_sin_inventario,0) = 0   -- todos con inventario
        ) AS es_completa

    FROM  base_ops o
    JOIN   app_dat_tienda             t    ON o.id_tienda          = t.id
    LEFT JOIN auth.users              u    ON o.uuid               = u.id
    LEFT JOIN trabajadores            tr   ON tr.uuid              = o.uuid
    LEFT JOIN ultimo_estado           ue   ON ue.id_operacion      = o.id
    LEFT JOIN app_dat_tpv             tpv  ON o.id_tpv             = tpv.id
    LEFT JOIN app_dat_clientes        cli  ON o.id_cliente         = cli.id
    LEFT JOIN items_agg               ia   ON ia.id_operacion      = o.id
    LEFT JOIN pagos_agg               pa   ON pa.id_operacion_venta = o.id_operacion_venta
    LEFT JOIN descuento_reciente      dr   ON dr.id_operacion      = o.id
),

-- ── 9. Construcción del documento JSON por orden ─────────────────────────────
orden_doc AS (
    SELECT
        es_completa,
        created_at,
        jsonb_build_object(
            'id_operacion',    id,
            'fecha_operacion', created_at,
            'tienda',          jsonb_build_object('id', id_tienda, 'nombre', tienda_nombre),
            'vendedor',        jsonb_build_object(
                                   'uuid',            uuid,
                                   'nombre_completo', vendedor_nombre,
                                   'email',           vendedor_email
                               ),
            'estado',          jsonb_build_object(
                                   'codigo', ultimo_estado,
                                   'nombre', CASE ultimo_estado
                                       WHEN 1 THEN 'Pendiente'
                                       WHEN 2 THEN 'Completada'
                                       WHEN 3 THEN 'Cancelada'
                                       WHEN 4 THEN 'En Proceso'
                                       ELSE        'Desconocido'
                                   END
                               ),
            'venta',           CASE WHEN tiene_venta THEN jsonb_build_object(
                                   'id_tpv',           id_tpv,
                                   'tpv_nombre',       tpv_nombre,
                                   'id_cliente',       id_cliente,
                                   'cliente_nombre',   cliente_nombre,
                                   'cliente_telefono', cliente_telefono,
                                   'importe_total',    importe_total,
                                   'es_pagada',        es_pagada
                               ) ELSE NULL END,
            'total_operacion', total_operacion,
            'cantidad_items',  cantidad_items,
            'items',           COALESCE(items_json, '[]'::jsonb),
            'pagos',           COALESCE(pagos_json, '[]'::jsonb),
            'descuento',       descuento_json,
            -- Razones solo para incompletas (VALUES evita UNION ALL)
            'razones_incompletitud', CASE WHEN NOT es_completa THEN (
                SELECT jsonb_agg(r)
                FROM (VALUES
                    (CASE WHEN NOT tiene_venta
                               THEN 'SIN_OPERACION_VENTA'    END),
                    (CASE WHEN tiene_venta AND cantidad_items = 0
                               THEN 'SIN_ITEMS_EXTRACCION'   END),
                    (CASE WHEN items_sin_inventario > 0
                               THEN 'SIN_INVENTARIO_EN_ITEMS' END)
                ) t(r)
                WHERE r IS NOT NULL
            ) ELSE NULL END
        ) AS doc
    FROM base
)

-- ── 10. Un único SELECT con FILTER → dos arrays en un solo paso ───────────────
SELECT jsonb_build_object(
    'periodo', jsonb_build_object(
        'fecha_desde', (SELECT fecha_desde FROM params),
        'fecha_hasta', (SELECT fecha_hasta FROM params)
    ),
    'resumen', jsonb_build_object(
        'total_completas',   COUNT(*) FILTER (WHERE     es_completa),
        'total_incompletas', COUNT(*) FILTER (WHERE NOT es_completa)
    ),
    'ordenes_completas',
        COALESCE(
            jsonb_agg(doc ORDER BY created_at DESC) FILTER (WHERE     es_completa),
            '[]'::jsonb
        ),
    'ordenes_incompletas',
        COALESCE(
            jsonb_agg(doc ORDER BY created_at DESC) FILTER (WHERE NOT es_completa),
            '[]'::jsonb
        )
)
FROM orden_doc;
$$;

-- =============================================================================
-- GRANT (ajusta según tus roles)
-- =============================================================================
-- GRANT EXECUTE ON FUNCTION public.reporte_ordenes_json(timestamptz,timestamptz,bigint,bigint)
--   TO authenticated;

-- =============================================================================
-- EJEMPLOS DE USO
-- =============================================================================
-- SELECT reporte_ordenes_json(5);                                          -- tienda 5, últimos 30 días
-- SELECT reporte_ordenes_json(5, '2026-04-01','2026-04-30');               -- tienda 5, rango
-- SELECT reporte_ordenes_json(5, NULL, NULL, 3);                           -- tienda 5, TPV 3
-- SELECT reporte_ordenes_json(5)->'ordenes_incompletas';                   -- solo incompletas
-- SELECT reporte_ordenes_json(5)->'resumen';                               -- totales
-- =============================================================================
