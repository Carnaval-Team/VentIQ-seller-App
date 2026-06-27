-- ============================================================================
-- FUNCIÓN: get_product_movements_v3
-- Variante de get_product_movements_v2 que incluye movimientos para productos
-- de tipo servicio o elaborado, los cuales no generan registros en
-- app_dat_inventario_productos pero sí guardan extracciones en
-- app_dat_extraccion_productos.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_product_movements_v3(
  p_id_producto       BIGINT,
  p_fecha_desde       DATE    DEFAULT NULL,
  p_fecha_hasta       DATE    DEFAULT NULL,
  p_tipo_operacion_id BIGINT  DEFAULT NULL,
  p_id_almacen        BIGINT  DEFAULT NULL,
  p_offset            INTEGER DEFAULT 0,
  p_limit             INTEGER DEFAULT 20
)
RETURNS TABLE (
  id                     BIGINT,
  id_operacion           BIGINT,
  tipo_movimiento        VARCHAR,
  tipo_operacion_id      BIGINT,
  tipo_operacion         VARCHAR,
  cantidad               NUMERIC,
  precio_unitario        NUMERIC,
  costo_real             NUMERIC,
  importe_real           NUMERIC,
  fecha                  TIMESTAMP WITH TIME ZONE,
  usuario_uuid           UUID,
  ubicacion_id           BIGINT,
  ubicacion_nombre       VARCHAR,
  almacen_id             BIGINT,
  almacen_nombre         VARCHAR,
  proveedor_id           BIGINT,
  proveedor_nombre       VARCHAR,
  observaciones          VARCHAR,
  entregado_por          VARCHAR,
  recibido_por           VARCHAR,
  autorizado_por         VARCHAR,
  motivo                 VARCHAR,
  observaciones_extraccion VARCHAR,
  comentario_completado  VARCHAR,
  cantidad_inicial       NUMERIC,
  cantidad_final         NUMERIC,
  estado_operacion       SMALLINT,
  estado_operacion_nombre VARCHAR,
  total_count            BIGINT
) AS $$
DECLARE
  v_rec RECORD;
