-- ============================================================================
-- 11 · Fase 1 · Enchufar el enrutamiento en las funciones de venta
-- ============================================================================
-- Proyecto Supabase: vsieeihstajlrdvpuooh
--
-- ESTE ARCHIVO TOCA DINERO REAL. Leer la seccion de hallazgos antes de aplicar.
--
-- QUE FALTA DESPUES DEL 10
-- ------------------------
-- El 10 dejo listos y probados los dos helpers de enrutamiento:
--   fn_resolver_origen_venta      decide de que almacen sale cada linea
--   fn_descontar_venta_enrutada   descuenta de ese almacen
--
-- Pero fn_registrar_venta y fn_registrar_venta_mesa siguen llamando al helper
-- viejo con el almacen del TPV. Este archivo las cambia.
--
--
-- ══════════════════════════════════════════════════════════════════════════
-- HALLAZGO BLOQUEANTE (leer antes de aplicar)
-- ══════════════════════════════════════════════════════════════════════════
-- No basta con cambiar el bloque de descuento. Antes de llegar ahi, las dos
-- funciones resuelven la UBICACION del producto y lo hacen SOLO dentro del
-- almacen del TPV (lineas ~204 y ~591 del 03):
--
--     IF v_id_ubicacion_resuelto IS NULL THEN
--       SELECT ip.id_ubicacion INTO v_id_ubicacion_resuelto
--         FROM app_dat_inventario_productos ip
--         JOIN app_dat_layout_almacen la ON la.id = ip.id_ubicacion
--        WHERE ip.id_producto = ...
--          AND la.id_almacen = v_id_almacen        <-- almacen del TPV
--        ...
--       IF v_id_ubicacion_resuelto IS NULL THEN
--         RETURN ... 'NO_LOCATION_FOUND' ...       <-- CORTA LA VENTA AQUI
--       END IF;
--     END IF;
--
-- Un plato de cocina NO tiene inventario en el almacen de la barra. Por tanto:
--
--   * v_id_ubicacion_resuelto queda NULL
--   * la funcion devuelve NO_LOCATION_FOUND
--   * la venta falla ANTES de llegar al bloque de descuento
--
-- Es decir: aunque el 09 haga que el vendedor VEA el plato y el 10 sepa de
-- donde descontarlo, al intentar venderlo el sistema lo rechaza en un punto
-- anterior. Cambiar solo el descuento no arregla nada.
--
-- Hay que intervenir en DOS puntos por funcion:
--
--   punto A (resolucion de ubicacion)  usar el almacen que resuelva el
--                                      enrutamiento, no siempre el del TPV
--   punto B (descuento de MP)          delegar en fn_descontar_venta_enrutada
--
-- Y hay una consecuencia de diseno que conviene decidir explicitamente:
-- app_dat_extraccion_productos.id_ubicacion guardara una ubicacion DE LA COCINA
-- para las lineas de cocina. Eso es lo correcto (es donde realmente salio la
-- mercancia y hace auditable el consumo por estacion), pero cualquier reporte
-- que asuma "toda extraccion de una venta pertenece al almacen del TPV" vera
-- ubicaciones de otro almacen. Ver consulta 11.1 para medir el impacto.
--
--
-- ORDEN DE APLICACION
-- -------------------
--   1. Correr 11.1 (impacto) y 11.2 (confirmar que el 03 sigue intacto).
--   2. Aplicar 11.3 y 11.4 (las dos funciones completas).
--   3. Correr la VERIFICACION y la prueba funcional del final.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 11.1 Medir el impacto del cambio de id_ubicacion (NO MODIFICA NADA)
--
-- Busca reportes/funciones que unan extracciones con el almacen del TPV. Si
-- alguna asume que coinciden, hay que revisarla despues de aplicar este archivo.
-- ----------------------------------------------------------------------------
SELECT
    p.oid::regprocedure AS funcion,
    length(p.prosrc)    AS largo
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.prosrc ILIKE '%app_dat_extraccion_productos%'
   AND p.prosrc ILIKE '%id_almacen%'
   AND p.proname NOT IN ('fn_registrar_venta', 'fn_registrar_venta_mesa')
 ORDER BY p.proname;


