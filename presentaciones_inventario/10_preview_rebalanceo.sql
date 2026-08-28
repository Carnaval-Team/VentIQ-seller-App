-- ============================================================================
-- 10 · fn_preview_rebalanceo · simular una conversion SIN escribir nada
-- ============================================================================
-- Plan: docs/PLAN_PRESENTACIONES_INVENTARIO.md
--       (habilita la decision 12: preguntar antes de abrir empaque en el TPV)
-- Proyecto Supabase: vsieeihstajlrdvpuooh
-- Aplicar en: SQL Editor del dashboard. Idempotente (CREATE OR REPLACE).
-- Depende de: 01, 02, 03 aplicados.
--
-- NO reemplaza ninguna funcion viva. Es una funcion NUEVA y de SOLO LECTURA.
--
--
-- POR QUE HACE FALTA
-- ------------------
-- La decision cerrada del plan es que el rebalanceo automatico se queda en el
-- SQL y que la UI del TPV pregunte antes:
--
--     Faltan 4 Unidades.
--     ¿Abrir 1 Caja (12 Unidades)? Quedarán 8 sueltas.
--     [Abrir]  [Cancelar]  [ ] No volver a preguntar
--
-- Ese dialogo es imposible con lo que hay hoy. `fn_rebalancear_presentaciones`
-- decide y EJECUTA en la misma llamada: registra la conversion, mueve los
-- saldos y recien entonces devuelve el detalle. Para poder preguntar, la app
-- necesita saber ANTES:
--   - si el saldo propio alcanza (entonces no se pregunta nada),
--   - que se abriria o empaquetaria exactamente,
--   - con cuantas sueltas queda el estante despues,
--   - y si no alcanza, cuanto es el maximo que se puede servir.
--
-- Esta funcion responde eso sin tocar una sola fila. Es el mismo algoritmo de
-- `fn_rebalancear_presentaciones` con los INSERT quitados: se cargan la cadena y
-- los saldos, se simula sobre arrays en memoria y se devuelve el plan.
--
-- Deliberadamente NO se refactorizo `fn_rebalancear_presentaciones` para que
-- llame a esta. Duplicar ~80 lineas de simulacion es peor que el riesgo de
-- tocar una funcion que ya esta viva y con 9 tests verdes encima; y si mañana
-- divergen, el que manda es el que escribe. Si esto se vuelve un problema, el
-- paso correcto es que la que escribe consuma el plan de la que simula, con su
-- propio ensayo.
--
--
-- CONTRATO DE RESPUESTA
-- ---------------------
-- {
--   "status": "success" | "error",
--   "necesita_conversion": bool,        -- false = el saldo propio alcanza
--   "estrategia": "ninguna" | "abrir" | "empaquetar" | "imposible",
--   "presentacion_nombre": "Unidad",
--   "saldo_propio": 0,                  -- lo que hay hoy de la presentacion pedida
--   "cantidad_solicitada": 4,
--   "faltante": 4,
--   "conversiones": [ { tipo, origen_nombre, destino_nombre,
--                       cantidad_origen, cantidad_destino } ],
--   "saldo_despues_conversion": 12,     -- saldo de la pedida tras convertir
--   "sobrante_tras_consumo": 8,         -- lo que queda si se consume lo pedido
--   "maximo_convertible": 47.000,
--   "mensaje_usuario": "Faltan 4 Unidades. ¿Abrir 1 Caja (12 Unidades)? Quedarán 8 sueltas.",
--   "equivalente_base": 47
-- }
--
-- `mensaje_usuario` viene armado desde el SQL a proposito: el plural correcto
-- ("1 Caja" / "2 Cajas") lo sabe `fn_plural_presentacion`, que ya existe y ya
-- maneja las irregularidades del nomenclador. Duplicar esa logica en Dart es
-- pedir que se desincronice.
--
-- El TPV puede ignorar `mensaje_usuario` y armar el suyo con los campos
-- estructurados; ambas cosas estan soportadas.
--
--
-- COMO LO USA EL TPV (flujo previsto para la Fase 4)
-- -------------------------------------------------
--   1. El usuario agrega N de una presentacion al carrito.
--   2. La app llama a fn_preview_rebalanceo.
--   3. necesita_conversion = false  -> seguir sin molestar.
--      estrategia = 'imposible'     -> avisar "solo hay X" y no dejar agregar.
--      estrategia = 'abrir'/'empaquetar' -> mostrar el dialogo con
--                                    mensaje_usuario, salvo que el usuario haya
--                                    marcado "no volver a preguntar".
--   4. Si acepta, se sigue con la venta normal: el rebalanceo real lo hace
--      fn_descontar_con_rebalanceo dentro de la RPC de venta. La preview NO
--      reserva nada.
--
-- LIMITACION HONESTA: entre la preview y la venta puede entrar otra caja
-- registradora y mover el saldo, asi que el plan mostrado puede quedar viejo.
-- No es una reserva ni un lock. La escritura real vuelve a calcular y puede
-- fallar con 'Stock insuficiente' aunque la preview dijera que si. El dialogo
-- es una cortesia para el cajero, no una garantia transaccional; tratarlo como
-- garantia seria el error.
-- ============================================================================

