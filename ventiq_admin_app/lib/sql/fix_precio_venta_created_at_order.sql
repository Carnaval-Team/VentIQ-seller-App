-- ============================================================================
-- Listado de triggers sobre public.app_dat_precio_venta
-- Correccion de created_at: garantizar que, dentro de cada producto/variante,
-- el registro con el ID mas alto tenga created_at posterior al maximo de sus
-- registros predecesores.
--
-- Filtros opcionales:
--   p_tienda_id    -> restringe a productos de esa tienda
--   p_producto_id  -> restringe a un producto concreto
--   p_dry_run      -> true solo reporta, false actualiza (default false)
-- ============================================================================

-- -------------------------------------------------------------------------
-- 1. CONSULTA PARA VER LOS TRIGGERS ACTIVOS SOBRE app_dat_precio_venta
-- -------------------------------------------------------------------------
SELECT
    tgname           AS trigger_name,
    tgtype,
    CASE WHEN (tgtype::int & 2) > 0 THEN 'BEFORE'
         WHEN (tgtype::int & 64) > 0 THEN 'INSTEAD OF'
         ELSE 'AFTER' END AS timing,
    CASE WHEN (tgtype::int & 4) > 0 THEN 'INSERT' ELSE '' END ||
    CASE WHEN (tgtype::int & 8) > 0 THEN 'DELETE' ELSE '' END ||
    CASE WHEN (tgtype::int & 16) > 0 THEN 'UPDATE' ELSE '' END AS events,
    pg_get_triggerdef(oid) AS trigger_definition
FROM pg_trigger
WHERE tgrelid = 'public.app_dat_precio_venta'::regclass
  AND NOT tgisinternal
ORDER BY tgname;

-- -------------------------------------------------------------------------
-- 2. FUNCION DE CORRECCION
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fix_precio_venta_created_at_order(
    p_tienda_id   BIGINT DEFAULT NULL,
    p_producto_id BIGINT DEFAULT NULL,
    p_dry_run     BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    id_producto BIGINT,
    id_variante BIGINT,
    ultimo_id BIGINT,
    created_at_actual TIMESTAMPTZ,
    max_predecesor TIMESTAMPTZ,
    nuevo_created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_updated INT;
BEGIN
    RETURN QUERY
    WITH last_rows AS (
        -- Ultimo registro por id dentro de cada (producto, variante)
        SELECT DISTINCT ON (pv.id_producto, COALESCE(pv.id_variante, 0))
            pv.id,
            pv.id_producto AS prod_id,
            pv.id_variante AS var_id,
            pv.created_at
        FROM public.app_dat_precio_venta pv
        JOIN public.app_dat_producto p ON p.id = pv.id_producto
        WHERE (p_producto_id IS NULL OR pv.id_producto = p_producto_id)
          AND (p_tienda_id   IS NULL OR p.id_tienda  = p_tienda_id)
        ORDER BY pv.id_producto, COALESCE(pv.id_variante, 0), pv.id DESC
    ),
    with_prev_max AS (
        SELECT
            lr.id,
            lr.prod_id,
            lr.var_id,
            lr.created_at AS created_at_actual,
            (
                SELECT MAX(pv2.created_at)
                FROM public.app_dat_precio_venta pv2
                WHERE pv2.id_producto = lr.prod_id
                  AND pv2.id_variante IS NOT DISTINCT FROM lr.var_id
                  AND pv2.id < lr.id
            ) AS max_predecesor
        FROM last_rows lr
    ),
    to_fix AS (
        SELECT
            wpm.id,
            wpm.prod_id,
            wpm.var_id,
            wpm.created_at_actual,
            wpm.max_predecesor,
            wpm.max_predecesor + '1 microsecond'::INTERVAL AS new_created_at
        FROM with_prev_max wpm
        WHERE wpm.max_predecesor IS NOT NULL
          AND wpm.created_at_actual <= wpm.max_predecesor
    )
    SELECT
        tf.prod_id,
        tf.var_id,
        tf.id,
        tf.created_at_actual,
        tf.max_predecesor,
        tf.new_created_at
    FROM to_fix tf
    ORDER BY tf.prod_id, tf.var_id;

    IF NOT p_dry_run THEN
        WITH last_rows AS (
            SELECT DISTINCT ON (pv.id_producto, COALESCE(pv.id_variante, 0))
                pv.id,
                pv.id_producto,
                pv.id_variante,
                pv.created_at
            FROM public.app_dat_precio_venta pv
            JOIN public.app_dat_producto p ON p.id = pv.id_producto
            WHERE (p_producto_id IS NULL OR pv.id_producto = p_producto_id)
              AND (p_tienda_id   IS NULL OR p.id_tienda  = p_tienda_id)
            ORDER BY pv.id_producto, COALESCE(pv.id_variante, 0), pv.id DESC
        ),
        with_prev_max AS (
            SELECT
                lr.id,
                lr.created_at,
                (
                    SELECT MAX(pv2.created_at)
                    FROM public.app_dat_precio_venta pv2
                    WHERE pv2.id_producto = lr.id_producto
                      AND pv2.id_variante IS NOT DISTINCT FROM lr.id_variante
                      AND pv2.id < lr.id
                ) AS max_predecesor
            FROM last_rows lr
        ),
        to_fix AS (
            SELECT
                wpm.id,
                wpm.max_predecesor + '1 microsecond'::INTERVAL AS new_created_at
            FROM with_prev_max wpm
            WHERE wpm.max_predecesor IS NOT NULL
              AND wpm.created_at <= wpm.max_predecesor
        )
        UPDATE public.app_dat_precio_venta pv
        SET created_at = tf.new_created_at
        FROM to_fix tf
        WHERE pv.id = tf.id;

        GET DIAGNOSTICS v_updated = ROW_COUNT;
        RAISE NOTICE 'Registros corregidos (ultimo id por producto/variante): %', v_updated;
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_fix_precio_venta_created_at_order(BIGINT, BIGINT, BOOLEAN) TO authenticated;

-- -------------------------------------------------------------------------
-- 3. EJEMPLOS DE USO
-- -------------------------------------------------------------------------
-- Solo ver (dry run) los problemas de una tienda:
-- SELECT * FROM public.fn_fix_precio_venta_created_at_order(
--   p_tienda_id := 123,
--   p_dry_run := TRUE
-- );
--
-- Corregir todos los registros de una tienda:
-- SELECT * FROM public.fn_fix_precio_venta_created_at_order(
--   p_tienda_id := 123,
--   p_dry_run := FALSE
-- );
--
-- Corregir solo un producto concreto:
-- SELECT * FROM public.fn_fix_precio_venta_created_at_order(
--   p_producto_id := 456
-- );
