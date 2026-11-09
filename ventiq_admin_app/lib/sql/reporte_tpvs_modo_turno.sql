-- ============================================================================
-- Config por tienda del criterio de turnos del tab TPVs (Ventas).
--
-- Problema: el parche de ventana solapada (tienda 45, turno abierto meses
-- antes) hizo que fn_reporte_ventas_por_turno_vendedor incluyera turnos que
-- NO se abrieron en el período (p. ej. tienda 235: el turno 3448 abierto el
-- 08/11 aparecía filtrando el 09/11 porque cerró ese día).
--
-- Solución: columna app_dat_configuracion_tienda.reporte_tpvs_modo_turno.
--   'solapado'            -> comportamiento actual (turnos que tocan la
--                            ventana, ventas recortadas al período). Default:
--                            ninguna tienda cambia si no toca el switch.
--   'apertura_en_periodo' -> solo turnos con fecha_apertura dentro del rango;
--                            las ventas se cuentan hasta el cierre del turno
--                            aunque cruce de día (sin recorte por created_at).
--
-- fn_reporte_ventas_por_turno y _v2 delegan en _vendedor: un solo cambio.
-- Ejecutar en el SQL Editor del proyecto (Main; replicar en Newa si aplica).
-- ============================================================================

ALTER TABLE public.app_dat_configuracion_tienda
  ADD COLUMN IF NOT EXISTS reporte_tpvs_modo_turno text NOT NULL DEFAULT 'solapado';

ALTER TABLE public.app_dat_configuracion_tienda
  DROP CONSTRAINT IF EXISTS app_dat_configuracion_tienda_modo_turno_chk;
ALTER TABLE public.app_dat_configuracion_tienda
  ADD CONSTRAINT app_dat_configuracion_tienda_modo_turno_chk
  CHECK (reporte_tpvs_modo_turno IN ('solapado', 'apertura_en_periodo'));

-- Tienda 235: solo turnos abiertos en el período.
UPDATE public.app_dat_configuracion_tienda
   SET reporte_tpvs_modo_turno = 'apertura_en_periodo'
 WHERE id_tienda = 235;

