-- =====================================================================
-- fn_vista_precios_productos3
-- Vista de precios/costos/ganancias por producto de una tienda.
--
-- CAMBIO PRINCIPAL:
--   El costo de un producto ELABORADO (app_dat_producto.es_elaborado = TRUE)
--   NO se toma de su propia presentacion, sino que se calcula sumando el
--   precio_promedio de las presentaciones de cada uno de sus ingredientes
--   (app_dat_producto_ingredientes -> app_dat_producto_presentacion).
--
--   Para productos NO elaborados el costo sigue saliendo de la presentacion
--   del propio producto (comportamiento original).
--
-- Se reestructuro con CTEs para calcular el costo UNA sola vez y reutilizarlo
-- en todas las columnas derivadas (ganancia / % / USD / CUP), evitando la
-- repeticion de COALESCE anidados y posibles inconsistencias.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.fn_vista_precios_productos3(
    p_id_tienda   BIGINT,
    p_fecha_desde DATE DEFAULT NULL,
    p_fecha_hasta DATE DEFAULT NULL
)
RETURNS TABLE (
    id_tienda                BIGINT,
    id_producto              BIGINT,
    nombre_producto          CHARACTER VARYING,
    precio_venta_cup         NUMERIC,
    precio_venta_usd         NUMERIC,
    precio_costo_usd         NUMERIC,
    precio_costo_cup         NUMERIC,
    valor_usd                NUMERIC,
    ganancia_cup             NUMERIC,
    ganancia_usd             NUMERIC,
    porcentaje_ganancia_cup  NUMERIC,
    porcentaje_ganancia_usd  NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
    -- Tasa USD -> CUP resuelta una sola vez para toda la tienda
    v_tasa NUMERIC;
BEGIN
    -- 1) Resolver la tasa de cambio de la tienda (extraoficial > conversion global > 1)
    v_tasa := COALESCE(
        (
            SELECT tce.valor_cambio
            FROM tasa_cambio_extraoficial tce
            WHERE tce.id_tienda = p_id_tienda
              AND tce.activo = TRUE
              AND tce.id_moneda_origen = 2   -- USD
              AND tce.id_moneda_destino = 1  -- CUP
              AND COALESCE(tce.usar_precio_toque, FALSE) = FALSE
              AND tce.valor_cambio IS NOT NULL
              AND tce.valor_cambio > 0
            ORDER BY tce.created_at DESC
            LIMIT 1
        ),
        (
            SELECT tc_inner.tasa
            FROM tasas_conversion tc_inner
            WHERE tc_inner.moneda_origen = 'USD'
              AND tc_inner.moneda_destino = 'CUP'
            ORDER BY tc_inner.fecha_actualizacion DESC
            LIMIT 1
        ),
        1
    );

    RETURN QUERY
    WITH
    -- 2) Precio de venta mas reciente por producto (variante base = 0)
    precio_venta AS (
        SELECT DISTINCT ON (ven.id_producto, ven.id_variante)
            ven.id_producto,
            ven.id_variante,
            ven.precio_venta_cup
        FROM app_dat_precio_venta ven
        WHERE
            (p_fecha_desde IS NULL AND p_fecha_hasta IS NULL) OR
            (
                (p_fecha_desde IS NULL OR ven.fecha_desde <= p_fecha_hasta)
                AND (p_fecha_hasta IS NULL OR ven.fecha_desde >= p_fecha_desde)
                AND (ven.fecha_hasta IS NULL OR ven.fecha_hasta >= p_fecha_desde)
            )
        ORDER BY ven.id_producto, ven.id_variante, ven.created_at DESC
    ),
    -- 3) Costo directo (presentacion del propio producto) para NO elaborados
    costo_directo AS (
        SELECT DISTINCT ON (pp_inner.id_producto)
            pp_inner.id_producto,
            pp_inner.precio_promedio
        FROM app_dat_producto_presentacion pp_inner
        WHERE pp_inner.precio_promedio IS NOT NULL
          AND pp_inner.precio_promedio > 0
        ORDER BY pp_inner.id_producto, pp_inner.created_at DESC
    ),
    -- 4) Costo por ingredientes para productos ELABORADOS:
    --    suma del precio_promedio (mas reciente) de la presentacion de cada ingrediente.
    costo_elaborado AS (
        SELECT
            ing.id_producto_elaborado AS id_producto,
            SUM(cd_ing.precio_promedio) AS precio_costo_usd
        FROM app_dat_producto_ingredientes ing
        JOIN costo_directo cd_ing
          ON cd_ing.id_producto = ing.id_ingrediente
        GROUP BY ing.id_producto_elaborado
    )
    SELECT
        p.id_tienda::BIGINT,
        p.id::BIGINT AS id_producto,
        p.denominacion::CHARACTER VARYING AS nombre_producto,

        -- Valores base reutilizados
        COALESCE(pv.precio_venta_cup, 0)::NUMERIC AS precio_venta_cup,
        (COALESCE(pv.precio_venta_cup, 0) / NULLIF(v_tasa, 0))::NUMERIC AS precio_venta_usd,

        -- Costo USD: elaborados -> ingredientes ; resto -> presentacion propia
        costo.precio_costo_usd::NUMERIC          AS precio_costo_usd,
        (costo.precio_costo_usd * v_tasa)::NUMERIC AS precio_costo_cup,

        v_tasa::NUMERIC AS valor_usd,

        -- Ganancias
        (COALESCE(pv.precio_venta_cup, 0) - costo.precio_costo_usd * v_tasa)::NUMERIC AS ganancia_cup,
        ((COALESCE(pv.precio_venta_cup, 0) / NULLIF(v_tasa, 0)) - costo.precio_costo_usd)::NUMERIC AS ganancia_usd,

        -- % ganancia CUP (sobre precio de venta CUP)
        CASE
            WHEN COALESCE(pv.precio_venta_cup, 0) > 0 THEN
                ((COALESCE(pv.precio_venta_cup, 0) - costo.precio_costo_usd * v_tasa)
                    / pv.precio_venta_cup) * 100
            ELSE 0
        END::NUMERIC AS porcentaje_ganancia_cup,

        -- % ganancia USD (sobre precio de venta USD)
        CASE
            WHEN (COALESCE(pv.precio_venta_cup, 0) / NULLIF(v_tasa, 0)) > 0 THEN
                (((COALESCE(pv.precio_venta_cup, 0) / NULLIF(v_tasa, 0)) - costo.precio_costo_usd)
                    / (COALESCE(pv.precio_venta_cup, 0) / NULLIF(v_tasa, 0))) * 100
            ELSE 0
        END::NUMERIC AS porcentaje_ganancia_usd
    FROM app_dat_producto p
    LEFT JOIN precio_venta pv
        ON p.id = pv.id_producto AND COALESCE(pv.id_variante, 0) = 0
    -- Costo efectivo: si es elaborado usa la suma de ingredientes; si no, el costo directo
    LEFT JOIN LATERAL (
        SELECT COALESCE(
            CASE WHEN p.es_elaborado THEN ce.precio_costo_usd END,
            cd.precio_promedio,
            0
        ) AS precio_costo_usd
        FROM (SELECT 1) _
        LEFT JOIN costo_elaborado ce ON ce.id_producto = p.id
        LEFT JOIN costo_directo   cd ON cd.id_producto = p.id
    ) costo ON TRUE
    WHERE p.id_tienda = p_id_tienda
    ORDER BY p.denominacion;
END;
$$;
