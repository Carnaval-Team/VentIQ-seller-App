-- ============================================================================
-- fn_registrar_cambio_estado_operacion_mejorado: cancelar/devolver recepción
-- ============================================================================
-- Proyecto: main Y newa (misma función). Base: cuerpo desplegado en main.
-- Decisión del 19/11/2026 (docs/plan-multimoneda/analisis_8_funciones_pendientes.md, función 8).
--
-- Contexto:
--   * main tenía la lógica de recepciones (sql_updates/fix_recepcion_inventario_al_completar.sql)
--     pero no el flag cambiar_fecha_creacion_operacion_al_cierre.
--   * newa tenía el flag (sql_updates/update_fecha_creacion_cierre.sql) pero no la lógica
--     de recepciones. Cada script reescribió la función completa y pisó al otro.
--   * Además, al cancelar/devolver una recepción main BORRABA las filas de inventario
--     ligadas a sus líneas, sin comprobar si ya se habían usado. Incluso en recepciones
--     completadas, porque el botón de cancelar de admin también se muestra para ellas.
--
-- Qué hace esta versión:
--   1. Conserva de main: completar recepción (estado 2) aplica el inventario sobre el
--      saldo real, y todo el manejo de extracciones.
--   2. Añade de newa: al completar (estado 2), si la tienda tiene activo
--      cambiar_fecha_creacion_operacion_al_cierre, created_at = NOW().
--   3. Cancelar/devolver una recepción (estado 3 o 4):
--        - Si el inventario de los productos de la recepción NO se ha tocado desde que
--          ingresó, se devuelve la cantidad con un movimiento compensatorio (origen 4
--          devolución / 5 cancelación). No se borra ninguna fila del historial.
--        - Si ALGÚN producto ya se movió (venta, ajuste, transferencia, otra recepción)
--          o el saldo actual no alcanza, no se cancela NADA y se devuelve
--          success=false, error_code='RECEPCION_INVENTARIO_USADO' y la lista
--          `productos_con_problema` para que el usuario los ajuste a mano.
--        - Si la recepción ya estaba devuelta/cancelada (3/4), no hay nada que revertir.
--        - Sirve igual para recepciones pendientes que tengan filas de inventario
--          prematuras (legado): se revierten con el mismo criterio, sin borrarlas.
--
-- No revierte: costos (precio promedio / costo real) calculados al registrar la recepción.
-- Misma firma. CREATE OR REPLACE conserva permisos. Idempotente.
-- ============================================================================

BEGIN;

DO $chk$
BEGIN
    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION 'Ejecutar como postgres (actual: %)', current_user;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public'
           AND table_name = 'app_dat_configuracion_tienda'
           AND column_name = 'cambiar_fecha_creacion_operacion_al_cierre'
    ) THEN
        RAISE EXCEPTION 'Falta app_dat_configuracion_tienda.cambiar_fecha_creacion_operacion_al_cierre (sql_updates/update_fecha_creacion_cierre.sql)';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public'
           AND table_name = 'app_dat_inventario_productos'
           AND column_name = 'id_lote'
    ) THEN
        RAISE EXCEPTION 'Falta app_dat_inventario_productos.id_lote';
    END IF;
END
$chk$;

