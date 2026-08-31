-- =============================================================================
-- PREVIEW: impacto de borrar almacén 330 ("Tienda Prueba", tienda 222 - Los Trujillos)
-- Solo consultas. NO modifica datos (ROLLBACK al final).
-- =============================================================================

BEGIN;

-- Validación: el almacén debe pertenecer a la tienda indicada
DO $$
DECLARE
  v_tienda_actual BIGINT;
BEGIN
  SELECT id_tienda INTO v_tienda_actual
  FROM app_dat_almacen
  WHERE id = 330;

  IF v_tienda_actual IS NULL THEN
    RAISE EXCEPTION 'No existe app_dat_almacen.id = 330';
  END IF;

  IF v_tienda_actual <> 222 THEN
    RAISE EXCEPTION
      'Almacén 330 pertenece a tienda %, no a 222. Verifique el id_almacen.',
      v_tienda_actual;
  END IF;
END $$;

CREATE TEMP TABLE tmp_purge_params AS
SELECT 330::bigint AS id_almacen, 222::bigint AS id_tienda;

CREATE TEMP TABLE tmp_layouts AS
SELECT la.id, la.denominacion
FROM app_dat_layout_almacen la
JOIN tmp_purge_params p ON la.id_almacen = p.id_almacen;

CREATE TEMP TABLE tmp_tpvs AS
SELECT t.id, t.denominacion
FROM app_dat_tpv t
JOIN tmp_purge_params p ON t.id_almacen = p.id_almacen;

CREATE TEMP TABLE tmp_cocinas AS
SELECT c.id, c.denominacion
FROM app_dat_cocina c
JOIN tmp_purge_params p ON c.id_almacen = p.id_almacen;

CREATE TEMP TABLE tmp_base_ops AS
SELECT DISTINCT x.id
FROM (
  SELECT rp.id_operacion AS id
  FROM app_dat_recepcion_productos rp
  WHERE rp.id_ubicacion IN (SELECT id FROM tmp_layouts)
    AND rp.id_operacion IS NOT NULL
  UNION
  SELECT ep.id_operacion
  FROM app_dat_extraccion_productos ep
  WHERE ep.id_ubicacion IN (SELECT id FROM tmp_layouts)
    AND ep.id_operacion IS NOT NULL
  UNION
  SELECT cp.id_operacion
  FROM app_dat_control_productos cp
  WHERE cp.id_ubicacion IN (SELECT id FROM tmp_layouts)
    AND cp.id_operacion IS NOT NULL
  UNION
  SELECT ov.id_operacion
  FROM app_dat_operacion_venta ov
  WHERE ov.id_tpv IN (SELECT id FROM tmp_tpvs)
  UNION
  SELECT cv.id_operacion
  FROM app_dat_conversion_presentacion cv
  WHERE cv.id_ubicacion IN (SELECT id FROM tmp_layouts)
    AND cv.id_operacion IS NOT NULL
  UNION
  SELECT ct.id_operacion_apertura
  FROM app_dat_caja_turno ct
  WHERE ct.id_tpv IN (SELECT id FROM tmp_tpvs)
  UNION
  SELECT ct.id_operacion_cierre
  FROM app_dat_caja_turno ct
  WHERE ct.id_operacion_cierre IS NOT NULL
    AND ct.id_tpv IN (SELECT id FROM tmp_tpvs)
  UNION
  SELECT ce.id_operacion_extraccion
  FROM app_dat_consignacion_envio ce
  JOIN tmp_purge_params p ON TRUE
  WHERE ce.id_operacion_extraccion IS NOT NULL
    AND (
      ce.id_almacen_origen = p.id_almacen
      OR ce.id_almacen_destino = p.id_almacen
      OR ce.id_almacen_recepcion_devolucion = p.id_almacen
    )
  UNION
  SELECT ce.id_operacion_recepcion
  FROM app_dat_consignacion_envio ce
  JOIN tmp_purge_params p ON TRUE
  WHERE ce.id_operacion_recepcion IS NOT NULL
    AND (
      ce.id_almacen_origen = p.id_almacen
      OR ce.id_almacen_destino = p.id_almacen
      OR ce.id_almacen_recepcion_devolucion = p.id_almacen
    )
) x
WHERE x.id IS NOT NULL;