-- ============================================================================
-- 10.0 · fn_fmt_cantidad · numero legible para mensajes
-- ============================================================================
-- `to_char(1, 'FM9999999990.999')` devuelve "1." con el punto colgando, asi que
-- los mensajes salian como "Faltan 1. Unidad". Es el mismo defecto que ya se
-- arreglo en 02_helpers_lectura_mixta.sql con un rtrim; aqui se encapsula para
-- no repetir la expresion en cada format() y para que la Fase 2 la reuse.
--
--   fn_fmt_cantidad(1)      -> '1'
--   fn_fmt_cantidad(12.000) -> '12'
--   fn_fmt_cantidad(1.5)    -> '1.5'
--   fn_fmt_cantidad(0.916)  -> '0.916'

CREATE OR REPLACE FUNCTION public.fn_fmt_cantidad(p_cantidad NUMERIC)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT rtrim(trim(to_char(COALESCE(p_cantidad, 0), 'FM9999999990.999')), '.');
$$;

COMMENT ON FUNCTION public.fn_fmt_cantidad(NUMERIC) IS
  'Formatea una cantidad para mostrar: sin ceros de relleno y sin el punto '
  'colgante que deja to_char con FM cuando el numero es entero.';

GRANT EXECUTE ON FUNCTION public.fn_fmt_cantidad(NUMERIC)
  TO anon, authenticated, service_role;