CREATE OR REPLACE FUNCTION public.fn_registrar_cambio_estado_operacion_mejorado(p_id_operacion bigint, p_nuevo_estado smallint, p_uuid_usuario uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_productos_extraidos RECORD;
    v_existente_estado RECORD;
    v_inventario_actual RECORD;
    v_ingrediente RECORD;
    v_cantidad_ingrediente_devolver NUMERIC;
    v_ultimo_inventario RECORD;
    v_es_recepcion BOOLEAN := FALSE;
    v_rp RECORD;
    v_mov RECORD;
    v_stock_actual NUMERIC;
    v_delta NUMERIC;
    v_saldo_actual NUMERIC;
    v_tocado BOOLEAN;
    v_nombre TEXT;
    v_detalle TEXT;
    v_problemas JSONB := '[]'::jsonb;
    v_ids_lineas BIGINT[];
    v_id_tienda BIGINT;
    v_cambiar_fecha_creacion BOOLEAN;
    v_response jsonb;
BEGIN
    v_response := jsonb_build_object(
        'success', false,
        'message', '',
        'operation_id', p_id_operacion,
        'new_state', p_nuevo_estado
    );

    IF p_nuevo_estado NOT IN (1, 2, 3, 4) THEN
        v_response := jsonb_set(v_response, '{success}', 'false');
        v_response := jsonb_set(
          v_response,
          '{message}',
          '"Estado de operación inválido. Solo se permiten 1 (Pendiente), 2 (Completada), 3 (Devuelta), 4 (Cancelada)"'
        );
        RETURN v_response;
    END IF;

    SELECT * INTO v_existente_estado
    FROM app_dat_estado_operacion
    WHERE id_operacion = p_id_operacion
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_existente_estado.estado = p_nuevo_estado THEN
        v_response := jsonb_set(v_response, '{success}', 'true');
        v_response := jsonb_set(v_response, '{message}', '"La operación ya tiene este estado"');
        RETURN v_response;
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM app_dat_operacion_recepcion orp
        WHERE orp.id_operacion = p_id_operacion
    ) INTO v_es_recepcion;

    -- ── COMPLETAR RECEPCIÓN: aplicar inventario sobre el stock REAL actual ──
    -- Ejemplo: había 3, pendiente +7, se vendió 1 → queda 2; al completar → 9.
    IF v_es_recepcion AND p_nuevo_estado = 2 THEN
        FOR v_rp IN
            SELECT
                rp.id AS id_recepcion_producto,
                rp.id_producto,
                rp.id_variante,
                rp.id_opcion_variante,
                rp.id_presentacion,
                rp.id_ubicacion,
                rp.id_proveedor,
                rp.cantidad,
                rp.sku_producto,
                rp.sku_ubicacion
            FROM app_dat_recepcion_productos rp
            WHERE rp.id_operacion = p_id_operacion
        LOOP
            -- Stock actual = último movimiento EXCLUYENDO filas prematuras
            -- de ESTA recepción (legacy de cuando se insertaba al crear).
            SELECT COALESCE((
                SELECT ip.cantidad_final
                FROM app_dat_inventario_productos ip
                WHERE ip.id_producto = v_rp.id_producto
                  AND (ip.id_variante        IS NOT DISTINCT FROM v_rp.id_variante)
                  AND (ip.id_opcion_variante IS NOT DISTINCT FROM v_rp.id_opcion_variante)
                  AND (ip.id_presentacion    IS NOT DISTINCT FROM v_rp.id_presentacion)
                  AND (ip.id_ubicacion       IS NOT DISTINCT FROM v_rp.id_ubicacion)
                  AND (ip.id_recepcion IS DISTINCT FROM v_rp.id_recepcion_producto)
                ORDER BY ip.id DESC
                LIMIT 1
            ), 0) INTO v_stock_actual;

            -- Eliminar movimiento prematuro legacy (si existe) para no contaminar MAX(id)
            DELETE FROM app_dat_inventario_productos
            WHERE id_recepcion = v_rp.id_recepcion_producto;

            INSERT INTO app_dat_inventario_productos (
                id_producto,
                id_variante,
                id_opcion_variante,
                id_ubicacion,
                id_presentacion,
                cantidad_inicial,
                cantidad_final,
                sku_producto,
                sku_ubicacion,
                origen_cambio,
                id_recepcion,
                id_proveedor,
                created_at
            ) VALUES (
                v_rp.id_producto,
                v_rp.id_variante,
                v_rp.id_opcion_variante,
                v_rp.id_ubicacion,
                v_rp.id_presentacion,
                v_stock_actual,
                v_stock_actual + v_rp.cantidad,
                v_rp.sku_producto,
                v_rp.sku_ubicacion,
                1,
                v_rp.id_recepcion_producto,
                v_rp.id_proveedor,
                NOW()
            );
        END LOOP;
    END IF;

    -- ── CANCELAR / DEVOLVER RECEPCIÓN: devolver al inventario lo que ingresó ──
    -- Si el inventario de los productos no se ha tocado desde la recepción, se revierte
    -- con un movimiento compensatorio. Si algún producto ya se movió, no se cancela nada
    -- y se informa cuáles para que el usuario los ajuste manualmente.
    -- Si la recepción ya estaba devuelta/cancelada (3/4) no hay nada que revertir.
    IF v_es_recepcion
       AND p_nuevo_estado IN (3, 4)
       AND COALESCE(v_existente_estado.estado, 0) NOT IN (3, 4) THEN

        SELECT COALESCE(array_agg(rp.id), ARRAY[]::bigint[])
          INTO v_ids_lineas
          FROM app_dat_recepcion_productos rp
         WHERE rp.id_operacion = p_id_operacion;

        -- Pasada 1: validar sin escribir nada.
        FOR v_rp IN
            SELECT rp.id AS id_linea, rp.id_producto
              FROM app_dat_recepcion_productos rp
             WHERE rp.id_operacion = p_id_operacion
             ORDER BY rp.id
        LOOP
            -- Último movimiento que dejó esta línea (define producto/variante/ubicación/lote).
            SELECT ip.id, ip.id_producto, ip.id_variante, ip.id_opcion_variante,
                   ip.id_presentacion, ip.id_ubicacion, ip.id_lote
              INTO v_mov
              FROM app_dat_inventario_productos ip
             WHERE ip.id_recepcion = v_rp.id_linea
             ORDER BY ip.id DESC
             LIMIT 1;
            IF NOT FOUND THEN
                CONTINUE;  -- la línea nunca tocó inventario: nada que devolver
            END IF;

            -- Cantidad que esta línea sumó al inventario.
            SELECT COALESCE(SUM(ip.cantidad_final - ip.cantidad_inicial), 0)
              INTO v_delta
              FROM app_dat_inventario_productos ip
             WHERE ip.id_recepcion = v_rp.id_linea;
            IF v_delta = 0 THEN
                CONTINUE;
            END IF;

            -- Saldo actual del mismo producto/combinación/lote.
            SELECT ip.cantidad_final
              INTO v_saldo_actual
              FROM app_dat_inventario_productos ip
             WHERE ip.id_producto = v_mov.id_producto
               AND COALESCE(ip.id_variante, 0)        = COALESCE(v_mov.id_variante, 0)
               AND COALESCE(ip.id_opcion_variante, 0) = COALESCE(v_mov.id_opcion_variante, 0)
               AND COALESCE(ip.id_presentacion, 0)    = COALESCE(v_mov.id_presentacion, 0)
               AND COALESCE(ip.id_ubicacion, 0)       = COALESCE(v_mov.id_ubicacion, 0)
               AND COALESCE(ip.id_lote, 0)            = COALESCE(v_mov.id_lote, 0)
             ORDER BY ip.id DESC
             LIMIT 1;

            -- ¿Hay algún movimiento posterior que no sea de esta misma recepción?
            SELECT EXISTS (
                SELECT 1
                  FROM app_dat_inventario_productos ip
                 WHERE ip.id_producto = v_mov.id_producto
                   AND COALESCE(ip.id_variante, 0)        = COALESCE(v_mov.id_variante, 0)
                   AND COALESCE(ip.id_opcion_variante, 0) = COALESCE(v_mov.id_opcion_variante, 0)
                   AND COALESCE(ip.id_presentacion, 0)    = COALESCE(v_mov.id_presentacion, 0)
                   AND COALESCE(ip.id_ubicacion, 0)       = COALESCE(v_mov.id_ubicacion, 0)
                   AND COALESCE(ip.id_lote, 0)            = COALESCE(v_mov.id_lote, 0)
                   AND ip.id > v_mov.id
                   AND (ip.id_recepcion IS NULL OR NOT (ip.id_recepcion = ANY (v_ids_lineas)))
            ) INTO v_tocado;

            IF v_tocado OR (COALESCE(v_saldo_actual, 0) - v_delta) < 0 THEN
                SELECT p.denominacion INTO v_nombre
                  FROM app_dat_producto p
                 WHERE p.id = v_mov.id_producto;

                v_problemas := v_problemas || jsonb_build_array(jsonb_build_object(
                    'id_producto',       v_mov.id_producto,
                    'producto',          COALESCE(v_nombre, 'Producto ' || v_mov.id_producto),
                    'cantidad_recibida', v_delta,
                    'saldo_actual',      COALESCE(v_saldo_actual, 0),
                    'motivo', CASE
                        WHEN v_tocado THEN 'El inventario cambió después de la recepción'
                        ELSE 'El saldo actual no alcanza para devolver lo recibido'
                    END
                ));
            END IF;
        END LOOP;

        IF jsonb_array_length(v_problemas) > 0 THEN
            SELECT string_agg(
                       '• ' || (x->>'producto')
                       || ' (recibido ' || trim_scale((x->>'cantidad_recibida')::numeric)::text
                       || ', saldo actual ' || trim_scale((x->>'saldo_actual')::numeric)::text || ')',
                       E'\n')
              INTO v_detalle
              FROM jsonb_array_elements(v_problemas) AS x;

            RETURN jsonb_build_object(
                'success', false,
                'error_code', 'RECEPCION_INVENTARIO_USADO',
                'operation_id', p_id_operacion,
                'new_state', p_nuevo_estado,
                'message', 'No se puede cancelar la recepción: el inventario de estos productos '
                           || 'ya cambió después de recibirse. Ajústalos manualmente y vuelve a intentar:'
                           || E'\n' || v_detalle,
                'productos_con_problema', v_problemas
            );
        END IF;

        -- Pasada 2: nada se movió; devolver las cantidades con movimientos compensatorios.
        FOR v_rp IN
            SELECT rp.id AS id_linea, rp.id_proveedor, rp.sku_producto, rp.sku_ubicacion
              FROM app_dat_recepcion_productos rp
             WHERE rp.id_operacion = p_id_operacion
             ORDER BY rp.id
        LOOP
            SELECT ip.id, ip.id_producto, ip.id_variante, ip.id_opcion_variante,
                   ip.id_presentacion, ip.id_ubicacion, ip.id_lote
              INTO v_mov
              FROM app_dat_inventario_productos ip
             WHERE ip.id_recepcion = v_rp.id_linea
             ORDER BY ip.id DESC
             LIMIT 1;
            IF NOT FOUND THEN
                CONTINUE;
            END IF;

            SELECT COALESCE(SUM(ip.cantidad_final - ip.cantidad_inicial), 0)
              INTO v_delta
              FROM app_dat_inventario_productos ip
             WHERE ip.id_recepcion = v_rp.id_linea;
            IF v_delta = 0 THEN
                CONTINUE;
            END IF;

            SELECT ip.cantidad_final
              INTO v_saldo_actual
              FROM app_dat_inventario_productos ip
             WHERE ip.id_producto = v_mov.id_producto
               AND COALESCE(ip.id_variante, 0)        = COALESCE(v_mov.id_variante, 0)
               AND COALESCE(ip.id_opcion_variante, 0) = COALESCE(v_mov.id_opcion_variante, 0)
               AND COALESCE(ip.id_presentacion, 0)    = COALESCE(v_mov.id_presentacion, 0)
               AND COALESCE(ip.id_ubicacion, 0)       = COALESCE(v_mov.id_ubicacion, 0)
               AND COALESCE(ip.id_lote, 0)            = COALESCE(v_mov.id_lote, 0)
             ORDER BY ip.id DESC
             LIMIT 1;

            INSERT INTO app_dat_inventario_productos (
                id_producto,
                id_variante,
                id_opcion_variante,
                id_ubicacion,
                id_presentacion,
                cantidad_inicial,
                cantidad_final,
                sku_producto,
                sku_ubicacion,
                origen_cambio,
                id_proveedor,
                id_lote,
                created_at
            ) VALUES (
                v_mov.id_producto,
                v_mov.id_variante,
                v_mov.id_opcion_variante,
                v_mov.id_ubicacion,
                v_mov.id_presentacion,
                COALESCE(v_saldo_actual, 0),
                COALESCE(v_saldo_actual, 0) - v_delta,
                v_rp.sku_producto,
                v_rp.sku_ubicacion,
                CASE WHEN p_nuevo_estado = 3 THEN 4 ELSE 5 END,  -- 4 Devolución, 5 Cancelación
                v_rp.id_proveedor,
                v_mov.id_lote,
                NOW()
            );
        END LOOP;
    END IF;

    INSERT INTO app_dat_estado_operacion (
        id_operacion, estado, uuid, created_at
    ) VALUES (
        p_id_operacion, p_nuevo_estado, p_uuid_usuario, NOW()
    );

    -- Al completar, si la tienda tiene activo 'cambiar_fecha_creacion_operacion_al_cierre',
    -- la fecha de creación de la operación pasa a la fecha/hora actual.
    IF p_nuevo_estado = 2 THEN
        SELECT id_tienda INTO v_id_tienda
        FROM app_dat_operaciones
        WHERE id = p_id_operacion;

        IF v_id_tienda IS NOT NULL THEN
            SELECT COALESCE(cambiar_fecha_creacion_operacion_al_cierre, false)
            INTO v_cambiar_fecha_creacion
            FROM app_dat_configuracion_tienda
            WHERE id_tienda = v_id_tienda;

            IF v_cambiar_fecha_creacion THEN
                UPDATE app_dat_operaciones
                SET created_at = NOW()
                WHERE id = p_id_operacion;
            END IF;
        END IF;
    END IF;

    -- Cancelar/devolver EXTRACCIÓN: devolver stock (igual que antes)
    IF p_nuevo_estado IN (3, 4) AND NOT v_es_recepcion THEN
        FOR v_productos_extraidos IN (
            SELECT
                id_producto,
                id_variante,
                id_opcion_variante,
                id_presentacion,
                id_ubicacion,
                cantidad,
                sku_producto,
                sku_ubicacion
            FROM app_dat_extraccion_productos
            WHERE id_operacion = p_id_operacion
        ) LOOP
            SELECT * INTO v_inventario_actual
            FROM app_dat_inventario_productos
            WHERE id_producto = v_productos_extraidos.id_producto
              AND COALESCE(id_variante, 0) = COALESCE(v_productos_extraidos.id_variante, 0)
              AND COALESCE(id_opcion_variante, 0) = COALESCE(v_productos_extraidos.id_opcion_variante, 0)
              AND COALESCE(id_presentacion, 0) = COALESCE(v_productos_extraidos.id_presentacion, 0)
              AND COALESCE(id_ubicacion, 0) = COALESCE(v_productos_extraidos.id_ubicacion, 0)
            ORDER BY created_at DESC
            LIMIT 1;

            IF v_inventario_actual.cantidad_final IS NULL THEN
                v_inventario_actual.cantidad_final := 0;
            END IF;

            INSERT INTO app_dat_inventario_productos (
                id_producto, id_variante, id_opcion_variante, id_presentacion,
                id_ubicacion, cantidad_inicial, cantidad_final,
                sku_producto, sku_ubicacion, origen_cambio, created_at
            ) VALUES (
                v_productos_extraidos.id_producto,
                v_productos_extraidos.id_variante,
                v_productos_extraidos.id_opcion_variante,
                v_productos_extraidos.id_presentacion,
                v_productos_extraidos.id_ubicacion,
                v_inventario_actual.cantidad_final,
                v_inventario_actual.cantidad_final + v_productos_extraidos.cantidad,
                v_productos_extraidos.sku_producto,
                v_productos_extraidos.sku_ubicacion,
                CASE
                    WHEN p_nuevo_estado = 3 THEN 4
                    WHEN p_nuevo_estado = 4 THEN 5
                END,
                NOW()
            );
        END LOOP;

        FOR v_productos_extraidos IN (
            SELECT ep.id_producto, ep.cantidad
            FROM app_dat_extraccion_productos ep
            INNER JOIN app_dat_producto p ON ep.id_producto = p.id
            WHERE ep.id_operacion = p_id_operacion
              AND p.es_elaborado = true
        ) LOOP
            FOR v_ingrediente IN (
                SELECT id_ingrediente, cantidad_necesaria
                FROM app_dat_producto_ingredientes
                WHERE id_producto_elaborado = v_productos_extraidos.id_producto
            ) LOOP
                v_cantidad_ingrediente_devolver :=
                    v_ingrediente.cantidad_necesaria * v_productos_extraidos.cantidad;

                SELECT * INTO v_ultimo_inventario
                FROM app_dat_inventario_productos
                WHERE id_producto = v_ingrediente.id_ingrediente
                ORDER BY created_at DESC
                LIMIT 1;

                IF v_ultimo_inventario IS NULL THEN
                    v_ultimo_inventario.cantidad_final := 0;
                    v_ultimo_inventario.id_presentacion := NULL;
                    v_ultimo_inventario.id_ubicacion := NULL;
                    v_ultimo_inventario.sku_producto := NULL;
                    v_ultimo_inventario.sku_ubicacion := NULL;
                END IF;

                INSERT INTO app_dat_inventario_productos (
                    id_producto, id_variante, id_opcion_variante, id_presentacion,
                    id_ubicacion, cantidad_inicial, cantidad_final,
                    sku_producto, sku_ubicacion, origen_cambio, created_at
                ) VALUES (
                    v_ingrediente.id_ingrediente,
                    COALESCE(v_ultimo_inventario.id_variante, NULL),
                    COALESCE(v_ultimo_inventario.id_opcion_variante, NULL),
                    v_ultimo_inventario.id_presentacion,
                    COALESCE(v_ultimo_inventario.id_ubicacion, NULL),
                    COALESCE(v_ultimo_inventario.cantidad_final, 0),
                    COALESCE(v_ultimo_inventario.cantidad_final, 0)
                      + v_cantidad_ingrediente_devolver,
                    COALESCE(v_ultimo_inventario.sku_producto, NULL),
                    COALESCE(v_ultimo_inventario.sku_ubicacion, NULL),
                    CASE
                        WHEN p_nuevo_estado = 3 THEN 6
                        WHEN p_nuevo_estado = 4 THEN 7
                    END,
                    NOW()
                );
            END LOOP;
        END LOOP;
    END IF;

    v_response := jsonb_set(v_response, '{success}', 'true');
    v_response := jsonb_set(v_response, '{message}', '"Operación actualizada exitosamente"');
    RETURN v_response;
EXCEPTION WHEN OTHERS THEN
    v_response := jsonb_set(v_response, '{success}', 'false');
    v_response := jsonb_set(v_response, '{message}', to_jsonb(SQLERRM));
    RETURN v_response;
END;
$function$;

DO $ver$
BEGIN
    IF (SELECT prosrc FROM pg_proc
         WHERE oid = to_regprocedure('public.fn_registrar_cambio_estado_operacion_mejorado(bigint,smallint,uuid)'))
       NOT LIKE '%RECEPCION_INVENTARIO_USADO%' THEN
        RAISE EXCEPTION 'fn_registrar_cambio_estado_operacion_mejorado no quedó con la lógica nueva';
    END IF;
END
$ver$;

COMMIT;