CREATE TEMP TABLE tmp_transfer_ops AS
SELECT tr.id_operacion AS id
FROM app_dat_operacion_transferencia tr
WHERE EXISTS (
  SELECT 1 FROM app_dat_extraccion_productos ep
  WHERE ep.id_operacion = tr.id_extraccion
    AND ep.id_ubicacion IN (SELECT id FROM tmp_layouts)
)
OR EXISTS (
  SELECT 1 FROM app_dat_recepcion_productos rp
  WHERE rp.id_operacion = tr.id_recepcion
    AND rp.id_ubicacion IN (SELECT id FROM tmp_layouts)
)
UNION
SELECT tr.id_extraccion FROM app_dat_operacion_transferencia tr
WHERE EXISTS (
  SELECT 1 FROM app_dat_extraccion_productos ep
  WHERE ep.id_operacion = tr.id_extraccion
    AND ep.id_ubicacion IN (SELECT id FROM tmp_layouts)
)
UNION
SELECT tr.id_recepcion FROM app_dat_operacion_transferencia tr
WHERE EXISTS (
  SELECT 1 FROM app_dat_recepcion_productos rp
  WHERE rp.id_operacion = tr.id_recepcion
    AND rp.id_ubicacion IN (SELECT id FROM tmp_layouts)
);

CREATE TEMP TABLE tmp_ops AS
SELECT id FROM tmp_base_ops
UNION
SELECT id FROM tmp_transfer_ops;

CREATE TEMP TABLE tmp_turnos AS
SELECT ct.id FROM app_dat_caja_turno ct
WHERE ct.id_tpv IN (SELECT id FROM tmp_tpvs);

CREATE TEMP TABLE tmp_recepciones AS
SELECT rp.id FROM app_dat_recepcion_productos rp
WHERE rp.id_operacion IN (SELECT id FROM tmp_ops)
   OR rp.id_ubicacion IN (SELECT id FROM tmp_layouts);

CREATE TEMP TABLE tmp_extracciones AS
SELECT ep.id FROM app_dat_extraccion_productos ep
WHERE ep.id_operacion IN (SELECT id FROM tmp_ops)
   OR ep.id_ubicacion IN (SELECT id FROM tmp_layouts);

CREATE TEMP TABLE tmp_controles AS
SELECT cp.id FROM app_dat_control_productos cp
WHERE cp.id_operacion IN (SELECT id FROM tmp_ops)
   OR cp.id_ubicacion IN (SELECT id FROM tmp_layouts);

CREATE TEMP TABLE tmp_inventario AS
SELECT ip.id FROM app_dat_inventario_productos ip
WHERE ip.id_ubicacion IN (SELECT id FROM tmp_layouts)
   OR ip.id_recepcion IN (SELECT id FROM tmp_recepciones)
   OR ip.id_extraccion IN (SELECT id FROM tmp_extracciones)
   OR ip.id_control IN (SELECT id FROM tmp_controles)
   OR ip.id_conversion IN (
     SELECT cv.id FROM app_dat_conversion_presentacion cv
     WHERE cv.id_ubicacion IN (SELECT id FROM tmp_layouts)
   );

CREATE TEMP TABLE tmp_envios AS
SELECT ce.id FROM app_dat_consignacion_envio ce
JOIN tmp_purge_params p ON TRUE
WHERE ce.id_almacen_origen = p.id_almacen
   OR ce.id_almacen_destino = p.id_almacen
   OR ce.id_almacen_recepcion_devolucion = p.id_almacen;

CREATE TEMP TABLE tmp_contratos AS
SELECT cc.id FROM app_dat_contrato_consignacion cc
JOIN tmp_purge_params p ON TRUE
WHERE cc.id_almacen_destino = p.id_almacen
   OR cc.id_layout_destino IN (SELECT id FROM tmp_layouts);

CREATE TEMP TABLE tmp_vendedores_tpv AS
SELECT v.id, v.uuid, v.id_trabajador, t.denominacion AS tpv
FROM app_dat_vendedor v
JOIN tmp_tpvs t ON t.id = v.id_tpv;

CREATE TEMP TABLE tmp_vendedores_exclusivos AS
SELECT v.*
FROM tmp_vendedores_tpv v
WHERE NOT EXISTS (SELECT 1 FROM app_dat_gerente g WHERE g.uuid = v.uuid)
  AND NOT EXISTS (
    SELECT 1 FROM app_dat_supervisor s
    JOIN app_dat_trabajadores tr ON tr.id = s.id_trabajador
    WHERE tr.uuid = v.uuid
  )
  AND NOT EXISTS (
    SELECT 1 FROM app_dat_almacenero al
    JOIN tmp_purge_params p ON TRUE
    WHERE al.uuid = v.uuid AND al.id_almacen <> p.id_almacen
  );

