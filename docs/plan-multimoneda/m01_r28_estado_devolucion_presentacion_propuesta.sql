BEGIN;

-- BORRADOR MC-054. NO EJECUTAR en main.
-- Enmienda del cambio de estado: las lineas producto-v1 guardan
-- id_presentacion NULL cuando la venta fue en la presentacion base, pero
-- app_dat_inventario_productos.id_presentacion es NOT NULL y el ledger
-- guarda la fila base de app_dat_producto_presentacion (p. ej. 19 para el
-- producto 12). Al devolver/cancelar (estados 3 y 4) la devolucion
-- resuelve NULL -> presentacion base del producto, tanto en el match del
-- saldo vigente como en el INSERT. El resto del cuerpo se conserva.

SET LOCAL app.m01_r28_estado_devolucion_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r28_estado_devolucion_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador MC-054: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    -- Solo reemplaza el cuerpo vigente (o una corrida previa de esta
    -- enmienda); cualquier otro cuerpo aborta.
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc
        WHERE oid = to_regprocedure('public.fn_registrar_cambio_estado_operacion(bigint,smallint,uuid)')
          AND prosecdef AND proowner = 'postgres'::regrole
          AND (position('v_productos_extraidos.id_presentacion,' in prosrc) > 0
               OR position('v_presentacion_devolver' in prosrc) > 0)
    ) THEN
        RAISE EXCEPTION 'fn_registrar_cambio_estado_operacion difiere del cuerpo vigente en newa; revisar sin reemplazar avances';
    END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.fn_registrar_cambio_estado_operacion(
    p_id_operacion bigint,
    p_nuevo_estado smallint,
    p_uuid_usuario uuid DEFAULT NULL::uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
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
    v_presentacion_devolver BIGINT;
BEGIN
    -- Primero, validar que el estado sea válido
    IF p_nuevo_estado NOT IN (1, 2, 3, 4) THEN
        RAISE EXCEPTION 'Estado de operación inválido. Solo se permiten 1 (Pendiente), 2 (Completada), 3 (Devuelta), 4 (Cancelada)';
    END IF;

    -- Verificar si ya existe un estado para esta operación
    SELECT * INTO v_existente_estado
    FROM app_dat_estado_operacion
    WHERE id_operacion = p_id_operacion
    ORDER BY created_at DESC
    LIMIT 1;

    -- Si el estado es el mismo que el último registrado, no hacer nada
    IF v_existente_estado.estado = p_nuevo_estado THEN
        RETURN;
    END IF;

    -- Insertar nuevo estado de operación
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

    -- Si la operación se está completando y la tienda tiene activo el flag
    -- 'cambiar_fecha_creacion_operacion_al_cierre', actualizar la fecha de creación
    -- de la operación a la fecha/hora actual.
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

    -- Si la operación es una RECEPCIÓN, al marcarla como Devuelta (3) o Cancelada (4)
    -- NO se debe retornar stock al inventario (se está cancelando la recepción).
    SELECT EXISTS (
        SELECT 1
        FROM app_dat_operacion_recepcion orp
        WHERE orp.id_operacion = p_id_operacion
    ) INTO v_es_recepcion;

    -- Si es una devolución o cancelación, devolver productos al inventario
    -- (solo aplica para operaciones con extracción; NO para recepciones).
    IF p_nuevo_estado IN (3, 4) AND NOT v_es_recepcion THEN
        -- Recuperar los productos extraídos originalmente
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

            -- producto-v1 deja NULL cuando la venta fue en la base; el
            -- ledger exige la fila de app_dat_producto_presentacion.
            v_presentacion_devolver := COALESCE(
                v_productos_extraidos.id_presentacion,
                (
                    SELECT pp.id
                    FROM app_dat_producto_presentacion pp
                    WHERE pp.id_producto = v_productos_extraidos.id_producto
                      AND pp.es_base
                    ORDER BY pp.id
                    LIMIT 1
                )
            );

            -- Obtener inventario actual más reciente
            SELECT * INTO v_inventario_actual
            FROM app_dat_inventario_productos
            WHERE id_producto = v_productos_extraidos.id_producto
              AND COALESCE(id_variante, 0) = COALESCE(v_productos_extraidos.id_variante, 0)
              AND COALESCE(id_opcion_variante, 0) = COALESCE(v_productos_extraidos.id_opcion_variante, 0)
              AND COALESCE(id_presentacion, 0) = COALESCE(v_presentacion_devolver, 0)
              AND COALESCE(id_ubicacion, 0) = COALESCE(v_productos_extraidos.id_ubicacion, 0)
            ORDER BY created_at DESC
            LIMIT 1;

            -- Si no existe inventario previo, usar 0
            IF v_inventario_actual.cantidad_final IS NULL THEN
                v_inventario_actual.cantidad_final := 0;
            END IF;

            -- Actualizar inventario para devolver los productos
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
                v_presentacion_devolver,
                v_productos_extraidos.id_ubicacion,
                v_inventario_actual.cantidad_final,
                v_inventario_actual.cantidad_final + v_productos_extraidos.cantidad,
                v_productos_extraidos.sku_producto,
                v_productos_extraidos.sku_ubicacion,
                CASE
                    WHEN p_nuevo_estado = 3 THEN 4  -- Devolución
                    WHEN p_nuevo_estado = 4 THEN 5  -- Cancelación
                END,
                NOW()
            );
        END LOOP;

        -- Procesar productos elaborados para devolver ingredientes
        FOR v_productos_extraidos IN (
            SELECT
                ep.id_producto,
                ep.cantidad
            FROM app_dat_extraccion_productos ep
            INNER JOIN app_dat_producto p ON ep.id_producto = p.id
            WHERE ep.id_operacion = p_id_operacion
              AND p.es_elaborado = true
        ) LOOP

            -- Para cada producto elaborado, devolver sus ingredientes
            FOR v_ingrediente IN (
                SELECT
                    id_ingrediente,
                    cantidad_necesaria
                FROM app_dat_producto_ingredientes
                WHERE id_producto_elaborado = v_productos_extraidos.id_producto
            ) LOOP

                -- Calcular cantidad total de ingrediente a devolver
                v_cantidad_ingrediente_devolver := v_ingrediente.cantidad_necesaria * v_productos_extraidos.cantidad;

                -- Obtener el ÚLTIMO registro de inventario del ingrediente para obtener el id_presentacion
                SELECT * INTO v_ultimo_inventario
                FROM app_dat_inventario_productos
                WHERE id_producto = v_ingrediente.id_ingrediente
                ORDER BY created_at DESC
                LIMIT 1;

                -- Si no existe inventario previo del ingrediente, usar la
                -- presentacion base del ingrediente; sin ella no hay fila
                -- de ledger posible.
                IF v_ultimo_inventario IS NULL THEN
                    v_ultimo_inventario.cantidad_final := 0;
                    v_ultimo_inventario.id_presentacion := NULL;
                    v_ultimo_inventario.id_ubicacion := NULL;
                    v_ultimo_inventario.sku_producto := NULL;
                    v_ultimo_inventario.sku_ubicacion := NULL;
                END IF;
                IF v_ultimo_inventario.id_presentacion IS NULL THEN
                    v_ultimo_inventario.id_presentacion := (
                        SELECT pp.id
                        FROM app_dat_producto_presentacion pp
                        WHERE pp.id_producto = v_ingrediente.id_ingrediente
                          AND pp.es_base
                        ORDER BY pp.id
                        LIMIT 1
                    );
                END IF;

                -- Devolver ingrediente al inventario usando el id_presentacion del último registro
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
                        WHEN p_nuevo_estado = 3 THEN 6  -- Devolución de ingredientes
                        WHEN p_nuevo_estado = 4 THEN 7  -- Cancelación de ingredientes
                    END,
                    NOW()
                );
            END LOOP;
        END LOOP;
    END IF;
END;
$function$;

COMMIT;
