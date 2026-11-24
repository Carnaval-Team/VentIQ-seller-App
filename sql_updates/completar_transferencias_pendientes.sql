-- Cerrar transferencia 191541 en main (tienda 234)
-- Ejecutar en el SQL Editor de Supabase.
--
-- Contexto: el stock ya salió del origen (383 -> -20 al crear) y YA entró al
-- destino (387) por una recepción manual posterior (línea 35127, +20 a las
-- 14:50). Por eso:
--   extracción 191539 -> COMPLETAR (estado 2, no re-descuenta stock)
--   recepción 191540  -> CANCELAR (estado 4, NO contabiliza: evita duplicar stock)
--   transferencia 191541 -> COMPLETAR (estado 2)
--
-- fn_registrar_cambio_estado_operacion devuelve void: cualquier fallo interno
-- aborta el bloque y revierte todo. Las consultas del final verifican el resultado.
--
-- Cambiar v_uuid por el uuid del usuario que ejecuta (puede ser NULL).

DO $$
DECLARE
    v_uuid uuid := '635388c5-bc9b-47b6-b7ee-233f2b5a882f';
BEGIN
    -- Extracción: completar
    PERFORM fn_registrar_cambio_estado_operacion(191539::bigint, 2::smallint, v_uuid);
    RAISE NOTICE 'extracción 191539 -> estado 2';

    -- Recepción: cancelar (el producto ya entró por otra recepción manual).
    -- En recepciones esta función no revierte inventario — solo registra el
    -- estado, que es lo que se quiere aquí.
    PERFORM fn_registrar_cambio_estado_operacion(191540::bigint, 4::smallint, v_uuid);
    RAISE NOTICE 'recepción 191540 -> estado 4 (cancelada)';

    -- Transferencia padre: completar
    PERFORM fn_registrar_cambio_estado_operacion(191541::bigint, 2::smallint, v_uuid);
    RAISE NOTICE 'padre 191541 -> estado 2';

    -- Guard: los 3 estados deben haber quedado como se esperaba
    IF (SELECT estado FROM app_dat_estado_operacion
        WHERE id_operacion = 191539 ORDER BY created_at DESC LIMIT 1) <> 2
    OR (SELECT estado FROM app_dat_estado_operacion
        WHERE id_operacion = 191540 ORDER BY created_at DESC LIMIT 1) <> 4
    OR (SELECT estado FROM app_dat_estado_operacion
        WHERE id_operacion = 191541 ORDER BY created_at DESC LIMIT 1) <> 2 THEN
        RAISE EXCEPTION 'Verificación falló: estados no quedaron como se esperaba';
    END IF;
END $$;

-- ============ Verificación ============
-- Estados esperados: 191539=2, 191540=4, 191541=2
SELECT e.id_operacion, e.estado, n.denominacion, e.created_at
FROM app_dat_estado_operacion e
LEFT JOIN app_nom_estado_operacion n ON n.id = e.estado
WHERE e.id_operacion IN (191539, 191540, 191541)
ORDER BY e.id_operacion, e.created_at;

-- Confirmar que la recepción 191540 NO generó inventario en destino
-- (debe devolver 0 filas)
SELECT ip.id, ip.id_producto, ip.id_ubicacion, ip.cantidad_inicial,
       ip.cantidad_final, ip.id_recepcion, ip.origen_cambio, ip.created_at
FROM app_dat_inventario_productos ip
WHERE ip.id_recepcion IN (
    SELECT id FROM app_dat_recepcion_productos WHERE id_operacion = 191540
)
ORDER BY ip.id;
