-- ============================================================================
-- 08 · Fase 1 · Ajuste de inventario por presentacion
-- ============================================================================
-- Plan: docs/PLAN_PRESENTACIONES_INVENTARIO.md  (Fase 1; el conteo mixto
--       completo es Fase 5, aqui solo se arregla el ajuste de UNA presentacion)
-- Proyecto Supabase: vsieeihstajlrdvpuooh
-- Aplicar en: SQL Editor del dashboard. Idempotente (CREATE OR REPLACE).
-- Depende de: 01, 02, 03, 04 aplicados.
--
-- REEMPLAZA UNA FUNCION VIVA: public.fn_insertar_ajuste_inventario2
-- (prod: 2780 chars, 124 lineas). Se partio del pg_get_functiondef vivo; el
-- repo no tiene copia de esta funcion.
--
-- No hace falta tocar fn_admin_caja_ajuste_inventario_offline: solo delega en
-- esta con parametros nombrados y guarda la idempotencia. Hereda el arreglo.
--
--
-- LOS TRES DEFECTOS QUE SE ARREGLAN
-- ---------------------------------
-- 1. CONFIA EN cantidad_anterior QUE MANDA EL CLIENTE.  <- el grave
--    Codigo actual: `v_diferencia := p_cantidad_nueva - p_cantidad_anterior;` y
--    luego inserta en el ledger `cantidad_inicial = p_cantidad_anterior`,
--    `cantidad_final = p_cantidad_nueva`, sin mirar el saldo real.
--    Medido en produccion: de las 3.235 filas de ajuste del ledger, 202 tienen
--    un cantidad_inicial que NO coincide con el cantidad_final del movimiento
--    anterior de esa misma (producto, ubicacion, presentacion). Son saltos en
--    la cadena de saldos: alguien conto con la pantalla desactualizada y el
--    ajuste piso el saldo real. El saldo no se vuelve negativo, pero se pierde
--    la diferencia sin dejar rastro de cuanta era.
--    Ahora el saldo previo se LEE de la base con fn_stock_saldos_presentacion.
--    Si lo declarado por el cliente difiere, se deja constancia en las
--    observaciones y en la respuesta (campos 'saldo_declarado' y 'desfase'),
--    pero manda el saldo real.
--
-- 2. NO VALIDA id_presentacion Y ACEPTA NULL.
--    El parametro es BIGINT sin NOT NULL y el cliente Dart lo declara
--    explicitamente nullable:
--      ventiq_admin_app/lib/services/inventory_service.dart:2210
--      required int? idPresentacion, // Make nullable to handle "Sin presentación"
--    Hoy en el ledger de ajustes no hay ninguna fila con presentacion NULL, o
--    sea que la ruta existe pero no se ha disparado. Con stock mixto una fila
--    asi seria invisible para todo desglose. Ahora se resuelve la base si no
--    viene, y se rechaza el id de otro producto o el del catalogo.
--
-- 3. ESCRIBE UNA FILA DE LEDGER AUNQUE NO HAYA CAMBIO.
--    Con diferencia 0 insertaba un movimiento N -> N que solo ensucia el
--    kardex. Ahora no se escribe nada.
--
--
-- SOBRE EL REBALANCEO EN ESTE ARCHIVO (leer antes de asumir)
-- ---------------------------------------------------------
-- El plan dice, como decision cerrada: "Ajuste de una sola presentacion: el
-- usuario baja solo unidades y no hay sueltas suficientes. Ahi si se abren
-- cajas para cubrir el delta".
--
-- Verificado en el ensayo: en ESTA RPC ese caso no puede ocurrir. La semantica
-- del parametro es "cantidad absoluta nueva", no "delta". Como
-- p_cantidad_nueva >= 0 (validado) y la diferencia se calcula contra el saldo
-- real leido, un descuento vale como maximo el saldo propio:
--
--     diferencia = p_cantidad_nueva - saldo_real
--     si diferencia < 0  =>  |diferencia| = saldo_real - p_cantidad_nueva
--                                        <= saldo_real
--
-- O sea que fn_descontar_con_rebalanceo siempre devuelve estrategia 'ninguna'
-- aqui. Se usa igual, por dos razones concretas y no por adorno:
--   - escribe el movimiento con el mismo criterio de lectura de saldo (id DESC)
--     que el resto del sistema, en vez de duplicar el INSERT a mano;
--   - si en la Fase 5 el conteo mixto pasa a mandar deltas en vez de absolutos,
--     el rebalanceo ya esta enganchado y no hay que volver a tocar esto.
--
-- La decision del plan SI aplica al egreso, y ahi ya esta cubierta: el archivo
-- 07 la ejerce de verdad (extraer 1 unidad con 4 cajas y 0 sueltas abre una
-- caja). No es que este archivo la implemente a medias: es que por esta puerta
-- no entra ese caso.
--
--
-- LO QUE NO CAMBIA
-- ----------------
-- Firma identica (9 parametros en el mismo orden), asi que ni el Dart ni
-- fn_admin_caja_ajuste_inventario_offline necesitan cambios. Se conservan: la
-- operacion en app_dat_operaciones, el estado 2 con el comentario 'Ajuste de
-- inventario completado', la fila en app_dat_ajuste_inventario, origen_cambio 3
-- y las claves de respuesta status / message / id_operacion / id_ajuste /
-- diferencia. Se rechaza igual p_cantidad_nueva negativa.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_insertar_ajuste_inventario2(
  p_id_producto        BIGINT,
  p_id_ubicacion       BIGINT,
  p_id_presentacion    BIGINT,
  p_cantidad_anterior  NUMERIC,
  p_cantidad_nueva     NUMERIC,
  p_motivo             TEXT,
  p_observaciones      TEXT,
  p_uuid_usuario       UUID,
  p_id_tipo_operacion  BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_id_operacion    BIGINT;
  v_id_ajuste       BIGINT;
  v_diferencia      NUMERIC;
  v_id_tienda       BIGINT;
  -- NUEVO
  v_id_presentacion BIGINT := p_id_presentacion;
  v_saldo_real      NUMERIC;
  v_desfase         BOOLEAN := false;
  v_observaciones   TEXT;
  v_movimiento      JSONB;
  v_err_message     TEXT;
BEGIN
  -- Obtener id_tienda del producto
  SELECT id_tienda
  INTO v_id_tienda
  FROM app_dat_producto
  WHERE id = p_id_producto;

  -- Validar parámetros
  IF p_id_producto IS NULL OR p_id_ubicacion IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'Parámetros requeridos faltantes: id_producto, id_ubicacion'
    );
  END IF;

  IF p_cantidad_nueva IS NULL OR p_cantidad_nueva < 0 THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'La cantidad nueva no puede ser negativa'
    );
  END IF;

  -- ── NUEVO (Fase 1): resolver y validar la presentacion ───────────────────
  -- El cliente Dart manda este parametro como nullable ("Sin presentación").
  -- Sin presentacion la fila del ledger no aparece en ningun desglose mixto.
  IF v_id_presentacion IS NULL THEN
    SELECT c.id_presentacion
    INTO v_id_presentacion
    FROM public.fn_presentaciones_producto(p_id_producto) c
    WHERE c.es_base
    LIMIT 1;

    IF v_id_presentacion IS NULL THEN
      RETURN jsonb_build_object(
        'status',  'error',
        'message', format(
          'El producto %s no tiene ninguna presentacion configurada en app_dat_producto_presentacion',
          p_id_producto)
      );
    END IF;
  END IF;

  BEGIN
    PERFORM public.fn_validar_id_presentacion(p_id_producto, v_id_presentacion);
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err_message = MESSAGE_TEXT;
      RETURN jsonb_build_object(
        'status',          'error',
        'message',         v_err_message,
        'id_presentacion', v_id_presentacion
      );
  END;

  -- ── NUEVO (Fase 1): el saldo previo se LEE, no se cree ───────────────────
  -- Con `id DESC`, el mismo criterio que el resto del sistema.
  SELECT COALESCE(SUM(s.saldo), 0)
  INTO v_saldo_real
  FROM public.fn_stock_saldos_presentacion(
         p_id_producto, NULL, p_id_ubicacion, true) s
  WHERE s.id_presentacion = v_id_presentacion;

  v_diferencia := p_cantidad_nueva - v_saldo_real;

  -- Si el cliente conto contra una pantalla desactualizada, queda registrado.
  IF p_cantidad_anterior IS NOT NULL AND p_cantidad_anterior <> v_saldo_real THEN
    v_desfase := true;
  END IF;

  v_observaciones := COALESCE(p_observaciones, '');
  IF v_desfase THEN
    v_observaciones := v_observaciones || format(
      ' [saldo declarado %s, saldo real %s]', p_cantidad_anterior, v_saldo_real);
  END IF;

  -- PASO 1: Crear la operación principal
  INSERT INTO app_dat_operaciones (
    id_tipo_operacion,
    uuid,
    id_tienda,
    observaciones,
    created_at
  ) VALUES (
    p_id_tipo_operacion,
    p_uuid_usuario,
    v_id_tienda,
    v_observaciones,
    NOW()
  ) RETURNING id INTO v_id_operacion;

  -- PASO 2: Crear estado inicial (Completada = 2)
  INSERT INTO app_dat_estado_operacion (
    id_operacion,
    estado,
    uuid,
    created_at,
    comentario
  ) VALUES (
    v_id_operacion,
    2,
    p_uuid_usuario,
    NOW(),
    'Ajuste de inventario completado'
  );

  -- PASO 3: Insertar en tabla de ajuste CON id_operacion
  -- cantidad_anterior = el saldo REAL leido, no el que declaro el cliente.
  INSERT INTO app_dat_ajuste_inventario (
    id_producto,
    id_variante,
    id_ubicacion,
    cantidad_anterior,
    cantidad_nueva,
    diferencia,
    id_operacion,
    uuid_usuario,
    created_at
  ) VALUES (
    p_id_producto,
    NULL,
    p_id_ubicacion,
    v_saldo_real,
    p_cantidad_nueva,
    v_diferencia,
    v_id_operacion,
    p_uuid_usuario,
    NOW()
  ) RETURNING id INTO v_id_ajuste;

  -- ── PASO 4 (Fase 1): el movimiento lo escriben los helpers ───────────────
  -- Antes se hacia un INSERT directo con cantidad_inicial = lo declarado por el
  -- cliente. Eso rompia la cadena de saldos (202 casos en produccion) y podia
  -- dejar negativos.
  IF v_diferencia > 0 THEN
    v_movimiento := public.fn_ingresar_presentacion(
      p_id_producto     := p_id_producto,
      p_id_ubicacion    := p_id_ubicacion,
      p_id_presentacion := v_id_presentacion,
      p_cantidad        := v_diferencia,
      p_origen_cambio   := 3                      -- 3 = ajuste
    );

  ELSIF v_diferencia < 0 THEN
    -- |v_diferencia| <= v_saldo_real siempre (ver la nota del encabezado), asi
    -- que aqui el helper no abre nada: devuelve estrategia 'ninguna'. Se usa
    -- por el criterio de lectura de saldo unificado y porque deja el
    -- rebalanceo listo si la Fase 5 pasa a mandar deltas.
    v_movimiento := public.fn_descontar_con_rebalanceo(
      p_id_producto     := p_id_producto,
      p_id_ubicacion    := p_id_ubicacion,
      p_id_presentacion := v_id_presentacion,
      p_cantidad        := -v_diferencia,
      p_origen_cambio   := 3,
      p_id_operacion    := v_id_operacion,
      p_uuid            := p_uuid_usuario,
      p_motivo          := COALESCE(NULLIF(TRIM(p_motivo), ''), 'ajuste')
    );

  ELSE
    -- Sin diferencia: no se escribe ledger. Antes insertaba una fila N -> N que
    -- solo ensuciaba el kardex.
    v_movimiento := jsonb_build_object('status', 'success', 'sin_cambios', true);
  END IF;

  IF COALESCE(v_movimiento->>'status', '') <> 'success' THEN
    -- RAISE para deshacer la operacion y la fila de ajuste ya insertadas.
    RAISE EXCEPTION '%', COALESCE(
      v_movimiento->>'message',
      'No se pudo aplicar el ajuste al inventario')
      USING ERRCODE = 'P0001';
  END IF;

  -- Retornar éxito
  RETURN jsonb_build_object(
    'status',          'success',
    'message',         'Ajuste de inventario registrado correctamente',
    'id_operacion',    v_id_operacion,
    'id_ajuste',       v_id_ajuste,
    'diferencia',      v_diferencia,
    'id_presentacion', v_id_presentacion,
    'saldo_anterior',  v_saldo_real,
    'saldo_nuevo',     p_cantidad_nueva,
    'saldo_declarado', p_cantidad_anterior,
    'desfase',         v_desfase,
    'conversiones',    COALESCE(v_movimiento->'conversiones', '[]'::JSONB)
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'status', 'error',
    'message', 'Error al procesar ajuste: ' || SQLERRM,
    'error_detail', SQLSTATE
  );
