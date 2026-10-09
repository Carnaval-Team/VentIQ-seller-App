-- ============================================================================
-- FUNCIÓN: obtener_reporte_inventario_export
-- Reporte de inventario con columnas:
--   cantidad_inicial, entradas_periodo, extracciones_periodo, ventas_periodo,
--   cantidad_reservada (pendiente de salida), cantidad_final.
-- Todo por (producto, variante, opción_variante, presentación, ubicación).
--
-- Reglas (confirmadas con el esquema real de Supabase):
-- * Inicial: cantidad_final del último registro de app_dat_inventario_productos
--   con created_at estrictamente anterior al rango. Si no existe ninguno,
--   se usa la cantidad_inicial del primer registro dentro del rango.
-- * Final: cantidad_final del último registro de app_dat_inventario_productos
--   con created_at dentro del rango.
-- * NOTA: origen_cambio de app_dat_inventario_productos NO identifica el tipo
--   de operación (una venta aparece con origen 2, 3 o 4). Se clasifica por el
--   tipo de la operación enlazada (recepción/extracción/control/conversión).
-- * Entradas: operaciones de tipo (1,3,5,8,11) que no son venta, completadas
--   (estado = 2) y con app_dat_operaciones.created_at en el rango.
-- * Extracciones: operaciones tipo 18 que no son venta, completadas en el rango.
-- * Ventas: operaciones con registro en app_dat_operacion_venta y estado
--   Completada (2), Facturada (10) o Despachada (12), created_at en el rango.
-- * Pendiente (cantidad_reservada): operaciones creadas en el rango cuyo estado
--   actual sea Pendiente (1) y su tipo de operación tenga acción 'salida'.
--   Se toma la cantidad desde app_dat_extraccion_productos porque las ops
--   pendientes aún no generan movimiento en inventario.
-- * Filtro de almacén: app_dat_inventario_productos.id_ubicacion referencia
--   app_dat_layout_almacen.id, que tiene id_almacen.
-- ============================================================================

DROP FUNCTION IF EXISTS public.obtener_reporte_inventario_export(
    BIGINT, TEXT, TEXT, BIGINT, BOOLEAN, BOOLEAN
);

