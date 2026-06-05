-- ============================================================================
-- 02_fn_listar_promociones_productos_batch.sql
-- ----------------------------------------------------------------------------
-- Versión BATCH de fn_listar_promociones_producto_nueva(p_id_producto bigint).
--
-- Objetivo: eliminar el N+1 en la sincronización offline
-- (lib/services/auto_sync_service.dart -> _syncProductPromotions()), donde hoy
-- se llama fn_listar_promociones_producto_nueva UNA VEZ POR PRODUCTO.
--
-- Recibe un array de ids de producto y devuelve TODAS las promociones
-- aplicables a esos productos en UNA sola llamada, añadiendo la columna
-- id_producto para poder repartir el resultado por producto en el cliente.
--
-- Las columnas (excepto id_producto al inicio) son EXACTAMENTE las mismas que
-- fn_listar_promociones_producto_nueva, para reutilizar el parseo del cliente.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_listar_promociones_productos_batch(
    ids_param bigint[]
)
RETURNS TABLE(
    id_producto bigint,
    id bigint,
    nombre text,
    descripcion text,
    valor_descuento numeric,
    fecha_inicio timestamp without time zone,
    fecha_fin timestamp without time zone,
    precio_base numeric,
    es_recargo boolean,
    estado boolean,
    codigo_promocion text,
    tipo_promocion text,
    requiere_medio_pago boolean,
    id_medio_pago_requerido bigint,
    id_tipo_promocion bigint,
    min_compra numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
RETURN QUERY
WITH producto_info AS (
    SELECT
        p.id AS producto_id,
        p.id_tienda,
        p.id_categoria,
        p.es_elaborado,
        COALESCE(pv.precio_venta_cup, 0.0) AS precio_base
    FROM app_dat_producto p
    LEFT JOIN LATERAL (
        SELECT precio_venta_cup
        FROM app_dat_precio_venta pv_inner
        WHERE pv_inner.id_producto = p.id
          AND (pv_inner.id_variante IS NULL OR pv_inner.id_variante = 0)
          AND (pv_inner.fecha_hasta IS NULL OR pv_inner.fecha_hasta >= CURRENT_DATE)
        ORDER BY pv_inner.created_at DESC
        LIMIT 1
    ) pv ON TRUE
    WHERE p.id = ANY(ids_param)   -- 👈 BATCH: todos los productos solicitados
)
SELECT
    pi.producto_id::bigint AS id_producto,   -- 👈 columna extra para repartir
    pr.id::BIGINT,
    pr.nombre::TEXT,
    pr.descripcion::TEXT,
    pr.valor_descuento::NUMERIC,
    pr.fecha_inicio::TIMESTAMP,
    pr.fecha_fin::TIMESTAMP,
    pi.precio_base::NUMERIC,
    CASE
        WHEN tp.denominacion ILIKE '%recargo%' OR tp.denominacion ILIKE '%aumento%' THEN true
        ELSE false
    END::BOOLEAN,
    pr.estado::BOOLEAN,
    pr.codigo_promocion::TEXT,
    tp.denominacion::TEXT,
    pr.requiere_medio_pago::boolean,
    pr.id_medio_pago_requerido::bigint,
    pr.id_tipo_promocion::bigint,
    pr.min_compra::numeric
FROM app_mkt_promociones pr
INNER JOIN app_mkt_tipo_promocion tp ON pr.id_tipo_promocion = tp.id
LEFT JOIN app_mkt_promocion_productos pp ON pr.id = pp.id_promocion
CROSS JOIN producto_info pi
WHERE
    pr.id_tienda = pi.id_tienda
    AND aplica_todo = false
    AND pr.estado = true
    AND pr.fecha_inicio <= CURRENT_TIMESTAMP
    AND (pr.fecha_fin IS NULL OR pr.fecha_fin >= CURRENT_TIMESTAMP)
    AND pi.precio_base > 0
    AND (
        pr.aplica_todo = true
        OR
        (
            pp.id_promocion IS NOT NULL
            AND (
                pp.id_producto = pi.producto_id
            )
        )
    )
ORDER BY
    pi.producto_id,
    CASE
        WHEN pp.id_producto = pi.producto_id THEN 1
        WHEN pp.id_categoria = pi.id_categoria THEN 2
        WHEN pp.id_subcategoria IS NOT NULL THEN 3
        ELSE 4
    END,
    pr.fecha_inicio DESC;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_listar_promociones_productos_batch(bigint[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_listar_promociones_productos_batch(bigint[]) TO anon;