END;
$$;

COMMENT ON FUNCTION public.fn_insertar_ajuste_inventario2(
  BIGINT, BIGINT, BIGINT, NUMERIC, NUMERIC, TEXT, TEXT, UUID, BIGINT) IS
  'Ajusta el inventario de UNA presentacion en una ubicacion. Fase 1 de '
  'presentaciones: lee el saldo previo real (ignora el declarado por el cliente '
  'y lo anota si difiere), valida id_presentacion, y aplica la diferencia con '
  'fn_ingresar_presentacion / fn_descontar_con_rebalanceo. El conteo mixto '
  'completo de varias presentaciones a la vez es la Fase 5.';


-- ============================================================================
-- ENSAYO YA REALIZADO (BEGIN/ROLLBACK contra datos reales, 2026-08-26)
-- ============================================================================
-- Producto con cadena Caja 12 / Unidad 1, ubicacion 74, tipo de operacion de
-- ajuste = 3. Resultados:
--
--   A1  subir unidades 0 -> 5  con 4 cajas presentes: success, diferencia +5,
--       queda "4 Cajas + 5 Unidades".
--   A2  bajar unidades 5 -> 2: diferencia -3, sin conversiones.
--   A3  DECLARAR 99 cuando el saldo real es 2, pidiendo 3: manda el real.
--       diferencia = +1 (no -96), saldo_anterior = 2, saldo_declarado = 99,
--       desfase = true, y la observacion de la operacion quedo como
--       "test F1 ajuste desfase [saldo declarado 99, saldo real 2]".
--       Con el codigo viejo esto habria escrito una fila 99 -> 3 y roto la
--       cadena de saldos, que es el bug de las 202 filas historicas.
--   A4  bajar unidades 3 -> 0: queda "4 Cajas".
--   A5  diferencia 0 (cajas 4 -> 4): status success y el ledger NO crece
--       (5 filas antes, 5 despues).
--   A6  bajar cajas 4 -> 0 con 0 sueltas: success, queda "Sin stock".
--   A9  id_presentacion NULL: resuelve la base (Unidad) y aplica sobre ella.
--   A10 presentacion de otro producto -> error con el mensaje que lo explica.
--   A11 id del catalogo (3 = Caja) -> error que distingue el caso.
--   A12 integridad final: 0 saldos negativos, 0 filas con presentacion NULL,
--       0 ajustes que rompan la cadena de saldos.
--
-- Hallazgo del ensayo, ya reflejado arriba: el caso A8 que se escribio para
-- provocar un rebalanceo ("bajar cajas a 0 teniendo solo 5 unidades") no puede
-- fallar, porque el saldo de cajas ya era 0 y la diferencia resulto 0. Confirma
-- por la via empirica lo que dice la nota del encabezado: con semantica de
-- cantidad absoluta, |diferencia| nunca supera el saldo propio.


