-- ============================================================================
-- newa: traer de main las funciones que main tiene más actualizadas (4)
-- ============================================================================
-- Proyecto: SOLO newa (qhprswhhfasrikhawjoz). No ejecutar en main: allí ya existen.
-- Decisión del 19/11/2026 (docs/plan-multimoneda/analisis_8_funciones_pendientes.md):
--   3. fn_dashboard_carnaval_proveedor
--        main devuelve monto por estado, top 10 por estado con status y
--        resumen solo de órdenes Completado; la pantalla de admin lo necesita.
--   4. fn_stock_producto_almacen_detalle   (skip scan; misma lógica, 79 ms -> 0,3 ms)
--   5. fn_stock_saldos_presentacion        (skip scan + rama con lotes sin cambios)
--   6. fn_reporte_ventas_con_proveedor_por_turno
--        main cuenta por fecha de operación, igual que su v2 (la que usa el cliente).
--
-- Los cuerpos son los de main tal cual (pg_get_functiondef, 18/11/2026).
-- Misma firma y mismo RETURNS: CREATE OR REPLACE conserva permisos.
--
-- Requisito de las funciones 4 y 5: índice parcial para saber si un producto
-- maneja lotes. main lo tiene; newa no. Es parcial (WHERE id_lote IS NOT NULL) y
-- en newa casi vacío, por eso se crea aquí sin CONCURRENTLY.
-- Idempotente.
-- ============================================================================

BEGIN;

