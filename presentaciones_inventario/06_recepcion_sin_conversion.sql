-- ============================================================================
-- 06 · Fase 1 · Recepcion: validar presentacion y dejar de recalcular el saldo
-- ============================================================================
-- Plan: docs/PLAN_PRESENTACIONES_INVENTARIO.md  (Fase 1)
-- Proyecto Supabase: vsieeihstajlrdvpuooh
-- Aplicar en: SQL Editor del dashboard. Idempotente (CREATE OR REPLACE).
-- Depende de: 01, 02, 03 aplicados.
--
-- REEMPLAZA UNA FUNCION VIVA: fn_registrar_recepcion_con_inventario.
-- Verificado antes de escribir: el archivo del repo
-- SQL_OPTIMIZATION/fn_registrar_recepcion_con_inventario.sql coincide byte a
-- byte con produccion (length(prosrc) = 8996, 273 lineas, ambos con CRLF), asi
-- que este archivo se basa en el codigo real que esta corriendo.
--
--
-- QUE CAMBIA
-- ----------
-- La recepcion YA NO convertia a base (eso lo hacia el cliente Dart, ver Fase 1
-- parte Dart). Aqui se corrigen dos cosas distintas:
--
-- 1. VALIDACION DEL id_presentacion (nueva).
--    Hoy la funcion inserta el id_presentacion que llega en el JSON sin
--    comprobar nada. Datos reales en produccion:
--      - 61 filas de app_dat_recepcion_productos con id_presentacion NULL
--      - 21 filas con un id_presentacion que pertenece a OTRO producto
--    (las mas recientes de mayo 2026; ninguna en los ultimos 30 dias, o sea que
--    el bug ya no se dispara seguido, pero la puerta sigue abierta).
--    Con stock mixto una presentacion ajena escribe un saldo en una fila que no
--    corresponde y el desglose queda corrupto para siempre. Ahora se valida con
--    fn_validar_id_presentacion, que ademas distingue el error clasico de mandar
--    app_nom_presentacion.id.
--
--    Si el JSON no trae id_presentacion, se resuelve la presentacion base del
--    producto en vez de insertar NULL. Antes quedaba NULL y esa fila del ledger
--    no aparecia en ningun desglose.
--
-- 2. EL SALDO SE OBTIENE CON EL MISMO CRITERIO QUE TODO LO DEMAS.
--    El codigo actual hace:
--        ORDER BY created_at DESC LIMIT 1
--    Dos movimientos del mismo producto/presentacion/ubicacion en el mismo
--    NOW() (pasa dentro de una misma transaccion: la funcion usa NOW(), que es
--    el inicio de la transaccion, no clock_timestamp()) empatan, y el desempate
--    queda al azar del plan de ejecucion. Con recepcion mixta de varias lineas
--    del mismo producto es un empate garantizado.
--    Ahora se delega en fn_ingresar_presentacion, que lee el saldo por
--    (ubicacion, variante, opcion, presentacion) con `ORDER BY id DESC` — el
--    criterio que ya usan fn_stock_producto_almacen_detalle y los helpers de la
--    Fase 0. Una sola fuente de verdad.
--
--
-- LO QUE NO CAMBIA
-- ----------------
-- Se conserva TODO lo demas tal cual: las 4 validaciones de entrada con sus
-- codigos V0001..V0005, el orden de los INSERT, app_dat_operacion_recepcion,
-- el estado inicial 1, el recalculo de monto_total cuando p_monto_total es
-- NULL, el bloque EXCEPTION con GET STACKED DIAGNOSTICS y los campos 'etapa' e
-- 'id_operacion_parcial'. La firma es identica: el cliente Dart no cambia por
-- este archivo.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_registrar_recepcion_con_inventario(
  p_entregado_por    TEXT,
  p_id_tienda        BIGINT,
  p_monto_total      NUMERIC  DEFAULT NULL,
  p_motivo           INTEGER  DEFAULT NULL,
  p_observaciones    TEXT     DEFAULT NULL,
  p_productos        JSONB    DEFAULT '[]'::JSONB,
  p_recibido_por     TEXT     DEFAULT NULL,
  p_uuid             UUID     DEFAULT NULL,
  p_moneda_factura   TEXT     DEFAULT 'USD'
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_id_operacion          BIGINT;
  v_id_tipo_operacion     BIGINT;
  v_producto_record       JSONB;
  v_cantidad_total        NUMERIC := 0;
  v_tienda_exists         BOOLEAN;
  v_moneda_factura        TEXT;
  -- Por producto
  v_id_recepcion_producto BIGINT;   -- id de app_dat_recepcion_productos
  v_id_producto           BIGINT;
  v_id_variante           BIGINT;
  v_id_opcion_variante    BIGINT;
  v_id_ubicacion          BIGINT;
  v_id_presentacion       BIGINT;
  v_id_proveedor          BIGINT;
  v_cantidad              NUMERIC;
  v_precio_unitario       NUMERIC;
  v_ingreso               JSONB;    -- NUEVO: resultado de fn_ingresar_presentacion
  -- Captura de errores
  v_err_message           TEXT;
  v_err_detail            TEXT;
  v_err_hint              TEXT;
  v_err_context           TEXT;
BEGIN

  -- ── Validación: tienda existe ────────────────────────────────────────────
  SELECT EXISTS(SELECT 1 FROM app_dat_tienda WHERE id = p_id_tienda)
  INTO v_tienda_exists;

  IF NOT v_tienda_exists THEN
    RETURN jsonb_build_object(
      'status',   'error',
      'message',  format('La tienda con ID %s no existe', p_id_tienda),
      'sqlstate', 'V0001',
      'etapa',    'validacion_tienda'
    );
  END IF;

  -- ── Validación: al menos un producto ────────────────────────────────────
  IF p_productos IS NULL OR jsonb_array_length(p_productos) = 0 THEN
    RETURN jsonb_build_object(
      'status',   'error',
      'message',  'Debe incluir al menos un producto',
      'sqlstate', 'V0002',
      'etapa',    'validacion_productos'
    );
  END IF;

  -- ── Validación: moneda ───────────────────────────────────────────────────
  v_moneda_factura := COALESCE(NULLIF(TRIM(p_moneda_factura), ''), 'USD');

  IF v_moneda_factura NOT IN ('USD', 'EUR', 'CUP') THEN
    RETURN jsonb_build_object(
      'status',   'error',
      'message',  format('Moneda no válida: "%s". Use USD, EUR o CUP', v_moneda_factura),
      'sqlstate', 'V0003',
      'etapa',    'validacion_moneda'
    );
  END IF;

  -- ── Validación: motivo → tipo de operación ───────────────────────────────
  SELECT id_tipo_operacion
  INTO v_id_tipo_operacion
  FROM app_nom_motivo_recepcion
  WHERE id = p_motivo::BIGINT;

  IF v_id_tipo_operacion IS NULL THEN
    RETURN jsonb_build_object(
      'status',   'error',
      'message',  format('No se encontró tipo de operación para el motivo %s', p_motivo),
      'sqlstate', 'V0004',
      'etapa',    'validacion_motivo'
    );
  END IF;

  -- ── 1. Operación principal ───────────────────────────────────────────────
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

  -- ── 2. Detalles de recepción ─────────────────────────────────────────────
  INSERT INTO app_dat_operacion_recepcion (
    id_operacion,
    entregado_por,
    recibido_por,
    monto_total,
    observaciones,
    motivo,
    created_at,
    moneda_factura
  ) VALUES (
    v_id_operacion,
    p_entregado_por,
    p_recibido_por,
    p_monto_total,
    p_observaciones,
    p_motivo,
    NOW(),
    v_moneda_factura
  );

  -- ── 3. Productos + movimiento de inventario ──────────────────────────────
  FOR v_producto_record IN SELECT * FROM jsonb_array_elements(p_productos)
  LOOP

    -- Validar campos mínimos del producto
    IF v_producto_record->>'id_producto' IS NULL
    OR v_producto_record->>'cantidad'    IS NULL THEN
      RETURN jsonb_build_object(
        'status',               'error',
        'message',              'Cada producto debe tener id_producto y cantidad',
        'sqlstate',             'V0005',
        'etapa',                'validacion_producto_item',
        'producto_recibido',    v_producto_record,
        'id_operacion_parcial', v_id_operacion
      );
    END IF;

    -- Extraer campos del JSON a variables locales para reutilizar
    v_id_producto        := (v_producto_record->>'id_producto')::BIGINT;
    v_id_variante        := NULLIF(v_producto_record->>'id_variante',        '')::BIGINT;
    v_id_opcion_variante := NULLIF(v_producto_record->>'id_opcion_variante', '')::BIGINT;
    v_id_proveedor       := NULLIF(v_producto_record->>'id_proveedor',       '')::BIGINT;
    v_id_ubicacion       := NULLIF(v_producto_record->>'id_ubicacion',       '')::BIGINT;
    v_id_presentacion    := NULLIF(v_producto_record->>'id_presentacion',    '')::BIGINT;
    v_cantidad           := (v_producto_record->>'cantidad')::NUMERIC;
    v_precio_unitario    := NULLIF(v_producto_record->>'precio_unitario',    '')::NUMERIC;

    -- ── NUEVO (Fase 1): resolver y validar la presentacion ────────────────
    -- Si no viene, se usa la base del producto. Antes se insertaba NULL y esa
    -- fila del ledger quedaba fuera de todo desglose.
    IF v_id_presentacion IS NULL THEN
      SELECT c.id_presentacion
      INTO v_id_presentacion
      FROM public.fn_presentaciones_producto(v_id_producto) c
      WHERE c.es_base
      LIMIT 1;

      IF v_id_presentacion IS NULL THEN
        RETURN jsonb_build_object(
          'status',               'error',
          'message',              format(
            'El producto %s no tiene ninguna presentacion configurada en app_dat_producto_presentacion',
            v_id_producto),
          'sqlstate',             'V0006',
          'etapa',                'resolucion_presentacion',
          'producto_recibido',    v_producto_record,
          'id_operacion_parcial', v_id_operacion
        );
      END IF;
    END IF;

    -- Rechaza id de otro producto y el clasico app_nom_presentacion.id.
    -- fn_validar_id_presentacion lanza excepcion con ERRCODE 22023 y un mensaje
    -- que explica cual de los dos casos fue. Se captura aqui para devolverlo
    -- como error de validacion y no como 'excepcion_no_controlada', que era
    -- confuso: en el ensayo el mensaje era correcto pero la etapa mentia.
    BEGIN
      PERFORM public.fn_validar_id_presentacion(v_id_producto, v_id_presentacion);
    EXCEPTION
      WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_err_message = MESSAGE_TEXT;
        RETURN jsonb_build_object(
          'status',               'error',
          'message',              v_err_message,
          'sqlstate',             'V0008',
          'etapa',                'validacion_presentacion',
          'id_presentacion',      v_id_presentacion,
          'id_producto',          v_id_producto,
          'producto_recibido',    v_producto_record,
          'id_operacion_parcial', v_id_operacion
        );
    END;

    -- 3a. Insertar en app_dat_recepcion_productos y capturar su id
    INSERT INTO app_dat_recepcion_productos (
      id_operacion,
      id_producto,
      id_variante,
      id_opcion_variante,
      id_proveedor,
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
      v_id_proveedor,
      v_id_ubicacion,
      v_id_presentacion,
      v_cantidad,
      v_precio_unitario,
      v_producto_record->>'sku_producto',
      v_producto_record->>'sku_ubicacion',
      NOW()
    ) RETURNING id INTO v_id_recepcion_producto;

    -- ── 3b + 3c (Fase 1): el movimiento lo escribe fn_ingresar_presentacion ─
    -- Antes se leia el saldo con `ORDER BY created_at DESC LIMIT 1` y se hacia
    -- el INSERT aqui mismo. Ese ORDER BY empata cuando hay varias lineas del
    -- mismo producto en la misma recepcion (NOW() es constante en la
    -- transaccion). El helper usa `id DESC`, que es el criterio del resto del
    -- sistema, y NO convierte la cantidad: entra en la presentacion pedida.
    v_ingreso := public.fn_ingresar_presentacion(
      p_id_producto        := v_id_producto,
      p_id_ubicacion       := v_id_ubicacion,
      p_id_presentacion    := v_id_presentacion,
      p_cantidad           := v_cantidad,
      p_origen_cambio      := 1,                      -- 1 = recepcion
      p_id_recepcion       := v_id_recepcion_producto,
      p_id_proveedor       := v_id_proveedor,
      p_id_variante        := v_id_variante,
      p_id_opcion_variante := v_id_opcion_variante,
      p_sku_producto       := v_producto_record->>'sku_producto',
      p_sku_ubicacion      := v_producto_record->>'sku_ubicacion'
    );

    IF COALESCE(v_ingreso->>'status', '') <> 'success' THEN
      RETURN jsonb_build_object(
        'status',               'error',
        'message',              COALESCE(v_ingreso->>'message',
                                         'Error al registrar el movimiento de inventario'),
        'sqlstate',             COALESCE(v_ingreso->>'error_code', 'V0007'),
        'etapa',                'movimiento_inventario',
        'producto_recibido',    v_producto_record,
        'detalle_ingreso',      v_ingreso,
        'id_operacion_parcial', v_id_operacion
      );
    END IF;

    -- Acumular monto total
    v_cantidad_total := v_cantidad_total + (v_cantidad * COALESCE(v_precio_unitario, 0));

  END LOOP;

  -- ── 4. Estado inicial (1 = Pendiente) ───────────────────────────────────
  INSERT INTO app_dat_estado_operacion (
    id_operacion,
    estado,
    uuid,
    created_at
  ) VALUES (
    v_id_operacion,
    1,
    p_uuid,
    NOW()
  );

  -- ── 5. Actualizar monto total si no se proporcionó ───────────────────────
  IF p_monto_total IS NULL THEN
    UPDATE app_dat_operacion_recepcion
    SET monto_total = v_cantidad_total
    WHERE id_operacion = v_id_operacion;
  END IF;

  -- ── Respuesta exitosa ────────────────────────────────────────────────────
  RETURN jsonb_build_object(
    'status',           'success',
    'id_operacion',     v_id_operacion,
    'total_productos',  jsonb_array_length(p_productos),
    'monto_total',      COALESCE(p_monto_total, v_cantidad_total),
    'moneda_utilizada', v_moneda_factura,
    'mensaje',          'Recepción registrada correctamente con movimientos de inventario'
  );

EXCEPTION
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      v_err_message = MESSAGE_TEXT,
      v_err_detail  = PG_EXCEPTION_DETAIL,
      v_err_hint    = PG_EXCEPTION_HINT,
      v_err_context = PG_EXCEPTION_CONTEXT;

    RETURN jsonb_build_object(
      'status',               'error',
      'message',              v_err_message,
      'detail',               COALESCE(v_err_detail,  ''),
      'hint',                 COALESCE(v_err_hint,    ''),
      'context',              COALESCE(v_err_context, ''),
      'sqlstate',             SQLSTATE,
      'etapa',                'excepcion_no_controlada',
      'id_operacion_parcial', v_id_operacion
    );
END;
$$;

COMMENT ON FUNCTION public.fn_registrar_recepcion_con_inventario(
  TEXT, BIGINT, NUMERIC, INTEGER, TEXT, JSONB, TEXT, UUID, TEXT) IS
  'Registra una recepcion con sus movimientos de inventario. Fase 1 de '
  'presentaciones: valida id_presentacion (rechaza el id del catalogo y el de '
  'otro producto), resuelve la base si no viene, y delega el movimiento en '
  'fn_ingresar_presentacion para no convertir a base y no empatar por created_at.';


-- ============================================================================
-- ENSAYO YA REALIZADO (BEGIN/ROLLBACK contra datos reales, 2026-08-26)
-- ============================================================================
-- Producto de prueba con cadena Bulto 120 / Caja 12 / Unidad 1, tienda 55,
-- ubicaciones 74, 75 y 76. Resultados:
--
--   T1 recepcion mixta 4 cajas + 4 unidades  -> success, "4 Cajas + 4 Unidades",
--      equivalente 52. Dos filas en el ledger, cada una con SU presentacion y
--      ligada a su fila de app_dat_recepcion_productos. monto_total 520.
--   T2 TRES lineas de la MISMA presentacion en una sola recepcion (2+3+4 cajas)
--      -> saldos encadenados 0->2, 2->5, 5->9. Es el caso que el
--      `ORDER BY created_at DESC` viejo no podia resolver: los tres movimientos
--      comparten NOW(). Antes el resultado dependia del plan de ejecucion.
--   T3 linea SIN id_presentacion -> resuelve la base: "7 Unidades", y CERO
--      filas con id_presentacion NULL ni en recepcion ni en el ledger.
--   T4 id_presentacion de otro producto -> error, saldos intactos.
--   T5 id del catalogo (3 = Caja) -> error con el mensaje que lo explica.
--   T6 despues de los dos errores: ubicacion 74 sigue en "4 Cajas + 4 Unidades",
--      0 saldos negativos, montos 520 / 1080 / 70 correctos.
--   T7 las 5 validaciones originales siguen devolviendo V0001..V0005.
--
-- El ensayo detecto que T4 y T5 devolvian etapa 'excepcion_no_controlada'
-- (el mensaje era correcto pero la etapa mentia). De ahi el BEGIN/EXCEPTION
-- alrededor del PERFORM, que ahora devuelve etapa 'validacion_presentacion'
-- con sqlstate V0008.


-- ============================================================================
-- VERIFICACION (correr despues de aplicar; no modifica datos)
-- ============================================================================
-- OJO: no uses `pg_get_functiondef(...) ILIKE '%ORDER BY created_at DESC%'` a
-- secas. Este archivo DOCUMENTA en comentarios el patron viejo que elimino, asi
-- que ese ILIKE encuentra el comentario y da un falso negativo. Hay que filtrar
-- las lineas de comentario antes de buscar. Comprobado en produccion: la
-- consulta ingenua decia que el ORDER BY seguia ahi cuando ya no estaba.
--
-- 1. La funcion quedo con los cambios y conserva lo de antes:
--
--   WITH limpio AS (
--     SELECT array_to_string(array(
--              SELECT l FROM regexp_split_to_table(p.prosrc, E'\n') l
--               WHERE btrim(l) NOT LIKE '--%'), E'\n') AS codigo
--       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--      WHERE n.nspname = 'public'
--        AND p.proname = 'fn_registrar_recepcion_con_inventario')
--   SELECT codigo ILIKE '%fn_ingresar_presentacion%'      AS usa_helper,
--          codigo ILIKE '%fn_validar_id_presentacion%'    AS valida_presentacion,
--          codigo ILIKE '%V0008%'                         AS etapa_validacion_pres,
--          codigo NOT ILIKE '%ORDER BY created_at DESC%'  AS ya_no_ordena_por_fecha,
--          codigo ILIKE '%GET STACKED DIAGNOSTICS%'       AS conserva_diagnostics,
--          codigo ILIKE '%V0005%'                         AS conserva_validaciones
--     FROM limpio;
--   -- esperado: todo true
--   -- verificado en produccion 2026-08-26: todo true
--
-- 2. La firma y los permisos no cambiaron (el cliente Dart no se entera):
--
--   SELECT p.oid::regprocedure AS firma, array_to_string(p.proacl, ' | ') AS acl
--     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname = 'public'
--      AND p.proname = 'fn_registrar_recepcion_con_inventario';
--   -- esperado: una sola fila, con anon / authenticated / service_role en el acl
--
-- 3. Ensayo funcional completo (crea, verifica y deshace): ver 09_tests_fase1.sql
