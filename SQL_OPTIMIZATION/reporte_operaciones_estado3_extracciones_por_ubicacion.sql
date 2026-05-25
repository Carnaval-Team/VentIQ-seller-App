-- =============================================================================
-- VERSIÓN RÁPIDA (copiar y ejecutar en Supabase)
-- =============================================================================
/*
WITH params AS (
    SELECT
        '57389782-8a5b-437a-9193-0249f845c74e'::uuid AS p_uuid_usuario,
        TIMESTAMPTZ '2026-05-20 00:00:00-04:00'     AS p_fecha_desde,
        TIMESTAMPTZ '2026-05-20 11:59:59-04:00'     AS p_fecha_hasta
),
-- Estado real = último registro en app_dat_estado_operacion por MAX(id), no por fecha.
ultimo_estado AS (
    SELECT
        eo.id_operacion,
        eo.id              AS id_estado_operacion,
        eo.estado,
        neo.denominacion   AS estado_nombre,
        eo.created_at      AS fecha_ultimo_estado
    FROM app_dat_estado_operacion eo
    INNER JOIN (
        SELECT id_operacion, MAX(id) AS max_id_estado
        FROM app_dat_estado_operacion
        GROUP BY id_operacion
    ) ult ON ult.id_operacion = eo.id_operacion
         AND ult.max_id_estado = eo.id
    LEFT JOIN app_nom_estado_operacion neo ON neo.id = eo.estado
),
operaciones_filtradas AS (
    SELECT
        op.id AS id_operacion,
        t.denominacion AS tienda_nombre,
        nto.denominacion AS tipo_operacion,
        op.created_at AS fecha_operacion,
        ue.id_estado_operacion,
        ue.estado AS ultimo_estado_id,
        ue.estado_nombre AS ultimo_estado_nombre,
        ue.fecha_ultimo_estado
    FROM app_dat_operaciones op
    CROSS JOIN params p
    INNER JOIN ultimo_estado ue ON ue.id_operacion = op.id
    LEFT JOIN app_nom_tipo_operacion nto ON nto.id = op.id_tipo_operacion
    LEFT JOIN app_dat_tienda t ON t.id = op.id_tienda
    WHERE ue.estado = 3
      AND ue.fecha_ultimo_estado BETWEEN p.p_fecha_desde AND p.p_fecha_hasta
      AND op.uuid = p.p_uuid_usuario
)
SELECT
    of.id_operacion,
    of.tienda_nombre,
    of.tipo_operacion,
    of.fecha_operacion,
    of.id_estado_operacion,
    of.ultimo_estado_nombre,
    of.fecha_ultimo_estado,
    alm.denominacion AS almacen_nombre,
    COALESCE(zona.denominacion, la.denominacion) AS zona_nombre,
    la.denominacion AS ubicacion_nombre,
    p.denominacion AS producto_nombre,
    ep.cantidad,
    ep.precio_unitario,
    ep.importe,
    ep.importe_real
FROM operaciones_filtradas of
INNER JOIN app_dat_extraccion_productos ep ON ep.id_operacion = of.id_operacion
INNER JOIN app_dat_producto p ON p.id = ep.id_producto
LEFT JOIN app_dat_layout_almacen la ON la.id = ep.id_ubicacion
LEFT JOIN app_dat_layout_almacen zona ON zona.id = la.id_layout_padre
LEFT JOIN app_dat_almacen alm ON alm.id = la.id_almacen
ORDER BY of.tienda_nombre, almacen_nombre, zona_nombre, of.id_operacion;
*/

