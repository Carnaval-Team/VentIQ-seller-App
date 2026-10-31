-- =============================================================================
-- Reporte de ventas con proveedor por FECHA de operación (sin turnos)
-- =============================================================================
-- Contexto: tienda 45, período 2026-10-25→31. La tienda tiene UN turno
-- (id 1225) abierto el 2026-02-25 y todavía abierto. Las 32 ventas pagadas
-- del período pertenecen a ese turno, pero
--   fn_reporte_ventas_con_proveedor_por_turno_v2
-- filtraba turnos por `fecha_apertura DENTRO del período` → el turno quedaba
-- fuera y el reporte devolvía 0.
--
-- Decisión del usuario: el reporte de proveedores NO necesita lógica de
-- turnos — debe listar las operaciones de venta por su fecha. Por tanto:
--
--   1. fn_reporte_ventas_con_proveedor_por_turno_v2: se elimina la CTE
--      `turnos` y `ops` pasa a ser "operaciones de venta pagadas y
--      completadas con created_at dentro de la ventana pedida". Firma,
--      columnas y permisos sin cambios → la app no necesita actualizarse.
--      (El chip "Turnos" de Tiempo Real queda equivalente a "Creación".)
--   2. fn_reporte_ventas_con_proveedor_por_turno (v1, fallback): mismo
--      cambio por coherencia.
--   3. fn_reporte_ventas_por_turno_vendedor (tab TPVs): ese reporte SÍ es
--      por turnos, pero tenía el mismo bug — un turno abierto antes del
--      período no aparecía. Se corrige a "turnos que SOLAPAN la ventana"
--      con ventas acotadas a la ventana pedida.
--
-- Las funciones se reescriben desde su definición VIVA (pg_get_functiondef)
-- con reemplazos verificados: si un ancla no coincide, el script aborta sin
-- tocar nada. Idempotente. CREATE OR REPLACE conserva firmas y permisos.
-- Aplicable a Main y Newa.
-- =============================================================================

BEGIN;

-- ── 1. por_turno_v2 → ops por fecha ──────────────────────────────────────────
DO $$
DECLARE
    v_fn  constant regprocedure :=
        'public.fn_reporte_ventas_con_proveedor_por_turno_v2(bigint, date, date, bigint)'::regprocedure;
    v_def text;
    v_turnos constant text :=
        '    -- Misma ventana de turnos que fn_reporte_ventas_por_turno (tab TPVs).' || E'\r\n'
        || '    turnos AS MATERIALIZED (' || E'\r\n'
        || '        SELECT' || E'\r\n'
        || '            ct.id_tpv,' || E'\r\n'
        || '            ct.fecha_apertura AS tinicio,' || E'\r\n'
        || '            COALESCE(ct.fecha_cierre, NOW()) AS tfin,' || E'\r\n'
        || '            v.uuid AS vuuid' || E'\r\n'
        || '        FROM app_dat_caja_turno ct' || E'\r\n'
        || '        JOIN app_dat_vendedor v ON v.id = ct.id_vendedor' || E'\r\n'
        || '        JOIN app_dat_tpv tp ON tp.id = ct.id_tpv' || E'\r\n'
        || '        WHERE tp.id_tienda = p_id_tienda' || E'\r\n'
        || '          AND ct.fecha_apertura >= v_fecha_inicio' || E'\r\n'
        || '          AND ct.fecha_apertura <  v_fecha_fin' || E'\r\n'
        || '    ),' || E'\r\n';
    v_ops_from constant text :=
        '        FROM turnos t' || E'\r\n'
        || '        JOIN app_dat_operaciones o' || E'\r\n'
        || '          ON o.uuid = t.vuuid' || E'\r\n'
        || '         AND o.id_tipo_operacion = v_id_tipo_venta' || E'\r\n'
        || '         AND o.id_tienda = p_id_tienda' || E'\r\n'
        || '         AND o.created_at >= t.tinicio' || E'\r\n'
        || '         AND o.created_at <= t.tfin' || E'\r\n'
        || '        JOIN app_dat_operacion_venta ov' || E'\r\n'
        || '          ON ov.id_operacion = o.id' || E'\r\n'
        || '         AND ov.id_tpv = t.id_tpv' || E'\r\n'
        || '         AND ov.es_pagada = true';
    v_where constant text := '        WHERE e.estado = 2';
