-- ============================================================================
-- FIX: eliminar un OrderDetail de Carnaval no devolvía inventario en Inventtia
-- ============================================================================
-- Síntoma: al cambiar la cantidad de una línea sí se devolvía stock, pero al
-- eliminar la línea completa solo se quitaba de la orden (y se reponía stock
-- en carnavalapp."Productos" por el fallback), sin crear la recepción tipo 5.
--
-- Causa: fn_orderdetails_ajustar_erp corrige la línea de la venta original con
--   v_linea_cant_new = GREATEST(0, extraccion.cantidad - mov_real)
-- Al eliminar la línea completa eso da 0, y el UPDATE a
-- app_dat_extraccion_productos viola chk_extraccion_cantidad_positiva
-- (cantidad > 0). La excepción revierte TODO el sub-bloque ERP (recepción +
-- movimiento de inventario incluidos) y queda aplicado_erp = false en bitácora
-- con erp_error = 'Excepción al ajustar Inventtia: new row for relation
-- "app_dat_extraccion_productos" violates check constraint ...'.
--
-- La línea NO se puede borrar (app_dat_inventario_productos.id_extraccion es
-- ON DELETE CASCADE y destruiría el historial), así que el diseño exige poder
-- dejarla en 0: una extracción en 0 significa "devuelta completa".
--
-- Impacto de permitir 0: stock_reservado y los reportes hacen SUM(cantidad),
-- donde 0 no aporta nada. Ningún flujo escribe 0 excepto este trigger.
--
-- APLICAR MANUALMENTE en Supabase (SQL Editor). Idempotente.
-- ============================================================================

ALTER TABLE public.app_dat_extraccion_productos
    DROP CONSTRAINT IF EXISTS chk_extraccion_cantidad_positiva;

-- Por si el constraint existe con el nombre auto-generado de Postgres.
ALTER TABLE public.app_dat_extraccion_productos
    DROP CONSTRAINT IF EXISTS app_dat_extraccion_productos_cantidad_check;

ALTER TABLE public.app_dat_extraccion_productos
    ADD CONSTRAINT chk_extraccion_cantidad_positiva
    CHECK (cantidad >= 0);

COMMENT ON COLUMN public.app_dat_extraccion_productos.cantidad IS
'Cantidad extraída. Puede quedar en 0 cuando la línea de la orden Carnaval se eliminó o devolvió completa (la fila no se borra: inventario.id_extraccion es ON DELETE CASCADE).';


-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================
-- SELECT conname, pg_get_constraintdef(oid)
--   FROM pg_constraint
--  WHERE conrelid = 'public.app_dat_extraccion_productos'::regclass
--    AND conname LIKE '%cantidad%';
--  -- esperado: CHECK (cantidad >= 0)
--
-- Daños pendientes de reparar a mano (borrados que no devolvieron inventario):
-- SELECT id, created_at, order_id, product_id, producto_nombre,
--        cantidad_anterior, delta, id_operacion_venta, id_tienda,
--        id_producto_erp, erp_error
--   FROM carnavalapp.order_details_bitacora
--  WHERE accion = 'eliminacion' AND NOT aplicado_erp
--  ORDER BY created_at DESC;
--
-- Para cada una hay que crear la recepción (tipo 5, motivo 3) con la cantidad
-- en cantidad_anterior y corregir la línea/importe de la venta id_operacion_venta.
