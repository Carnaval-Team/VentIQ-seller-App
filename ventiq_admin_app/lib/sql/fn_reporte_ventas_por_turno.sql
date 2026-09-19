-- Reporte de ventas por TURNO de caja (uno por fila de app_dat_caja_turno).
-- Tab TPVs del admin: cada apertura/cierre sale independiente, sin agrupar.

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