-- =============================================================================
-- Reporte: operaciones cuyo ÚLTIMO estado = 3, ese estado creado en un rango,
--           de un usuario; detalle de productos extraídos por orden,
--           desglosado por tienda, almacén y zona (layout).
--
-- Parámetros de ejemplo (ajusta zona horaria si aplica):
--   Usuario : 57389782-8a5b-437a-9193-0249f845c74e
--   Rango   : 2026-05-20 00:00:00 → 2026-05-20 11:59:59 (America/Havana)
--
-- Regla de negocio: el estado REAL de una operación es el último registro en
-- app_dat_estado_operacion ordenado por id DESC (equivalente a MAX(id) por operación).
-- Los filtros (estado = 3, rango de fechas) se aplican SOLO sobre ese último registro.
--
-- Nota: estado = 3 según app_nom_estado_operacion (verificar denominación en tu BD).
-- En ventas, los ítems salen de app_dat_extraccion_productos con el mismo id_operacion.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) DETALLE: una fila por producto extraído en cada operación filtrada
-- ─────────────────────────────────────────────────────────────────────────────
WITH params AS (
    SELECT
        '57389782-8a5b-437a-9193-0249f845c74e'::uuid AS p_uuid_usuario,
        TIMESTAMPTZ '2026-05-20 00:00:00-04:00'     AS p_fecha_desde,  -- 20-05-2026 inicio
        TIMESTAMPTZ '2026-05-20 11:59:59-04:00'     AS p_fecha_hasta   -- 20-05-2026 11:59:59
),
ultimo_estado AS (
    SELECT
        eo.id_operacion,
        eo.id              AS id_estado_operacion,
        eo.estado,
        neo.denominacion   AS estado_nombre,
        eo.created_at      AS fecha_ultimo_estado,
        eo.uuid            AS uuid_estado,
        eo.comentario
    FROM app_dat_estado_operacion eo
    INNER JOIN (
        SELECT id_operacion, MAX(id) AS max_id_estado
        FROM app_dat_estado_operacion
        GROUP BY id_operacion
    ) ult ON ult.id_operacion = eo.id_operacion
         AND ult.max_id_estado = eo.id
    LEFT JOIN app_nom_estado_operacion neo ON neo.id = eo.estado
),
operaciones_filtradas AS (
    SELECT
        op.id                    AS id_operacion,
        op.id_tipo_operacion,
        nto.denominacion         AS tipo_operacion,
        op.uuid                  AS uuid_usuario,
        op.id_tienda,
        t.denominacion           AS tienda_nombre,
        op.observaciones,
        op.created_at            AS fecha_operacion,
        ue.id_estado_operacion,
        ue.estado                AS ultimo_estado_id,
        ue.estado_nombre         AS ultimo_estado_nombre,
        ue.fecha_ultimo_estado,
        ue.comentario            AS comentario_estado,
        ov.id_tpv,
        tpv.denominacion         AS tpv_nombre,
        ov.importe_total,
        ov.es_pagada,
        tr.nombres || ' ' || tr.apellidos AS vendedor_nombre
    FROM app_dat_operaciones op
    CROSS JOIN params p
    INNER JOIN ultimo_estado ue ON ue.id_operacion = op.id
    LEFT JOIN app_nom_tipo_operacion nto ON nto.id = op.id_tipo_operacion
    LEFT JOIN app_dat_tienda t ON t.id = op.id_tienda
    LEFT JOIN app_dat_operacion_venta ov ON ov.id_operacion = op.id
    LEFT JOIN app_dat_tpv tpv ON tpv.id = ov.id_tpv
    LEFT JOIN app_dat_vendedor v ON v.uuid = op.uuid
    LEFT JOIN app_dat_trabajadores tr ON tr.id = v.id_trabajador
    WHERE ue.estado = 3
      AND ue.fecha_ultimo_estado >= p.p_fecha_desde
      AND ue.fecha_ultimo_estado <= p.p_fecha_hasta
      AND op.uuid = p.p_uuid_usuario
)
SELECT
    of.id_operacion,
    of.tipo_operacion,
    of.fecha_operacion,
    of.id_estado_operacion,
    of.ultimo_estado_id,
    of.ultimo_estado_nombre,
    of.fecha_ultimo_estado,
    of.uuid_usuario,
    of.vendedor_nombre,
    of.id_tienda,
    of.tienda_nombre,
    of.id_tpv,
    of.tpv_nombre,
    of.importe_total,
    of.es_pagada,
    -- Producto / extracción
    ep.id                    AS id_extraccion,
    ep.id_producto,
    p.denominacion           AS producto_nombre,
    p.sku                    AS producto_sku,
    ep.cantidad,
    ep.precio_unitario,
    ep.importe,
    ep.importe_real,
    ep.created_at            AS fecha_extraccion,
    -- Ubicación: almacén y zona (layout)
    alm.id                   AS id_almacen,
    alm.denominacion         AS almacen_nombre,
    la.id                    AS id_ubicacion,
    la.denominacion          AS ubicacion_nombre,
    la.id_layout_padre       AS id_zona,
    COALESCE(zona.denominacion, la.denominacion) AS zona_nombre,
    la.sku_codigo            AS ubicacion_sku,
    -- Inventario generado por la extracción (si existe)
    ip.id                    AS id_inventario,
    ip.cantidad_inicial,
    ip.cantidad_final,
    ip.created_at            AS fecha_movimiento_inventario
FROM operaciones_filtradas of
INNER JOIN app_dat_extraccion_productos ep ON ep.id_operacion = of.id_operacion
INNER JOIN app_dat_producto p ON p.id = ep.id_producto
LEFT JOIN app_dat_layout_almacen la ON la.id = ep.id_ubicacion
LEFT JOIN app_dat_layout_almacen zona ON zona.id = la.id_layout_padre
LEFT JOIN app_dat_almacen alm ON alm.id = la.id_almacen
LEFT JOIN app_dat_inventario_productos ip ON ip.id_extraccion = ep.id
ORDER BY
    of.tienda_nombre,
    alm.denominacion,
    zona_nombre,
    ubicacion_nombre,
    of.id_operacion,
    ep.id;


