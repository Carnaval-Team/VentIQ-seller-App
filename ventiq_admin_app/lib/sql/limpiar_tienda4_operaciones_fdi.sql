-- =============================================================================
-- LIMPIEZA TIENDA 4 (NewStore) — proyecto newa
-- Borra TODAS las operaciones (ventas, extracciones, turnos, pagos, etc.),
-- TODO el módulo FDI (fondo de inversión) y el inventario de la tienda 4.
-- CONSERVA: productos, categorías, lotes, almacenes, staff, TPV, config,
--           suscripción y la fila de app_dat_tienda.
-- Ejecutar en el SQL Editor de Supabase. Irreversible.
-- Orden de DELETEs según el grafo real de FKs (hijos antes que padres).
-- =============================================================================

BEGIN;

-- Ids de operaciones de la tienda (se reutiliza en todos los DELETEs).
CREATE TEMP TABLE _ops_t4 ON COMMIT DROP AS
    SELECT id FROM public.app_dat_operaciones WHERE id_tienda = 4;

-- -----------------------------------------------------------------------------
-- 1. MÓDULO FDI (orden por FKs)
-- -----------------------------------------------------------------------------
DELETE FROM public.fdi_dat_inversor_reparto WHERE id_tienda = 4;
DELETE FROM public.fdi_dat_liquidacion_orden
    WHERE id_liquidacion IN (SELECT id FROM public.fdi_dat_liquidacion WHERE id_tienda = 4);
DELETE FROM public.fdi_dat_liquidacion_detalle
    WHERE id_liquidacion IN (SELECT id FROM public.fdi_dat_liquidacion WHERE id_tienda = 4);
DELETE FROM public.fdi_dat_inversion_recepcion
    WHERE id_inversion IN (SELECT id FROM public.fdi_dat_inversion WHERE id_tienda = 4)
       OR id_operacion IN (SELECT id FROM _ops_t4);
DELETE FROM public.fdi_dat_inversion_fuente
    WHERE id_inversion IN (SELECT id FROM public.fdi_dat_inversion WHERE id_tienda = 4);
DELETE FROM public.fdi_hist_estado_inversion
    WHERE id_inversion IN (SELECT id FROM public.fdi_dat_inversion WHERE id_tienda = 4);
DELETE FROM public.fdi_dat_inversion      WHERE id_tienda = 4;
DELETE FROM public.fdi_dat_movimiento     WHERE id_tienda = 4;
DELETE FROM public.fdi_dat_saldo          WHERE id_tienda = 4;
DELETE FROM public.fdi_dat_transferencia  WHERE id_tienda = 4;
DELETE FROM public.fdi_dat_liquidacion    WHERE id_tienda = 4;
DELETE FROM public.fdi_dat_cuenta         WHERE id_tienda = 4;
DELETE FROM public.fdi_dat_inversor       WHERE id_tienda = 4;
DELETE FROM public.fdi_dat_concepto       WHERE id_tienda = 4;
DELETE FROM public.fdi_dat_config         WHERE id_tienda = 4;

-- -----------------------------------------------------------------------------
-- 2. VENTAS: pagos y movimientos de consignación dependen de operacion_venta.
--    Nota: app_dat_operacion_venta usa id_operacion como PK (no tiene id propio),
--    por lo que id_operacion_venta = id de la operación.
-- -----------------------------------------------------------------------------
DELETE FROM public.app_dat_pago_venta
    WHERE id_operacion_venta IN (SELECT id FROM _ops_t4);
DELETE FROM public.app_dat_movimiento_consignacion
    WHERE id_operacion_venta IN (SELECT id FROM _ops_t4);
DELETE FROM public.app_dat_operacion_venta WHERE id_operacion IN (SELECT id FROM _ops_t4);

-- -----------------------------------------------------------------------------
-- 3. CONSIGNACIÓN: envío cascada borra envio_movimiento y envio_producto
--    (envio_producto referencia a inventario → debe ir antes que inventario).
-- -----------------------------------------------------------------------------
DELETE FROM public.app_dat_consignacion_envio
    WHERE id_operacion_recepcion  IN (SELECT id FROM _ops_t4)
       OR id_operacion_extraccion IN (SELECT id FROM _ops_t4);
DELETE FROM public.app_dat_producto_consignacion
    WHERE id_operacion_extraccion IN (SELECT id FROM _ops_t4)
       OR id_operacion_recepcion  IN (SELECT id FROM _ops_t4);

-- -----------------------------------------------------------------------------
-- 4. GASTOS originados en recepciones (referencia NO ACTION).
-- -----------------------------------------------------------------------------
DELETE FROM public.app_cont_gastos
    WHERE id_tienda = 4
       OR origen_operacion IN (
           SELECT id FROM public.app_dat_recepcion_productos
           WHERE id_operacion IN (SELECT id FROM _ops_t4));

-- -----------------------------------------------------------------------------
-- 5. INVENTARIO de los lotes de la tienda
--    (referencia a control_productos y es referenciado por envio_producto).
-- -----------------------------------------------------------------------------
DELETE FROM public.app_dat_inventario_productos
    WHERE id_lote IN (SELECT id FROM public.app_dat_lote WHERE id_tienda = 4)
       OR id_producto IN (SELECT id FROM public.app_dat_producto WHERE id_tienda = 4)
       OR id_control IN (
           SELECT id FROM public.app_dat_control_productos
           WHERE id_operacion IN (SELECT id FROM _ops_t4))
       OR id_extraccion IN (
           SELECT id FROM public.app_dat_extraccion_productos
           WHERE id_operacion IN (SELECT id FROM _ops_t4))
       OR id_recepcion IN (
           SELECT id FROM public.app_dat_recepcion_productos
           WHERE id_operacion IN (SELECT id FROM _ops_t4))
       OR id_conversion IN (
           SELECT id FROM public.app_dat_conversion_presentacion
           WHERE id_operacion IN (SELECT id FROM _ops_t4))
       OR id_conversion_evento IN (
           SELECT id FROM public.app_dat_conversion_presentacion_evento
           WHERE id_operacion IN (SELECT id FROM _ops_t4));

