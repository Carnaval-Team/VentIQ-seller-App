-- Función v3: Registrar apertura de turno con observaciones personalizadas
CREATE OR REPLACE FUNCTION registrar_apertura_turno_v3(
    p_efectivo_inicial NUMERIC,
    p_id_tpv BIGINT,
    p_id_vendedor BIGINT,
    p_usuario UUID,
    p_maneja_inventario BOOLEAN,
    p_productos JSONB DEFAULT NULL,
    p_observaciones TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_id_operacion BIGINT;
    v_id_tienda BIGINT;
    v_turno_inventario_abierto BIGINT;
    v_producto JSONB;
    v_observaciones_finales TEXT;
BEGIN
    -- Establecer contexto seguro
    SET search_path = public;

    -- Validar autenticación
    IF p_usuario IS NULL THEN
        RAISE EXCEPTION 'Usuario no autenticado';
    END IF;

    -- Validar que el TPV exista
    SELECT id_tienda INTO v_id_tienda
    FROM app_dat_tpv
    WHERE id = p_id_tpv;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'TPV con id % no encontrado', p_id_tpv;
    END IF;

    -- Validar que el vendedor exista
    PERFORM 1 FROM app_dat_vendedor WHERE id = p_id_vendedor;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Vendedor con id % no encontrado', p_id_vendedor;
    END IF;

    -- Si el vendedor quiere manejar el inventario, verificar que no haya otro turno abierto que ya lo haga
    IF p_maneja_inventario THEN
        SELECT ct.id INTO v_turno_inventario_abierto
        FROM app_dat_caja_turno ct
        WHERE ct.id_tpv = p_id_tpv
          AND ct.maneja_inventario = true
          AND ct.estado = 1; -- Turno abierto

        IF v_turno_inventario_abierto IS NOT NULL THEN
            RAISE EXCEPTION 'Ya existe un turno abierto para este TPV que maneja el inventario (ID: %). Solo uno puede gestionar el inventario.', v_turno_inventario_abierto;
        END IF;
    END IF;

    -- Construir observaciones finales combinando info del sistema con observaciones del usuario
    v_observaciones_finales := format('Apertura de caja con fondo inicial de %s. Maneja inventario: %s', p_efectivo_inicial, p_maneja_inventario);
    
    -- Si hay observaciones del usuario, agregarlas
    IF p_observaciones IS NOT NULL AND LENGTH(TRIM(p_observaciones)) > 0 THEN
        v_observaciones_finales := v_observaciones_finales || E'\n\n--- OBSERVACIONES ---\n' || p_observaciones;
    END IF;

    -- Crear operación de apertura con observaciones completas
    INSERT INTO app_dat_operaciones (id_tipo_operacion, uuid, id_tienda, observaciones)
    VALUES (
        (SELECT id FROM app_nom_tipo_operacion WHERE LOWER(denominacion) = 'apertura de caja'),
        p_usuario,
        v_id_tienda,
        v_observaciones_finales
    )
    RETURNING id INTO v_id_operacion;

    -- Registrar productos recibidos (opcional)
    IF p_productos IS NOT NULL AND jsonb_array_length(p_productos) > 0 THEN
        FOR v_producto IN SELECT * FROM jsonb_array_elements(p_productos)
        LOOP
            IF (v_producto->>'id_producto') IS NULL OR (v_producto->>'id_ubicacion') IS NULL THEN
                RAISE EXCEPTION 'Cada producto debe tener id_producto e id_ubicacion';
            END IF;

            INSERT INTO app_dat_control_productos (
                id_operacion,
                id_producto,
                id_variante,
                id_ubicacion,
                id_presentacion,
                cantidad,
                sku_producto,
                sku_ubicacion
            )
            SELECT
                v_id_operacion,
                (v_producto->>'id_producto')::BIGINT,
                NULLIF((v_producto->>'id_variante')::TEXT, 'null')::BIGINT,
                (v_producto->>'id_ubicacion')::BIGINT,
                NULLIF((v_producto->>'id_presentacion')::TEXT, 'null')::BIGINT,
                GREATEST(COALESCE((v_producto->>'cantidad')::NUMERIC, 0), 0),
                p.sku,
                l.sku_codigo
            FROM app_dat_producto p
            JOIN app_dat_layout_almacen l ON l.id = (v_producto->>'id_ubicacion')::BIGINT
            WHERE p.id = (v_producto->>'id_producto')::BIGINT;

            IF NOT FOUND THEN
                RAISE WARNING 'No se encontró producto o ubicación para el registro: %', v_producto;
            END IF;
        END LOOP;
    END IF;

    -- Registrar estado: Ejecutada (estado 2)
    INSERT INTO app_dat_estado_operacion (id_operacion, estado, uuid)
    VALUES (v_id_operacion, 2, p_usuario);

    -- Registrar el turno
    INSERT INTO app_dat_caja_turno (
        id_operacion_apertura,
        id_tpv,
        id_vendedor,
        efectivo_inicial,
        creado_por,
        estado,
        maneja_inventario
    ) VALUES (
        v_id_operacion,
        p_id_tpv,
        p_id_vendedor,
        p_efectivo_inicial,
        p_usuario,
        1, -- Abierto
        p_maneja_inventario
    );

    -- Retornar el ID de la operación de apertura
    RETURN v_id_operacion;
END;
$$;

-- Comentario de la función
COMMENT ON FUNCTION registrar_apertura_turno_v3 IS 
'Versión 3: Registra apertura de turno con soporte para observaciones personalizadas.
Incluye información de excesos/defectos de inventario generada automáticamente por la app.
Parámetros:
- p_efectivo_inicial: Monto inicial en caja
- p_id_tpv: ID del punto de venta
- p_id_vendedor: ID del vendedor
- p_usuario: UUID del usuario autenticado
- p_maneja_inventario: Si el turno manejará inventario
- p_productos: Array JSON con productos contados (opcional)
- p_observaciones: Observaciones del usuario + diferencias de inventario (opcional)
Retorna: ID de la operación de apertura creada';

-- Ejemplo de uso:
/*
SELECT registrar_apertura_turno_v3(
    p_efectivo_inicial := 500.00,
    p_id_tpv := 5,
    p_id_vendedor := 123,
    p_usuario := 'uuid-del-usuario',
    p_maneja_inventario := true,
    p_productos := '[
        {"id_producto": 100, "id_ubicacion": 10, "cantidad": 50},
        {"id_producto": 101, "id_ubicacion": 10, "cantidad": 30}
    ]'::jsonb,
    p_observaciones := 'Turno de mañana

--- INVENTARIO ---
FALTANTES:
Faltan 5.00 unidades de Pizza Margarita
Faltan 2.50 unidades de Coca Cola

EXCESOS:
Sobran 3.00 unidades de Hamburguesa'
);
*/
