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
    v_descuento_bom JSONB;   -- resultado de fn_descontar_venta_enrutada
    -- FASE 1 · enrutamiento a cocina
    v_ruta JSONB;              -- resultado de fn_resolver_origen_venta
    v_id_almacen_origen BIGINT;-- almacen del que realmente sale la linea
    v_origen_venta TEXT;       -- barra | cocina_al_pedido | cocina_por_tanda | servicio
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

      -- ══════════════════════════════════════════════════════════════════════
      -- FASE 1 · Resolver DE DONDE sale esta linea antes de tocar nada.
      --
      -- Sin esto, un plato de cocina moria aqui con NO_LOCATION_FOUND: no tiene
      -- inventario en el almacen de la barra, asi que la busqueda de ubicacion
      -- no encontraba nada y la venta se cortaba ANTES del descuento.
      --
      -- fn_resolver_origen_venta tambien valida el enrutamiento (COCINA_NO_LIGADA,
      -- COCINA_INACTIVA), asi que un TPV no puede vender platos de una cocina a
      -- la que no esta ligado.
      -- ══════════════════════════════════════════════════════════════════════
      v_ruta := public.fn_resolver_origen_venta(
        (v_producto->>'id_producto')::BIGINT,
        p_id_tpv
      );

      IF (v_ruta->>'status') <> 'success' THEN
        RETURN v_ruta;
      END IF;

      v_origen_venta      := v_ruta->>'origen';
      v_id_almacen_origen := (v_ruta->>'id_almacen')::BIGINT;

      -- Resolver id_ubicacion dentro del almacen de ORIGEN (barra o cocina)
      v_id_ubicacion_resuelto := NULLIF(v_producto->>'id_ubicacion', '')::BIGINT;

      IF v_id_ubicacion_resuelto IS NULL THEN
        SELECT ip.id_ubicacion
        INTO v_id_ubicacion_resuelto
        FROM app_dat_inventario_productos ip
        INNER JOIN app_dat_layout_almacen la ON la.id = ip.id_ubicacion
        WHERE ip.id_producto = (v_producto->>'id_producto')::BIGINT
          AND la.id_almacen = v_id_almacen_origen
          AND la.deleted_at IS NULL
          AND COALESCE(ip.id_variante, 0) = COALESCE(NULLIF(v_producto->>'id_variante', '')::BIGINT, 0)
        ORDER BY ip.cantidad_final DESC NULLS LAST, ip.id DESC
        LIMIT 1;

        -- Un plato al_pedido no tiene fila de inventario propia: se fabrica a
        -- partir de ingredientes. La linea de extraccion necesita apuntar a
        -- ALGUNA ubicacion, asi que se usa un layout de la cocina. Solo se
        -- aplica a origenes de cocina: en barra se conserva el comportamiento
        -- previo (y su error) tal cual.
        IF v_id_ubicacion_resuelto IS NULL AND v_origen_venta <> 'barra' THEN
          SELECT la.id
          INTO v_id_ubicacion_resuelto
          FROM app_dat_layout_almacen la
          WHERE la.id_almacen = v_id_almacen_origen
            AND la.deleted_at IS NULL
          ORDER BY la.id
          LIMIT 1;
        END IF;

        IF v_id_ubicacion_resuelto IS NULL THEN
          RETURN jsonb_build_object(
            'status', 'error',
            'message', CASE
                WHEN v_origen_venta = 'barra'
                  THEN 'No se encontró ubicación con stock para el producto en el almacén del TPV'
                ELSE 'La cocina "' || COALESCE(v_ruta->>'cocina', '?')
                     || '" no tiene ubicaciones donde registrar la salida'
              END,
            'error_code', 'NO_LOCATION_FOUND',
            'id_producto', (v_producto->>'id_producto')::BIGINT,
            'id_almacen', v_id_almacen_origen,
            'origen',     v_origen_venta,
            'id_cocina',  v_ruta->'id_cocina',
            'cocina',     v_ruta->'cocina'
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
          -- Elaborado/servicio: la venta no decrementa el SKU (lo hace el BOM).
          -- Origen cocina: tampoco, lo descuenta fn_descontar_venta_enrutada
          -- del almacen de la cocina. Sin esta segunda condicion, un producto
          -- por_tanda NO elaborado se descontaria dos veces.
          WHEN v_es_elaborado = true OR v_origen_venta <> 'barra'
            THEN COALESCE(ip.cantidad_final, 0)
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
      -- FASE 1 · Descuento enrutado.
      --
      -- Una sola llamada cubre las cuatro rutas:
      --   barra normal      ya descontado arriba -> aqui solo valida
      --   barra elaborado   descuenta receta del almacen del TPV (como Fase 0)
      --   cocina al_pedido  descuenta receta del almacen de la COCINA
      --   cocina por_tanda  descuenta la PORCION hecha del almacen de la cocina
      --                     (sin tocar la receta: la MP se consumio al producir)
      --
      -- p_ya_descontado_sku evita el doble descuento: es true solo cuando el
      -- INSERT de arriba ya decremento el SKU, o sea barra no elaborada.
      -- ══════════════════════════════════════════════════════════════════════
      v_descuento_bom := public.fn_descontar_venta_enrutada(
        p_id_producto       := (v_producto->>'id_producto')::BIGINT,
        p_cantidad          := (v_producto->>'cantidad')::NUMERIC,
        p_id_tpv            := p_id_tpv,
        p_id_extraccion     := v_id_extraccion,
        p_origen_cambio     := 4,
        p_ya_descontado_sku := (v_origen_venta = 'barra' AND v_es_elaborado = false)
      );

      IF (v_descuento_bom->>'status') <> 'success' THEN
        -- El helper ya devuelve error_code + los campos que espera el cliente
        -- (INSUFFICIENT_STOCK_INGREDIENT, INSUFFICIENT_PORTIONS, COCINA_*).
        RETURN v_descuento_bom || jsonb_build_object(
          'id_producto', (v_producto->>'id_producto')::BIGINT,
          'id_almacen',  v_id_almacen_origen
        );
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
    v_descuento_bom JSONB;   -- resultado de fn_descontar_venta_enrutada
    -- FASE 1 · enrutamiento a cocina
    v_ruta JSONB;              -- resultado de fn_resolver_origen_venta
    v_id_almacen_origen BIGINT;-- almacen del que realmente sale la linea
    v_origen_venta TEXT;       -- barra | cocina_al_pedido | cocina_por_tanda | servicio
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

      -- ══════════════════════════════════════════════════════════════════════
      -- FASE 1 · Resolver DE DONDE sale esta linea antes de tocar nada.
      --
      -- Sin esto, un plato de cocina moria aqui con NO_LOCATION_FOUND: no tiene
      -- inventario en el almacen de la barra, asi que la busqueda de ubicacion
      -- no encontraba nada y la venta se cortaba ANTES del descuento.
      --
      -- fn_resolver_origen_venta tambien valida el enrutamiento (COCINA_NO_LIGADA,
      -- COCINA_INACTIVA), asi que un TPV no puede vender platos de una cocina a
      -- la que no esta ligado.
      -- ══════════════════════════════════════════════════════════════════════
      v_ruta := public.fn_resolver_origen_venta(
        (v_producto->>'id_producto')::BIGINT,
        p_id_tpv
      );

      IF (v_ruta->>'status') <> 'success' THEN
        RETURN v_ruta;
      END IF;

      v_origen_venta      := v_ruta->>'origen';
      v_id_almacen_origen := (v_ruta->>'id_almacen')::BIGINT;

      -- Resolver id_ubicacion dentro del almacen de ORIGEN (barra o cocina)
      v_id_ubicacion_resuelto := NULLIF(v_producto->>'id_ubicacion', '')::BIGINT;

      IF v_id_ubicacion_resuelto IS NULL THEN
        SELECT ip.id_ubicacion
        INTO v_id_ubicacion_resuelto
        FROM app_dat_inventario_productos ip
        INNER JOIN app_dat_layout_almacen la ON la.id = ip.id_ubicacion
        WHERE ip.id_producto = (v_producto->>'id_producto')::BIGINT
          AND la.id_almacen = v_id_almacen_origen
          AND la.deleted_at IS NULL
          AND COALESCE(ip.id_variante, 0) = COALESCE(NULLIF(v_producto->>'id_variante', '')::BIGINT, 0)
        ORDER BY ip.cantidad_final DESC NULLS LAST, ip.id DESC
        LIMIT 1;

        -- Un plato al_pedido no tiene fila de inventario propia: se fabrica a
        -- partir de ingredientes. La linea de extraccion necesita apuntar a
        -- ALGUNA ubicacion, asi que se usa un layout de la cocina. Solo se
        -- aplica a origenes de cocina: en barra se conserva el comportamiento
        -- previo (y su error) tal cual.
        IF v_id_ubicacion_resuelto IS NULL AND v_origen_venta <> 'barra' THEN
          SELECT la.id
          INTO v_id_ubicacion_resuelto
          FROM app_dat_layout_almacen la
          WHERE la.id_almacen = v_id_almacen_origen
            AND la.deleted_at IS NULL
          ORDER BY la.id
          LIMIT 1;
        END IF;

        IF v_id_ubicacion_resuelto IS NULL THEN
          RETURN jsonb_build_object(
            'status', 'error',
            'message', CASE
                WHEN v_origen_venta = 'barra'
                  THEN 'No se encontró ubicación con stock para el producto en el almacén del TPV'
                ELSE 'La cocina "' || COALESCE(v_ruta->>'cocina', '?')
                     || '" no tiene ubicaciones donde registrar la salida'
              END,
            'error_code', 'NO_LOCATION_FOUND',
            'id_producto', (v_producto->>'id_producto')::BIGINT,
            'id_almacen', v_id_almacen_origen,
            'origen',     v_origen_venta,
            'id_cocina',  v_ruta->'id_cocina',
            'cocina',     v_ruta->'cocina'
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
          -- Elaborado/servicio: la venta no decrementa el SKU (lo hace el BOM).
          -- Origen cocina: tampoco, lo descuenta fn_descontar_venta_enrutada
          -- del almacen de la cocina. Sin esta segunda condicion, un producto
          -- por_tanda NO elaborado se descontaria dos veces.
          WHEN v_es_elaborado = true OR v_origen_venta <> 'barra'
            THEN COALESCE(ip.cantidad_final, 0)
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
      -- FASE 1 · Descuento enrutado.
      --
      -- Una sola llamada cubre las cuatro rutas:
      --   barra normal      ya descontado arriba -> aqui solo valida
      --   barra elaborado   descuenta receta del almacen del TPV (como Fase 0)
      --   cocina al_pedido  descuenta receta del almacen de la COCINA
      --   cocina por_tanda  descuenta la PORCION hecha del almacen de la cocina
      --                     (sin tocar la receta: la MP se consumio al producir)
      --
      -- p_ya_descontado_sku evita el doble descuento: es true solo cuando el
      -- INSERT de arriba ya decremento el SKU, o sea barra no elaborada.
      -- ══════════════════════════════════════════════════════════════════════
      v_descuento_bom := public.fn_descontar_venta_enrutada(
        p_id_producto       := (v_producto->>'id_producto')::BIGINT,
        p_cantidad          := (v_producto->>'cantidad')::NUMERIC,
        p_id_tpv            := p_id_tpv,
        p_id_extraccion     := v_id_extraccion,
        p_origen_cambio     := 4,
        p_ya_descontado_sku := (v_origen_venta = 'barra' AND v_es_elaborado = false)
      );

      IF (v_descuento_bom->>'status') <> 'success' THEN
        -- El helper ya devuelve error_code + los campos que espera el cliente
        -- (INSUFFICIENT_STOCK_INGREDIENT, INSUFFICIENT_PORTIONS, COCINA_*).
        RETURN v_descuento_bom || jsonb_build_object(
          'id_producto', (v_producto->>'id_producto')::BIGINT,
          'id_almacen',  v_id_almacen_origen
        );
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