-- -----------------------------------------------------------------------------
-- 6. RESTO DE HIJOS DE app_dat_operaciones
-- -----------------------------------------------------------------------------
-- ajuste_inventario referencia a control_productos → va primero.
DELETE FROM public.app_dat_ajuste_inventario   WHERE id_operacion IN (SELECT id FROM _ops_t4);
DELETE FROM public.app_dat_control_productos   WHERE id_operacion IN (SELECT id FROM _ops_t4);
DELETE FROM public.app_dat_extraccion_productos WHERE id_operacion IN (SELECT id FROM _ops_t4);
DELETE FROM public.app_dat_extraccion_v2_solicitud
    WHERE id_tienda = 4 OR id_operacion IN (SELECT id FROM _ops_t4);
DELETE FROM public.app_dat_recepcion_productos WHERE id_operacion IN (SELECT id FROM _ops_t4);
DELETE FROM public.app_dat_conversion_presentacion_pata
    WHERE id_conversion_evento IN (
        SELECT id FROM public.app_dat_conversion_presentacion_evento
        WHERE id_operacion IN (SELECT id FROM _ops_t4));
DELETE FROM public.app_dat_conversion_presentacion WHERE id_operacion IN (SELECT id FROM _ops_t4);
DELETE FROM public.app_dat_conversion_presentacion_evento WHERE id_operacion IN (SELECT id FROM _ops_t4);
DELETE FROM public.app_dat_garantia_uso   WHERE id_operacion_devolucion IN (SELECT id FROM _ops_t4)
                                             OR id_garantia_venta IN (
                                                 SELECT id FROM public.app_dat_garantia_venta
                                                 WHERE id_venta_original IN (SELECT id FROM _ops_t4));
DELETE FROM public.app_dat_garantia_venta WHERE id_venta_original IN (SELECT id FROM _ops_t4);
DELETE FROM public.app_dat_historial_pre_asignaciones WHERE id_operacion IN (SELECT id FROM _ops_t4);
DELETE FROM public.app_dat_log_modificacion_orden     WHERE id_operacion IN (SELECT id FROM _ops_t4);
DELETE FROM public.app_dat_estado_operacion           WHERE id_operacion IN (SELECT id FROM _ops_t4);
DELETE FROM public.app_dat_operacion_extraccion       WHERE id_operacion IN (SELECT id FROM _ops_t4);
DELETE FROM public.app_dat_operacion_recepcion        WHERE id_operacion IN (SELECT id FROM _ops_t4);
DELETE FROM public.app_dat_operacion_transferencia
    WHERE id_operacion IN (SELECT id FROM _ops_t4)
       OR id_extraccion IN (SELECT id FROM _ops_t4)
       OR id_recepcion  IN (SELECT id FROM _ops_t4);
DELETE FROM public.app_dat_operacion_contabilizacion_historial
    WHERE id_operacion IN (SELECT id FROM _ops_t4);
DELETE FROM public.app_dat_operacion_offline_idempotencia
    WHERE id_operacion IN (SELECT id FROM _ops_t4);
DELETE FROM public.app_mkt_cliente_promociones WHERE id_operacion IN (SELECT id FROM _ops_t4);
DELETE FROM public.app_mkt_eventos_fidelizacion
    WHERE id_tienda = 4 OR id_operacion IN (SELECT id FROM _ops_t4);
DELETE FROM public.paqueteria_ordenes WHERE id_operacion IN (SELECT id FROM _ops_t4);

-- -----------------------------------------------------------------------------
-- 7. TURNOS (entregas parciales referencia a caja_turno con NO ACTION)
-- -----------------------------------------------------------------------------
CREATE TEMP TABLE _turnos_t4 ON COMMIT DROP AS
    SELECT id FROM public.app_dat_caja_turno
    WHERE id_tpv IN (SELECT id FROM public.app_dat_tpv WHERE id_tienda = 4)
       OR id_operacion_apertura IN (SELECT id FROM _ops_t4)
       OR id_operacion_cierre   IN (SELECT id FROM _ops_t4);

DELETE FROM public.app_dat_entregas_parciales_caja
    WHERE id_turno IN (SELECT id FROM _turnos_t4);
DELETE FROM public.app_dat_turno_trabajadores
    WHERE id_turno IN (SELECT id FROM _turnos_t4);
DELETE FROM public.app_dat_caja_turno WHERE id IN (SELECT id FROM _turnos_t4);

-- -----------------------------------------------------------------------------
-- 8. MESAS: comanda referencia a mesa_cuenta_abierta → comanda primero
--    (comanda_item y mesa_cuenta_item se borran en cascada).
-- -----------------------------------------------------------------------------
DELETE FROM public.app_dat_comanda             WHERE id_tienda = 4;
DELETE FROM public.app_dat_mesa_cuenta_abierta WHERE id_tienda = 4;

-- -----------------------------------------------------------------------------
-- 9. OPERACIONES
-- -----------------------------------------------------------------------------
DELETE FROM public.app_dat_operaciones WHERE id_tienda = 4;

COMMIT;
