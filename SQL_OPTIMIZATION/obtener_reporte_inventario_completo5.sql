-- ============================================================================
-- FUNCIÓN: obtener_reporte_inventario_completo5
-- Variante de obtener_reporte_inventario_completo4 que reorganiza el cálculo
-- de movimientos partiendo de app_dat_inventario_productos.
-- ============================================================================
-- Diferencias respecto a la versión 4:
--   1. Se listan todos los productos de la tienda y se cruzan con sus ubicaciones.
--   2. Se buscan los movimientos de inventario de cada producto/ubicación en
--      el rango de fechas, y desde esos movimientos se obtienen las operaciones
--      para conocer estado y tipo (entrada, extracción, venta).
--   3. Se separan los pendientes en:
--        - cantidad_reservada: salidas/extracciones en operaciones pendientes (estado = 1)
--        - cantidad_pendiente_entrada: recepciones en operaciones pendientes (estado = 1)
--   4. Se mantiene stock_reservado como alias de cantidad_reservada por compatibilidad.
-- ============================================================================

DROP FUNCTION IF EXISTS public.obtener_reporte_inventario_completo5(
    BIGINT, TEXT, TEXT, BIGINT, BOOLEAN
);

CREATE OR REPLACE FUNCTION public.obtener_reporte_inventario_completo5(
    p_id_tienda   BIGINT,
    p_fecha_desde TEXT    DEFAULT NULL,
    p_fecha_hasta TEXT    DEFAULT NULL,
    p_id_almacen  BIGINT  DEFAULT NULL,
    p_include_zero BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    id_almacen                  BIGINT,
    almacen                     TEXT,
    id_ubicacion                BIGINT,
    ubicacion                   TEXT,
    id_producto                 BIGINT,
    nombre_producto             TEXT,
    codigo                      TEXT,
    categoria                   TEXT,
    stock_disponible            NUMERIC,   -- cantidad_final - reservado (>=0)
    stock_reservado             NUMERIC,   -- reservado en ops pendientes
    cantidad_inicial            NUMERIC,
    cantidad_final              NUMERIC,
    entradas_periodo            NUMERIC,
    extracciones_periodo        NUMERIC,
    ventas_periodo              NUMERIC,
    monto_ventas                NUMERIC,
    precio_venta                NUMERIC,
    costo_promedio_usd          NUMERIC,
    costo_promedio_cup          NUMERIC,
    valor_inventario_usd        NUMERIC,
    valor_inventario_cup        NUMERIC,
    valor_venta_inventario      NUMERIC,
    dias_inventario             NUMERIC,
    rotacion_anual              NUMERIC,
    margen_bruto_pct            NUMERIC,
    tasa_cambio                 NUMERIC,
    fecha_reporte               TIMESTAMP,
    tiene_inventario            BOOLEAN,
    sku                         TEXT,
    id_categoria                BIGINT,
    nombre_comercial            TEXT,
    denominacion_corta          TEXT,
    descripcion                 TEXT,
    descripcion_corta           TEXT,
    um                          TEXT,
    es_refrigerado              BOOLEAN,
    es_fragil                   BOOLEAN,
    es_peligroso                BOOLEAN,
    es_vendible                 BOOLEAN,
    es_comprable                BOOLEAN,
    es_inventariable            BOOLEAN,
    es_por_lotes                BOOLEAN,
    dias_alert_caducidad        NUMERIC,
    producto_created_at         TIMESTAMP,
    imagen                      TEXT,
    es_elaborado                BOOLEAN,
    es_servicio                 BOOLEAN,
    deleted_at                  TIMESTAMP,
    -- NUEVA COLUMNA: cantidad reservada en operaciones pendientes
    cantidad_reservada          NUMERIC,
    -- NUEVA COLUMNA: recepciones pendientes (estado = 1)
    cantidad_pendiente_entrada  NUMERIC,
    -- Alias de compatibilidad para el código Dart/Flutter
    sku_producto                TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
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

    v_fecha_desde_ts := CASE WHEN p_fecha_desde IS NOT NULL THEN p_fecha_desde::TIMESTAMP ELSE NULL END;
    v_fecha_hasta_ts := CASE WHEN p_fecha_hasta IS NOT NULL THEN (p_fecha_hasta::DATE + INTERVAL '1 day' - INTERVAL '1 second')::TIMESTAMP ELSE NULL END;

    RAISE NOTICE 'DEBUG: v_fecha_desde_ts = %, v_fecha_hasta_ts = %', v_fecha_desde_ts, v_fecha_hasta_ts;

    RETURN QUERY
    WITH productos_base AS (
        SELECT DISTINCT p.id, p.denominacion AS nombre_producto_base, p.codigo_barras as codigo,
            c.denominacion as categoria, COALESCE(pv.precio_venta_cup, 0) as precio_venta, t.id as id_tienda_filtro,
            p.sku, p.id_categoria, p.nombre_comercial, p.denominacion_corta, p.descripcion, p.descripcion_corta,
            p.um, p.es_refrigerado, p.es_fragil, p.es_peligroso, p.es_vendible, p.es_comprable,
            p.es_inventariable, p.es_por_lotes, p.dias_alert_caducidad, p.created_at AS producto_created_at,
            p.imagen, p.es_elaborado, p.es_servicio, p.deleted_at
        FROM app_dat_producto p
        INNER JOIN app_dat_tienda t ON p.id_tienda = t.id
        LEFT JOIN app_dat_precio_venta pv ON p.id = pv.id_producto 
            AND (pv.id_variante IS NULL OR pv.id_variante = 0)
            AND (pv.fecha_hasta IS NULL OR pv.fecha_hasta >= CURRENT_DATE)
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
    inventario_inicial AS (
        SELECT DISTINCT ON (i.id_producto, COALESCE(i.id_variante, 0), COALESCE(i.id_opcion_variante, 0), 
                           COALESCE(i.id_presentacion, 0), COALESCE(i.id_ubicacion, 0))
            i.id_producto, i.id_variante, i.id_opcion_variante, i.id_ubicacion, i.id_presentacion,
            i.cantidad_final as cantidad_inicial, i.created_at
        FROM app_dat_inventario_productos i
        INNER JOIN ubicaciones_filtro uf ON i.id_ubicacion = uf.id_ubicacion
        WHERE (v_fecha_desde_ts IS NULL OR i.created_at < v_fecha_desde_ts)
        ORDER BY i.id_producto, COALESCE(i.id_variante, 0), COALESCE(i.id_opcion_variante, 0), 
                 COALESCE(i.id_presentacion, 0), COALESCE(i.id_ubicacion, 0), i.created_at DESC, i.id DESC
    ),
    inventario_final AS (
        SELECT DISTINCT ON (i.id_producto, COALESCE(i.id_variante, 0), COALESCE(i.id_opcion_variante, 0), 
                           COALESCE(i.id_presentacion, 0), COALESCE(i.id_ubicacion, 0))
            i.id_producto, i.id_variante, i.id_opcion_variante, i.id_ubicacion, i.id_presentacion,
            i.cantidad_final, i.created_at
        FROM app_dat_inventario_productos i
        INNER JOIN ubicaciones_filtro uf ON i.id_ubicacion = uf.id_ubicacion
        WHERE (v_fecha_hasta_ts IS NULL OR i.created_at <= v_fecha_hasta_ts)
        ORDER BY i.id_producto, COALESCE(i.id_variante, 0), COALESCE(i.id_opcion_variante, 0), 
                 COALESCE(i.id_presentacion, 0), COALESCE(i.id_ubicacion, 0), i.created_at DESC, i.id DESC
    ),
    inventario_completo AS (
        SELECT 
            COALESCE(ii.id_producto, ifin.id_producto) as id_producto,
            COALESCE(ii.id_variante, ifin.id_variante) as id_variante,
            COALESCE(ii.id_opcion_variante, ifin.id_opcion_variante) as id_opcion_variante,
            COALESCE(ii.id_ubicacion, ifin.id_ubicacion) as id_ubicacion,
            COALESCE(ii.id_presentacion, ifin.id_presentacion) as id_presentacion,
            COALESCE(ii.cantidad_inicial, 0) as cantidad_inicial,
            COALESCE(ifin.cantidad_final, 0) as cantidad_final
        FROM inventario_inicial ii
        FULL OUTER JOIN inventario_final ifin ON (
            ii.id_producto = ifin.id_producto
            AND COALESCE(ii.id_variante, 0) = COALESCE(ifin.id_variante, 0)
            AND COALESCE(ii.id_opcion_variante, 0) = COALESCE(ifin.id_opcion_variante, 0)
            AND COALESCE(ii.id_presentacion, 0) = COALESCE(ifin.id_presentacion, 0)
            AND COALESCE(ii.id_ubicacion, 0) = COALESCE(ifin.id_ubicacion, 0)
        )
    ),
    -- Movimientos de inventario en el rango/ubicación, para identificar operaciones
    movimientos_inventario AS (
        SELECT DISTINCT
            i.id_producto,
            COALESCE(i.id_variante, 0) as id_variante,
            COALESCE(i.id_opcion_variante, 0) as id_opcion_variante,
            COALESCE(i.id_presentacion, 0) as id_presentacion,
            i.id_ubicacion,
            i.id_operacion
        FROM app_dat_inventario_productos i
        INNER JOIN ubicaciones_filtro uf ON i.id_ubicacion = uf.id_ubicacion
        WHERE i.id_operacion IS NOT NULL
          AND (v_fecha_hasta_ts IS NULL OR i.created_at <= v_fecha_hasta_ts)
          AND (v_fecha_desde_ts IS NULL OR i.created_at >= v_fecha_desde_ts)
    ),
    -- Operaciones asociadas a los movimientos, con su estado actual
    operaciones_movimientos AS (
        SELECT DISTINCT
            mi.id_producto,
            mi.id_variante,
            mi.id_opcion_variante,
            mi.id_presentacion,
            mi.id_ubicacion,
            mi.id_operacion,
            COALESCE(eo.estado, 0) as estado
        FROM movimientos_inventario mi
        INNER JOIN app_dat_operaciones o ON mi.id_operacion = o.id
        LEFT JOIN app_dat_estado_operacion eo ON o.id = eo.id_operacion
    ),
    -- Entradas del periodo: recepciones completadas vinculadas a movimientos de inventario
    entradas_periodo AS (
        SELECT
            om.id_producto,
            om.id_variante,
            om.id_opcion_variante,
            om.id_presentacion,
            om.id_ubicacion,
            SUM(rp.cantidad) as cantidad_entradas
        FROM operaciones_movimientos om
        INNER JOIN app_dat_operacion_recepcion orp ON om.id_operacion = orp.id_operacion
        INNER JOIN app_dat_recepcion_productos rp ON (
            om.id_operacion = rp.id_operacion
            AND om.id_producto = rp.id_producto
            AND om.id_variante = COALESCE(rp.id_variante, 0)
            AND om.id_opcion_variante = COALESCE(rp.id_opcion_variante, 0)
            AND om.id_presentacion = COALESCE(rp.id_presentacion, 0)
            AND om.id_ubicacion = rp.id_ubicacion
        )
        WHERE om.estado = 2
        GROUP BY om.id_producto, om.id_variante, om.id_opcion_variante, om.id_presentacion, om.id_ubicacion
    ),
    -- Extracciones del periodo (no ventas): extracciones completadas vinculadas a movimientos
    extracciones_periodo AS (
        SELECT
            om.id_producto,
            om.id_variante,
            om.id_opcion_variante,
            om.id_presentacion,
            om.id_ubicacion,
            SUM(ep.cantidad) as cantidad_extracciones
        FROM operaciones_movimientos om
        INNER JOIN app_dat_operacion_extraccion oe ON om.id_operacion = oe.id_operacion
        INNER JOIN app_dat_extraccion_productos ep ON (
            om.id_operacion = ep.id_operacion
            AND om.id_producto = ep.id_producto
            AND om.id_variante = COALESCE(ep.id_variante, 0)
            AND om.id_opcion_variante = COALESCE(ep.id_opcion_variante, 0)
            AND om.id_presentacion = COALESCE(ep.id_presentacion, 0)
            AND om.id_ubicacion = ep.id_ubicacion
        )
        WHERE om.estado = 2
          AND oe.id_motivo_operacion <= 10
        GROUP BY om.id_producto, om.id_variante, om.id_opcion_variante, om.id_presentacion, om.id_ubicacion
    ),
    -- Ventas del periodo: extracciones completadas que son operaciones de venta
    ventas_periodo AS (
        SELECT
            om.id_producto,
            om.id_variante,
            om.id_opcion_variante,
            om.id_presentacion,
            om.id_ubicacion,
            SUM(ep.cantidad) as cantidad_ventas
        FROM operaciones_movimientos om
        INNER JOIN app_dat_operacion_venta ov ON om.id_operacion = ov.id_operacion
        INNER JOIN app_dat_extraccion_productos ep ON (
            om.id_operacion = ep.id_operacion
            AND om.id_producto = ep.id_producto
            AND om.id_variante = COALESCE(ep.id_variante, 0)
            AND om.id_opcion_variante = COALESCE(ep.id_opcion_variante, 0)
            AND om.id_presentacion = COALESCE(ep.id_presentacion, 0)
            AND om.id_ubicacion = ep.id_ubicacion
        )
        WHERE om.estado = 2
        GROUP BY om.id_producto, om.id_variante, om.id_opcion_variante, om.id_presentacion, om.id_ubicacion
    ),
    -- Stock reservado: salidas pendientes (extracciones en operaciones con estado = 1)
    -- NOTA: se calcula directamente desde operaciones, ya que las operaciones pendientes
    -- aún no generan movimiento de inventario.
    stock_reservado AS (
        SELECT
            ep.id_producto,
            COALESCE(ep.id_variante, 0) as id_variante,
            COALESCE(ep.id_opcion_variante, 0) as id_opcion_variante,
            COALESCE(ep.id_presentacion, 0) as id_presentacion,
            ep.id_ubicacion,
            SUM(ep.cantidad) AS reservado
        FROM app_dat_extraccion_productos ep
        INNER JOIN app_dat_operaciones o ON ep.id_operacion = o.id
        INNER JOIN app_dat_estado_operacion eo ON o.id = eo.id_operacion
        WHERE eo.estado = 1
        GROUP BY ep.id_producto, COALESCE(ep.id_variante, 0), COALESCE(ep.id_opcion_variante, 0), COALESCE(ep.id_presentacion, 0), ep.id_ubicacion
    ),
    -- Pendientes de entrada: recepciones en operaciones con estado = 1
    pendientes_entrada AS (
        SELECT
            rp.id_producto,
            COALESCE(rp.id_variante, 0) as id_variante,
            COALESCE(rp.id_opcion_variante, 0) as id_opcion_variante,
            COALESCE(rp.id_presentacion, 0) as id_presentacion,
            rp.id_ubicacion,
            SUM(rp.cantidad) AS cantidad_pendiente_entrada
        FROM app_dat_recepcion_productos rp
        INNER JOIN app_dat_operaciones o ON rp.id_operacion = o.id
        INNER JOIN app_dat_estado_operacion eo ON o.id = eo.id_operacion
        WHERE eo.estado = 1
        GROUP BY rp.id_producto, COALESCE(rp.id_variante, 0), COALESCE(rp.id_opcion_variante, 0), COALESCE(rp.id_presentacion, 0), rp.id_ubicacion
    ),
    costo_promedio_productos AS (
        SELECT rp.id_producto, COALESCE(rp.id_variante, 0) as id_variante,
            COALESCE(rp.id_opcion_variante, 0) as id_opcion_variante, COALESCE(rp.id_presentacion, 0) as id_presentacion,
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
        GROUP BY rp.id_producto, COALESCE(rp.id_variante, 0), COALESCE(rp.id_opcion_variante, 0), COALESCE(rp.id_presentacion, 0)
    ),
    tasa_conversion AS (
        SELECT
            COALESCE(custom.valor_cambio, fallback.tasa, 1)::NUMERIC AS tasa,
            COALESCE(custom.created_at, fallback.fecha_actualizacion, NOW()) AS fecha_actualizacion
        FROM (SELECT 1) x
        LEFT JOIN LATERAL (
            SELECT tce.valor_cambio, tce.created_at
            FROM tasa_cambio_extraoficial tce
            WHERE tce.id_tienda = p_id_tienda
              AND tce.activo = TRUE
              AND tce.id_moneda_origen = 2
              AND tce.id_moneda_destino = 1
              AND COALESCE(tce.usar_precio_toque, FALSE) = FALSE
              AND tce.valor_cambio IS NOT NULL
              AND tce.valor_cambio > 0
            ORDER BY tce.created_at DESC
            LIMIT 1
        ) custom ON TRUE
        LEFT JOIN LATERAL (
            SELECT tc_inner.tasa, tc_inner.fecha_actualizacion
            FROM tasas_conversion tc_inner
            WHERE tc_inner.moneda_origen = 'USD'
              AND tc_inner.moneda_destino = 'CUP'
            ORDER BY tc_inner.fecha_actualizacion DESC
            LIMIT 1
        ) fallback ON TRUE
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
    productos_ubicaciones AS (
        SELECT pb.*, uf.id_ubicacion, uf.ubicacion, uf.id_almacen, uf.almacen
        FROM productos_base pb
        CROSS JOIN ubicaciones_filtro uf
    ),
    productos_inventario_completo AS (
        SELECT pu.*, COALESCE(ic.id_variante, NULL) as inv_id_variante,
            COALESCE(ic.id_opcion_variante, NULL) as inv_id_opcion_variante,
            COALESCE(ic.id_presentacion, NULL) as inv_id_presentacion,
            COALESCE(ic.cantidad_inicial, 0) as cantidad_inicial,
            COALESCE(ic.cantidad_final, 0) as cantidad_final,
            CASE WHEN ic.id_producto IS NOT NULL THEN TRUE ELSE FALSE END as tiene_inventario
        FROM productos_ubicaciones pu
        LEFT JOIN inventario_completo ic ON (pu.id = ic.id_producto AND pu.id_ubicacion = ic.id_ubicacion)
    )
    SELECT
        pic.id_almacen::BIGINT,
        pic.almacen::TEXT,
        pic.id_ubicacion::BIGINT,
        pic.ubicacion::TEXT,
        pic.id::BIGINT AS id_producto,
        CASE
            WHEN pic.inv_id_presentacion IS NOT NULL AND pres.presentacion_nombre IS NOT NULL 
                 AND pic.inv_id_variante IS NOT NULL AND vi.nombre_atributo IS NOT NULL
            THEN CONCAT(pic.nombre_producto_base, ' ', vi.nombre_atributo, ': ', vi.valor_opcion, ' (', pres.presentacion_nombre, ')')
            WHEN pic.inv_id_presentacion IS NOT NULL AND pres.presentacion_nombre IS NOT NULL
            THEN CONCAT(pic.nombre_producto_base, ' (', pres.presentacion_nombre, ')')
            WHEN pic.inv_id_variante IS NOT NULL AND vi.nombre_atributo IS NOT NULL
            THEN CONCAT(pic.nombre_producto_base, ' ', vi.nombre_atributo, ': ', vi.valor_opcion)
            ELSE pic.nombre_producto_base
        END::TEXT AS nombre_producto,
        pic.codigo::TEXT,
        pic.categoria::TEXT,
        -- Stock disponible (cantidad_final - reservado, mínimo 0)
        GREATEST(COALESCE(pic.cantidad_final, 0) - COALESCE(sr.reservado, 0), 0)::NUMERIC AS stock_disponible,
        -- Stock reservado en operaciones pendientes
        COALESCE(sr.reservado, 0)::NUMERIC AS stock_reservado,
        COALESCE(pic.cantidad_inicial, 0)::NUMERIC AS cantidad_inicial,
        COALESCE(pic.cantidad_final, 0)::NUMERIC AS cantidad_final,
        COALESCE(ent.cantidad_entradas, 0)::NUMERIC AS entradas_periodo,
        COALESCE(ext.cantidad_extracciones, 0)::NUMERIC AS extracciones_periodo,
        COALESCE(vent.cantidad_ventas, 0)::NUMERIC AS ventas_periodo,
        ROUND(COALESCE(vent.cantidad_ventas, 0) * pic.precio_venta, 2)::NUMERIC AS monto_ventas,
        pic.precio_venta::NUMERIC,
        COALESCE(cp.costo_promedio_usd, 0)::NUMERIC AS costo_promedio_usd,
        ROUND(COALESCE(cp.costo_promedio_usd, 0) * COALESCE(tc.tasa, 1), 2)::NUMERIC AS costo_promedio_cup,
        ROUND(GREATEST(COALESCE(pic.cantidad_final, 0) - COALESCE(sr.reservado, 0), 0) * COALESCE(cp.costo_promedio_usd, 0), 2)::NUMERIC AS valor_inventario_usd,
        ROUND(GREATEST(COALESCE(pic.cantidad_final, 0) - COALESCE(sr.reservado, 0), 0) * ROUND(COALESCE(cp.costo_promedio_usd, 0) * COALESCE(tc.tasa, 1), 2), 2)::NUMERIC AS valor_inventario_cup,
        ROUND(GREATEST(COALESCE(pic.cantidad_final, 0) - COALESCE(sr.reservado, 0), 0) * pic.precio_venta, 2)::NUMERIC AS valor_venta_inventario,
        CASE
            WHEN COALESCE(vent.cantidad_ventas, 0) > 0 AND GREATEST(COALESCE(pic.cantidad_final, 0) - COALESCE(sr.reservado, 0), 0) > 0 
            THEN ROUND((GREATEST(COALESCE(pic.cantidad_final, 0) - COALESCE(sr.reservado, 0), 0) / COALESCE(vent.cantidad_ventas, 0)) * 30, 1)
            ELSE NULL
        END::NUMERIC AS dias_inventario,
        CASE
            WHEN COALESCE(vent.cantidad_ventas, 0) > 0 AND GREATEST(COALESCE(pic.cantidad_final, 0) - COALESCE(sr.reservado, 0), 0) > 0 
            THEN ROUND((COALESCE(vent.cantidad_ventas, 0) / GREATEST(COALESCE(pic.cantidad_final, 0) - COALESCE(sr.reservado, 0), 0)) * 12, 2)
            ELSE 0
        END::NUMERIC AS rotacion_anual,
        CASE
            WHEN ROUND(COALESCE(cp.costo_promedio_usd, 0) * COALESCE(tc.tasa, 1), 2) > 0 AND pic.precio_venta > 0 
            THEN ROUND(((pic.precio_venta / ROUND(COALESCE(cp.costo_promedio_usd, 0) * COALESCE(tc.tasa, 1), 2)) - 1) * 100, 2)
            ELSE 0
        END::NUMERIC AS margen_bruto_pct,
        COALESCE(tc.tasa, 1)::NUMERIC AS tasa_cambio,
        NOW()::TIMESTAMP AS fecha_reporte,
        pic.tiene_inventario::BOOLEAN,
        COALESCE(pic.sku, '')::TEXT AS sku,
        pic.id_categoria::BIGINT,
        COALESCE(pic.nombre_comercial, '')::TEXT AS nombre_comercial,
        COALESCE(pic.denominacion_corta, '')::TEXT AS denominacion_corta,
        COALESCE(pic.descripcion, '')::TEXT AS descripcion,
        COALESCE(pic.descripcion_corta, '')::TEXT AS descripcion_corta,
        COALESCE(pic.um, '')::TEXT AS um,
        COALESCE(pic.es_refrigerado, false)::BOOLEAN,
        COALESCE(pic.es_fragil, false)::BOOLEAN,
        COALESCE(pic.es_peligroso, false)::BOOLEAN,
        COALESCE(pic.es_vendible, true)::BOOLEAN,
        COALESCE(pic.es_comprable, true)::BOOLEAN,
        COALESCE(pic.es_inventariable, true)::BOOLEAN,
        COALESCE(pic.es_por_lotes, false)::BOOLEAN,
        pic.dias_alert_caducidad::NUMERIC,
        pic.producto_created_at::TIMESTAMP,
        COALESCE(pic.imagen, '')::TEXT,
        COALESCE(pic.es_elaborado, false)::BOOLEAN,
        COALESCE(pic.es_servicio, false)::BOOLEAN,
        pic.deleted_at::TIMESTAMP,
        -- NUEVA COLUMNA: cantidad reservada (igual que stock_reservado, alias explícito)
        COALESCE(sr.reservado, 0)::NUMERIC AS cantidad_reservada,
        -- NUEVA COLUMNA: recepciones pendientes (estado = 1)
        COALESCE(pe.cantidad_pendiente_entrada, 0)::NUMERIC AS cantidad_pendiente_entrada,
        -- Alias de compatibilidad para el código Dart/Flutter
        COALESCE(pic.sku, '')::TEXT AS sku_producto
    FROM productos_inventario_completo pic
    LEFT JOIN stock_reservado sr ON (
        pic.id = sr.id_producto
        AND COALESCE(pic.inv_id_variante, 0) = sr.id_variante
        AND COALESCE(pic.inv_id_opcion_variante, 0) = sr.id_opcion_variante
        AND COALESCE(pic.inv_id_presentacion, 0) = sr.id_presentacion
        AND pic.id_ubicacion = sr.id_ubicacion
    )
    LEFT JOIN pendientes_entrada pe ON (
        pic.id = pe.id_producto
        AND COALESCE(pic.inv_id_variante, 0) = pe.id_variante
        AND COALESCE(pic.inv_id_opcion_variante, 0) = pe.id_opcion_variante
        AND COALESCE(pic.inv_id_presentacion, 0) = pe.id_presentacion
        AND pic.id_ubicacion = pe.id_ubicacion
    )
    LEFT JOIN entradas_periodo ent ON (
        pic.id = ent.id_producto
        AND COALESCE(pic.inv_id_variante, 0) = ent.id_variante
        AND COALESCE(pic.inv_id_opcion_variante, 0) = ent.id_opcion_variante
        AND COALESCE(pic.inv_id_presentacion, 0) = ent.id_presentacion
        AND pic.id_ubicacion = ent.id_ubicacion
    )
    LEFT JOIN extracciones_periodo ext ON (
        pic.id = ext.id_producto
        AND COALESCE(pic.inv_id_variante, 0) = ext.id_variante
        AND COALESCE(pic.inv_id_opcion_variante, 0) = ext.id_opcion_variante
        AND COALESCE(pic.inv_id_presentacion, 0) = ext.id_presentacion
        AND pic.id_ubicacion = ext.id_ubicacion
    )
    LEFT JOIN ventas_periodo vent ON (
        pic.id = vent.id_producto
        AND COALESCE(pic.inv_id_variante, 0) = vent.id_variante
        AND COALESCE(pic.inv_id_opcion_variante, 0) = vent.id_opcion_variante
        AND COALESCE(pic.inv_id_presentacion, 0) = vent.id_presentacion
        AND pic.id_ubicacion = vent.id_ubicacion
    )
    LEFT JOIN costo_promedio_productos cp ON (
        pic.id = cp.id_producto
        AND COALESCE(pic.inv_id_variante, 0) = cp.id_variante
        AND COALESCE(pic.inv_id_opcion_variante, 0) = cp.id_opcion_variante
        AND COALESCE(pic.inv_id_presentacion, 0) = cp.id_presentacion
    )
    LEFT JOIN presentacion_info pres ON pic.inv_id_presentacion = pres.id
    LEFT JOIN variante_info vi ON pic.inv_id_variante = vi.id_variante
    CROSS JOIN tasa_conversion tc
    WHERE (
        CASE
            WHEN p_include_zero = TRUE THEN pic.tiene_inventario = TRUE
            ELSE (
                GREATEST(COALESCE(pic.cantidad_final, 0) - COALESCE(sr.reservado, 0), 0) > 0
                OR COALESCE(pic.cantidad_inicial, 0) > 0
                OR COALESCE(pic.cantidad_final, 0) > 0
                OR COALESCE(ent.cantidad_entradas, 0) > 0
                OR COALESCE(ext.cantidad_extracciones, 0) > 0
                OR COALESCE(vent.cantidad_ventas, 0) > 0
                OR COALESCE(pe.cantidad_pendiente_entrada, 0) > 0
            )
        END
    )
    ORDER BY pic.tiene_inventario DESC, pic.almacen, pic.ubicacion, pic.nombre_producto_base;

END;
$$;

-- Grants de acceso
GRANT EXECUTE ON FUNCTION public.obtener_reporte_inventario_completo5(BIGINT, TEXT, TEXT, BIGINT, BOOLEAN)
    TO authenticated, anon;

-- ============================================================================
-- VERIFICACIÓN: Confirmar que retorna la nueva columna
-- SELECT id_producto, nombre_producto, stock_disponible, stock_reservado, cantidad_reservada, cantidad_pendiente_entrada
-- FROM obtener_reporte_inventario_completo5(1)
-- LIMIT 10;
-- ============================================================================