-- ============================================================================
-- VERIFICACION (correr despues de aplicar; no modifica datos)
-- ============================================================================
-- 1. Los cambios estan y lo de antes se conserva:
--
--   SELECT
--     pg_get_functiondef('public.fn_insertar_ajuste_inventario2'::regproc)
--       ILIKE '%fn_descontar_con_rebalanceo%'         AS usa_rebalanceo,
--     pg_get_functiondef('public.fn_insertar_ajuste_inventario2'::regproc)
--       ILIKE '%fn_ingresar_presentacion%'            AS usa_ingreso,
--     pg_get_functiondef('public.fn_insertar_ajuste_inventario2'::regproc)
--       ILIKE '%fn_validar_id_presentacion%'          AS valida_presentacion,
--     pg_get_functiondef('public.fn_insertar_ajuste_inventario2'::regproc)
--       NOT ILIKE '%p_cantidad_nueva - p_cantidad_anterior%' AS no_confia_en_cliente,
--     pg_get_functiondef('public.fn_insertar_ajuste_inventario2'::regproc)
--       ILIKE '%Ajuste de inventario completado%'     AS conserva_estado_2;
--   -- esperado: todo true
--
-- 2. La firma no cambio (el Dart y el wrapper offline no se enteran):
--
--   SELECT p.oid::regprocedure AS firma, array_to_string(p.proacl,' | ') AS acl
--     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname='public' AND p.proname='fn_insertar_ajuste_inventario2';
--   -- esperado: una sola fila con 9 parametros, acl con anon/authenticated/service_role
--
-- 3. El wrapper offline sigue delegando (no hubo que tocarlo):
--
--   SELECT pg_get_functiondef('public.fn_admin_caja_ajuste_inventario_offline'::regproc)
--            ILIKE '%fn_insertar_ajuste_inventario2%' AS delega_ok;
--   -- esperado: true
--
-- 4. De aqui en adelante NO deberian aparecer ajustes nuevos que rompan la
--    cadena de saldos. Los 202 historicos se quedan como estan (no se migra
--    nada, igual que el resto del plan):
--
--   SELECT count(*) AS ajustes_con_inicial_desfasado
--     FROM app_dat_inventario_productos i2
--    WHERE i2.origen_cambio = 3
--      AND i2.created_at > '2026-08-26'
--      AND i2.cantidad_inicial <> COALESCE((
--            SELECT i3.cantidad_final FROM app_dat_inventario_productos i3
--             WHERE i3.id_producto = i2.id_producto
--               AND i3.id_ubicacion IS NOT DISTINCT FROM i2.id_ubicacion
--               AND i3.id_presentacion IS NOT DISTINCT FROM i2.id_presentacion
--               AND i3.id < i2.id
--             ORDER BY i3.id DESC LIMIT 1), 0);
--   -- esperado: 0
