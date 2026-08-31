-- =============================================================================
-- EJECUCIÓN: hard delete almacén 330 y todo lo relacionado
-- Almacén: 330 | Tienda: 222 | "Tienda Prueba" (Los Trujillos)
--
-- ANTES:
--   1) Ejecutar purge_almacen_330_preview.sql
--   2) Backup / snapshot
--
-- Política:
--   - Hard delete de operaciones del almacén
--   - Transferencias: solo pierna de almacén 330 (la contraparte queda)
--   - Borra TPVs del almacén
--   - Borra vendedores exclusivos (fn_eliminar_trabajador_completo)
--   - Quita rol vendedor a quienes tienen otro rol (ej. gerente)
--   - Consignación ligada: borrado completo
--   - Cocina: borrado completo si aplica
--   - Borra app_dat_almacen
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

CREATE TEMP TABLE tmp_purge_params ON COMMIT DROP AS
SELECT 330::bigint AS id_almacen, 222::bigint AS id_tienda;

CREATE TEMP TABLE tmp_layouts ON COMMIT DROP AS
SELECT la.id
FROM app_dat_layout_almacen la
JOIN tmp_purge_params p ON la.id_almacen = p.id_almacen;

CREATE TEMP TABLE tmp_tpvs ON COMMIT DROP AS
SELECT t.id
FROM app_dat_tpv t
JOIN tmp_purge_params p ON t.id_almacen = p.id_almacen;

CREATE TEMP TABLE tmp_cocinas ON COMMIT DROP AS
SELECT c.id
FROM app_dat_cocina c
JOIN tmp_purge_params p ON c.id_almacen = p.id_almacen;

CREATE TEMP TABLE tmp_base_ops ON COMMIT DROP AS
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

CREATE TEMP TABLE tmp_transfer_ops ON COMMIT DROP AS
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

CREATE TEMP TABLE tmp_ops ON COMMIT DROP AS
SELECT id FROM tmp_base_ops
UNION
SELECT id FROM tmp_transfer_ops;

CREATE TEMP TABLE tmp_transferencias ON COMMIT DROP AS
SELECT tr.id_operacion, tr.id_recepcion, tr.id_extraccion
FROM app_dat_operacion_transferencia tr
WHERE tr.id_operacion IN (SELECT id FROM tmp_transfer_ops)
   OR tr.id_recepcion IN (SELECT id FROM tmp_transfer_ops)
   OR tr.id_extraccion IN (SELECT id FROM tmp_transfer_ops);

CREATE TEMP TABLE tmp_turnos ON COMMIT DROP AS
SELECT ct.id FROM app_dat_caja_turno ct
WHERE ct.id_tpv IN (SELECT id FROM tmp_tpvs);

CREATE TEMP TABLE tmp_ventas ON COMMIT DROP AS
SELECT ov.id_operacion FROM app_dat_operacion_venta ov
WHERE ov.id_operacion IN (SELECT id FROM tmp_ops);

CREATE TEMP TABLE tmp_recepciones ON COMMIT DROP AS
SELECT rp.id FROM app_dat_recepcion_productos rp
WHERE rp.id_operacion IN (SELECT id FROM tmp_ops)
   OR rp.id_ubicacion IN (SELECT id FROM tmp_layouts);

CREATE TEMP TABLE tmp_extracciones ON COMMIT DROP AS
SELECT ep.id FROM app_dat_extraccion_productos ep
WHERE ep.id_operacion IN (SELECT id FROM tmp_ops)
   OR ep.id_ubicacion IN (SELECT id FROM tmp_layouts);

CREATE TEMP TABLE tmp_controles ON COMMIT DROP AS
SELECT cp.id FROM app_dat_control_productos cp
WHERE cp.id_operacion IN (SELECT id FROM tmp_ops)
   OR cp.id_ubicacion IN (SELECT id FROM tmp_layouts);

CREATE TEMP TABLE tmp_inventario ON COMMIT DROP AS
SELECT ip.id FROM app_dat_inventario_productos ip
WHERE ip.id_ubicacion IN (SELECT id FROM tmp_layouts)
   OR ip.id_recepcion IN (SELECT id FROM tmp_recepciones)
   OR ip.id_extraccion IN (SELECT id FROM tmp_extracciones)
   OR ip.id_control IN (SELECT id FROM tmp_controles)
   OR ip.id_conversion IN (
     SELECT cv.id FROM app_dat_conversion_presentacion cv
     WHERE cv.id_ubicacion IN (SELECT id FROM tmp_layouts)
   );