DO $chk$
BEGIN
    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION 'Ejecutar como postgres (actual: %)', current_user;
    END IF;
    -- fn_turno_alinear_fecha_apertura (R33) solo existe en newa: evita correrlo en main.
    IF to_regprocedure('public.fn_turno_alinear_fecha_apertura(bigint,timestamp with time zone)') IS NULL THEN
        RAISE EXCEPTION 'Este script es solo para newa (falta fn_turno_alinear_fecha_apertura). ¿Estás en main?';
    END IF;
    IF to_regprocedure('public.fn_presentaciones_producto(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta fn_presentaciones_producto(bigint)';
    END IF;
END
$chk$;

CREATE INDEX IF NOT EXISTS idx_inv_prod_lote_producto
    ON public.app_dat_inventario_productos (id_producto)
    WHERE id_lote IS NOT NULL;

-- ── 1/4 · fn_dashboard_carnaval_proveedor(bigint,date,date) ──
CREATE OR REPLACE FUNCTION public.fn_dashboard_carnaval_proveedor(p_id_tienda bigint, p_fecha_desde date DEFAULT ((CURRENT_DATE - '30 days'::interval))::date, p_fecha_hasta date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'carnavalapp'
AS $function$
DECLARE
    v_id_proveedor BIGINT;
    v_result       JSONB;
BEGIN
    IF p_fecha_desde > p_fecha_hasta THEN
        RAISE EXCEPTION 'El rango de fechas no es válido';
    END IF;

    IF NOT public.fn_user_can_access_tienda(p_id_tienda) THEN
        RAISE EXCEPTION 'No autorizado para esta tienda';
    END IF;

    SELECT id_tienda_carnaval INTO v_id_proveedor
    FROM public.app_dat_tienda
    WHERE id = p_id_tienda;

    IF v_id_proveedor IS NULL THEN
        RETURN jsonb_build_object('error', 'Tienda no sincronizada con Carnaval App');
    END IF;

    WITH ordenes_del_proveedor AS (
        SELECT DISTINCT
            o.id,
            o.created_at,
            o.status,
            o.metodo_pago
        FROM carnavalapp."Orders" o
        WHERE o.created_at >= p_fecha_desde
          AND o.created_at < (p_fecha_hasta + 1)
          AND EXISTS (
              SELECT 1
              FROM carnavalapp."OrderDetails" od
              WHERE od.order_id = o.id
                AND od.proveedor = v_id_proveedor
          )
    ),
    detalles_con_producto_local AS (
        SELECT
            od.id              AS order_detail_id,
            od.order_id,
            od.product_id,
            od.quantity,
            od.extra,
            o.created_at       AS order_date,
            o.status,
            o.metodo_pago,
            COALESCE(
                (SELECT p.id
                 FROM public.app_dat_producto p
                 WHERE p.id_vendedor_app = od.product_id
                   AND p.id_tienda = p_id_tienda
                 LIMIT 1),
                (SELECT p.id
                 FROM public.relation_products_carnaval rpc
                 JOIN public.app_dat_producto p ON p.id = rpc.id_producto
                 WHERE rpc.id_producto_carnaval = od.product_id
                   AND p.id_tienda = p_id_tienda
                 LIMIT 1)
            ) AS id_producto_local
        FROM carnavalapp."OrderDetails" od
        JOIN ordenes_del_proveedor o ON o.id = od.order_id
        WHERE od.proveedor = v_id_proveedor
    ),
    detalles_con_precio AS (
        SELECT
            d.*,
            COALESCE(
                (SELECT pv.precio_venta_cup
                 FROM public.app_dat_precio_venta pv
                 WHERE pv.id_producto = d.id_producto_local
                   AND pv.fecha_desde <= d.order_date
                   AND d.order_date < COALESCE(pv.fecha_hasta, '9999-12-31'::DATE)
                 ORDER BY pv.fecha_desde DESC, pv.created_at DESC
                 LIMIT 1),
                0
            )::NUMERIC AS precio_inventtia
        FROM detalles_con_producto_local d
        WHERE d.id_producto_local IS NOT NULL
    ),
    detalles_calculados AS (
        SELECT
            order_id,
            order_date,
            status,
            metodo_pago,
            id_producto_local,
            (COALESCE(quantity, 0) + COALESCE(extra, 0))::NUMERIC AS cantidad,
            precio_inventtia,
            (COALESCE(quantity, 0) + COALESCE(extra, 0))::NUMERIC * precio_inventtia AS monto
        FROM detalles_con_precio
    ),
    resumen AS (
        SELECT
            COUNT(DISTINCT order_id)                                        AS ordenes_count,
            COUNT(DISTINCT CASE WHEN status = 'Completado' THEN order_id END) AS ordenes_completadas,
            -- Solo lo vendido (Completado), valorado al precio Inventtia.
            SUM(cantidad) FILTER (WHERE status = 'Completado')              AS productos_vendidos,
            SUM(monto) FILTER (WHERE status = 'Completado')                 AS monto_total
        FROM detalles_calculados
    ),
    por_estado AS (
        SELECT
            status,
            COUNT(DISTINCT order_id) AS count,
            SUM(monto)               AS monto
        FROM detalles_calculados
        GROUP BY status
        ORDER BY count DESC
    ),
    por_metodo AS (
        SELECT
            metodo_pago,
            COUNT(DISTINCT order_id) AS ordenes_count,
            SUM(monto)               AS monto
        FROM detalles_calculados
        GROUP BY metodo_pago
        ORDER BY monto DESC
    ),
    evolucion AS (
        SELECT
            order_date::DATE         AS fecha,
            COUNT(DISTINCT order_id) AS ordenes_count,
            SUM(cantidad)            AS productos_vendidos,
            SUM(monto)               AS monto
        FROM detalles_calculados
        GROUP BY order_date::DATE
        ORDER BY order_date::DATE
    ),
    top_productos AS (
        -- Top 10 por cada estado; la app filtra según el estado seleccionado.
        SELECT id, status, nombre, cantidad, monto
        FROM (
            SELECT
                c.id_producto_local AS id,
                c.status,
                (SELECT p.denominacion FROM public.app_dat_producto p WHERE p.id = c.id_producto_local LIMIT 1) AS nombre,
                SUM(c.cantidad)     AS cantidad,
                SUM(c.monto)        AS monto,
                ROW_NUMBER() OVER (
                    PARTITION BY c.status
                    ORDER BY SUM(c.monto) DESC
                ) AS rn
            FROM detalles_calculados c
            GROUP BY c.id_producto_local, c.status
        ) ranked
        WHERE rn <= 10
    )
    SELECT jsonb_build_object(
        'id_proveedor_carnaval', v_id_proveedor,
        'desde',                 p_fecha_desde,
        'hasta',                 p_fecha_hasta,
        'resumen', (SELECT jsonb_build_object(
            'ordenes_count',       r.ordenes_count,
            'ordenes_completadas', r.ordenes_completadas,
            'productos_vendidos',  r.productos_vendidos,
            'monto_total',         ROUND(r.monto_total, 2),
            'ticket_promedio',     CASE WHEN r.ordenes_completadas > 0 THEN ROUND(r.monto_total / r.ordenes_completadas, 2) ELSE 0 END
        ) FROM resumen r),
        'por_estado', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'status', pe.status,
            'count',  pe.count,
            'monto',  ROUND(pe.monto, 2)
        )), '[]'::jsonb) FROM por_estado pe),
        'por_metodo_pago', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'metodo_pago',   pm.metodo_pago,
            'ordenes_count', pm.ordenes_count,
            'monto',         ROUND(pm.monto, 2)
        )), '[]'::jsonb) FROM por_metodo pm),
        'evolucion_diaria', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'fecha',              e.fecha,
            'ordenes_count',      e.ordenes_count,
            'productos_vendidos', e.productos_vendidos,
            'monto',              ROUND(e.monto, 2)
        )), '[]'::jsonb) FROM evolucion e),
        'top_productos', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'id',      tp.id,
            'status',  tp.status,
            'nombre',  tp.nombre,
            'cantidad', tp.cantidad,
            'monto',   ROUND(tp.monto, 2)
        )), '[]'::jsonb) FROM top_productos tp)
    ) INTO v_result;

    RETURN v_result;
