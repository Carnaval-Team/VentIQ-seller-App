-- Consulta SELECT equivalente a la función listar_ordenes con parámetros hardcodeados
-- Parámetros aplicados:
-- p_id_tpv = 18
-- p_uuid_vendedor = '0a6886f2-ac36-416a-bfba-bd08d0671568'
-- p_estado_operacion = NULL
-- p_id_tienda = 11
-- p_fecha_desde = '2025-08-29'
-- p_fecha_hasta = '2025-08-29'
-- p_limite = 10
-- p_pagina = 1

WITH ventas_filtradas AS (
    SELECT 
        o.id,
        o.created_at,
        ov.id_tpv,
        tp.denominacion AS tpv_nombre,
        o.uuid AS uuid_vendedor,
        COALESCE(tr.nombres || ' ' || tr.apellidos, u.email) AS vendedor_nombre,
        ov.codigo_promocion,
        ov.id_cliente,
        c.nombre_completo AS cliente_nombre,
        (SELECT SUM(ep.importe) 
         FROM app_dat_extraccion_productos ep 
         WHERE ep.id_operacion = o.id) AS total_venta,
        (SELECT COUNT(*) 
         FROM app_dat_extraccion_productos ep 
         WHERE ep.id_operacion = o.id) AS cantidad_items
    FROM 
        app_dat_operaciones o
    INNER JOIN 
        app_dat_operacion_venta ov ON o.id = ov.id_operacion
    INNER JOIN 
        app_dat_tpv tp ON ov.id_tpv = tp.id
    LEFT JOIN 
        auth.users u ON o.uuid = u.id
    LEFT JOIN 
        app_dat_vendedor ven ON ven.uuid = u.id
    LEFT JOIN 
        app_dat_trabajadores tr ON ven.id_trabajador = tr.id
    LEFT JOIN 
        app_dat_clientes c ON ov.id_cliente = c.id
    WHERE 
        o.id_tipo_operacion = (SELECT id FROM app_nom_tipo_operacion WHERE denominacion = 'Venta')
        AND ov.id_tpv = 18  -- p_id_tpv
        AND o.uuid = '0a6886f2-ac36-416a-bfba-bd08d0671568'  -- p_uuid_vendedor
        AND o.id_tienda = 11  -- p_id_tienda
        AND o.created_at >= '2025-08-29'::date  -- p_fecha_desde
        AND o.created_at <= '2025-08-29'::date  -- p_fecha_hasta
        -- Validar permisos por tienda (usando auth.uid() actual)
        AND EXISTS (
            SELECT 1 FROM (
                SELECT id_tienda FROM app_dat_gerente WHERE uuid = auth.uid() AND id_tienda = o.id_tienda
                UNION
                SELECT id_tienda FROM app_dat_supervisor WHERE uuid = auth.uid() AND id_tienda = o.id_tienda
                UNION
                SELECT a.id_tienda FROM app_dat_almacenero al
                JOIN app_dat_almacen a ON al.id_almacen = a.id
                WHERE al.uuid = auth.uid() AND a.id_tienda = o.id_tienda
                UNION
                SELECT tpv.id_tienda FROM app_dat_vendedor v
                JOIN app_dat_tpv tpv ON v.id_tpv = tpv.id
                WHERE v.uuid = auth.uid() AND tpv.id_tienda = o.id_tienda
            ) AS usuarios_tienda
        )
    ORDER BY 
        o.created_at DESC
    LIMIT 
        10  -- p_limite
    OFFSET 
        (1 - 1) * 10  -- (p_pagina - 1) * p_limite = 0
)
SELECT 
    vf.id,
    vf.id_tpv,
    vf.tpv_nombre,
    vf.uuid_vendedor,
    vf.vendedor_nombre,
    vf.created_at,
    vf.total_venta,
    vf.cantidad_items,
    vf.codigo_promocion,
    vf.id_cliente,
    vf.cliente_nombre,
    jsonb_build_object(
        'items', (
            SELECT jsonb_agg(jsonb_build_object(
                'id_producto', ep.id_producto,
                'producto', p.denominacion,
                'sku', p.sku,
                'cantidad', ep.cantidad,
                'precio_unitario', ep.precio_unitario,
                'importe', ep.importe,
                'variante', CASE 
                    WHEN ep.id_variante IS NOT NULL THEN jsonb_build_object(
                        'id', ep.id_variante,
                        'atributo', a.denominacion,
                        'opcion', ao.valor
                    )
                    ELSE NULL
                END,
                'presentacion', CASE 
                    WHEN ep.id_presentacion IS NOT NULL THEN jsonb_build_object(
                        'id', pp.id,
                        'nombre', np.denominacion,
                        'cantidad', pp.cantidad
                    )
                    ELSE NULL
                END
            ))
            FROM app_dat_extraccion_productos ep
            JOIN app_dat_producto p ON ep.id_producto = p.id
            LEFT JOIN app_dat_variantes var ON ep.id_variante = var.id
            LEFT JOIN app_dat_atributos a ON var.id_atributo = a.id
            LEFT JOIN app_dat_atributo_opcion ao ON ep.id_opcion_variante = ao.id
            LEFT JOIN app_dat_producto_presentacion pp ON ep.id_presentacion = pp.id
            LEFT JOIN app_nom_presentacion np ON pp.id_presentacion = np.id
            WHERE ep.id_operacion = vf.id
        ),
        'pagos', (
            SELECT jsonb_agg(jsonb_build_object(
                'tipo_pago', pp.tipo_pago,
                'monto', pp.monto,
                'referencia', pp.referencia,
                'fecha', pp.created_at
            ))
            FROM app_dat_pagos_operacion pp
            WHERE pp.id_operacion = vf.id
        ),
        'promocion_aplicada', (
            SELECT jsonb_build_object(
                'id', prom.id,
                'nombre', prom.nombre,
                'descuento_aplicado', cp.descuento_aplicado
            )
            FROM app_mkt_cliente_promociones cp
            JOIN app_mkt_promociones prom ON cp.id_promocion = prom.id
            WHERE cp.id_operacion = vf.id
            LIMIT 1
        ),
        'detalle_venta', (
            SELECT jsonb_build_object(
                'id', o.id,
                'created_at', o.created_at,
                'observaciones', o.observaciones,
                'denominacion', ov.denominacion,
                'codigo_promocion', ov.codigo_promocion,
                'importe_total', ov.importe_total,
                'tpv_denominacion', tp.denominacion,
                'vendedor_nombre', COALESCE(tr.nombres || ' ' || tr.apellidos, 'Sin asignar'),
                'cliente', CASE 
                    WHEN c.id IS NOT NULL THEN 
                        json_build_object(
                            'id', c.id,
                            'codigo_cliente', c.codigo_cliente,
                            'nombre_completo', c.nombre_completo,
                            'telefono', c.telefono,
                            'email', c.email
                        )
                    ELSE NULL
                END,
                'productos', (
                    SELECT json_agg(
                        json_build_object(
                            'id_producto', ep.id_producto,
                            'cantidad', ep.cantidad,
                            'precio_unitario', ep.precio_unitario,
                            'importe', ep.importe,
                            'sku_producto', ep.sku_producto
                        )
                    )
                    FROM app_dat_extraccion_productos ep
                    WHERE ep.id_operacion = o.id
                ),
                'estado_actual', (
                    SELECT eo.estado
                    FROM app_dat_estado_operacion eo
                    WHERE eo.id_operacion = o.id
                    ORDER BY eo.created_at DESC
                    LIMIT 1
                )
            )
            FROM app_dat_operaciones o
            INNER JOIN app_dat_operacion_venta ov ON o.id = ov.id_operacion
            INNER JOIN app_dat_tpv tp ON ov.id_tpv = tp.id
            LEFT JOIN app_dat_vendedor ven ON o.uuid = ven.uuid
            LEFT JOIN app_dat_trabajadores tr ON ven.id_trabajador = tr.id
            LEFT JOIN app_dat_clientes c ON ov.id_cliente = c.id
            WHERE o.id = vf.id
        )
    ) AS detalles_venta
