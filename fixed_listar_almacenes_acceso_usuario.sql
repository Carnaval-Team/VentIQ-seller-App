-- Fixed version of listar_almacenes_acceso_usuario RPC function
CREATE OR REPLACE FUNCTION listar_almacenes_acceso_usuario(
    p_denominacion_filter TEXT DEFAULT NULL,
    p_direccion_filter TEXT DEFAULT NULL,
    p_pagina INTEGER DEFAULT 1,
    p_por_pagina INTEGER DEFAULT 10,
    p_tienda_filter INTEGER DEFAULT NULL,
    p_uuid UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_total_almacenes bigint;
    v_total_paginas integer;
    v_resultado JSONB;
    v_almacenes JSONB;
BEGIN
    -- Verificar que el usuario existe
    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_uuid) THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Usuario no encontrado',
            'data', '{}'::JSONB
        );
    END IF;

    -- Contar total de almacenes con acceso
    SELECT COUNT(*) INTO v_total_almacenes
    FROM app_dat_almacen a
    JOIN app_dat_tienda t ON a.id_tienda = t.id
    WHERE (
        -- Verificar acceso como almacenero
        EXISTS (
            SELECT 1 
            FROM app_dat_almacenero al
            WHERE al.uuid = p_uuid 
            AND al.id_almacen = a.id
        )
        OR
        -- Verificar acceso como gerente de la tienda
        EXISTS (
            SELECT 1 
            FROM app_dat_gerente g
            WHERE g.uuid = p_uuid 
            AND g.id_tienda = t.id
        )
        OR
        -- Verificar acceso como supervisor de la tienda
        EXISTS (
            SELECT 1 
            FROM app_dat_supervisor s
            WHERE s.uuid = p_uuid 
            AND s.id_tienda = t.id
        )
    )
    AND (
        p_denominacion_filter IS NULL OR 
        a.denominacion ILIKE '%' || p_denominacion_filter || '%'
    )
    AND (
        p_direccion_filter IS NULL OR 
        a.direccion ILIKE '%' || p_direccion_filter || '%'
    )
    AND (
        p_tienda_filter IS NULL OR 
        a.id_tienda = p_tienda_filter
    );

    -- Calcular total de páginas
    v_total_paginas := CASE 
        WHEN v_total_almacenes = 0 THEN 0 
        ELSE CEIL(v_total_almacenes::numeric / p_por_pagina) 
    END;

    -- Obtener almacenes con paginación (FIXED: Moved ORDER BY inside subquery)
    WITH almacenes_ordenados AS (
        SELECT 
            a.id,
            a.denominacion,
            a.direccion,
            a.ubicacion,
            a.created_at,
            t.id as tienda_id,
            t.denominacion as tienda_denominacion,
            t.direccion as tienda_direccion
        FROM app_dat_almacen a
        JOIN app_dat_tienda t ON a.id_tienda = t.id
        WHERE (
            EXISTS (
                SELECT 1 
                FROM app_dat_almacenero al
                WHERE al.uuid = p_uuid 
                AND al.id_almacen = a.id
            )
            OR
            EXISTS (
                SELECT 1 
                FROM app_dat_gerente g
                WHERE g.uuid = p_uuid 
                AND g.id_tienda = t.id
            )
            OR
            EXISTS (
                SELECT 1 
                FROM app_dat_supervisor s
                WHERE s.uuid = p_uuid 
                AND s.id_tienda = t.id
            )
        )
        AND (
            p_denominacion_filter IS NULL OR 
            a.denominacion ILIKE '%' || p_denominacion_filter || '%'
        )
        AND (
            p_direccion_filter IS NULL OR 
            a.direccion ILIKE '%' || p_direccion_filter || '%'
        )
        AND (
            p_tienda_filter IS NULL OR 
            a.id_tienda = p_tienda_filter
        )
        ORDER BY t.denominacion, a.denominacion
        LIMIT p_por_pagina
        OFFSET (p_pagina - 1) * p_por_pagina
    )
    SELECT JSONB_AGG(
        JSONB_BUILD_OBJECT(
            'id', ao.id,
            'denominacion', ao.denominacion,
            'direccion', ao.direccion,
            'ubicacion', ao.ubicacion,
            'created_at', ao.created_at,
            'tienda', JSONB_BUILD_OBJECT(
                'id', ao.tienda_id,
                'denominacion', ao.tienda_denominacion,
                'direccion', ao.tienda_direccion
            ),
            'roles', (
                SELECT JSONB_AGG(DISTINCT rol)
                FROM (
                    SELECT 'ALMACENERO' as rol
                    FROM app_dat_almacenero al
                    WHERE al.uuid = p_uuid 
                    AND al.id_almacen = ao.id
                    UNION
                    SELECT 'GERENTE' as rol
                    FROM app_dat_gerente g
                    WHERE g.uuid = p_uuid 
                    AND g.id_tienda = ao.tienda_id
                    UNION
                    SELECT 'SUPERVISOR' as rol
                    FROM app_dat_supervisor s
                    WHERE s.uuid = p_uuid 
                    AND s.id_tienda = ao.tienda_id
                ) roles
            ),
            'layouts', (
                SELECT JSONB_AGG(
                    JSONB_BUILD_OBJECT(
                        'id', la.id,
                        'denominacion', la.denominacion,
                        'tipo_layout', tl.denominacion,
                        'sku_codigo', la.sku_codigo
                    )
                )
                FROM app_dat_layout_almacen la
                JOIN app_nom_tipo_layout_almacen tl ON la.id_tipo_layout = tl.id
                WHERE la.id_almacen = ao.id
            ),
            'condiciones', (
                SELECT JSONB_AGG(
                    JSONB_BUILD_OBJECT(
                        'id', tc.id,
                        'denominacion', tc.denominacion
                    )
                )
                FROM app_dat_layout_condiciones lc
                JOIN app_nom_tipo_condicion tc ON lc.id_condicion = tc.id
                WHERE lc.id_layout = ao.id
            ),
            'almaceneros_count', (
                SELECT COUNT(*) 
                FROM app_dat_almacenero al2
                WHERE al2.id_almacen = ao.id
            ),
            'limites_stock_count', (
                SELECT COUNT(*) 
                FROM app_dat_almacen_limites alim
                WHERE alim.id_almacen = ao.id
            )
        )
    ) INTO v_almacenes
    FROM almacenes_ordenados ao;

    -- Construir respuesta
    v_resultado := JSONB_BUILD_OBJECT(
        'success', true,
        'data', JSONB_BUILD_OBJECT(
            'almacenes', COALESCE(v_almacenes, '[]'::JSONB),
            'paginacion', JSONB_BUILD_OBJECT(
                'pagina_actual', p_pagina,
                'por_pagina', p_por_pagina,
                'total_almacenes', v_total_almacenes,
                'total_paginas', v_total_paginas,
                'tiene_anterior', p_pagina > 1,
                'tiene_siguiente', p_pagina < v_total_paginas
            )
        )
    );

    RETURN v_resultado;

EXCEPTION
    WHEN OTHERS THEN
        RETURN JSONB_BUILD_OBJECT(
            'success', false,
            'message', 'Error al listar almacenes: ' || SQLERRM,
            'error_code', SQLSTATE
        );
END;
$$;
