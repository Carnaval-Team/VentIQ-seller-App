-- ============================================================
-- TABLA: app_dat_log_modificacion_orden
-- Registra cada modificación realizada a una orden pendiente
-- ============================================================
CREATE TABLE IF NOT EXISTS app_dat_log_modificacion_orden (
    id            BIGSERIAL PRIMARY KEY,
    id_operacion  BIGINT        NOT NULL REFERENCES app_dat_operaciones(id),
    uuid_usuario  UUID          NOT NULL,
    accion        TEXT          NOT NULL,  -- 'add_product' | 'update_quantity' | 'remove_product'
    detalle       JSONB         NOT NULL,  -- snapshot completo de lo que se hizo
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_log_mod_orden_operacion  ON app_dat_log_modificacion_orden(id_operacion);
CREATE INDEX IF NOT EXISTS idx_log_mod_orden_usuario    ON app_dat_log_modificacion_orden(uuid_usuario);
CREATE INDEX IF NOT EXISTS idx_log_mod_orden_created_at ON app_dat_log_modificacion_orden(created_at DESC);

COMMENT ON TABLE  app_dat_log_modificacion_orden              IS 'Auditoría de cambios realizados a órdenes en estado Pendiente';
COMMENT ON COLUMN app_dat_log_modificacion_orden.accion       IS 'add_product | update_quantity | remove_product';
COMMENT ON COLUMN app_dat_log_modificacion_orden.detalle      IS 'JSON con el antes/después de la modificación';


-- ============================================================
-- FUNCIÓN: fn_actualizar_cantidad_producto_orden
-- Aumenta o disminuye la cantidad de un producto ya existente
-- en una orden pendiente, ajustando inventario e importe.
--
-- p_id_extraccion      → ID en app_dat_extraccion_productos
-- p_nueva_cantidad     → nueva cantidad deseada (> 0)
-- p_uuid_usuario       → UUID del usuario que hace el cambio
-- ============================================================
CREATE OR REPLACE FUNCTION fn_actualizar_cantidad_producto_orden(
    p_id_extraccion  BIGINT,
    p_nueva_cantidad NUMERIC,
    p_uuid_usuario   UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_extraccion        RECORD;
    v_operacion         RECORD;
    v_ultimo_inventario RECORD;
    v_delta             NUMERIC;
    v_nuevo_importe     NUMERIC;
    v_nuevo_total       NUMERIC;
    v_es_elaborado      BOOLEAN;
    v_ingrediente       RECORD;
    v_inv_ingrediente   RECORD;
BEGIN
    -- 1. Obtener datos actuales de la extracción
    SELECT e.*, o.id AS op_id
      INTO v_extraccion
      FROM app_dat_extraccion_productos e
      JOIN app_dat_operaciones           o ON o.id = e.id_operacion
     WHERE e.id = p_id_extraccion;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('status','error','message','Extracción no encontrada');
    END IF;

    -- 2. Verificar que la orden esté en estado Pendiente (estado = 1)
    SELECT eo.estado INTO v_operacion
      FROM app_dat_estado_operacion eo
     WHERE eo.id_operacion = v_extraccion.op_id
     ORDER BY eo.created_at DESC, eo.id DESC
     LIMIT 1;

    IF v_operacion.estado IS DISTINCT FROM 1 THEN
        RETURN jsonb_build_object('status','error','message','Solo se pueden editar órdenes en estado Pendiente');
    END IF;

    IF p_nueva_cantidad <= 0 THEN
        RETURN jsonb_build_object('status','error','message','La nueva cantidad debe ser mayor que 0. Para eliminar usa fn_eliminar_producto_orden.');
    END IF;

    -- 3. Calcular delta (diferencia entre nueva y antigua cantidad)
    v_delta := p_nueva_cantidad - v_extraccion.cantidad;

    -- 4. Verificar si el producto es elaborado
    SELECT es_elaborado INTO v_es_elaborado
      FROM app_dat_producto
     WHERE id = v_extraccion.id_producto;

    -- 5. Si no es elaborado, verificar/ajustar inventario base
    IF v_es_elaborado IS NOT TRUE THEN
        SELECT cantidad_final
          INTO v_ultimo_inventario
          FROM app_dat_inventario_productos
         WHERE id_producto = v_extraccion.id_producto
           AND COALESCE(id_variante,  0) = COALESCE(v_extraccion.id_variante,  0)
           AND COALESCE(id_ubicacion, 0) = COALESCE(v_extraccion.id_ubicacion, 0)
         ORDER BY created_at DESC, id DESC
         LIMIT 1;

        IF v_delta > 0 AND (v_ultimo_inventario IS NULL OR v_ultimo_inventario.cantidad_final < v_delta) THEN
            RETURN jsonb_build_object(
                'status','error',
                'message','Stock insuficiente para aumentar la cantidad',
                'disponible', COALESCE(v_ultimo_inventario.cantidad_final, 0),
                'requerido',  v_delta
            );
        END IF;

        -- Registrar ajuste de inventario del producto base
        INSERT INTO app_dat_inventario_productos (
            id_producto, id_variante, id_opcion_variante, id_ubicacion, id_presentacion,
            cantidad_inicial, cantidad_final,
            sku_producto, sku_ubicacion,
            origen_cambio, id_extraccion, created_at
        )
        SELECT
            v_extraccion.id_producto,
            v_extraccion.id_variante,
            v_extraccion.id_opcion_variante,
            v_extraccion.id_ubicacion,
            v_extraccion.id_presentacion,
            COALESCE(ip.cantidad_final, 0),
            COALESCE(ip.cantidad_final, 0) - v_delta,
            v_extraccion.sku_producto,
            v_extraccion.sku_ubicacion,
            3,   -- Origen: Venta / ajuste
            p_id_extraccion,
            NOW()
        FROM (
            SELECT cantidad_final
              FROM app_dat_inventario_productos
             WHERE id_producto = v_extraccion.id_producto
               AND COALESCE(id_variante,  0) = COALESCE(v_extraccion.id_variante,  0)
               AND COALESCE(id_ubicacion, 0) = COALESCE(v_extraccion.id_ubicacion, 0)
             ORDER BY created_at DESC, id DESC
             LIMIT 1
        ) ip;
    ELSE
        -- Producto elaborado: ajustar ingredientes
        FOR v_ingrediente IN
            SELECT id_ingrediente, cantidad_total_necesaria
              FROM fn_obtener_ingredientes_recursivos(v_extraccion.id_producto, ABS(v_delta))
        LOOP
            SELECT id_producto, id_variante, id_opcion_variante, id_ubicacion, id_presentacion,
                   cantidad_final, sku_producto, sku_ubicacion
              INTO v_inv_ingrediente
              FROM app_dat_inventario_productos
             WHERE id_producto = v_ingrediente.id_ingrediente
             ORDER BY created_at DESC
             LIMIT 1;

            IF v_delta > 0 THEN
                -- Aumentar cantidad → descontar más ingredientes
                IF v_inv_ingrediente IS NULL OR v_inv_ingrediente.cantidad_final < v_ingrediente.cantidad_total_necesaria THEN
                    RETURN jsonb_build_object(
                        'status','error',
                        'message','Stock insuficiente de ingrediente: ' ||
                            (SELECT denominacion FROM app_dat_producto WHERE id = v_ingrediente.id_ingrediente),
                        'id_ingrediente', v_ingrediente.id_ingrediente,
                        'disponible', COALESCE(v_inv_ingrediente.cantidad_final, 0),
                        'requerido',  v_ingrediente.cantidad_total_necesaria
                    );
                END IF;

                INSERT INTO app_dat_inventario_productos (
                    id_producto, id_variante, id_opcion_variante, id_ubicacion, id_presentacion,
                    cantidad_inicial, cantidad_final, sku_producto, sku_ubicacion,
                    origen_cambio, id_extraccion, created_at
                ) VALUES (
                    v_inv_ingrediente.id_producto,
                    v_inv_ingrediente.id_variante,
                    v_inv_ingrediente.id_opcion_variante,
                    v_inv_ingrediente.id_ubicacion,
                    v_inv_ingrediente.id_presentacion,
                    v_inv_ingrediente.cantidad_final,
                    v_inv_ingrediente.cantidad_final - v_ingrediente.cantidad_total_necesaria,
                    v_inv_ingrediente.sku_producto,
                    v_inv_ingrediente.sku_ubicacion,
                    4, p_id_extraccion, NOW()
                );
            ELSE
                -- Disminuir cantidad → devolver ingredientes
                INSERT INTO app_dat_inventario_productos (
                    id_producto, id_variante, id_opcion_variante, id_ubicacion, id_presentacion,
                    cantidad_inicial, cantidad_final, sku_producto, sku_ubicacion,
                    origen_cambio, id_extraccion, created_at
                ) VALUES (
                    v_inv_ingrediente.id_producto,
                    v_inv_ingrediente.id_variante,
                    v_inv_ingrediente.id_opcion_variante,
                    v_inv_ingrediente.id_ubicacion,
                    v_inv_ingrediente.id_presentacion,
                    COALESCE(v_inv_ingrediente.cantidad_final, 0),
                    COALESCE(v_inv_ingrediente.cantidad_final, 0) + v_ingrediente.cantidad_total_necesaria,
                    v_inv_ingrediente.sku_producto,
                    v_inv_ingrediente.sku_ubicacion,
                    4, p_id_extraccion, NOW()
                );
            END IF;
        END LOOP;
    END IF;

    -- 6. Actualizar extracción
    v_nuevo_importe := p_nueva_cantidad * v_extraccion.precio_unitario;

    UPDATE app_dat_extraccion_productos
       SET cantidad        = p_nueva_cantidad,
           importe         = v_nuevo_importe,
           importe_real    = p_nueva_cantidad * COALESCE(v_extraccion.precio_unitario, 0)
     WHERE id = p_id_extraccion;

    -- 7. Recalcular importe total de la venta
    SELECT COALESCE(SUM(cantidad * precio_unitario), 0)
      INTO v_nuevo_total
      FROM app_dat_extraccion_productos
     WHERE id_operacion = v_extraccion.op_id;

    UPDATE app_dat_operacion_venta
       SET importe_total = v_nuevo_total
     WHERE id_operacion = v_extraccion.op_id;

    -- 8. Actualizar pago más alto
    UPDATE app_dat_pago_venta
       SET monto = v_nuevo_total
     WHERE id = (
         SELECT id FROM app_dat_pago_venta
          WHERE id_operacion_venta = v_extraccion.op_id
          ORDER BY monto DESC LIMIT 1
     );

    -- 9. Log
    INSERT INTO app_dat_log_modificacion_orden
        (id_operacion, uuid_usuario, accion, detalle, created_at)
    VALUES (
        v_extraccion.op_id,
        p_uuid_usuario,
        'update_quantity',
        jsonb_build_object(
            'id_extraccion',    p_id_extraccion,
            'id_producto',      v_extraccion.id_producto,
            'cantidad_anterior',v_extraccion.cantidad,
            'cantidad_nueva',   p_nueva_cantidad,
            'importe_anterior', v_extraccion.importe,
            'importe_nuevo',    v_nuevo_importe,
            'delta',            v_delta,
            'nuevo_total_orden',v_nuevo_total
        ),
        NOW()
    );

    RETURN jsonb_build_object(
        'status',         'success',
        'id_extraccion',  p_id_extraccion,
        'cantidad_nueva', p_nueva_cantidad,
        'importe_nuevo',  v_nuevo_importe,
        'total_orden',    v_nuevo_total,
        'message',        'Cantidad actualizada correctamente'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('status','error','message','Error: ' || SQLERRM, 'sqlstate', SQLSTATE);
END;
$$;


-- ============================================================
-- FUNCIÓN: fn_eliminar_producto_orden
-- Elimina un producto de una orden pendiente y restaura stock
--
-- p_id_extraccion  → ID en app_dat_extraccion_productos
-- p_uuid_usuario   → UUID del usuario que hace el cambio
-- ============================================================
CREATE OR REPLACE FUNCTION fn_eliminar_producto_orden(
    p_id_extraccion  BIGINT,
    p_uuid_usuario   UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_extraccion       RECORD;
    v_nuevo_total      NUMERIC;
    v_es_elaborado     BOOLEAN;
    v_ingrediente      RECORD;
    v_inv_ingrediente  RECORD;
    v_estado           INT;
BEGIN
    -- 1. Obtener extracción
    SELECT e.*, o.id AS op_id
      INTO v_extraccion
      FROM app_dat_extraccion_productos e
      JOIN app_dat_operaciones           o ON o.id = e.id_operacion
     WHERE e.id = p_id_extraccion;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('status','error','message','Extracción no encontrada');
    END IF;

    -- 2. Verificar estado Pendiente
    SELECT eo.estado INTO v_estado
      FROM app_dat_estado_operacion eo
     WHERE eo.id_operacion = v_extraccion.op_id
     ORDER BY eo.created_at DESC, eo.id DESC
     LIMIT 1;

    IF v_estado IS DISTINCT FROM 1 THEN
        RETURN jsonb_build_object('status','error','message','Solo se pueden editar órdenes en estado Pendiente');
    END IF;

    -- 3. Verificar si es elaborado
    SELECT es_elaborado INTO v_es_elaborado
      FROM app_dat_producto WHERE id = v_extraccion.id_producto;

    -- 4. Restaurar inventario (devolver stock)
    IF v_es_elaborado IS NOT TRUE THEN
        INSERT INTO app_dat_inventario_productos (
            id_producto, id_variante, id_opcion_variante, id_ubicacion, id_presentacion,
            cantidad_inicial, cantidad_final,
            sku_producto, sku_ubicacion,
            origen_cambio, id_extraccion, created_at
        )
        SELECT
            v_extraccion.id_producto,
            v_extraccion.id_variante,
            v_extraccion.id_opcion_variante,
            v_extraccion.id_ubicacion,
            v_extraccion.id_presentacion,
            COALESCE(ip.cantidad_final, 0),
            COALESCE(ip.cantidad_final, 0) + v_extraccion.cantidad,  -- devolver stock
            v_extraccion.sku_producto,
            v_extraccion.sku_ubicacion,
            3,
            p_id_extraccion,
            NOW()
        FROM (
            SELECT cantidad_final
              FROM app_dat_inventario_productos
             WHERE id_producto = v_extraccion.id_producto
               AND COALESCE(id_variante,  0) = COALESCE(v_extraccion.id_variante,  0)
               AND COALESCE(id_ubicacion, 0) = COALESCE(v_extraccion.id_ubicacion, 0)
             ORDER BY created_at DESC, id DESC
             LIMIT 1
        ) ip;
    ELSE
        -- Elaborado: devolver ingredientes
        FOR v_ingrediente IN
            SELECT id_ingrediente, cantidad_total_necesaria
              FROM fn_obtener_ingredientes_recursivos(v_extraccion.id_producto, v_extraccion.cantidad)
        LOOP
            SELECT id_producto, id_variante, id_opcion_variante, id_ubicacion, id_presentacion,
                   cantidad_final, sku_producto, sku_ubicacion
              INTO v_inv_ingrediente
              FROM app_dat_inventario_productos
             WHERE id_producto = v_ingrediente.id_ingrediente
             ORDER BY created_at DESC LIMIT 1;

            INSERT INTO app_dat_inventario_productos (
                id_producto, id_variante, id_opcion_variante, id_ubicacion, id_presentacion,
                cantidad_inicial, cantidad_final, sku_producto, sku_ubicacion,
                origen_cambio, id_extraccion, created_at
            ) VALUES (
                v_inv_ingrediente.id_producto,
                v_inv_ingrediente.id_variante,
                v_inv_ingrediente.id_opcion_variante,
                v_inv_ingrediente.id_ubicacion,
                v_inv_ingrediente.id_presentacion,
                COALESCE(v_inv_ingrediente.cantidad_final, 0),
                COALESCE(v_inv_ingrediente.cantidad_final, 0) + v_ingrediente.cantidad_total_necesaria,
                v_inv_ingrediente.sku_producto,
                v_inv_ingrediente.sku_ubicacion,
                4, p_id_extraccion, NOW()
            );
        END LOOP;
    END IF;

    -- 5. Eliminar extracción
    DELETE FROM app_dat_extraccion_productos WHERE id = p_id_extraccion;

    -- 6. Recalcular total
    SELECT COALESCE(SUM(cantidad * precio_unitario), 0)
      INTO v_nuevo_total
      FROM app_dat_extraccion_productos
     WHERE id_operacion = v_extraccion.op_id;

    UPDATE app_dat_operacion_venta
       SET importe_total = v_nuevo_total
     WHERE id_operacion = v_extraccion.op_id;

    -- Actualizar pago más alto (si quedan productos)
    IF v_nuevo_total > 0 THEN
        UPDATE app_dat_pago_venta
           SET monto = v_nuevo_total
         WHERE id = (
             SELECT id FROM app_dat_pago_venta
              WHERE id_operacion_venta = v_extraccion.op_id
              ORDER BY monto DESC LIMIT 1
         );
    END IF;

    -- 7. Log
    INSERT INTO app_dat_log_modificacion_orden
        (id_operacion, uuid_usuario, accion, detalle, created_at)
    VALUES (
        v_extraccion.op_id,
        p_uuid_usuario,
        'remove_product',
        jsonb_build_object(
            'id_extraccion',   p_id_extraccion,
            'id_producto',     v_extraccion.id_producto,
            'cantidad',        v_extraccion.cantidad,
            'precio_unitario', v_extraccion.precio_unitario,
            'importe',         v_extraccion.importe,
            'nuevo_total_orden',v_nuevo_total
        ),
        NOW()
    );

    RETURN jsonb_build_object(
        'status',       'success',
        'id_extraccion',p_id_extraccion,
        'total_orden',  v_nuevo_total,
        'message',      'Producto eliminado correctamente'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('status','error','message','Error: ' || SQLERRM, 'sqlstate', SQLSTATE);
END;
$$;


-- ============================================================
-- FUNCIÓN: fn_agregar_producto_orden_pendiente
-- Agrega un producto nuevo a una orden que ya existe y está
-- en estado Pendiente, sin crear una nueva operación.
--
-- Reutiliza la misma lógica de inventario de fn_registrar_venta.
-- ============================================================
CREATE OR REPLACE FUNCTION fn_agregar_producto_orden_pendiente(
    p_id_operacion   BIGINT,
    p_producto       JSONB,       -- mismo shape que en fn_registrar_venta
    p_uuid_usuario   UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado           INT;
    v_id_extraccion    BIGINT;
    v_importe          NUMERIC;
    v_nuevo_total      NUMERIC;
    v_es_elaborado     BOOLEAN;
    v_ingrediente      RECORD;
    v_inv_ingrediente  RECORD;
    v_extraccion_exist RECORD;   -- para detectar duplicado
    v_nueva_cantidad   NUMERIC;
BEGIN
    -- 1. Verificar estado Pendiente
    SELECT eo.estado INTO v_estado
      FROM app_dat_estado_operacion eo
     WHERE eo.id_operacion = p_id_operacion
     ORDER BY eo.created_at DESC, eo.id DESC
     LIMIT 1;

    IF v_estado IS DISTINCT FROM 1 THEN
        RETURN jsonb_build_object('status','error','message','Solo se pueden editar órdenes en estado Pendiente');
    END IF;

    -- 2. Validar campos mínimos
    IF p_producto->>'id_producto'     IS NULL OR
       p_producto->>'cantidad'        IS NULL OR
       p_producto->>'precio_unitario' IS NULL THEN
        RETURN jsonb_build_object('status','error','message','El producto debe incluir id_producto, cantidad y precio_unitario');
    END IF;

    -- 3. Buscar si ya existe una extracción con el mismo producto/variante/ubicación
    SELECT ep.id, ep.cantidad
      INTO v_extraccion_exist
      FROM app_dat_extraccion_productos ep
     WHERE ep.id_operacion = p_id_operacion
       AND ep.id_producto  = (p_producto->>'id_producto')::BIGINT
       AND COALESCE(ep.id_variante,  0) = COALESCE(NULLIF(p_producto->>'id_variante',  '')::BIGINT, 0)
       AND COALESCE(ep.id_ubicacion, 0) = COALESCE(NULLIF(p_producto->>'id_ubicacion', '')::BIGINT, 0)
     ORDER BY ep.created_at DESC
     LIMIT 1;

    IF FOUND THEN
        -- ── Producto duplicado: redirigir a fn_actualizar_cantidad_producto_orden ──
        v_nueva_cantidad := v_extraccion_exist.cantidad + (p_producto->>'cantidad')::NUMERIC;

        RETURN fn_actualizar_cantidad_producto_orden(
            v_extraccion_exist.id,
            v_nueva_cantidad,
            p_uuid_usuario
        );
    END IF;

    v_importe := (p_producto->>'cantidad')::NUMERIC * (p_producto->>'precio_unitario')::NUMERIC;

    -- 4. Insertar extracción (producto nuevo en la orden)
    INSERT INTO app_dat_extraccion_productos (
        id_operacion, id_producto, id_variante, id_opcion_variante,
        id_ubicacion, id_presentacion,
        cantidad, precio_unitario, importe, importe_real,
        sku_producto, sku_ubicacion, created_at
    ) VALUES (
        p_id_operacion,
        (p_producto->>'id_producto')::BIGINT,
        NULLIF(p_producto->>'id_variante',       '')::BIGINT,
        NULLIF(p_producto->>'id_opcion_variante','')::BIGINT,
        NULLIF(p_producto->>'id_ubicacion',      '')::BIGINT,
        NULLIF(p_producto->>'id_presentacion',   '')::BIGINT,
        (p_producto->>'cantidad')::NUMERIC,
        (p_producto->>'precio_unitario')::NUMERIC,
        v_importe,
        (p_producto->>'cantidad')::NUMERIC * COALESCE(
            NULLIF(p_producto->>'precio_real','')::NUMERIC,
            (p_producto->>'precio_unitario')::NUMERIC
        ),
        p_producto->>'sku_producto',
        p_producto->>'sku_ubicacion',
        NOW()
    ) RETURNING id INTO v_id_extraccion;

    -- 4. Verificar si es elaborado
    SELECT es_elaborado INTO v_es_elaborado
      FROM app_dat_producto WHERE id = (p_producto->>'id_producto')::BIGINT;

    -- 5. Ajustar inventario
    IF v_es_elaborado IS NOT TRUE THEN
        INSERT INTO app_dat_inventario_productos (
            id_producto, id_variante, id_opcion_variante, id_ubicacion, id_presentacion,
            cantidad_inicial, cantidad_final, sku_producto, sku_ubicacion,
            origen_cambio, id_extraccion, created_at
        )
        SELECT
            (p_producto->>'id_producto')::BIGINT,
            NULLIF(p_producto->>'id_variante',       '')::BIGINT,
            NULLIF(p_producto->>'id_opcion_variante','')::BIGINT,
            NULLIF(p_producto->>'id_ubicacion',      '')::BIGINT,
            NULLIF(p_producto->>'id_presentacion',   '')::BIGINT,
            COALESCE(ip.cantidad_final, 0),
            COALESCE(ip.cantidad_final, 0) - (p_producto->>'cantidad')::NUMERIC,
            p_producto->>'sku_producto',
            p_producto->>'sku_ubicacion',
            3, v_id_extraccion, NOW()
        FROM (
            SELECT cantidad_final
              FROM app_dat_inventario_productos
             WHERE id_producto = (p_producto->>'id_producto')::BIGINT
               AND COALESCE(id_variante,  0) = COALESCE(NULLIF(p_producto->>'id_variante','')::BIGINT, 0)
               AND COALESCE(id_ubicacion, 0) = COALESCE(NULLIF(p_producto->>'id_ubicacion','')::BIGINT, 0)
             ORDER BY created_at DESC, id DESC
             LIMIT 1
        ) ip;
    ELSE
        -- Elaborado: descontar ingredientes
        FOR v_ingrediente IN
            SELECT id_ingrediente, cantidad_total_necesaria
              FROM fn_obtener_ingredientes_recursivos(
                  (p_producto->>'id_producto')::BIGINT,
                  (p_producto->>'cantidad')::NUMERIC
              )
        LOOP
            SELECT id_producto, id_variante, id_opcion_variante, id_ubicacion, id_presentacion,
                   cantidad_final, sku_producto, sku_ubicacion
              INTO v_inv_ingrediente
              FROM app_dat_inventario_productos
             WHERE id_producto = v_ingrediente.id_ingrediente
             ORDER BY created_at DESC LIMIT 1;

            IF v_inv_ingrediente IS NULL OR v_inv_ingrediente.cantidad_final < v_ingrediente.cantidad_total_necesaria THEN
                RETURN jsonb_build_object(
                    'status','error',
                    'message','Stock insuficiente de ingrediente: ' ||
                        (SELECT denominacion FROM app_dat_producto WHERE id = v_ingrediente.id_ingrediente),
                    'id_ingrediente', v_ingrediente.id_ingrediente,
                    'disponible', COALESCE(v_inv_ingrediente.cantidad_final, 0),
                    'requerido',  v_ingrediente.cantidad_total_necesaria
                );
            END IF;

            INSERT INTO app_dat_inventario_productos (
                id_producto, id_variante, id_opcion_variante, id_ubicacion, id_presentacion,
                cantidad_inicial, cantidad_final, sku_producto, sku_ubicacion,
                origen_cambio, id_extraccion, created_at
            ) VALUES (
                v_inv_ingrediente.id_producto,
                v_inv_ingrediente.id_variante,
                v_inv_ingrediente.id_opcion_variante,
                v_inv_ingrediente.id_ubicacion,
                v_inv_ingrediente.id_presentacion,
                v_inv_ingrediente.cantidad_final,
                v_inv_ingrediente.cantidad_final - v_ingrediente.cantidad_total_necesaria,
                v_inv_ingrediente.sku_producto,
                v_inv_ingrediente.sku_ubicacion,
                4, v_id_extraccion, NOW()
            );
        END LOOP;
    END IF;

    -- 6. Recalcular total
    SELECT COALESCE(SUM(cantidad * precio_unitario), 0)
      INTO v_nuevo_total
      FROM app_dat_extraccion_productos
     WHERE id_operacion = p_id_operacion;

    UPDATE app_dat_operacion_venta
       SET importe_total = v_nuevo_total
     WHERE id_operacion = p_id_operacion;

    -- 7. Actualizar pago más alto
    UPDATE app_dat_pago_venta
       SET monto = v_nuevo_total
     WHERE id = (
         SELECT id FROM app_dat_pago_venta
          WHERE id_operacion_venta = p_id_operacion
          ORDER BY monto DESC LIMIT 1
     );

    -- 8. Log
    INSERT INTO app_dat_log_modificacion_orden
        (id_operacion, uuid_usuario, accion, detalle, created_at)
    VALUES (
        p_id_operacion,
        p_uuid_usuario,
        'add_product',
        jsonb_build_object(
            'id_extraccion',   v_id_extraccion,
            'producto',        p_producto,
            'importe',         v_importe,
            'nuevo_total_orden',v_nuevo_total
        ),
        NOW()
    );

    RETURN jsonb_build_object(
        'status',        'success',
        'id_extraccion', v_id_extraccion,
        'importe',       v_importe,
        'total_orden',   v_nuevo_total,
        'message',       'Producto agregado correctamente'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('status','error','message','Error: ' || SQLERRM, 'sqlstate', SQLSTATE);
END;
$$;
