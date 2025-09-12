
DECLARE
    v_id_turno BIGINT;
    v_id_operacion_apertura BIGINT;
    v_id_tienda BIGINT;
    v_id_operacion_cierre BIGINT;
    v_producto JSONB;
    v_maneja_inventario BOOLEAN;
    v_producto_id BIGINT;
    v_ubicacion_id BIGINT;
BEGIN
    -- Establecer contexto
    SET search_path = public;

    -- Validar autenticación
    IF p_usuario IS NULL THEN
        RAISE EXCEPTION 'Usuario no autenticado';
    END IF;

    -- Obtener el turno abierto y si maneja inventario
    SELECT ct.id, ct.id_operacion_apertura, op.id_tienda, ct.maneja_inventario
    INTO v_id_turno, v_id_operacion_apertura, v_id_tienda, v_maneja_inventario
    FROM app_dat_caja_turno ct
    JOIN app_dat_operaciones op ON ct.id_operacion_apertura = op.id
    WHERE ct.id_tpv = p_id_tpv AND ct.estado = 1 and ct.creado_por = p_usuario;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No se encontró un turno abierto para el TPV %', p_id_tpv;
    END IF;

    -- Crear operación de cierre
    INSERT INTO app_dat_operaciones (id_tipo_operacion, uuid, id_tienda, observaciones)
    VALUES (
        17, -- Asegúrate de que sea "Cierre de Caja"
        p_usuario,
        v_id_tienda,
        COALESCE(p_observaciones, 'Cierre de turno')
    )
    RETURNING id INTO v_id_operacion_cierre;

    -- Registrar productos solo si este turno maneja inventario
    IF v_maneja_inventario THEN
        -- Validar que p_productos no sea NULL ni vacío
        IF p_productos IS NULL THEN
            RAISE EXCEPTION 'El parámetro p_productos es obligatorio porque este turno maneja el inventario';
        END IF;

        IF jsonb_array_length(p_productos) = 0 THEN
            RAISE EXCEPTION 'La lista de productos no puede estar vacía porque este turno maneja el inventario';
        END IF;

        -- Registrar cada producto
        FOR v_producto IN SELECT * FROM jsonb_array_elements(p_productos)
        LOOP
            v_producto_id := (v_producto->>'id_producto')::BIGINT;
            v_ubicacion_id := (v_producto->>'id_ubicacion')::BIGINT;

            IF v_producto_id IS NULL THEN
                RAISE EXCEPTION 'id_producto es obligatorio en p_productos';
            END IF;
            IF v_ubicacion_id IS NULL THEN
                RAISE EXCEPTION 'id_ubicacion es obligatorio en p_productos';
            END IF;

            INSERT INTO app_dat_control_productos (
                id_operacion,
                id_producto,
                id_ubicacion,
                cantidad
            ) VALUES (
                v_id_operacion_cierre,
                v_producto_id,
                v_ubicacion_id,
                GREATEST(COALESCE((v_producto->>'cantidad')::NUMERIC, 0), 0)
            );
        END LOOP;
    ELSE
        -- Si no maneja inventario, permitir p_productos NULL o vacío
        -- No se hace nada, es válido
        IF p_productos IS NOT NULL AND jsonb_array_length(p_productos) > 0 THEN
            RAISE WARNING 'Productos enviados en cierre, pero este turno no maneja inventario. Serán ignorados.';
        END IF;
    END IF;

    -- Registrar estado: Ejecutada (estado 2)
    INSERT INTO app_dat_estado_operacion (id_operacion, estado, uuid)
    VALUES (v_id_operacion_cierre, 2, p_usuario);

    -- Actualizar el turno a cerrado
    UPDATE app_dat_caja_turno
    SET
        id_operacion_cierre = v_id_operacion_cierre,
        efectivo_real = p_efectivo_real,
        fecha_cierre = NOW(),
        estado = 2, -- Cerrado
        observaciones = p_observaciones,
        cerrado_por = p_usuario
    WHERE id = v_id_turno;

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error en cerrar_turno: % | Detalle: %', SQLERRM, SQLSTATE;
END;
