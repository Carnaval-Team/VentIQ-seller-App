-- Idempotencia: si el turno ya está cerrado por el mismo usuario, retorna TRUE
-- en lugar de lanzar excepción (evita re-cierres duplicados).
--
-- Fix multi-open: varios turnos abiertos del mismo TPV/usuario (apertura
-- offline duplicada al sincronizar) hacían fallar el SELECT INTO sin LIMIT
-- ("query returned more than one row") y el turno quedaba abierto online.

CREATE OR REPLACE FUNCTION public.fn_cerrar_turno_tpv(
    p_id_tpv bigint,
    p_efectivo_real numeric,
    p_usuario uuid,
    p_productos jsonb DEFAULT NULL::jsonb,
    p_observaciones text DEFAULT NULL::text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
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
    SET search_path = public;

    IF p_usuario IS NULL THEN
        RAISE EXCEPTION 'Usuario no autenticado';
    END IF;

    SELECT ct.id, ct.id_operacion_apertura, op.id_tienda, ct.maneja_inventario
    INTO v_id_turno, v_id_operacion_apertura, v_id_tienda, v_maneja_inventario
    FROM app_dat_caja_turno ct
    JOIN app_dat_operaciones op ON ct.id_operacion_apertura = op.id
    WHERE ct.id_tpv = p_id_tpv AND ct.estado = 1 AND ct.creado_por = p_usuario
    ORDER BY ct.fecha_apertura DESC NULLS LAST, ct.id DESC
    LIMIT 1;

    IF NOT FOUND THEN
        -- Idempotencia: turno ya cerrado por este usuario en este TPV.
        SELECT ct.id
        INTO v_id_turno
        FROM app_dat_caja_turno ct
        WHERE ct.id_tpv = p_id_tpv
          AND ct.creado_por = p_usuario
          AND ct.estado = 2
        ORDER BY ct.fecha_cierre DESC NULLS LAST, ct.id DESC
        LIMIT 1;

        IF FOUND THEN
            RETURN TRUE;
        END IF;

        RAISE EXCEPTION 'No se encontró un turno abierto para el TPV %', p_id_tpv;
    END IF;

    INSERT INTO app_dat_operaciones (id_tipo_operacion, uuid, id_tienda, observaciones)
    VALUES (
        17,
        p_usuario,
        v_id_tienda,
        COALESCE(p_observaciones, 'Cierre de turno')
    )
    RETURNING id INTO v_id_operacion_cierre;

    IF v_maneja_inventario THEN
        IF p_productos IS NULL THEN
            RAISE EXCEPTION 'El parámetro p_productos es obligatorio porque este turno maneja el inventario';
        END IF;

        IF jsonb_array_length(p_productos) = 0 THEN
            RAISE EXCEPTION 'La lista de productos no puede estar vacía porque este turno maneja el inventario';
        END IF;

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
        IF p_productos IS NOT NULL AND jsonb_array_length(p_productos) > 0 THEN
            RAISE WARNING 'Productos enviados en cierre, pero este turno no maneja inventario. Serán ignorados.';
        END IF;
    END IF;

    INSERT INTO app_dat_estado_operacion (id_operacion, estado, uuid)
    VALUES (v_id_operacion_cierre, 2, p_usuario);

    UPDATE app_dat_caja_turno
    SET
        id_operacion_cierre = v_id_operacion_cierre,
        efectivo_real = p_efectivo_real,
        fecha_cierre = NOW(),
        estado = 2,
        observaciones = p_observaciones,
        cerrado_por = p_usuario
    WHERE id = v_id_turno;

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error en cerrar_turno: % | Detalle: %', SQLERRM, SQLSTATE;
END;
$function$;