-- ─────────────────────────────────────────────────────────────────────────────
-- 2) RESUMEN: totales por tienda, almacén y zona
-- ─────────────────────────────────────────────────────────────────────────────
/*
WITH params AS (
    SELECT
        '57389782-8a5b-437a-9193-0249f845c74e'::uuid AS p_uuid_usuario,
        TIMESTAMPTZ '2026-05-20 00:00:00-04:00'     AS p_fecha_desde,
        TIMESTAMPTZ '2026-05-20 11:59:59-04:00'     AS p_fecha_hasta
),
ultimo_estado AS (
    SELECT eo.id_operacion, eo.estado, eo.created_at AS fecha_ultimo_estado
    FROM app_dat_estado_operacion eo
    INNER JOIN (
        SELECT id_operacion, MAX(id) AS max_id_estado
        FROM app_dat_estado_operacion
        GROUP BY id_operacion
    ) ult ON ult.id_operacion = eo.id_operacion AND ult.max_id_estado = eo.id
),
operaciones_filtradas AS (
    SELECT op.id AS id_operacion, op.id_tienda
    FROM app_dat_operaciones op
    CROSS JOIN params p
    INNER JOIN ultimo_estado ue ON ue.id_operacion = op.id
    WHERE ue.estado = 3
      AND ue.fecha_ultimo_estado BETWEEN p.p_fecha_desde AND p.p_fecha_hasta
      AND op.uuid = p.p_uuid_usuario
),
detalle AS (
    SELECT
        t.id   AS id_tienda,
        t.denominacion AS tienda_nombre,
        alm.id AS id_almacen,
        alm.denominacion AS almacen_nombre,
        COALESCE(zona.id, la.id) AS id_zona,
        COALESCE(zona.denominacion, la.denominacion) AS zona_nombre,
        of.id_operacion,
        ep.id AS id_extraccion,
        ep.cantidad,
        COALESCE(ep.importe_real, ep.importe, 0) AS importe_linea
    FROM operaciones_filtradas of
    INNER JOIN app_dat_operaciones op ON op.id = of.id_operacion
    INNER JOIN app_dat_tienda t ON t.id = op.id_tienda
    INNER JOIN app_dat_extraccion_productos ep ON ep.id_operacion = of.id_operacion
    LEFT JOIN app_dat_layout_almacen la ON la.id = ep.id_ubicacion
    LEFT JOIN app_dat_layout_almacen zona ON zona.id = la.id_layout_padre
    LEFT JOIN app_dat_almacen alm ON alm.id = la.id_almacen
)
SELECT
    id_tienda,
    tienda_nombre,
    id_almacen,
    almacen_nombre,
    id_zona,
    zona_nombre,
    COUNT(DISTINCT id_operacion)  AS total_ordenes,
    COUNT(*)                      AS total_lineas_extraccion,
    SUM(cantidad)                 AS cantidad_total,
    SUM(importe_linea)            AS importe_total
FROM detalle
GROUP BY
    id_tienda, tienda_nombre,
    id_almacen, almacen_nombre,
    id_zona, zona_nombre
ORDER BY
    tienda_nombre, almacen_nombre, zona_nombre;
*/


-- ─────────────────────────────────────────────────────────────────────────────
-- 3) Solo IDs de operaciones (útil para depurar el filtro de estados)
-- ─────────────────────────────────────────────────────────────────────────────
/*
SELECT op.id, ue.estado, ue.fecha_ultimo_estado, op.uuid, op.created_at
FROM app_dat_operaciones op
INNER JOIN (
    SELECT eo.id_operacion, eo.estado, eo.created_at AS fecha_ultimo_estado
    FROM app_dat_estado_operacion eo
    INNER JOIN (
        SELECT id_operacion, MAX(id) AS max_id_estado
        FROM app_dat_estado_operacion
        GROUP BY id_operacion
    ) ult ON ult.id_operacion = eo.id_operacion AND ult.max_id_estado = eo.id
) ue ON ue.id_operacion = op.id
WHERE ue.estado = 3
  AND ue.fecha_ultimo_estado >= TIMESTAMPTZ '2026-05-20 00:00:00-04:00'
  AND ue.fecha_ultimo_estado <= TIMESTAMPTZ '2026-05-20 11:59:59-04:00'
  AND op.uuid = '57389782-8a5b-437a-9193-0249f845c74e'::uuid
ORDER BY op.id;
*/
