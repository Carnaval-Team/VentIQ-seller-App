-- =============================================================================
-- Migración a MAIN: fn_reporte_ventas_por_turno por-turno (versión de newa)
-- =============================================================================
-- Contexto: tab TPVs de sales_screen (tienda 177, 2026-11-16). En main la
-- función devolvía UNA FILA POR VENDEDOR sin id_turno → el cliente no podía
-- filtrar egresos por turno (turnoId siempre null) y
-- fn_listar_entregas_por_fechas_usuario devolvía egresos de TODOS los turnos
-- del vendedor que tocan el rango (egresos del día 14 colados en el turno del
-- 16). En newa la función ya devuelve una fila POR TURNO.
--
-- Este script deja main igual que newa:
--   1. DROP v2 (depende de la v1 por ser SQL-language).
--   2. DROP v1 (cambia el RETURNS TABLE → CREATE OR REPLACE solo no basta).
--   3. CREATE v1 por-turno (idéntica a la que vive en newa y a
--      ventiq_admin_app/lib/sql/fn_reporte_ventas_por_turno.sql).
--   4. Recrea la _v2 con el bloque dinámico de fase5b: detecta `id_turno` en
--      la nueva firma y arma el desglose con fn_desglose_monedas_turno.
--
-- Compatibilidad: la nueva salida incluye TODAS las columnas viejas + 6
-- nuevas al inicio; PostgREST devuelve JSON por nombre, así que las apps
-- viejas ignoran las extra. Diferencia de comportamiento: ahora hay una
-- fila por turno (antes una por vendedor) y solo entran turnos con
-- apertura dentro del rango (el modo 'solapado' de
-- fn_reporte_ventas_por_turno_vendedor queda sin uso).
--
-- Ejecutar en el SQL Editor de Supabase del proyecto MAIN.
-- =============================================================================

BEGIN;

-- ── 1/2. Dropear v2 y v1 (orden importa: v2 referencia a v1) ─────────────────
DROP FUNCTION IF EXISTS public.fn_reporte_ventas_por_turno_v2(uuid, date, date, bigint);
DROP FUNCTION IF EXISTS public.fn_reporte_ventas_por_turno(uuid, date, date, bigint);

