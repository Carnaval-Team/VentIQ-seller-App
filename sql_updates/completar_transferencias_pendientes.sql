-- Completar transferencias pendientes en main (tienda 234)
-- 191541: extracción 191539 / recepción 191540 (layout 383 -> 387)
-- 191353: extracción 191351 / recepción 191352
--
-- Replica el flujo del cliente (InventoryService.completeOperation):
--   extracción -> fn_registrar_cambio_estado_operacion (estado 2; NO re-descuenta stock)
--   recepción  -> fn_contabilizar_operacion (acredita stock en destino + marca estado)
--   padre      -> fn_registrar_cambio_estado_operacion (estado 2)
--
-- Reemplazar :uuid por el uuid del usuario que ejecuta (puede ir NULL).
\set uuid '''635388c5-bc9b-47b6-b7ee-233f2b5a882f'''

BEGIN;

-- ============ Transferencia 191353 ============
SELECT fn_registrar_cambio_estado_operacion(191351::bigint, 2::smallint, :uuid::uuid);
SELECT fn_contabilizar_operacion(191352::bigint, :uuid::uuid, 'Confirmación manual por SQL (auditoría transferencia pendiente)');
SELECT fn_registrar_cambio_estado_operacion(191353::bigint, 2::smallint, :uuid::uuid);

-- ============ Transferencia 191541 ============
SELECT fn_registrar_cambio_estado_operacion(191539::bigint, 2::smallint, :uuid::uuid);
SELECT fn_contabilizar_operacion(191540::bigint, :uuid::uuid, 'Confirmación manual por SQL (auditoría transferencia pendiente)');
SELECT fn_registrar_cambio_estado_operacion(191541::bigint, 2::smallint, :uuid::uuid);

COMMIT;

-- ============ Verificación ============
-- Debe devolver 6 filas, todas estado = 2
SELECT e.id_operacion, e.estado, n.denominacion, e.created_at
FROM app_dat_estado_operacion e
LEFT JOIN app_nom_estado_operacion n ON n.id = e.estado
WHERE e.id_operacion IN (191351, 191352, 191353, 191539, 191540, 191541)
ORDER BY e.id_operacion, e.created_at;

-- El destino de cada transferencia debe tener el movimiento de entrada
-- (ajustar cantidades según las líneas de cada recepción)
SELECT ip.id, ip.id_producto, ip.id_ubicacion, ip.cantidad_inicial,
       ip.cantidad_final, ip.id_recepcion, ip.origen_cambio, ip.created_at
FROM app_dat_inventario_productos ip
WHERE ip.id_recepcion IN (
    SELECT id FROM app_dat_recepcion_productos
    WHERE id_operacion IN (191352, 191540)
)
ORDER BY ip.id;
