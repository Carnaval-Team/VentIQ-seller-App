-- Función optimizada con filtro p_id_producto
CREATE OR REPLACE FUNCTION fn_inventario_detallado_optimizado(
    p_id_tienda BIGINT,
    p_fecha_desde DATE DEFAULT NULL,
    p_fecha_hasta DATE DEFAULT NULL,
    p_id_almacen BIGINT DEFAULT NULL,
    p_id_producto BIGINT DEFAULT NULL  -- NUEVO PARÁMETRO
)
RETURNS TABLE(
    id_almacen bigint, 
    almacen text, 
    id_ubicacion bigint, 
    ubicacion text, 
    id_producto bigint, 
    nombre_producto text, 
    codigo_producto text, 
    categoria_producto text, 
    stock_disponible numeric, 
    stock_reservado numeric, 
    cantidad_inicial numeric, 
    cantidad_final numeric, 
    entradas_periodo numeric, 
    extracciones_periodo numeric, 
    ventas_periodo numeric, 
    ventas_cup numeric, 
    precio_venta_cup numeric, 
    costo_promedio_usd numeric, 
    costo_promedio_cup numeric, 
    valor_inventario_usd numeric, 
    valor_inventario_cup numeric, 
    valor_venta_estimado_cup numeric, 
    dias_inventario numeric, 
    rotacion_anual numeric, 
    margen_bruto_porcentaje numeric, 
    tasa_cambio numeric, 
    ultima_actualizacion timestamp without time zone, 
    tiene_inventario boolean
) 
LANGUAGE plpgsql
AS $$