-- ----------------------------------------------------------------------------
-- 11.2 Confirmar que las funciones de venta siguen como las dejo el 03
--
-- RESULTADO OBTENIDO (verificado):
--   fn_registrar_venta       prod 11719  local 11383 + 336 lineas (CR) = 11719  OK
--   fn_registrar_venta_mesa  prod 11452  local 11120 + 332 lineas (CR) = 11452  OK
--
-- La diferencia era solo el CR de los finales de linea CRLF del archivo local
-- (un byte por linea). Los cuerpos son IDENTICOS: el 03 sirve como base fiable
-- para este archivo. delega_en_helper = true y conserva_patron_roto = false en
-- ambas, como se esperaba.
-- ----------------------------------------------------------------------------
SELECT
    p.oid::regprocedure AS firma,
    length(p.prosrc)    AS largo_cuerpo,
    (p.prosrc ILIKE '%fn_descontar_ingredientes_elaborado%') AS delega_en_helper,
    (p.prosrc ILIKE '%v_inventario_ingrediente%')            AS conserva_patron_roto,
    (p.prosrc ILIKE '%fn_descontar_venta_enrutada%')          AS ya_tiene_el_11
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_registrar_venta', 'fn_registrar_venta_mesa')
 ORDER BY p.proname;


-- ----------------------------------------------------------------------------
-- 11.2c RESULTADO DEL 11.2b · las dos dudas quedaron resueltas
--
-- (1) fn_descontar_inventario_plato · NO INTERFIERE. Es codigo muerto.
--     Existen dos versiones (una trigger sin argumentos y una de 3 argumentos)
--     y AMBAS operan sobre tablas de otro esquema de restaurante:
--       app_rest_recetas, app_rest_platos_elaborados,
--       app_rest_venta_platos, app_rest_descuentos_inventario
--     Se comprobo contra produccion: las CUATRO devuelven PGRST205
--     ("Could not find the table ... in the schema cache"). No existen.
--     Son de una implementacion de restaurante abandonada; nunca se ejecutan
--     sin fallar. No hay que integrarse con ellas ni respetarlas.
--
--     (De paso: la version trigger hacia
--        UPDATE app_dat_inventario_productos SET cantidad_final = ...
--                                          WHERE id_producto = ...
--      sin filtrar ubicacion NI almacen, y mutando la fila en vez de insertar
--      un movimiento nuevo. Es el mismo antipatron que arreglo la Fase 0, a lo
--      grande. Otra razon para no tomarla como referencia.)
--
-- (2) fn_almacen_de_extraccion · EL CAMBIO ES SEGURO Y ADEMAS CORRECTO.
--     Su definicion real es:
--
--         COALESCE(
--           (1) almacen del layout de la linea   -- ep.id_ubicacion -> la.id_almacen
--           (2) almacen del TPV de la venta      -- fallback
--         )
--
--     Ya prioriza la ubicacion de la linea sobre el almacen del TPV. Es decir:
--     el sistema YA esta disenado para que una extraccion pueda pertenecer a un
--     almacen distinto del TPV, y los reportes que usan este helper atribuiran
--     automaticamente el consumo a la COCINA. Eso es exactamente lo que se
--     quiere para auditar produccion por estacion (Fase 3).
--
--     Guardar una ubicacion de cocina en app_dat_extraccion_productos no es un
--     efecto colateral a tolerar: es la via que el propio esquema ya contemplaba.
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------

-- 11.2b (ya ejecutada) Exportar las dos funciones que decidian el impacto.
-- Se conserva la consulta para poder repetir la comprobacion si el esquema
-- cambia. El analisis de su resultado esta en 11.2c, arriba.
-- ----------------------------------------------------------------------------
SELECT
    p.oid::regprocedure       AS firma,
    pg_get_functiondef(p.oid) AS definicion
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_almacen_de_extraccion', 'fn_descontar_inventario_plato')
 ORDER BY p.proname;


-- ----------------------------------------------------------------------------
-- 11.3 / 11.4 · fn_registrar_venta y fn_registrar_venta_mesa enrutadas
--
-- Generadas por _generar_11.py a partir de los cuerpos del 03 (verificados
-- identicos a produccion en 11.2). El script aplica exactamente cuatro cambios
-- por funcion, ASSERTA que cada anclaje aparezca una sola vez, comprueba que el
-- balance IF/END IF no cambie y que no se perdio ningun bloque critico (pago
-- monto 0, validaciones de mesa, extraccion, estado de operacion).
--
-- Los cuatro cambios:
--   A  DECLARE: v_ruta, v_id_almacen_origen, v_origen_venta
--   B  resolucion de ubicacion en el almacen de ORIGEN, con fallback a un
--      layout de la cocina para platos al_pedido (no tienen inventario propio)
--   C1 el INSERT de inventario NO decrementa el SKU si el origen es cocina
--   C2 el descuento delega en fn_descontar_venta_enrutada
--
-- Regenerar con:  python funcionalidad_cocina/_generar_11.py
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