-- ============================================================================
-- 10.1 · fn_preview_rebalanceo
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_preview_rebalanceo(
  p_id_producto        BIGINT,
  p_id_ubicacion       BIGINT,
  p_id_presentacion    BIGINT,
  p_cantidad           NUMERIC,
  p_id_variante        BIGINT DEFAULT NULL,
  p_id_opcion_variante BIGINT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_n            INTEGER;
  v_t            INTEGER;
  v_ids          BIGINT[]  := '{}';
  v_nombres      TEXT[]    := '{}';
  v_factor_rel   NUMERIC[] := '{}';
  v_fhijo        NUMERIC[] := '{}';
  v_s            NUMERIC[] := '{}';
  v_abrir        NUMERIC[] := '{}';
  v_req          NUMERIC[] := '{}';
  v_falta        NUMERIC[] := '{}';
  v_consumo      NUMERIC[] := '{}';
  v_i            INTEGER;
  v_j            INTEGER;
  v_nivel_top    INTEGER;
  v_nivel_deep   INTEGER;
  v_viable       BOOLEAN;
  v_conversiones JSONB := '[]'::JSONB;
  v_prod_hijos   NUMERIC;
  v_consumo_hijos NUMERIC;
  v_equiv        NUMERIC;
  v_estrategia   TEXT := 'ninguna';
  v_saldo_propio NUMERIC;
  v_faltante     NUMERIC;
  v_max_conv     NUMERIC;
  v_sobrante     NUMERIC;
  v_mensaje      TEXT;
  v_primera      JSONB;
  v_ultima       JSONB;
  v_pasos        INTEGER;
  v_err_message  TEXT;
  r              RECORD;
BEGIN
  IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
    RETURN jsonb_build_object(
      'status',     'error',
      'message',    'La cantidad debe ser mayor que cero',
      'error_code', 'INVALID_QUANTITY');
  END IF;

  IF p_id_ubicacion IS NULL THEN
    RETURN jsonb_build_object(
      'status',     'error',
      'message',    'Se necesita una ubicacion concreta para simular el rebalanceo',
      'error_code', 'MISSING_LOCATION');
  END IF;

  -- Mismo contrato de IDs que las escrituras: si viene el id del catalogo o el
  -- de otro producto, se devuelve el error explicativo en vez de un resultado
  -- silenciosamente equivocado.
  BEGIN
    PERFORM public.fn_validar_id_presentacion(p_id_producto, p_id_presentacion);
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err_message = MESSAGE_TEXT;
      RETURN jsonb_build_object(
        'status',          'error',
        'message',         v_err_message,
        'error_code',      'INVALID_PRESENTATION',
        'id_presentacion', p_id_presentacion);
  END;

  -- ── Cadena de presentaciones a arrays indexados por nivel ─────────────────
  FOR r IN
    SELECT c.nivel, c.id_presentacion, c.nombre, c.factor_rel, c.factor_hijo
      FROM public.fn_presentaciones_producto(p_id_producto) c
     ORDER BY c.nivel
  LOOP
    v_ids[r.nivel]        := r.id_presentacion;
    v_nombres[r.nivel]    := r.nombre;
    v_factor_rel[r.nivel] := r.factor_rel;
    v_fhijo[r.nivel]      := r.factor_hijo;
    v_s[r.nivel]          := 0;
    IF r.id_presentacion = p_id_presentacion THEN
      v_t := r.nivel;
    END IF;
  END LOOP;

  v_n := COALESCE(array_length(v_ids, 1), 0);

  IF v_n = 0 OR v_t IS NULL THEN
    RETURN jsonb_build_object(
      'status',     'error',
      'message',    format('El producto %s no tiene la presentacion %s en su cadena',
                           p_id_producto, p_id_presentacion),
      'error_code', 'PRESENTATION_NOT_IN_CHAIN');
  END IF;

  -- ── Saldos vigentes de esa ubicacion ──────────────────────────────────────
  FOR r IN
    SELECT s.id_presentacion, SUM(s.saldo) AS saldo
      FROM public.fn_stock_saldos_presentacion(
             p_id_producto, NULL, p_id_ubicacion, true) s
     WHERE (p_id_variante        IS NULL OR s.id_variante        IS NOT DISTINCT FROM p_id_variante)
       AND (p_id_opcion_variante IS NULL OR s.id_opcion_variante IS NOT DISTINCT FROM p_id_opcion_variante)
     GROUP BY s.id_presentacion
  LOOP
    FOR v_i IN 1 .. v_n LOOP
      IF v_ids[v_i] = r.id_presentacion THEN
        v_s[v_i] := COALESCE(r.saldo, 0);
      END IF;
    END LOOP;
  END LOOP;

  v_saldo_propio := v_s[v_t];

  -- Equivalente en base de TODO lo que hay, para el maximo convertible.
  v_equiv := 0;
  FOR v_i IN 1 .. v_n LOOP
    v_equiv := v_equiv + (v_s[v_i] * COALESCE(v_factor_rel[v_i], 1));
  END LOOP;
  v_max_conv := TRUNC(v_equiv / NULLIF(v_factor_rel[v_t], 0), 3);

  -- ── Caso facil: el saldo propio alcanza, no se pregunta nada ──────────────
  IF v_saldo_propio >= p_cantidad THEN
    RETURN jsonb_build_object(
      'status',                   'success',
      'necesita_conversion',      false,
      'estrategia',               'ninguna',
      'presentacion_nombre',      v_nombres[v_t],
      'saldo_propio',             v_saldo_propio,
      'cantidad_solicitada',      p_cantidad,
      'faltante',                 0,
      'conversiones',             '[]'::JSONB,
      'saldo_despues_conversion', v_saldo_propio,
      'sobrante_tras_consumo',    v_saldo_propio - p_cantidad,
      'maximo_convertible',       v_max_conv,
      'equivalente_base',         v_equiv,
      'mensaje_usuario',          NULL);
  END IF;

  v_faltante := p_cantidad - v_saldo_propio;

  -- ========================================================================
  -- SIMULACION 1 · ABRIR
  -- ========================================================================
  v_viable := false;

  IF v_t > 1 THEN
    v_req[v_t] := v_faltante;

    v_nivel_top := NULL;
    FOR v_i IN REVERSE (v_t - 1) .. 1 LOOP
      IF COALESCE(v_fhijo[v_i], 0) <= 0 THEN
        EXIT;
      END IF;
      v_abrir[v_i] := CEIL(v_req[v_i + 1] / v_fhijo[v_i]);
      v_req[v_i]   := GREATEST(0, v_abrir[v_i] - v_s[v_i]);
      IF v_req[v_i] = 0 THEN
        v_nivel_top := v_i;
        EXIT;
      END IF;
    END LOOP;

    IF v_nivel_top IS NOT NULL THEN
      v_viable     := true;
      v_estrategia := 'abrir';

      FOR v_i IN v_nivel_top .. (v_t - 1) LOOP
        v_prod_hijos := v_abrir[v_i] * v_fhijo[v_i];

        v_s[v_i]     := v_s[v_i]     - v_abrir[v_i];
        v_s[v_i + 1] := v_s[v_i + 1] + v_prod_hijos;

        v_conversiones := v_conversiones || jsonb_build_object(
          'tipo',             'abrir',
          'origen_nombre',    v_nombres[v_i],
          'destino_nombre',   v_nombres[v_i + 1],
          'cantidad_origen',  v_abrir[v_i],
          'cantidad_destino', v_prod_hijos);
      END LOOP;
    END IF;
  END IF;

  -- ========================================================================
  -- SIMULACION 2 · EMPAQUETAR
  -- ========================================================================
  IF NOT v_viable AND v_t < v_n THEN
    v_falta[v_t] := v_faltante;

    v_nivel_deep := NULL;
    FOR v_j IN v_t .. (v_n - 1) LOOP
      IF COALESCE(v_fhijo[v_j], 0) <= 0 THEN
        EXIT;
      END IF;
      v_consumo[v_j + 1] := v_falta[v_j] * v_fhijo[v_j];
      v_falta[v_j + 1]   := GREATEST(0, v_consumo[v_j + 1] - v_s[v_j + 1]);
      IF v_falta[v_j + 1] = 0 THEN
        v_nivel_deep := v_j + 1;
        EXIT;
      END IF;
    END LOOP;

    IF v_nivel_deep IS NOT NULL THEN
      v_viable     := true;
      v_estrategia := 'empaquetar';

      FOR v_j IN REVERSE (v_nivel_deep - 1) .. v_t LOOP
        v_consumo_hijos := v_falta[v_j] * v_fhijo[v_j];

        v_s[v_j + 1] := v_s[v_j + 1] - v_consumo_hijos;
        v_s[v_j]     := v_s[v_j]     + v_falta[v_j];

        v_conversiones := v_conversiones || jsonb_build_object(
          'tipo',             'empaquetar',
          'origen_nombre',    v_nombres[v_j + 1],
          'destino_nombre',   v_nombres[v_j],
          'cantidad_origen',  v_consumo_hijos,
          'cantidad_destino', v_falta[v_j]);
      END LOOP;
    END IF;
  END IF;

  -- ========================================================================
  -- No alcanza ni abriendo ni empaquetando
  -- ========================================================================
  IF NOT v_viable THEN
    RETURN jsonb_build_object(
      'status',                   'success',   -- la consulta funciono; el stock es el que no da
      'necesita_conversion',      true,
      'estrategia',               'imposible',
      'presentacion_nombre',      v_nombres[v_t],
      'saldo_propio',             v_saldo_propio,
      'cantidad_solicitada',      p_cantidad,
      'faltante',                 v_faltante,
      'conversiones',             '[]'::JSONB,
      'saldo_despues_conversion', v_saldo_propio,
      'sobrante_tras_consumo',    NULL,
      'maximo_convertible',       v_max_conv,
      'equivalente_base',         v_equiv,
      'error_code',               'INSUFFICIENT_STOCK_CONVERTIBLE',
      'mensaje_usuario',          format(
        'No alcanza: se piden %s %s y como máximo se pueden servir %s.',
        public.fn_fmt_cantidad(p_cantidad),
        public.fn_plural_presentacion(v_nombres[v_t], p_cantidad),
        public.fn_fmt_cantidad(v_max_conv)));
  END IF;

  -- ── Plan viable: armar el mensaje del dialogo ────────────────────────────
  v_sobrante := v_s[v_t] - p_cantidad;
  v_primera  := v_conversiones -> 0;
  v_ultima   := v_conversiones -> -1;
  v_pasos    := jsonb_array_length(v_conversiones);

  IF v_estrategia = 'abrir' THEN
    -- Ojo con las cadenas de mas de un paso (Bulto -> Caja -> Unidad): el
    -- empaque que se abre es el de la PRIMERA conversion, pero lo que llega a
    -- la presentacion pedida sale de la ULTIMA. Mezclarlos daba mensajes
    -- incoherentes del tipo "Abrir 1 Bulto (10 Cajas)? Quedaran 11 Unidades".
    v_mensaje := format(
      'Faltan %s %s. ¿Abrir %s %s? Quedarán %s %s.',
      public.fn_fmt_cantidad(v_faltante),
      public.fn_plural_presentacion(v_nombres[v_t], v_faltante),
      public.fn_fmt_cantidad((v_primera->>'cantidad_origen')::NUMERIC),
      public.fn_plural_presentacion(v_primera->>'origen_nombre',
                                    (v_primera->>'cantidad_origen')::NUMERIC),
      public.fn_fmt_cantidad(v_sobrante),
      public.fn_plural_presentacion(v_nombres[v_t], v_sobrante));

    IF v_pasos > 1 THEN
      -- Se dice el camino completo para que el cajero sepa que se rompen dos
      -- empaques, no uno.
      v_mensaje := v_mensaje || ' (' || public.fn_fmt_cantidad(
          (v_primera->>'cantidad_origen')::NUMERIC) || ' '
        || public.fn_plural_presentacion(v_primera->>'origen_nombre',
             (v_primera->>'cantidad_origen')::NUMERIC);
      FOR v_i IN 0 .. (v_pasos - 1) LOOP
        v_mensaje := v_mensaje || ' → ' || public.fn_fmt_cantidad(
            ((v_conversiones -> v_i)->>'cantidad_destino')::NUMERIC) || ' '
          || public.fn_plural_presentacion(
               (v_conversiones -> v_i)->>'destino_nombre',
               ((v_conversiones -> v_i)->>'cantidad_destino')::NUMERIC);
      END LOOP;
      v_mensaje := v_mensaje || ')';
    END IF;
  ELSE
    v_mensaje := format(
      'Faltan %s %s. ¿Armar %s %s con %s %s?',
      public.fn_fmt_cantidad(v_faltante),
      public.fn_plural_presentacion(v_nombres[v_t], v_faltante),
      public.fn_fmt_cantidad((v_ultima->>'cantidad_destino')::NUMERIC),
      public.fn_plural_presentacion(v_ultima->>'destino_nombre',
                                    (v_ultima->>'cantidad_destino')::NUMERIC),
      public.fn_fmt_cantidad((v_primera->>'cantidad_origen')::NUMERIC),
      public.fn_plural_presentacion(v_primera->>'origen_nombre',
                                    (v_primera->>'cantidad_origen')::NUMERIC));
  END IF;

  RETURN jsonb_build_object(
    'status',                   'success',
    'necesita_conversion',      true,
    'estrategia',               v_estrategia,
    'presentacion_nombre',      v_nombres[v_t],
    'saldo_propio',             v_saldo_propio,
    'cantidad_solicitada',      p_cantidad,
    'faltante',                 v_faltante,
    'conversiones',             v_conversiones,
    'saldo_despues_conversion', v_s[v_t],
    'sobrante_tras_consumo',    v_sobrante,
    'maximo_convertible',       v_max_conv,
    'equivalente_base',         v_equiv,
    'mensaje_usuario',          v_mensaje);
END;
$$;

COMMENT ON FUNCTION public.fn_preview_rebalanceo(
  BIGINT, BIGINT, BIGINT, NUMERIC, BIGINT, BIGINT) IS
  'SOLO LECTURA: simula el rebalanceo de presentaciones sin escribir nada y '
  'devuelve el plan (que se abriria, con cuantas sueltas queda) mas un '
  'mensaje_usuario listo para el dialogo de confirmacion del TPV. No reserva '
  'stock: entre la preview y la venta el saldo puede cambiar.';

GRANT EXECUTE ON FUNCTION public.fn_preview_rebalanceo(
  BIGINT, BIGINT, BIGINT, NUMERIC, BIGINT, BIGINT)
  TO anon, authenticated, service_role;


-- ============================================================================
-- ENSAYO YA REALIZADO (BEGIN/ROLLBACK contra datos reales, 2026-08-26)
-- ============================================================================
-- Cadena Bulto 120 / Caja 12 / Unidad 1 (o sea 1 Bulto = 10 Cajas), tienda 55.
-- Mensajes textuales devueltos, tal cual salieron:
--
--   fn_fmt_cantidad: 1 -> "1", 12.000 -> "12", 1.5 -> "1.5", 0.916 -> "0.916",
--                    NULL -> "0"
--
--   P1  ubic 74 con 4 Cajas y 0 sueltas, piden 1 Unidad
--       estrategia 'abrir', 1 conversion, saldo_despues 12, sobrante 11
--       "Faltan 1 Unidad. ¿Abrir 1 Caja? Quedarán 11 Unidades."
--
--   P8  el mismo estante, piden 25 Unidades
--       "Faltan 25 Unidades. ¿Abrir 3 Cajas? Quedarán 11 Unidades."
--       (el CEIL abre 3 cajas = 36 y sobran 11 tras consumir 25)
--
--   P9  el mismo estante, piden 2 Cajas -> mensaje_usuario NULL y
--       necesita_conversion false: la UI NO debe preguntar nada.
--
--   P3  ubic 75 con 20 sueltas y 0 cajas, piden 1 Caja
--       estrategia 'empaquetar'
--       "Faltan 1 Caja. ¿Armar 1 Caja con 12 Unidades?"
--
--   P5  ubic 76 con 1 Bulto, 0 cajas, 0 sueltas, piden 1 Unidad
--       DOS conversiones encadenadas sin saltar a base, y el mensaje dice el
--       camino completo:
--       "Faltan 1 Unidad. ¿Abrir 1 Bulto? Quedarán 11 Unidades.
--        (1 Bulto → 10 Cajas → 12 Unidades)"
--
--   P4  piden 500 Unidades con 48 de equivalente
--       estrategia 'imposible', maximo_convertible 48.000
--       "No alcanza: se piden 500 Unidades y como máximo se pueden servir 48."
--
--   P6  id del catalogo (3) y presentacion de otro producto -> status 'error'
--       con INVALID_PRESENTATION y el mensaje que explica cual es cual.
--       Cantidad 0 -> INVALID_QUANTITY.
--
--   P7  el ledger NO crecio y no se creo ninguna fila en
--       app_dat_conversion_presentacion: la preview no escribe.
--
-- Dos defectos que aparecieron en el primer ensayo y estan corregidos arriba:
--   (a) los mensajes salian con el punto colgante ("Faltan 1. Unidad") porque
--       to_char con FM lo deja; de ahi nacio fn_fmt_cantidad.
--   (b) en las cadenas de dos pasos el mensaje mezclaba la primera conversion
--       con el destino final y decia "¿Abrir 1 Bulto (10 Cajas)? Quedarán 11
--       Unidades", que suena a que quedan 11 cajas. Ahora el parentesis muestra
--       el camino completo.


-- ============================================================================
-- VERIFICACION (correr despues de aplicar; no modifica datos)
-- ============================================================================
-- 1. Existen las dos funciones, la preview es STABLE (no escribe) y hay grants:
--
--   SELECT p.oid::regprocedure AS firma,
--          p.provolatile AS volatilidad,
--          p.prosecdef   AS secdef,
--          array_to_string(p.proacl, ' | ') AS acl
--     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname = 'public'
--      AND p.proname IN ('fn_preview_rebalanceo', 'fn_fmt_cantidad')
--    ORDER BY p.proname;
--   -- esperado: fn_fmt_cantidad volatilidad 'i'; fn_preview_rebalanceo 's' y
--   --           secdef true; ambas con anon/authenticated/service_role
--
-- 2. Prueba en vivo con un producto multipresentacion real (no escribe nada):
--
--   SELECT jsonb_pretty(public.fn_preview_rebalanceo(
--            p_id_producto     => 1140,
--            p_id_ubicacion    => 74,
--            p_id_presentacion => (SELECT pp.id
--                                    FROM app_dat_producto_presentacion pp
--                                   WHERE pp.id_producto = 1140
--                                     AND pp.es_base
--                                   LIMIT 1),
--            p_cantidad        => 1));
--
-- 3. Confirmar que de verdad no escribio:
--
--   SELECT (SELECT count(*) FROM app_dat_inventario_productos)     AS ledger,
--          (SELECT count(*) FROM app_dat_conversion_presentacion)  AS conversiones;
--   -- correr antes y despues del punto 2: los dos numeros deben ser iguales
