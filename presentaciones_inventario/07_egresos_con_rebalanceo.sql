-- ============================================================================
-- 07 · Fase 1 · Egresos: extraccion y transferencia con rebalanceo
-- ============================================================================
-- Plan: docs/PLAN_PRESENTACIONES_INVENTARIO.md  (Fase 1)
-- Proyecto Supabase: vsieeihstajlrdvpuooh
-- Aplicar en: SQL Editor del dashboard. Idempotente (CREATE OR REPLACE).
-- Depende de: 01, 02, 03, 04 aplicados. Conviene aplicar el 06 antes que este.
--
-- REEMPLAZA DOS FUNCIONES VIVAS:
--   public.fn_crear_extraccion_con_movimiento   (prod: 6641 chars, 213 lineas)
--   public.fn_transferir_inventario_entre_layouts (prod: 8949 chars, 291 lineas)
--
-- Verificado antes de escribir: para la transferencia, los archivos del repo
-- ventiq_admin_app/docs/migrations/fn_transferir_inventario_entre_layouts.sql y
-- sql_updates/fn_transferir_inventario_entre_layouts_pendiente_tipos_7_8.sql
-- coinciden byte a byte con produccion (8949 chars / 291 lineas, CRLF). Para la
-- extraccion NO hay copia fiel en el repo (fn_insertar_extraccion_completa.sql
-- es otra funcion, 7817 chars), asi que se partio del pg_get_functiondef vivo.
--
--
-- POR QUE ESTAS DOS Y NO MAS
-- --------------------------
-- fn_crear_extraccion_con_movimiento es el UNICO punto donde el sistema
-- descuenta por extraccion. Se comprobo en el catalogo (no en el repo) quien la
-- llama:
--
--   crear_devolucion_consignacion_v2      (devolucion de consignacion)
--   aprobar_devolucion_consignacion_v2    (aprobacion de esa devolucion)
--   fn_transferir_inventario_entre_layouts(la pata de salida de un traslado)
--   fn_admin_caja_extraccion_offline      (sync de caja offline)
--   ... mas las llamadas directas desde Dart:
--       ventiq_admin_app/lib/services/inventory_service.dart:192
--       ventiq_admin_app/lib/services/consignacion_service.dart:894
--       ventiq_admin_app/lib/screens/asignar_productos_consignacion_screen.dart:290
--       ventiq_app/lib/services/admin_inventory_service.dart:1688
--
-- Arreglarla arregla las cinco rutas de egreso de una vez. Ninguna de las que
-- la llaman necesita cambios: la firma y el contrato de respuesta se conservan.
--
--
-- QUE CAMBIA EN fn_crear_extraccion_con_movimiento
-- ------------------------------------------------
-- Codigo actual (verbatim de produccion):
--
--     SELECT COALESCE(cantidad_final, 0) INTO v_cantidad_inicial
--       FROM app_dat_inventario_productos
--      WHERE id_producto = v_id_producto
--        AND (id_variante        IS NOT DISTINCT FROM v_id_variante)
--        AND (id_opcion_variante IS NOT DISTINCT FROM v_id_opcion_variante)
--        AND (id_ubicacion       IS NOT DISTINCT FROM v_id_ubicacion)
--        AND (id_presentacion    IS NOT DISTINCT FROM v_id_presentacion)
--      ORDER BY created_at DESC LIMIT 1;
--     ...
--     v_cantidad_final := v_cantidad_inicial - v_cantidad;
--     INSERT INTO app_dat_inventario_productos (...) VALUES (...);
--
-- Tres defectos, en orden de gravedad:
--
-- 1. NO REBALANCEA. Si piden 1 unidad y solo hay cajas, el saldo de unidades es
--    0 y escribe cantidad_final = -1. La funcion no valida stock en ningun
--    punto: acepta cualquier cantidad y deja el ledger negativo. Es el motivo
--    central de la Fase 0.
-- 2. `ORDER BY created_at DESC` empata cuando hay varias lineas del mismo
--    producto/presentacion/ubicacion en la misma extraccion, porque NOW() es
--    constante en la transaccion. El desempate lo decide el plan de ejecucion.
-- 3. No valida el id_presentacion. Produccion tiene 32 filas de
--    app_dat_extraccion_productos con una presentacion de OTRO producto y 2.863
--    con NULL.
--
-- Ahora: se resuelve/valida la presentacion igual que en el 06, y el descuento
-- se delega en fn_descontar_con_rebalanceo, que abre o empaqueta lo necesario,
-- lee el saldo con `id DESC` y RECHAZA si ni con conversion alcanza.
--
-- Consecuencia deliberada: una extraccion sin stock suficiente ahora FALLA en
-- vez de dejar saldo negativo. Es un cambio de comportamiento visible; el
-- status/message del error viaja en el mismo formato que ya devolvia la funcion.
--
--
-- QUE CAMBIA EN fn_transferir_inventario_entre_layouts
-- ----------------------------------------------------
-- Una sola linea:
--
--     v_productos_base := public.fn_productos_json_a_presentacion_base(p_productos);
--
-- Aplanaba 2 cajas a 24 unidades ANTES de extraer, y luego ingresaba 24
-- unidades en el destino. El criterio de aceptacion del plan dice "Transferir
-- 2 cajas no las convierte a 24 unidades en destino". Ahora el JSON pasa tal
-- cual: se extraen 2 cajas del origen (con rebalanceo si hace falta) y se
-- ingresan 2 cajas en el destino.
--
-- Todo lo demas se conserva: tipos de operacion 7 y 8, la operacion padre 19,
-- app_dat_operacion_transferencia, el orden entregado/transporta/recibe, el
-- p_completar_operaciones y el bloque EXCEPTION con 'id_extraccion_parcial'.
--
-- NOTA: fn_productos_json_a_presentacion_base sigue existiendo y no se toca.
-- Despues de este archivo ya no queda ninguna funcion viva que la llame
-- (verificado en el catalogo); se deja para no romper nada que no hayamos visto.
-- ============================================================================