-- Los GRANT no cambian (CREATE OR REPLACE los conserva), pero se reafirman por
-- si la funcion se recreara desde cero en otro entorno.
GRANT EXECUTE ON FUNCTION public.fn_registrar_venta(bigint, uuid, jsonb, text, text, text, smallint, bigint)
    TO PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.fn_registrar_venta_mesa(bigint, uuid, jsonb, text, text, text, smallint, bigint, bigint)
    TO PUBLIC, anon, authenticated, service_role;


-- ============================================================================
-- VERIFICACION
-- ============================================================================

-- (a) Ambas deben delegar en el enrutador y NO llamar ya al helper viejo
--     directamente -> 2 filas con enruta=true, llama_helper_viejo=false
SELECT
    p.oid::regprocedure AS firma,
    length(p.prosrc)    AS largo_cuerpo,
    (p.prosrc ILIKE '%fn_descontar_venta_enrutada%')          AS enruta,
    (p.prosrc ILIKE '%fn_resolver_origen_venta%')             AS resuelve_origen,
    (p.prosrc ILIKE '%fn_descontar_ingredientes_elaborado%')  AS llama_helper_viejo,
    (p.prosrc ILIKE '%v_id_almacen_origen%')                  AS usa_almacen_origen
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_registrar_venta', 'fn_registrar_venta_mesa')
 ORDER BY p.proname;

-- (b) Los bloques criticos deben seguir vivos -> 2 filas, todo true
SELECT
    p.proname,
    (p.prosrc LIKE '%app_dat_extraccion_productos%')       AS registra_extraccion,
    (p.prosrc LIKE '%app_dat_estado_operacion%')           AS registra_estado,
    (p.prosrc LIKE '%RETURNING id INTO v_id_extraccion%')  AS captura_extraccion,
    CASE p.proname
      WHEN 'fn_registrar_venta'
        THEN (p.prosrc LIKE '%Venta mostrador - monto 0%')
      ELSE (p.prosrc LIKE '%MESA_NOT_FOUND%' AND p.prosrc LIKE '%MESA_WRONG_TIENDA%')
    END AS conserva_especificos
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_registrar_venta', 'fn_registrar_venta_mesa')
 ORDER BY p.proname;

-- (c) Ninguna debe conservar una busqueda de ubicacion atada al almacen del TPV
--     -> 0 filas
SELECT p.oid::regprocedure AS aun_atada_al_tpv
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_registrar_venta', 'fn_registrar_venta_mesa')
   AND p.prosrc LIKE '%AND la.id_almacen = v_id_almacen' || chr(10) || '%';