END;
$function$;

-- ── 2/4 · fn_stock_producto_almacen_detalle(bigint,bigint) ──
CREATE OR REPLACE FUNCTION public.fn_stock_producto_almacen_detalle(p_id_producto bigint, p_id_almacen bigint DEFAULT NULL::bigint)
 RETURNS TABLE(id_ubicacion bigint, id_almacen bigint, id_variante bigint, id_opcion_variante bigint, id_presentacion bigint, cantidad_final numeric, sku_producto character varying, sku_ubicacion character varying)
 LANGUAGE sql
 STABLE
AS $function$
    -- Última fila (mayor id) por variante/opción/presentación/ubicación,
    -- recorriendo idx_inv_prod_combo de combinación en combinación.
    WITH RECURSIVE combos AS (
        (SELECT ip.id,
                COALESCE(ip.id_variante, 0)        AS v,
                COALESCE(ip.id_opcion_variante, 0) AS o,
                COALESCE(ip.id_presentacion, 0)    AS p,
                COALESCE(ip.id_ubicacion, 0)       AS u
           FROM public.app_dat_inventario_productos ip
          WHERE ip.id_producto = p_id_producto
          ORDER BY ip.id_producto,
                   COALESCE(ip.id_variante, 0),
                   COALESCE(ip.id_opcion_variante, 0),
                   COALESCE(ip.id_presentacion, 0),
                   COALESCE(ip.id_ubicacion, 0),
                   ip.id DESC
          LIMIT 1)
        UNION ALL
        SELECT n.id, n.v, n.o, n.p, n.u
          FROM combos c
          CROSS JOIN LATERAL (
              SELECT ip.id,
                     COALESCE(ip.id_variante, 0)        AS v,
                     COALESCE(ip.id_opcion_variante, 0) AS o,
                     COALESCE(ip.id_presentacion, 0)    AS p,
                     COALESCE(ip.id_ubicacion, 0)       AS u
                FROM public.app_dat_inventario_productos ip
               WHERE ip.id_producto = p_id_producto
                 AND (COALESCE(ip.id_variante, 0),
                      COALESCE(ip.id_opcion_variante, 0),
                      COALESCE(ip.id_presentacion, 0),
                      COALESCE(ip.id_ubicacion, 0)) > (c.v, c.o, c.p, c.u)
               ORDER BY ip.id_producto,
                        COALESCE(ip.id_variante, 0),
                        COALESCE(ip.id_opcion_variante, 0),
                        COALESCE(ip.id_presentacion, 0),
                        COALESCE(ip.id_ubicacion, 0),
                        ip.id DESC
               LIMIT 1
          ) n
    )
    SELECT ip.id_ubicacion,
           la.id_almacen,
           ip.id_variante,
           ip.id_opcion_variante,
           ip.id_presentacion,
           ip.cantidad_final,
           ip.sku_producto,
           ip.sku_ubicacion
      FROM combos c
      JOIN public.app_dat_inventario_productos ip ON ip.id = c.id
      JOIN public.app_dat_layout_almacen la      ON la.id = ip.id_ubicacion
     WHERE la.deleted_at IS NULL
       AND (p_id_almacen IS NULL OR la.id_almacen = p_id_almacen)
       AND COALESCE(ip.cantidad_final, 0) > 0
     ORDER BY ip.cantidad_final DESC, ip.id_ubicacion;
