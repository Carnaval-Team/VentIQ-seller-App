-- ============================================================================
-- 48 · Precio/costo unitarios en unidades base + reporte por turno con
--      presentaciones — APLICADO en newa y en Main.
-- ============================================================================
-- Corrige dos huecos para empezar a vender en presentaciones no-base:
--
-- 1) v5 debe preservar el desglose de la v4: UNA FILA por cada combinación
--    distinta de precio_venta_cup + precio_costo_cup (y presentación interna
--    de v4). No compactar todo el producto en un promedio.
--    Unitarios e ingresos vienen de la fila v4 (precio cobrado / importes).
--    equiv_unidades_base ≈ total_vendido de ESA fila.
--
-- 2) El filtro "Turnos" de Tiempo Real llamaba a
--    `fn_reporte_ventas_con_proveedor_por_turno` SIN columnas de presentación
--    y emparejando turnos por rango de IDs. Se crea la v2 con el mismo
--    contrato de columnas que la v5. Posteriormente (fix_reportes_turnos_
--    ventana_solapada.sql) se decidió que el reporte liste las operaciones
--    por FECHA, sin depender de turnos.
--
-- La v4 / por_turno original NO se tocan.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- A · Parche de v5: unitarios en base (equiv), no en cantidad física
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_reporte_ventas_con_proveedor5(
    p_id_tienda    bigint,
    p_fecha_desde  date    DEFAULT NULL::date,
    p_fecha_hasta  date    DEFAULT NULL::date,
    p_id_almacen   bigint  DEFAULT NULL::bigint,
    p_filtro_fecha text    DEFAULT 'creacion'::text
)
RETURNS TABLE (
    id_tienda                   bigint,
    id_producto                 bigint,
    nombre_producto             character varying,
    id_proveedor                bigint,
    nombre_proveedor            character varying,
    precio_venta_cup            numeric,
    precio_costo                numeric,
    valor_usd                   numeric,
    precio_costo_cup            numeric,
    total_vendido               numeric,
    ingresos_totales            numeric,
    costo_total_vendido         numeric,
    ganancia_unitaria           numeric,
    ganancia_total              numeric,
    es_elaborado                boolean,
    es_servicio                 boolean,
    cantidades_por_presentacion jsonb,
    equiv_unidades_base         numeric,
    cantidad_formateada         text,
    n_presentaciones            integer,
    n_precios_distintos         integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_filtro_fecha  text := lower(coalesce(nullif(trim(p_filtro_fecha), ''), 'creacion'));
    v_id_tipo_venta bigint;
BEGIN
    PERFORM public.check_user_has_access_to_tienda(p_id_tienda);

    IF v_filtro_fecha NOT IN ('creacion', 'completado') THEN
        v_filtro_fecha := 'creacion';
    END IF;

    SELECT id INTO v_id_tipo_venta
      FROM app_nom_tipo_operacion
     WHERE lower(denominacion) = 'venta'
     LIMIT 1;

    IF v_id_tipo_venta IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY
    WITH
    base AS MATERIALIZED (
        SELECT * FROM public.fn_reporte_ventas_con_proveedor4(
            p_id_tienda, p_fecha_desde, p_fecha_hasta, p_id_almacen, p_filtro_fecha
        )
    ),

    -- Una fila por cada combinación precio_venta + costo de la v4 (sin promediar).
    filas AS (
        SELECT
            b.id_tienda,
            b.id_producto,
            b.nombre_producto,
            b.id_proveedor,
            b.nombre_proveedor,
            b.precio_venta_cup,
            b.precio_costo,
            b.valor_usd,
            b.precio_costo_cup,
            b.total_vendido,
            b.ingresos_totales,
            b.costo_total_vendido,
            b.ganancia_unitaria,
            b.ganancia_total,
            b.es_elaborado,
            b.es_servicio,
            1::integer AS n_precios_distintos
        FROM base b
    )

    SELECT
        f.id_tienda,
        f.id_producto,
        f.nombre_producto,
        f.id_proveedor,
        f.nombre_proveedor,
        ROUND(f.precio_venta_cup::numeric, 2) AS precio_venta_cup,
        ROUND(f.precio_costo::numeric, 4) AS precio_costo,
        ROUND(f.valor_usd::numeric, 2) AS valor_usd,
        ROUND(f.precio_costo_cup::numeric, 2) AS precio_costo_cup,
        f.total_vendido,
        ROUND(f.ingresos_totales::numeric, 2) AS ingresos_totales,
        ROUND(f.costo_total_vendido::numeric, 2) AS costo_total_vendido,
        ROUND(f.ganancia_unitaria::numeric, 2) AS ganancia_unitaria,
        ROUND(f.ganancia_total::numeric, 2) AS ganancia_total,
        f.es_elaborado,
        f.es_servicio,
        '[]'::jsonb AS cantidades_por_presentacion,
        f.total_vendido AS equiv_unidades_base,
        public.fn_fmt_cantidad(f.total_vendido) AS cantidad_formateada,
        1::integer AS n_presentaciones,
        f.n_precios_distintos
    FROM filas f
    ORDER BY f.nombre_producto, f.precio_venta_cup DESC, f.precio_costo_cup DESC;
END;
$function$;

COMMENT ON FUNCTION public.fn_reporte_ventas_con_proveedor5(bigint, date, date, bigint, text) IS
'Reporte de ventas: una fila por cada precio_venta_cup + precio_costo_cup '
'(igual que v4). Precio cobrado / importes reales vía v4. '
'Columnas de presentación se rellenan por fila (equiv = total_vendido). '
'Archivo 48.';

GRANT EXECUTE ON FUNCTION public.fn_reporte_ventas_con_proveedor5(bigint, date, date, bigint, text)
    TO anon, authenticated, service_role;


-- ---------------------------------------------------------------------------
-- B · por_turno_v2: mismo contrato que v5 + ventana temporal = tab TPVs
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_reporte_ventas_con_proveedor_por_turno_v2(
    p_id_tienda   bigint,
    p_fecha_desde date DEFAULT NULL::date,
    p_fecha_hasta date DEFAULT NULL::date,
    p_id_almacen  bigint DEFAULT NULL::bigint
)
RETURNS TABLE (
    id_tienda                   bigint,
    id_producto                 bigint,
    nombre_producto             character varying,
    id_proveedor                bigint,
    nombre_proveedor            character varying,
    precio_venta_cup            numeric,
    precio_costo                numeric,
    valor_usd                   numeric,
    precio_costo_cup            numeric,
    total_vendido               numeric,
    ingresos_totales            numeric,
    costo_total_vendido         numeric,
    ganancia_unitaria           numeric,
    ganancia_total              numeric,
    es_elaborado                boolean,
    es_servicio                 boolean,
    cantidades_por_presentacion jsonb,
    equiv_unidades_base         numeric,
    cantidad_formateada         text,
    n_presentaciones            integer,
    n_precios_distintos         integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_id_tipo_venta bigint;
    v_tasa_fallback numeric;
    v_fecha_inicio  timestamptz;
    v_fecha_fin     timestamptz;
BEGIN
    PERFORM public.check_user_has_access_to_tienda(p_id_tienda);

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
    -- Operaciones de venta por FECHA (sin lógica de turnos): pagadas y
    -- completadas dentro de la ventana pedida.
    ops AS MATERIALIZED (
        SELECT DISTINCT
            o.id,
            o.created_at AS ts_op
        FROM app_dat_operaciones o
        JOIN app_dat_operacion_venta ov
          ON ov.id_operacion = o.id
         AND ov.es_pagada = true
        CROSS JOIN LATERAL (
            SELECT eo.estado
              FROM app_dat_estado_operacion eo
             WHERE eo.id_operacion = o.id
             ORDER BY eo.id DESC
             LIMIT 1
        ) e
        WHERE o.id_tipo_operacion = v_id_tipo_venta
          AND o.id_tienda = p_id_tienda
          AND o.created_at >= v_fecha_inicio
          AND o.created_at <  v_fecha_fin
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

    -- Precio de venta del reporte = cobrado en la operación (no lista histórica).

    tasa_historica AS MATERIALIZED (
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

    -- Costo de ESA presentación (newa ya lo guarda en todas).
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
        SELECT pp.id_producto, pp.id AS id_presentacion, pp.precio_promedio AS costo_unitario_usd
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
            COALESCE(
                vd.importe,
                CASE
                    WHEN vd.cantidad > 0 AND COALESCE(vd.precio_unitario, 0) > 0
                        THEN vd.cantidad * vd.precio_unitario
                    ELSE NULL
                END
            ) AS importe_op,
            ROUND(COALESCE(
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
                    ORDER BY pv.created_at DESC
                    LIMIT 1
                )
            ), 2) AS precio_venta_cup_op,
            COALESCE(th.tasa_cup, v_tasa_fallback) AS tasa_op,
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
            END::NUMERIC, 4) AS costo_usd_op
        FROM ventas_detalle vd
        JOIN app_dat_producto p ON p.id = vd.id_producto
        LEFT JOIN tasa_historica th ON th.fecha_op = vd.fecha_op
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

    -- Filas crudas (pueden partir por presentacion/precio); se compactan luego.
    filas_v4 AS (
        SELECT
            p.id_tienda,
            p.id AS id_producto,
            p.denominacion::VARCHAR AS nombre_producto,
            COALESCE(p.id_proveedor, 0)::BIGINT AS id_proveedor,
            COALESCE(prov.denominacion, 'Sin Proveedor')::VARCHAR AS nombre_proveedor,
            ROUND(ag.precio_venta_cup_op::NUMERIC, 2) AS precio_venta_cup,
            ROUND(ag.costo_usd_op::NUMERIC, 4) AS precio_costo,
            ROUND(ag.tasa_op::NUMERIC, 2) AS valor_usd,
            ag.costo_cup_op AS precio_costo_cup,
            ag.total_vendido,
            ROUND(ag.ingresos_totales::NUMERIC, 2) AS ingresos_totales,
            ROUND(ag.costo_total_vendido::NUMERIC, 2) AS costo_total_vendido,
            COALESCE(p.es_elaborado, FALSE) AS es_elaborado,
            COALESCE(p.es_servicio, FALSE) AS es_servicio
        FROM (
            SELECT
                ve.id_producto,
                ve.precio_venta_cup_op,
                ROUND((ve.costo_usd_op * ve.tasa_op)::NUMERIC, 2) AS costo_cup_op,
                ve.costo_usd_op,
                ve.tasa_op,
                SUM(ve.cantidad) AS total_vendido,
                SUM(COALESCE(ve.importe_op, ve.precio_venta_cup_op * ve.cantidad))
                    AS ingresos_totales,
                SUM(ve.costo_usd_op * ve.tasa_op * ve.cantidad) AS costo_total_vendido
            FROM ventas_enriquecidas ve
            GROUP BY
                ve.id_producto,
                ve.variante_key,
                ve.id_presentacion,
                ve.precio_venta_cup_op,
                ROUND((ve.costo_usd_op * ve.tasa_op)::NUMERIC, 2),
                ve.costo_usd_op,
                ve.tasa_op
            HAVING SUM(ve.cantidad) > 0
        ) ag
        JOIN app_dat_producto p ON ag.id_producto = p.id
        LEFT JOIN app_dat_proveedor prov ON p.id_proveedor = prov.id
        WHERE p.id_tienda = p_id_tienda
    ),

    -- Una fila por cada precio_venta + costo (sin compactar el producto).
    filas AS (
        SELECT
            b.id_tienda,
            b.id_producto,
            b.nombre_producto,
            b.id_proveedor,
            b.nombre_proveedor,
            b.precio_venta_cup,
            b.precio_costo,
            b.valor_usd,
            b.precio_costo_cup,
            b.total_vendido,
            b.ingresos_totales,
            b.costo_total_vendido,
            ROUND((b.precio_venta_cup - b.precio_costo_cup)::numeric, 2) AS ganancia_unitaria,
            ROUND((b.ingresos_totales - b.costo_total_vendido)::numeric, 2) AS ganancia_total,
            b.es_elaborado,
            b.es_servicio,
            1::integer AS n_precios_distintos
        FROM filas_v4 b
    )

    SELECT
        f.id_tienda,
        f.id_producto,
        f.nombre_producto,
        f.id_proveedor,
        f.nombre_proveedor,
        ROUND(f.precio_venta_cup::numeric, 2) AS precio_venta_cup,
        ROUND(f.precio_costo::numeric, 4) AS precio_costo,
        ROUND(f.valor_usd::numeric, 2) AS valor_usd,
        ROUND(f.precio_costo_cup::numeric, 2) AS precio_costo_cup,
        f.total_vendido,
        ROUND(f.ingresos_totales::numeric, 2),
        ROUND(f.costo_total_vendido::numeric, 2),
        f.ganancia_unitaria,
        f.ganancia_total,
        f.es_elaborado,
        f.es_servicio,
        '[]'::jsonb AS cantidades_por_presentacion,
        f.total_vendido AS equiv_unidades_base,
        public.fn_fmt_cantidad(f.total_vendido) AS cantidad_formateada,
        1::integer AS n_presentaciones,
        f.n_precios_distintos
    FROM filas f
    ORDER BY f.nombre_producto, f.precio_venta_cup DESC, f.precio_costo_cup DESC;
END;
$function$;

COMMENT ON FUNCTION public.fn_reporte_ventas_con_proveedor_por_turno_v2(bigint, date, date, bigint) IS
'Igual que fn_reporte_ventas_con_proveedor5 (una fila por precio venta + costo) '
'filtrando por turnos con la misma ventana temporal que el tab TPVs. '
'Archivo 48.';

GRANT EXECUTE ON FUNCTION public.fn_reporte_ventas_con_proveedor_por_turno_v2(bigint, date, date, bigint)
    TO anon, authenticated, service_role;
