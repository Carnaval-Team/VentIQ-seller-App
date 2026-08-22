-- ============================================================================
-- 17 · Fase 2 · Cobrar sin re-descontar lo ya movido al pedir
-- ============================================================================
-- Proyecto Supabase: vsieeihstajlrdvpuooh
--
-- QUE CIERRA ESTE ARCHIVO
-- -----------------------
-- El 14 hizo que PEDIR mueva el inventario. Pero fn_registrar_venta_mesa sigue
-- descontando al COBRAR, asi que ahora mismo un plato pedido desde una cuenta
-- abierta se descontaria DOS VECES:
--
--   1. al pedirlo   -> fn_pedir_item_cuenta llama fn_descontar_venta_enrutada
--   2. al cobrarlo  -> fn_registrar_venta_mesa vuelve a descontar
--
-- Cada plato pagaria su materia prima dos veces. Este archivo lo corta: si la
-- linea ya movio stock, cobrar es un acto puramente contable.
--
-- Es el requisito 2.3 del plan: "fn_cerrar_cuenta_mesa / fn_registrar_venta_mesa:
-- NO volver a descontar lo ya movido al pedir".
--
-- COMO SE IDENTIFICA UNA LINEA YA MOVIDA
-- --------------------------------------
-- La app llama fn_registrar_venta_mesa con un jsonb de productos, no con ids de
-- lineas de cuenta. Asi que hay que emparejar cada producto del cobro con su
-- linea en la cuenta abierta. Se hace por:
--
--   id_cuenta + id_producto + id_variante + id_presentacion + stock_movido = true
--
-- Y al emparejar se pone stock_movido = false en esa linea, para que una segunda
-- entrada del MISMO producto en la misma venta no reuse la misma linea. Es un
-- consumo de marcas: N entradas del cobro consumen N lineas ya movidas, y si el
-- cobro trae mas cantidad que lo pedido, el resto se descuenta normalmente.
--
-- COMPATIBILIDAD CON LO EXISTENTE (importante)
-- --------------------------------------------
-- Las lineas creadas antes de la Fase 2, o por la ruta vieja
-- fn_agregar_item_cuenta_mesa, tienen stock_movido = false. Para esas el cobro
-- descuenta igual que siempre: cero cambio de comportamiento.
--
-- Y una venta de mostrador (p_id_mesa NULL) no busca cuenta abierta en absoluto:
-- v_id_cuenta_abierta queda NULL y todo el bloque nuevo se salta.
--
-- POR QUE SOLO fn_registrar_venta_mesa
-- ------------------------------------
-- fn_registrar_venta (mostrador) no tiene cuenta abierta: ahi pedir y cobrar son
-- el mismo acto. No hay nada que deduplicar, y tocarla seria anadir riesgo sin
-- beneficio.
--
-- GENERADO POR SCRIPT
-- -------------------
-- El cuerpo sale de _11_funciones_generadas.sql (el 11 ya aplicado y verificado
-- en produccion: enruta=true, helper_viejo=false), con 5 cambios aplicados por
-- _generar_17.py. El script ASSERTA una coincidencia por anclaje, comprueba el
-- balance IF/END IF y que sobrevivan los bloques criticos (validaciones de mesa,
-- extraccion, estado de operacion).
--
-- Regenerar con:  python funcionalidad_cocina/_generar_17.py
--
-- ORDEN DE APLICACION
-- -------------------
--   1. Correr 17.1 (confirmar que el 11 sigue en pie).
--   2. Aplicar 17.2.
--   3. Correr la VERIFICACION y la prueba funcional del final.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 17.1 Confirmar el punto de partida (NO MODIFICA NADA)
--
-- Esperado: enruta = true, helper_viejo = false, ya_tiene_el_17 = false.
-- Si ya_tiene_el_17 es true, este archivo ya se aplico.
-- ----------------------------------------------------------------------------
SELECT
    p.oid::regprocedure AS firma,
    length(p.prosrc)    AS largo_cuerpo,
    (p.prosrc ILIKE '%fn_descontar_venta_enrutada%')         AS enruta,
    (p.prosrc ILIKE '%fn_descontar_ingredientes_elaborado%') AS helper_viejo,
    (p.prosrc ILIKE '%v_lineas_ya_movidas%')                 AS ya_tiene_el_17
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname = 'fn_registrar_venta_mesa';


