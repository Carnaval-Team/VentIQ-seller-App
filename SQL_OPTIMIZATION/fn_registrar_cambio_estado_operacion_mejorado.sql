CREATE OR REPLACE FUNCTION public.fn_registrar_cambio_estado_operacion_mejorado(
    p_id_operacion BIGINT,
    p_nuevo_estado SMALLINT,
    p_uuid_usuario UUID DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_productos_extraidos RECORD;
    v_existente_estado RECORD;
    v_inventario_actual RECORD;
    v_ingrediente RECORD;
    v_cantidad_ingrediente_devolver NUMERIC;
    v_ultimo_inventario RECORD;
    v_es_recepcion BOOLEAN := FALSE;
    v_rp RECORD;
    v_stock_actual NUMERIC;
    v_inv_prematuro_id BIGINT;
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
          '"Estado de operaciÃ³n invÃ¡lido. Solo se permiten 1 (Pendiente), 2 (Completada), 3 (Devuelta), 4 (Cancelada)"'
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
        v_response := jsonb_set(v_response, '{message}', '"La operaciÃ³n ya tiene este estado"');
        RETURN v_response;
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM app_dat_operacion_recepcion orp
        WHERE orp.id_operacion = p_id_operacion
    ) INTO v_es_recepcion;

    -- â”€â”€ COMPLETAR RECEPCIÃ“N: aplicar inventario sobre el stock REAL actual â”€â”€
    -- Ejemplo: habÃ­a 3, pendiente +7, se vendiÃ³ 1 â†’ queda 2; al completar â†’ 9.
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
            -- Stock actual = Ãºltimo movimiento EXCLUYENDO filas prematuras
            -- de ESTA recepciÃ³n (legacy de cuando se insertaba al crear).
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

    -- â”€â”€ CANCELAR / DEVOLVER RECEPCIÃ“N PENDIENTE: limpiar filas prematuras â”€â”€
    IF v_es_recepcion AND p_nuevo_estado IN (3, 4) THEN
        DELETE FROM app_dat_inventario_productos ip
        WHERE ip.id_recepcion IN (
            SELECT rp.id
            FROM app_dat_recepcion_productos rp
            WHERE rp.id_operacion = p_id_operacion
        );
    END IF;

    INSERT INTO app_dat_estado_operacion (
        id_operacion, estado, uuid, created_at
    ) VALUES (
        p_id_operacion, p_nuevo_estado, p_uuid_usuario, NOW()
    );

    -- Cancelar/devolver EXTRACCIÃ“N: devolver stock (igual que antes)
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
    v_response := jsonb_set(v_response, '{message}', '"OperaciÃ³n actualizada exitosamente"');
    RETURN v_response;
EXCEPTION WHEN OTHERS THEN
    v_response := jsonb_set(v_response, '{success}', 'false');
    v_response := jsonb_set(v_response, '{message}', to_jsonb(SQLERRM));
    RETURN v_response;
END;
$$;

COMMENT ON FUNCTION public.fn_registrar_recepcion_con_inventario IS
  'Crea recepciÃ³n en estado Pendiente SIN mover inventario. El stock se aplica al completar.';

COMMENT ON FUNCTION public.fn_registrar_cambio_estado_operacion_mejorado IS
  'Al completar recepciÃ³n (estado=2) inserta inventario con saldo real actual + cantidad recibida.';