CREATE TEMP TABLE tmp_envios ON COMMIT DROP AS
SELECT ce.id FROM app_dat_consignacion_envio ce
JOIN tmp_purge_params p ON TRUE
WHERE ce.id_almacen_origen = p.id_almacen
   OR ce.id_almacen_destino = p.id_almacen
   OR ce.id_almacen_recepcion_devolucion = p.id_almacen;

CREATE TEMP TABLE tmp_contratos ON COMMIT DROP AS
SELECT cc.id FROM app_dat_contrato_consignacion cc
JOIN tmp_purge_params p ON TRUE
WHERE cc.id_almacen_destino = p.id_almacen
   OR cc.id_layout_destino IN (SELECT id FROM tmp_layouts);

CREATE TEMP TABLE tmp_vendedores_exclusivos ON COMMIT DROP AS
SELECT v.id, v.id_trabajador, v.uuid
FROM app_dat_vendedor v
WHERE v.id_tpv IN (SELECT id FROM tmp_tpvs)
  AND NOT EXISTS (SELECT 1 FROM app_dat_gerente g WHERE g.uuid = v.uuid)
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

-- 1) Cocina / restaurante
DELETE FROM app_dat_comanda_item ci
WHERE ci.id_comanda IN (
  SELECT cm.id FROM app_dat_comanda cm
  WHERE cm.id_cocina IN (SELECT id FROM tmp_cocinas)
     OR cm.id_tpv IN (SELECT id FROM tmp_tpvs)
);

DELETE FROM app_dat_comanda cm
WHERE cm.id_cocina IN (SELECT id FROM tmp_cocinas)
   OR cm.id_tpv IN (SELECT id FROM tmp_tpvs);

DELETE FROM app_dat_mesa_cuenta_item mci
WHERE mci.id_ubicacion IN (SELECT id FROM tmp_layouts)
   OR mci.id_cocina IN (SELECT id FROM tmp_cocinas);

-- 2) Caja / pagos / marketing / garantías / logs
DELETE FROM app_cont_egresos_procesados ep
WHERE ep.id_egreso IN (
  SELECT e.id FROM app_dat_entregas_parciales_caja e
  WHERE e.id_turno IN (SELECT id FROM tmp_turnos)
);

DELETE FROM app_dat_entregas_parciales_caja e
WHERE e.id_turno IN (SELECT id FROM tmp_turnos);

DELETE FROM app_dat_turno_trabajadores tt
WHERE tt.id_turno IN (SELECT id FROM tmp_turnos);

DELETE FROM app_dat_movimiento_consignacion mc
WHERE mc.id_operacion_venta IN (SELECT id_operacion FROM tmp_ventas);

DELETE FROM app_dat_pago_venta pv
WHERE pv.id_operacion_venta IN (SELECT id_operacion FROM tmp_ventas);

DELETE FROM app_mkt_cliente_promociones
WHERE id_operacion IN (SELECT id FROM tmp_ops);

DELETE FROM app_mkt_eventos_fidelizacion
WHERE id_operacion IN (SELECT id FROM tmp_ops);

DELETE FROM paqueteria_ordenes
WHERE id_operacion IN (SELECT id FROM tmp_ops);

DELETE FROM app_dat_garantia_uso gu
WHERE gu.id_operacion_devolucion IN (SELECT id FROM tmp_ops)
   OR gu.id_garantia_venta IN (
     SELECT gv.id FROM app_dat_garantia_venta gv
     WHERE gv.id_venta_original IN (SELECT id FROM tmp_ops)
   );

DELETE FROM app_dat_garantia_venta gv
WHERE gv.id_venta_original IN (SELECT id FROM tmp_ops);

DELETE FROM app_dat_log_modificacion_orden
WHERE id_operacion IN (SELECT id FROM tmp_ops);

DELETE FROM app_dat_historial_pre_asignaciones
WHERE id_operacion IN (SELECT id FROM tmp_ops);

DELETE FROM app_dat_operacion_offline_idempotencia
WHERE id_operacion IN (SELECT id FROM tmp_ops);

-- 3) Consignación
DELETE FROM app_dat_consignacion_envio_movimiento em
WHERE em.id_envio IN (SELECT id FROM tmp_envios);