-- ── 3. v1 por-turno (versión de newa) ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_reporte_ventas_por_turno(
  p_uuid_usuario uuid DEFAULT NULL::uuid,
  p_fecha_desde date DEFAULT NULL::date,
  p_fecha_hasta date DEFAULT NULL::date,
  p_id_tienda bigint DEFAULT NULL::bigint
)
RETURNS TABLE(
  id_turno bigint,
  id_tpv bigint,
  tpv_nombre character varying,
  estado_turno smallint,
  fecha_apertura timestamp with time zone,
  fecha_cierre timestamp with time zone,
  uuid_usuario uuid,
  nombres character varying,
  apellidos character varying,
  nombre_completo character varying,
  total_ventas bigint,
  total_productos_vendidos numeric,
  total_dinero_efectivo numeric,
  total_dinero_transferencia numeric,
  total_dinero_general numeric,
  total_importe_ventas numeric,
  productos_diferentes_vendidos bigint,
  primera_venta timestamp with time zone,
  ultima_venta timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_fecha_inicio timestamptz;
  v_fecha_fin timestamptz;
  v_id_tipo_venta bigint;
BEGIN
  v_fecha_inicio := COALESCE(p_fecha_desde, CURRENT_DATE)::timestamptz;
  v_fecha_fin := (COALESCE(p_fecha_hasta, CURRENT_DATE) + INTERVAL '1 day')::timestamptz;

  SELECT id INTO v_id_tipo_venta
  FROM app_nom_tipo_operacion
  WHERE LOWER(denominacion) = 'venta'
  LIMIT 1;

  RETURN QUERY
  WITH turnos AS (
    SELECT
      ct.id AS tid,
      ct.id_tpv AS ttpv,
      tp.denominacion AS ttpv_nombre,
      ct.estado AS testado,
      ct.fecha_apertura AS tapertura,
      ct.fecha_cierre AS tcierre,
      v.uuid AS tuuid,
      t.nombres AS tnombres,
      t.apellidos AS tapellidos,
      (t.nombres || ' ' || t.apellidos)::varchar AS tnombre_completo,
      ct.fecha_apertura AS tinicio,
      COALESCE(ct.fecha_cierre, NOW()) AS tfin
    FROM app_dat_caja_turno ct
    JOIN app_dat_tpv tp ON tp.id = ct.id_tpv
    JOIN app_dat_vendedor v ON v.id = ct.id_vendedor
    JOIN app_dat_trabajadores t ON t.id = v.id_trabajador
    WHERE ct.fecha_apertura >= v_fecha_inicio
      AND ct.fecha_apertura < v_fecha_fin
      AND (p_id_tienda IS NULL OR tp.id_tienda = p_id_tienda)
      AND (p_uuid_usuario IS NULL OR v.uuid = p_uuid_usuario)
  ),
  productos_por_operacion AS (
    SELECT
      ep.id_operacion,
      SUM(ep.cantidad) AS total_productos,
      SUM(ep.importe) AS total_importe,
      COUNT(DISTINCT ep.id_producto) AS productos_diferentes
    FROM app_dat_extraccion_productos ep
    GROUP BY ep.id_operacion
  ),
  pagos_por_operacion AS (
    SELECT
      pv.id_operacion_venta,
      SUM(CASE WHEN pv.id_medio_pago = 1 THEN pv.monto ELSE 0 END) AS total_efectivo,
      SUM(CASE WHEN pv.id_medio_pago <> 1 THEN pv.monto ELSE 0 END) AS total_transferencia,
      SUM(pv.monto) AS total_general
    FROM app_dat_pago_venta pv
    GROUP BY pv.id_operacion_venta
  ),
  ventas_turno AS (
    SELECT
      tr.tid,
      o.id AS id_operacion,
      o.created_at,
      ppo.total_productos,
      ppo.total_importe,
      ppo.productos_diferentes,
      pago.total_efectivo,
      pago.total_transferencia,
      pago.total_general
    FROM turnos tr
    JOIN app_dat_operaciones o
      ON o.uuid = tr.tuuid
     AND o.id_tipo_operacion = v_id_tipo_venta
     AND o.created_at >= tr.tinicio
     AND o.created_at <= tr.tfin
    JOIN app_dat_operacion_venta ov
      ON ov.id_operacion = o.id
     AND ov.id_tpv = tr.ttpv
     AND ov.es_pagada = true
    JOIN LATERAL (
      SELECT eo.estado
      FROM app_dat_estado_operacion eo
      WHERE eo.id_operacion = o.id
      ORDER BY eo.id DESC
      LIMIT 1
    ) est ON est.estado = 2
    LEFT JOIN productos_por_operacion ppo ON ppo.id_operacion = o.id
    LEFT JOIN pagos_por_operacion pago ON pago.id_operacion_venta = ov.id_operacion
  )
  SELECT
    tr.tid,
    tr.ttpv,
    tr.ttpv_nombre,
    tr.testado,
    tr.tapertura,
    tr.tcierre,
    tr.tuuid,
    tr.tnombres,
    tr.tapellidos,
    tr.tnombre_completo,
    COUNT(vt.id_operacion)::bigint,
    COALESCE(SUM(vt.total_productos), 0),
    COALESCE(SUM(vt.total_efectivo), 0),
    COALESCE(SUM(vt.total_transferencia), 0),
    COALESCE(SUM(vt.total_general), 0),
    COALESCE(SUM(vt.total_importe), 0),
    COALESCE(SUM(vt.productos_diferentes), 0)::bigint,
    MIN(vt.created_at),
    MAX(vt.created_at)
  FROM turnos tr
  LEFT JOIN ventas_turno vt ON vt.tid = tr.tid
  GROUP BY
    tr.tid,
    tr.ttpv,
    tr.ttpv_nombre,
    tr.testado,
    tr.tapertura,
    tr.tcierre,
    tr.tuuid,
    tr.tnombres,
    tr.tapellidos,
    tr.tnombre_completo
  ORDER BY tr.tapertura DESC, tr.ttpv, tr.tid;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_reporte_ventas_por_turno(uuid, date, date, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_reporte_ventas_por_turno(uuid, date, date, bigint) TO service_role;

-- ── 4. Recrear la _v2 (bloque dinámico de fase5b: detecta id_turno y usa
--       fn_desglose_monedas_turno) ────────────────────────────────────────────
DO $$
DECLARE
  v_cols     text;
  v_es_turno boolean;
  v_expr     text;
BEGIN
  SELECT substring(pg_get_function_result(p.oid) FROM 'TABLE\((.*)\)$')
    INTO v_cols
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'fn_reporte_ventas_por_turno';

  IF v_cols IS NULL THEN
    RAISE EXCEPTION 'no pude leer las columnas de fn_reporte_ventas_por_turno';
  END IF;

  v_es_turno := position('id_turno' IN v_cols) > 0;

  v_expr := CASE WHEN v_es_turno
    THEN 'public.fn_desglose_monedas_turno(b.id_turno, false)'
    ELSE 'public.fn_desglose_monedas_usuario(b.uuid_usuario, p_fecha_desde, p_fecha_hasta, p_id_tienda)'
  END;

  EXECUTE format($f$
    CREATE OR REPLACE FUNCTION public.fn_reporte_ventas_por_turno_v2(
      p_uuid_usuario uuid DEFAULT NULL,
      p_fecha_desde  date DEFAULT NULL,
      p_fecha_hasta  date DEFAULT NULL,
      p_id_tienda    bigint DEFAULT NULL
    ) RETURNS TABLE(%s, desglose_monedas jsonb, total_base numeric)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path TO 'public'
    AS $body$
      WITH base AS (
        SELECT * FROM public.fn_reporte_ventas_por_turno(
          p_uuid_usuario, p_fecha_desde, p_fecha_hasta, p_id_tienda)
      )
      SELECT b.*, d.desglose_monedas, d.total_base
      FROM base b
      CROSS JOIN LATERAL %s d;
    $body$;
  $f$, v_cols, v_expr);

  RAISE NOTICE '_v2 recreada con criterio %',
    CASE WHEN v_es_turno THEN 'por turno' ELSE 'por vendedor' END;
END $$;

GRANT EXECUTE ON FUNCTION public.fn_reporte_ventas_por_turno_v2(uuid, date, date, bigint)
  TO authenticated, service_role;

COMMIT;

-- ── Verificación ─────────────────────────────────────────────────────────────
-- La v1 debe devolver 19 columnas por turno (id_turno primero):
SELECT pg_get_function_result('public.fn_reporte_ventas_por_turno(uuid,date,date,bigint)'::regprocedure) AS v1_result;

-- La v2 = columnas de v1 + desglose_monedas + total_base:
SELECT pg_get_function_result('public.fn_reporte_ventas_por_turno_v2(uuid,date,date,bigint)'::regprocedure) AS v2_result;

-- Prueba de humo con la tienda 177 (día del reporte):
SELECT id_turno, id_tpv, estado_turno, fecha_apertura, fecha_cierre,
       nombre_completo, total_ventas, total_dinero_general
  FROM public.fn_reporte_ventas_por_turno(
    NULL, '2026-11-14'::date, '2026-11-16'::date, 177)
 ORDER BY fecha_apertura;
-- Esperado: una fila por turno (3504 del 14, 3522 del 16), no agregadas.
