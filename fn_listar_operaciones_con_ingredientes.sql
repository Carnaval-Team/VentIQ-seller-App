-- Función RPC modificada para incluir ingredientes de productos elaborados
CREATE OR REPLACE FUNCTION fn_listar_operaciones_con_ingredientes(
    fecha_desde_param timestamptz DEFAULT NULL,
    fecha_hasta_param timestamptz DEFAULT NULL,
    id_tienda_param BIGINT DEFAULT NULL,
    id_tpv_param BIGINT DEFAULT NULL,
    id_usuario_param UUID DEFAULT NULL,
    id_estado_param INTEGER DEFAULT NULL,
    id_tipo_operacion_param BIGINT DEFAULT NULL,
    limite_param INTEGER DEFAULT 50,
    pagina_param INTEGER DEFAULT 1
)
RETURNS TABLE(
    id_operacion BIGINT,
    tipo_operacion VARCHAR,
    id_tienda BIGINT,
    tienda_nombre VARCHAR,
    id_tpv BIGINT,
    tpv_nombre VARCHAR,
    usuario_nombre VARCHAR,
    estado INTEGER,
    estado_nombre VARCHAR,
    fecha_operacion TIMESTAMPTZ,
    total_operacion NUMERIC,
    cantidad_items INTEGER,
    observaciones TEXT,
    detalles JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_fecha_inicio timestamptz;
    v_fecha_fin timestamptz;
    v_tiene_turno_abierto boolean := false;
    v_id_turno_abierto BIGINT;
    v_uuid_usuario UUID := NULL;
BEGIN
    -- Establecer contexto
    SET search_path = public;

    -- Obtener el usuario autenticado si no se pasa
    v_uuid_usuario := COALESCE(id_usuario_param, auth.uid());
    -- Verificar que el usuario tenga permisos en al menos una tienda
    PERFORM check_user_has_access_to_any_tienda();
    
    -- Si NO se pasan fechas, usamos el turno abierto del vendedor en el TPV
    IF fecha_desde_param IS NULL AND fecha_hasta_param IS NULL AND id_tpv_param IS NOT NULL AND v_uuid_usuario IS NOT NULL THEN
        -- Buscar el turno abierto del vendedor en ese TPV
        SELECT ct.id, ct.fecha_apertura
        INTO v_id_turno_abierto, v_fecha_inicio
        FROM app_dat_caja_turno ct
        JOIN app_dat_vendedor v ON ct.id_vendedor = v.id
        WHERE ct.id_tpv = id_tpv_param
          AND v.uuid = v_uuid_usuario
          AND ct.estado = 1 -- Abierto
        ORDER BY ct.fecha_apertura DESC
        LIMIT 1;

        IF NOT FOUND THEN
            -- No hay turno abierto → no devolver nada
            RETURN;
        END IF;

        v_fecha_fin := NOW(); -- Hasta ahora
        v_tiene_turno_abierto := TRUE;
    ELSE
        -- Si se pasan fechas, usamos ese rango
        v_fecha_inicio := fecha_desde_param;
        v_fecha_fin := COALESCE(fecha_hasta_param, CURRENT_DATE) + INTERVAL '1 day' - INTERVAL '1 second';
    END IF;

    RETURN QUERY
    WITH operaciones_filtradas AS (
        SELECT 
            o.id,
            o.created_at,
            o.id_tipo_operacion,
            top.denominacion AS tipo_operacion_nombre,
            o.id_tienda,
            t.denominacion AS tienda_nombre,
            o.uuid,
            COALESCE(u.email, 'Sistema') AS usuario_email,
            e.estado,
            CASE 
                WHEN e.estado = 1 THEN 'Pendiente'
                WHEN e.estado = 2 THEN 'Completada'
                WHEN e.estado = 3 THEN 'Cancelada'
                WHEN e.estado = 4 THEN 'En Proceso'
                ELSE 'Desconocido'
            END AS estado_nombre,
            o.observaciones::TEXT,
            -- Datos específicos de TPV para operaciones de venta
            CASE 
                WHEN o.id_tipo_operacion = (SELECT id FROM app_nom_tipo_operacion WHERE LOWER(denominacion) = 'venta' LIMIT 1) THEN
                    (SELECT jsonb_build_object(
                        'id_tpv', ov.id_tpv,
                        'tpv_nombre', tp.denominacion,
                        'codigo_promocion', ov.codigo_promocion,
                        'id_cliente', ov.id_cliente,
                        'cliente_nombre', cli.nombre_completo,
                        'cliente_telefono', cli.telefono
                    ) 
                    FROM app_dat_operacion_venta ov 
                    JOIN app_dat_tpv tp ON ov.id_tpv = tp.id
                    LEFT JOIN app_dat_clientes cli ON ov.id_cliente = cli.id
                    WHERE ov.id_operacion = o.id
                    LIMIT 1)
                ELSE NULL
            END AS datos_especificos,
            -- Contar items en la operación
            (SELECT COUNT(*) FROM app_dat_extraccion_productos ep WHERE ep.id_operacion = o.id)::INTEGER AS cantidad_items,
            -- Calcular total de la operación
            (SELECT COALESCE(SUM(ep.importe), 0) FROM app_dat_extraccion_productos ep WHERE ep.id_operacion = o.id) AS total_operacion
        FROM 
            app_dat_operaciones o
        JOIN 
            app_nom_tipo_operacion top ON o.id_tipo_operacion = top.id
        JOIN 
            app_dat_tienda t ON o.id_tienda = t.id
        LEFT JOIN 
            auth.users u ON o.uuid = u.id
        LEFT JOIN 
            app_dat_estado_operacion e ON e.id_operacion = o.id AND e.id = (
                SELECT MAX(id) FROM app_dat_estado_operacion er WHERE er.id_operacion = o.id
            )
        WHERE
            -- Filtros básicos
            (id_tienda_param IS NULL OR o.id_tienda = id_tienda_param)
            AND (id_tpv_param IS NULL OR EXISTS (
                SELECT 1 FROM app_dat_operacion_venta ov 
                WHERE ov.id_operacion = o.id AND ov.id_tpv = id_tpv_param
            ))
            AND (v_uuid_usuario IS NULL OR o.uuid = v_uuid_usuario)
            AND (id_estado_param IS NULL OR e.estado = id_estado_param)
            -- Filtro de fechas basado en turno o parámetros
            AND (v_fecha_inicio IS NULL OR o.created_at >= v_fecha_inicio)
            AND (v_fecha_fin IS NULL OR o.created_at <= v_fecha_fin)
            AND (id_tipo_operacion_param IS NULL OR o.id_tipo_operacion = id_tipo_operacion_param)
            -- Filtro de permisos del usuario
            AND EXISTS (
                SELECT 1 FROM (
                    SELECT gr.id_tienda FROM app_dat_gerente gr WHERE gr.uuid = auth.uid()
                    UNION
                    SELECT sup.id_tienda FROM app_dat_supervisor sup WHERE sup.uuid = auth.uid()
                    UNION
                    SELECT a.id_tienda FROM app_dat_almacenero al
                    JOIN app_dat_almacen a ON al.id_almacen = a.id
                    WHERE al.uuid = auth.uid()
                    UNION
                    SELECT tpv.id_tienda FROM app_dat_vendedor v
                    JOIN app_dat_tpv tpv ON v.id_tpv = tpv.id
                    WHERE v.uuid = auth.uid()
                ) AS tiendas_usuario
                WHERE tiendas_usuario.id_tienda = o.id_tienda
            )
        ORDER BY 
            o.created_at DESC
        LIMIT 
            CASE WHEN limite_param = 0 THEN NULL ELSE limite_param END
        OFFSET 
            CASE WHEN limite_param = 0 THEN 0 ELSE (pagina_param - 1) * limite_param END
    )
    SELECT 
        of.id AS id_operacion,
        of.tipo_operacion_nombre AS tipo_operacion,
        of.id_tienda,
        of.tienda_nombre,
        (of.datos_especificos->>'id_tpv')::BIGINT AS id_tpv,
        (of.datos_especificos->>'tpv_nombre')::VARCHAR AS tpv_nombre,
        COALESCE(
            (SELECT nombres || ' ' || apellidos 
             FROM app_dat_trabajadores 
             WHERE uuid = of.uuid
             LIMIT 1),
            of.usuario_email
        ) AS usuario_nombre,
        of.estado,
        of.estado_nombre,
        of.created_at AS fecha_operacion,
        of.total_operacion,
        of.cantidad_items::INTEGER,
        of.observaciones::TEXT,
        jsonb_build_object(
            'productos', (
                SELECT COALESCE(jsonb_agg(
                    jsonb_build_object(
                        'id_producto', ep.id_producto,
                        'nombre_producto', p.denominacion,
                        'cantidad', ep.cantidad,
                        'precio_unitario', ep.precio_unitario,
                        'importe', ep.importe,
                        'descuento', ep.descuento,
                        'observaciones', ep.observaciones,
                        'es_elaborado', COALESCE(p.es_elaborado, false),
                        -- ✅ NUEVO: Agregar ingredientes para productos elaborados
                        'ingredientes', CASE 
                            WHEN COALESCE(p.es_elaborado, false) = true THEN (
                                SELECT COALESCE(jsonb_agg(
                                    jsonb_build_object(
                                        'id_producto', ing_prod.id,
                                        'denominacion', ing_prod.denominacion,
                                        'cantidad_inicial', inv.cantidad_inicial,
                                        'cantidad_final', inv.cantidad_final,
                                        'vendido', (inv.cantidad_inicial - inv.cantidad_final)
                                    )
                                ), '[]'::jsonb)
                                FROM app_dat_inventario_productos inv
                                JOIN app_dat_producto ing_prod ON inv.id_producto = ing_prod.id
                                WHERE inv.id_extraccion = ep.id
                            )
                            ELSE '[]'::jsonb
                        END
                    )
                ), '[]'::jsonb)
                FROM app_dat_extraccion_productos ep
                JOIN app_dat_producto p ON ep.id_producto = p.id
                WHERE ep.id_operacion = of.id
            ),
            'pagos', (
                SELECT COALESCE(jsonb_agg(
                    jsonb_build_object(
                        'id_medio_pago', pv.id_medio_pago,
                        'medio_pago', mp.denominacion,
                        'monto', pv.monto,
                        'referencia', pv.referencia,
                        'observaciones', pv.observaciones
                    )
                ), '[]'::jsonb)
                FROM app_dat_pago_venta pv
                JOIN app_nom_medio_pago mp ON pv.id_medio_pago = mp.id
                WHERE pv.id_operacion = of.id
            ),
            'datos_especificos', of.datos_especificos
        ) AS detalles
    FROM operaciones_filtradas of;
END;
$$;
