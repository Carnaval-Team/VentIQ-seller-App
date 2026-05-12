-- ============================================================
-- RPC: fn_get_inventario_movimientos_tiempo_real
-- Devuelve el último estado del inventario por tienda, agrupado
-- por almacén/zona, con la variación (positivo = salió, negativo
-- = entró), el SKU y nombre del producto, ordenado por la fecha
-- del último movimiento (DESC) y con paginación.
-- ============================================================
DROP FUNCTION IF EXISTS public.fn_get_inventario_movimientos_tiempo_real(
  BIGINT, INTEGER, INTEGER
);

CREATE OR REPLACE FUNCTION public.fn_get_inventario_movimientos_tiempo_real(
  p_id_tienda BIGINT,
  p_pagina    INTEGER DEFAULT 1,
  p_limite    INTEGER DEFAULT 50
)
RETURNS TABLE (
  id_inventario       BIGINT,
  id_producto         BIGINT,
  producto_nombre     TEXT,
  sku                 TEXT,
  id_almacen          BIGINT,
  almacen_nombre      TEXT,
  id_ubicacion        BIGINT,
  zona_nombre         TEXT,
  cantidad_final      NUMERIC,
  cantidad_inicial    NUMERIC,
  variacion           NUMERIC,
  direccion           TEXT,   -- 'subio' | 'bajo' | 'sin_cambio'
  origen_cambio       SMALLINT,
  ultima_fecha        TIMESTAMPTZ,
  total_count         BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_offset INTEGER := (GREATEST(p_pagina, 1) - 1) * p_limite;
  v_total  BIGINT;
BEGIN
  -- Por cada (producto, variante, opcion, presentacion, ubicacion)
  -- tomamos la fila más reciente del histórico de inventario.
  WITH ultimo_inv AS (
    SELECT DISTINCT ON (
      ip.id_producto,
      COALESCE(ip.id_variante, 0),
      COALESCE(ip.id_opcion_variante, 0),
      ip.id_presentacion,
      ip.id_ubicacion
    )
      ip.id              AS id_inventario,
      ip.id_producto,
      ip.id_ubicacion,
      ip.cantidad_inicial,
      ip.cantidad_final,
      ip.origen_cambio,
      ip.created_at      AS ultima_fecha
    FROM public.app_dat_inventario_productos ip
    INNER JOIN public.app_dat_layout_almacen la ON la.id = ip.id_ubicacion
    INNER JOIN public.app_dat_almacen a         ON a.id  = la.id_almacen
    WHERE a.id_tienda = p_id_tienda
      AND a.deleted_at IS NULL
      AND la.deleted_at IS NULL
    ORDER BY
      ip.id_producto,
      COALESCE(ip.id_variante, 0),
      COALESCE(ip.id_opcion_variante, 0),
      ip.id_presentacion,
      ip.id_ubicacion,
      ip.created_at DESC,
      ip.id DESC
  )
  SELECT COUNT(*) INTO v_total FROM ultimo_inv;

  RETURN QUERY
  WITH ultimo_inv AS (
    SELECT DISTINCT ON (
      ip.id_producto,
      COALESCE(ip.id_variante, 0),
      COALESCE(ip.id_opcion_variante, 0),
      ip.id_presentacion,
      ip.id_ubicacion
    )
      ip.id              AS id_inventario,
      ip.id_producto,
      ip.id_ubicacion,
      ip.cantidad_inicial,
      ip.cantidad_final,
      ip.origen_cambio,
      ip.created_at      AS ultima_fecha
    FROM public.app_dat_inventario_productos ip
    INNER JOIN public.app_dat_layout_almacen la ON la.id = ip.id_ubicacion
    INNER JOIN public.app_dat_almacen a         ON a.id  = la.id_almacen
    WHERE a.id_tienda = p_id_tienda
      AND a.deleted_at IS NULL
      AND la.deleted_at IS NULL
    ORDER BY
      ip.id_producto,
      COALESCE(ip.id_variante, 0),
      COALESCE(ip.id_opcion_variante, 0),
      ip.id_presentacion,
      ip.id_ubicacion,
      ip.created_at DESC,
      ip.id DESC
  )
  SELECT
    u.id_inventario,
    p.id                                                         AS id_producto,
    COALESCE(p.denominacion, '(sin nombre)')::TEXT               AS producto_nombre,
    COALESCE(p.sku, '')::TEXT                                    AS sku,
    a.id                                                         AS id_almacen,
    COALESCE(a.denominacion, '(sin almacén)')::TEXT              AS almacen_nombre,
    la.id                                                        AS id_ubicacion,
    COALESCE(la.denominacion, '')::TEXT                          AS zona_nombre,
    u.cantidad_final,
    u.cantidad_inicial,
    (u.cantidad_inicial - u.cantidad_final)                      AS variacion,
    CASE
      WHEN (u.cantidad_inicial - u.cantidad_final) > 0 THEN 'bajo'
      WHEN (u.cantidad_inicial - u.cantidad_final) < 0 THEN 'subio'
      ELSE 'sin_cambio'
    END::TEXT                                                    AS direccion,
    u.origen_cambio,
    u.ultima_fecha,
    v_total                                                      AS total_count
  FROM ultimo_inv u
  INNER JOIN public.app_dat_producto       p  ON p.id  = u.id_producto
  INNER JOIN public.app_dat_layout_almacen la ON la.id = u.id_ubicacion
  INNER JOIN public.app_dat_almacen        a  ON a.id  = la.id_almacen
  ORDER BY a.denominacion ASC, u.ultima_fecha DESC, u.id_inventario DESC
  LIMIT p_limite
  OFFSET v_offset;
END;
$$;


-- ============================================================
-- RPC: fn_get_historial_producto_dia
-- Historial de un producto puntual desde 00:00:00 del día actual
-- hasta la hora actual, en orden cronológico DESC.
-- ============================================================
DROP FUNCTION IF EXISTS public.fn_get_historial_producto_dia(
  BIGINT, BIGINT, BIGINT
);

CREATE OR REPLACE FUNCTION public.fn_get_historial_producto_dia(
  p_id_tienda    BIGINT,
  p_id_producto  BIGINT,
  p_id_ubicacion BIGINT DEFAULT NULL
)
RETURNS TABLE (
  id_inventario     BIGINT,
  fecha             TIMESTAMPTZ,
  cantidad_inicial  NUMERIC,
  cantidad_final    NUMERIC,
  variacion         NUMERIC,
  direccion         TEXT,
  origen_cambio     SMALLINT,
  id_ubicacion      BIGINT,
  zona_nombre       TEXT,
  almacen_nombre    TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_inicio_dia TIMESTAMPTZ := date_trunc('day', now());
  v_fin_dia    TIMESTAMPTZ := now();
BEGIN
  RETURN QUERY
  SELECT
    ip.id                                                AS id_inventario,
    ip.created_at                                        AS fecha,
    ip.cantidad_inicial,
    ip.cantidad_final,
    (ip.cantidad_inicial - ip.cantidad_final)            AS variacion,
    CASE
      WHEN (ip.cantidad_inicial - ip.cantidad_final) > 0 THEN 'bajo'
      WHEN (ip.cantidad_inicial - ip.cantidad_final) < 0 THEN 'subio'
      ELSE 'sin_cambio'
    END::TEXT                                            AS direccion,
    ip.origen_cambio,
    la.id                                                AS id_ubicacion,
    COALESCE(la.denominacion, '')::TEXT                  AS zona_nombre,
    COALESCE(a.denominacion, '')::TEXT                   AS almacen_nombre
  FROM public.app_dat_inventario_productos ip
  INNER JOIN public.app_dat_layout_almacen la ON la.id = ip.id_ubicacion
  INNER JOIN public.app_dat_almacen        a  ON a.id  = la.id_almacen
  WHERE a.id_tienda = p_id_tienda
    AND ip.id_producto = p_id_producto
    AND (p_id_ubicacion IS NULL OR ip.id_ubicacion = p_id_ubicacion)
    AND ip.created_at >= v_inicio_dia
    AND ip.created_at <= v_fin_dia
  ORDER BY ip.created_at DESC, ip.id DESC;
END;
$$;


-- ============================================================
-- RPC: fn_get_operaciones_dia_tiempo_real
-- Lista de operaciones de la tienda desde 00:00 del día actual,
-- ordenadas por fecha DESC y paginadas. Reutiliza la lógica de
-- listar_operaciones_completas pero acotada al día actual y a
-- una sola tienda.
-- ============================================================
DROP FUNCTION IF EXISTS public.fn_get_operaciones_dia_tiempo_real(
  BIGINT, INTEGER, INTEGER
);

CREATE OR REPLACE FUNCTION public.fn_get_operaciones_dia_tiempo_real(
  p_id_tienda BIGINT,
  p_pagina    INTEGER DEFAULT 1,
  p_limite    INTEGER DEFAULT 50
)
RETURNS TABLE (
  id_operacion          BIGINT,
  tipo_operacion        TEXT,
  id_tienda             BIGINT,
  tienda_nombre         TEXT,
  usuario_nombre        TEXT,
  estado                SMALLINT,
  estado_nombre         TEXT,
  created_at            TIMESTAMPTZ,
  total                 NUMERIC,
  cantidad_items        INTEGER,
  observaciones         TEXT,
  total_count           BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_offset      INTEGER     := (GREATEST(p_pagina, 1) - 1) * p_limite;
  v_inicio_dia  TIMESTAMPTZ := date_trunc('day', now());
  v_fin_dia     TIMESTAMPTZ := now();
  v_total       BIGINT;
BEGIN
  SELECT COUNT(*) INTO v_total
  FROM public.app_dat_operaciones o
  WHERE o.id_tienda = p_id_tienda
    AND o.created_at >= v_inicio_dia
    AND o.created_at <= v_fin_dia;

  RETURN QUERY
  WITH ult_estado AS (
    SELECT DISTINCT ON (e.id_operacion)
      e.id_operacion,
      e.estado,
      e.created_at
    FROM public.app_dat_estado_operacion e
    ORDER BY e.id_operacion, e.created_at DESC
  ),
  op AS (
    SELECT
      o.id,
      o.created_at,
      o.id_tipo_operacion,
      top.denominacion                                       AS tipo_operacion_nombre,
      o.id_tienda,
      t.denominacion                                         AS tienda_nombre,
      o.uuid,
      e.estado,
      neo.denominacion                                       AS estado_nombre,
      o.observaciones
    FROM public.app_dat_operaciones o
    INNER JOIN public.app_nom_tipo_operacion top ON o.id_tipo_operacion = top.id
    INNER JOIN public.app_dat_tienda t           ON o.id_tienda = t.id
    LEFT  JOIN ult_estado e                      ON e.id_operacion = o.id
    LEFT  JOIN public.app_nom_estado_operacion neo ON neo.id = e.estado
    WHERE o.id_tienda = p_id_tienda
      AND o.created_at >= v_inicio_dia
      AND o.created_at <= v_fin_dia
  )
  SELECT
    op.id::BIGINT                                            AS id_operacion,
    COALESCE(op.tipo_operacion_nombre, '')::TEXT             AS tipo_operacion,
    op.id_tienda::BIGINT,
    COALESCE(op.tienda_nombre, '')::TEXT                     AS tienda_nombre,
    COALESCE(
      (SELECT t.nombres || ' ' || t.apellidos
         FROM app_dat_trabajadores t
        WHERE t.id = (
          SELECT DISTINCT id_trabajador FROM (
            SELECT v.id_trabajador   FROM app_dat_vendedor   v   WHERE v.uuid   = op.uuid
            UNION
            SELECT s.id_trabajador   FROM app_dat_supervisor s   WHERE s.uuid   = op.uuid
            UNION
            SELECT g.id_trabajador   FROM app_dat_gerente    g   WHERE g.uuid   = op.uuid
            UNION
            SELECT aud.id_trabajador FROM auditor            aud WHERE aud.uuid = op.uuid
            UNION
            SELECT al.id_trabajador  FROM app_dat_almacenero al  WHERE al.uuid  = op.uuid
          ) roles
          LIMIT 1
        )),
      'Sistema'
    )::TEXT                                                  AS usuario_nombre,
    COALESCE(op.estado, 0)::SMALLINT                         AS estado,
    COALESCE(op.estado_nombre, '')::TEXT                     AS estado_nombre,
    op.created_at::TIMESTAMPTZ,
    COALESCE(
      (SELECT SUM(ep.importe)
         FROM app_dat_extraccion_productos ep
        WHERE ep.id_operacion = op.id),
      (SELECT SUM(rp.precio_unitario * rp.cantidad)
         FROM app_dat_recepcion_productos rp
        WHERE rp.id_operacion = op.id),
      0
    )::NUMERIC                                               AS total,
    (
      SELECT COUNT(*)::INTEGER FROM (
        SELECT 1 FROM app_dat_extraccion_productos exy WHERE exy.id_operacion = op.id
        UNION ALL
        SELECT 1 FROM app_dat_recepcion_productos  rxy WHERE rxy.id_operacion = op.id
        UNION ALL
        SELECT 1 FROM app_dat_inventario_productos invp WHERE invp.id_control = op.id
      ) items
    )::INTEGER                                               AS cantidad_items,
    COALESCE(op.observaciones, '')::TEXT                     AS observaciones,
    v_total                                                  AS total_count
  FROM op
  ORDER BY op.created_at DESC, op.id DESC
  LIMIT p_limite
  OFFSET v_offset;
END;
$$;