-- ----------------------------------------------------------------------------
-- 17.2 fn_registrar_venta_mesa con cobro deduplicado
--
-- Los cinco cambios respecto al 11:
--   A  DECLARE: v_id_cuenta_abierta, v_id_item_cuenta, v_ya_movido y contadores
--   B  antes del loop, localizar la cuenta abierta de la mesa (estado 1)
--   C  el descuento se salta si la linea ya movio stock al pedirse
--   D  el INSERT de inventario tampoco decrementa en ese caso
--   E  la respuesta expone lineas_ya_movidas_al_pedir / lineas_descontadas_al_cobrar
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
    v_descuento_bom JSONB;   -- resultado de fn_descontar_venta_enrutada
    -- FASE 1 · enrutamiento a cocina
    v_ruta JSONB;              -- resultado de fn_resolver_origen_venta
    v_id_almacen_origen BIGINT;-- almacen del que realmente sale la linea
    v_origen_venta TEXT;       -- barra | cocina_al_pedido | cocina_por_tanda | servicio
    -- FASE 2 · cobro que no re-descuenta lo ya movido al pedir
    v_id_cuenta_abierta BIGINT;-- cuenta abierta de la mesa, si la hay
    v_id_item_cuenta BIGINT;   -- linea de esa cuenta que corresponde a este producto
    v_ya_movido BOOLEAN;       -- true si el stock ya salio al pedirse
    v_lineas_ya_movidas INTEGER := 0;
    v_lineas_descontadas INTEGER := 0;
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

    -- ══════════════════════════════════════════════════════════════════════
    -- FASE 2 · Localizar la cuenta abierta de esta mesa.
    --
    -- Si la venta viene de una cuenta abierta, sus lineas pueden traer el stock
    -- YA descontado (fn_pedir_item_cuenta lo movio al pedir). Cobrar tiene que
    -- respetar eso: volver a descontar duplicaria el consumo.
    --
    -- Se busca por mesa y estado abierto, que es como la localiza el resto del
    -- flujo (fn_abrir_cuenta_mesa reusa por (id_mesa, estado = 1)).
    -- ══════════════════════════════════════════════════════════════════════
    IF p_id_mesa IS NOT NULL THEN
      SELECT c.id INTO v_id_cuenta_abierta
        FROM app_dat_mesa_cuenta_abierta c
       WHERE c.id_mesa = p_id_mesa
         AND c.estado = 1
       ORDER BY c.created_at ASC
       LIMIT 1;
    END IF;

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
          -- Ya movido al pedir: el INSERT solo deja rastro, no decrementa.
          WHEN v_es_elaborado = true
               OR v_origen_venta <> 'barra'
               OR v_ya_movido = true
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
      -- FASE 2 · Descuento enrutado, SALVO que ya se movio al pedir.
      --
      -- "Pedir != cobrar": si esta linea ya salio del inventario cuando el
      -- mesero la pidio (fn_pedir_item_cuenta), cobrar es un acto puramente
      -- contable. Volver a descontar aqui duplicaria el consumo: cada plato
      -- pagaria su materia prima dos veces.
      --
      -- Se identifica la linea de la cuenta abierta por producto + variante +
      -- presentacion, tomando una que tenga stock_movido = true y no haya sido
      -- consumida ya por otra linea de esta misma venta. Las lineas creadas
      -- antes de la Fase 2 tienen stock_movido = false: se descuentan aqui como
      -- siempre, sin cambio de comportamiento.
      -- ══════════════════════════════════════════════════════════════════════
      v_ya_movido := false;
      v_id_item_cuenta := NULL;

      IF v_id_cuenta_abierta IS NOT NULL THEN
        SELECT i.id INTO v_id_item_cuenta
          FROM app_dat_mesa_cuenta_item i
         WHERE i.id_cuenta = v_id_cuenta_abierta
           AND i.id_producto = (v_producto->>'id_producto')::BIGINT
           AND COALESCE(i.id_variante, 0)
               = COALESCE(NULLIF(v_producto->>'id_variante', '')::BIGINT, 0)
           -- La presentacion solo discrimina si AMBOS lados la traen.
           -- fn_pedir_item_cuenta la guarda NULL cuando el vendedor no la manda,
           -- mientras el cobro SI la resuelve: comparar con COALESCE(...,0)
           -- nunca emparejaba y el cobro volvia a descontar.
           AND (i.id_presentacion IS NULL
                OR v_producto_presentacion_id IS NULL
                OR i.id_presentacion = v_producto_presentacion_id)
           AND i.stock_movido = true
         ORDER BY i.id
         LIMIT 1;

        v_ya_movido := (v_id_item_cuenta IS NOT NULL);
      END IF;

      IF v_ya_movido THEN
        -- Ya salio del inventario al pedirse: no se toca nada.
        v_lineas_ya_movidas := v_lineas_ya_movidas + 1;

        -- Marcar la linea como cobrada para que no la reuse otra linea de esta
        -- venta (una venta puede repetir el mismo producto en dos entradas).
        UPDATE app_dat_mesa_cuenta_item
           SET stock_movido = false,
               updated_at = now()
         WHERE id = v_id_item_cuenta;
      ELSE
        v_descuento_bom := public.fn_descontar_venta_enrutada(
          p_id_producto       := (v_producto->>'id_producto')::BIGINT,
          p_cantidad          := (v_producto->>'cantidad')::NUMERIC,
          p_id_tpv            := p_id_tpv,
          p_id_extraccion     := v_id_extraccion,
          p_origen_cambio     := 4,
          p_ya_descontado_sku := (v_origen_venta = 'barra' AND v_es_elaborado = false)
        );

        IF (v_descuento_bom->>'status') <> 'success' THEN
          RETURN v_descuento_bom || jsonb_build_object(
            'id_producto', (v_producto->>'id_producto')::BIGINT,
            'id_almacen',  v_id_almacen_origen
          );
        END IF;

        v_lineas_descontadas := v_lineas_descontadas + 1;
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
      -- Trazabilidad de la Fase 2: cuantas lineas ya venian descontadas del
      -- momento de pedir y cuantas se descontaron en el cobro.
      'lineas_ya_movidas_al_pedir', v_lineas_ya_movidas,
      'lineas_descontadas_al_cobrar', v_lineas_descontadas,
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


