CREATE OR REPLACE FUNCTION fn_inventario_resumen_por_usuario_almacen2(
    p_id_tienda BIGINT DEFAULT NULL,
    p_id_almacen BIGINT DEFAULT NULL,
    p_busqueda TEXT DEFAULT NULL,
    p_mostrar_sin_stock BOOLEAN DEFAULT TRUE,
    p_limite INTEGER DEFAULT 50,
    p_pagina INTEGER DEFAULT 1
)
RETURNS TABLE(
    prod_id BIGINT,
    prod_nombre VARCHAR,
    prod_sku VARCHAR,
    variante_id BIGINT,
    variante_valor VARCHAR,
    opcion_variante_id BIGINT,
    opcion_variante_valor VARCHAR,
    cant_unidades_base NUMERIC,
    cant_almacen_total NUMERIC,
    stock_disponible NUMERIC,
    stock_reservado NUMERIC,
    zonas_count INTEGER,
    presentaciones_count INTEGER,
    total_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_offset INTEGER := (p_pagina - 1) * p_limite;
    v_total_count BIGINT;
BEGIN
    -- Establecer contexto seguro
    SET search_path = public;


    -- Validar autenticación
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Usuario no autenticado';
    END IF;


    -- Validar acceso si se especifica tienda
    IF p_id_tienda IS NOT NULL THEN
        PERFORM check_user_has_access_to_tienda(p_id_tienda);
        
        -- Validar que la tienda exista
        IF NOT EXISTS (SELECT 1 FROM app_dat_tienda t WHERE t.id = p_id_tienda) THEN
            RAISE EXCEPTION 'La tienda con ID % no existe', p_id_tienda;
        END IF;
    END IF;


    -- Validar que el almacén pertenezca a la tienda si ambos están especificados
    IF p_id_tienda IS NOT NULL AND p_id_almacen IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM app_dat_almacen a 
            WHERE a.id = p_id_almacen AND a.id_tienda = p_id_tienda
        ) THEN
            RAISE EXCEPTION 'El almacén con ID % no pertenece a la tienda con ID %', p_id_almacen, p_id_tienda;
        END IF;
    END IF;


    -- Contar total de resultados para paginación
    WITH usuario_roles AS (
        -- Obtener tiendas a las que el usuario tiene acceso
        SELECT DISTINCT t.id AS id_tienda
        FROM app_dat_tienda t
        WHERE EXISTS (
            SELECT 1 FROM app_dat_gerente g WHERE g.uuid = auth.uid() AND g.id_tienda = t.id
            UNION
            SELECT 1 FROM app_dat_supervisor s WHERE s.uuid = auth.uid() AND s.id_tienda = t.id
            UNION
            SELECT 1 FROM app_dat_almacenero a
            JOIN app_dat_almacen alm ON a.id_almacen = alm.id
            WHERE a.uuid = auth.uid() AND alm.id_tienda = t.id
            UNION
            SELECT 1 FROM app_dat_vendedor v
            JOIN app_dat_tpv tpv ON v.id_tpv = tpv.id
            WHERE v.uuid = auth.uid() AND tpv.id_tienda = t.id
        )
        AND (p_id_tienda IS NULL OR t.id = p_id_tienda)
    ),
    inventario_con_acceso AS (
        -- Filtrar ubicaciones a las que el usuario tiene acceso
        SELECT l.id AS id_ubicacion, alm.id AS id_almacen, alm.id_tienda
        FROM app_dat_layout_almacen l
        JOIN app_dat_almacen alm ON l.id_almacen = alm.id
        JOIN usuario_roles ur ON alm.id_tienda = ur.id_tienda
        WHERE (p_id_almacen IS NULL OR alm.id = p_id_almacen)
    ),
    ultima_inventario AS (
        -- Obtener la última entrada de inventario para cada combinación
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
        -- Solo la última operación por combinación
        SELECT *
        FROM ultima_inventario
        WHERE rn = 1
    ),
    presentacion_base AS (
        -- Factor de conversión a unidad base
        SELECT 
            id_producto,
            cantidad AS factor
        FROM app_dat_producto_presentacion
        WHERE es_base = true
    ),
    stock_reservado AS (
        -- Calcular stock reservado por producto/variante/ubicación
        SELECT
            ep.id_producto,
            COALESCE(ep.id_variante, 0) as id_variante,
            COALESCE(ep.id_opcion_variante, 0) as id_opcion_variante,
            ep.id_ubicacion,
            SUM(ep.cantidad) AS reservado
        FROM app_dat_extraccion_productos ep
        INNER JOIN app_dat_operaciones o ON ep.id_operacion = o.id
        INNER JOIN app_dat_estado_operacion eo ON o.id = eo.id_operacion
        INNER JOIN inventario_con_acceso ia ON ep.id_ubicacion = ia.id_ubicacion
        WHERE eo.estado = 1 -- Pendiente
        GROUP BY ep.id_producto, COALESCE(ep.id_variante, 0), COALESCE(ep.id_opcion_variante, 0), ep.id_ubicacion
    ),
    resumen AS (
        SELECT 
            u.id_producto,
            u.id_variante,
            u.id_opcion_variante,
            COALESCE(pb.factor, 1) AS factor_base,
            SUM(u.cantidad_final) AS cant_almacen_total,
            SUM(u.cantidad_final * COALESCE(pb.factor, 1)) AS cant_unidades_base,
            SUM(GREATEST(u.cantidad_final - COALESCE(sr.reservado, 0), 0)) AS stock_disponible_total,
            SUM(COALESCE(sr.reservado, 0)) AS stock_reservado_total,
            COUNT(DISTINCT u.id_ubicacion) AS zonas_count,
            COUNT(DISTINCT u.id_presentacion) AS presentaciones_count
        FROM ultimas u
        LEFT JOIN presentacion_base pb ON u.id_producto = pb.id_producto
        LEFT JOIN stock_reservado sr ON (
            u.id_producto = sr.id_producto
            AND COALESCE(u.id_variante, 0) = sr.id_variante
            AND COALESCE(u.id_opcion_variante, 0) = sr.id_opcion_variante
            AND u.id_ubicacion = sr.id_ubicacion
        )
        GROUP BY u.id_producto, u.id_variante, u.id_opcion_variante, COALESCE(pb.factor, 1)
    ),
    resumen_filtrado AS (
        SELECT r.*
        FROM resumen r
        JOIN app_dat_producto p ON r.id_producto = p.id
        LEFT JOIN app_dat_atributo_opcion ao ON r.id_variante = ao.id
        LEFT JOIN app_dat_atributo_opcion aoo ON r.id_opcion_variante = aoo.id
        WHERE (
            p_busqueda IS NULL OR
            p.denominacion ILIKE '%' || p_busqueda || '%' OR
            p.sku ILIKE '%' || p_busqueda || '%' OR
            p.nombre_comercial ILIKE '%' || p_busqueda || '%' OR
            p.denominacion_corta ILIKE '%' || p_busqueda || '%' OR
            p.codigo_barras ILIKE '%' || p_busqueda || '%' OR
            ao.valor ILIKE '%' || p_busqueda || '%' OR
            aoo.valor ILIKE '%' || p_busqueda || '%'
        )
    )
    SELECT COUNT(*) INTO v_total_count FROM resumen_filtrado;


    -- Retornar resultados paginados
    RETURN QUERY
    WITH usuario_roles AS (
        -- Obtener tiendas a las que el usuario tiene acceso
        SELECT DISTINCT t.id AS id_tienda
        FROM app_dat_tienda t
        WHERE EXISTS (
            SELECT 1 FROM app_dat_gerente g WHERE g.uuid = auth.uid() AND g.id_tienda = t.id
            UNION
            SELECT 1 FROM app_dat_supervisor s WHERE s.uuid = auth.uid() AND s.id_tienda = t.id
            UNION
            SELECT 1 FROM app_dat_almacenero a
            JOIN app_dat_almacen alm ON a.id_almacen = alm.id
            WHERE a.uuid = auth.uid() AND alm.id_tienda = t.id
            UNION
            SELECT 1 FROM app_dat_vendedor v
            JOIN app_dat_tpv tpv ON v.id_tpv = tpv.id
            WHERE v.uuid = auth.uid() AND tpv.id_tienda = t.id
        )
        AND (p_id_tienda IS NULL OR t.id = p_id_tienda)
    ),
    inventario_con_acceso AS (
        -- Filtrar ubicaciones a las que el usuario tiene acceso
        SELECT l.id AS id_ubicacion, alm.id AS id_almacen, alm.id_tienda
        FROM app_dat_layout_almacen l
        JOIN app_dat_almacen alm ON l.id_almacen = alm.id
        JOIN usuario_roles ur ON alm.id_tienda = ur.id_tienda
        WHERE (p_id_almacen IS NULL OR alm.id = p_id_almacen)
    ),
    ultima_inventario AS (
        -- Obtener la última entrada de inventario para cada combinación
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
        -- Solo la última operación por combinación
        SELECT *
        FROM ultima_inventario
        WHERE rn = 1
    ),
    presentacion_base AS (
        -- Factor de conversión a unidad base
        SELECT 
            id_producto,
            cantidad AS factor
        FROM app_dat_producto_presentacion
        WHERE es_base = true
    ),
    stock_reservado AS (
        -- Calcular stock reservado por producto/variante/ubicación
        SELECT
            ep.id_producto,
            COALESCE(ep.id_variante, 0) as id_variante,
            COALESCE(ep.id_opcion_variante, 0) as id_opcion_variante,
            ep.id_ubicacion,
            SUM(ep.cantidad) AS reservado
        FROM app_dat_extraccion_productos ep
        INNER JOIN app_dat_operaciones o ON ep.id_operacion = o.id
        INNER JOIN app_dat_estado_operacion eo ON o.id = eo.id_operacion
        INNER JOIN inventario_con_acceso ia ON ep.id_ubicacion = ia.id_ubicacion
        WHERE eo.estado = 1 -- Pendiente
        GROUP BY ep.id_producto, COALESCE(ep.id_variante, 0), COALESCE(ep.id_opcion_variante, 0), ep.id_ubicacion
    ),
    resumen AS (
        SELECT 
            u.id_producto,
            u.id_variante,
            u.id_opcion_variante,
            COALESCE(pb.factor, 1) AS factor_base,
            SUM(u.cantidad_final) AS cant_almacen_total,
            SUM(u.cantidad_final * COALESCE(pb.factor, 1)) AS cant_unidades_base,
            SUM(GREATEST(u.cantidad_final - COALESCE(sr.reservado, 0), 0)) AS stock_disponible_total,
            SUM(COALESCE(sr.reservado, 0)) AS stock_reservado_total,
            COUNT(DISTINCT u.id_ubicacion) AS zonas_count,
            COUNT(DISTINCT u.id_presentacion) AS presentaciones_count
        FROM ultimas u
        LEFT JOIN presentacion_base pb ON u.id_producto = pb.id_producto
        LEFT JOIN stock_reservado sr ON (
            u.id_producto = sr.id_producto
            AND COALESCE(u.id_variante, 0) = sr.id_variante
            AND COALESCE(u.id_opcion_variante, 0) = sr.id_opcion_variante
            AND u.id_ubicacion = sr.id_ubicacion
        )
        GROUP BY u.id_producto, u.id_variante, u.id_opcion_variante, COALESCE(pb.factor, 1)
    )
    SELECT 
        r.id_producto::BIGINT AS prod_id,
        p.denominacion::VARCHAR AS prod_nombre,
        COALESCE(p.sku, '')::VARCHAR AS prod_sku,
        r.id_variante::BIGINT AS variante_id,
        COALESCE(ao.valor, 'N/A')::VARCHAR AS variante_valor,
        r.id_opcion_variante::BIGINT AS opcion_variante_id,
        COALESCE(aoo.valor, 'N/A')::VARCHAR AS opcion_variante_valor,
        ROUND(r.cant_unidades_base, 3)::NUMERIC AS cant_unidades_base,
        ROUND(r.cant_almacen_total, 3)::NUMERIC AS cant_almacen_total,
        ROUND(r.stock_disponible_total, 3)::NUMERIC AS stock_disponible,
        ROUND(r.stock_reservado_total, 3)::NUMERIC AS stock_reservado,
        r.zonas_count::INTEGER AS zonas_count,
        r.presentaciones_count::INTEGER AS presentaciones_count,
        v_total_count::BIGINT AS total_count
    FROM resumen r
    JOIN app_dat_producto p ON r.id_producto = p.id
    LEFT JOIN app_dat_atributo_opcion ao ON r.id_variante = ao.id
    LEFT JOIN app_dat_atributo_opcion aoo ON r.id_opcion_variante = aoo.id
    WHERE (
        p_busqueda IS NULL OR
        p.denominacion ILIKE '%' || p_busqueda || '%' OR
        p.sku ILIKE '%' || p_busqueda || '%' OR
        p.nombre_comercial ILIKE '%' || p_busqueda || '%' OR
        p.denominacion_corta ILIKE '%' || p_busqueda || '%' OR
        p.codigo_barras ILIKE '%' || p_busqueda || '%' OR
        ao.valor ILIKE '%' || p_busqueda || '%' OR
        aoo.valor ILIKE '%' || p_busqueda || '%'
    )
    ORDER BY p.denominacion, r.cant_unidades_base DESC
    LIMIT p_limite
    OFFSET v_offset;
END;
$$;
