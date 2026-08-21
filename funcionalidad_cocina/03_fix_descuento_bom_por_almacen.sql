-- ============================================================================
-- 03 · Fase 0 · Descuento de receta acotado al almacen del TPV
-- ============================================================================
-- Proyecto Supabase: vsieeihstajlrdvpuooh
-- Aplicar en: SQL Editor del dashboard. Idempotente (CREATE OR REPLACE).
-- REQUISITO: haber aplicado antes 01_helpers_bom_almacen.sql.
--
-- ALCANCE DE ESTE ARCHIVO
-- -----------------------
-- Reemplaza SOLO las dos funciones de venta cuya definicion real de produccion
-- fue exportada y verificada con la consulta 2.1:
--
--   fn_registrar_venta(bigint,uuid,jsonb,text,text,text,smallint,bigint)
--   fn_registrar_venta_mesa(bigint,uuid,jsonb,text,text,text,smallint,bigint,bigint)
--
-- El cuerpo se conserva IDENTICO al de produccion salvo el bloque de descuento
-- de ingredientes, que pasa a delegar en fn_descontar_ingredientes_elaborado.
--
-- Se conservan explicitamente (no estaban en las copias del repo):
--   - fn_registrar_venta: el bloque "5. Registrar pago de venta con monto 0".
--   - fn_registrar_venta_mesa: la validacion de mesa (MESA_NOT_FOUND /
--     MESA_WRONG_TIENDA).
--
-- NO se toca fn_registrar_venta_offline: solo delega en fn_registrar_venta con
-- idempotencia por client_uuid, asi que hereda el fix sin cambios.
--
-- QUEDA PENDIENTE (ver 04_exportar_rutas_restantes.sql): hay otras 3 funciones
-- que escriben inventario de ingredientes con el mismo patron roto y cuya
-- definicion de produccion NO coincide con el repo, por lo que no se pueden
-- parchear a ciegas.
--
-- QUE CAMBIA EN EL COMPORTAMIENTO
-- -------------------------------
-- Antes: el ingrediente se buscaba con la ultima fila GLOBAL de
--        app_dat_inventario_productos (sin filtrar almacen, una sola ubicacion).
-- Ahora: se busca en los layouts del almacen del TPV (v_id_almacen), sumando
--        todas sus ubicaciones, y se consume ubicacion por ubicacion.
--
-- Impacto medido en la base (consultas 2.4 y 2.5):
--   - Con stock en mas de un almacen: AZUCAR (417), LEVADURA (413), tete (1180),
--     hh (848), azucar refino (217), SALCHICHA 100G (1197).
--     Estos podian descontarse del almacen equivocado.
--   - Con stock repartido en 2 ubicaciones del mismo almacen 12:
--     azucar refino (217) -> 100.0 + 3.0 = 103.0 (antes solo se veian 100.0)
--     harina de trigo (216) -> 4.0 + 1.0 = 5.0  (antes solo se veian 4.0)
--     Estos daban "stock insuficiente" en falso.
--
-- El contrato con el cliente Flutter no cambia: los errores siguen saliendo con
-- 'status' = 'error' y 'error_code' = 'INSUFFICIENT_STOCK_INGREDIENT', con los
-- mismos campos id_ingrediente / cantidad_requerida / cantidad_disponible.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 3.1 fn_registrar_venta
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_registrar_venta(
    p_id_tpv bigint,
    p_uuid uuid,
    p_productos jsonb,
    p_codigo_promocion text DEFAULT NULL::text,
    p_denominacion text DEFAULT 'Venta en mostrador'::text,
    p_observaciones text DEFAULT NULL::text,
    p_estado_inicial smallint DEFAULT 1,
    p_id_cliente bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_id_operacion BIGINT;
    v_id_tipo_operacion BIGINT;
    v_id_tienda BIGINT;
    v_id_almacen BIGINT;
    v_producto JSONB;
    v_result JSONB;
    v_total_venta NUMERIC := 0;
    v_tpv_exists BOOLEAN;
    v_error_message TEXT;
    v_id_extraccion BIGINT;
    v_es_elaborado BOOLEAN;
    v_producto_presentacion_id BIGINT;
    v_id_ubicacion_resuelto BIGINT;
    v_descuento_bom JSONB;   -- resultado de fn_descontar_ingredientes_elaborado
  BEGIN
    -- Validar que el TPV existe y obtener la tienda y el almacen
    SELECT EXISTS(SELECT 1 FROM app_dat_tpv WHERE id = p_id_tpv),
           (SELECT id_tienda FROM app_dat_tpv WHERE id = p_id_tpv),
           (SELECT id_almacen FROM app_dat_tpv WHERE id = p_id_tpv)
    INTO v_tpv_exists, v_id_tienda, v_id_almacen;

    IF NOT v_tpv_exists THEN
      RETURN jsonb_build_object(
        'status', 'error',
        'message', 'El punto de venta especificado no existe'
      );
    END IF;

    -- Obtener ID del tipo de operación "Venta"
    SELECT id INTO v_id_tipo_operacion
    FROM app_nom_tipo_operacion
    WHERE denominacion ILIKE '%venta%' LIMIT 1;

    IF v_id_tipo_operacion IS NULL THEN
      RETURN jsonb_build_object(
        'status', 'error',
        'message', 'No se encontró tipo de operación para ventas'
      );
    END IF;

    -- Validar productos
    IF jsonb_array_length(p_productos) = 0 THEN
      RETURN jsonb_build_object(
        'status', 'error',
        'message', 'Debe incluir al menos un producto'
      );
    END IF;

    -- Validar cliente si se proporciona (opcional)
    IF p_id_cliente IS NOT NULL THEN
      IF NOT EXISTS (SELECT 1 FROM app_dat_clientes WHERE id = p_id_cliente) THEN
        RETURN jsonb_build_object(
          'status', 'error',
          'message', 'El cliente especificado no existe'
        );
      END IF;
    END IF;

    -- 1. Registrar operación principal
    INSERT INTO app_dat_operaciones (
      id_tipo_operacion,
      uuid,
      id_tienda,
      observaciones,
      created_at
    ) VALUES (
      v_id_tipo_operacion,
      p_uuid,
      v_id_tienda,
      p_observaciones,
      NOW()
    ) RETURNING id INTO v_id_operacion;

    -- 2. Registrar detalles específicos de venta (CON id_cliente)
    INSERT INTO app_dat_operacion_venta (
      id_operacion,
      id_tpv,
      denominacion,
      codigo_promocion,
      id_cliente,
      created_at
    ) VALUES (
      v_id_operacion,
      p_id_tpv,
      p_denominacion,
      p_codigo_promocion,
      p_id_cliente,
      NOW()
    );

    -- 3. Procesar cada producto vendido
    FOR v_producto IN SELECT * FROM jsonb_array_elements(p_productos)
    LOOP
      -- Validación de datos mínimos
      IF v_producto->>'id_producto' IS NULL OR
         v_producto->>'cantidad' IS NULL OR
         v_producto->>'precio_unitario' IS NULL THEN
        RAISE EXCEPTION 'Cada producto debe tener id_producto, cantidad y precio_unitario';
      END IF;

      -- Si id_presentacion es null o no existe, buscar la primera presentación del producto
      IF v_producto->>'id_presentacion' IS NULL OR NULLIF(v_producto->>'id_presentacion', '') IS NULL THEN
        SELECT id INTO v_producto_presentacion_id
        FROM app_dat_producto_presentacion
        WHERE id_producto = (v_producto->>'id_producto')::BIGINT
        ORDER BY id ASC
        LIMIT 1;

        IF v_producto_presentacion_id IS NULL THEN
          CONTINUE;
        END IF;
      ELSE
        -- Verificar que la presentación proporcionada existe
        IF NOT EXISTS (
          SELECT 1 FROM app_dat_producto_presentacion
          WHERE id = (v_producto->>'id_presentacion')::BIGINT
        ) THEN
          SELECT id INTO v_producto_presentacion_id
          FROM app_dat_producto_presentacion
          WHERE id_producto = (v_producto->>'id_producto')::BIGINT
          ORDER BY id ASC
          LIMIT 1;

          IF v_producto_presentacion_id IS NULL THEN
            CONTINUE;
          END IF;
        ELSE
          v_producto_presentacion_id := (v_producto->>'id_presentacion')::BIGINT;
        END IF;
      END IF;

      -- Resolver id_ubicacion: si no viene, buscar la zona del almacen del TPV con mayor stock para el producto
      v_id_ubicacion_resuelto := NULLIF(v_producto->>'id_ubicacion', '')::BIGINT;

      IF v_id_ubicacion_resuelto IS NULL THEN
        SELECT ip.id_ubicacion
        INTO v_id_ubicacion_resuelto
        FROM app_dat_inventario_productos ip
        INNER JOIN app_dat_layout_almacen la ON la.id = ip.id_ubicacion
        WHERE ip.id_producto = (v_producto->>'id_producto')::BIGINT
          AND la.id_almacen = v_id_almacen
          AND la.deleted_at IS NULL
          AND COALESCE(ip.id_variante, 0) = COALESCE(NULLIF(v_producto->>'id_variante', '')::BIGINT, 0)
        ORDER BY ip.cantidad_final DESC NULLS LAST, ip.id DESC
        LIMIT 1;

        IF v_id_ubicacion_resuelto IS NULL THEN
          RETURN jsonb_build_object(
            'status', 'error',
            'message', 'No se encontró ubicación con stock para el producto en el almacén del TPV',
            'error_code', 'NO_LOCATION_FOUND',
            'id_producto', (v_producto->>'id_producto')::BIGINT,
            'id_almacen', v_id_almacen
          );
        END IF;
      END IF;

      -- Registrar producto vendido Y CAPTURAR EL ID DE EXTRACCIÓN
      INSERT INTO app_dat_extraccion_productos (
        id_operacion,
        id_producto,
        id_variante,
        id_opcion_variante,
        id_ubicacion,
        id_presentacion,
        cantidad,
        precio_unitario,
        importe,
        importe_real,
        sku_producto,
        sku_ubicacion,
        created_at
      ) VALUES (
        v_id_operacion,
        (v_producto->>'id_producto')::BIGINT,
        NULLIF(v_producto->>'id_variante', '')::BIGINT,
        NULLIF(v_producto->>'id_opcion_variante', '')::BIGINT,
        v_id_ubicacion_resuelto,
        v_producto_presentacion_id,
        (v_producto->>'cantidad')::NUMERIC,
        (v_producto->>'precio_unitario')::NUMERIC,
        (v_producto->>'cantidad')::NUMERIC * (v_producto->>'precio_unitario')::NUMERIC,
        (v_producto->>'cantidad')::NUMERIC * COALESCE(NULLIF(v_producto->>'precio_real', '')::NUMERIC,
  (v_producto->>'precio_unitario')::NUMERIC),
        v_producto->>'sku_producto',
        v_producto->>'sku_ubicacion',
        NOW()
      ) RETURNING id INTO v_id_extraccion;

      -- Actualizar total de venta
      v_total_venta := v_total_venta + ((v_producto->>'cantidad')::NUMERIC * (v_producto->>'precio_unitario')::NUMERIC);

      -- Verificar si el producto es elaborado ANTES de actualizar inventario
      SELECT (es_elaborado or es_servicio) INTO v_es_elaborado
        FROM app_dat_producto
        WHERE id = (v_producto->>'id_producto')::BIGINT;

      -- Actualizar inventario usando el ID de extracción correcto
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
        id_extraccion,
        created_at
      )
      SELECT
        (v_producto->>'id_producto')::BIGINT,
        NULLIF(v_producto->>'id_variante', '')::BIGINT,
        NULLIF(v_producto->>'id_opcion_variante', '')::BIGINT,
        v_id_ubicacion_resuelto,
        v_producto_presentacion_id,
        COALESCE(ip.cantidad_final, 0),
        CASE
          WHEN v_es_elaborado = true THEN COALESCE(ip.cantidad_final, 0)
          ELSE COALESCE(ip.cantidad_final, 0) - (v_producto->>'cantidad')::NUMERIC
        END,
        v_producto->>'sku_producto',
        v_producto->>'sku_ubicacion',
        3,
        v_id_extraccion,
        NOW()
      FROM (
        SELECT cantidad_final
        FROM app_dat_inventario_productos
        WHERE id_producto = (v_producto->>'id_producto')::BIGINT
          AND COALESCE(id_variante, 0) = COALESCE(NULLIF(v_producto->>'id_variante', '')::BIGINT, 0)
          AND COALESCE(id_ubicacion, 0) = COALESCE(v_id_ubicacion_resuelto, 0)
        ORDER BY id desc, created_at DESC
        LIMIT 1
      ) ip;

      -- ══════════════════════════════════════════════════════════════════════
      -- FASE 0 · Descuento de materia prima acotado al almacen del TPV.
      --
      -- Antes este bloque leia la ultima fila GLOBAL de
      -- app_dat_inventario_productos por ingrediente: descontaba de cualquier
      -- almacen y solo de una ubicacion. Ahora delega en el helper, que acota a
      -- los layouts de v_id_almacen, suma todas sus ubicaciones y valida todos
      -- los ingredientes antes de tocar inventario.
      -- ══════════════════════════════════════════════════════════════════════
      IF v_es_elaborado = true THEN
        v_descuento_bom := public.fn_descontar_ingredientes_elaborado(
          p_id_producto_elaborado := (v_producto->>'id_producto')::BIGINT,
          p_cantidad              := (v_producto->>'cantidad')::NUMERIC,
          p_id_almacen            := v_id_almacen,
          p_id_extraccion         := v_id_extraccion,
          p_origen_cambio         := 4
        );

        IF (v_descuento_bom->>'status') <> 'success' THEN
          -- El helper ya devuelve error_code INSUFFICIENT_STOCK_INGREDIENT con
          -- los mismos campos que esperaba el cliente. Se agrega el contexto
          -- del producto vendido.
          RETURN v_descuento_bom || jsonb_build_object(
            'id_producto', (v_producto->>'id_producto')::BIGINT,
            'id_almacen',  v_id_almacen
          );
        END IF;
      END IF;
    END LOOP;

    -- 4. Actualizar monto total en la venta
    UPDATE app_dat_operacion_venta
    SET importe_total = v_total_venta
    WHERE id_operacion = v_id_operacion;

    -- 5. Registrar pago de venta con monto 0 cuando el total sea 0
    -- Esto garantiza que las ventas gratuitas/promocionales tengan su registro
    -- de pago sin duplicar pagos en ventas normales (que las registra la app).
    IF COALESCE(v_total_venta, 0) = 0 THEN
      INSERT INTO app_dat_pago_venta (
        id_operacion_venta,
        id_medio_pago,
        monto,
        creado_por,
        tipo_pago,
        importe_sin_descuento,
        referencia_pago,
        fecha_pago,
        created_at
      ) VALUES (
        v_id_operacion,
        1,                 -- Efectivo por defecto
        0,
        p_uuid,
        1,                 -- Tipo efectivo
        0,
        'Venta mostrador - monto 0',
        NOW(),
        NOW()
      );
    END IF;

    -- 6. Registrar estado inicial
    INSERT INTO app_dat_estado_operacion (
      id_operacion,
      estado,
      uuid,
      created_at
    ) VALUES (
      v_id_operacion,
      p_estado_inicial,
      p_uuid,
      NOW()
    );

    -- Construir respuesta
    v_result := jsonb_build_object(
      'status', 'success',
      'id_operacion', v_id_operacion,
      'total_venta', v_total_venta,
      'total_productos', jsonb_array_length(p_productos),
      'id_cliente', p_id_cliente,
      'mensaje', 'Venta registrada correctamente'
    );

    RETURN v_result;

  EXCEPTION
    WHEN OTHERS THEN
      v_result := jsonb_build_object(
        'status', 'error',
        'message', 'Error al registrar venta: ' || SQLERRM,
        'sqlstate', SQLSTATE
      );
      RETURN v_result;
  END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_registrar_venta(bigint, uuid, jsonb, text, text, text, smallint, bigint) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_registrar_venta(bigint, uuid, jsonb, text, text, text, smallint, bigint) TO anon;
