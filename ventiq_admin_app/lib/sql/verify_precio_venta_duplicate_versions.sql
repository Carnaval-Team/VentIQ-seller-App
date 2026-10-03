-- ============================================================================
-- Verificacion de versiones duplicadas en public.app_dat_precio_venta
-- Generado tipicamente cuando el trigger trg_price_update_to_insert inserta
-- una nueva fila aunque el precio no haya cambiado.
--
-- Detecta, por cada (id_producto, id_variante), filas consecutivas donde
-- precio_venta_cup, precio_venta_usd y precio_descuento sean identicos
-- (IS NOT DISTINCT FROM) a la fila anterior.
--
-- Filtros opcionales:
--   p_tienda_id    -> restringe a productos de esa tienda
--   p_producto_id  -> restringe a un producto concreto
--   p_delete       -> true borra las filas duplicadas (default false)
-- ============================================================================

-- -------------------------------------------------------------------------
-- 1. VISTA / CONSULTA DIRECTA: listar duplicados
-- -------------------------------------------------------------------------
-- Ejemplo: ver duplicados de una tienda:
--
-- SELECT *
-- FROM public.fn_verify_precio_venta_duplicate_versions(
--   p_tienda_id := 231,
--   p_delete := FALSE
-- );

CREATE OR REPLACE FUNCTION public.fn_verify_precio_venta_duplicate_versions(
    p_tienda_id   BIGINT DEFAULT NULL,
    p_producto_id BIGINT DEFAULT NULL,
    p_delete      BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    id_producto BIGINT,
    id_variante BIGINT,
    duplicados_count INT,
    ultimo_id BIGINT,
    ultimo_created_at TIMESTAMPTZ,
    max_predecesor_created_at TIMESTAMPTZ,
    ultimo_created_at_ok BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_deleted INT;
BEGIN
    RETURN QUERY
    WITH ordered AS (
        SELECT
            pv.id,
            pv.id_producto,
            pv.id_variante,
            pv.precio_venta_cup,
            pv.precio_venta_usd,
            pv.precio_descuento,
            pv.created_at,
            LAG(pv.id)               OVER w AS anterior_id,
            LAG(pv.precio_venta_cup)   OVER w AS anterior_precio_venta_cup,
            LAG(pv.precio_venta_usd)   OVER w AS anterior_precio_venta_usd,
            LAG(pv.precio_descuento)   OVER w AS anterior_precio_descuento,
            MAX(pv.created_at) OVER (
                PARTITION BY pv.id_producto, pv.id_variante
                ORDER BY pv.id
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            ) AS max_predecesor_created_at,
            ROW_NUMBER() OVER (
                PARTITION BY pv.id_producto, pv.id_variante
                ORDER BY pv.id DESC
            ) AS rn_desc
        FROM public.app_dat_precio_venta pv
        JOIN public.app_dat_producto p ON p.id = pv.id_producto
        WHERE (p_producto_id IS NULL OR pv.id_producto = p_producto_id)
          AND (p_tienda_id   IS NULL OR p.id_tienda  = p_tienda_id)
        WINDOW w AS (
            PARTITION BY pv.id_producto, pv.id_variante
            ORDER BY pv.id
        )
    ),
    grouped AS (
        SELECT
            o.id_producto,
            o.id_variante,
            SUM(
                CASE
                    WHEN o.anterior_id IS NOT NULL
                        AND o.precio_venta_cup IS NOT DISTINCT FROM o.anterior_precio_venta_cup
                        AND o.precio_venta_usd IS NOT DISTINCT FROM o.anterior_precio_venta_usd
                        AND o.precio_descuento IS NOT DISTINCT FROM o.anterior_precio_descuento
                    THEN 1 ELSE 0
                END
            )::INT AS duplicados_count,
            MAX(CASE WHEN o.rn_desc = 1 THEN o.id END) AS ultimo_id,
            MAX(CASE WHEN o.rn_desc = 1 THEN o.created_at END) AS ultimo_created_at,
            MAX(o.max_predecesor_created_at) AS max_predecesor_created_at
        FROM ordered o
        GROUP BY o.id_producto, o.id_variante
    )
    SELECT
        g.id_producto,
        g.id_variante,
        g.duplicados_count,
        g.ultimo_id,
        g.ultimo_created_at,
        g.max_predecesor_created_at,
        CASE
            WHEN g.max_predecesor_created_at IS NULL THEN TRUE
            WHEN g.ultimo_created_at > g.max_predecesor_created_at THEN TRUE
            ELSE FALSE
        END AS ultimo_created_at_ok
    FROM grouped g
    WHERE g.duplicados_count > 0
       OR g.ultimo_created_at <= g.max_predecesor_created_at
    ORDER BY g.id_producto, g.id_variante;

    IF p_delete THEN
        WITH ordered AS (
            SELECT
                pv.id,
                pv.id_producto,
                pv.id_variante,
                pv.precio_venta_cup,
                pv.precio_venta_usd,
                pv.precio_descuento,
                LAG(pv.id)               OVER w AS anterior_id,
                LAG(pv.precio_venta_cup) OVER w AS anterior_precio_venta_cup,
                LAG(pv.precio_venta_usd) OVER w AS anterior_precio_venta_usd,
                LAG(pv.precio_descuento) OVER w AS anterior_precio_descuento
            FROM public.app_dat_precio_venta pv
            JOIN public.app_dat_producto p ON p.id = pv.id_producto
            WHERE (p_producto_id IS NULL OR pv.id_producto = p_producto_id)
              AND (p_tienda_id   IS NULL OR p.id_tienda  = p_tienda_id)
            WINDOW w AS (
                PARTITION BY pv.id_producto, pv.id_variante
                ORDER BY pv.id
            )
        ),
        duplicados AS (
            SELECT o.id AS duplicado_id, o.anterior_id
            FROM ordered o
            WHERE o.anterior_id IS NOT NULL
              AND o.precio_venta_cup IS NOT DISTINCT FROM o.anterior_precio_venta_cup
              AND o.precio_venta_usd IS NOT DISTINCT FROM o.anterior_precio_venta_usd
              AND o.precio_descuento IS NOT DISTINCT FROM o.anterior_precio_descuento
        ),
        deleted AS (
            DELETE FROM public.app_dat_precio_venta pv
            USING duplicados d
            WHERE pv.id = d.duplicado_id
            RETURNING pv.id
        )
        SELECT COUNT(*) INTO v_deleted FROM deleted;

        RAISE NOTICE 'Filas duplicadas borradas: %', v_deleted;
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_verify_precio_venta_duplicate_versions(BIGINT, BIGINT, BOOLEAN) TO authenticated;

-- -------------------------------------------------------------------------
-- 2. EJEMPLOS DE USO
-- -------------------------------------------------------------------------
-- Ver duplicados de una tienda:
-- SELECT * FROM public.fn_verify_precio_venta_duplicate_versions(
--   p_tienda_id := 231
-- );
--
-- Ver duplicados de un producto:
-- SELECT * FROM public.fn_verify_precio_venta_duplicate_versions(
--   p_producto_id := 12345
-- );
--
-- Borrar duplicados detectados de una tienda (usar con precaucion):
-- SELECT * FROM public.fn_verify_precio_venta_duplicate_versions(
--   p_tienda_id := 231,
--   p_delete := TRUE
-- );