CREATE TEMP TABLE tmp_transferencias AS
SELECT tr.*
FROM app_dat_operacion_transferencia tr
WHERE EXISTS (
  SELECT 1 FROM app_dat_extraccion_productos ep
  WHERE ep.id_operacion = tr.id_extraccion
    AND ep.id_ubicacion IN (SELECT id FROM tmp_layouts)
)
OR EXISTS (
  SELECT 1 FROM app_dat_recepcion_productos rp
  WHERE rp.id_operacion = tr.id_recepcion
    AND rp.id_ubicacion IN (SELECT id FROM tmp_layouts)
);

-- Resultado 1: cabecera
SELECT
  a.id,
  a.id_tienda,
  t.denominacion AS tienda,
  a.denominacion AS almacen,
  a.es_cocina
FROM app_dat_almacen a
JOIN app_dat_tienda t ON t.id = a.id_tienda
WHERE a.id = (SELECT id_almacen FROM tmp_purge_params);

-- Resultado 2: resumen
SELECT 'layouts' AS concepto, count(*)::bigint AS cantidad FROM tmp_layouts
UNION ALL SELECT 'tpvs', count(*) FROM tmp_tpvs
UNION ALL SELECT 'cocinas', count(*) FROM tmp_cocinas
UNION ALL SELECT 'operaciones_a_borrar', count(*) FROM tmp_ops
UNION ALL SELECT 'transferencias_afectadas', count(*) FROM tmp_transferencias
UNION ALL SELECT 'turnos_caja', count(*) FROM tmp_turnos
UNION ALL SELECT 'movimientos_inventario', count(*) FROM tmp_inventario
UNION ALL SELECT 'lineas_recepcion', count(*) FROM tmp_recepciones
UNION ALL SELECT 'lineas_extraccion', count(*) FROM tmp_extracciones
UNION ALL SELECT 'lineas_control', count(*) FROM tmp_controles
UNION ALL SELECT 'envios_consignacion', count(*) FROM tmp_envios
UNION ALL SELECT 'contratos_consignacion', count(*) FROM tmp_contratos
UNION ALL SELECT 'vendedores_tpv_total', count(*) FROM tmp_vendedores_tpv
UNION ALL SELECT 'vendedores_exclusivos_a_borrar', count(*) FROM tmp_vendedores_exclusivos
UNION ALL SELECT 'vendedores_no_exclusivos_solo_rol', count(*)::bigint FROM (
  SELECT 1 FROM tmp_vendedores_tpv v
  WHERE v.id NOT IN (SELECT id FROM tmp_vendedores_exclusivos)
) s
UNION ALL SELECT 'almaceneros', count(*)::bigint FROM app_dat_almacenero al
JOIN tmp_purge_params p ON al.id_almacen = p.id_almacen
ORDER BY concepto;

-- Resultado 3: TPVs y layouts
SELECT 'TPV' AS tipo, id::text, denominacion FROM tmp_tpvs
UNION ALL
SELECT 'LAYOUT', id::text, denominacion FROM tmp_layouts;

-- Resultado 4: vendedores
SELECT 'EXCLUSIVO' AS tipo, id, uuid::text, id_trabajador, tpv
FROM tmp_vendedores_exclusivos
UNION ALL
SELECT 'SOLO_ROL_VENDEDOR', v.id, v.uuid::text, v.id_trabajador, v.tpv
FROM tmp_vendedores_tpv v
WHERE v.id NOT IN (SELECT id FROM tmp_vendedores_exclusivos)
ORDER BY tipo, id;

-- Resultado 5: transferencias (solo pierna de almacén 330)
SELECT
  tr.id_operacion AS op_transferencia,
  tr.id_extraccion,
  tr.id_recepcion,
  EXISTS (
    SELECT 1 FROM app_dat_extraccion_productos ep
    WHERE ep.id_operacion = tr.id_extraccion
      AND ep.id_ubicacion IN (SELECT id FROM tmp_layouts)
  ) AS borra_extraccion,
  EXISTS (
    SELECT 1 FROM app_dat_recepcion_productos rp
    WHERE rp.id_operacion = tr.id_recepcion
      AND rp.id_ubicacion IN (SELECT id FROM tmp_layouts)
  ) AS borra_recepcion
FROM tmp_transferencias tr
ORDER BY tr.id_operacion;

-- Resultado 6: muestra de operaciones
SELECT
  o.id,
  top.denominacion AS tipo_operacion,
  o.created_at
FROM app_dat_operaciones o
JOIN app_nom_tipo_operacion top ON top.id = o.id_tipo_operacion
WHERE o.id IN (SELECT id FROM tmp_ops)
ORDER BY o.created_at DESC
LIMIT 500;

ROLLBACK;
