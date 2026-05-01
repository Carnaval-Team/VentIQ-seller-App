DROP FUNCTION IF EXISTS fn_listar_operaciones_inventario_new(bigint,bigint,bigint,smallint[],date,date,uuid,text,integer,integer);

CREATE OR REPLACE FUNCTION fn_listar_operaciones_inventario_new(
    p_id_tienda           BIGINT    DEFAULT NULL,
    p_id_tpv              BIGINT    DEFAULT NULL,
    p_id_tipo_operacion   BIGINT    DEFAULT NULL,
    p_estados             SMALLINT[] DEFAULT NULL,
    p_fecha_desde         DATE      DEFAULT NULL,
    p_fecha_hasta         DATE      DEFAULT NULL,
    p_uuid_usuario_operador UUID    DEFAULT NULL,
    p_busqueda            TEXT      DEFAULT NULL,
    p_limite              INTEGER   DEFAULT 20,
    p_pagina              INTEGER   DEFAULT 1
)
RETURNS TABLE (
    id                   BIGINT,
    tipo_operacion_nombre TEXT,
    tipo_operacion_accion TEXT,
    id_tienda            BIGINT,
    tienda_nombre        TEXT,
    id_tpv               BIGINT,
    tpv_nombre           TEXT,
    uuid                 UUID,
    usuario_nombre       TEXT,
    estado               SMALLINT,
    estado_nombre        TEXT,
    created_at           TIMESTAMPTZ,
    total                NUMERIC,
    cantidad_items       INTEGER,
    observaciones        TEXT,
    detalles             JSONB,
    total_count          BIGINT
)

LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_offset INTEGER := (p_pagina - 1) * p_limite;
BEGIN
    RETURN QUERY
    WITH
    -- IDs que deben excluirse del listado independiente de extracciones/recepciones:
    -- hijos de transferencias + operaciones que ya son ventas (las ventas también registran extracción)
    op_children AS (
        SELECT id_extraccion AS op_id FROM app_dat_operacion_transferencia WHERE id_extraccion IS NOT NULL
        UNION ALL
        SELECT id_recepcion  AS op_id FROM app_dat_operacion_transferencia WHERE id_recepcion  IS NOT NULL
        UNION ALL
        SELECT id_operacion  AS op_id FROM app_dat_operacion_venta
    ),
    -- Último estado de cada operación
    ultimo_estado AS (
        SELECT DISTINCT ON (e.id_operacion) e.id_operacion, e.estado
        FROM app_dat_estado_operacion e
        ORDER BY e.id_operacion, e.id DESC
    ),
    -- Tiendas accesibles para el usuario actual
    accesos AS (
        SELECT g.id_tienda  FROM app_dat_gerente    g   WHERE g.uuid  = auth.uid()
        UNION
        SELECT s.id_tienda  FROM app_dat_supervisor  s   WHERE s.uuid  = auth.uid()
        UNION
        SELECT aud.id_tienda FROM auditor            aud WHERE aud.uuid = auth.uid()
        UNION
        SELECT a.id_tienda  FROM app_dat_almacenero  al
                             JOIN app_dat_almacen    a  ON al.id_almacen = a.id
                             WHERE al.uuid = auth.uid()
        UNION
        SELECT tpv.id_tienda FROM app_dat_vendedor   v
                              JOIN app_dat_tpv       tpv ON v.id_tpv = tpv.id
                              WHERE v.uuid = auth.uid()
    ),
    -- ══════════════════════════════════════════════════════════════════════════
    todas_ops AS (

        -- ── 1. VENTAS ────────────────────────────────────────────────────────
        SELECT
            o.id                                                AS op_id,
            top.denominacion                                    AS tipo_nombre,
            top.accion                                          AS tipo_accion,
            o.id_tienda,
            t.denominacion                                      AS tienda_nom,
            ov.id_tpv                                           AS tpv_id,
            tpv.denominacion                                    AS tpv_nom,
            o.uuid,
            ue.estado,
            neo.denominacion                                    AS estado_nom,
            o.created_at,
            o.observaciones,
            COALESCE(ov.importe_total, 0)::NUMERIC              AS total_op,
            (SELECT COUNT(*)::INTEGER FROM app_dat_extraccion_productos ep
             WHERE ep.id_operacion = o.id)                      AS items_count,
            jsonb_build_object(
                'id_tpv',         ov.id_tpv,
                'tpv_nombre',     tpv.denominacion,
                'total',          ov.importe_total,
                'id_cliente',     ov.id_cliente,
                'nombre_cliente', c.nombre_completo
            )                                                   AS det_esp,
            (SELECT jsonb_agg(jsonb_build_object(
                 'id_producto',    ep.id_producto,
                 'producto_nombre', COALESCE(p.denominacion, 'Producto no encontrado'),
                 'sku_producto',   p.sku,
                 'cantidad',       ep.cantidad,
                 'precio_unitario', ep.precio_unitario,
                 'importe',        COALESCE(ep.importe, ep.precio_unitario * ep.cantidad)
             ))
             FROM app_dat_extraccion_productos ep
             LEFT JOIN app_dat_producto p ON ep.id_producto = p.id
             WHERE ep.id_operacion = o.id
             LIMIT 100)                                         AS det_items
        FROM app_dat_operacion_venta        ov
        JOIN app_dat_operaciones            o   ON ov.id_operacion    = o.id
        JOIN app_nom_tipo_operacion         top ON o.id_tipo_operacion = top.id
        JOIN app_dat_tienda                 t   ON o.id_tienda        = t.id
        LEFT JOIN app_dat_tpv               tpv ON ov.id_tpv          = tpv.id
        LEFT JOIN app_dat_clientes          c   ON ov.id_cliente       = c.id
        LEFT JOIN ultimo_estado             ue  ON o.id = ue.id_operacion
        LEFT JOIN app_nom_estado_operacion  neo ON ue.estado = neo.id
        WHERE (p_id_tienda            IS NULL OR o.id_tienda          = p_id_tienda)
          AND (p_id_tpv               IS NULL OR ov.id_tpv            = p_id_tpv)
          AND (p_id_tipo_operacion    IS NULL OR o.id_tipo_operacion  = p_id_tipo_operacion)
          AND (p_estados              IS NULL OR ue.estado            = ANY(p_estados))
          AND (p_fecha_desde          IS NULL OR o.created_at::DATE   >= p_fecha_desde)
          AND (p_fecha_hasta          IS NULL OR o.created_at::DATE   <= p_fecha_hasta)
          AND (p_uuid_usuario_operador IS NULL OR o.uuid              = p_uuid_usuario_operador)
          AND (p_busqueda IS NULL
               OR o.id::TEXT         ILIKE '%' || p_busqueda || '%'
               OR top.denominacion   ILIKE '%' || p_busqueda || '%'
               OR t.denominacion     ILIKE '%' || p_busqueda || '%'
               OR c.nombre_completo  ILIKE '%' || p_busqueda || '%'
               OR o.observaciones    ILIKE '%' || p_busqueda || '%')
          AND o.id_tienda IN (SELECT ac.id_tienda FROM accesos ac)

        UNION ALL

        -- ── 2. TRANSFERENCIAS ─────────────────────────────────────────────────
        SELECT
            o.id,
            top.denominacion,
            top.accion,
            o.id_tienda,
            t.denominacion,
            NULL::BIGINT,
            NULL::TEXT,
            o.uuid,
            -- Estado derivado de los hijos: extraccion completada + recepcion completada = Completada
            CASE
                WHEN neo_ext.denominacion ILIKE '%complet%' AND neo_rec.denominacion ILIKE '%complet%'
                    THEN ue_rec.estado
                WHEN neo_ext.denominacion ILIKE '%complet%'
                    THEN ue_ext.estado
                ELSE ue.estado
            END AS estado,
            CASE
                WHEN neo_ext.denominacion ILIKE '%complet%' AND neo_rec.denominacion ILIKE '%complet%'
                    THEN COALESCE(neo_rec.denominacion, 'Completada')
                WHEN neo_ext.denominacion ILIKE '%complet%'
                    THEN 'En camino'
                ELSE COALESCE(neo.denominacion, 'Sin estado')
            END AS estado_nom,
            o.created_at,
            o.observaciones,
            COALESCE((SELECT SUM(ep.precio_unitario * ep.cantidad)
                      FROM app_dat_extraccion_productos ep
                      WHERE ep.id_operacion = ot.id_extraccion), 0)::NUMERIC,
            COALESCE((SELECT COUNT(*)::INTEGER
                      FROM app_dat_extraccion_productos ep
                      WHERE ep.id_operacion = ot.id_extraccion), 0),
            jsonb_build_object(
                'autorizado_por', ot.autorizado_por,
                'id_extraccion',  ot.id_extraccion,
                'id_recepcion',   ot.id_recepcion,
                -- Origen: ALMACEN - ZONA de la extracción hija
                'origen', (
                    SELECT al.denominacion || ' - ' || la.denominacion
                    FROM app_dat_extraccion_productos ep_loc
                    JOIN app_dat_layout_almacen la ON ep_loc.id_ubicacion = la.id
                    JOIN app_dat_almacen al         ON la.id_almacen      = al.id
                    WHERE ep_loc.id_operacion = ot.id_extraccion
                    LIMIT 1
                ),
                -- Destino: ALMACEN - ZONA de la recepción hija
                'destino', (
                    SELECT al.denominacion || ' - ' || la.denominacion
                    FROM app_dat_recepcion_productos rp_loc
                    JOIN app_dat_layout_almacen la ON rp_loc.id_ubicacion = la.id
                    JOIN app_dat_almacen al         ON la.id_almacen      = al.id
                    WHERE rp_loc.id_operacion = ot.id_recepcion
                    LIMIT 1
                ),
                'estado_extraccion', COALESCE(neo_ext.denominacion, 'Sin estado'),
                'estado_recepcion',  COALESCE(neo_rec.denominacion, 'Sin estado'),
                'extraccion', jsonb_build_object('items', COALESCE((
                    SELECT jsonb_agg(jsonb_build_object(
                        'id_producto',    ep.id_producto,
                        'producto_nombre', COALESCE(p.denominacion, 'Producto no encontrado'),
                        'sku_producto',   p.sku,
                        'cantidad',       ep.cantidad,
                        'precio_unitario', ep.precio_unitario,
                        'importe',        COALESCE(ep.importe, ep.precio_unitario * ep.cantidad)
                    ))
                    FROM app_dat_extraccion_productos ep
                    LEFT JOIN app_dat_producto p ON ep.id_producto = p.id
                    WHERE ep.id_operacion = ot.id_extraccion LIMIT 100
                ), '[]'::jsonb)),
                'recepcion', jsonb_build_object('items', COALESCE((
                    SELECT jsonb_agg(jsonb_build_object(
                        'id_producto',    rp.id_producto,
                        'producto_nombre', COALESCE(p.denominacion, 'Producto no encontrado'),
                        'sku_producto',   p.sku,
                        'cantidad',       rp.cantidad,
                        'precio_unitario', rp.precio_unitario
                    ))
                    FROM app_dat_recepcion_productos rp
                    LEFT JOIN app_dat_producto p ON rp.id_producto = p.id
                    WHERE rp.id_operacion = ot.id_recepcion LIMIT 100
                ), '[]'::jsonb))
            ),
            COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                    'id_producto',    ep.id_producto,
                    'producto_nombre', COALESCE(p.denominacion, 'Producto no encontrado'),
                    'sku_producto',   p.sku,
                    'cantidad',       ep.cantidad,
                    'precio_unitario', ep.precio_unitario,
                    'importe',        COALESCE(ep.importe, ep.precio_unitario * ep.cantidad)
                ))
                FROM app_dat_extraccion_productos ep
                LEFT JOIN app_dat_producto p ON ep.id_producto = p.id
                WHERE ep.id_operacion = ot.id_extraccion LIMIT 100
            ), '[]'::jsonb)
        FROM app_dat_operacion_transferencia ot
        JOIN app_dat_operaciones             o   ON ot.id_operacion    = o.id
        JOIN app_nom_tipo_operacion          top ON o.id_tipo_operacion = top.id
        JOIN app_dat_tienda                  t   ON o.id_tienda        = t.id
        LEFT JOIN ultimo_estado              ue     ON o.id              = ue.id_operacion
        LEFT JOIN app_nom_estado_operacion   neo    ON ue.estado         = neo.id
        -- Estados de las operaciones hijo
        LEFT JOIN ultimo_estado              ue_ext ON ot.id_extraccion  = ue_ext.id_operacion
        LEFT JOIN app_nom_estado_operacion   neo_ext ON ue_ext.estado    = neo_ext.id
        LEFT JOIN ultimo_estado              ue_rec ON ot.id_recepcion   = ue_rec.id_operacion
        LEFT JOIN app_nom_estado_operacion   neo_rec ON ue_rec.estado    = neo_rec.id
        WHERE p_id_tpv IS NULL
          AND (p_id_tienda            IS NULL OR o.id_tienda          = p_id_tienda)
          AND (p_id_tipo_operacion    IS NULL OR o.id_tipo_operacion  = p_id_tipo_operacion)
          AND (p_estados              IS NULL OR ue.estado            = ANY(p_estados))
          AND (p_fecha_desde          IS NULL OR o.created_at::DATE   >= p_fecha_desde)
          AND (p_fecha_hasta          IS NULL OR o.created_at::DATE   <= p_fecha_hasta)
          AND (p_uuid_usuario_operador IS NULL OR o.uuid              = p_uuid_usuario_operador)
          AND (p_busqueda IS NULL
               OR o.id::TEXT         ILIKE '%' || p_busqueda || '%'
               OR top.denominacion   ILIKE '%' || p_busqueda || '%'
               OR t.denominacion     ILIKE '%' || p_busqueda || '%'
               OR o.observaciones    ILIKE '%' || p_busqueda || '%')
          AND o.id_tienda IN (SELECT ac.id_tienda FROM accesos ac)

        UNION ALL

        -- ── 3. EXTRACCIONES INDEPENDIENTES (no vinculadas a ninguna transferencia)
        SELECT
            o.id,
            top.denominacion,
            top.accion,
            o.id_tienda,
            t.denominacion,
            NULL::BIGINT,
            NULL::TEXT,
            o.uuid,
            ue.estado,
            neo.denominacion,
            o.created_at,
            o.observaciones,
            COALESCE((SELECT SUM(ep.precio_unitario * ep.cantidad)
                      FROM app_dat_extraccion_productos ep
                      WHERE ep.id_operacion = o.id), 0)::NUMERIC,
            COALESCE((SELECT COUNT(*)::INTEGER
                      FROM app_dat_extraccion_productos ep
                      WHERE ep.id_operacion = o.id), 0),
            jsonb_build_object(
                'motivo',         nme.denominacion,
                'observaciones',  oe.observaciones,
                'autorizado_por', oe.autorizado_por
            ),
            (SELECT jsonb_agg(jsonb_build_object(
                 'id_producto',    ep.id_producto,
                 'producto_nombre', COALESCE(p.denominacion, 'Producto no encontrado'),
                 'sku_producto',   p.sku,
                 'cantidad',       ep.cantidad,
                 'precio_unitario', ep.precio_unitario,
                 'importe',        COALESCE(ep.importe, ep.precio_unitario * ep.cantidad)
             ))
             FROM app_dat_extraccion_productos ep
             LEFT JOIN app_dat_producto p ON ep.id_producto = p.id
             WHERE ep.id_operacion = o.id
             LIMIT 100)
        FROM app_dat_operacion_extraccion   oe
        JOIN app_dat_operaciones            o   ON oe.id_operacion    = o.id
        JOIN app_nom_tipo_operacion         top ON o.id_tipo_operacion = top.id
        JOIN app_dat_tienda                 t   ON o.id_tienda        = t.id
        LEFT JOIN app_nom_motivo_extraccion nme ON oe.id_motivo_operacion = nme.id
        LEFT JOIN ultimo_estado             ue  ON o.id = ue.id_operacion
        LEFT JOIN app_nom_estado_operacion  neo ON ue.estado = neo.id
        WHERE oe.id_operacion NOT IN (SELECT op_id FROM op_children)
          AND p_id_tpv IS NULL
          AND (p_id_tienda            IS NULL OR o.id_tienda          = p_id_tienda)
          AND (p_id_tipo_operacion    IS NULL OR o.id_tipo_operacion  = p_id_tipo_operacion)
          AND (p_estados              IS NULL OR ue.estado            = ANY(p_estados))
          AND (p_fecha_desde          IS NULL OR o.created_at::DATE   >= p_fecha_desde)
          AND (p_fecha_hasta          IS NULL OR o.created_at::DATE   <= p_fecha_hasta)
          AND (p_uuid_usuario_operador IS NULL OR o.uuid              = p_uuid_usuario_operador)
          AND (p_busqueda IS NULL
               OR o.id::TEXT         ILIKE '%' || p_busqueda || '%'
               OR top.denominacion   ILIKE '%' || p_busqueda || '%'
               OR t.denominacion     ILIKE '%' || p_busqueda || '%'
               OR o.observaciones    ILIKE '%' || p_busqueda || '%')
          AND o.id_tienda IN (SELECT ac.id_tienda FROM accesos ac)

        UNION ALL

        -- ── 4. RECEPCIONES INDEPENDIENTES (no vinculadas a ninguna transferencia)
        SELECT
            o.id,
            top.denominacion,
            top.accion,
            o.id_tienda,
            t.denominacion,
            NULL::BIGINT,
            NULL::TEXT,
            o.uuid,
            ue.estado,
            neo.denominacion,
            o.created_at,
            o.observaciones,
            COALESCE(orec.monto_total, 0)::NUMERIC,
            COALESCE((SELECT COUNT(*)::INTEGER
                      FROM app_dat_recepcion_productos rp
                      WHERE rp.id_operacion = o.id), 0),
            jsonb_build_object(
                'entregado_por', orec.entregado_por,
                'recibido_por',  orec.recibido_por,
                'monto_total',   orec.monto_total
            ),
            (SELECT jsonb_agg(jsonb_build_object(
                 'id_producto',    rp.id_producto,
                 'producto_nombre', COALESCE(p.denominacion, 'Producto no encontrado'),
                 'sku_producto',   p.sku,
                 'cantidad',       rp.cantidad,
                 'precio_unitario', rp.precio_unitario
             ))
             FROM app_dat_recepcion_productos rp
             LEFT JOIN app_dat_producto p ON rp.id_producto = p.id
             WHERE rp.id_operacion = o.id
             LIMIT 100)
        FROM app_dat_operacion_recepcion    orec
        JOIN app_dat_operaciones            o   ON orec.id_operacion  = o.id
        JOIN app_nom_tipo_operacion         top ON o.id_tipo_operacion = top.id
        JOIN app_dat_tienda                 t   ON o.id_tienda        = t.id
        LEFT JOIN ultimo_estado             ue  ON o.id = ue.id_operacion
        LEFT JOIN app_nom_estado_operacion  neo ON ue.estado = neo.id
        WHERE orec.id_operacion NOT IN (SELECT op_id FROM op_children)
          AND p_id_tpv IS NULL
          AND (p_id_tienda            IS NULL OR o.id_tienda          = p_id_tienda)
          AND (p_id_tipo_operacion    IS NULL OR o.id_tipo_operacion  = p_id_tipo_operacion)
          AND (p_estados              IS NULL OR ue.estado            = ANY(p_estados))
          AND (p_fecha_desde          IS NULL OR o.created_at::DATE   >= p_fecha_desde)
          AND (p_fecha_hasta          IS NULL OR o.created_at::DATE   <= p_fecha_hasta)
          AND (p_uuid_usuario_operador IS NULL OR o.uuid              = p_uuid_usuario_operador)
          AND (p_busqueda IS NULL
               OR o.id::TEXT         ILIKE '%' || p_busqueda || '%'
               OR top.denominacion   ILIKE '%' || p_busqueda || '%'
               OR t.denominacion     ILIKE '%' || p_busqueda || '%'
               OR o.observaciones    ILIKE '%' || p_busqueda || '%')
          AND o.id_tienda IN (SELECT ac.id_tienda FROM accesos ac)
    )
    -- ── Proyección final con nombre de usuario y paginación ───────────────────
    SELECT
        ops.op_id::BIGINT,
        ops.tipo_nombre::TEXT,
        ops.tipo_accion::TEXT,
        ops.id_tienda::BIGINT,
        ops.tienda_nom::TEXT,
        ops.tpv_id::BIGINT,
        ops.tpv_nom::TEXT,
        ops.uuid::UUID,
        COALESCE(
            (SELECT tr.nombres || ' ' || tr.apellidos
             FROM app_dat_trabajadores tr
             WHERE tr.id = (
                 SELECT rol.id_trabajador FROM (
                     SELECT v.id_trabajador FROM app_dat_vendedor   v  WHERE v.uuid  = ops.uuid
                     UNION
                     SELECT s.id_trabajador FROM app_dat_supervisor s  WHERE s.uuid  = ops.uuid
                     UNION
                     SELECT g.id_trabajador FROM app_dat_gerente    g  WHERE g.uuid  = ops.uuid
                     UNION
                     SELECT al.id_trabajador FROM app_dat_almacenero al WHERE al.uuid = ops.uuid
                 ) rol LIMIT 1
             )),
            ops.uuid::TEXT
        )::TEXT,
        ops.estado::SMALLINT,
        COALESCE(ops.estado_nom, 'Sin estado')::TEXT,
        ops.created_at::TIMESTAMPTZ,
        ops.total_op::NUMERIC,
        ops.items_count::INTEGER,
        ops.observaciones::TEXT,
        jsonb_build_object(
            'detalles_especificos', ops.det_esp,
            'items', COALESCE(ops.det_items, '[]'::jsonb)
        )::JSONB,
        COUNT(*) OVER()::BIGINT
    FROM todas_ops ops
    ORDER BY ops.created_at DESC
    LIMIT  p_limite
    OFFSET v_offset;
END;
$$;