DELETE FROM app_dat_consignacion_envio_producto ep
WHERE ep.id_envio IN (SELECT id FROM tmp_envios);

DELETE FROM app_dat_consignacion_envio ce
WHERE ce.id IN (SELECT id FROM tmp_envios);

DELETE FROM app_dat_movimiento_consignacion mc
WHERE mc.id_producto_consignacion IN (
  SELECT pc.id FROM app_dat_producto_consignacion pc
  WHERE pc.id_contrato IN (SELECT id FROM tmp_contratos)
);

DELETE FROM app_dat_producto_consignacion_duplicado
WHERE id_contrato_consignacion IN (SELECT id FROM tmp_contratos);

DELETE FROM app_dat_liquidacion_consignacion
WHERE id_contrato IN (SELECT id FROM tmp_contratos);

DELETE FROM app_dat_consignacion_zona cz
WHERE cz.id_contrato IN (SELECT id FROM tmp_contratos)
   OR cz.id_zona IN (SELECT id FROM tmp_layouts);

DELETE FROM app_dat_producto_consignacion
WHERE id_contrato IN (SELECT id FROM tmp_contratos)
   OR id_ubicacion_origen IN (SELECT id FROM tmp_layouts);

DELETE FROM app_dat_contrato_consignacion
WHERE id IN (SELECT id FROM tmp_contratos);

-- 4) Transferencias (ANTES de borrar líneas recepción/extracción)
DELETE FROM app_dat_operacion_transferencia tr
WHERE tr.id_operacion IN (SELECT id_operacion FROM tmp_transferencias)
   OR tr.id_recepcion IN (SELECT id_recepcion FROM tmp_transferencias)
   OR tr.id_extraccion IN (SELECT id_extraccion FROM tmp_transferencias);

-- 5) Inventario / gastos / ajustes
DELETE FROM app_cont_gastos g
WHERE g.origen_operacion IN (SELECT id FROM tmp_recepciones);

UPDATE app_dat_produccion_tanda pt
SET id_inventario_entrada = NULL
WHERE pt.id_inventario_entrada IN (SELECT id FROM tmp_inventario);

DELETE FROM app_dat_consignacion_envio_producto ep
WHERE ep.id_inventario IN (SELECT id FROM tmp_inventario)
   OR ep.id_inventario_original IN (SELECT id FROM tmp_inventario);

DELETE FROM app_dat_inventario_productos ip
WHERE ip.id IN (SELECT id FROM tmp_inventario);

DELETE FROM app_dat_ajuste_inventario ai
WHERE ai.id_ubicacion IN (SELECT id FROM tmp_layouts)
   OR ai.id_operacion IN (SELECT id FROM tmp_ops)
   OR ai.id_control IN (SELECT id FROM tmp_controles);

DELETE FROM app_dat_produccion_tanda pt
WHERE pt.id_almacen = (SELECT id_almacen FROM tmp_purge_params)
   OR pt.id_ubicacion IN (SELECT id FROM tmp_layouts)
   OR pt.id_cocina IN (SELECT id FROM tmp_cocinas);

DELETE FROM app_dat_conversion_presentacion cv
WHERE cv.id_ubicacion IN (SELECT id FROM tmp_layouts);

DELETE FROM app_dat_recepcion_productos rp
WHERE rp.id IN (SELECT id FROM tmp_recepciones);

DELETE FROM app_dat_extraccion_productos ep
WHERE ep.id IN (SELECT id FROM tmp_extracciones);

DELETE FROM app_dat_control_productos cp
WHERE cp.id IN (SELECT id FROM tmp_controles);

-- 6) Operaciones
DELETE FROM app_dat_estado_operacion eo
WHERE eo.id_operacion IN (SELECT id FROM tmp_ops);

DELETE FROM app_dat_operacion_recepcion
WHERE id_operacion IN (SELECT id FROM tmp_ops);

DELETE FROM app_dat_operacion_extraccion
WHERE id_operacion IN (SELECT id FROM tmp_ops);

DELETE FROM app_dat_operacion_venta
WHERE id_operacion IN (SELECT id FROM tmp_ops);

DELETE FROM app_dat_caja_turno ct
WHERE ct.id IN (SELECT id FROM tmp_turnos);

DELETE FROM app_dat_operaciones o
WHERE o.id IN (SELECT id FROM tmp_ops);