-- ────────────────────────────────────────────────────────────────────────────
-- 7.1 · fn_crear_extraccion_con_movimiento
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_crear_extraccion_con_movimiento(
  p_autorizado_por      TEXT,
  p_estado_inicial      SMALLINT,
  p_id_motivo_operacion BIGINT,
  p_id_tienda           BIGINT,
  p_observaciones       TEXT,
  p_productos           JSONB,
  p_uuid                UUID
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_id_operacion        BIGINT;
  v_id_extraccion_prod  BIGINT;
  v_id_tipo_operacion   BIGINT;
  v_producto_record     JSONB;
  v_cantidad_total      NUMERIC := 0;
  v_result              JSONB;
  v_tienda_exists       BOOLEAN;
  v_motivo_exists       BOOLEAN;
  -- Variables para el movimiento de inventario
  v_id_producto         BIGINT;
  v_id_variante         BIGINT;
  v_id_opcion_variante  BIGINT;
  v_id_ubicacion        BIGINT;
  v_id_presentacion     BIGINT;
  v_cantidad            NUMERIC;
  v_precio_unitario     NUMERIC;
  v_sku_producto        TEXT;
  v_sku_ubicacion       TEXT;
  v_descuento           JSONB;   -- NUEVO: resultado de fn_descontar_con_rebalanceo
  v_err_message         TEXT;    -- NUEVO: para el error de validacion
BEGIN
  -- ── Validaciones ──────────────────────────────────────────────────────────
  SELECT EXISTS(SELECT 1 FROM app_dat_tienda WHERE id = p_id_tienda)
  INTO v_tienda_exists;

  SELECT EXISTS(SELECT 1 FROM app_nom_motivo_extraccion WHERE id = p_id_motivo_operacion)
  INTO v_motivo_exists;

  IF NOT v_tienda_exists THEN
    RAISE EXCEPTION 'La tienda con ID % no existe', p_id_tienda;
  END IF;

  IF NOT v_motivo_exists THEN
    RAISE EXCEPTION 'El motivo de extracción con ID % no existe', p_id_motivo_operacion;
  END IF;

  IF jsonb_array_length(p_productos) = 0 THEN
    RAISE EXCEPTION 'Debe incluir al menos un producto';
  END IF;

  -- ── Obtener tipo de operación Extracción ───────────────────────────────────
  SELECT id INTO v_id_tipo_operacion
  FROM app_nom_tipo_operacion
  WHERE denominacion ILIKE '%extraccion%' OR denominacion ILIKE '%extracción%'
  LIMIT 1;

  IF v_id_tipo_operacion IS NULL THEN
    RAISE EXCEPTION 'No se encontró tipo de operación para extracción';
  END IF;

  -- ── 1. Operación principal ─────────────────────────────────────────────────
  INSERT INTO app_dat_operaciones (
    id_tipo_operacion,
    uuid,
    id_tienda,
    observaciones,
    created_at
  ) VALUES (
    v_id_tipo_operacion,
    p_uuid,
    p_id_tienda,
    p_observaciones,
    NOW()
  ) RETURNING id INTO v_id_operacion;

  -- ── 2. Detalle de extracción ───────────────────────────────────────────────
  INSERT INTO app_dat_operacion_extraccion (
    id_operacion,
    id_motivo_operacion,
    observaciones,
    autorizado_por,
    created_at
  ) VALUES (
    v_id_operacion,
    p_id_motivo_operacion,
    p_observaciones,
    p_autorizado_por,
    NOW()
  );

  -- ── 3. Productos + movimiento de inventario inmediato ─────────────────────
  FOR v_producto_record IN SELECT * FROM jsonb_array_elements(p_productos)
  LOOP
    IF v_producto_record->>'id_producto' IS NULL OR v_producto_record->>'cantidad' IS NULL THEN
      RAISE EXCEPTION 'Cada producto debe tener id_producto y cantidad';
    END IF;

    -- Extraer campos del JSON
    v_id_producto        := (v_producto_record->>'id_producto')::BIGINT;
    v_id_variante        := NULLIF(v_producto_record->>'id_variante', '')::BIGINT;
    v_id_opcion_variante := NULLIF(v_producto_record->>'id_opcion_variante', '')::BIGINT;
    v_id_ubicacion       := NULLIF(v_producto_record->>'id_ubicacion', '')::BIGINT;
    v_id_presentacion    := NULLIF(v_producto_record->>'id_presentacion', '')::BIGINT;
    v_cantidad           := (v_producto_record->>'cantidad')::NUMERIC;
    v_precio_unitario    := NULLIF(v_producto_record->>'precio_unitario', '')::NUMERIC;
    v_sku_producto       := v_producto_record->>'sku_producto';
    v_sku_ubicacion      := v_producto_record->>'sku_ubicacion';

    -- ── NUEVO (Fase 1): la ubicacion es obligatoria ───────────────────────
    -- fn_descontar_con_rebalanceo necesita una ubicacion concreta para saber
    -- de que estante abrir. Antes un NULL aqui escribia una fila del ledger
    -- sin ubicacion, invisible para cualquier desglose.
    IF v_id_ubicacion IS NULL THEN
      RAISE EXCEPTION
        'La linea del producto % no trae id_ubicacion; el descuento por presentacion lo necesita',
        v_id_producto
        USING ERRCODE = '22023';
    END IF;

    -- ── NUEVO (Fase 1): resolver y validar la presentacion ────────────────
    IF v_id_presentacion IS NULL THEN
      SELECT c.id_presentacion
      INTO v_id_presentacion
      FROM public.fn_presentaciones_producto(v_id_producto) c
      WHERE c.es_base
      LIMIT 1;

      IF v_id_presentacion IS NULL THEN
        RAISE EXCEPTION
          'El producto % no tiene ninguna presentacion configurada en app_dat_producto_presentacion',
          v_id_producto
          USING ERRCODE = '22023';
      END IF;
    END IF;

    PERFORM public.fn_validar_id_presentacion(v_id_producto, v_id_presentacion);

    -- 3a. Registrar producto en la extracción
    INSERT INTO app_dat_extraccion_productos (
      id_operacion,
      id_producto,
      id_variante,
      id_opcion_variante,
      id_ubicacion,
      id_presentacion,
      cantidad,
      precio_unitario,
      sku_producto,
      sku_ubicacion,
      created_at
    ) VALUES (
      v_id_operacion,
      v_id_producto,
      v_id_variante,
      v_id_opcion_variante,
      v_id_ubicacion,
      v_id_presentacion,
      v_cantidad,
      v_precio_unitario,
      v_sku_producto,
      v_sku_ubicacion,
      NOW()
    ) RETURNING id INTO v_id_extraccion_prod;

    -- ── 3b + 3c + 3d (Fase 1): descuento con rebalanceo ───────────────────
    -- Sustituye al bloque que leia el saldo con `ORDER BY created_at DESC` y
    -- restaba a ciegas (podia dejar cantidad_final negativa). El helper:
    --   - abre o empaqueta en cadena si el saldo propio no alcanza,
    --   - registra esas conversiones como movimientos aparte (origen_cambio 20),
    --   - lee el saldo con `id DESC` (sin empates dentro de la transaccion),
    --   - devuelve error si ni con conversion alcanza, sin tocar nada.
    v_descuento := public.fn_descontar_con_rebalanceo(
      p_id_producto        := v_id_producto,
      p_id_ubicacion       := v_id_ubicacion,
      p_id_presentacion    := v_id_presentacion,
      p_cantidad           := v_cantidad,
      p_origen_cambio      := 2,                      -- 2 = extraccion
      p_id_extraccion      := v_id_extraccion_prod,
      p_id_variante        := v_id_variante,
      p_id_opcion_variante := v_id_opcion_variante,
      p_id_operacion       := v_id_operacion,
      p_uuid               := p_uuid,
      p_motivo             := 'extraccion'
    );

    IF COALESCE(v_descuento->>'status', '') <> 'success' THEN
      -- RAISE para que la transaccion completa se deshaga: sin esto quedaria
      -- la operacion creada y una extraccion a medias.
      RAISE EXCEPTION '%', COALESCE(
        v_descuento->>'message',
        format('No se pudo descontar el producto %s', v_id_producto))
        USING ERRCODE = 'P0001';
    END IF;

    -- Acumular total
    v_cantidad_total := v_cantidad_total + v_cantidad;
  END LOOP;

  -- ── 4. Estado inicial de la operación ─────────────────────────────────────
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

  -- ── Respuesta exitosa ──────────────────────────────────────────────────────
  v_result := jsonb_build_object(
    'status',          'success',
    'id_operacion',    v_id_operacion,
    'total_productos', jsonb_array_length(p_productos),
    'cantidad_total',  v_cantidad_total,
    'mensaje',         'Extracción registrada y movimientos de inventario aplicados'
  );

  RETURN v_result;

EXCEPTION
  WHEN OTHERS THEN
    v_result := jsonb_build_object(
      'status',    'error',
      'message',   'Error al registrar extracción: ' || SQLERRM,
      'sqlstate',  SQLSTATE
    );
    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.fn_crear_extraccion_con_movimiento(
  TEXT, SMALLINT, BIGINT, BIGINT, TEXT, JSONB, UUID) IS
  'Registra una extraccion y descuenta inventario. Fase 1 de presentaciones: '
  'valida id_presentacion, exige id_ubicacion y delega el descuento en '
  'fn_descontar_con_rebalanceo (abre/empaqueta si hace falta y rechaza si no '
  'alcanza, en vez de dejar saldo negativo). Punto unico de egreso: lo usan '
  'consignacion, transferencia, caja offline y las apps.';


-- ────────────────────────────────────────────────────────────────────────────
-- 7.2 · fn_transferir_inventario_entre_layouts
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_transferir_inventario_entre_layouts(
  p_id_layout_origen      BIGINT,
  p_id_layout_destino     BIGINT,
  p_productos             JSONB,
  p_autorizado_por        TEXT,
  p_observaciones         TEXT    DEFAULT ''::TEXT,
  p_id_tienda             BIGINT  DEFAULT NULL::BIGINT,
  p_uuid                  UUID    DEFAULT NULL::UUID,
  p_completar_operaciones BOOLEAN DEFAULT false,
  p_moneda_factura        TEXT    DEFAULT 'USD'::TEXT,
  p_entregado_por         TEXT    DEFAULT NULL::TEXT,
  p_transportado_por      TEXT    DEFAULT NULL::TEXT,
  p_recibido_por          TEXT    DEFAULT NULL::TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  c_motivo_extraccion      CONSTANT BIGINT  := 7;
  c_motivo_recepcion       CONSTANT INTEGER := 2;

  v_item                   JSONB;
  v_productos_extraccion   JSONB := '[]'::JSONB;
  v_productos_recepcion    JSONB := '[]'::JSONB;
  v_cantidad               NUMERIC;

  v_ext_result             JSONB;
  v_rec_result             JSONB;
  v_id_extraccion          BIGINT;
  v_id_recepcion           BIGINT;

  v_id_tipo_transferencia  BIGINT;
  v_id_operacion_padre     BIGINT;
  v_estado_actual          SMALLINT;
  v_op_a_completar         BIGINT;

  v_entregado              TEXT;
  v_transporta             TEXT;
  v_recibe                 TEXT;
BEGIN
  v_entregado := COALESCE(
    NULLIF(TRIM(p_entregado_por), ''),
    NULLIF(TRIM(p_autorizado_por), ''),
    'Sistema'
  );
  v_transporta := COALESCE(
    NULLIF(TRIM(p_transportado_por), ''),
    v_entregado
  );
  v_recibe := COALESCE(
    NULLIF(TRIM(p_recibido_por), ''),
    v_transporta
  );

  IF p_id_layout_origen IS NULL OR p_id_layout_destino IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'Debe indicar layout de origen y destino',
      'etapa', 'validacion_layouts'
    );
  END IF;

  IF p_id_layout_origen = p_id_layout_destino THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'El layout de origen y destino no pueden ser el mismo',
      'etapa', 'validacion_layouts'
    );
  END IF;

  IF p_productos IS NULL OR jsonb_array_length(p_productos) = 0 THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'Debe incluir al menos un producto',
      'etapa', 'validacion_productos'
    );
  END IF;

  IF p_id_tienda IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'id_tienda es obligatorio',
      'etapa', 'validacion_tienda'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.app_dat_tienda WHERE id = p_id_tienda) THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', format('La tienda %s no existe', p_id_tienda),
      'etapa', 'validacion_tienda'
    );
  END IF;

  IF p_uuid IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'uuid de usuario es obligatorio',
      'etapa', 'validacion_uuid'
    );
  END IF;

  -- ── Fase 1: se ELIMINO la conversion a presentacion base ─────────────────
  -- Antes aqui iba:
  --   v_productos_base := public.fn_productos_json_a_presentacion_base(p_productos);
  -- y el resto del cuerpo iteraba v_productos_base. Eso convertia 2 cajas en
  -- 24 unidades antes de mover nada, y el destino recibia unidades sueltas.
  -- Ahora se itera p_productos tal cual: la presentacion viaja intacta de
  -- origen a destino. El rebalanceo, si el origen no tiene cajas enteras, lo
  -- resuelve fn_descontar_con_rebalanceo dentro de la extraccion.
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_productos)
  LOOP
    IF v_item->>'id_producto' IS NULL OR v_item->>'cantidad' IS NULL THEN
      RAISE EXCEPTION 'Cada producto debe tener id_producto y cantidad';
    END IF;

    v_cantidad := (v_item->>'cantidad')::NUMERIC;
    IF v_cantidad <= 0 THEN
      RAISE EXCEPTION 'La cantidad debe ser mayor que cero (producto %)', v_item->>'id_producto';
    END IF;

    v_productos_extraccion := v_productos_extraccion || jsonb_build_array(
      v_item || jsonb_build_object(
        'id_ubicacion', p_id_layout_origen::TEXT,
        'precio_unitario', COALESCE(NULLIF(v_item->>'precio_unitario', '')::NUMERIC, 0)
      )
    );

    v_productos_recepcion := v_productos_recepcion || jsonb_build_array(
      v_item || jsonb_build_object(
        'id_ubicacion', p_id_layout_destino::TEXT,
        'precio_unitario', 0,
        'id_motivo_operacion', c_motivo_recepcion::TEXT
      )
    );
  END LOOP;

  -- 1. Extracción
  v_ext_result := public.fn_crear_extraccion_con_movimiento(
    p_autorizado_por         => v_entregado,
    p_estado_inicial         => 1::SMALLINT,
    p_id_motivo_operacion    => c_motivo_extraccion,
    p_id_tienda              => p_id_tienda,
    p_observaciones          => 'Extracción para transferencia: ' || COALESCE(p_observaciones, ''),
    p_productos              => v_productos_extraccion,
    p_uuid                   => p_uuid
  );

  IF COALESCE(v_ext_result->>'status', '') <> 'success' THEN
    RAISE EXCEPTION 'Error en extracción: %', COALESCE(v_ext_result->>'message', v_ext_result::TEXT);
  END IF;

  v_id_extraccion := (v_ext_result->>'id_operacion')::BIGINT;

  -- Salida de transferencia: tipo 7 (no el 18 genérico de extracción)
  UPDATE public.app_dat_operaciones
  SET id_tipo_operacion = 7
  WHERE id = v_id_extraccion;

  -- Personas en extracción: entrega = origen, recibe = transporta
  UPDATE public.app_dat_operacion_extraccion
  SET autorizado_por = v_entregado,
      entregado_por  = v_entregado,
      recibido_por    = v_transporta
  WHERE id_operacion = v_id_extraccion;

  -- 2. Recepción: entrega = transporta, recibe = destino
  v_rec_result := public.fn_registrar_recepcion_con_inventario(
    p_entregado_por    => v_transporta,
    p_id_tienda        => p_id_tienda,
    p_monto_total      => 0,
    p_motivo           => c_motivo_recepcion,
    p_observaciones    => 'Transferencia: ' || COALESCE(p_observaciones, ''),
    p_productos        => v_productos_recepcion,
    p_recibido_por     => v_recibe,
    p_uuid             => p_uuid,
    p_moneda_factura   => COALESCE(NULLIF(TRIM(p_moneda_factura), ''), 'USD')
  );

  IF COALESCE(v_rec_result->>'status', '') <> 'success' THEN
    RAISE EXCEPTION 'Error en recepción: %', COALESCE(v_rec_result->>'message', v_rec_result::TEXT);
  END IF;

  v_id_recepcion := (v_rec_result->>'id_operacion')::BIGINT;

  -- Entrada de transferencia: tipo 8 (refuerzo por si el motivo no lo resolvió)
  UPDATE public.app_dat_operaciones
  SET id_tipo_operacion = 8
  WHERE id = v_id_recepcion;

  -- 3. Vínculo transferencia (padre = Transferencia de productos = 19)
  SELECT id
  INTO v_id_tipo_transferencia
  FROM public.app_nom_tipo_operacion
  WHERE id = 19
     OR denominacion ILIKE '%transferencia de productos%'
  ORDER BY CASE WHEN id = 19 THEN 0 ELSE 1 END, id
  LIMIT 1;

  IF v_id_tipo_transferencia IS NULL THEN
    SELECT o.id_tipo_operacion
    INTO v_id_tipo_transferencia
    FROM public.app_dat_operaciones o
    WHERE o.id = v_id_extraccion;
  END IF;

  INSERT INTO public.app_dat_operaciones (
    id_tipo_operacion,
    uuid,
    id_tienda,
    observaciones,
    created_at
  ) VALUES (
    v_id_tipo_transferencia,
    p_uuid,
    p_id_tienda,
    format(
      'Transferencia layout %s → %s (extracción %s, recepción %s). Entrega: %s | Transporta: %s | Recibe: %s',
      p_id_layout_origen,
      p_id_layout_destino,
      v_id_extraccion,
      v_id_recepcion,
      v_entregado,
      v_transporta,
      v_recibe
    ),
    NOW()
  )
  RETURNING id INTO v_id_operacion_padre;

  INSERT INTO public.app_dat_operacion_transferencia (
    id_operacion,
    id_extraccion,
    id_recepcion,
    autorizado_por
  ) OVERRIDING SYSTEM VALUE
  VALUES (
    v_id_operacion_padre,
    v_id_extraccion,
    v_id_recepcion,
    v_entregado
  );

  -- Estado pendiente del padre (la UI lista la transferencia como una sola op)
  INSERT INTO public.app_dat_estado_operacion (
    id_operacion,
    estado,
    uuid,
    created_at
  ) VALUES (
    v_id_operacion_padre,
    1,
    p_uuid,
    NOW()
  );

  -- 4. Completar operaciones
  IF p_completar_operaciones THEN
    FOREACH v_op_a_completar IN ARRAY ARRAY[v_id_extraccion, v_id_recepcion, v_id_operacion_padre]
    LOOP
      SELECT eo.estado
      INTO v_estado_actual
      FROM public.app_dat_estado_operacion eo
      WHERE eo.id_operacion = v_op_a_completar
      ORDER BY eo.created_at DESC
      LIMIT 1;

      IF COALESCE(v_estado_actual, 0) <> 2 THEN
        INSERT INTO public.app_dat_estado_operacion (
          id_operacion,
          estado,
          uuid,
          created_at
        ) VALUES (
          v_op_a_completar,
          2,
          p_uuid,
          NOW()
        );
      END IF;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'status', 'success',
    'message', CASE
      WHEN p_completar_operaciones THEN 'Transferencia entre layouts completada exitosamente'
      ELSE 'Transferencia registrada en pendiente (extracción y recepción)'
    END,
    'id_extraccion', v_id_extraccion,
    'id_recepcion', v_id_recepcion,
    'id_operacion_transferencia', v_id_operacion_padre,
    'total_productos', jsonb_array_length(p_productos),
    'monto_total', 0,
    'entregado_por', v_entregado,
    'transportado_por', v_transporta,
    'recibido_por', v_recibe,
    'estado', CASE WHEN p_completar_operaciones THEN 'completado' ELSE 'pendiente' END
  );

EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', SQLERRM,
      'sqlstate', SQLSTATE,
      'etapa', 'fn_transferir_inventario_entre_layouts',
      'id_extraccion_parcial', v_id_extraccion,
      'id_recepcion_parcial', v_id_recepcion
    );
END;
$$;

COMMENT ON FUNCTION public.fn_transferir_inventario_entre_layouts(
  BIGINT, BIGINT, JSONB, TEXT, TEXT, BIGINT, UUID, BOOLEAN, TEXT, TEXT, TEXT, TEXT) IS
  'Transfiere productos entre dos layouts (extraccion tipo 7 + recepcion tipo 8 '
  '+ operacion padre 19). Fase 1 de presentaciones: ya NO llama a '
  'fn_productos_json_a_presentacion_base, asi que transferir 2 cajas mueve '
  '2 cajas y no 24 unidades.';


-- ============================================================================
-- ENSAYO YA REALIZADO (BEGIN/ROLLBACK contra datos reales, 2026-08-26)
-- ============================================================================
-- Producto con cadena Caja 12 / Unidad 1, tienda 55, ubicaciones 74, 75 y 76.
-- Se aplicaron 06 + 07 completos dentro de la transaccion y se deshizo todo.
--
--   E0  stock inicial: 4 Cajas, 0 sueltas.
--   E1  extraer 1 UNIDAD sin sueltas -> success. Queda "3 Cajas + 11 Unidades".
--       El ledger muestra las cuatro filas en orden: recepcion (oc=1, 0->4),
--       conversion salida caja (oc=20, 4->3, id_conversion), conversion entrada
--       unidades (oc=20, 0->12, id_conversion) y el egreso (oc=2, 12->11,
--       id_extraccion). Antes esta linea escribia cantidad_final = -1.
--   E2  pedir 500 unidades -> error "Stock insuficiente de Unidad: se piden 500
--       y el convertible alcanza para 47.000". Saldos intactos, 0 negativos y
--       CERO operaciones creadas: el bloque EXCEPTION de plpgsql actua como
--       subtransaccion, asi que la operacion y el detalle se deshacen solos.
--   E3  linea sin id_ubicacion -> error 22023.
--   E4  presentacion de otro producto -> error 22023 con el mensaje que lo dice.
--   T1  transferir 2 CAJAS de la 74 a la 75 -> destino "2 Cajas", NO
--       "24 Unidades". Es el criterio de aceptacion del plan. Origen queda
--       "1 Caja + 11 Unidades".
--   T2  transferir 1 CAJA teniendo 1 caja + 11 sueltas -> usa la caja entera;
--       origen "11 Unidades", destino 76 "1 Caja".
--   T3  transferir 1 CAJA teniendo solo 11 sueltas -> error "se piden 1 y el
--       convertible alcanza para 0.916", con id_extraccion_parcial NULL: no
--       quedo ninguna pata suelta.
--   T4  transferir 6 UNIDADES con saldo propio -> sin conversiones. Estado
--       final: 74 "5 Unidades", 75 "2 Cajas + 6 Unidades", 76 "1 Caja",
--       0 saldos negativos y 0 filas de extraccion con presentacion NULL.


