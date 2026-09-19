-- ============================================================================
-- fn_dashboard_carnaval_proveedor
-- Dashboard de estadísticas para el proveedor dueño de una tienda Inventtia
-- sincronizada con Carnaval App. Devuelve un JSONB con resumen, evolución,
-- top productos y desglose por estado y método de pago.
-- El monto se recalcula con el precio histórico del producto local
-- (app_dat_precio_venta) en la fecha de la orden.
-- ============================================================================

DROP FUNCTION IF EXISTS public.fn_dashboard_carnaval_proveedor(BIGINT, DATE, DATE);

CREATE OR REPLACE FUNCTION public.fn_dashboard_carnaval_proveedor(
    p_id_tienda   BIGINT,
    p_fecha_desde DATE DEFAULT (CURRENT_DATE - INTERVAL '30 days')::DATE,
    p_fecha_hasta DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, carnavalapp
AS $$
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
            SUM(cantidad)                                                   AS productos_vendidos,
            SUM(monto)                                                      AS monto_total
        FROM detalles_calculados
    ),
    por_estado AS (
        SELECT status, COUNT(DISTINCT order_id) AS count
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
        SELECT
            c.id_producto_local AS id,
            (SELECT p.denominacion FROM public.app_dat_producto p WHERE p.id = c.id_producto_local LIMIT 1) AS nombre,
            SUM(c.cantidad)     AS cantidad,
            SUM(c.monto)        AS monto
        FROM detalles_calculados c
        GROUP BY c.id_producto_local
        ORDER BY monto DESC
        LIMIT 10
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
            'ticket_promedio',     CASE WHEN r.ordenes_count > 0 THEN ROUND(r.monto_total / r.ordenes_count, 2) ELSE 0 END
        ) FROM resumen r),
        'por_estado', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'status', pe.status,
            'count',  pe.count
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
            'nombre',  tp.nombre,
            'cantidad', tp.cantidad,
            'monto',   ROUND(tp.monto, 2)
        )), '[]'::jsonb) FROM top_productos tp)
    ) INTO v_result;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_dashboard_carnaval_proveedor(BIGINT, DATE, DATE) TO authenticated;
