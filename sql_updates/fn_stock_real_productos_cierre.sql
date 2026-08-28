-- ============================================================
-- fn_stock_real_productos_cierre
-- ============================================================
-- Propósito: stock "debe haber" para control de inventario en cierre
--   (reemplaza N x fn_listar_inventario_productos_paged2 + queries Carnaval).
--
-- Por producto:
--   stock_sistema      = suma de cantidad_final (1 fila por ubicación)
--   pendiente_carnaval = ops cuyo historial de estado es SOLO estado=1
--   en_camino          = pendientes Inventtia ligadas a Orders Carnaval
--                        con status 'Entregando'
--   debe_haber         = stock + max(pendiente - en_camino, 0)
--
-- p_id_almacen NULL  → todos los almacenes de la tienda.
-- p_id_almacen set   → solo ese almacén (uso en cierre del vendedor).
-- p_ids_producto NULL → todos los inventariables no servicio/elaborado
--                       con movimiento en el alcance.
--
-- Idempotente: CREATE OR REPLACE.
-- APLICAR MANUALMENTE en Supabase (SQL Editor).
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_stock_real_productos_cierre(
    p_id_tienda     bigint,
    p_id_almacen    bigint DEFAULT NULL,
    p_ids_producto  bigint[] DEFAULT NULL
)
RETURNS TABLE (
    id_producto         bigint,
    stock_sistema       numeric,
    pendiente_carnaval  numeric,
    en_camino           numeric,
    debe_haber          numeric
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
AS $$
BEGIN
    IF p_id_tienda IS NULL THEN
        RAISE EXCEPTION 'p_id_tienda es obligatorio';
    END IF;

    PERFORM check_user_has_access_to_tienda(p_id_tienda);

    IF NOT EXISTS (SELECT 1 FROM app_dat_tienda t WHERE t.id = p_id_tienda) THEN
        RAISE EXCEPTION 'La tienda con ID % no existe', p_id_tienda;
    END IF;

    RETURN QUERY
    WITH productos AS (
        SELECT p.id
        FROM public.app_dat_producto p
        WHERE (
                p_ids_producto IS NULL
                OR p.id = ANY (p_ids_producto)
              )
          AND (
                -- Si vienen IDs explícitos, no exigir id_tienda del producto
                -- (pueden estar asociados por inventario de la tienda).
                p_ids_producto IS NOT NULL
                OR p.id_tienda = p_id_tienda
              )
    ),
    inv_last AS (
        SELECT DISTINCT ON (
            ih.id_producto,
            COALESCE(ih.id_variante, 0),
            COALESCE(ih.id_opcion_variante, 0),
            COALESCE(ih.id_presentacion, 0),
            COALESCE(ih.id_ubicacion, 0)
        )
            ih.id,
            ih.id_producto,
            ih.id_ubicacion,
            ih.cantidad_final,
            ih.id_extraccion
        FROM public.app_dat_inventario_productos ih
        WHERE ih.id_producto IN (SELECT productos.id FROM productos)
        ORDER BY
            ih.id_producto,
            COALESCE(ih.id_variante, 0),
            COALESCE(ih.id_opcion_variante, 0),
            COALESCE(ih.id_presentacion, 0),
            COALESCE(ih.id_ubicacion, 0),
            ih.id DESC
    ),
    inv_alcance AS (
        SELECT
            i.id,
            i.id_producto,
            i.id_ubicacion,
            i.cantidad_final,
            i.id_extraccion,
            a.id AS id_almacen
        FROM inv_last i
        INNER JOIN public.app_dat_layout_almacen l ON i.id_ubicacion = l.id
        INNER JOIN public.app_dat_almacen a       ON l.id_almacen = a.id
        WHERE a.id_tienda = p_id_tienda
          AND (p_id_almacen IS NULL OR a.id = p_id_almacen)
    ),
    -- Una cantidad por ubicación (igual que el cliente: primera fila / ubicación).
    stock_por_ubic AS (
        SELECT DISTINCT ON (ia.id_producto, ia.id_ubicacion)
            ia.id_producto,
            ia.id_ubicacion,
            ia.cantidad_final
        FROM inv_alcance ia
        ORDER BY ia.id_producto, ia.id_ubicacion, ia.id DESC
    ),
    stock_agg AS (
        SELECT
            s.id_producto,
            COALESCE(SUM(s.cantidad_final), 0)::numeric AS stock_sistema
        FROM stock_por_ubic s
        GROUP BY s.id_producto
    ),
    -- Pendientes Carnaval: historial de estado SOLO = 1 (nunca otro estado).
    pendiente_agg AS (
        SELECT
            inv.id_producto,
            COALESCE(SUM(ABS(inv.cantidad_final - inv.cantidad_inicial)), 0)::numeric
                AS pendiente_carnaval
        FROM public.app_dat_inventario_productos inv
        INNER JOIN public.app_dat_extraccion_productos ep
            ON inv.id_extraccion = ep.id
        INNER JOIN public.app_dat_layout_almacen la
            ON inv.id_ubicacion = la.id
        INNER JOIN public.app_dat_almacen a
            ON la.id_almacen = a.id
        WHERE inv.id_extraccion IS NOT NULL
          AND inv.id_producto IN (SELECT productos.id FROM productos)
          AND a.id_tienda = p_id_tienda
          AND (p_id_almacen IS NULL OR a.id = p_id_almacen)
          AND EXISTS (
                SELECT 1
                FROM public.app_dat_estado_operacion eo
                WHERE eo.id_operacion = ep.id_operacion
                  AND eo.estado = 1
              )
          AND NOT EXISTS (
                SELECT 1
                FROM public.app_dat_estado_operacion eo
                WHERE eo.id_operacion = ep.id_operacion
                  AND eo.estado <> 1
              )
        GROUP BY inv.id_producto
    ),
    -- Ops pendientes (último estado = 1) ligadas a orden Carnaval.
    ops_pendientes AS (
        SELECT
            ep.id_producto,
            ABS(ep.cantidad)::numeric AS qty,
            COALESCE(
                o.id_carnaval_order,
                (
                    SELECT (regexp_match(
                        COALESCE(o.observaciones, ''),
                        'Venta desde orden\s+(\d+)',
                        'i'
                    ))[1]::bigint
                )
            ) AS order_id
        FROM public.app_dat_extraccion_productos ep
        INNER JOIN public.app_dat_operaciones o
            ON ep.id_operacion = o.id
        INNER JOIN public.app_dat_layout_almacen la
            ON ep.id_ubicacion = la.id
        INNER JOIN public.app_dat_almacen a
            ON la.id_almacen = a.id
        INNER JOIN LATERAL (
            SELECT eo.estado
            FROM public.app_dat_estado_operacion eo
            WHERE eo.id_operacion = o.id
            ORDER BY eo.id DESC
            LIMIT 1
        ) ult ON ult.estado = 1
        WHERE ep.id_producto IN (SELECT productos.id FROM productos)
          AND a.id_tienda = p_id_tienda
          AND (p_id_almacen IS NULL OR a.id = p_id_almacen)
    ),
    en_camino_agg AS (
        SELECT
            op.id_producto,
            COALESCE(SUM(op.qty), 0)::numeric AS en_camino
        FROM ops_pendientes op
        INNER JOIN carnavalapp."Orders" ord
            ON ord.id = op.order_id
        WHERE op.order_id IS NOT NULL
          AND ord.status = 'Entregando'
        GROUP BY op.id_producto
    ),
    ids AS (
        SELECT id AS id_producto FROM productos
        WHERE p_ids_producto IS NOT NULL
        UNION
        SELECT sa.id_producto FROM stock_agg sa
        WHERE p_ids_producto IS NULL
        UNION
        SELECT pa.id_producto FROM pendiente_agg pa
        WHERE p_ids_producto IS NULL
        UNION
        SELECT ea.id_producto FROM en_camino_agg ea
        WHERE p_ids_producto IS NULL
    )
    SELECT
        i.id_producto::bigint,
        COALESCE(sa.stock_sistema, 0)::numeric AS stock_sistema,
        COALESCE(pa.pendiente_carnaval, 0)::numeric AS pendiente_carnaval,
        COALESCE(ea.en_camino, 0)::numeric AS en_camino,
        GREATEST(
            COALESCE(sa.stock_sistema, 0)
            + GREATEST(
                COALESCE(pa.pendiente_carnaval, 0) - COALESCE(ea.en_camino, 0),
                0
              ),
            0
        )::numeric AS debe_haber
    FROM ids i
    LEFT JOIN stock_agg sa ON sa.id_producto = i.id_producto
    LEFT JOIN pendiente_agg pa ON pa.id_producto = i.id_producto
    LEFT JOIN en_camino_agg ea ON ea.id_producto = i.id_producto
    ORDER BY i.id_producto;
END;
$$;

COMMENT ON FUNCTION public.fn_stock_real_productos_cierre(bigint, bigint, bigint[]) IS
'Stock debe-haber para cierre: stock_sistema + max(pendiente_carnaval - en_camino, 0) por producto.';

GRANT EXECUTE ON FUNCTION public.fn_stock_real_productos_cierre(bigint, bigint, bigint[])
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_stock_real_productos_cierre(bigint, bigint, bigint[])
    TO service_role;
