-- =============================================================================
-- MAIN: egresos del mismo turno que el reporte de TPVs
-- =============================================================================
-- El reporte arma cada turno con app_dat_caja_turno.id (y su rango de
-- operaciones de apertura a cierre, el TPV y el modo de la tienda) y después
-- los junta en una fila por vendedor. Por eso el 3524 y el 3533 del mismo
-- día, y el 3504 que sigue abierto desde el 14, salían juntos.
--
-- Este script:
--   1. Deja fn_reporte_ventas_por_turno en una fila por ct.id. Entran solo
--      los turnos cuya fecha_apertura cae en el rango del filtro; un turno
--      abierto de otro día no aparece. Las ventas del turno se cuentan
--      hasta su cierre. No toca _vendedor: el reporte de proveedores sigue
--      llamándola.
--   2. Recrea la _v2 para que arrastre id_turno y el desglose por turno.
--   3. fn_listar_entregas_por_fechas_usuario, con p_id_turno, devuelve solo
--      los egresos de ese ct.id. Sin el parámetro (total del período) solo
--      entran egresos cuya fecha cae en el rango.
--
-- Ejecutar completo en el SQL Editor de MAIN.
-- =============================================================================

BEGIN;

-- ── 1. Reporte: una fila por turno ───────────────────────────────────────────
DROP FUNCTION IF EXISTS public.fn_reporte_ventas_por_turno_v2(uuid, date, date, bigint);
DROP FUNCTION IF EXISTS public.fn_reporte_ventas_por_turno(uuid, date, date, bigint);

