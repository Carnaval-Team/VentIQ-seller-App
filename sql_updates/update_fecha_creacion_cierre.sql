-- ============================================================================
-- Actualizar created_at de la operación al completarla, según configuración
-- de la tienda: cambiar_fecha_creacion_operacion_al_cierre
-- ============================================================================

BEGIN;

-- 1. Asegurar que la columna de configuración exista en app_dat_configuracion_tienda
ALTER TABLE public.app_dat_configuracion_tienda
  ADD COLUMN IF NOT EXISTS cambiar_fecha_creacion_operacion_al_cierre boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.app_dat_configuracion_tienda.cambiar_fecha_creacion_operacion_al_cierre
  IS 'Si true, al completar (estado 2) una operación se actualiza app_dat_operaciones.created_at a NOW().';

-- 2. fn_registrar_cambio_estado_operacion (usado por ventiq_app al confirmar pago)
CREATE OR REPLACE FUNCTION public.fn_registrar_cambio_estado_operacion(
    p_id_operacion bigint,
    p_nuevo_estado smallint,
    p_uuid_usuario uuid DEFAULT NULL::uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_productos_extraidos RECORD;
    v_existente_estado RECORD;
    v_inventario_actual RECORD;
    v_ingrediente RECORD;
    v_cantidad_ingrediente_devolver NUMERIC;
    v_ultimo_inventario RECORD;
    v_es_recepcion BOOLEAN := FALSE;
    v_id_tienda BIGINT;
    v_cambiar_fecha_creacion BOOLEAN;
BEGIN
    IF p_nuevo_estado NOT IN (1, 2, 3, 4) THEN
        RAISE EXCEPTION 'Estado de operación inválido. Solo se permiten 1 (Pendiente), 2 (Completada), 3 (Devuelta), 4 (Cancelada)';
    END IF;

    SELECT * INTO v_existente_estado
    FROM app_dat_estado_operacion
    WHERE id_operacion = p_id_operacion
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_existente_estado.estado = p_nuevo_estado THEN
        RETURN;
    END IF;

    INSERT INTO app_dat_estado_operacion (
        id_operacion,
        estado,
        uuid,
        created_at
    ) VALUES (
        p_id_operacion,
        p_nuevo_estado,
        p_uuid_usuario,
        NOW()
    );

    -- Si se está completando la operación y la tienda tiene activo el flag,
    -- actualizar la fecha de creación de la operación.
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

    SELECT EXISTS (
        SELECT 1
        FROM app_dat_operacion_recepcion orp
        WHERE orp.id_operacion = p_id_operacion
    ) INTO v_es_recepcion;

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
                id_producto,
                id_variante,
                id_opcion_variante,
                id_presentacion,
                id_ubicacion,
                cantidad_inicial,
                cantidad_final,
                sku_producto,
                sku_ubicacion,
                origen_cambio,
                created_at
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
            SELECT
                ep.id_producto,
                ep.cantidad
            FROM app_dat_extraccion_productos ep
            INNER JOIN app_dat_producto p ON ep.id_producto = p.id
            WHERE ep.id_operacion = p_id_operacion
              AND p.es_elaborado = true
        ) LOOP

            FOR v_ingrediente IN (
                SELECT
                    id_ingrediente,
                    cantidad_necesaria
                FROM app_dat_producto_ingredientes
                WHERE id_producto_elaborado = v_productos_extraidos.id_producto
            ) LOOP

                v_cantidad_ingrediente_devolver := v_ingrediente.cantidad_necesaria * v_productos_extraidos.cantidad;

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
                    id_producto,
                    id_variante,
                    id_opcion_variante,
                    id_presentacion,
                    id_ubicacion,
                    cantidad_inicial,
                    cantidad_final,
                    sku_producto,
                    sku_ubicacion,
                    origen_cambio,
                    created_at
                ) VALUES (
                    v_ingrediente.id_ingrediente,
                    COALESCE(v_ultimo_inventario.id_variante, NULL),
                    COALESCE(v_ultimo_inventario.id_opcion_variante, NULL),
                    v_ultimo_inventario.id_presentacion,
                    COALESCE(v_ultimo_inventario.id_ubicacion, NULL),
                    COALESCE(v_ultimo_inventario.cantidad_final, 0),
                    COALESCE(v_ultimo_inventario.cantidad_final, 0) + v_cantidad_ingrediente_devolver,
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
END;
$function$;

-- 3. fn_registrar_cambio_estado_operacion_mejorado (misma lógica, retorna jsonb)
CREATE OR REPLACE FUNCTION public.fn_registrar_cambio_estado_operacion_mejorado(
    p_id_operacion bigint,
    p_nuevo_estado smallint,
    p_uuid_usuario uuid DEFAULT NULL::uuid
)
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
        v_response := jsonb_set(v_response, '{message}', '"Estado de operación inválido. Solo se permiten 1 (Pendiente), 2 (Completada), 3 (Devuelta), 4 (Cancelada)"');
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

    INSERT INTO app_dat_estado_operacion (
        id_operacion,
        estado,
        uuid,
        created_at
    ) VALUES (
        p_id_operacion,
        p_nuevo_estado,
        p_uuid_usuario,
        NOW()
    );

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

    SELECT EXISTS (
        SELECT 1
        FROM app_dat_operacion_recepcion orp
        WHERE orp.id_operacion = p_id_operacion
    ) INTO v_es_recepcion;

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
                id_producto,
                id_variante,
                id_opcion_variante,
                id_presentacion,
                id_ubicacion,
                cantidad_inicial,
                cantidad_final,
                sku_producto,
                sku_ubicacion,
                origen_cambio,
                created_at
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
            SELECT
                ep.id_producto,
                ep.cantidad
            FROM app_dat_extraccion_productos ep
            INNER JOIN app_dat_producto p ON ep.id_producto = p.id
            WHERE ep.id_operacion = p_id_operacion
              AND p.es_elaborado = true
        ) LOOP

            FOR v_ingrediente IN (
                SELECT
                    id_ingrediente,
                    cantidad_necesaria
                FROM app_dat_producto_ingredientes
                WHERE id_producto_elaborado = v_productos_extraidos.id_producto
            ) LOOP

                v_cantidad_ingrediente_devolver := v_ingrediente.cantidad_necesaria * v_productos_extraidos.cantidad;

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
                    id_producto,
                    id_variante,
                    id_opcion_variante,
                    id_presentacion,
                    id_ubicacion,
                    cantidad_inicial,
                    cantidad_final,
                    sku_producto,
                    sku_ubicacion,
                    origen_cambio,
                    created_at
                ) VALUES (
                    v_ingrediente.id_ingrediente,
                    COALESCE(v_ultimo_inventario.id_variante, NULL),
                    COALESCE(v_ultimo_inventario.id_opcion_variante, NULL),
                    v_ultimo_inventario.id_presentacion,
                    COALESCE(v_ultimo_inventario.id_ubicacion, NULL),
                    COALESCE(v_ultimo_inventario.cantidad_final, 0),
                    COALESCE(v_ultimo_inventario.cantidad_final, 0) + v_cantidad_ingrediente_devolver,
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

COMMIT;