-- ============================================================================
-- VERIFICACION (correr despues de aplicar; no modifica datos)
-- ============================================================================
-- OJO: estas funciones DOCUMENTAN en comentarios los patrones viejos que
-- eliminan (`ORDER BY created_at DESC`, `fn_productos_json_a_presentacion_base`).
-- Un `pg_get_functiondef(...) ILIKE '%patron%'` a secas encuentra el comentario
-- y reporta un falso negativo: comprobado en produccion, decia que el aplanado
-- seguia vivo cuando ya no estaba. Hay que filtrar las lineas de comentario.
--
-- 1. Los patrones viejos se fueron y los nuevos estan:
--
--   WITH limpio AS (
--     SELECT p.proname,
--            array_to_string(array(
--              SELECT l FROM regexp_split_to_table(p.prosrc, E'\n') l
--               WHERE btrim(l) NOT LIKE '--%'), E'\n') AS codigo
--       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--      WHERE n.nspname = 'public'
--        AND p.proname IN ('fn_crear_extraccion_con_movimiento',
--                          'fn_transferir_inventario_entre_layouts'))
--   SELECT proname,
--          codigo ILIKE '%fn_descontar_con_rebalanceo%'            AS usa_helper,
--          codigo ILIKE '%fn_validar_id_presentacion%'             AS valida_pres,
--          codigo NOT ILIKE '%ORDER BY created_at DESC%'           AS sin_order_fecha,
--          codigo NOT ILIKE '%v_cantidad_inicial - v_cantidad%'    AS sin_resta_ciega,
--          codigo NOT ILIKE '%fn_productos_json_a_presentacion_base%' AS sin_aplanado
--     FROM limpio ORDER BY proname;
--
--   -- esperado, verificado en produccion 2026-08-26:
--   --   fn_crear_extraccion_con_movimiento:     usa_helper t, valida_pres t,
--   --      sin_order_fecha t, sin_resta_ciega t, sin_aplanado t
--   --   fn_transferir_inventario_entre_layouts: sin_aplanado t, sin_order_fecha t
--   --      (usa_helper y valida_pres son FALSE a proposito: la transferencia
--   --       delega en la extraccion y en la recepcion, no descuenta ella misma)
--
-- 2. La transferencia conserva lo que no debia cambiar:
--
--   SELECT pg_get_functiondef('public.fn_transferir_inventario_entre_layouts'::regproc)
--            ILIKE '%OVERRIDING SYSTEM VALUE%' AS conserva_insert_transferencia,
--          pg_get_functiondef('public.fn_transferir_inventario_entre_layouts'::regproc)
--            ILIKE '%SECURITY DEFINER%'        AS conserva_secdef;
--   -- esperado: true, true
--
-- 3. Ya no queda NINGUNA funcion viva que aplane a base:
--
--   WITH limpio AS (
--     SELECT p.oid::regprocedure AS firma,
--            array_to_string(array(
--              SELECT l FROM regexp_split_to_table(p.prosrc, E'\n') l
--               WHERE btrim(l) NOT LIKE '--%'), E'\n') AS codigo
--       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--      WHERE n.nspname = 'public'
--        AND p.proname <> 'fn_productos_json_a_presentacion_base')
--   SELECT firma FROM limpio
--    WHERE codigo ILIKE '%fn_productos_json_a_presentacion_base%';
--   -- esperado: 0 filas. Verificado en produccion 2026-08-26.
--   -- (la propia fn_productos_json_a_presentacion_base sigue existiendo, sin
--   --  usarse; no se borra para no romper nada que no hayamos visto)
--
-- 4. Las firmas y los permisos siguen igual (ningun caller se entera):
--
--   SELECT p.oid::regprocedure AS firma, p.prosecdef, array_to_string(p.proacl,' | ') AS acl
--     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname='public'
--      AND p.proname IN ('fn_crear_extraccion_con_movimiento',
--                        'fn_transferir_inventario_entre_layouts');
--
-- 5. Ensayo funcional: ver 09_tests_fase1.sql, bloque B.