-- ----------------------------------------------------------------------------
-- PRUEBA FUNCIONAL DE PUNTA A PUNTA (transaccion revertida)
--
-- Es la prueba que cierra la Fase 1: ventas REALES con las tres cosas
-- conviviendo, como pide el plan ("En la misma cuenta conviven: listo para
-- venta (cerveza), tanda (moro) y al pedido (bistec)").
--
-- Datos reales verificados contra produccion:
--   tienda 11, TPV 18 -> almacen 12 (barra); ubicacion 37 pertenece al almacen 12
--   219 "croqueta" elaborado = 40 g harina (216) + 10 g sal (218)
--   harina (216) en barra: 5.0     sal (218) en barra: 27.5
--
-- Sustituir TODOS los <UUID> por un uuid de trabajador valido de la tienda 11.
-- Ejecutar TODO el bloque de una vez.
-- ----------------------------------------------------------------------------
/*
BEGIN;

    -- Montaje -------------------------------------------------------------
    SELECT public.fn_crear_cocina(11, 'PRUEBA Cocina 11') AS cocina;

    SELECT public.fn_asignar_tpv_cocina(
        18,
        (SELECT id FROM app_dat_cocina WHERE denominacion = 'PRUEBA Cocina 11')
    ) AS ligar;

    -- MP solo en la COCINA: 500 g harina, 200 g sal -> alcanza para 12 croquetas
    INSERT INTO app_dat_inventario_productos
        (id_producto, id_ubicacion, cantidad_inicial, cantidad_final, created_at)
    SELECT 216, la.id, 500, 500, now()
      FROM app_dat_layout_almacen la
      JOIN app_dat_cocina c ON c.id_almacen = la.id_almacen
     WHERE c.denominacion = 'PRUEBA Cocina 11' LIMIT 1;

    INSERT INTO app_dat_inventario_productos
        (id_producto, id_ubicacion, cantidad_inicial, cantidad_final, created_at)
    SELECT 218, la.id, 200, 200, now()
      FROM app_dat_layout_almacen la
      JOIN app_dat_cocina c ON c.id_almacen = la.id_almacen
     WHERE c.denominacion = 'PRUEBA Cocina 11' LIMIT 1;

    UPDATE app_dat_producto
       SET id_cocina = (SELECT id FROM app_dat_cocina
                         WHERE denominacion = 'PRUEBA Cocina 11'),
           modo_elaboracion = 'al_pedido'
     WHERE id = 219;

    -- Foto ANTES ----------------------------------------------------------
    SELECT 'ANTES' AS momento,
           public.fn_stock_producto_almacen(216, 12) AS harina_barra,
           public.fn_stock_producto_almacen(218, 12) AS sal_barra,
           public.fn_stock_producto_almacen(216,
             (SELECT id_almacen FROM app_dat_cocina
               WHERE denominacion = 'PRUEBA Cocina 11')) AS harina_cocina,
           public.fn_stock_producto_almacen(218,
             (SELECT id_almacen FROM app_dat_cocina
               WHERE denominacion = 'PRUEBA Cocina 11')) AS sal_cocina;
    -- esperado: 5.0 / 27.5 / 500 / 200

    -- 1. VENTA REAL de 2 croquetas al_pedido ------------------------------
    -- Antes del 11 esto devolvia NO_LOCATION_FOUND y no se podia vender.
    SELECT public.fn_registrar_venta(
        p_id_tpv    := 18,
        p_uuid      := '<UUID>'::uuid,
        p_productos := jsonb_build_array(
            jsonb_build_object(
                'id_producto',     219,
                'cantidad',        2,
                'precio_unitario', 100
            )
        )
    ) AS venta_al_pedido;
    -- esperado: status success, total_venta 200

    -- 2. Foto DESPUES  ·  COMPROBACION CLAVE ------------------------------
    SELECT 'DESPUES' AS momento,
           public.fn_stock_producto_almacen(216, 12) AS harina_barra,
           public.fn_stock_producto_almacen(218, 12) AS sal_barra,
           public.fn_stock_producto_almacen(216,
             (SELECT id_almacen FROM app_dat_cocina
               WHERE denominacion = 'PRUEBA Cocina 11')) AS harina_cocina,
           public.fn_stock_producto_almacen(218,
             (SELECT id_almacen FROM app_dat_cocina
               WHERE denominacion = 'PRUEBA Cocina 11')) AS sal_cocina;
    -- esperado: harina_barra   5.0   <- INTACTA
    --           sal_barra     27.5   <- INTACTA
    --           harina_cocina  420   <- 500 - 80
    --           sal_cocina     180   <- 200 - 20

    -- 3. La extraccion debe apuntar a una ubicacion DE LA COCINA ----------
    SELECT ep.id_producto,
           ep.cantidad,
           ep.id_ubicacion,
           la.id_almacen                          AS almacen_de_la_linea,
           public.fn_almacen_de_extraccion(ep.id) AS almacen_derivado,
           (la.id_almacen = (SELECT id_almacen FROM app_dat_cocina
                              WHERE denominacion = 'PRUEBA Cocina 11')) AS es_cocina
      FROM app_dat_extraccion_productos ep
      JOIN app_dat_layout_almacen la ON la.id = ep.id_ubicacion
      JOIN app_dat_operacion_venta ov ON ov.id_operacion = ep.id_operacion
     WHERE ov.id_tpv = 18
     ORDER BY ep.id DESC
     LIMIT 5;
    -- esperado en la linea de la croqueta: es_cocina = true, y
    --           almacen_derivado = almacen de la cocina (no 12)
    -- Asi el consumo queda atribuido a la estacion, no a la barra.

    -- 4. por_tanda: vender porciones hechas -------------------------------
    UPDATE app_dat_producto SET modo_elaboracion = 'por_tanda' WHERE id = 219;

    -- Sin porciones debe rechazar la venta aunque haya MP de sobra.
    SELECT public.fn_registrar_venta(
        18, '<UUID>'::uuid,
        jsonb_build_array(jsonb_build_object(
            'id_producto', 219, 'cantidad', 1, 'precio_unitario', 100))
    ) AS venta_sin_porciones;
    -- esperado: error_code INSUFFICIENT_PORTIONS

    -- Meter 7 porciones hechas en la cocina.
    INSERT INTO app_dat_inventario_productos
        (id_producto, id_ubicacion, cantidad_inicial, cantidad_final, created_at)
    SELECT 219, la.id, 7, 7, now()
      FROM app_dat_layout_almacen la
      JOIN app_dat_cocina c ON c.id_almacen = la.id_almacen
     WHERE c.denominacion = 'PRUEBA Cocina 11' LIMIT 1;

    SELECT public.fn_registrar_venta(
        18, '<UUID>'::uuid,
        jsonb_build_array(jsonb_build_object(
            'id_producto', 219, 'cantidad', 3, 'precio_unitario', 100))
    ) AS venta_por_tanda;
    -- esperado: status success

    SELECT public.fn_stock_producto_almacen(219,
             (SELECT id_almacen FROM app_dat_cocina
               WHERE denominacion = 'PRUEBA Cocina 11')) AS porciones_restantes,
           public.fn_stock_producto_almacen(216,
             (SELECT id_almacen FROM app_dat_cocina
               WHERE denominacion = 'PRUEBA Cocina 11')) AS harina_cocina;
    -- esperado: porciones_restantes 4    (7 - 3, descuento de la PORCION)
    --           harina_cocina       420  <- SIN CAMBIO: no se toco la receta
    --
    -- Si la harina hubiera bajado, se estaria cobrando la MP dos veces: una al
    -- producir la tanda y otra al venderla.

    -- 5. Enrutamiento: TPV no ligado no puede vender el plato -------------
    SELECT public.fn_desasignar_tpv_cocina(
        18,
        (SELECT id FROM app_dat_cocina WHERE denominacion = 'PRUEBA Cocina 11')
    );

    SELECT public.fn_registrar_venta(
        18, '<UUID>'::uuid,
        jsonb_build_array(jsonb_build_object(
            'id_producto', 219, 'cantidad', 1, 'precio_unitario', 100))
    ) AS venta_no_ligada;
    -- esperado: error_code COCINA_NO_LIGADA

    -- 6. NO REGRESION  ·  producto de barra normal ------------------------
    -- Vender harina (216) directo de la barra debe seguir descontando de 12.
    SELECT public.fn_stock_producto_almacen(216, 12) AS harina_barra_antes;

    SELECT public.fn_registrar_venta(
        18, '<UUID>'::uuid,
        jsonb_build_array(jsonb_build_object(
            'id_producto', 216, 'cantidad', 1, 'precio_unitario', 10))
    ) AS venta_barra;
    -- esperado: status success

    SELECT public.fn_stock_producto_almacen(216, 12) AS harina_barra_despues;
    -- esperado: 4.0  <- bajo exactamente 1, NI MAS NI MENOS
    -- Si bajara 2, hay doble descuento (el INSERT de la venta y el helper).

    -- 7. Cuenta mixta: barra + tanda en la MISMA venta --------------------
    -- El escenario del plan. Se vuelve a ligar y se venden las dos cosas juntas.
    SELECT public.fn_asignar_tpv_cocina(
        18,
        (SELECT id FROM app_dat_cocina WHERE denominacion = 'PRUEBA Cocina 11')
    );

    SELECT public.fn_registrar_venta(
        18, '<UUID>'::uuid,
        jsonb_build_array(
            jsonb_build_object('id_producto', 216, 'cantidad', 1, 'precio_unitario', 10),
            jsonb_build_object('id_producto', 219, 'cantidad', 2, 'precio_unitario', 100)
        )
    ) AS venta_mixta;
    -- esperado: status success, total_venta 210

    SELECT public.fn_stock_producto_almacen(216, 12) AS harina_barra,
           public.fn_stock_producto_almacen(219,
             (SELECT id_almacen FROM app_dat_cocina
               WHERE denominacion = 'PRUEBA Cocina 11')) AS porciones;
    -- esperado: harina_barra 3.0 (bajo 1 mas), porciones 2 (bajaron 2)
    -- Cada linea salio de su almacen correcto en la misma operacion.

ROLLBACK;
*/

-- Comprobar que el ROLLBACK dejo todo limpio
-- SELECT id, denominacion FROM app_dat_cocina WHERE denominacion LIKE 'PRUEBA%';
-- SELECT public.fn_stock_producto_almacen(216, 12) AS harina_barra;  -- debe ser 5.0
