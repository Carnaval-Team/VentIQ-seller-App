CREATE OR REPLACE FUNCTION obtener_ipv(
    p_id_tienda BIGINT,
    p_id_almacen BIGINT DEFAULT NULL,
    p_fecha_desde TEXT DEFAULT NULL,
    p_fecha_hasta TEXT DEFAULT NULL,
    p_include_zero BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    id_almacen BIGINT,
    almacen TEXT,
    id_ubicacion BIGINT,
    ubicacion TEXT,
    id_producto BIGINT,
    nombre_producto TEXT,
    codigo TEXT,
    categoria TEXT,
    cantidad_disponible NUMERIC,
    reservado NUMERIC,
    cantidad_inicial NUMERIC,
    cantidad_final NUMERIC,
    cantidad_entradas NUMERIC,
    cantidad_extracciones NUMERIC,
    cantidad_ventas NUMERIC,
    valor_total_ventas NUMERIC,
    precio_venta NUMERIC,
    costo_promedio_usd NUMERIC,
    costo_promedio_cup NUMERIC,
    costo_inventario_usd NUMERIC,
    costo_inventario_cup NUMERIC,
    valor_inventario_venta NUMERIC,
    dias_inventario NUMERIC,
    rotacion_anual NUMERIC,
    margen_porcentaje NUMERIC,
    tasa_conversion NUMERIC,
    fecha_consulta TIMESTAMP,
    tiene_inventario BOOLEAN,
    sku TEXT,
    id_categoria BIGINT,
    nombre_comercial TEXT,
    denominacion_corta TEXT,
    descripcion TEXT,
    descripcion_corta TEXT,
    um TEXT,
    es_refrigerado BOOLEAN,
    es_fragil BOOLEAN,
    es_peligroso BOOLEAN,
    es_vendible BOOLEAN,
    es_comprable BOOLEAN,
    es_inventariable BOOLEAN,
    es_por_lotes BOOLEAN,
    dias_alert_caducidad NUMERIC,
    producto_created_at TIMESTAMP,
    imagen TEXT,
    es_elaborado BOOLEAN,
    es_servicio BOOLEAN,
    deleted_at TIMESTAMP
) AS $$
DECLARE
    v_fecha_desde_ts TIMESTAMP;
    v_fecha_hasta_ts TIMESTAMP;