FROM 
    ventas_filtradas vf;

-- CONSULTA SIMPLIFICADA PARA DEBUG (sin permisos ni JSONB)
-- Ejecutar esta primero para ver si hay datos básicos

SELECT 
    o.id,
    o.created_at,
    ov.id_tpv,
    tp.denominacion AS tpv_nombre,
    o.uuid AS uuid_vendedor,
    COALESCE(tr.nombres || ' ' || tr.apellidos, u.email) AS vendedor_nombre,
    ov.codigo_promocion,
    ov.id_cliente,
    c.nombre_completo AS cliente_nombre,
    o.id_tienda,
    (SELECT denominacion FROM app_nom_tipo_operacion WHERE id = o.id_tipo_operacion) as tipo_operacion
FROM 
    app_dat_operaciones o
INNER JOIN 
    app_dat_operacion_venta ov ON o.id = ov.id_operacion
INNER JOIN 
    app_dat_tpv tp ON ov.id_tpv = tp.id
LEFT JOIN 
    auth.users u ON o.uuid = u.id
LEFT JOIN 
    app_dat_vendedor ven ON ven.uuid = u.id
LEFT JOIN 
    app_dat_trabajadores tr ON ven.id_trabajador = tr.id
LEFT JOIN 
    app_dat_clientes c ON ov.id_cliente = c.id
WHERE 
    o.id_tipo_operacion = (SELECT id FROM app_nom_tipo_operacion WHERE denominacion = 'Venta')
    AND ov.id_tpv = 18
    AND o.uuid = '0a6886f2-ac36-416a-bfba-bd08d0671568'
    AND o.id_tienda = 11
    AND o.created_at >= '2025-08-29'::date
    AND o.created_at <= '2025-08-29'::date + interval '1 day'
ORDER BY 
    o.created_at DESC;