BEGIN
    v_def := pg_get_functiondef(v_fn);

    IF position('AND o.created_at <  v_fecha_fin' IN v_def) > 0
       AND position('FROM turnos t' IN v_def) = 0 THEN
        RAISE NOTICE 'por_turno_v2 ya es por fecha: se omite';
        RETURN;
    END IF;

    IF position(v_turnos IN v_def) = 0
       OR position(v_ops_from IN v_def) = 0
       OR position(v_where IN v_def) = 0 THEN
        RAISE EXCEPTION 'Anclas no encontradas en por_turno_v2';
    END IF;

    -- Quitar la CTE turnos (ya no se referencia).
    v_def := replace(v_def, v_turnos, '');
    -- ops: operaciones por fecha, sin uuid/tpv del turno.
    v_def := replace(v_def, v_ops_from,
        '        FROM app_dat_operaciones o' || E'\r\n'
        || '        JOIN app_dat_operacion_venta ov' || E'\r\n'
        || '          ON ov.id_operacion = o.id' || E'\r\n'
        || '         AND ov.es_pagada = true');
    v_def := replace(v_def, v_where,
        '        WHERE o.id_tipo_operacion = v_id_tipo_venta' || E'\r\n'
        || '          AND o.id_tienda = p_id_tienda' || E'\r\n'
        || '          AND o.created_at >= v_fecha_inicio' || E'\r\n'
        || '          AND o.created_at <  v_fecha_fin' || E'\r\n'
        || '          AND e.estado = 2');

    EXECUTE v_def;
    RAISE NOTICE 'por_turno_v2: ahora reporta operaciones por fecha';
END
$$;

-- ── 2. por_turno v1 (fallback) → ops por fecha ───────────────────────────────
DO $$
DECLARE
    v_fn  constant regprocedure :=
        'public.fn_reporte_ventas_con_proveedor_por_turno(bigint, date, date, bigint)'::regprocedure;
    v_def text;
    v_turnos constant text :=
        '    turnos AS MATERIALIZED (' || E'\r\n'
        || '        SELECT' || E'\r\n'
        || '            ct.id_tpv,' || E'\r\n'
        || '            ct.id_operacion_apertura,' || E'\r\n'
        || '            ct.id_operacion_cierre,' || E'\r\n'
        || '            v.uuid' || E'\r\n'
        || '        FROM app_dat_caja_turno ct' || E'\r\n'
        || '        JOIN app_dat_vendedor v ON v.id = ct.id_vendedor' || E'\r\n'
        || '        JOIN app_dat_tpv tp ON tp.id = ct.id_tpv' || E'\r\n'
        || '        WHERE tp.id_tienda = p_id_tienda' || E'\r\n'
        || '          AND ct.fecha_apertura::date >= COALESCE(p_fecha_desde, CURRENT_DATE)' || E'\r\n'
        || '          AND ct.fecha_apertura::date <= COALESCE(p_fecha_hasta, CURRENT_DATE)' || E'\r\n'
        || '    ),' || E'\r\n'
        || E'\r\n'
        || '    max_op AS MATERIALIZED (' || E'\r\n'
        || '        SELECT MAX(o2.id) AS max_id FROM app_dat_operaciones o2' || E'\r\n'
        || '    ),' || E'\r\n';
    v_join constant text :=
        '        JOIN turnos t' || E'\r\n'
        || '          ON t.uuid = o.uuid' || E'\r\n'
        || '         AND ov.id_tpv = t.id_tpv' || E'\r\n'
        || '         AND o.id >= t.id_operacion_apertura' || E'\r\n'
        || '         AND o.id <= COALESCE(t.id_operacion_cierre, (SELECT max_id FROM max_op))' || E'\r\n';
    v_where constant text :=
        '        WHERE o.id_tienda = p_id_tienda' || E'\r\n'
        || '          AND o.id_tipo_operacion = v_id_tipo_venta' || E'\r\n'
        || '          AND e.estado = 2';