BEGIN
    -- Validar que el id_tienda sea obligatorio
    IF p_id_tienda IS NULL THEN
        RAISE EXCEPTION 'El id_tienda es obligatorio';
    END IF;

    -- Validar que la tienda exista
    IF NOT EXISTS (SELECT 1 FROM app_dat_tienda t WHERE t.id = p_id_tienda) THEN
        RAISE EXCEPTION 'La tienda con ID % no existe', p_id_tienda;
    END IF;

    -- Validar que el almacén exista si se especifica
    IF p_id_almacen IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM app_dat_almacen a WHERE a.id = p_id_almacen) THEN
            RAISE EXCEPTION 'El almacén con ID % no existe', p_id_almacen;
        END IF;
    END IF;

    -- Validar que el producto exista si se especifica
    IF p_id_producto IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM app_dat_producto p WHERE p.id = p_id_producto AND p.id_tienda = p_id_tienda) THEN
            RAISE EXCEPTION 'El producto con ID % no existe en la tienda %', p_id_producto, p_id_tienda;
        END IF;
    END IF;

    -- Validar fechas
    IF p_fecha_desde IS NOT NULL AND p_fecha_hasta IS NOT NULL AND p_fecha_desde > p_fecha_hasta THEN
        RAISE EXCEPTION 'La fecha desde no puede ser mayor que la fecha hasta';
    END IF;

    RETURN QUERY
    WITH productos_base AS (
        -- Todos los productos inventariables de la tienda/almacén
        SELECT DISTINCT
            p.id,
            p.denominacion AS nombre_producto_base,
            p.codigo_barras as codigo,
            c.denominacion as categoria,
            COALESCE(pv.precio_venta_cup, 0) as precio_venta,
            t.id as id_tienda_filtro
        FROM app_dat_producto p
        INNER JOIN app_dat_tienda t ON p.id_tienda = t.id
        LEFT JOIN app_dat_precio_venta pv ON p.id = pv.id_producto 
            AND (pv.id_variante IS NULL OR pv.id_variante = 0)
            AND (pv.fecha_hasta IS NULL OR pv.fecha_hasta >= CURRENT_DATE)
        LEFT JOIN app_dat_categoria c ON p.id_categoria = c.id
        WHERE p.es_inventariable = true
          AND t.id = p_id_tienda
          -- FILTRO OPTIMIZADO: Solo el producto solicitado si se especifica
          AND (p_id_producto IS NULL OR p.id = p_id_producto)
          -- EXCLUIR productos elaborados y servicios - CORREGIDO
          AND (p.es_elaborado IS NULL OR p.es_elaborado = false)
          AND (p.es_servicio IS NULL OR p.es_servicio = false)
    ),
    inventario_detalle AS (
        -- CANTIDAD INICIAL: Primera operación en el periodo (como la primera función)
        -- CANTIDAD FINAL: Última operación en el periodo
        SELECT 
            COALESCE(inv_inicial.id_producto, inv_final.id_producto) as id_producto,
            COALESCE(inv_inicial.id_variante, inv_final.id_variante) as id_variante,
            COALESCE(inv_inicial.id_opcion_variante, inv_final.id_opcion_variante) as id_opcion_variante,
            COALESCE(inv_inicial.id_ubicacion, inv_final.id_ubicacion) as id_ubicacion,
            COALESCE(inv_inicial.id_presentacion, inv_final.id_presentacion) as id_presentacion,
            -- Cantidad inicial: Primera operación DEL periodo (no antes)
            COALESCE(inv_inicial.cantidad_inicial, 0) as cantidad_inicial,
            -- Cantidad final: Última operación del periodo
            COALESCE(inv_final.cantidad_final, inv_inicial.cantidad_final, 0) as cantidad_final,
            COALESCE(inv_final.created_at, inv_inicial.created_at) as created_at
        FROM (
            -- Primera operación EN el periodo para cantidad inicial
            SELECT DISTINCT ON (i.id_producto, COALESCE(i.id_variante, 0), COALESCE(i.id_opcion_variante, 0), 
                               COALESCE(i.id_presentacion, 0), COALESCE(i.id_ubicacion, 0))
                i.id_producto,
                i.id_variante,
                i.id_opcion_variante,
                i.id_ubicacion,
                i.id_presentacion,
                i.cantidad_inicial,  -- Tomar cantidad_inicial de la primera operación
                i.cantidad_final,
                i.created_at
            FROM app_dat_inventario_productos i
            INNER JOIN app_dat_layout_almacen l ON i.id_ubicacion = l.id
            INNER JOIN app_dat_almacen a ON l.id_almacen = a.id
            INNER JOIN app_dat_tienda t ON a.id_tienda = t.id
            WHERE t.id = p_id_tienda
              AND (p_id_almacen IS NULL OR a.id = p_id_almacen)
              AND (p_id_producto IS NULL OR i.id_producto = p_id_producto)
              AND (p_fecha_hasta IS NULL OR i.created_at <= p_fecha_hasta)
              AND (p_fecha_desde IS NULL OR i.created_at >= p_fecha_desde)  -- DENTRO del periodo
            ORDER BY i.id_producto, COALESCE(i.id_variante, 0), COALESCE(i.id_opcion_variante, 0), 
                     COALESCE(i.id_presentacion, 0), COALESCE(i.id_ubicacion, 0), 
                     i.created_at ASC, i.id ASC  -- ASC para tomar la PRIMERA
        ) inv_inicial
        FULL OUTER JOIN (
            -- Última operación DENTRO del periodo para cantidad final
            SELECT DISTINCT ON (i.id_producto, COALESCE(i.id_variante, 0), COALESCE(i.id_opcion_variante, 0), 
                               COALESCE(i.id_presentacion, 0), COALESCE(i.id_ubicacion, 0))
                i.id_producto,
                i.id_variante,
                i.id_opcion_variante,
                i.id_ubicacion,
                i.id_presentacion,
                i.cantidad_final,
                i.created_at
            FROM app_dat_inventario_productos i
            INNER JOIN app_dat_layout_almacen l ON i.id_ubicacion = l.id
            INNER JOIN app_dat_almacen a ON l.id_almacen = a.id
            INNER JOIN app_dat_tienda t ON a.id_tienda = t.id
            WHERE t.id = p_id_tienda
              AND (p_id_almacen IS NULL OR a.id = p_id_almacen)
              AND (p_id_producto IS NULL OR i.id_producto = p_id_producto)
              AND (p_fecha_hasta IS NULL OR i.created_at <= p_fecha_hasta)
              AND (p_fecha_desde IS NULL OR i.created_at >= p_fecha_desde)  -- DENTRO del periodo
            ORDER BY i.id_producto, COALESCE(i.id_variante, 0), COALESCE(i.id_opcion_variante, 0), 
                     COALESCE(i.id_presentacion, 0), COALESCE(i.id_ubicacion, 0), 
                     i.created_at DESC, i.id DESC  -- DESC para tomar la ÚLTIMA
        ) inv_final ON (
            inv_inicial.id_producto = inv_final.id_producto
            AND COALESCE(inv_inicial.id_variante, 0) = COALESCE(inv_final.id_variante, 0)
            AND COALESCE(inv_inicial.id_opcion_variante, 0) = COALESCE(inv_final.id_opcion_variante, 0)
            AND COALESCE(inv_inicial.id_presentacion, 0) = COALESCE(inv_final.id_presentacion, 0)
            AND COALESCE(inv_inicial.id_ubicacion, 0) = COALESCE(inv_final.id_ubicacion, 0)
        )
        WHERE COALESCE(inv_inicial.cantidad_inicial, 0) != 0 
           OR COALESCE(inv_final.cantidad_final, 0) != 0  -- Solo incluir registros con inventario
    ),
    ubicacion_info AS (
        SELECT
            l.id AS id_ubicacion,
            l.denominacion AS ubicacion,
            a.id AS id_almacen,
            a.denominacion AS almacen,
            t.id AS id_tienda
        FROM app_dat_layout_almacen l
        INNER JOIN app_dat_almacen a ON l.id_almacen = a.id
        INNER JOIN app_dat_tienda t ON a.id_tienda = t.id
        WHERE t.id = p_id_tienda
          AND (p_id_almacen IS NULL OR a.id = p_id_almacen)
    ),
    stock_reservado AS (
        SELECT
            ep.id_producto,
            COALESCE(ep.id_variante, 0) as id_variante,
            COALESCE(ep.id_opcion_variante, 0) as id_opcion_variante,
            ep.id_ubicacion,
            SUM(ep.cantidad) AS reservado
        FROM app_dat_extraccion_productos ep
        INNER JOIN app_dat_operaciones o ON ep.id_operacion = o.id
        INNER JOIN app_dat_estado_operacion eo ON o.id = eo.id_operacion
        WHERE eo.estado = 1 -- Pendiente
          AND (p_id_producto IS NULL OR ep.id_producto = p_id_producto)
        GROUP BY ep.id_producto, COALESCE(ep.id_variante, 0), COALESCE(ep.id_opcion_variante, 0), ep.id_ubicacion
    ),
    -- ENTRADAS EN EL PERIODO (RECEPCIONES)
    entradas_periodo AS (
        SELECT
            rp.id_producto,
            COALESCE(rp.id_variante, 0) as id_variante,
            COALESCE(rp.id_opcion_variante, 0) as id_opcion_variante,
            COALESCE(rp.id_presentacion, 0) as id_presentacion,
            rp.id_ubicacion,
            SUM(rp.cantidad) as cantidad_entradas
        FROM app_dat_recepcion_productos rp
        INNER JOIN app_dat_operaciones o ON rp.id_operacion = o.id
        INNER JOIN app_dat_operacion_recepcion orp ON o.id = orp.id_operacion
        WHERE (p_fecha_hasta IS NULL OR rp.created_at <= p_fecha_hasta)
          AND (p_fecha_desde IS NULL OR rp.created_at >= p_fecha_desde)
          AND (p_id_producto IS NULL OR rp.id_producto = p_id_producto)
        GROUP BY rp.id_producto, COALESCE(rp.id_variante, 0), COALESCE(rp.id_opcion_variante, 0), 
                 COALESCE(rp.id_presentacion, 0), rp.id_ubicacion
    ),
    -- EXTRACCIONES EN EL PERIODO (TODAS LAS SALIDAS)
    extracciones_periodo AS (
        SELECT
            ep.id_producto,
            COALESCE(ep.id_variante, 0) as id_variante,
            COALESCE(ep.id_opcion_variante, 0) as id_opcion_variante,
            COALESCE(ep.id_presentacion, 0) as id_presentacion,
            ep.id_ubicacion,
            SUM(ep.cantidad) as cantidad_extracciones
        FROM app_dat_extraccion_productos ep
        INNER JOIN app_dat_operaciones o ON ep.id_operacion = o.id
        INNER JOIN app_dat_operacion_extraccion oe ON o.id = oe.id_operacion
        WHERE (p_fecha_hasta IS NULL OR ep.created_at <= p_fecha_hasta)
          AND (p_fecha_desde IS NULL OR ep.created_at >= p_fecha_desde)
          AND (p_id_producto IS NULL OR ep.id_producto = p_id_producto)
          -- EXCLUIR OPERACIONES DE VENTA (id_motivo_operacion > 10)
          AND oe.id_motivo_operacion <= 10
        GROUP BY ep.id_producto, COALESCE(ep.id_variante, 0), COALESCE(ep.id_opcion_variante, 0), 
                 COALESCE(ep.id_presentacion, 0), ep.id_ubicacion
    ),
    -- VENTAS EN EL PERIODO (SOLO EXTRACCIONES DE VENTAS)
    ventas_periodo AS (
        SELECT
            ep.id_producto,
            COALESCE(ep.id_variante, 0) as id_variante,
            COALESCE(ep.id_opcion_variante, 0) as id_opcion_variante,
            COALESCE(ep.id_presentacion, 0) as id_presentacion,
            ep.id_ubicacion,
            SUM(ep.cantidad) as cantidad_ventas
        FROM app_dat_extraccion_productos ep
        INNER JOIN app_dat_operaciones o ON ep.id_operacion = o.id
        INNER JOIN app_dat_operacion_venta ov ON o.id = ov.id_operacion
        INNER JOIN app_dat_estado_operacion eo ON o.id = eo.id_operacion
        INNER JOIN app_nom_estado_operacion neo ON eo.estado = neo.id
        WHERE neo.denominacion = 'Completada' -- Solo ventas completadas
          AND (p_fecha_hasta IS NULL OR ep.created_at <= p_fecha_hasta)
          AND (p_fecha_desde IS NULL OR ep.created_at >= p_fecha_desde)
          AND (p_id_producto IS NULL OR ep.id_producto = p_id_producto)
        GROUP BY ep.id_producto, COALESCE(ep.id_variante, 0), COALESCE(ep.id_opcion_variante, 0), 
                 COALESCE(ep.id_presentacion, 0), ep.id_ubicacion
    ),
    -- CÁLCULO MEJORADO DE COSTO PROMEDIO PONDERADO
    costo_promedio_productos AS (
        SELECT
            rp.id_producto,
            COALESCE(rp.id_variante, 0) as id_variante,
            COALESCE(rp.id_opcion_variante, 0) as id_opcion_variante,
            COALESCE(rp.id_presentacion, 0) as id_presentacion,
            -- Costo promedio ponderado por cantidad
            CASE 
                WHEN SUM(rp.cantidad) > 0 THEN
                    SUM(
                        CASE 
                            WHEN rp.costo_real IS NOT NULL AND rp.costo_real > 0 THEN rp.costo_real * rp.cantidad
                            WHEN rp.precio_unitario IS NOT NULL AND rp.precio_unitario > 0 THEN rp.precio_unitario * rp.cantidad
                            ELSE 0
                        END
                    ) / SUM(rp.cantidad)
                ELSE 0
            END AS costo_promedio_usd,
            -- Cantidad total recibida para validación
            SUM(rp.cantidad) as cantidad_total_recibida
        FROM app_dat_recepcion_productos rp
        INNER JOIN app_dat_operaciones o ON rp.id_operacion = o.id
        INNER JOIN app_dat_operacion_recepcion orp ON o.id = orp.id_operacion
        WHERE (
            (rp.precio_unitario IS NOT NULL AND rp.precio_unitario > 0) OR
            (rp.costo_real IS NOT NULL AND rp.costo_real > 0)
        )
          AND (p_fecha_hasta IS NULL OR rp.created_at <= p_fecha_hasta)
          AND (p_id_producto IS NULL OR rp.id_producto = p_id_producto)
        GROUP BY rp.id_producto, COALESCE(rp.id_variante, 0), COALESCE(rp.id_opcion_variante, 0), COALESCE(rp.id_presentacion, 0)
    ),
    tasa_conversion AS (
        SELECT 
            tasa,
            fecha_actualizacion
        FROM tasas_conversion 
        WHERE moneda_origen = 'USD' AND moneda_destino = 'CUP'
        ORDER BY fecha_actualizacion DESC
        LIMIT 1
    ),
    presentacion_info AS (
        SELECT
            pp.id,
            np.denominacion AS presentacion_nombre
        FROM app_dat_producto_presentacion pp
        LEFT JOIN app_nom_presentacion np ON pp.id_presentacion = np.id
    ),
    variante_info AS (
        SELECT
            v.id as id_variante,
            a.denominacion as nombre_atributo,
            ao.valor as valor_opcion
        FROM app_dat_variantes v
        LEFT JOIN app_dat_atributos a ON v.id_atributo = a.id
        LEFT JOIN app_dat_atributo_opcion ao ON v.id = ao.id_atributo
    ),
    -- PRODUCTOS CON Y SIN INVENTARIO
    productos_con_inventario AS (
        SELECT
            pb.id as id_producto,
            pb.nombre_producto_base,
            pb.codigo,
            pb.categoria,
            pb.precio_venta,
            pb.id_tienda_filtro,
            inv_det.id_variante,
            inv_det.id_opcion_variante,
            inv_det.id_ubicacion,
            inv_det.id_presentacion,
            inv_det.cantidad_inicial,
            inv_det.cantidad_final,
            inv_det.created_at,
            TRUE as tiene_inventario
        FROM productos_base pb
        INNER JOIN inventario_detalle inv_det ON pb.id = inv_det.id_producto
    ),
    productos_sin_inventario AS (
        SELECT
            pb.id as id_producto,
            pb.nombre_producto_base,
            pb.codigo,
            pb.categoria,
            pb.precio_venta,
            pb.id_tienda_filtro,
            NULL::bigint as id_variante,
            NULL::bigint as id_opcion_variante,
            NULL::bigint as id_ubicacion,
            NULL::bigint as id_presentacion,
            0 as cantidad_inicial,
            0 as cantidad_final,
            NULL::timestamp as created_at,
            FALSE as tiene_inventario
        FROM productos_base pb
        WHERE NOT EXISTS (
            SELECT 1 FROM inventario_detalle inv_det 
            WHERE inv_det.id_producto = pb.id
        )
    ),
    todos_los_productos AS (
        SELECT * FROM productos_con_inventario
        UNION ALL
        SELECT * FROM productos_sin_inventario
    )
    SELECT
        COALESCE(u.id_almacen, 0)::BIGINT,
        COALESCE(u.almacen, 'SIN UBICACIÓN')::TEXT,
        COALESCE(u.id_ubicacion, 0)::BIGINT,
        COALESCE(u.ubicacion, 'SIN UBICACIÓN')::TEXT,
        tp.id_producto::BIGINT,
        -- Nombre del producto con variante y presentación si aplica
        CASE 
            WHEN tp.id_presentacion IS NOT NULL AND pres.presentacion_nombre IS NOT NULL 
                 AND tp.id_variante IS NOT NULL AND vi.nombre_atributo IS NOT NULL
            THEN CONCAT(tp.nombre_producto_base, ' ', vi.nombre_atributo, ': ', vi.valor_opcion, ' (', pres.presentacion_nombre, ')')
            WHEN tp.id_presentacion IS NOT NULL AND pres.presentacion_nombre IS NOT NULL
            THEN CONCAT(tp.nombre_producto_base, ' (', pres.presentacion_nombre, ')')
            WHEN tp.id_variante IS NOT NULL AND vi.nombre_atributo IS NOT NULL
            THEN CONCAT(tp.nombre_producto_base, ' ', vi.nombre_atributo, ': ', vi.valor_opcion)
            ELSE tp.nombre_producto_base
        END::TEXT AS nombre_producto,
        tp.codigo::TEXT as codigo_producto,
        tp.categoria::TEXT as categoria_producto,
        -- Stock y cantidades
        GREATEST(COALESCE(tp.cantidad_final, 0) - COALESCE(sr.reservado, 0), 0)::NUMERIC AS stock_disponible,
        COALESCE(sr.reservado, 0)::NUMERIC AS stock_reservado,
        COALESCE(tp.cantidad_inicial, 0)::NUMERIC,
        COALESCE(tp.cantidad_final, 0)::NUMERIC,
        -- Entradas y extracciones del periodo
        COALESCE(ent.cantidad_entradas, 0)::NUMERIC as entradas_periodo,
        COALESCE(ext.cantidad_extracciones, 0)::NUMERIC as extracciones_periodo,
        COALESCE(vent.cantidad_ventas, 0)::NUMERIC as ventas_periodo,
        -- NUEVO CAMPO: Ventas en CUP (ventas * precio_venta)
        ROUND(COALESCE(vent.cantidad_ventas, 0) * tp.precio_venta, 2)::NUMERIC as ventas_cup,
        -- Precios y costos
        tp.precio_venta::NUMERIC as precio_venta_cup,
        COALESCE(cp.costo_promedio_usd, 0)::NUMERIC AS costo_promedio_usd,
        ROUND(COALESCE(cp.costo_promedio_usd, 0) * COALESCE(tc.tasa, 1), 2)::NUMERIC AS costo_promedio_cup,
        -- Valorización
        ROUND(GREATEST(COALESCE(tp.cantidad_final, 0) - COALESCE(sr.reservado, 0), 0) * COALESCE(cp.costo_promedio_usd, 0), 2)::NUMERIC AS valor_inventario_usd,
        ROUND(GREATEST(COALESCE(tp.cantidad_final, 0) - COALESCE(sr.reservado, 0), 0) * ROUND(COALESCE(cp.costo_promedio_usd, 0) * COALESCE(tc.tasa, 1), 2), 2)::NUMERIC AS valor_inventario_cup,
        ROUND(GREATEST(COALESCE(tp.cantidad_final, 0) - COALESCE(sr.reservado, 0), 0) * tp.precio_venta, 2)::NUMERIC AS valor_venta_estimado_cup,
        -- Indicadores de gestión (usando ventas del periodo)
        -- Días de inventario
        CASE 
            WHEN COALESCE(vent.cantidad_ventas, 0) > 0 AND GREATEST(COALESCE(tp.cantidad_final, 0) - COALESCE(sr.reservado, 0), 0) > 0 THEN
                ROUND((GREATEST(COALESCE(tp.cantidad_final, 0) - COALESCE(sr.reservado, 0), 0) / COALESCE(vent.cantidad_ventas, 0)) * 30, 1)
            ELSE NULL
        END::NUMERIC as dias_inventario,
        -- Rotación anual
        CASE 
            WHEN COALESCE(vent.cantidad_ventas, 0) > 0 AND GREATEST(COALESCE(tp.cantidad_final, 0) - COALESCE(sr.reservado, 0), 0) > 0 THEN
                ROUND((COALESCE(vent.cantidad_ventas, 0) / GREATEST(COALESCE(tp.cantidad_final, 0) - COALESCE(sr.reservado, 0), 0)) * 12, 2)
            ELSE 0
        END::NUMERIC as rotacion_anual,
        -- Margen bruto porcentaje
        CASE 
            WHEN ROUND(COALESCE(cp.costo_promedio_usd, 0) * COALESCE(tc.tasa, 1), 2) > 0 AND tp.precio_venta > 0 THEN
                ROUND(((tp.precio_venta / ROUND(COALESCE(cp.costo_promedio_usd, 0) * COALESCE(tc.tasa, 1), 2)) - 1) * 100, 2)
            ELSE 0
        END::NUMERIC as margen_bruto_porcentaje,
        -- Tasa de cambio
        COALESCE(tc.tasa, 1)::NUMERIC AS tasa_cambio,
        COALESCE(tp.created_at, NOW())::TIMESTAMP as ultima_actualizacion,
        tp.tiene_inventario::BOOLEAN
    FROM todos_los_productos tp
    LEFT JOIN ubicacion_info u ON tp.id_ubicacion = u.id_ubicacion
    LEFT JOIN stock_reservado sr ON (
        tp.id_producto = sr.id_producto
        AND COALESCE(tp.id_variante, 0) = sr.id_variante
        AND COALESCE(tp.id_opcion_variante, 0) = sr.id_opcion_variante
        AND COALESCE(tp.id_ubicacion, 0) = sr.id_ubicacion
    )
    LEFT JOIN entradas_periodo ent ON (
        tp.id_producto = ent.id_producto
        AND COALESCE(tp.id_variante, 0) = ent.id_variante
        AND COALESCE(tp.id_opcion_variante, 0) = ent.id_opcion_variante
        AND COALESCE(tp.id_presentacion, 0) = ent.id_presentacion
        AND COALESCE(tp.id_ubicacion, 0) = ent.id_ubicacion
    )
    LEFT JOIN extracciones_periodo ext ON (
        tp.id_producto = ext.id_producto
        AND COALESCE(tp.id_variante, 0) = ext.id_variante
        AND COALESCE(tp.id_opcion_variante, 0) = ext.id_opcion_variante
        AND COALESCE(tp.id_presentacion, 0) = ext.id_presentacion
        AND COALESCE(tp.id_ubicacion, 0) = ext.id_ubicacion
    )
    LEFT JOIN ventas_periodo vent ON (
        tp.id_producto = vent.id_producto
        AND COALESCE(tp.id_variante, 0) = vent.id_variante
        AND COALESCE(tp.id_opcion_variante, 0) = vent.id_opcion_variante
        AND COALESCE(tp.id_presentacion, 0) = vent.id_presentacion
        AND COALESCE(tp.id_ubicacion, 0) = vent.id_ubicacion
    )
    LEFT JOIN costo_promedio_productos cp ON (
        tp.id_producto = cp.id_producto
        AND COALESCE(tp.id_variante, 0) = cp.id_variante
        AND COALESCE(tp.id_opcion_variante, 0) = cp.id_opcion_variante
        AND COALESCE(tp.id_presentacion, 0) = cp.id_presentacion
    )
    LEFT JOIN presentacion_info pres ON tp.id_presentacion = pres.id
    LEFT JOIN variante_info vi ON tp.id_variante = vi.id_variante
    CROSS JOIN tasa_conversion tc
    ORDER BY 
        tp.tiene_inventario DESC,
        COALESCE(u.almacen, 'ZZZ'),
        COALESCE(u.ubicacion, 'ZZZ'),
        tp.nombre_producto_base;

END;
$$