GRANT EXECUTE ON FUNCTION public.fn_registrar_venta(bigint, uuid, jsonb, text, text, text, smallint, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_registrar_venta(bigint, uuid, jsonb, text, text, text, smallint, bigint) TO service_role;


-- ----------------------------------------------------------------------------
-- 3.2 fn_registrar_venta_mesa
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_registrar_venta_mesa(
    p_id_tpv bigint,
    p_uuid uuid,
    p_productos jsonb,
    p_codigo_promocion text DEFAULT NULL::text,
    p_denominacion text DEFAULT 'Venta en mostrador'::text,
    p_observaciones text DEFAULT NULL::text,
    p_estado_inicial smallint DEFAULT 1,
    p_id_cliente bigint DEFAULT NULL::bigint,
    p_id_mesa bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_id_operacion BIGINT;
    v_id_tipo_operacion BIGINT;
    v_id_tienda BIGINT;
    v_id_almacen BIGINT;
    v_producto JSONB;
    v_result JSONB;
    v_total_venta NUMERIC := 0;
    v_tpv_exists BOOLEAN;
    v_error_message TEXT;
    v_id_extraccion BIGINT;
    v_es_elaborado BOOLEAN;
    v_producto_presentacion_id BIGINT;
    v_id_ubicacion_resuelto BIGINT;
    v_mesa_tienda BIGINT;
    v_descuento_bom JSONB;   -- resultado de fn_descontar_ingredientes_elaborado
  BEGIN
    -- Validar que el TPV existe y obtener la tienda y el almacen
    SELECT EXISTS(SELECT 1 FROM app_dat_tpv WHERE id = p_id_tpv),
           (SELECT id_tienda FROM app_dat_tpv WHERE id = p_id_tpv),
           (SELECT id_almacen FROM app_dat_tpv WHERE id = p_id_tpv)
    INTO v_tpv_exists, v_id_tienda, v_id_almacen;

    IF NOT v_tpv_exists THEN
      RETURN jsonb_build_object(
        'status', 'error',
        'message', 'El punto de venta especificado no existe'
      );
    END IF;

    -- Obtener ID del tipo de operación "Venta"
    SELECT id INTO v_id_tipo_operacion
    FROM app_nom_tipo_operacion
    WHERE denominacion ILIKE '%venta%' LIMIT 1;

    IF v_id_tipo_operacion IS NULL THEN
      RETURN jsonb_build_object(
        'status', 'error',
        'message', 'No se encontró tipo de operación para ventas'
      );
    END IF;

    -- Validar productos
    IF jsonb_array_length(p_productos) = 0 THEN
      RETURN jsonb_build_object(
        'status', 'error',
        'message', 'Debe incluir al menos un producto'
      );
    END IF;

    -- Validar cliente si se proporciona (opcional)
    IF p_id_cliente IS NOT NULL THEN
      IF NOT EXISTS (SELECT 1 FROM app_dat_clientes WHERE id = p_id_cliente) THEN
        RETURN jsonb_build_object(
          'status', 'error',
          'message', 'El cliente especificado no existe'
        );
      END IF;
    END IF;

    -- Validar mesa si se proporciona (opcional, sólo modo restaurante)
    IF p_id_mesa IS NOT NULL THEN
      SELECT id_tienda INTO v_mesa_tienda
        FROM app_dat_mesas
       WHERE id = p_id_mesa AND activa = true;

      IF v_mesa_tienda IS NULL THEN
        RETURN jsonb_build_object(
          'status',     'error',
          'message',    'La mesa especificada no existe o está inactiva',
          'error_code', 'MESA_NOT_FOUND',
          'id_mesa',    p_id_mesa
        );
      END IF;

      IF v_mesa_tienda <> v_id_tienda THEN
        RETURN jsonb_build_object(
          'status',     'error',
          'message',    'La mesa no pertenece a la tienda del TPV',
          'error_code', 'MESA_WRONG_TIENDA',
          'id_mesa',    p_id_mesa
        );
      END IF;
    END IF;

    -- 1. Registrar operación principal
    INSERT INTO app_dat_operaciones (
      id_tipo_operacion,
      uuid,
      id_tienda,
      observaciones,
      created_at
    ) VALUES (
      v_id_tipo_operacion,
      p_uuid,
      v_id_tienda,
      p_observaciones,
      NOW()
    ) RETURNING id INTO v_id_operacion;

    -- 2. Registrar detalles específicos de venta (CON id_cliente y id_mesa)
    INSERT INTO app_dat_operacion_venta (
      id_operacion,
      id_tpv,
      denominacion,
      codigo_promocion,
      id_cliente,
      id_mesa,
      created_at
    ) VALUES (
      v_id_operacion,
      p_id_tpv,
      p_denominacion,
      p_codigo_promocion,
      p_id_cliente,
      p_id_mesa,
      NOW()
    );

    -- 3. Procesar cada producto vendido
    FOR v_producto IN SELECT * FROM jsonb_array_elements(p_productos)
    LOOP
      -- Validación de datos mínimos
      IF v_producto->>'id_producto' IS NULL OR
         v_producto->>'cantidad' IS NULL OR
         v_producto->>'precio_unitario' IS NULL THEN
        RAISE EXCEPTION 'Cada producto debe tener id_producto, cantidad y precio_unitario';
      END IF;

      -- Si id_presentacion es null o no existe, buscar la primera presentación del producto
      IF v_producto->>'id_presentacion' IS NULL OR NULLIF(v_producto->>'id_presentacion', '') IS NULL THEN
        SELECT id INTO v_producto_presentacion_id
        FROM app_dat_producto_presentacion
        WHERE id_producto = (v_producto->>'id_producto')::BIGINT
        ORDER BY id ASC
        LIMIT 1;

        IF v_producto_presentacion_id IS NULL THEN
          CONTINUE;
        END IF;
      ELSE
        -- Verificar que la presentación proporcionada existe
        IF NOT EXISTS (
          SELECT 1 FROM app_dat_producto_presentacion
          WHERE id = (v_producto->>'id_presentacion')::BIGINT
        ) THEN
          SELECT id INTO v_producto_presentacion_id
          FROM app_dat_producto_presentacion
          WHERE id_producto = (v_producto->>'id_producto')::BIGINT
          ORDER BY id ASC
          LIMIT 1;

          IF v_producto_presentacion_id IS NULL THEN
            CONTINUE;
          END IF;
        ELSE
          v_producto_presentacion_id := (v_producto->>'id_presentacion')::BIGINT;
        END IF;
      END IF;

      -- Resolver id_ubicacion: si no viene, buscar la zona del almacen del TPV con mayor stock para el producto
      v_id_ubicacion_resuelto := NULLIF(v_producto->>'id_ubicacion', '')::BIGINT;

      IF v_id_ubicacion_resuelto IS NULL THEN
        SELECT ip.id_ubicacion
        INTO v_id_ubicacion_resuelto
        FROM app_dat_inventario_productos ip
        INNER JOIN app_dat_layout_almacen la ON la.id = ip.id_ubicacion
        WHERE ip.id_producto = (v_producto->>'id_producto')::BIGINT
          AND la.id_almacen = v_id_almacen
          AND la.deleted_at IS NULL
          AND COALESCE(ip.id_variante, 0) = COALESCE(NULLIF(v_producto->>'id_variante', '')::BIGINT, 0)
        ORDER BY ip.cantidad_final DESC NULLS LAST, ip.id DESC
        LIMIT 1;

        IF v_id_ubicacion_resuelto IS NULL THEN
          RETURN jsonb_build_object(
            'status', 'error',
            'message', 'No se encontró ubicación con stock para el producto en el almacén del TPV',
            'error_code', 'NO_LOCATION_FOUND',
            'id_producto', (v_producto->>'id_producto')::BIGINT,
            'id_almacen', v_id_almacen
          );
        END IF;
      END IF;

      -- Registrar producto vendido Y CAPTURAR EL ID DE EXTRACCIÓN
      INSERT INTO app_dat_extraccion_productos (
        id_operacion,
        id_producto,
        id_variante,
        id_opcion_variante,
        id_ubicacion,
        id_presentacion,
        cantidad,
        precio_unitario,
        importe,
        importe_real,
        sku_producto,
        sku_ubicacion,
        created_at
      ) VALUES (
        v_id_operacion,
        (v_producto->>'id_producto')::BIGINT,
        NULLIF(v_producto->>'id_variante', '')::BIGINT,
        NULLIF(v_producto->>'id_opcion_variante', '')::BIGINT,
        v_id_ubicacion_resuelto,
        v_producto_presentacion_id,
        (v_producto->>'cantidad')::NUMERIC,
        (v_producto->>'precio_unitario')::NUMERIC,
        (v_producto->>'cantidad')::NUMERIC * (v_producto->>'precio_unitario')::NUMERIC,
        (v_producto->>'cantidad')::NUMERIC * COALESCE(NULLIF(v_producto->>'precio_real', '')::NUMERIC,
  (v_producto->>'precio_unitario')::NUMERIC),
        v_producto->>'sku_producto',
        v_producto->>'sku_ubicacion',
        NOW()
      ) RETURNING id INTO v_id_extraccion;

      -- Actualizar total de venta
      v_total_venta := v_total_venta + ((v_producto->>'cantidad')::NUMERIC * (v_producto->>'precio_unitario')::NUMERIC);

      -- Verificar si el producto es elaborado ANTES de actualizar inventario
      SELECT (es_elaborado or es_servicio) INTO v_es_elaborado
        FROM app_dat_producto
        WHERE id = (v_producto->>'id_producto')::BIGINT;

      -- Actualizar inventario usando el ID de extracción correcto
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
        id_extraccion,
        created_at
      )
      SELECT
        (v_producto->>'id_producto')::BIGINT,
        NULLIF(v_producto->>'id_variante', '')::BIGINT,
        NULLIF(v_producto->>'id_opcion_variante', '')::BIGINT,
        v_id_ubicacion_resuelto,
        v_producto_presentacion_id,
        COALESCE(ip.cantidad_final, 0),
        CASE
          WHEN v_es_elaborado = true THEN COALESCE(ip.cantidad_final, 0)
          ELSE COALESCE(ip.cantidad_final, 0) - (v_producto->>'cantidad')::NUMERIC
        END,
        v_producto->>'sku_producto',
        v_producto->>'sku_ubicacion',
        3,
        v_id_extraccion,
        NOW()
      FROM (
        SELECT cantidad_final
        FROM app_dat_inventario_productos
        WHERE id_producto = (v_producto->>'id_producto')::BIGINT
          AND COALESCE(id_variante, 0) = COALESCE(NULLIF(v_producto->>'id_variante', '')::BIGINT, 0)
          AND COALESCE(id_ubicacion, 0) = COALESCE(v_id_ubicacion_resuelto, 0)
        ORDER BY id desc, created_at DESC
        LIMIT 1
      ) ip;

      -- ══════════════════════════════════════════════════════════════════════
      -- FASE 0 · Descuento de materia prima acotado al almacen del TPV.
      --
      -- En Fase 2 esta misma llamada pasara a recibir el almacen de la COCINA
      -- destino en lugar del almacen del TPV, cuando el plato sea al_pedido.
      -- ══════════════════════════════════════════════════════════════════════
      IF v_es_elaborado = true THEN
        v_descuento_bom := public.fn_descontar_ingredientes_elaborado(
          p_id_producto_elaborado := (v_producto->>'id_producto')::BIGINT,
          p_cantidad              := (v_producto->>'cantidad')::NUMERIC,
          p_id_almacen            := v_id_almacen,
          p_id_extraccion         := v_id_extraccion,
          p_origen_cambio         := 4
        );

        IF (v_descuento_bom->>'status') <> 'success' THEN
          RETURN v_descuento_bom || jsonb_build_object(
            'id_producto', (v_producto->>'id_producto')::BIGINT,
            'id_almacen',  v_id_almacen
          );
        END IF;
      END IF;
    END LOOP;

    -- 4. Actualizar monto total en la venta
    UPDATE app_dat_operacion_venta
    SET importe_total = v_total_venta
    WHERE id_operacion = v_id_operacion;

    -- 5. Registrar estado inicial
    INSERT INTO app_dat_estado_operacion (
      id_operacion,
      estado,
      uuid,
      created_at
    ) VALUES (
      v_id_operacion,
      p_estado_inicial,
      p_uuid,
      NOW()
    );

    -- Construir respuesta
    v_result := jsonb_build_object(
      'status', 'success',
      'id_operacion', v_id_operacion,
      'total_venta', v_total_venta,
      'total_productos', jsonb_array_length(p_productos),
      'id_cliente', p_id_cliente,
      'id_mesa', p_id_mesa,
      'mensaje', 'Venta registrada correctamente'
    );

    RETURN v_result;

  EXCEPTION
    WHEN OTHERS THEN
      v_result := jsonb_build_object(
        'status', 'error',
        'message', 'Error al registrar venta: ' || SQLERRM,
        'sqlstate', SQLSTATE
      );
      RETURN v_result;
  END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_registrar_venta_mesa(bigint, uuid, jsonb, text, text, text, smallint, bigint, bigint) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_registrar_venta_mesa(bigint, uuid, jsonb, text, text, text, smallint, bigint, bigint) TO anon;
GRANT EXECUTE ON FUNCTION public.fn_registrar_venta_mesa(bigint, uuid, jsonb, text, text, text, smallint, bigint, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_registrar_venta_mesa(bigint, uuid, jsonb, text, text, text, smallint, bigint, bigint) TO service_role;


-- ============================================================================
-- VERIFICACION
-- ============================================================================
-- 1. Que las funciones ya no contengan el patron roto (deben devolver 0 filas):
--
--    SELECT p.oid::regprocedure
--      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--     WHERE n.nspname = 'public'
--       AND p.proname IN ('fn_registrar_venta','fn_registrar_venta_mesa')
--       AND p.prosrc ILIKE '%v_inventario_ingrediente%';
--
-- 2. Que ahora deleguen en el helper (deben devolver 2 filas):
--
--    SELECT p.oid::regprocedure
--      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--     WHERE n.nspname = 'public'
--       AND p.proname IN ('fn_registrar_venta','fn_registrar_venta_mesa')
--       AND p.prosrc ILIKE '%fn_descontar_ingredientes_elaborado%';
--
-- 3. Prueba funcional del caso que antes fallaba en falso.
--    harina de trigo (216) tiene 4.0 + 1.0 = 5.0 en el almacen 12.
--    El elaborado 219 consume 40 g de 216 por unidad.
--
--    SELECT public.fn_validar_ingredientes_elaborado(219, 1, 12);
--    -- debe reportar cantidad_disponible = 5.0 para el 216, no 4.0
--
-- 4. Venta real de un elaborado desde un TPV del almacen 12 y comprobar que
--    las filas nuevas de app_dat_inventario_productos con origen_cambio = 4
--    caen en ubicaciones de ESE almacen:
--
--    SELECT ip.id, ip.id_producto, ip.id_ubicacion, la.id_almacen,
--           ip.cantidad_inicial, ip.cantidad_final, ip.created_at
--      FROM app_dat_inventario_productos ip
--      JOIN app_dat_layout_almacen la ON la.id = ip.id_ubicacion
--     WHERE ip.origen_cambio = 4
--     ORDER BY ip.id DESC
--     LIMIT 20;
-- ============================================================================