-- 7) Pre-asignaciones / carnaval / layouts
DELETE FROM app_dat_pre_asignaciones pa
WHERE pa.id_ubicacion_origen IN (SELECT id FROM tmp_layouts)
   OR pa.id_ubicacion_destino IN (SELECT id FROM tmp_layouts);

DELETE FROM relation_products_carnaval rpc
WHERE rpc.id_ubicacion IN (SELECT id FROM tmp_layouts);

UPDATE app_dat_tienda t
SET layout_catalogo = NULL
WHERE layout_catalogo IN (SELECT id FROM tmp_layouts);

DELETE FROM app_dat_layout_abc la
WHERE la.id_layout IN (SELECT id FROM tmp_layouts);

DELETE FROM app_dat_layout_condiciones lc
WHERE lc.id_layout IN (SELECT id FROM tmp_layouts);

-- 8) Vendedores exclusivos (trabajador completo vía RPC existente)
DO $$
DECLARE
  r RECORD;
  v_result JSONB;
  v_id_tienda BIGINT;
BEGIN
  SELECT id_tienda INTO v_id_tienda FROM tmp_purge_params LIMIT 1;

  FOR r IN
    SELECT DISTINCT ve.id_trabajador
    FROM tmp_vendedores_exclusivos ve
    WHERE ve.id_trabajador IS NOT NULL
  LOOP
    SELECT public.fn_eliminar_trabajador_completo(r.id_trabajador, v_id_tienda)
    INTO v_result;
    RAISE NOTICE 'Trabajador %: %', r.id_trabajador, v_result;
  END LOOP;
END $$;

DELETE FROM app_dat_descuentos_vendedor dv
WHERE dv.id_vendedor IN (SELECT id FROM tmp_vendedores_exclusivos);

DELETE FROM app_dat_vendedor_productos_default vpd
WHERE vpd.uuid IN (SELECT uuid FROM tmp_vendedores_exclusivos);

-- Vendedores con otro rol (ej. gerente): solo quitar rol vendedor
DELETE FROM app_dat_vendedor v
WHERE v.id_tpv IN (SELECT id FROM tmp_tpvs);

DELETE FROM app_dat_precio_tpv
WHERE id_tpv IN (SELECT id FROM tmp_tpvs);

DELETE FROM app_dat_tpv_dispositivos
WHERE id_tpv IN (SELECT id FROM tmp_tpvs);

DELETE FROM app_dat_tpv_cocina
WHERE id_tpv IN (SELECT id FROM tmp_tpvs);

DELETE FROM app_dat_cambio_precio
WHERE id_tpv IN (SELECT id FROM tmp_tpvs);

DELETE FROM app_dat_tpv
WHERE id IN (SELECT id FROM tmp_tpvs);

-- 9) Cocina
UPDATE app_dat_producto p
SET id_cocina = NULL
WHERE p.id_cocina IN (SELECT id FROM tmp_cocinas);

UPDATE app_dat_categoria_tienda ct
SET id_cocina = NULL
WHERE ct.id_cocina IN (SELECT id FROM tmp_cocinas);

DELETE FROM app_dat_jefe_cocina
WHERE id_cocina IN (SELECT id FROM tmp_cocinas);

DELETE FROM app_dat_tpv_cocina
WHERE id_cocina IN (SELECT id FROM tmp_cocinas);

DELETE FROM app_dat_comanda
WHERE id_cocina IN (SELECT id FROM tmp_cocinas);

DELETE FROM app_dat_cocina
WHERE id IN (SELECT id FROM tmp_cocinas);

-- 10) Almacén
DELETE FROM app_dat_almacenero al
WHERE al.id_almacen = (SELECT id_almacen FROM tmp_purge_params);

DELETE FROM app_dat_almacen_limites
WHERE id_almacen = (SELECT id_almacen FROM tmp_purge_params);

DELETE FROM app_dat_layout_almacen la
WHERE la.id_almacen = (SELECT id_almacen FROM tmp_purge_params);

DELETE FROM app_dat_almacen
WHERE id = (SELECT id_almacen FROM tmp_purge_params);

COMMIT;

-- Verificación post-borrado
SELECT EXISTS (SELECT 1 FROM app_dat_almacen WHERE id = 330) AS almacen_existe;
SELECT count(*) AS tpvs_restantes
FROM app_dat_tpv WHERE id_almacen = 330;
SELECT count(*) AS operaciones_venta_tpv226
FROM app_dat_operacion_venta ov
WHERE ov.id_tpv = 226;