CREATE OR REPLACE FUNCTION public.fn_reporte_ventas_por_turno_vendedor(
  p_uuid_usuario uuid DEFAULT NULL::uuid,
  p_fecha_desde date DEFAULT NULL::date,
  p_fecha_hasta date DEFAULT NULL::date,
  p_id_tienda bigint DEFAULT NULL::bigint
)
RETURNS TABLE(
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
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_fecha_inicio timestamptz;
    v_fecha_fin    timestamptz;
    v_id_tipo_venta bigint;
    v_modo_turno   text := 'solapado';
BEGIN
    v_fecha_inicio := COALESCE(p_fecha_desde, CURRENT_DATE)::timestamptz;
    v_fecha_fin    := (COALESCE(p_fecha_hasta, CURRENT_DATE) + INTERVAL '1 day')::timestamptz;

    -- Obtener el tipo de operación "venta".
    SELECT tipo.id
      INTO v_id_tipo_venta
      FROM public.app_nom_tipo_operacion tipo
     WHERE LOWER(tipo.denominacion) = 'venta'
     ORDER BY tipo.id
     LIMIT 1;

    IF v_id_tipo_venta IS NULL THEN
        RETURN;
    END IF;

    -- Criterio de turnos configurado en la tienda (default 'solapado').
    IF p_id_tienda IS NOT NULL THEN
        SELECT cfg.reporte_tpvs_modo_turno
          INTO v_modo_turno
          FROM public.app_dat_configuracion_tienda cfg
         WHERE cfg.id_tienda = p_id_tienda
         LIMIT 1;
        v_modo_turno := COALESCE(v_modo_turno, 'solapado');
    END IF;

    RETURN QUERY
    WITH turnos AS (
        -- 'apertura_en_periodo': solo turnos abiertos dentro del rango.
        -- 'solapado': cualquier turno que toque la ventana (abierto antes y
        -- aún abierto, o cerrado dentro/después de ella).
        SELECT
            ct.id                       AS turno_id,
            ct.id_tpv                   AS turno_tpv_id,
            ct.id_operacion_apertura    AS op_apertura,
            ct.id_operacion_cierre      AS op_cierre,
            ct.estado                   AS turno_estado,
            vendedor.uuid               AS vendedor_uuid,
            trabajador.nombres          AS vendedor_nombres,
            trabajador.apellidos        AS vendedor_apellidos,
            CONCAT_WS(' ', trabajador.nombres, trabajador.apellidos)::varchar
                                        AS vendedor_nombre_completo
        FROM public.app_dat_caja_turno ct
        INNER JOIN public.app_dat_tpv tp
            ON tp.id = ct.id_tpv
        INNER JOIN public.app_dat_vendedor vendedor
            ON vendedor.id = ct.id_vendedor
        INNER JOIN public.app_dat_trabajadores trabajador
            ON trabajador.id = vendedor.id_trabajador
        WHERE (
                (v_modo_turno = 'apertura_en_periodo'
                    AND ct.fecha_apertura >= v_fecha_inicio)
                OR
                (v_modo_turno <> 'apertura_en_periodo'
                    AND COALESCE(ct.fecha_cierre, NOW()) >= v_fecha_inicio)
              )
          AND ct.fecha_apertura < v_fecha_fin
          AND (p_id_tienda IS NULL OR tp.id_tienda = p_id_tienda)
          AND (p_uuid_usuario IS NULL OR vendedor.uuid = p_uuid_usuario)
    ),
    rangos_vendedor AS (
        SELECT
            t.vendedor_uuid,
            t.vendedor_nombres,
            t.vendedor_apellidos,
            t.vendedor_nombre_completo,
            t.turno_tpv_id,
            t.op_apertura,
            COALESCE(t.op_cierre, (SELECT MAX(o2.id) FROM public.app_dat_operaciones o2))
                AS op_cierre_efectivo
        FROM turnos t
    ),
    productos_por_operacion AS (
        SELECT
            ep.id_operacion,
            SUM(ep.cantidad)              AS total_productos,
            SUM(ep.importe)               AS total_importe,
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
        -- Las operaciones se delimitan por id_operacion (apertura..cierre).
        -- En modo 'solapado' además se recortan por created_at a la ventana
        -- pedida; en 'apertura_en_periodo' el turno se cuenta completo hasta
        -- su cierre.
        SELECT DISTINCT ON (o.id)
            rv.vendedor_uuid,
            rv.vendedor_nombres,
            rv.vendedor_apellidos,
            rv.vendedor_nombre_completo,
            o.id            AS id_operacion,
            o.created_at,
            COALESCE(ppo.total_productos, 0)     AS total_productos,
            COALESCE(ppo.total_importe, 0)        AS total_importe,
            COALESCE(ppo.productos_diferentes, 0) AS productos_diferentes,
            COALESCE(pago.total_efectivo, 0)      AS total_efectivo,
            COALESCE(pago.total_transferencia, 0) AS total_transferencia,
            COALESCE(pago.total_general, 0)       AS total_general
        FROM rangos_vendedor rv
        INNER JOIN public.app_dat_operaciones o
            ON o.uuid = rv.vendedor_uuid
           AND o.id_tipo_operacion = v_id_tipo_venta
           AND o.id >= rv.op_apertura
           AND o.id <= rv.op_cierre_efectivo
           AND (
                 v_modo_turno = 'apertura_en_periodo'
                 OR (o.created_at >= v_fecha_inicio AND o.created_at < v_fecha_fin)
               )
        INNER JOIN public.app_dat_operacion_venta ov
            ON ov.id_operacion = o.id
           AND ov.id_tpv = rv.turno_tpv_id
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
        ORDER BY o.id
    )
    SELECT
        v.vendedor_uuid,
        v.vendedor_nombres,
        v.vendedor_apellidos,
        v.vendedor_nombre_completo,
        COUNT(v.id_operacion)::bigint                       AS total_ventas,
        COALESCE(SUM(v.total_productos), 0)::numeric        AS total_productos_vendidos,
        COALESCE(SUM(v.total_efectivo), 0)::numeric         AS total_dinero_efectivo,
        COALESCE(SUM(v.total_transferencia), 0)::numeric    AS total_dinero_transferencia,
        COALESCE(SUM(v.total_general), 0)::numeric          AS total_dinero_general,
        COALESCE(SUM(v.total_importe), 0)::numeric          AS total_importe_ventas,
        COALESCE(SUM(v.productos_diferentes), 0)::bigint    AS productos_diferentes_vendidos,
        MIN(v.created_at)                                    AS primera_venta,
        MAX(v.created_at)                                    AS ultima_venta
    FROM ventas v
    GROUP BY
        v.vendedor_uuid,
        v.vendedor_nombres,
        v.vendedor_apellidos,
        v.vendedor_nombre_completo
    ORDER BY total_dinero_general DESC, total_ventas DESC;
END;
$function$;

-- ── Verificación (tienda 235, 09/11/2026) ────────────────────────────────────
-- Solo debe aparecer el turno 3457 (abierto el 09/11), no el 3448 (08→09):
--   SELECT * FROM public.fn_reporte_ventas_por_turno(NULL, '2026-11-09', '2026-11-09', 235);
-- Una tienda sin tocar sigue en 'solapado':
--   SELECT * FROM public.fn_reporte_ventas_por_turno(NULL, '2026-10-25', '2026-10-31', 45);
