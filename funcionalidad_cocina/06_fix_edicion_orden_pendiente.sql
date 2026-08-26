-- ============================================================================
-- 06 · Fase 0 · Fix de las rutas de edicion de orden pendiente
-- ============================================================================
-- Proyecto Supabase: vsieeihstajlrdvpuooh
-- Aplicar en: SQL Editor del dashboard. Idempotente (CREATE OR REPLACE).
-- REQUISITOS: 01_helpers_bom_almacen.sql y 05_helpers_devolucion_bom.sql aplicados.
--
-- Reemplaza las tres funciones de edicion de orden pendiente, escritas sobre la
-- definicion REAL de produccion exportada con la consulta 4.1:
--
--   fn_actualizar_cantidad_producto_orden(bigint,numeric,uuid)
--   fn_agregar_producto_orden_pendiente(bigint,jsonb,uuid)
--   fn_eliminar_producto_orden(bigint,uuid)
--
-- NO se toca _fn_distribuir_pagos_orden: no maneja inventario.
--
--
-- CAMBIO 1 · Materia prima acotada al almacen (el mismo fix del 03)
-- -----------------------------------------------------------------
-- Las tres funciones descontaban o devolvian MP con el patron roto: ultima fila
-- global del ingrediente, sin filtrar almacen, una sola ubicacion. Ahora delegan
-- en los helpers, que resuelven el almacen de la linea con
-- fn_almacen_de_extraccion / fn_almacen_de_operacion.
--
--
-- CAMBIO 2 · Unificar el criterio de "no descuenta stock propio"
-- --------------------------------------------------------------
-- Habia una INCONSISTENCIA real entre funciones:
--
--   fn_registrar_venta                     -> (es_elaborado OR es_servicio)
--   fn_registrar_venta_mesa                -> (es_elaborado OR es_servicio)
--   fn_actualizar_cantidad_producto_orden  -> (es_elaborado OR es_servicio)
--   fn_agregar_producto_orden_pendiente    -> (es_elaborado OR es_servicio)
--   fn_eliminar_producto_orden             -> es_elaborado          <-- SOLO ESTA
--
-- Consecuencia para un producto con es_servicio = true y es_elaborado = false
-- (hay 46 en la base: MANGUERA POR METROS, CARGA DE ACEITE, ELECTRICIDAD...):
--
--   al vender    -> se trata como servicio, NO se descuenta stock propio;
--   al quitarlo  -> fn_eliminar_producto_orden lo trata como producto normal
--                   y DEVUELVE stock que nunca se habia descontado.
--
-- Eso crea stock fantasma. Verificado en produccion antes de este fix:
-- 8 filas de app_dat_inventario_productos con origen_cambio = 3 que SUBEN el
-- stock de un servicio, +35.3 unidades en total:
--
--   10086  MANGUERA POR METROS   +22.3
--    2624  CARGA DE ACEITE        +9.0
--    9448  SOLDADURA              +3.0
--    2643  ELECTRICIDAD           +1.0
--
-- Aqui fn_eliminar_producto_orden pasa a usar (es_elaborado OR es_servicio),
-- igual que las otras cuatro. Este archivo NO corrige el stock ya inflado; para
-- eso esta la seccion 6.4 (diagnostico) y el ajuste debe hacerse por la via
-- normal de ajuste de inventario, con su trazabilidad.
--
--
-- CONTRATO CON FLUTTER
-- --------------------
-- Los mensajes de error de estas tres funciones se conservan tal cual
-- ('Stock insuficiente de ingrediente: ...' con 'disponible' y 'requerido'),
-- porque el cliente ya los muestra. Se agregan campos, no se quitan.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 6.1 fn_actualizar_cantidad_producto_orden
-- Subir o bajar la cantidad de una linea de una orden pendiente.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_actualizar_cantidad_producto_orden(
    p_id_extraccion bigint,
    p_nueva_cantidad numeric,
    p_uuid_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_extraccion        RECORD;
    v_operacion         RECORD;
    v_ultimo_inventario RECORD;
    v_delta             NUMERIC;
    v_nuevo_importe     NUMERIC;
    v_nuevo_total       NUMERIC;
    v_es_elaborado      BOOLEAN;
    v_id_almacen        BIGINT;
    v_bom               JSONB;
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
    SELECT (es_elaborado or es_servicio) INTO v_es_elaborado
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
        -- ══════════════════════════════════════════════════════════════════
        -- FASE 0 · Ajuste de materia prima acotado al almacen de la linea.
        --
        -- Antes: lookup global del ingrediente (cualquier almacen, una sola
        -- ubicacion). Ahora se resuelve el almacen de la linea y se delega en
        -- los helpers, que suman todas las ubicaciones de ESE almacen.
        -- ══════════════════════════════════════════════════════════════════
        v_id_almacen := public.fn_almacen_de_extraccion(p_id_extraccion);

        IF v_id_almacen IS NULL THEN
            RETURN jsonb_build_object(
                'status','error',
                'message','No se pudo determinar el almacen de la linea para ajustar la materia prima',
                'error_code','ALMACEN_NOT_RESOLVED',
                'id_extraccion', p_id_extraccion
            );
        END IF;

        IF v_delta > 0 THEN
            -- Aumentar cantidad → descontar más ingredientes
            v_bom := public.fn_descontar_ingredientes_elaborado(
                p_id_producto_elaborado := v_extraccion.id_producto,
                p_cantidad              := v_delta,
                p_id_almacen            := v_id_almacen,
                p_id_extraccion         := p_id_extraccion,
                p_origen_cambio         := 4
            );
        ELSIF v_delta < 0 THEN
            -- Disminuir cantidad → devolver ingredientes
            v_bom := public.fn_devolver_ingredientes_elaborado(
                p_id_producto_elaborado := v_extraccion.id_producto,
                p_cantidad              := ABS(v_delta),
                p_id_almacen            := v_id_almacen,
                p_id_extraccion         := p_id_extraccion,
                p_origen_cambio         := 4
            );
        ELSE
            -- delta = 0: nada que mover
            v_bom := jsonb_build_object('status','success','lineas_afectadas',0);
        END IF;

        IF (v_bom->>'status') <> 'success' THEN
            -- Reescribir al formato de error que ya espera esta pantalla,
            -- conservando el detalle del helper.
            RETURN jsonb_build_object(
                'status',        'error',
                'message',       COALESCE(v_bom->>'message', 'Error ajustando materia prima'),
                'error_code',    COALESCE(v_bom->>'error_code', 'BOM_ERROR'),
                'id_ingrediente', v_bom->'id_ingrediente',
                'disponible',    COALESCE(v_bom->'cantidad_disponible', to_jsonb(0)),
                'requerido',     COALESCE(v_bom->'cantidad_requerida',  to_jsonb(0)),
                'id_almacen',    v_id_almacen
            );
        END IF;
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

    -- 8. Redistribuir pagos proporcionalmente
    PERFORM _fn_distribuir_pagos_orden(v_extraccion.op_id, v_nuevo_total);

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
            'nuevo_total_orden',v_nuevo_total,
            'id_almacen_bom',   v_id_almacen
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
$function$;

GRANT EXECUTE ON FUNCTION public.fn_actualizar_cantidad_producto_orden(bigint, numeric, uuid) TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 6.2 fn_agregar_producto_orden_pendiente
-- Agregar un producto a una orden ya creada y pendiente.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_agregar_producto_orden_pendiente(
    p_id_operacion bigint,
    p_producto jsonb,
    p_uuid_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_estado           INT;
    v_id_extraccion    BIGINT;
    v_importe          NUMERIC;
    v_nuevo_total      NUMERIC;
    v_es_elaborado     BOOLEAN;
    v_extraccion_exist RECORD;   -- para detectar duplicado
    v_nueva_cantidad   NUMERIC;
    v_id_medio_pago    INT;
    v_id_almacen       BIGINT;
    v_bom              JSONB;
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
       p_producto->>'precio_unitario' IS NULL OR
       p_producto->>'id_medio_pago'   IS NULL THEN
        RETURN jsonb_build_object('status','error','message','El producto debe incluir id_producto, cantidad, precio_unitario e id_medio_pago');
    END IF;

    v_id_medio_pago := (p_producto->>'id_medio_pago')::INT;

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

    -- 5. Verificar si es elaborado
    SELECT (es_elaborado or es_servicio) INTO v_es_elaborado
      FROM app_dat_producto WHERE id = (p_producto->>'id_producto')::BIGINT;

    -- 6. Ajustar inventario
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
        -- ══════════════════════════════════════════════════════════════════
        -- FASE 0 · Descuento de materia prima acotado al almacen del TPV de la
        -- orden. Si la linea trae ubicacion propia, fn_almacen_de_extraccion la
        -- prioriza; si no, cae al almacen del TPV.
        -- ══════════════════════════════════════════════════════════════════
        v_id_almacen := COALESCE(
            public.fn_almacen_de_extraccion(v_id_extraccion),
            public.fn_almacen_de_operacion(p_id_operacion)
        );

        IF v_id_almacen IS NULL THEN
            RETURN jsonb_build_object(
                'status','error',
                'message','No se pudo determinar el almacen para descontar la materia prima',
                'error_code','ALMACEN_NOT_RESOLVED',
                'id_operacion', p_id_operacion
            );
        END IF;

        v_bom := public.fn_descontar_ingredientes_elaborado(
            p_id_producto_elaborado := (p_producto->>'id_producto')::BIGINT,
            p_cantidad              := (p_producto->>'cantidad')::NUMERIC,
            p_id_almacen            := v_id_almacen,
            p_id_extraccion         := v_id_extraccion,
            p_origen_cambio         := 4
        );

        IF (v_bom->>'status') <> 'success' THEN
            RETURN jsonb_build_object(
                'status',        'error',
                'message',       COALESCE(v_bom->>'message', 'Error descontando materia prima'),
                'error_code',    COALESCE(v_bom->>'error_code', 'BOM_ERROR'),
                'id_ingrediente', v_bom->'id_ingrediente',
                'disponible',    COALESCE(v_bom->'cantidad_disponible', to_jsonb(0)),
                'requerido',     COALESCE(v_bom->'cantidad_requerida',  to_jsonb(0)),
                'id_almacen',    v_id_almacen
            );
        END IF;
    END IF;

    -- 7. Recalcular total
    SELECT COALESCE(SUM(cantidad * precio_unitario), 0)
      INTO v_nuevo_total
      FROM app_dat_extraccion_productos
     WHERE id_operacion = p_id_operacion;

    UPDATE app_dat_operacion_venta
       SET importe_total = v_nuevo_total
     WHERE id_operacion = p_id_operacion;

    -- 8. Registrar/acumular pago para el método seleccionado
    --    Si ya existe una fila para ese medio de pago en esta operación, sumar.
    --    Si no existe, insertar.
    IF EXISTS (
        SELECT 1 FROM app_dat_pago_venta
         WHERE id_operacion_venta = p_id_operacion
           AND id_medio_pago = v_id_medio_pago
    ) THEN
        UPDATE app_dat_pago_venta
           SET monto = monto + v_importe
         WHERE id_operacion_venta = p_id_operacion
           AND id_medio_pago = v_id_medio_pago;
    ELSE
        INSERT INTO app_dat_pago_venta (id_operacion_venta, id_medio_pago, monto, created_at)
        VALUES (p_id_operacion, v_id_medio_pago, v_importe, NOW());
    END IF;

    -- 9. Log
    INSERT INTO app_dat_log_modificacion_orden
        (id_operacion, uuid_usuario, accion, detalle, created_at)
    VALUES (
        p_id_operacion,
        p_uuid_usuario,
        'add_product',
        jsonb_build_object(
            'id_extraccion',    v_id_extraccion,
            'producto',         p_producto,
            'importe',          v_importe,
            'id_medio_pago',    v_id_medio_pago,
            'nuevo_total_orden',v_nuevo_total,
            'id_almacen_bom',   v_id_almacen
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
$function$;

GRANT EXECUTE ON FUNCTION public.fn_agregar_producto_orden_pendiente(bigint, jsonb, uuid) TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 6.3 fn_eliminar_producto_orden
-- Quitar un producto de una orden pendiente y restaurar lo que se habia movido.
--
-- Aqui va el CAMBIO 2: el chequeo pasa de es_elaborado a
-- (es_elaborado OR es_servicio), para dejar de crear stock fantasma en los
-- productos marcados solo como servicio.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_eliminar_producto_orden(
    p_id_extraccion bigint,
    p_uuid_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_extraccion       RECORD;
    v_nuevo_total      NUMERIC;
    v_es_elaborado     BOOLEAN;
    v_estado           INT;
    v_id_almacen       BIGINT;
    v_bom              JSONB;
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
    --    FASE 0 · CAMBIO 2: antes era solo es_elaborado. Un producto marcado
    --    es_servicio = true y es_elaborado = false no descuenta stock propio al
    --    venderse, pero esta funcion se lo DEVOLVIA al quitarlo de la orden,
    --    inflando el inventario. Ahora usa el mismo criterio que
    --    fn_registrar_venta y las otras rutas de edicion.
    SELECT (es_elaborado or es_servicio) INTO v_es_elaborado
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
        -- ══════════════════════════════════════════════════════════════════
        -- FASE 0 · Devolucion de materia prima acotada al almacen de la linea.
        --
        -- Nota: para un producto es_servicio sin receta,
        -- fn_obtener_ingredientes_recursivos no devuelve filas y el helper
        -- termina con lineas_afectadas = 0. Es el comportamiento correcto:
        -- no se movio MP al venderlo, no hay nada que devolver.
        -- ══════════════════════════════════════════════════════════════════
        v_id_almacen := public.fn_almacen_de_extraccion(p_id_extraccion);

        IF v_id_almacen IS NULL THEN
            RETURN jsonb_build_object(
                'status','error',
                'message','No se pudo determinar el almacen de la linea para devolver la materia prima',
                'error_code','ALMACEN_NOT_RESOLVED',
                'id_extraccion', p_id_extraccion
            );
        END IF;

        v_bom := public.fn_devolver_ingredientes_elaborado(
            p_id_producto_elaborado := v_extraccion.id_producto,
            p_cantidad              := v_extraccion.cantidad,
            p_id_almacen            := v_id_almacen,
            p_id_extraccion         := p_id_extraccion,
            p_origen_cambio         := 4
        );

        IF (v_bom->>'status') <> 'success' THEN
            RETURN jsonb_build_object(
                'status',     'error',
                'message',    COALESCE(v_bom->>'message', 'Error devolviendo materia prima'),
                'error_code', COALESCE(v_bom->>'error_code', 'BOM_ERROR'),
                'id_almacen', v_id_almacen
            );
        END IF;
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

    -- 7. Redistribuir pagos proporcionalmente (solo si quedan productos)
    IF v_nuevo_total > 0 THEN
        PERFORM _fn_distribuir_pagos_orden(v_extraccion.op_id, v_nuevo_total);
    END IF;

    -- 8. Log
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
            'nuevo_total_orden',v_nuevo_total,
            'id_almacen_bom',  v_id_almacen
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
$function$;

GRANT EXECUTE ON FUNCTION public.fn_eliminar_producto_orden(bigint, uuid) TO anon, authenticated, service_role;


-- ============================================================================
-- 6.4 VERIFICACION
-- ============================================================================

-- (a) Ninguna de las tres debe conservar el patron roto -> 0 filas
SELECT p.oid::regprocedure AS aun_roto
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_actualizar_cantidad_producto_orden',
                     'fn_agregar_producto_orden_pendiente',
                     'fn_eliminar_producto_orden')
   AND p.prosrc ILIKE '%v_inv_ingrediente%';

-- (b) Las tres deben delegar en los helpers -> 3 filas
SELECT p.oid::regprocedure AS delega_ok
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_actualizar_cantidad_producto_orden',
                     'fn_agregar_producto_orden_pendiente',
                     'fn_eliminar_producto_orden')
   AND (p.prosrc ILIKE '%fn_descontar_ingredientes_elaborado%'
     OR p.prosrc ILIKE '%fn_devolver_ingredientes_elaborado%');

-- (c) Las CINCO rutas deben compartir el criterio (es_elaborado OR es_servicio)
--     -> 5 filas, todas con criterio_unificado = true
SELECT p.proname,
       (p.prosrc ILIKE '%es_elaborado or es_servicio%') AS criterio_unificado
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_registrar_venta',
                     'fn_registrar_venta_mesa',
                     'fn_actualizar_cantidad_producto_orden',
                     'fn_agregar_producto_orden_pendiente',
                     'fn_eliminar_producto_orden')
 ORDER BY p.proname;

-- (d) Helpers del 01 y del 05 presentes -> 7 filas
SELECT p.oid::regprocedure AS helper
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_stock_producto_almacen_detalle',
                     'fn_stock_producto_almacen',
                     'fn_validar_ingredientes_elaborado',
                     'fn_descontar_ingredientes_elaborado',
                     'fn_almacen_de_extraccion',
                     'fn_almacen_de_operacion',
                     'fn_ubicacion_destino_devolucion',
                     'fn_devolver_ingredientes_elaborado')
 ORDER BY p.proname;


-- ----------------------------------------------------------------------------
-- 6.5 DIAGNOSTICO · stock fantasma ya creado por el bug del CAMBIO 2
-- Este archivo NO corrige el historico. Esta consulta lista el dano para
-- decidir el ajuste por la via normal de inventario.
--
-- Resultado esperado antes de aplicar el 06 (medido via API): 8 filas,
-- +35.3 unidades entre MANGUERA POR METROS, CARGA DE ACEITE, SOLDADURA
-- y ELECTRICIDAD. Despues de aplicar el 06 no deben aparecer filas NUEVAS.
-- ----------------------------------------------------------------------------
SELECT
    ip.id,
    ip.created_at,
    pr.id                 AS id_producto,
    pr.denominacion       AS producto,
    pr.es_elaborado,
    pr.es_servicio,
    la.id_almacen,
    ip.id_ubicacion,
    ip.cantidad_inicial,
    ip.cantidad_final,
    (ip.cantidad_final - ip.cantidad_inicial) AS stock_inflado,
    ip.id_extraccion
  FROM public.app_dat_inventario_productos ip
  JOIN public.app_dat_producto pr ON pr.id = ip.id_producto
  LEFT JOIN public.app_dat_layout_almacen la ON la.id = ip.id_ubicacion
 WHERE pr.es_servicio  = true
   AND pr.es_elaborado = false
   AND ip.origen_cambio = 3
   AND ip.cantidad_final > ip.cantidad_inicial
 ORDER BY ip.created_at DESC;

-- Resumen por producto
SELECT
    pr.id                                     AS id_producto,
    pr.denominacion                            AS producto,
    COUNT(*)                                   AS filas,
    SUM(ip.cantidad_final - ip.cantidad_inicial) AS total_inflado
  FROM public.app_dat_inventario_productos ip
  JOIN public.app_dat_producto pr ON pr.id = ip.id_producto
 WHERE pr.es_servicio  = true
   AND pr.es_elaborado = false
   AND ip.origen_cambio = 3
   AND ip.cantidad_final > ip.cantidad_inicial
 GROUP BY pr.id, pr.denominacion
 ORDER BY total_inflado DESC;