CREATE FUNCTION public.fn_reporte_ventas_por_turno(
  p_uuid_usuario uuid DEFAULT NULL,
  p_fecha_desde date DEFAULT NULL,
  p_fecha_hasta date DEFAULT NULL,
  p_id_tienda bigint DEFAULT NULL
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
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_fecha_inicio timestamptz;
  v_fecha_fin timestamptz;
  v_id_tipo_venta bigint;
BEGIN
  v_fecha_inicio := COALESCE(p_fecha_desde, CURRENT_DATE)::timestamptz;
  v_fecha_fin := (COALESCE(p_fecha_hasta, CURRENT_DATE) + INTERVAL '1 day')::timestamptz;

  SELECT tipo.id
    INTO v_id_tipo_venta
    FROM public.app_nom_tipo_operacion tipo
   WHERE LOWER(tipo.denominacion) = 'venta'
   ORDER BY tipo.id
   LIMIT 1;

  IF v_id_tipo_venta IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH turnos AS (
    SELECT
      ct.id AS turno_id,
      ct.id_tpv AS turno_tpv_id,
      tp.denominacion AS turno_tpv_nombre,
      ct.estado::smallint AS turno_estado,
      ct.fecha_apertura AS turno_apertura,
      ct.fecha_cierre AS turno_cierre,
      ct.id_operacion_apertura AS op_apertura,
      COALESCE(
        ct.id_operacion_cierre,
        (SELECT MAX(o2.id) FROM public.app_dat_operaciones o2)
      ) AS op_cierre_efectivo,
      vendedor.uuid AS vendedor_uuid,
      trabajador.nombres AS vendedor_nombres,
      trabajador.apellidos AS vendedor_apellidos,
      CONCAT_WS(' ', trabajador.nombres, trabajador.apellidos)::varchar
        AS vendedor_nombre_completo
    FROM public.app_dat_caja_turno ct
    INNER JOIN public.app_dat_tpv tp
      ON tp.id = ct.id_tpv
    INNER JOIN public.app_dat_vendedor vendedor
      ON vendedor.id = ct.id_vendedor
    INNER JOIN public.app_dat_trabajadores trabajador
      ON trabajador.id = vendedor.id_trabajador
    WHERE ct.fecha_apertura >= v_fecha_inicio
      AND ct.fecha_apertura < v_fecha_fin
      AND (p_id_tienda IS NULL OR tp.id_tienda = p_id_tienda)
      AND (p_uuid_usuario IS NULL OR vendedor.uuid = p_uuid_usuario)
  ),
  productos_por_operacion AS (
    SELECT
      ep.id_operacion,
      SUM(ep.cantidad) AS total_productos,
      SUM(ep.importe) AS total_importe,
      COUNT(DISTINCT ep.id_producto) AS productos_diferentes
    FROM public.app_dat_extraccion_productos ep
    GROUP BY ep.id_operacion
  ),
  pagos_por_operacion AS (
    SELECT
      pv.id_operacion_venta,
      SUM(CASE WHEN pv.id_medio_pago = 1 THEN pv.monto ELSE 0 END) AS total_efectivo,
      SUM(CASE WHEN pv.id_medio_pago <> 1 THEN pv.monto ELSE 0 END) AS total_transferencia,
      SUM(pv.monto) AS total_general
    FROM public.app_dat_pago_venta pv
    GROUP BY pv.id_operacion_venta
  ),
  ventas AS (
    SELECT DISTINCT ON (o.id)
      t.turno_id,
      o.id AS id_operacion,
      o.created_at,
      COALESCE(ppo.total_productos, 0) AS total_productos,
      COALESCE(ppo.total_importe, 0) AS total_importe,
      COALESCE(ppo.productos_diferentes, 0) AS productos_diferentes,
      COALESCE(pago.total_efectivo, 0) AS total_efectivo,
      COALESCE(pago.total_transferencia, 0) AS total_transferencia,
      COALESCE(pago.total_general, 0) AS total_general
    FROM turnos t
    INNER JOIN public.app_dat_operaciones o
      ON o.uuid = t.vendedor_uuid
     AND o.id_tipo_operacion = v_id_tipo_venta
     AND o.id >= t.op_apertura
     AND o.id <= t.op_cierre_efectivo
    INNER JOIN public.app_dat_operacion_venta ov
      ON ov.id_operacion = o.id
     AND ov.id_tpv = t.turno_tpv_id
     AND ov.es_pagada = true
    INNER JOIN LATERAL (
      SELECT eo.estado
      FROM public.app_dat_estado_operacion eo
      WHERE eo.id_operacion = o.id
      ORDER BY eo.id DESC
      LIMIT 1
    ) est ON est.estado = 2
    LEFT JOIN productos_por_operacion ppo
      ON ppo.id_operacion = o.id
    LEFT JOIN pagos_por_operacion pago
      ON pago.id_operacion_venta = o.id
    WHERE (p_id_tienda IS NULL OR o.id_tienda = p_id_tienda)
    ORDER BY o.id, t.turno_id
  )
  SELECT
    t.turno_id,
    t.turno_tpv_id,
    t.turno_tpv_nombre,
    t.turno_estado,
    t.turno_apertura,
    t.turno_cierre,
    t.vendedor_uuid,
    t.vendedor_nombres,
    t.vendedor_apellidos,
    t.vendedor_nombre_completo,
    COUNT(v.id_operacion)::bigint,
    COALESCE(SUM(v.total_productos), 0)::numeric,
    COALESCE(SUM(v.total_efectivo), 0)::numeric,
    COALESCE(SUM(v.total_transferencia), 0)::numeric,
    COALESCE(SUM(v.total_general), 0)::numeric,
    COALESCE(SUM(v.total_importe), 0)::numeric,
    COALESCE(SUM(v.productos_diferentes), 0)::bigint,
    MIN(v.created_at),
    MAX(v.created_at)
  FROM turnos t
  LEFT JOIN ventas v ON v.turno_id = t.turno_id
  GROUP BY
    t.turno_id,
    t.turno_tpv_id,
    t.turno_tpv_nombre,
    t.turno_estado,
    t.turno_apertura,
    t.turno_cierre,
    t.vendedor_uuid,
    t.vendedor_nombres,
    t.vendedor_apellidos,
    t.vendedor_nombre_completo
  ORDER BY t.turno_apertura DESC, t.turno_tpv_id, t.turno_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_reporte_ventas_por_turno(uuid, date, date, bigint)
  TO PUBLIC, anon, authenticated, service_role;

-- ── 2. v2: mismas columnas + desglose del turno ──────────────────────────────
DO $$
DECLARE
  v_cols text;
  v_es_turno boolean;
  v_expr text;
BEGIN
  SELECT substring(pg_get_function_result(p.oid) FROM 'TABLE\((.*)\)$')
    INTO v_cols
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = 'fn_reporte_ventas_por_turno'
     AND pg_get_function_identity_arguments(p.oid) LIKE 'p_uuid_usuario%';

  IF v_cols IS NULL THEN
    RAISE EXCEPTION 'no pude leer las columnas de fn_reporte_ventas_por_turno';
  END IF;

  v_es_turno := position('id_turno' IN v_cols) > 0;
  v_expr := CASE
    WHEN v_es_turno THEN 'public.fn_desglose_monedas_turno(b.id_turno, false)'
    ELSE 'public.fn_desglose_monedas_usuario(b.uuid_usuario, p_fecha_desde, p_fecha_hasta, p_id_tienda)'
  END;

  EXECUTE format($f$
    CREATE FUNCTION public.fn_reporte_ventas_por_turno_v2(
      p_uuid_usuario uuid DEFAULT NULL,
      p_fecha_desde date DEFAULT NULL,
      p_fecha_hasta date DEFAULT NULL,
      p_id_tienda bigint DEFAULT NULL
    ) RETURNS TABLE(%s, desglose_monedas jsonb, total_base numeric)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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
END $$;

GRANT EXECUTE ON FUNCTION public.fn_reporte_ventas_por_turno_v2(uuid, date, date, bigint)
  TO PUBLIC, anon, authenticated, service_role;

-- ── 3. Egresos: el mismo id de turno ─────────────────────────────────────────
-- La firma vieja (timestamp sin zona) y la nueva (timestamptz + p_id_turno),
-- para poder volver a ejecutar el script.
DROP FUNCTION IF EXISTS public.fn_listar_entregas_por_fechas_usuario(
  timestamp without time zone,
  timestamp without time zone,
  uuid
);
DROP FUNCTION IF EXISTS public.fn_listar_entregas_por_fechas_usuario(
  timestamptz,
  timestamptz,
  uuid,
  bigint
);

CREATE FUNCTION public.fn_listar_entregas_por_fechas_usuario(
  p_fecha_inicio timestamptz,
  p_fecha_fin timestamptz,
  p_uuid_usuario uuid DEFAULT NULL,
  p_id_turno bigint DEFAULT NULL
)
RETURNS SETOF public.app_dat_entregas_parciales_caja
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT entrega.*
  FROM public.app_dat_entregas_parciales_caja entrega
  INNER JOIN public.app_dat_caja_turno turno
    ON turno.id = entrega.id_turno
  INNER JOIN public.app_dat_vendedor vendedor
    ON vendedor.id = turno.id_vendedor
  WHERE (p_uuid_usuario IS NULL OR vendedor.uuid = p_uuid_usuario)
    AND entrega.fecha_entrega >= turno.fecha_apertura
    AND entrega.fecha_entrega <= COALESCE(turno.fecha_cierre, NOW())
    AND (
      (
        -- El mismo ct.id que usa el reporte. No importa si el egreso
        -- es posterior a la última venta: sigue siendo de este turno.
        p_id_turno IS NOT NULL
        AND entrega.id_turno = p_id_turno
      )
      OR (
        p_id_turno IS NULL
        AND entrega.fecha_entrega >= p_fecha_inicio
        AND entrega.fecha_entrega <= p_fecha_fin
      )
    )
  ORDER BY entrega.fecha_entrega DESC, entrega.id DESC;
$function$;

REVOKE ALL ON FUNCTION public.fn_listar_entregas_por_fechas_usuario(
  timestamptz, timestamptz, uuid, bigint
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_listar_entregas_por_fechas_usuario(
  timestamptz, timestamptz, uuid, bigint
) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- Turno 3533: solo 2422, 2423 y 2424. El 3504 (día 14) no entra.
-- SELECT id, id_turno, monto_entrega, fecha_entrega
--   FROM public.fn_listar_entregas_por_fechas_usuario(
--     '2026-11-17T16:07:17-05',
--     '2026-11-17T16:16:02-05',
--     '748b2bc7-dadb-4c76-b327-251c047657fe',
--     3533);
