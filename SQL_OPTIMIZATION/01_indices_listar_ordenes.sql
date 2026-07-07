-- ============================================================================
-- ÍNDICES PARA OPTIMIZAR fn_listar_ordenes
-- ============================================================================
-- Ejecutar UNO POR UNO. En producción usar CONCURRENTLY (fuera de transacción)
-- para no bloquear escrituras. Sin CONCURRENTLY el bloqueo es de ~1-3s por tabla.
--
-- Diagnóstico (medido con EXPLAIN ANALYZE):
--   * app_dat_pago_venta (87k filas)  -> Seq Scan por CADA orden de la página.
--   * app_dat_descuentos_vendedor     -> sin índice en id_operacion (LATERAL por orden).
--   * app_dat_inventario_productos (238k) -> subconsulta entradas_producto por ítem.
-- ============================================================================

-- [CRÍTICO] El subquery de 'pagos' hacía Seq Scan de 87k filas por cada orden.
-- Antes: Seq Scan (Rows Removed by Filter: 87427) ~12ms x N órdenes.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_pago_venta_operacion_venta
  ON public.app_dat_pago_venta USING btree (id_operacion_venta);

-- [CRÍTICO] LEFT JOIN LATERAL de descuentos: filtra id_operacion + ORDER BY created_at DESC LIMIT 1.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_descuentos_vendedor_operacion
  ON public.app_dat_descuentos_vendedor USING btree (id_operacion, created_at DESC);

-- [ALTO] Subconsulta 'entradas_producto' sobre inventario (238k filas):
-- filtra id_producto + id_recepcion IS NOT NULL + rango created_at.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_inventario_recepcion_producto_fecha
  ON public.app_dat_inventario_productos USING btree (id_producto, created_at)
  WHERE id_recepcion IS NOT NULL;

-- [MEDIO] Filtro id_tpv en app_dat_operacion_venta ya tiene idx_operacion_venta_tpv,
-- pero el EXISTS por id_tpv se beneficia de cubrir id_operacion también.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_operacion_venta_tpv_operacion
  ON public.app_dat_operacion_venta USING btree (id_tpv, id_operacion);

-- Nota: app_dat_operaciones ya tiene idx_operaciones_tienda_tipo_fecha (id_tienda, id_tipo_operacion, created_at DESC)
-- y app_dat_estado_operacion ya tiene idx_estado_op_op_created (id_operacion, created_at DESC). No hace falta recrearlos.

-- Actualizar estadísticas del planner tras crear índices:
ANALYZE public.app_dat_pago_venta;
ANALYZE public.app_dat_descuentos_vendedor;
ANALYZE public.app_dat_inventario_productos;
ANALYZE public.app_dat_operacion_venta;