$function$;

-- ── 3/4 · fn_stock_saldos_presentacion(bigint,bigint,bigint,boolean) ──
CREATE OR REPLACE FUNCTION public.fn_stock_saldos_presentacion(p_id_producto bigint, p_id_almacen bigint DEFAULT NULL::bigint, p_id_ubicacion bigint DEFAULT NULL::bigint, p_incluir_cero boolean DEFAULT false)
 RETURNS TABLE(id_ubicacion bigint, id_almacen bigint, id_variante bigint, id_opcion_variante bigint, id_presentacion bigint, presentacion_nombre character varying, sku_codigo character varying, factor_rel numeric, es_base boolean, nivel integer, saldo numeric, equivalente_base numeric, sku_producto character varying, sku_ubicacion character varying)
 LANGUAGE sql
 STABLE
AS $function$
    WITH RECURSIVE
    -- Usa idx_inv_prod_lote_producto (parcial): respuesta inmediata.
    hay_lotes AS (
        SELECT EXISTS (
            SELECT 1
              FROM public.app_dat_inventario_productos x
             WHERE x.id_producto = p_id_producto
               AND x.id_lote IS NOT NULL
        ) AS hay
    ),
    -- Sin lotes: última fila por combinación saltando por idx_inv_prod_combo.
    combos AS (
        (SELECT ip.id,
                COALESCE(ip.id_variante, 0)        AS v,
                COALESCE(ip.id_opcion_variante, 0) AS o,
                COALESCE(ip.id_presentacion, 0)    AS p,
                COALESCE(ip.id_ubicacion, 0)       AS u
           FROM public.app_dat_inventario_productos ip
          WHERE ip.id_producto = p_id_producto
            AND NOT (SELECT hay FROM hay_lotes)
          ORDER BY ip.id_producto,
                   COALESCE(ip.id_variante, 0),
                   COALESCE(ip.id_opcion_variante, 0),
                   COALESCE(ip.id_presentacion, 0),
                   COALESCE(ip.id_ubicacion, 0),
                   ip.id DESC
          LIMIT 1)
        UNION ALL
        SELECT n.id, n.v, n.o, n.p, n.u
          FROM combos c
          CROSS JOIN LATERAL (
              SELECT ip.id,
                     COALESCE(ip.id_variante, 0)        AS v,
                     COALESCE(ip.id_opcion_variante, 0) AS o,
                     COALESCE(ip.id_presentacion, 0)    AS p,
                     COALESCE(ip.id_ubicacion, 0)       AS u
                FROM public.app_dat_inventario_productos ip
               WHERE ip.id_producto = p_id_producto
                 AND (COALESCE(ip.id_variante, 0),
                      COALESCE(ip.id_opcion_variante, 0),
                      COALESCE(ip.id_presentacion, 0),
                      COALESCE(ip.id_ubicacion, 0)) > (c.v, c.o, c.p, c.u)
               ORDER BY ip.id_producto,
                        COALESCE(ip.id_variante, 0),
                        COALESCE(ip.id_opcion_variante, 0),
                        COALESCE(ip.id_presentacion, 0),
                        COALESCE(ip.id_ubicacion, 0),
                        ip.id DESC
               LIMIT 1
          ) n
    ),
    vigente_lote AS (
        SELECT ip.id_ubicacion,
               la.id_almacen,
               ip.id_variante,
               ip.id_opcion_variante,
               ip.id_presentacion,
               ip.id_lote,
               COALESCE(ip.cantidad_final, 0) AS saldo,
               ip.sku_producto,
               ip.sku_ubicacion
          FROM combos c
          JOIN public.app_dat_inventario_productos ip ON ip.id = c.id
          JOIN public.app_dat_layout_almacen la      ON la.id = ip.id_ubicacion
         WHERE la.deleted_at IS NULL
           AND (p_id_ubicacion IS NULL OR ip.id_ubicacion = p_id_ubicacion)
           AND (p_id_almacen   IS NULL OR la.id_almacen   = p_id_almacen)
        UNION ALL
        -- Con lotes: consulta original, sin cambios.
        SELECT o.*
          FROM (
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
          ) o
         WHERE (SELECT hay FROM hay_lotes)
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

-- ── 4/4 · fn_reporte_ventas_con_proveedor_por_turno(bigint,date,date,bigint) ──
CREATE OR REPLACE FUNCTION public.fn_reporte_ventas_con_proveedor_por_turno(p_id_tienda bigint, p_fecha_desde date DEFAULT NULL::date, p_fecha_hasta date DEFAULT NULL::date, p_id_almacen bigint DEFAULT NULL::bigint)
 RETURNS TABLE(id_tienda bigint, id_producto bigint, nombre_producto character varying, id_proveedor bigint, nombre_proveedor character varying, precio_venta_cup numeric, precio_costo numeric, valor_usd numeric, precio_costo_cup numeric, total_vendido numeric, ingresos_totales numeric, costo_total_vendido numeric, ganancia_unitaria numeric, ganancia_total numeric, es_elaborado boolean, es_servicio boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column

DECLARE
    v_id_tipo_venta BIGINT;
    v_tasa_fallback NUMERIC;
BEGIN
    PERFORM public.check_user_has_access_to_tienda(p_id_tienda);

    SELECT id INTO v_id_tipo_venta
    FROM app_nom_tipo_operacion
    WHERE LOWER(denominacion) = 'venta'
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
    -- -------------------------------------------------------------------------
    -- 0. Turnos abiertos dentro del rango de fechas (mismo criterio que TPVs).
    --    El turno se delimita por los IDs de sus operaciones de apertura y
    --    cierre, NO por fecha/hora. Para turnos abiertos usamos el ID máximo
    --    de operación existente como cierre efectivo.
    -- -------------------------------------------------------------------------

    -- -------------------------------------------------------------------------
    -- 1. Operaciones de venta válidas que caen dentro de alguno de los turnos.
    --    Se empareja por uuid del vendedor y por id_tpv de la operación de venta,
    --    y el id de operación debe estar entre la apertura y el cierre del turno
    --    (igual que fn_reporte_ventas_por_turno_vendedor desplegada).
    -- -------------------------------------------------------------------------
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
        WHERE o.id_tienda = p_id_tienda
          AND o.id_tipo_operacion = v_id_tipo_venta
          AND o.created_at >= COALESCE(p_fecha_desde, CURRENT_DATE)::timestamptz
          AND o.created_at <  (COALESCE(p_fecha_hasta, CURRENT_DATE) + INTERVAL '1 day')::timestamptz
          AND e.estado = 2
    ),

    -- -------------------------------------------------------------------------
    -- 2. Líneas de venta. El filtro de fecha ya no aplica porque las operaciones
    --    quedaron acotadas por el intervalo del turno.
    -- -------------------------------------------------------------------------
    ventas_detalle AS MATERIALIZED (
        SELECT
            ep.id_producto,
            ep.id_variante,
            COALESCE(ep.id_variante, 0) AS variante_key,
            ep.id_presentacion,
            ep.cantidad,
            ep.importe,
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

    -- -------------------------------------------------------------------------
    -- 3. Pares (producto, variante) distintos.
    -- -------------------------------------------------------------------------
    prod_var AS MATERIALIZED (
        SELECT DISTINCT vd.id_producto, vd.variante_key
        FROM ventas_detalle vd
    ),

    -- -------------------------------------------------------------------------
    -- 4. Precio de venta CUP vigente en la fecha de la operación.
    -- -------------------------------------------------------------------------
    precio_venta_historico AS MATERIALIZED (
        SELECT
            k.id_producto,
            k.variante_key,
            k.fecha_op,
            ROUND(x.precio_venta_cup::NUMERIC, 2) AS precio_cup_historico
        FROM (SELECT DISTINCT vd.id_producto, vd.variante_key, vd.fecha_op
              FROM ventas_detalle vd) k
        CROSS JOIN LATERAL (
            SELECT pv.precio_venta_cup
            FROM app_dat_precio_venta pv
            WHERE pv.id_producto = k.id_producto
              AND (pv.id_variante IS NULL OR pv.id_variante = 0
                   OR pv.id_variante = k.variante_key)
              AND pv.fecha_desde <= k.fecha_op
              AND (pv.fecha_hasta IS NULL OR pv.fecha_hasta >= k.fecha_op)
            ORDER BY pv.created_at DESC
            LIMIT 1
        ) x
    ),

    -- -------------------------------------------------------------------------
    -- 5. Tasa USD->CUP vigente en cada fecha de operación.
    -- -------------------------------------------------------------------------
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

    -- -------------------------------------------------------------------------
    -- 6a. Costo USD histórico por presentación.
    -- -------------------------------------------------------------------------
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

    -- -------------------------------------------------------------------------
    -- 6b. Fallbacks de costo.
    -- -------------------------------------------------------------------------
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

    -- -------------------------------------------------------------------------
    -- 6c. Costo de receta histórico para elaborados/servicios.
    -- -------------------------------------------------------------------------
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

    -- -------------------------------------------------------------------------
    -- 7. Enriquecer cada línea con precio, tasa y costo históricos.
    -- -------------------------------------------------------------------------
    ventas_enriquecidas AS MATERIALIZED (
        SELECT
            vd.id_producto,
            vd.variante_key,
            vd.id_presentacion,
            vd.cantidad,
            ROUND(COALESCE(
                pvh.precio_cup_historico,
                CASE WHEN vd.cantidad > 0 THEN (vd.importe / vd.cantidad)::NUMERIC ELSE 0 END
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
        LEFT JOIN precio_venta_historico pvh
               ON pvh.id_producto = vd.id_producto
              AND pvh.variante_key = vd.variante_key
              AND pvh.fecha_op = vd.fecha_op
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

    -- -------------------------------------------------------------------------
    -- 8. Agregar por producto/presentación/precio_venta/costo_cup.
    -- -------------------------------------------------------------------------
    agregado AS (
        SELECT
            ve.id_producto,
            ve.precio_venta_cup_op,
            ROUND((ve.costo_usd_op * ve.tasa_op)::NUMERIC, 2) AS costo_cup_op,
            ve.costo_usd_op,
            ve.tasa_op,
            SUM(ve.cantidad) AS total_vendido,
            SUM(ve.precio_venta_cup_op * ve.cantidad) AS ingresos_totales,
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
    )

    -- -------------------------------------------------------------------------
    -- 9. Resultado final con datos del producto y proveedor.
    -- -------------------------------------------------------------------------
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
        ROUND((ag.precio_venta_cup_op - ag.costo_cup_op)::NUMERIC, 2) AS ganancia_unitaria,
        ROUND((ag.ingresos_totales - ag.costo_total_vendido)::NUMERIC, 2) AS ganancia_total,
        COALESCE(p.es_elaborado, FALSE) AS es_elaborado,
        COALESCE(p.es_servicio, FALSE) AS es_servicio
    FROM agregado ag
    JOIN app_dat_producto p ON ag.id_producto = p.id
    LEFT JOIN app_dat_proveedor prov ON p.id_proveedor = prov.id
    WHERE p.id_tienda = p_id_tienda
    ORDER BY p.denominacion, ag.precio_venta_cup_op DESC, ag.costo_cup_op DESC;

END;
$function$;

-- ── Verificación: el cuerpo de newa debe ser el mismo que el de main ──
DO $ver$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT * FROM (VALUES
            ('fn_dashboard_carnaval_proveedor(bigint,date,date)', '8734944d'),
            ('fn_stock_producto_almacen_detalle(bigint,bigint)', '1f2ef38a'),
            ('fn_stock_saldos_presentacion(bigint,bigint,bigint,boolean)', '8005bbfa'),
            ('fn_reporte_ventas_con_proveedor_por_turno(bigint,date,date,bigint)', 'f6f60db6')
        ) AS t(firma, hash_main)
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_proc p
             WHERE p.oid = to_regprocedure('public.' || r.firma)
               AND left(md5(p.prosrc), 8) = r.hash_main
        ) THEN
            RAISE EXCEPTION 'El cuerpo de % no coincide con el de main', r.firma;
        END IF;
    END LOOP;
END
$ver$;

COMMIT;