BEGIN

  -- ----------------------------------------------------------------
  -- PASO 1: Detectar registros con información incompleta y loguear
  -- ----------------------------------------------------------------
  FOR v_rec IN
    SELECT
      inv.id              AS id_inventario,
      inv.id_recepcion,
      inv.id_extraccion,
      inv.id_control,
      CASE
        WHEN inv.id_recepcion  IS NOT NULL THEN 'recepcion'
        WHEN inv.id_extraccion IS NOT NULL THEN 'extraccion'
        WHEN inv.id_control    IS NOT NULL THEN 'control'
        ELSE 'sin_tipo'
      END                 AS tipo_mov,
      -- Recepción: ¿tiene operación padre?
      CASE
        WHEN inv.id_recepcion IS NOT NULL AND rp_chk.id_operacion IS NULL
          THEN 'recepcion_productos sin id_operacion'
        WHEN inv.id_extraccion IS NOT NULL AND ep_chk.id_operacion IS NULL
          THEN 'extraccion_productos sin id_operacion'
        WHEN inv.id_control IS NOT NULL AND cp_chk.id_operacion IS NULL
          THEN 'control_productos sin id_operacion'
        WHEN inv.id_recepcion  IS NULL
         AND inv.id_extraccion IS NULL
         AND inv.id_control    IS NULL
          THEN 'inventario sin ningun FK de movimiento'
        ELSE NULL
      END                 AS problema
    FROM app_dat_inventario_productos inv
    LEFT JOIN app_dat_recepcion_productos  rp_chk ON rp_chk.id = inv.id_recepcion
    LEFT JOIN app_dat_extraccion_productos ep_chk ON ep_chk.id = inv.id_extraccion
    LEFT JOIN app_dat_control_productos    cp_chk ON cp_chk.id = inv.id_control
    WHERE inv.id_producto = p_id_producto
  LOOP
    IF v_rec.problema IS NOT NULL THEN
      RAISE NOTICE '[get_product_movements_v2] REGISTRO INCOMPLETO - id_inventario=% tipo=% problema="%"',
        v_rec.id_inventario,
        v_rec.tipo_mov,
        v_rec.problema;
    END IF;
  END LOOP;

  -- ----------------------------------------------------------------
  -- PASO 2: Consulta principal con la nueva lógica de navegación
  -- ----------------------------------------------------------------
  RETURN QUERY
  WITH producto_info AS (
    SELECT
      COALESCE(p.es_servicio, false) AS es_servicio,
      COALESCE(p.es_elaborado, false) AS es_elaborado
    FROM app_dat_producto p
    WHERE p.id = p_id_producto
  ),
  -- Movimientos normales: partir de inventario y resolver detalle
  movimientos_inventario AS (
    SELECT
      inv.id                  AS inv_id,
      inv.id_producto,
      inv.cantidad_inicial,
      inv.cantidad_final,
      inv.id_proveedor        AS inv_id_proveedor,
      inv.id_ubicacion        AS inv_id_ubicacion,
      inv.created_at          AS inv_created_at,

      -- Tipo de movimiento
      CASE
        WHEN inv.id_recepcion  IS NOT NULL THEN 'Recepción'::VARCHAR
        WHEN inv.id_extraccion IS NOT NULL THEN 'Extracción'::VARCHAR
        WHEN inv.id_control    IS NOT NULL THEN 'Control'::VARCHAR
        ELSE 'Reajuste'::VARCHAR
      END                     AS tipo_movimiento,

      -- IDs de detalle
      inv.id_recepcion,
      inv.id_extraccion,
      inv.id_control,

      -- Campos de recepción
      rp.id                   AS rp_id,
      rp.id_operacion         AS rp_id_operacion,
      rp.cantidad             AS rp_cantidad,
      rp.precio_unitario      AS rp_precio_unitario,
      rp.costo_real           AS rp_costo_real,
      rp.id_ubicacion         AS rp_id_ubicacion,
      rp.id_proveedor         AS rp_id_proveedor,
      rp.created_at           AS rp_created_at,

      -- Campos de extracción
      ep.id                   AS ep_id,
      ep.id_operacion         AS ep_id_operacion,
      ep.cantidad             AS ep_cantidad,
      ep.precio_unitario      AS ep_precio_unitario,
      ep.importe_real         AS ep_importe_real,
      ep.id_ubicacion         AS ep_id_ubicacion,
      ep.created_at           AS ep_created_at,

      -- Campos de control
      cp.id                   AS cp_id,
      cp.id_operacion         AS cp_id_operacion,
      cp.cantidad             AS cp_cantidad,
      cp.id_ubicacion         AS cp_id_ubicacion,
      cp.created_at           AS cp_created_at

    FROM app_dat_inventario_productos inv
    LEFT JOIN app_dat_recepcion_productos  rp ON rp.id = inv.id_recepcion
    LEFT JOIN app_dat_extraccion_productos ep ON ep.id = inv.id_extraccion
    LEFT JOIN app_dat_control_productos    cp ON cp.id = inv.id_control
    WHERE inv.id_producto = p_id_producto
      AND (p_fecha_desde IS NULL OR inv.created_at::DATE >= p_fecha_desde)
      AND (p_fecha_hasta IS NULL OR inv.created_at::DATE <= p_fecha_hasta)
      -- Garantía: un registro inv nunca debe tener más de una FK activa
      -- Si por error de datos tuviera dos, tomamos solo la primera encontrada
      AND (
        (inv.id_recepcion IS NOT NULL AND inv.id_extraccion IS NULL AND inv.id_control IS NULL)
        OR (inv.id_extraccion IS NOT NULL AND inv.id_recepcion IS NULL AND inv.id_control IS NULL)
        OR (inv.id_control IS NOT NULL AND inv.id_recepcion IS NULL AND inv.id_extraccion IS NULL)
        OR (inv.id_recepcion IS NULL AND inv.id_extraccion IS NULL AND inv.id_control IS NULL)
      )
  ),
  -- Extracciones directas para productos de servicio o elaborado
  -- (no generan movimiento en app_dat_inventario_productos)
  extracciones_servicio_elaborado AS (
    SELECT
      ep.id                   AS inv_id,
      ep.id_producto,
      NULL::NUMERIC           AS cantidad_inicial,
      NULL::NUMERIC           AS cantidad_final,
      NULL::BIGINT            AS inv_id_proveedor,
      ep.id_ubicacion         AS inv_id_ubicacion,
      ep.created_at           AS inv_created_at,
      'Extracción'::VARCHAR   AS tipo_movimiento,
      NULL::BIGINT            AS id_recepcion,
      ep.id                   AS id_extraccion,
      NULL::BIGINT            AS id_control,
      NULL::BIGINT            AS rp_id,
      NULL::BIGINT            AS rp_id_operacion,
      NULL::NUMERIC           AS rp_cantidad,
      NULL::NUMERIC           AS rp_precio_unitario,
      NULL::NUMERIC           AS rp_costo_real,
      NULL::BIGINT            AS rp_id_ubicacion,
      NULL::BIGINT            AS rp_id_proveedor,
      NULL::TIMESTAMP WITH TIME ZONE AS rp_created_at,
      ep.id                   AS ep_id,
      ep.id_operacion         AS ep_id_operacion,
      ep.cantidad             AS ep_cantidad,
      ep.precio_unitario      AS ep_precio_unitario,
      ep.importe_real         AS ep_importe_real,
      ep.id_ubicacion         AS ep_id_ubicacion,
      ep.created_at           AS ep_created_at,
      NULL::BIGINT            AS cp_id,
      NULL::BIGINT            AS cp_id_operacion,
      NULL::NUMERIC           AS cp_cantidad,
      NULL::BIGINT            AS cp_id_ubicacion,
      NULL::TIMESTAMP WITH TIME ZONE AS cp_created_at
    FROM app_dat_extraccion_productos ep
    CROSS JOIN producto_info pi
    WHERE ep.id_producto = p_id_producto
      AND (pi.es_servicio = true OR pi.es_elaborado = true)
      AND (p_fecha_desde IS NULL OR ep.created_at::DATE >= p_fecha_desde)
      AND (p_fecha_hasta IS NULL OR ep.created_at::DATE <= p_fecha_hasta)
  ),
  -- Base unificada: movimientos de inventario + extracciones directas de servicios/elaborados
  base AS (
    SELECT * FROM movimientos_inventario
    UNION ALL
    SELECT * FROM extracciones_servicio_elaborado
  ),
  con_operacion AS (
    -- Resolver la operación padre directamente desde el detalle (solo registros con FK)
    SELECT
      b.*,
      COALESCE(b.rp_id_operacion, b.ep_id_operacion, b.cp_id_operacion) AS id_op
    FROM base b
    WHERE COALESCE(b.rp_id_operacion, b.ep_id_operacion, b.cp_id_operacion) IS NOT NULL
  ),
  -- Separar en dos: ajustes (con registro en app_dat_ajuste_inventario) y cancelaciones
  reajustes_reales AS (
    SELECT
      b.inv_id, b.id_producto, b.cantidad_inicial, b.cantidad_final,
      b.inv_id_proveedor, b.inv_created_at,
      b.tipo_movimiento,
      b.id_recepcion, b.id_extraccion, b.id_control,
      b.rp_id, b.ep_id, b.cp_id,
      b.rp_cantidad, b.ep_cantidad, b.cp_cantidad,
      b.rp_precio_unitario, b.ep_precio_unitario,
      b.rp_costo_real, b.ep_importe_real,
      b.rp_created_at, b.ep_created_at, b.cp_created_at,
      b.rp_id_operacion, b.ep_id_operacion, b.cp_id_operacion,
      -- Intentar encontrar ajuste por id_producto + created_at (misma transacción)
      aj.id_operacion        AS aj_id_operacion,
      aj.id                  AS aj_id,
      op_aj.observaciones    AS aj_observaciones,
      nto_aj.denominacion    AS aj_tipo_op_nombre,
      op_aj.id_tipo_operacion  AS aj_id_tipo_operacion,
      aj.id_ubicacion          AS aj_id_ubicacion,
      aj_la.denominacion       AS aj_la_nombre,
      aj_la.id_almacen         AS aj_la_id_almacen,
      aj_alm.denominacion      AS aj_alm_nombre,
      est_aj.comentario        AS aj_comentario_completado,
      -- ubicación del registro inventario (para cancelaciones)
      b.inv_id_ubicacion       AS canc_id_ubicacion,
      inv_la.denominacion      AS canc_la_nombre,
      inv_la.id_almacen        AS canc_la_id_almacen,
      inv_alm.denominacion     AS canc_alm_nombre
    FROM base b
    LEFT JOIN LATERAL (
      SELECT aj2.id, aj2.id_operacion, aj2.id_ubicacion
      FROM app_dat_ajuste_inventario aj2
      WHERE aj2.id_producto  = b.id_producto
        AND aj2.id_ubicacion = b.inv_id_ubicacion
        -- mismo segundo de creación (misma transacción SQL)
        AND date_trunc('second', aj2.created_at) = date_trunc('second', b.inv_created_at)
      ORDER BY aj2.id DESC
      LIMIT 1
    ) aj ON TRUE
    LEFT JOIN app_dat_operaciones    op_aj  ON op_aj.id  = aj.id_operacion
    LEFT JOIN app_nom_tipo_operacion nto_aj ON nto_aj.id = op_aj.id_tipo_operacion
    -- Resolver ubicación del ajuste → almacén
    LEFT JOIN app_dat_layout_almacen aj_la  ON aj_la.id  = aj.id_ubicacion
    LEFT JOIN app_dat_almacen        aj_alm ON aj_alm.id = aj_la.id_almacen
    -- Resolver ubicación del inventario (cancelaciones) → almacén
    LEFT JOIN app_dat_layout_almacen inv_la  ON inv_la.id  = b.inv_id_ubicacion
    LEFT JOIN app_dat_almacen        inv_alm ON inv_alm.id = inv_la.id_almacen
    LEFT JOIN LATERAL (
      SELECT e.comentario
      FROM app_dat_estado_operacion e
      WHERE e.id_operacion = aj.id_operacion
        AND e.comentario IS NOT NULL
        AND TRIM(e.comentario) <> ''
      ORDER BY e.id DESC
      LIMIT 1
    ) est_aj ON aj.id_operacion IS NOT NULL
    WHERE b.id_recepcion IS NULL
      AND b.id_extraccion IS NULL
      AND b.id_control    IS NULL
  ),
  -- Marcador de ajuste vs cancelacion (para usar en UNION)
  solo_reajustes AS (
    SELECT *
    FROM reajustes_reales
    WHERE aj_id IS NULL  -- sin registro en ajuste = cancelación de operación
  ),
  solo_ajustes AS (
    SELECT *
    FROM reajustes_reales
    WHERE aj_id IS NOT NULL  -- con registro en ajuste = ajuste de inventario
  ),
  -- Dummy para compatibilidad de nombre
  reajustes AS (
    SELECT * FROM solo_reajustes
  ),
  ajustes AS (
    SELECT * FROM solo_ajustes
  ),
  con_tipo AS (
    -- Unir con app_dat_operaciones y app_nom_tipo_operacion
    SELECT
      co.*,
      op.id_tipo_operacion,
      op.uuid             AS op_uuid,
      op.observaciones    AS op_observaciones,
      nto.denominacion    AS tipo_op_nombre,

      -- Detalle de recepción / extracción
      orec.entregado_por  AS entregado_por,
      orec.recibido_por   AS recibido_por,
      oe.autorizado_por   AS autorizado_por,
      nme.denominacion    AS motivo,
      oe.observaciones    AS observaciones_extraccion,
      est_comp.comentario AS comentario_completado,

      -- Almacén: prioridad → ubicación del detalle → TPV de venta
      COALESCE(co.rp_id_ubicacion, co.ep_id_ubicacion, co.cp_id_ubicacion) AS id_ubicacion_detalle,

      -- Almacén via TPV (ventas)
      tpv.id_almacen      AS tpv_id_almacen

    FROM con_operacion co
    INNER JOIN app_dat_operaciones    op  ON op.id  = co.id_op
    INNER JOIN app_nom_tipo_operacion nto ON nto.id = op.id_tipo_operacion

    LEFT JOIN app_dat_operacion_recepcion  orec ON orec.id_operacion = co.id_op
    LEFT JOIN app_dat_operacion_extraccion  oe   ON oe.id_operacion   = co.id_op
    LEFT JOIN app_nom_motivo_extraccion     nme  ON nme.id            = oe.id_motivo_operacion
    LEFT JOIN LATERAL (
      SELECT e.comentario
      FROM app_dat_estado_operacion e
      WHERE e.id_operacion = co.id_op
        AND e.comentario IS NOT NULL
        AND TRIM(e.comentario) <> ''
      ORDER BY e.id DESC
      LIMIT 1
    ) est_comp ON TRUE

    -- Venta: op → app_dat_operacion_venta → app_dat_tpv
    LEFT JOIN app_dat_operacion_venta  ov  ON ov.id_operacion = co.id_op
    LEFT JOIN app_dat_tpv              tpv ON tpv.id = ov.id_tpv
  ),
  con_ubicacion AS (
    -- Resolver ubicación → almacén
    SELECT
      ct.*,
      la.id               AS la_id,
      la.denominacion     AS la_nombre,
      la.id_almacen       AS la_id_almacen,
      alm.denominacion    AS alm_nombre
    FROM con_tipo ct
    LEFT JOIN app_dat_layout_almacen la  ON la.id  = ct.id_ubicacion_detalle
    LEFT JOIN app_dat_almacen        alm ON alm.id = la.id_almacen
  ),
  con_proveedor AS (
    -- Resolver proveedor
    SELECT
      cu.*,
      prov.id             AS prov_id,
      prov.denominacion   AS prov_nombre
    FROM con_ubicacion cu
    LEFT JOIN app_dat_proveedor prov
      ON prov.id = COALESCE(cu.rp_id_proveedor, cu.inv_id_proveedor)
  ),
  filtrado AS (
    -- Registros con operacion: aplicar filtros de tipo_operacion y almacén
    SELECT cp2.*
    FROM con_proveedor cp2
    WHERE (p_tipo_operacion_id IS NULL OR cp2.id_tipo_operacion = p_tipo_operacion_id)
      AND (
        p_id_almacen IS NULL
        OR cp2.la_id_almacen   = p_id_almacen
        OR cp2.tpv_id_almacen  = p_id_almacen
      )
  ),
  todos AS (
    -- Unir movimientos normales con reajustes
    -- Los reajustes no se filtran por tipo_operacion ni almacén (no tienen esos datos)
    SELECT
      f.inv_id, f.id_op, f.tipo_movimiento,
      f.id_tipo_operacion, f.tipo_op_nombre,
      f.rp_id, f.ep_id, f.cp_id,
      f.rp_cantidad, f.ep_cantidad, f.cp_cantidad,
      f.rp_precio_unitario, f.ep_precio_unitario,
      f.rp_costo_real, f.ep_importe_real,
      f.rp_created_at, f.ep_created_at, f.cp_created_at,
      f.inv_created_at,
      f.op_uuid, f.id_ubicacion_detalle,
      f.la_nombre, f.la_id_almacen, f.alm_nombre,
      f.prov_id, f.prov_nombre,
      f.op_observaciones,
      f.entregado_por, f.recibido_por, f.autorizado_por,
      f.motivo, f.observaciones_extraccion, f.comentario_completado,
      f.cantidad_inicial, f.cantidad_final
    FROM filtrado f

    UNION ALL

    -- Cancelaciones de operación (sin ajuste en app_dat_ajuste_inventario)
    SELECT
      r.inv_id,
      NULL::BIGINT                            AS id_op,
      'Reajuste'::VARCHAR                     AS tipo_movimiento,
      NULL::BIGINT                            AS id_tipo_operacion,
      'Reajuste de cancelación'::VARCHAR      AS tipo_op_nombre,
      NULL::BIGINT AS rp_id, NULL::BIGINT AS ep_id, NULL::BIGINT AS cp_id,
      NULL::NUMERIC AS rp_cantidad, NULL::NUMERIC AS ep_cantidad, NULL::NUMERIC AS cp_cantidad,
      NULL::NUMERIC AS rp_precio_unitario, NULL::NUMERIC AS ep_precio_unitario,
      NULL::NUMERIC AS rp_costo_real, NULL::NUMERIC AS ep_importe_real,
      NULL::TIMESTAMP WITH TIME ZONE AS rp_created_at,
      NULL::TIMESTAMP WITH TIME ZONE AS ep_created_at,
      NULL::TIMESTAMP WITH TIME ZONE AS cp_created_at,
      r.inv_created_at,
      NULL::UUID                              AS op_uuid,
      r.canc_id_ubicacion                    AS id_ubicacion_detalle,
      r.canc_la_nombre::VARCHAR               AS la_nombre,
      r.canc_la_id_almacen                    AS la_id_almacen,
      r.canc_alm_nombre::VARCHAR              AS alm_nombre,
      NULL::BIGINT                            AS prov_id,
      NULL::VARCHAR                           AS prov_nombre,
      NULL::VARCHAR                           AS op_observaciones,
      NULL::VARCHAR AS entregado_por, NULL::VARCHAR AS recibido_por,
      NULL::VARCHAR AS autorizado_por, NULL::VARCHAR AS motivo,
      NULL::VARCHAR AS observaciones_extraccion, NULL::VARCHAR AS comentario_completado,
      r.cantidad_inicial, r.cantidad_final
    FROM reajustes r
    WHERE p_tipo_operacion_id IS NULL
      AND (p_id_almacen IS NULL OR r.canc_la_id_almacen = p_id_almacen)

    UNION ALL

    -- Ajustes de inventario (con registro en app_dat_ajuste_inventario)
    SELECT
      a.inv_id,
      a.aj_id_operacion                       AS id_op,
      'Ajuste'::VARCHAR                       AS tipo_movimiento,
      a.aj_id_tipo_operacion                  AS id_tipo_operacion,
      COALESCE(a.aj_tipo_op_nombre, 'Ajuste de inventario')::VARCHAR AS tipo_op_nombre,
      NULL::BIGINT AS rp_id, NULL::BIGINT AS ep_id, NULL::BIGINT AS cp_id,
      NULL::NUMERIC AS rp_cantidad, NULL::NUMERIC AS ep_cantidad, NULL::NUMERIC AS cp_cantidad,
      NULL::NUMERIC AS rp_precio_unitario, NULL::NUMERIC AS ep_precio_unitario,
      NULL::NUMERIC AS rp_costo_real, NULL::NUMERIC AS ep_importe_real,
      NULL::TIMESTAMP WITH TIME ZONE AS rp_created_at,
      NULL::TIMESTAMP WITH TIME ZONE AS ep_created_at,
      NULL::TIMESTAMP WITH TIME ZONE AS cp_created_at,
      a.inv_created_at,
      NULL::UUID                              AS op_uuid,
      a.aj_id_ubicacion                       AS id_ubicacion_detalle,
      a.aj_la_nombre::VARCHAR                 AS la_nombre,
      a.aj_la_id_almacen                      AS la_id_almacen,
      a.aj_alm_nombre::VARCHAR                AS alm_nombre,
      NULL::BIGINT                            AS prov_id,
      NULL::VARCHAR                           AS prov_nombre,
      a.aj_observaciones::VARCHAR             AS op_observaciones,
      NULL::VARCHAR AS entregado_por, NULL::VARCHAR AS recibido_por,
      NULL::VARCHAR AS autorizado_por, NULL::VARCHAR AS motivo,
      NULL::VARCHAR AS observaciones_extraccion,
      a.aj_comentario_completado::VARCHAR     AS comentario_completado,
      a.cantidad_inicial, a.cantidad_final
    FROM ajustes a
    WHERE (p_tipo_operacion_id IS NULL OR a.aj_id_tipo_operacion = p_tipo_operacion_id)
      AND (p_id_almacen IS NULL OR a.aj_la_id_almacen = p_id_almacen)
  )
  SELECT
    t.inv_id::BIGINT,
    t.id_op::BIGINT,
    t.tipo_movimiento::VARCHAR,
    t.id_tipo_operacion::BIGINT,
    t.tipo_op_nombre::VARCHAR,
    COALESCE(t.rp_cantidad,  t.ep_cantidad,  t.cp_cantidad, (t.cantidad_final - t.cantidad_inicial))::NUMERIC,
    COALESCE(t.rp_precio_unitario, t.ep_precio_unitario)::NUMERIC,
    t.rp_costo_real::NUMERIC,
    t.ep_importe_real::NUMERIC,
    COALESCE(t.rp_created_at, t.ep_created_at, t.cp_created_at, t.inv_created_at)::TIMESTAMP WITH TIME ZONE,
    t.op_uuid::UUID,
    t.id_ubicacion_detalle::BIGINT,
    t.la_nombre::VARCHAR,
    t.la_id_almacen::BIGINT,
    t.alm_nombre::VARCHAR,
    t.prov_id::BIGINT,
    t.prov_nombre::VARCHAR,
    t.op_observaciones::VARCHAR,
    t.entregado_por::VARCHAR,
    t.recibido_por::VARCHAR,
    t.autorizado_por::VARCHAR,
    t.motivo::VARCHAR,
    t.observaciones_extraccion::VARCHAR,
    t.comentario_completado::VARCHAR,
    t.cantidad_inicial::NUMERIC,
    t.cantidad_final::NUMERIC,
    eo.estado::SMALLINT,
    CASE
      WHEN t.id_op IS NULL     THEN 'Reajuste'::VARCHAR
      WHEN eo.estado = 1       THEN 'Pendiente'::VARCHAR
      WHEN eo.estado = 2       THEN 'Completada'::VARCHAR
      WHEN eo.estado = 3       THEN 'Devuelta'::VARCHAR
      WHEN eo.estado = 4       THEN 'Cancelada'::VARCHAR
      ELSE 'Desconocido'::VARCHAR
    END::VARCHAR,
    COUNT(*) OVER ()::BIGINT
  FROM todos t
  LEFT JOIN LATERAL (
    SELECT est.estado
    FROM app_dat_estado_operacion est
    WHERE est.id_operacion = t.id_op
    ORDER BY est.id DESC
    LIMIT 1
  ) eo ON TRUE
  ORDER BY t.inv_id ASC
  LIMIT  p_limit
  OFFSET p_offset;

END;
$$ LANGUAGE plpgsql;