CREATE OR REPLACE FUNCTION public.obtener_reporte_inventario_export(
    p_id_tienda   BIGINT,
    p_fecha_desde TEXT    DEFAULT NULL,
    p_fecha_hasta TEXT    DEFAULT NULL,
    p_id_almacen  BIGINT  DEFAULT NULL,
    p_include_zero BOOLEAN DEFAULT FALSE,
    p_solo_completadas_en_periodo BOOLEAN DEFAULT FALSE
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
    sku                         TEXT,
    sku_producto                TEXT,
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
    id_presentacion             BIGINT,
    presentacion                TEXT,
    id_variante                 BIGINT,
    id_opcion_variante          BIGINT,
    cantidad_inicial            NUMERIC,
    entradas_periodo            NUMERIC,
    extracciones_periodo        NUMERIC,
    ventas_periodo              NUMERIC,
    cantidad_reservada          NUMERIC,
    cantidad_final              NUMERIC,
    tiene_inventario            BOOLEAN,
    precio_venta                NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_fecha_desde_ts TIMESTAMP;
    v_fecha_hasta_ts TIMESTAMP;
BEGIN
    IF p_id_tienda IS NULL THEN
        RAISE EXCEPTION 'El id_tienda es obligatorio';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM app_dat_tienda t WHERE t.id = p_id_tienda) THEN
        RAISE EXCEPTION 'La tienda con ID % no existe', p_id_tienda;
    END IF;

    v_fecha_desde_ts := CASE WHEN p_fecha_desde IS NOT NULL THEN p_fecha_desde::TIMESTAMP ELSE NULL END;
    v_fecha_hasta_ts := CASE WHEN p_fecha_hasta IS NOT NULL THEN p_fecha_hasta::TIMESTAMP ELSE NULL END;

    IF v_fecha_desde_ts IS NOT NULL AND v_fecha_hasta_ts IS NOT NULL AND v_fecha_desde_ts > v_fecha_hasta_ts THEN
        RAISE EXCEPTION 'La fecha desde no puede ser mayor que la fecha hasta';
    END IF;

    -- Verificar que el usuario tenga acceso a la tienda.
    PERFORM public.check_user_has_access_to_tienda(p_id_tienda);

    RETURN QUERY
    WITH ubicaciones_filtro AS (
        SELECT
            l.id AS id_ubicacion,
            l.denominacion AS ubicacion,
            a.id AS id_almacen,
            a.denominacion AS almacen
        FROM app_dat_layout_almacen l
        INNER JOIN app_dat_almacen a ON l.id_almacen = a.id
        WHERE a.id_tienda = p_id_tienda
          AND (p_id_almacen IS NULL OR a.id = p_id_almacen)
    ),
    productos_base AS (
        SELECT
            p.id,
            p.denominacion AS nombre_producto_base,
            p.codigo_barras AS codigo,
            c.denominacion AS categoria,
            p.sku,
            p.id_categoria,
            p.nombre_comercial,
            p.denominacion_corta,
            p.descripcion,
            p.descripcion_corta,
            p.um,
            p.es_refrigerado,
            p.es_fragil,
            p.es_peligroso,
            p.es_vendible,
            p.es_comprable,
            p.es_inventariable,
            p.es_por_lotes,
            p.dias_alert_caducidad,
            p.created_at AS producto_created_at,
            p.imagen,
            p.es_elaborado,
            p.es_servicio,
            p.deleted_at
        FROM app_dat_producto p
        LEFT JOIN app_dat_categoria c ON p.id_categoria = c.id
        WHERE p.id_tienda = p_id_tienda
          AND COALESCE(p.es_inventariable, TRUE) = TRUE
          AND COALESCE(p.es_elaborado, FALSE) = FALSE
          AND COALESCE(p.es_servicio, FALSE) = FALSE
    ),
    inventario_filtrado AS (
        SELECT i.*
        FROM app_dat_inventario_productos i
        INNER JOIN ubicaciones_filtro uf ON i.id_ubicacion = uf.id_ubicacion
        INNER JOIN productos_base pb ON pb.id = i.id_producto
    ),
    inventario_previo AS (
        SELECT DISTINCT ON (
            i.id_producto,
            COALESCE(i.id_variante, 0),
            COALESCE(i.id_opcion_variante, 0),
            COALESCE(i.id_presentacion, 0),
            i.id_ubicacion
        )
            i.id_producto,
            i.id_variante,
            i.id_opcion_variante,
            i.id_presentacion,
            i.id_ubicacion,
            i.cantidad_final AS cantidad_inicial
        FROM inventario_filtrado i
        WHERE v_fecha_desde_ts IS NOT NULL
          AND i.created_at < v_fecha_desde_ts
        ORDER BY
            i.id_producto,
            COALESCE(i.id_variante, 0),
            COALESCE(i.id_opcion_variante, 0),
            COALESCE(i.id_presentacion, 0),
            i.id_ubicacion,
            i.created_at DESC,
            i.id DESC
    ),
    inventario_primero_rango AS (
        SELECT DISTINCT ON (
            i.id_producto,
            COALESCE(i.id_variante, 0),
            COALESCE(i.id_opcion_variante, 0),
            COALESCE(i.id_presentacion, 0),
            i.id_ubicacion
        )
            i.id_producto,
            i.id_variante,
            i.id_opcion_variante,
            i.id_presentacion,
            i.id_ubicacion,
            i.cantidad_inicial AS cantidad_inicial
        FROM inventario_filtrado i
        WHERE (v_fecha_desde_ts IS NULL OR i.created_at >= v_fecha_desde_ts)
          AND (v_fecha_hasta_ts IS NULL OR i.created_at <= v_fecha_hasta_ts)
        ORDER BY
            i.id_producto,
            COALESCE(i.id_variante, 0),
            COALESCE(i.id_opcion_variante, 0),
            COALESCE(i.id_presentacion, 0),
            i.id_ubicacion,
            i.created_at ASC,
            i.id ASC
    ),
    inventario_inicial AS (
        SELECT
            COALESCE(ip.id_producto, ir.id_producto) AS id_producto,
            COALESCE(ip.id_variante, ir.id_variante) AS id_variante,
            COALESCE(ip.id_opcion_variante, ir.id_opcion_variante) AS id_opcion_variante,
            COALESCE(ip.id_presentacion, ir.id_presentacion) AS id_presentacion,
            COALESCE(ip.id_ubicacion, ir.id_ubicacion) AS id_ubicacion,
            COALESCE(ip.cantidad_inicial, ir.cantidad_inicial) AS cantidad_inicial
        FROM inventario_previo ip
        FULL OUTER JOIN inventario_primero_rango ir ON (
            ip.id_producto = ir.id_producto
            AND COALESCE(ip.id_variante, 0) = COALESCE(ir.id_variante, 0)
            AND COALESCE(ip.id_opcion_variante, 0) = COALESCE(ir.id_opcion_variante, 0)
            AND COALESCE(ip.id_presentacion, 0) = COALESCE(ir.id_presentacion, 0)
            AND ip.id_ubicacion = ir.id_ubicacion
        )
    ),
    inventario_final AS (
        SELECT DISTINCT ON (
            i.id_producto,
            COALESCE(i.id_variante, 0),
            COALESCE(i.id_opcion_variante, 0),
            COALESCE(i.id_presentacion, 0),
            i.id_ubicacion
        )
            i.id_producto,
            i.id_variante,
            i.id_opcion_variante,
            i.id_presentacion,
            i.id_ubicacion,
            i.cantidad_final
        FROM inventario_filtrado i
        WHERE (v_fecha_hasta_ts IS NULL OR i.created_at <= v_fecha_hasta_ts)
        ORDER BY
            i.id_producto,
            COALESCE(i.id_variante, 0),
            COALESCE(i.id_opcion_variante, 0),
            COALESCE(i.id_presentacion, 0),
            i.id_ubicacion,
            i.created_at DESC,
            i.id DESC
    ),
    inventario_completo AS (
        SELECT
            COALESCE(ii.id_producto, ifin.id_producto) AS id_producto,
            COALESCE(ii.id_variante, ifin.id_variante) AS id_variante,
            COALESCE(ii.id_opcion_variante, ifin.id_opcion_variante) AS id_opcion_variante,
            COALESCE(ii.id_presentacion, ifin.id_presentacion) AS id_presentacion,
            COALESCE(ii.id_ubicacion, ifin.id_ubicacion) AS id_ubicacion,
            COALESCE(ii.cantidad_inicial, 0) AS cantidad_inicial,
            COALESCE(ifin.cantidad_final, 0) AS cantidad_final
        FROM inventario_inicial ii
        FULL OUTER JOIN inventario_final ifin ON (
            ii.id_producto = ifin.id_producto
            AND COALESCE(ii.id_variante, 0) = COALESCE(ifin.id_variante, 0)
            AND COALESCE(ii.id_opcion_variante, 0) = COALESCE(ifin.id_opcion_variante, 0)
            AND COALESCE(ii.id_presentacion, 0) = COALESCE(ifin.id_presentacion, 0)
            AND ii.id_ubicacion = ifin.id_ubicacion
        )
    ),
    -- Reconstruir id_operación desde cada línea de detalle vinculada
    movimientos_con_operacion AS (
        SELECT
            i.id_producto,
            i.id_variante,
            i.id_opcion_variante,
            i.id_presentacion,
            i.id_ubicacion,
            i.origen_cambio,
            i.cantidad_inicial,
            i.cantidad_final,
            COALESCE(rp.id_operacion, ep.id_operacion, cp.id_operacion, cvp.id_operacion, ai.id_operacion) AS id_operacion
        FROM inventario_filtrado i
        LEFT JOIN app_dat_recepcion_productos rp ON rp.id = i.id_recepcion
        LEFT JOIN app_dat_extraccion_productos ep ON ep.id = i.id_extraccion
        LEFT JOIN app_dat_control_productos cp ON cp.id = i.id_control
        LEFT JOIN app_dat_conversion_presentacion cvp ON cvp.id = i.id_conversion
        LEFT JOIN app_dat_ajuste_inventario ai ON ai.id_control = i.id_control
        WHERE (v_fecha_desde_ts IS NULL OR i.created_at >= v_fecha_desde_ts)
          AND (v_fecha_hasta_ts IS NULL OR i.created_at <= v_fecha_hasta_ts)
          AND COALESCE(rp.id_operacion, ep.id_operacion, cp.id_operacion, cvp.id_operacion, ai.id_operacion) IS NOT NULL
    ),
    ultimo_estado_operacion AS (
        SELECT DISTINCT ON (eo.id_operacion)
            eo.id_operacion,
            eo.estado
        FROM app_dat_estado_operacion eo
        ORDER BY eo.id_operacion, eo.created_at DESC, eo.id DESC
    ),
    movimientos_con_tipo AS (
        SELECT
            mco.*,
            o.id_tipo_operacion,
            nt.denominacion AS tipo_operacion,
            nt.accion,
            COALESCE(ueo.estado, 0) AS estado_actual,
            EXISTS (
                SELECT 1 FROM app_dat_operacion_venta ov WHERE ov.id_operacion = o.id
            ) AS es_venta
        FROM movimientos_con_operacion mco
        INNER JOIN app_dat_operaciones o ON o.id = mco.id_operacion
        INNER JOIN app_nom_tipo_operacion nt ON nt.id = o.id_tipo_operacion
        LEFT JOIN ultimo_estado_operacion ueo ON ueo.id_operacion = o.id
        WHERE (v_fecha_desde_ts IS NULL OR o.created_at >= v_fecha_desde_ts)
          AND (v_fecha_hasta_ts IS NULL OR o.created_at <= v_fecha_hasta_ts)
    ),
    -- Entradas completadas
    entradas_agg AS (
        SELECT
            mco.id_producto,
            COALESCE(mco.id_variante, 0) AS id_variante,
            COALESCE(mco.id_opcion_variante, 0) AS id_opcion_variante,
            COALESCE(mco.id_presentacion, 0) AS id_presentacion,
            mco.id_ubicacion,
            SUM(mco.cantidad_final - mco.cantidad_inicial) AS cantidad_entradas
        FROM movimientos_con_tipo mco
        WHERE mco.id_tipo_operacion IN (1, 3, 5, 8, 11)
          AND NOT mco.es_venta
          AND mco.estado_actual = 2
        GROUP BY
            mco.id_producto,
            COALESCE(mco.id_variante, 0),
            COALESCE(mco.id_opcion_variante, 0),
            COALESCE(mco.id_presentacion, 0),
            mco.id_ubicacion
    ),
    -- Extracciones completadas (tipo 18)
    extracciones_agg AS (
        SELECT
            mco.id_producto,
            COALESCE(mco.id_variante, 0) AS id_variante,
            COALESCE(mco.id_opcion_variante, 0) AS id_opcion_variante,
            COALESCE(mco.id_presentacion, 0) AS id_presentacion,
            mco.id_ubicacion,
            SUM(mco.cantidad_inicial - mco.cantidad_final) AS cantidad_extracciones
        FROM movimientos_con_tipo mco
        WHERE mco.id_tipo_operacion = 18
          AND NOT mco.es_venta
          AND mco.estado_actual = 2
        GROUP BY
            mco.id_producto,
            COALESCE(mco.id_variante, 0),
            COALESCE(mco.id_opcion_variante, 0),
            COALESCE(mco.id_presentacion, 0),
            mco.id_ubicacion
    ),
    -- Ventas completadas (tipo 2) en estados completados
    ventas_agg AS (
        SELECT
            mco.id_producto,
            COALESCE(mco.id_variante, 0) AS id_variante,
            COALESCE(mco.id_opcion_variante, 0) AS id_opcion_variante,
            COALESCE(mco.id_presentacion, 0) AS id_presentacion,
            mco.id_ubicacion,
            SUM(mco.cantidad_inicial - mco.cantidad_final) AS cantidad_ventas
        FROM movimientos_con_tipo mco
        WHERE mco.es_venta
          AND mco.estado_actual IN (2, 10, 12)
        GROUP BY
            mco.id_producto,
            COALESCE(mco.id_variante, 0),
            COALESCE(mco.id_opcion_variante, 0),
            COALESCE(mco.id_presentacion, 0),
            mco.id_ubicacion
    ),
    -- Operaciones pendientes de salida: ventas, extracciones, transferencias, etc.
    pendiente_salida AS (
        SELECT
            ep.id_producto,
            COALESCE(ep.id_variante, 0) AS id_variante,
            COALESCE(ep.id_opcion_variante, 0) AS id_opcion_variante,
            COALESCE(ep.id_presentacion, 0) AS id_presentacion,
            ep.id_ubicacion,
            SUM(ep.cantidad) AS cantidad_pendiente
        FROM app_dat_extraccion_productos ep
        INNER JOIN app_dat_operaciones o ON o.id = ep.id_operacion
        INNER JOIN app_nom_tipo_operacion nt ON nt.id = o.id_tipo_operacion
        INNER JOIN ultimo_estado_operacion ueo ON ueo.id_operacion = o.id
        WHERE ueo.estado = 1
          AND nt.accion = 'salida'
          AND (v_fecha_desde_ts IS NULL OR o.created_at >= v_fecha_desde_ts)
          AND (v_fecha_hasta_ts IS NULL OR o.created_at <= v_fecha_hasta_ts)
          AND EXISTS (
              SELECT 1 FROM productos_base pb WHERE pb.id = ep.id_producto
          )
          AND EXISTS (
              SELECT 1 FROM ubicaciones_filtro uf WHERE uf.id_ubicacion = ep.id_ubicacion
          )
        GROUP BY
            ep.id_producto,
            COALESCE(ep.id_variante, 0),
            COALESCE(ep.id_opcion_variante, 0),
            COALESCE(ep.id_presentacion, 0),
            ep.id_ubicacion
    ),
    presentaciones_nombres AS (
        SELECT
            pp.id_producto,
            pp.id AS id_presentacion,
            np.denominacion AS nombre_presentacion
        FROM app_dat_producto_presentacion pp
        INNER JOIN app_nom_presentacion np ON np.id = pp.id_presentacion
        WHERE EXISTS (SELECT 1 FROM productos_base pb WHERE pb.id = pp.id_producto)
    ),
    precios_vigentes AS (
        SELECT DISTINCT ON (pv.id_producto)
            pv.id_producto,
            pv.precio_venta_cup
        FROM app_dat_precio_venta pv
        WHERE (pv.id_variante IS NULL OR pv.id_variante = 0)
          AND (pv.fecha_hasta IS NULL OR pv.fecha_hasta >= CURRENT_DATE)
        ORDER BY pv.id_producto, pv.fecha_desde DESC, pv.created_at DESC
    )
    SELECT
        uf.id_almacen,
        uf.almacen::TEXT,
        ic.id_ubicacion,
        uf.ubicacion::TEXT,
        pb.id,
        pb.nombre_producto_base::TEXT,
        pb.codigo::TEXT,
        pb.categoria::TEXT,
        pb.sku::TEXT,
        (pb.sku)::TEXT AS sku_producto,
        pb.id_categoria,
        pb.nombre_comercial::TEXT,
        pb.denominacion_corta::TEXT,
        pb.descripcion::TEXT,
        pb.descripcion_corta::TEXT,
        pb.um::TEXT,
        pb.es_refrigerado,
        pb.es_fragil,
        pb.es_peligroso,
        pb.es_vendible,
        pb.es_comprable,
        pb.es_inventariable,
        pb.es_por_lotes,
        pb.dias_alert_caducidad,
        pb.producto_created_at::TIMESTAMP,
        pb.imagen::TEXT,
        pb.es_elaborado,
        pb.es_servicio,
        pb.deleted_at::TIMESTAMP,
        ic.id_presentacion,
        COALESCE(pn.nombre_presentacion, 'Presentación ' || ic.id_presentacion)::TEXT AS presentacion,
        ic.id_variante,
        ic.id_opcion_variante,
        ic.cantidad_inicial,
        COALESCE(ea.cantidad_entradas, 0) AS entradas_periodo,
        COALESCE(xa.cantidad_extracciones, 0) AS extracciones_periodo,
        COALESCE(va.cantidad_ventas, 0) AS ventas_periodo,
        COALESCE(ps.cantidad_pendiente, 0) AS cantidad_reservada,
        ic.cantidad_final,
        TRUE AS tiene_inventario,
        COALESCE(pv.precio_venta_cup, 0) AS precio_venta
    FROM inventario_completo ic
    INNER JOIN productos_base pb ON pb.id = ic.id_producto
    INNER JOIN ubicaciones_filtro uf ON uf.id_ubicacion = ic.id_ubicacion
    LEFT JOIN entradas_agg ea ON
        ea.id_producto = ic.id_producto
        AND ea.id_variante = COALESCE(ic.id_variante, 0)
        AND ea.id_opcion_variante = COALESCE(ic.id_opcion_variante, 0)
        AND ea.id_presentacion = COALESCE(ic.id_presentacion, 0)
        AND ea.id_ubicacion = ic.id_ubicacion
    LEFT JOIN extracciones_agg xa ON
        xa.id_producto = ic.id_producto
        AND xa.id_variante = COALESCE(ic.id_variante, 0)
        AND xa.id_opcion_variante = COALESCE(ic.id_opcion_variante, 0)
        AND xa.id_presentacion = COALESCE(ic.id_presentacion, 0)
        AND xa.id_ubicacion = ic.id_ubicacion
    LEFT JOIN ventas_agg va ON
        va.id_producto = ic.id_producto
        AND va.id_variante = COALESCE(ic.id_variante, 0)
        AND va.id_opcion_variante = COALESCE(ic.id_opcion_variante, 0)
        AND va.id_presentacion = COALESCE(ic.id_presentacion, 0)
        AND va.id_ubicacion = ic.id_ubicacion
    LEFT JOIN pendiente_salida ps ON
        ps.id_producto = ic.id_producto
        AND ps.id_variante = COALESCE(ic.id_variante, 0)
        AND ps.id_opcion_variante = COALESCE(ic.id_opcion_variante, 0)
        AND ps.id_presentacion = COALESCE(ic.id_presentacion, 0)
        AND ps.id_ubicacion = ic.id_ubicacion
    LEFT JOIN presentaciones_nombres pn ON
        pn.id_producto = ic.id_producto AND pn.id_presentacion = ic.id_presentacion
    LEFT JOIN precios_vigentes pv ON pv.id_producto = ic.id_producto
    WHERE p_include_zero = TRUE OR ic.cantidad_final <> 0
    ORDER BY uf.almacen, uf.ubicacion, pb.nombre_producto_base, ic.id_presentacion;
END;
$$;

GRANT EXECUTE ON FUNCTION public.obtener_reporte_inventario_export(BIGINT, TEXT, TEXT, BIGINT, BOOLEAN, BOOLEAN) TO authenticated;