BEGIN
    v_def := pg_get_functiondef(v_fn);

    IF position('AND o.created_at >= COALESCE(p_fecha_desde' IN v_def) > 0 THEN
        RAISE NOTICE 'por_turno v1 ya es por fecha: se omite';
        RETURN;
    END IF;

    IF position(v_turnos IN v_def) = 0
       OR position(v_join IN v_def) = 0
       OR position(v_where IN v_def) = 0 THEN
        RAISE EXCEPTION 'Anclas no encontradas en por_turno v1';
    END IF;

    v_def := replace(v_def, v_turnos, '');
    v_def := replace(v_def, v_join, '');
    v_def := replace(v_def, v_where,
        '        WHERE o.id_tienda = p_id_tienda' || E'\r\n'
        || '          AND o.id_tipo_operacion = v_id_tipo_venta' || E'\r\n'
        || '          AND o.created_at >= COALESCE(p_fecha_desde, CURRENT_DATE)::timestamptz' || E'\r\n'
        || '          AND o.created_at <  (COALESCE(p_fecha_hasta, CURRENT_DATE) + INTERVAL ''1 day'')::timestamptz' || E'\r\n'
        || '          AND e.estado = 2');

    EXECUTE v_def;
    RAISE NOTICE 'por_turno v1: ahora reporta operaciones por fecha';
END
$$;

-- ── 3. por_turno_vendedor (tab TPVs): turnos que SOLAPAN la ventana ──────────
DO $$
DECLARE
    v_fn  constant regprocedure :=
        'public.fn_reporte_ventas_por_turno_vendedor(uuid, date, date, bigint)'::regprocedure;
    v_def text;
    v_anchor constant text := 'AND o.id <= rv.op_cierre_efectivo';
BEGIN
    v_def := pg_get_functiondef(v_fn);

    IF position('AND o.created_at >= v_fecha_inicio' IN v_def) > 0 THEN
        RAISE NOTICE 'por_turno_vendedor ya parcheada: se omite';
        RETURN;
    END IF;

    IF position('WHERE ct.fecha_apertura >= v_fecha_inicio' IN v_def) = 0
       OR position(v_anchor IN v_def) = 0 THEN
        RAISE EXCEPTION 'Anclas no encontradas en por_turno_vendedor';
    END IF;

    -- Un turno abierto antes del período (y aún abierto) también entra.
    v_def := replace(v_def,
        'WHERE ct.fecha_apertura >= v_fecha_inicio',
        'WHERE COALESCE(ct.fecha_cierre, NOW()) >= v_fecha_inicio');
    -- Sus ventas se acotan además a la ventana pedida (no todo el turno).
    v_def := replace(v_def, v_anchor, v_anchor
        || E'\r\n           AND o.created_at >= v_fecha_inicio'
        || E'\r\n           AND o.created_at <  v_fecha_fin');

    EXECUTE v_def;
    RAISE NOTICE 'por_turno_vendedor: turnos que solapan la ventana';
END
$$;

COMMIT;

-- ── Verificación ─────────────────────────────────────────────────────────────
SELECT proname,
       position('turnos t' IN prosrc) = 0                AS sin_join_turnos,
       prosrc ~ 'created_at >= v_fecha_inicio'
        OR prosrc ~ 'created_at >= COALESCE'             AS ops_por_fecha
  FROM pg_proc
 WHERE pronamespace = 'public'::regnamespace
   AND proname IN ('fn_reporte_ventas_con_proveedor_por_turno_v2',
                   'fn_reporte_ventas_con_proveedor_por_turno')
 ORDER BY proname;

SELECT proname,
       prosrc ~ 'COALESCE\(ct\.fecha_cierre, NOW\(\)\) >= v_fecha_inicio' AS solapa,
       prosrc ~ 'o\.created_at >= v_fecha_inicio'                        AS ops_acotadas
  FROM pg_proc
 WHERE pronamespace = 'public'::regnamespace
   AND proname = 'fn_reporte_ventas_por_turno_vendedor';

-- Prueba de humo (con un usuario con acceso a la tienda 45):
-- SELECT * FROM public.fn_reporte_ventas_con_proveedor_por_turno_v2(45, '2026-10-25', '2026-10-31');
-- Debe devolver las ventas del 25→31 aunque el turno 1225 se abrió en febrero.
