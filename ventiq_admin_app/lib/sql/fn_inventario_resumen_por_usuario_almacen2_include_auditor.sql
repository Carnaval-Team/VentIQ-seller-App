-- ============================================================================
-- FIX: fn_inventario_resumen_por_usuario_almacen2 — incluir rol auditor
-- ============================================================================
-- Sintoma: InventoryStockScreen (vista resumen por defecto) lista 0 productos
-- para usuarios cuyo unico rol admin es auditor. check_user_has_access_to_tienda
-- ya incluye auditor, pero el CTE usuario_roles del resumen NO — el JOIN deja
-- inventario_con_acceso vacio y la UI recibe lista vacia sin error.
--
-- Llamado desde: InventoryService.getInventorySummaryByUser
--   -> fn_inventario_resumen_por_usuario_almacen3 (wrapper)
--     -> fn_inventario_resumen_por_usuario_almacen2
--
-- Aplicar en SQL Editor. Idempotente (CREATE OR REPLACE). Firma sin cambios.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_inventario_resumen_por_usuario_almacen2(
    p_id_tienda bigint DEFAULT NULL::bigint,
    p_id_almacen bigint DEFAULT NULL::bigint,
    p_busqueda text DEFAULT NULL::text,
    p_mostrar_sin_stock boolean DEFAULT true,
    p_filtro_stock text DEFAULT 'Todos'::text,
    p_limite integer DEFAULT 50,
    p_pagina integer DEFAULT 1
)
RETURNS TABLE(
    prod_id bigint,
    prod_nombre character varying,
    prod_sku character varying,
    variante_id bigint,
    variante_valor character varying,
    opcion_variante_id bigint,
    opcion_variante_valor character varying,
    cant_unidades_base numeric,
    cant_almacen_total numeric,
    stock_disponible numeric,
    stock_reservado numeric,
    zonas_count integer,
    presentaciones_count integer,
    total_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_offset INTEGER := (p_pagina - 1) * p_limite;
    v_total_count BIGINT;
BEGIN
    SET search_path = public;

    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Usuario no autenticado';
    END IF;

    IF p_id_tienda IS NOT NULL THEN
        PERFORM check_user_has_access_to_tienda(p_id_tienda);
        IF NOT EXISTS (SELECT 1 FROM app_dat_tienda t WHERE t.id = p_id_tienda) THEN
            RAISE EXCEPTION 'La tienda con ID % no existe', p_id_tienda;
        END IF;
    END IF;

    IF p_id_tienda IS NOT NULL AND p_id_almacen IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM app_dat_almacen a
            WHERE a.id = p_id_almacen AND a.id_tienda = p_id_tienda
        ) THEN
            RAISE EXCEPTION 'El almacén con ID % no pertenece a la tienda con ID %',
                p_id_almacen, p_id_tienda;
        END IF;
    END IF;

    WITH usuario_roles AS (
        SELECT DISTINCT t.id AS id_tienda
        FROM app_dat_tienda t
        WHERE EXISTS (
            SELECT 1 FROM app_dat_gerente g
            WHERE g.uuid = auth.uid() AND g.id_tienda = t.id
            UNION
            SELECT 1 FROM app_dat_supervisor s
            WHERE s.uuid = auth.uid() AND s.id_tienda = t.id
            UNION
            SELECT 1 FROM app_dat_almacenero a
            JOIN app_dat_almacen alm ON a.id_almacen = alm.id
            WHERE a.uuid = auth.uid() AND alm.id_tienda = t.id
            UNION
            SELECT 1 FROM app_dat_vendedor v
            JOIN app_dat_tpv tpv ON v.id_tpv = tpv.id
            WHERE v.uuid = auth.uid() AND tpv.id_tienda = t.id
            UNION
            SELECT 1 FROM auditor aud
            WHERE aud.uuid = auth.uid() AND aud.id_tienda = t.id
        )
        AND (p_id_tienda IS NULL OR t.id = p_id_tienda)
    ),
    inventario_con_acceso AS (
        SELECT l.id AS id_ubicacion, alm.id AS id_almacen, alm.id_tienda
        FROM app_dat_layout_almacen l
        JOIN app_dat_almacen alm ON l.id_almacen = alm.id
        JOIN usuario_roles ur ON alm.id_tienda = ur.id_tienda
        WHERE (p_id_almacen IS NULL OR alm.id = p_id_almacen)
    ),
    ultima_inventario AS (
        SELECT
            ip.id_producto,
            ip.id_variante,
            ip.id_opcion_variante,
            ip.id_ubicacion,
            ip.id_presentacion,
            ip.cantidad_final,
            ROW_NUMBER() OVER (
                PARTITION BY
                    ip.id_producto,
                    ip.id_variante,
                    ip.id_opcion_variante,
                    ip.id_ubicacion,
                    ip.id_presentacion
                ORDER BY ip.created_at DESC
            ) AS rn
        FROM app_dat_inventario_productos ip
        JOIN inventario_con_acceso ia ON ip.id_ubicacion = ia.id_ubicacion
        WHERE ip.cantidad_final IS NOT NULL
          AND (p_mostrar_sin_stock = TRUE OR ip.cantidad_final > 0)
    ),
    ultimas AS (
        SELECT * FROM ultima_inventario WHERE rn = 1
    ),
    presentacion_base AS (
        SELECT pp.id_producto, pp.id AS id_presentacion, c.factor_rel AS factor
        FROM app_dat_producto_presentacion pp
        JOIN LATERAL public.fn_presentaciones_producto(pp.id_producto) c
            ON c.id_presentacion = pp.id
    ),
    stock_reservado AS (
        SELECT
            ep.id_producto,
            COALESCE(ep.id_variante, 0) AS id_variante,
            COALESCE(ep.id_opcion_variante, 0) AS id_opcion_variante,
            ep.id_ubicacion,
            SUM(ep.cantidad) AS reservado
        FROM app_dat_extraccion_productos ep
        INNER JOIN app_dat_operaciones o ON ep.id_operacion = o.id
        INNER JOIN app_dat_estado_operacion eo ON o.id = eo.id_operacion
        INNER JOIN inventario_con_acceso ia ON ep.id_ubicacion = ia.id_ubicacion
        WHERE eo.estado = 1
        GROUP BY
            ep.id_producto,
            COALESCE(ep.id_variante, 0),
            COALESCE(ep.id_opcion_variante, 0),
            ep.id_ubicacion
    ),
    resumen AS (
        SELECT
            u.id_producto,
            u.id_variante,
            u.id_opcion_variante,
            SUM(u.cantidad_final) AS cant_almacen_total,
            SUM(u.cantidad_final * COALESCE(pb.factor, 1)) AS cant_unidades_base,
            SUM(GREATEST(u.cantidad_final - COALESCE(sr.reservado, 0), 0)) AS stock_disponible_total,
            SUM(COALESCE(sr.reservado, 0)) AS stock_reservado_total,
            COUNT(DISTINCT u.id_ubicacion) AS zonas_count,
            COUNT(DISTINCT u.id_presentacion) AS presentaciones_count
        FROM ultimas u
        LEFT JOIN presentacion_base pb
            ON u.id_producto = pb.id_producto
           AND u.id_presentacion = pb.id_presentacion
        LEFT JOIN stock_reservado sr ON (
            u.id_producto = sr.id_producto
            AND COALESCE(u.id_variante, 0) = sr.id_variante
            AND COALESCE(u.id_opcion_variante, 0) = sr.id_opcion_variante
            AND u.id_ubicacion = sr.id_ubicacion
        )
        GROUP BY u.id_producto, u.id_variante, u.id_opcion_variante
    ),
    resumen_filtrado AS (
        SELECT r.*
        FROM resumen r
        JOIN app_dat_producto p ON r.id_producto = p.id
        LEFT JOIN app_dat_atributo_opcion ao ON r.id_variante = ao.id
        LEFT JOIN app_dat_atributo_opcion aoo ON r.id_opcion_variante = aoo.id
        WHERE (
            p_busqueda IS NULL
            OR p.denominacion ILIKE '%' || p_busqueda || '%'
            OR p.sku ILIKE '%' || p_busqueda || '%'
            OR p.nombre_comercial ILIKE '%' || p_busqueda || '%'
            OR p.denominacion_corta ILIKE '%' || p_busqueda || '%'
            OR p.codigo_barras ILIKE '%' || p_busqueda || '%'
            OR ao.valor ILIKE '%' || p_busqueda || '%'
            OR aoo.valor ILIKE '%' || p_busqueda || '%'
        )
        AND (
            CASE
                WHEN p_filtro_stock = 'Sin Stock' THEN r.cant_almacen_total <= 0
                WHEN p_filtro_stock = 'Stock Bajo' THEN
                    r.cant_almacen_total > 0 AND r.cant_almacen_total <= 10
                WHEN p_filtro_stock = 'Stock OK' THEN r.cant_almacen_total > 10
                ELSE TRUE
            END
        )
    )
    SELECT COUNT(*) INTO v_total_count FROM resumen_filtrado;

    RETURN QUERY
    WITH usuario_roles AS (
        SELECT DISTINCT t.id AS id_tienda
        FROM app_dat_tienda t
        WHERE EXISTS (
            SELECT 1 FROM app_dat_gerente g
            WHERE g.uuid = auth.uid() AND g.id_tienda = t.id
            UNION
            SELECT 1 FROM app_dat_supervisor s
            WHERE s.uuid = auth.uid() AND s.id_tienda = t.id
            UNION
            SELECT 1 FROM app_dat_almacenero a
            JOIN app_dat_almacen alm ON a.id_almacen = alm.id
            WHERE a.uuid = auth.uid() AND alm.id_tienda = t.id
            UNION
            SELECT 1 FROM app_dat_vendedor v
            JOIN app_dat_tpv tpv ON v.id_tpv = tpv.id
            WHERE v.uuid = auth.uid() AND tpv.id_tienda = t.id
            UNION
            SELECT 1 FROM auditor aud
            WHERE aud.uuid = auth.uid() AND aud.id_tienda = t.id
        )
        AND (p_id_tienda IS NULL OR t.id = p_id_tienda)
    ),
    inventario_con_acceso AS (
        SELECT l.id AS id_ubicacion, alm.id AS id_almacen, alm.id_tienda
        FROM app_dat_layout_almacen l
        JOIN app_dat_almacen alm ON l.id_almacen = alm.id
        JOIN usuario_roles ur ON alm.id_tienda = ur.id_tienda
        WHERE (p_id_almacen IS NULL OR alm.id = p_id_almacen)
    ),
    ultima_inventario AS (
        SELECT
            ip.id_producto,
            ip.id_variante,
            ip.id_opcion_variante,
            ip.id_ubicacion,
            ip.id_presentacion,
            ip.cantidad_final,
            ROW_NUMBER() OVER (
                PARTITION BY
                    ip.id_producto,
                    ip.id_variante,
                    ip.id_opcion_variante,
                    ip.id_ubicacion,
                    ip.id_presentacion
                ORDER BY ip.created_at DESC
            ) AS rn
        FROM app_dat_inventario_productos ip
        JOIN inventario_con_acceso ia ON ip.id_ubicacion = ia.id_ubicacion
        WHERE ip.cantidad_final IS NOT NULL
          AND (p_mostrar_sin_stock = TRUE OR ip.cantidad_final > 0)
    ),
    ultimas AS (
        SELECT * FROM ultima_inventario WHERE rn = 1
    ),
    presentacion_base AS (
        SELECT pp.id_producto, pp.id AS id_presentacion, c.factor_rel AS factor
        FROM app_dat_producto_presentacion pp
        JOIN LATERAL public.fn_presentaciones_producto(pp.id_producto) c
            ON c.id_presentacion = pp.id
    ),
    stock_reservado AS (
        SELECT
            ep.id_producto,
            COALESCE(ep.id_variante, 0) AS id_variante,
            COALESCE(ep.id_opcion_variante, 0) AS id_opcion_variante,
            ep.id_ubicacion,
            SUM(ep.cantidad) AS reservado
        FROM app_dat_extraccion_productos ep
        INNER JOIN app_dat_operaciones o ON ep.id_operacion = o.id
        INNER JOIN app_dat_estado_operacion eo ON o.id = eo.id_operacion
        INNER JOIN inventario_con_acceso ia ON ep.id_ubicacion = ia.id_ubicacion
        WHERE eo.estado = 1
        GROUP BY
            ep.id_producto,
            COALESCE(ep.id_variante, 0),
            COALESCE(ep.id_opcion_variante, 0),
            ep.id_ubicacion
    ),
    resumen AS (
        SELECT
            u.id_producto,
            u.id_variante,
            u.id_opcion_variante,
            SUM(u.cantidad_final) AS cant_almacen_total,
            SUM(u.cantidad_final * COALESCE(pb.factor, 1)) AS cant_unidades_base,
            SUM(GREATEST(u.cantidad_final - COALESCE(sr.reservado, 0), 0)) AS stock_disponible_total,
            SUM(COALESCE(sr.reservado, 0)) AS stock_reservado_total,
            COUNT(DISTINCT u.id_ubicacion) AS zonas_count,
            COUNT(DISTINCT u.id_presentacion) AS presentaciones_count
        FROM ultimas u
        LEFT JOIN presentacion_base pb
            ON u.id_producto = pb.id_producto
           AND u.id_presentacion = pb.id_presentacion
        LEFT JOIN stock_reservado sr ON (
            u.id_producto = sr.id_producto
            AND COALESCE(u.id_variante, 0) = sr.id_variante
            AND COALESCE(u.id_opcion_variante, 0) = sr.id_opcion_variante
            AND u.id_ubicacion = sr.id_ubicacion
        )
        GROUP BY u.id_producto, u.id_variante, u.id_opcion_variante
    )
    SELECT
        r.id_producto::BIGINT,
        p.denominacion::VARCHAR,
        COALESCE(p.sku, '')::VARCHAR,
        r.id_variante::BIGINT,
        COALESCE(ao.valor, 'N/A')::VARCHAR,
        r.id_opcion_variante::BIGINT,
        COALESCE(aoo.valor, 'N/A')::VARCHAR,
        ROUND(r.cant_unidades_base, 3)::NUMERIC,
        ROUND(r.cant_almacen_total, 3)::NUMERIC,
        ROUND(r.stock_disponible_total, 3)::NUMERIC,
        ROUND(r.stock_reservado_total, 3)::NUMERIC,
        r.zonas_count::INTEGER,
        r.presentaciones_count::INTEGER,
        v_total_count::BIGINT
    FROM resumen r
    JOIN app_dat_producto p ON r.id_producto = p.id
    LEFT JOIN app_dat_atributo_opcion ao ON r.id_variante = ao.id
    LEFT JOIN app_dat_atributo_opcion aoo ON r.id_opcion_variante = aoo.id
    WHERE (
        p_busqueda IS NULL
        OR p.denominacion ILIKE '%' || p_busqueda || '%'
        OR p.sku ILIKE '%' || p_busqueda || '%'
        OR p.nombre_comercial ILIKE '%' || p_busqueda || '%'
        OR p.denominacion_corta ILIKE '%' || p_busqueda || '%'
        OR p.codigo_barras ILIKE '%' || p_busqueda || '%'
        OR ao.valor ILIKE '%' || p_busqueda || '%'
        OR aoo.valor ILIKE '%' || p_busqueda || '%'
    )
    AND (
        CASE
            WHEN p_filtro_stock = 'Sin Stock' THEN r.cant_almacen_total <= 0
            WHEN p_filtro_stock = 'Stock Bajo' THEN
                r.cant_almacen_total > 0 AND r.cant_almacen_total <= 10
            WHEN p_filtro_stock = 'Stock OK' THEN r.cant_almacen_total > 10
            ELSE TRUE
        END
    )
    ORDER BY p.denominacion, r.cant_unidades_base DESC
    LIMIT p_limite OFFSET v_offset;
END;
$function$;

COMMENT ON FUNCTION public.fn_inventario_resumen_por_usuario_almacen2(
    bigint, bigint, text, boolean, text, integer, integer
) IS
  'Resumen de inventario por usuario/almacen. Incluye gerente, supervisor, '
  'almacenero, vendedor y auditor en usuario_roles.';