GRANT EXECUTE ON FUNCTION public.fn_registrar_venta_mesa(bigint, uuid, jsonb, text, text, text, smallint, bigint, bigint)
    TO PUBLIC, anon, authenticated, service_role;


-- ============================================================================
-- VERIFICACION
-- ============================================================================

-- (a) Debe tener el 17, seguir enrutando y conservar las validaciones de mesa
SELECT p.oid::regprocedure AS firma,
       length(p.prosrc) AS largo,
       (p.prosrc LIKE '%v_lineas_ya_movidas%')                  AS tiene_17,
       (p.prosrc LIKE '%stock_movido = true%')                  AS empareja_linea,
       (p.prosrc LIKE '%MESA_NOT_FOUND%')                       AS conserva_mesa,
       (p.prosrc LIKE '%fn_descontar_venta_enrutada%')           AS enruta,
       (p.prosrc LIKE '%fn_descontar_ingredientes_elaborado%')   AS helper_viejo
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'fn_registrar_venta_mesa';

-- (b) El emparejamiento NO debe usar COALESCE sobre la presentacion -> false
SELECT (p.prosrc LIKE '%COALESCE(v_producto_presentacion_id, 0)%') AS usa_coalesce_presentacion
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'fn_registrar_venta_mesa';


-- ----------------------------------------------------------------------------
-- PRUEBA FUNCIONAL · EJECUTADA Y VERDE (resultados reales anotados)
--
-- Se corrio por MCP contra produccion en una transaccion revertida, simulando
-- el JWT del vendedor del TPV 18 (las RPC llevan check_user_has_access_to_tienda,
-- que necesita auth.uid()):
--
--   SELECT set_config('request.jwt.claims',
--       json_build_object('sub','<uuid-vendedor>','role','authenticated')::text, true);
--
-- A · COBRO DE LINEA YA MOVIDA (el objetivo del archivo)
--     harina cocina 500 -> pedir 2 croquetas -> 420 -> cobrar -> 420
--     bajo_al_pedir 80, bajo_al_cobrar 0
--     lineas_ya_movidas_al_pedir 1, lineas_descontadas_al_cobrar 0
--     SIN_DOBLE_DESCUENTO: true
--
-- B · NO REGRESION, mostrador sin mesa
--     barra 5 -> vender 1 harina -> 4  (bajo 1)
--     ya_movidas 0, descontadas 1  -> descuenta como siempre
--
-- C · LINEA LEGADO (creada por fn_agregar_item_cuenta_mesa, stock_movido=false)
--     bajo 1, ya_movidas 0, descontadas 1
--     Las cuentas abiertas anteriores a la Fase 2 siguen cobrandose igual.
-- ----------------------------------------------------------------------------