BEGIN
    -- Validaciones
    IF p_id_tienda IS NULL THEN
        RAISE EXCEPTION 'El id_tienda es obligatorio';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM app_dat_tienda t WHERE t.id = p_id_tienda) THEN
        RAISE EXCEPTION 'La tienda con ID % no existe', p_id_tienda;
    END IF;

    IF p_id_almacen IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM app_dat_almacen a WHERE a.id = p_id_almacen) THEN
            RAISE EXCEPTION 'El almacén con ID % no existe', p_id_almacen;
        END IF;
    END IF;

    IF p_fecha_desde IS NOT NULL AND p_fecha_hasta IS NOT NULL AND p_fecha_desde > p_fecha_hasta THEN
        RAISE EXCEPTION 'La fecha desde no puede ser mayor que la fecha hasta';
    END IF;

    -- CONVERSIÓN CORRECTA DE FECHAS A TIMESTAMP
    -- p_fecha_desde: inicio del día (00:00:00)
    -- p_fecha_hasta: fin del día (23:59:59)
    v_fecha_desde_ts := CASE WHEN p_fecha_desde IS NOT NULL THEN p_fecha_desde::TIMESTAMP ELSE NULL END;
    v_fecha_hasta_ts := CASE WHEN p_fecha_hasta IS NOT NULL THEN (p_fecha_hasta::DATE + INTERVAL '1 day' - INTERVAL '1 second')::TIMESTAMP ELSE NULL END;

    RAISE NOTICE 'DEBUG: v_fecha_desde_ts = %, v_fecha_hasta_ts = %', v_fecha_desde_ts, v_fecha_hasta_ts;

    RETURN QUERY
    WITH precio_venta_productos AS (
        SELECT DISTINCT ON (pv.id_producto)
            pv.id_producto, pv.precio_venta_cup
        FROM app_dat_precio_venta pv
        WHERE pv.id_variante IS NULL OR pv.id_variante = 0
        ORDER BY pv.id_producto, pv.created_at DESC
    ),
    productos_base AS (
        SELECT DISTINCT p.id, p.denominacion AS nombre_producto_base, p.codigo_barras as codigo,
            c.denominacion as categoria, COALESCE(pv.precio_venta_cup, 0) as precio_venta, t.id as id_tienda_filtro,
            p.sku, p.id_categoria, p.nombre_comercial, p.denominacion_corta, p.descripcion, p.descripcion_corta,
            p.um, p.es_refrigerado, p.es_fragil, p.es_peligroso, p.es_vendible, p.es_comprable,
            p.es_inventariable, p.es_por_lotes, p.dias_alert_caducidad, p.created_at AS producto_created_at,
            p.imagen, p.es_elaborado, p.es_servicio, p.deleted_at
        FROM app_dat_producto p
        INNER JOIN app_dat_tienda t ON p.id_tienda = t.id
        LEFT JOIN precio_venta_productos pv ON p.id = pv.id_producto
        LEFT JOIN app_dat_categoria c ON p.id_categoria = c.id
        WHERE p.es_inventariable = true AND t.id = p_id_tienda
          AND (p.es_elaborado IS NULL OR p.es_elaborado = false)
          AND (p.es_servicio IS NULL OR p.es_servicio = false)
    ),
    ubicaciones_filtro AS (
        SELECT l.id AS id_ubicacion, l.denominacion AS ubicacion, a.id AS id_almacen, a.denominacion AS almacen, t.id AS id_tienda
        FROM app_dat_layout_almacen l
        INNER JOIN app_dat_almacen a ON l.id_almacen = a.id
        INNER JOIN app_dat_tienda t ON a.id_tienda = t.id
        WHERE t.id = p_id_tienda AND (p_id_almacen IS NULL OR a.id = p_id_almacen)
    ),
    primer_registro_rango AS (
        SELECT DISTINCT ON (i.id_producto, COALESCE(i.id_presentacion, 0), COALESCE(i.id_ubicacion, 0))
            i.id_producto, i.id_ubicacion, i.id_presentacion,
            i.cantidad_inicial
        FROM app_dat_inventario_productos i
        INNER JOIN ubicaciones_filtro uf ON i.id_ubicacion = uf.id_ubicacion
        WHERE (v_fecha_desde_ts IS NULL OR i.created_at >= v_fecha_desde_ts)
          AND (v_fecha_hasta_ts IS NULL OR i.created_at <= v_fecha_hasta_ts)
        ORDER BY i.id_producto, COALESCE(i.id_presentacion, 0), COALESCE(i.id_ubicacion, 0), i.created_at ASC, i.id ASC
    ),
    ultimo_registro_antes AS (
        SELECT DISTINCT ON (i.id_producto, COALESCE(i.id_presentacion, 0), COALESCE(i.id_ubicacion, 0))
            i.id_producto, i.id_ubicacion, i.id_presentacion,
            i.cantidad_final
        FROM app_dat_inventario_productos i
        INNER JOIN ubicaciones_filtro uf ON i.id_ubicacion = uf.id_ubicacion
        WHERE v_fecha_desde_ts IS NOT NULL AND i.created_at < v_fecha_desde_ts
        ORDER BY i.id_producto, COALESCE(i.id_presentacion, 0), COALESCE(i.id_ubicacion, 0), i.created_at DESC, i.id DESC
    ),
    inventario_inicial AS (
        SELECT 
            COALESCE(prr.id_producto, ura.id_producto) as id_producto,
            COALESCE(prr.id_ubicacion, ura.id_ubicacion) as id_ubicacion,
            COALESCE(prr.id_presentacion, ura.id_presentacion) as id_presentacion,
            CASE 
                WHEN prr.id_producto IS NOT NULL THEN prr.cantidad_inicial
                WHEN ura.id_producto IS NOT NULL THEN ura.cantidad_final
                ELSE 0 
            END as cantidad_inicial
        FROM primer_registro_rango prr
        FULL OUTER JOIN ultimo_registro_antes ura ON (
            prr.id_producto = ura.id_producto 
            AND COALESCE(prr.id_presentacion, 0) = COALESCE(ura.id_presentacion, 0)
            AND prr.id_ubicacion = ura.id_ubicacion
        )
    ),
    inventario_final AS (
        SELECT DISTINCT ON (i.id_producto, COALESCE(i.id_presentacion, 0), COALESCE(i.id_ubicacion, 0))
            i.id_producto, i.id_ubicacion, i.id_presentacion,
            i.cantidad_final, i.created_at
        FROM app_dat_inventario_productos i
        INNER JOIN ubicaciones_filtro uf ON i.id_ubicacion = uf.id_ubicacion
        WHERE (v_fecha_hasta_ts IS NULL OR i.created_at <= v_fecha_hasta_ts)
        ORDER BY i.id_producto, COALESCE(i.id_presentacion, 0), COALESCE(i.id_ubicacion, 0), i.created_at DESC, i.id DESC
    ),
    inventario_completo AS (
        SELECT 
            COALESCE(ii.id_producto, ifin.id_producto) as id_producto,
            COALESCE(ii.id_ubicacion, ifin.id_ubicacion) as id_ubicacion,
            COALESCE(ii.id_presentacion, ifin.id_presentacion) as id_presentacion,
            COALESCE(ii.cantidad_inicial, 0) as cantidad_inicial,
            COALESCE(ifin.cantidad_final, 0) as cantidad_final
        FROM inventario_inicial ii
        FULL OUTER JOIN inventario_final ifin ON (
            ii.id_producto = ifin.id_producto
            AND COALESCE(ii.id_presentacion, 0) = COALESCE(ifin.id_presentacion, 0)
            AND COALESCE(ii.id_ubicacion, 0) = COALESCE(ifin.id_ubicacion, 0)
        )
    ),
    estados_actuales AS (
        -- Obtener el último estado de cada operación de forma segura
        SELECT DISTINCT ON (id_operacion) 
            id_operacion, 
            estado
        FROM app_dat_estado_operacion
        ORDER BY id_operacion, created_at DESC, id DESC
    ),
    stock_reservado AS (
        SELECT ep.id_producto, 
            COALESCE(ep.id_presentacion, 0) as id_presentacion,
            ep.id_ubicacion, SUM(ep.cantidad) AS reservado
        FROM app_dat_extraccion_productos ep
        INNER JOIN app_dat_operaciones o ON ep.id_operacion = o.id
        INNER JOIN estados_actuales ea ON o.id = ea.id_operacion
        WHERE ea.estado = 1 -- Solo si su estado ACTUAL es PENDIENTE
        GROUP BY ep.id_producto, COALESCE(ep.id_presentacion, 0), ep.id_ubicacion
    ),
    entradas_periodo AS (
        SELECT rp.id_producto, COALESCE(rp.id_presentacion, 0) as id_presentacion,
            rp.id_ubicacion, SUM(rp.cantidad) as cantidad_entradas
        FROM app_dat_operacion_recepcion orp
        INNER JOIN app_dat_operaciones o ON orp.id_operacion = o.id
        INNER JOIN app_dat_recepcion_productos rp ON o.id = rp.id_operacion
        INNER JOIN app_dat_inventario_productos i ON rp.id = i.id_recepcion
        INNER JOIN estados_actuales ea ON o.id = ea.id_operacion
        WHERE o.id_tienda = p_id_tienda
          AND ea.estado = 2 -- Solo si su estado ACTUAL es COMPLETADA
          AND (v_fecha_hasta_ts IS NULL OR i.created_at <= v_fecha_hasta_ts)
          AND (v_fecha_desde_ts IS NULL OR i.created_at >= v_fecha_desde_ts)
        GROUP BY rp.id_producto, COALESCE(rp.id_presentacion, 0), rp.id_ubicacion
    ),
    extracciones_periodo AS (
        SELECT ep.id_producto, COALESCE(ep.id_presentacion, 0) as id_presentacion,
            ep.id_ubicacion, SUM(ep.cantidad) as cantidad_extracciones
        FROM app_dat_operacion_extraccion oe
        INNER JOIN app_dat_operaciones o ON oe.id_operacion = o.id
        INNER JOIN app_dat_extraccion_productos ep ON o.id = ep.id_operacion
        INNER JOIN app_dat_inventario_productos i ON ep.id = i.id_extraccion
        INNER JOIN estados_actuales ea ON o.id = ea.id_operacion
        WHERE o.id_tienda = p_id_tienda
          AND ea.estado = 2 -- Solo si su estado ACTUAL es COMPLETADA
          AND (v_fecha_hasta_ts IS NULL OR i.created_at <= v_fecha_hasta_ts)
          AND (v_fecha_desde_ts IS NULL OR i.created_at >= v_fecha_desde_ts)
        GROUP BY ep.id_producto, COALESCE(ep.id_presentacion, 0), ep.id_ubicacion
    ),
    ventas_periodo AS (
        SELECT ep.id_producto, COALESCE(ep.id_presentacion, 0) as id_presentacion,
            ep.id_ubicacion, SUM(ep.cantidad) as cantidad_ventas
        FROM app_dat_operacion_venta ov
        INNER JOIN app_dat_operaciones o ON ov.id_operacion = o.id
        INNER JOIN app_dat_extraccion_productos ep ON o.id = ep.id_operacion
        INNER JOIN app_dat_inventario_productos i ON ep.id = i.id_extraccion
        INNER JOIN estados_actuales ea ON o.id = ea.id_operacion
        WHERE o.id_tienda = p_id_tienda
          AND ea.estado = 2 -- Solo si su estado ACTUAL es COMPLETADA
          AND (v_fecha_hasta_ts IS NULL OR i.created_at <= v_fecha_hasta_ts)
          AND (v_fecha_desde_ts IS NULL OR i.created_at >= v_fecha_desde_ts)
        GROUP BY ep.id_producto, COALESCE(ep.id_presentacion, 0), ep.id_ubicacion
    ),
    costo_promedio_productos AS (
        SELECT rp.id_producto, COALESCE(rp.id_presentacion, 0) as id_presentacion,
            CASE WHEN SUM(rp.cantidad) > 0 THEN
                SUM(CASE WHEN rp.costo_real IS NOT NULL AND rp.costo_real > 0 THEN rp.costo_real * rp.cantidad
                         WHEN rp.precio_unitario IS NOT NULL AND rp.precio_unitario > 0 THEN rp.precio_unitario * rp.cantidad
                         ELSE 0 END) / SUM(rp.cantidad)
                ELSE 0 END AS costo_promedio_usd,
            SUM(rp.cantidad) as cantidad_total_recibida
        FROM app_dat_recepcion_productos rp
        INNER JOIN app_dat_operaciones o ON rp.id_operacion = o.id
        INNER JOIN app_dat_operacion_recepcion orp ON o.id = orp.id_operacion
        WHERE ((rp.precio_unitario IS NOT NULL AND rp.precio_unitario > 0) OR
               (rp.costo_real IS NOT NULL AND rp.costo_real > 0))
          AND (v_fecha_hasta_ts IS NULL OR rp.created_at <= v_fecha_hasta_ts)
        GROUP BY rp.id_producto, COALESCE(rp.id_presentacion, 0)
    ),
    tasa_conversion AS (
        SELECT tasa, fecha_actualizacion FROM tasas_conversion 
        WHERE moneda_origen = 'USD' AND moneda_destino = 'CUP'
        ORDER BY fecha_actualizacion DESC LIMIT 1
    ),
    presentacion_info AS (
        SELECT pp.id, np.denominacion AS presentacion_nombre
        FROM app_dat_producto_presentacion pp
        LEFT JOIN app_nom_presentacion np ON pp.id_presentacion = np.id
    ),
    variante_info AS (
        SELECT v.id as id_variante, a.denominacion as nombre_atributo, ao.valor as valor_opcion
        FROM app_dat_variantes v
        LEFT JOIN app_dat_atributos a ON v.id_atributo = a.id
        LEFT JOIN app_dat_atributo_opcion ao ON v.id = ao.id_atributo
    ),
    combinaciones_con_actividad AS (
        -- Consolidar todas las combinaciones reales que tienen ALGO de actividad (ignorando variantes)
        SELECT ic_comb.id_producto, ic_comb.id_presentacion, ic_comb.id_ubicacion FROM inventario_completo ic_comb
        UNION
        SELECT ep_comb.id_producto, ep_comb.id_presentacion, ep_comb.id_ubicacion FROM entradas_periodo ep_comb
        UNION
        SELECT ex_comb.id_producto, ex_comb.id_presentacion, ex_comb.id_ubicacion FROM extracciones_periodo ex_comb
        UNION
        SELECT vp_comb.id_producto, vp_comb.id_presentacion, vp_comb.id_ubicacion FROM ventas_periodo vp_comb
    ),
    productos_inventario_completo AS (
        SELECT 
            pb.*,
            uf.id_almacen, uf.almacen, uf.ubicacion,
            cca.id_ubicacion as actividad_id_ubicacion,
            COALESCE(cca.id_presentacion, 0) as inv_id_presentacion,
            COALESCE(ic.cantidad_inicial, 0) as cantidad_inicial,
            COALESCE(ic.cantidad_final, 0) as cantidad_final,
            CASE WHEN ic.id_producto IS NOT NULL THEN TRUE ELSE FALSE END as tiene_inventario
        FROM combinaciones_con_actividad cca
        INNER JOIN productos_base pb ON cca.id_producto = pb.id
        INNER JOIN ubicaciones_filtro uf ON cca.id_ubicacion = uf.id_ubicacion
        LEFT JOIN inventario_completo ic ON (
            cca.id_producto = ic.id_producto 
            AND cca.id_ubicacion = ic.id_ubicacion
            AND COALESCE(cca.id_presentacion, 0) = COALESCE(ic.id_presentacion, 0)
        )
    )
    SELECT pic.id_almacen::BIGINT, pic.almacen::TEXT, pic.actividad_id_ubicacion::BIGINT, pic.ubicacion::TEXT, pic.id::BIGINT as id_producto,
        CASE WHEN pic.inv_id_presentacion IS NOT NULL AND pres.presentacion_nombre IS NOT NULL
            THEN CONCAT(pic.nombre_producto_base, ' (', pres.presentacion_nombre, ')')
            ELSE pic.nombre_producto_base END::TEXT AS nombre_producto,
        pic.codigo::TEXT, pic.categoria::TEXT,
        GREATEST(COALESCE(pic.cantidad_final, 0) - COALESCE(sr.reservado, 0), 0)::NUMERIC,
        COALESCE(sr.reservado, 0)::NUMERIC, COALESCE(pic.cantidad_inicial, 0)::NUMERIC,
        COALESCE(pic.cantidad_final, 0)::NUMERIC, COALESCE(ent.cantidad_entradas, 0)::NUMERIC,
        COALESCE(ext.cantidad_extracciones, 0)::NUMERIC, COALESCE(vent.cantidad_ventas, 0)::NUMERIC,
        ROUND(COALESCE(vent.cantidad_ventas, 0) * pic.precio_venta, 2)::NUMERIC,
        pic.precio_venta::NUMERIC, COALESCE(cp.costo_promedio_usd, 0)::NUMERIC,
        ROUND(COALESCE(cp.costo_promedio_usd, 0) * COALESCE(tc.tasa, 1), 2)::NUMERIC,
        ROUND(GREATEST(COALESCE(pic.cantidad_final, 0) - COALESCE(sr.reservado, 0), 0) * COALESCE(cp.costo_promedio_usd, 0), 2)::NUMERIC,
        ROUND(GREATEST(COALESCE(pic.cantidad_final, 0) - COALESCE(sr.reservado, 0), 0) * ROUND(COALESCE(cp.costo_promedio_usd, 0) * COALESCE(tc.tasa, 1), 2), 2)::NUMERIC,
        ROUND(GREATEST(COALESCE(pic.cantidad_final, 0) - COALESCE(sr.reservado, 0), 0) * pic.precio_venta, 2)::NUMERIC,
        CASE WHEN COALESCE(vent.cantidad_ventas, 0) > 0 AND GREATEST(COALESCE(pic.cantidad_final, 0) - COALESCE(sr.reservado, 0), 0) > 0 
            THEN ROUND((GREATEST(COALESCE(pic.cantidad_final, 0) - COALESCE(sr.reservado, 0), 0) / COALESCE(vent.cantidad_ventas, 0)) * 30, 1) ELSE NULL END::NUMERIC,
        CASE WHEN COALESCE(vent.cantidad_ventas, 0) > 0 AND GREATEST(COALESCE(pic.cantidad_final, 0) - COALESCE(sr.reservado, 0), 0) > 0 
            THEN ROUND((COALESCE(vent.cantidad_ventas, 0) / GREATEST(COALESCE(pic.cantidad_final, 0) - COALESCE(sr.reservado, 0), 0)) * 12, 2) ELSE 0 END::NUMERIC,
        CASE WHEN ROUND(COALESCE(cp.costo_promedio_usd, 0) * COALESCE(tc.tasa, 1), 2) > 0 AND pic.precio_venta > 0 
            THEN ROUND(((pic.precio_venta / ROUND(COALESCE(cp.costo_promedio_usd, 0) * COALESCE(tc.tasa, 1), 2)) - 1) * 100, 2) ELSE 0 END::NUMERIC,
        COALESCE(tc.tasa, 1)::NUMERIC, NOW()::TIMESTAMP, pic.tiene_inventario::BOOLEAN,
        COALESCE(pic.sku, '')::TEXT, pic.id_categoria::BIGINT, COALESCE(pic.nombre_comercial, '')::TEXT,
        COALESCE(pic.denominacion_corta, '')::TEXT, COALESCE(pic.descripcion, '')::TEXT,
        COALESCE(pic.descripcion_corta, '')::TEXT, COALESCE(pic.um, '')::TEXT,
        COALESCE(pic.es_refrigerado, false)::BOOLEAN, COALESCE(pic.es_fragil, false)::BOOLEAN,
        COALESCE(pic.es_peligroso, false)::BOOLEAN, COALESCE(pic.es_vendible, true)::BOOLEAN,
        COALESCE(pic.es_comprable, true)::BOOLEAN, COALESCE(pic.es_inventariable, true)::BOOLEAN,
        COALESCE(pic.es_por_lotes, false)::BOOLEAN, pic.dias_alert_caducidad::NUMERIC,
        pic.producto_created_at::TIMESTAMP, COALESCE(pic.imagen, '')::TEXT,
        COALESCE(pic.es_elaborado, false)::BOOLEAN, COALESCE(pic.es_servicio, false)::BOOLEAN, pic.deleted_at::TIMESTAMP
    FROM productos_inventario_completo pic
    LEFT JOIN stock_reservado sr ON (pic.id = sr.id_producto 
        AND pic.inv_id_presentacion = sr.id_presentacion
        AND pic.actividad_id_ubicacion = sr.id_ubicacion)
    LEFT JOIN entradas_periodo ent ON (pic.id = ent.id_producto 
        AND pic.inv_id_presentacion = ent.id_presentacion
        AND pic.actividad_id_ubicacion = ent.id_ubicacion)
    LEFT JOIN extracciones_periodo ext ON (pic.id = ext.id_producto 
        AND pic.inv_id_presentacion = ext.id_presentacion
        AND pic.actividad_id_ubicacion = ext.id_ubicacion)
    LEFT JOIN ventas_periodo vent ON (pic.id = vent.id_producto 
        AND pic.inv_id_presentacion = vent.id_presentacion
        AND pic.actividad_id_ubicacion = vent.id_ubicacion)
    LEFT JOIN costo_promedio_productos cp ON (pic.id = cp.id_producto 
        AND pic.inv_id_presentacion = cp.id_presentacion)
    LEFT JOIN presentacion_info pres ON pic.inv_id_presentacion = pres.id
    CROSS JOIN tasa_conversion tc
    WHERE (CASE WHEN p_include_zero = TRUE THEN pic.tiene_inventario = TRUE
        ELSE (GREATEST(COALESCE(pic.cantidad_final, 0) - COALESCE(sr.reservado, 0), 0) > 0
            OR COALESCE(pic.cantidad_inicial, 0) > 0 OR COALESCE(pic.cantidad_final, 0) > 0
            OR COALESCE(ent.cantidad_entradas, 0) > 0 OR COALESCE(ext.cantidad_extracciones, 0) > 0
            OR COALESCE(vent.cantidad_ventas, 0) > 0) END)
    ORDER BY pic.tiene_inventario DESC, pic.almacen, pic.ubicacion, pic.nombre_producto_base;
END;
$$ LANGUAGE plpgsql STABLE;
