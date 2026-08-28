-- ============================================================================
-- 12 · Congelar el factor de una presentacion que ya tiene movimientos
-- ============================================================================
-- Plan: docs/PLAN_PRESENTACIONES_INVENTARIO.md (Fase 2.0)
-- Proyecto Supabase: vsieeihstajlrdvpuooh
-- Aplicar en: SQL Editor del dashboard. Idempotente (CREATE OR REPLACE +
--             DROP TRIGGER IF EXISTS).
--
-- DEPENDE DE:
--   - 10_preview_rebalanceo.sql  (usa fn_fmt_cantidad en el mensaje de error)
--   - 11_indices_presentacion.sql (SIN esos indices,
--     fn_presentacion_tiene_movimientos tarda ~120 ms por llamada porque hace
--     cuatro Seq Scan; con ellos, 0,3 ms). El 11 ya esta aplicado.
--
-- NO reemplaza ninguna funcion viva. Agrega una funcion de trigger nueva y un
-- trigger nuevo sobre app_dat_producto_presentacion.
--
--
-- EL PROBLEMA
-- -----------
-- `app_dat_producto_presentacion.cantidad` es el factor: cuantas unidades base
-- entran en esa presentacion. Todo el sistema de presentaciones lo interpreta
-- en tiempo de LECTURA, no lo copia al ledger:
--
--   factor_rel = pp.cantidad / cantidad_de_la_base
--
-- El ledger guarda "4" en la fila de Caja. Que eso signifique 48 unidades o 96
-- lo decide `pp.cantidad` HOY, no el dia que se registro el movimiento.
--
-- Entonces cambiar el 12 por un 24 en una Caja que ya tiene historia no corrige
-- un dato: reescribe el pasado. Los 4 que se recibieron el mes pasado pasan a
-- valer 96 unidades, el IPV de ese mes cambia solo, la valoracion del almacen
-- cambia sola, y no queda ninguna traza de que paso. Ningun movimiento se
-- inserto ni se borro; el mismo numero significa otra cosa.
--
-- Verificado en produccion (2026-08-26):
--   - 8.891 filas en app_dat_producto_presentacion
--   - 7.434 de ellas ya tienen movimientos en el ledger (84 %)
--   - hoy NADA lo impide: el unico trigger de la tabla es
--     `trg_registrar_precio_costo`, que solo mira `precio_promedio`
--   - ninguna RPC toca `cantidad` en un UPDATE; el riesgo entra por la app y
--     por el SQL Editor
--
-- NetSuite y SAP B1 prohiben cambiar la unidad de medida base cuando el item ya
-- tiene transacciones, exactamente por esto (ver
-- docs/REFERENCIA_INDUSTRIA_PRESENTACIONES.md).
--
--
-- ⚠️ SUPERSEDIDO EN PARTE POR EL `23`
-- ----------------------------------
-- `es_base` se sacó del guard en `23_compatibilidad_es_base.sql`: bloquearlo
-- rompía los tres métodos de `presentation_service.dart` que cambian la base de
-- un producto (todos empiezan apagando la marca de TODAS las filas), y la app
-- en producción recibía un 23001 al hacer
-- `PATCH ...?id_producto=eq.X {"es_base": false}`. Lo que sigue vigente de este
-- archivo son las otras tres columnas y el DELETE.
--
-- QUE SE BLOQUEA Y QUE NO
-- -----------------------
-- Se bloquea, SOLO si esa fila ya tiene movimientos:
--   - cambiar `cantidad`      (el factor: reinterpreta todo el historico)
--   - cambiar `id_presentacion` (convierte una Caja historica en un Bulto)
--   - cambiar `id_producto`   (mueve la fila a otro producto)
--   - borrar la fila
--
-- NO se bloquea nunca:
--   - `es_base` (desde el `23`: es un puntero reversible, no un dato)
--   - `precio_promedio` (cambia todo el tiempo por recepcion; es el caso normal
--     y tiene su propio trigger de auditoria)
--   - INSERT de una presentacion nueva
--   - cualquier cambio sobre una fila SIN movimientos (un typo recien creado se
--     sigue corrigiendo sin friccion: son 1.457 filas)
--
-- El DELETE ya fallaba por las FK (`app_dat_inventario_productos` y 4 mas
-- referencian esta tabla con NO ACTION), pero con un mensaje de violacion de
-- clave ajena que no le dice nada a nadie. El trigger lo intercepta antes y
-- explica el motivo.
--
--
-- COMO CORREGIR UN FACTOR MAL PUESTO (la salida legitima)
-- ------------------------------------------------------
-- Si el factor esta mal de verdad y hay que arreglarlo, hay dos caminos:
--
-- A. Lo correcto: crear una presentacion NUEVA con el factor bueno y dejar de
--    usar la vieja. El historico sigue significando lo que significaba.
--
-- B. La salida de emergencia, cuando el factor es un error de carga y el
--    historico esta igual de mal: desbloquear para UNA transaccion.
--
--      BEGIN;
--      SET LOCAL ventiq.permitir_cambio_factor = 'on';
--      UPDATE app_dat_producto_presentacion SET cantidad = 24 WHERE id = 11053;
--      COMMIT;
--
--    `SET LOCAL` muere con la transaccion, asi que no queda una puerta abierta.
--    Es deliberado que sea incomodo y que haya que escribirlo a mano: obliga a
--    pensarlo. Antes de hacerlo, conviene mirar cuanto historico se va a
--    reinterpretar (la consulta esta al final de este archivo).
--
--
-- POR QUE UN TRIGGER Y NO PERMISOS
-- --------------------------------
-- Quitarle el UPDATE a `anon`/`authenticated` sobre esta tabla romperia el
-- guardado de precios, que si es legitimo y pasa por la misma tabla. Un trigger
-- distingue por columna; un GRANT no.
-- ============================================================================


-- ────────────────────────────────────────────────────────────────────────────
-- 12.1 · fn_presentacion_tiene_movimientos
-- ────────────────────────────────────────────────────────────────────────────
-- Separada del trigger a proposito: la UI la necesita para deshabilitar el
-- campo "cantidad" ANTES de que el usuario escriba, en vez de dejarlo escribir
-- y despues mostrarle un error.
--
-- Se consultan las 5 tablas que referencian una presentacion con historia:
-- el ledger, los tres detalles de operacion y las conversiones. Se usa EXISTS
-- con OR y corto-circuito, no COUNT, para que pare en el primer hallazgo.
--
-- RENDIMIENTO: depende por completo de los indices del archivo 11. Sin ellos
-- son cuatro Seq Scan sobre 720.000 filas (~120 ms por llamada); con ellos, 4
-- Index Only Scan con Heap Fetches 0 y un BitmapOr: 0,3 ms. Medido, no
-- estimado. Si esta funcion se pone lenta, lo primero a revisar es que los seis
-- indices sigan VALIDOS (ver la verificacion del 11).
--
-- El orden de los EXISTS NO es alfabetico ni casual: primero el ledger, que es
-- donde esta el 84 % de las presentaciones con historia, para que el
-- corto-circuito corte en la primera comprobacion en el caso tipico.

CREATE OR REPLACE FUNCTION public.fn_presentacion_tiene_movimientos(
  p_id_producto_presentacion BIGINT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT p_id_producto_presentacion IS NOT NULL
     AND (
       EXISTS (SELECT 1 FROM app_dat_inventario_productos t
                WHERE t.id_presentacion = p_id_producto_presentacion)
    OR EXISTS (SELECT 1 FROM app_dat_recepcion_productos t
                WHERE t.id_presentacion = p_id_producto_presentacion)
    OR EXISTS (SELECT 1 FROM app_dat_extraccion_productos t
                WHERE t.id_presentacion = p_id_producto_presentacion)
    OR EXISTS (SELECT 1 FROM app_dat_control_productos t
                WHERE t.id_presentacion = p_id_producto_presentacion)
    OR EXISTS (SELECT 1 FROM app_dat_conversion_presentacion t
                WHERE t.id_presentacion_origen  = p_id_producto_presentacion
                   OR t.id_presentacion_destino = p_id_producto_presentacion)
     );
$$;

COMMENT ON FUNCTION public.fn_presentacion_tiene_movimientos(BIGINT) IS
  'true si esa fila de app_dat_producto_presentacion ya aparece en el ledger, '
  'en un detalle de recepcion/extraccion/control o en una conversion. La UI la '
  'usa para deshabilitar el campo del factor; el trigger para rechazar el '
  'cambio.';

GRANT EXECUTE ON FUNCTION public.fn_presentacion_tiene_movimientos(BIGINT)
  TO anon, authenticated, service_role;


-- ────────────────────────────────────────────────────────────────────────────
-- 12.2 · fn_trg_congelar_factor_presentacion
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_trg_congelar_factor_presentacion()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_id            BIGINT;
  v_permitir      TEXT;
  v_movimientos   BOOLEAN;
  v_que_cambia    TEXT[] := '{}';
  v_nombre        TEXT;
BEGIN
  v_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END;

  -- Salida de emergencia explicita (SET LOCAL, muere con la transaccion).
  -- El segundo argumento 'true' de current_setting evita el error cuando la
  -- variable no esta definida, que es el caso normal.
  v_permitir := COALESCE(current_setting('ventiq.permitir_cambio_factor', true), 'off');
  IF lower(v_permitir) IN ('on', 'true', '1', 'yes') THEN
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  -- ── Que se intenta cambiar ───────────────────────────────────────────────
  IF TG_OP = 'UPDATE' THEN
    IF NEW.cantidad IS DISTINCT FROM OLD.cantidad THEN
      v_que_cambia := v_que_cambia || format('el factor (cantidad: %s -> %s)',
                        public.fn_fmt_cantidad(OLD.cantidad),
                        public.fn_fmt_cantidad(NEW.cantidad));
    END IF;

    IF NEW.id_presentacion IS DISTINCT FROM OLD.id_presentacion THEN
      v_que_cambia := v_que_cambia || format('la presentacion (id_presentacion: %s -> %s)',
                        OLD.id_presentacion, NEW.id_presentacion);
    END IF;

    IF NEW.es_base IS DISTINCT FROM OLD.es_base THEN
      v_que_cambia := v_que_cambia || format('la marca de base (es_base: %s -> %s)',
                        OLD.es_base, NEW.es_base);
    END IF;

    IF NEW.id_producto IS DISTINCT FROM OLD.id_producto THEN
      v_que_cambia := v_que_cambia || format('el producto (id_producto: %s -> %s)',
                        OLD.id_producto, NEW.id_producto);
    END IF;

    -- Solo cambio precio_promedio (u otra columna libre): se deja pasar.
    IF array_length(v_que_cambia, 1) IS NULL THEN
      RETURN NEW;
    END IF;
  END IF;

  -- ── Recien aca se consulta el historico ──────────────────────────────────
  -- Puesto despues del chequeo de columnas a proposito: el UPDATE de
  -- precio_promedio pasa por este trigger en cada recepcion y no debe pagar
  -- cinco EXISTS por nada.
  v_movimientos := public.fn_presentacion_tiene_movimientos(v_id);

  IF NOT v_movimientos THEN
    -- Sin historia, cualquier correccion es libre.
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  SELECT np.denominacion
  INTO v_nombre
  FROM app_nom_presentacion np
  WHERE np.id = OLD.id_presentacion;

  -- OJO: en RAISE el placeholder es `%`, NO `%s` (eso es de format()). Con
  -- `%s` el % consume el argumento y queda una `s` suelta en el mensaje.
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION
      'No se puede borrar la presentacion "%" (id %) del producto %: ya tiene movimientos de inventario registrados. Los movimientos historicos quedarian sin referencia. Cree una presentacion nueva y deje de usar esta.',
      COALESCE(v_nombre, '?'), OLD.id, OLD.id_producto
      USING ERRCODE = 'restrict_violation',
            HINT = 'Si es un error de carga y hay que forzarlo: BEGIN; SET LOCAL ventiq.permitir_cambio_factor = ''on''; ... COMMIT;';
  END IF;

  RAISE EXCEPTION
    'No se puede cambiar % de la presentacion "%" (id %) del producto %: ya tiene movimientos de inventario. El factor se interpreta al leer, asi que cambiarlo reinterpreta TODO el historico de esa presentacion (saldos, IPV, valoracion y costos de meses cerrados cambiarian solos, sin dejar traza).',
    array_to_string(v_que_cambia, ' y '),
    COALESCE(v_nombre, '?'), NEW.id, NEW.id_producto
    USING ERRCODE = 'restrict_violation',
          HINT = 'Cree una presentacion nueva con el factor correcto y deje de usar la vieja. Si es un error de carga y el historico tambien esta mal: BEGIN; SET LOCAL ventiq.permitir_cambio_factor = ''on''; ... COMMIT;';
END;
$$;

COMMENT ON FUNCTION public.fn_trg_congelar_factor_presentacion() IS
  'Trigger BEFORE UPDATE/DELETE de app_dat_producto_presentacion: impide '
  'cambiar cantidad, id_presentacion, es_base o id_producto, y borrar la fila, '
  'cuando ya hay movimientos. precio_promedio y las filas sin historia no se '
  'tocan. Escape: SET LOCAL ventiq.permitir_cambio_factor = ''on''.';


-- ────────────────────────────────────────────────────────────────────────────
-- 12.3 · El trigger
-- ────────────────────────────────────────────────────────────────────────────
-- Se limita el UPDATE a las 4 columnas sensibles con `UPDATE OF`, asi Postgres
-- ni siquiera invoca la funcion cuando solo cambia precio_promedio. Es la misma
-- tecnica que ya usa trg_registrar_precio_costo (UPDATE OF precio_promedio).
--
-- Convive sin conflicto con trg_registrar_precio_costo: ese es AFTER y mira
-- otra columna.

DROP TRIGGER IF EXISTS trg_congelar_factor_presentacion
  ON public.app_dat_producto_presentacion;

CREATE TRIGGER trg_congelar_factor_presentacion
  BEFORE UPDATE OF cantidad, id_presentacion, es_base, id_producto
      OR DELETE
  ON public.app_dat_producto_presentacion
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_trg_congelar_factor_presentacion();


-- ============================================================================
-- ENSAYO YA REALIZADO (BEGIN/ROLLBACK contra datos reales, 2026-08-26)
-- ============================================================================
-- Los 12 bloques del 13 pasaron. Detalle en la cabecera de
-- 13_tests_congelar_factor.sql. Lo esencial:
--   - los cuatro cambios prohibidos se rechazan con SQLSTATE **23001** y un
--     mensaje que explica el motivo (no una violacion de FK cruda);
--   - `precio_promedio` sobre una presentacion con movimientos sigue pasando
--     (es el camino caliente de cada recepcion);
--   - el factor de una presentacion sin historia se sigue corrigiendo;
--   - el escape `SET LOCAL` funciona y al volver a 'off' vuelve a bloquear;
--   - el trigger preexistente `trg_registrar_precio_costo` quedo intacto.
--
-- SQLSTATE: `ERRCODE = 'restrict_violation'` lo mapea Postgres a **23001**. Ese
-- es el codigo que tiene que mirar la app si quiere distinguir este rechazo.


-- ============================================================================
-- YA APLICADO EN PRODUCCION (2026-08-26)
-- ============================================================================
-- Verificado despues de aplicar:
--   trg_congelar_factor_presentacion  BEFORE DELETE OR UPDATE OF cantidad,
--     id_presentacion, es_base, id_producto  ON app_dat_producto_presentacion
--     FOR EACH ROW
--   trg_registrar_precio_costo  AFTER INSERT OR UPDATE OF precio_promedio
--     (el preexistente, sin cambios)
--   fn_presentacion_tiene_movimientos -> STABLE ('s')
--   fn_trg_congelar_factor_presentacion -> VOLATILE ('v', correcto para trigger)


-- ============================================================================
-- LIMITE PREEXISTENTE QUE CONVIENE CONOCER (no lo introduce este archivo)
-- ============================================================================
-- Una presentacion a la que alguien le puso precio alguna vez YA NO SE PUEDE
-- BORRAR, aunque nunca se haya movido: el trigger `trg_registrar_precio_costo`
-- le inserta una fila en app_dat_precio_costo y esa FK es NO ACTION.
--
-- Reparto real de las 8.891 filas:
--   7.486  con movimientos                      -> las congela este trigger
--      87  sin movimientos pero con precio_costo -> imborrables por la FK
--   1.319  borrables de verdad
--
-- O sea que de las 1.405 "libres", 87 lo son solo a medias. No es algo que este
-- archivo tenga que resolver, pero la pantalla de edicion de presentaciones
-- (Fase 2) se va a topar con ese error si intenta borrarlas.


-- ============================================================================
-- ANTES DE APLICAR: mirar que se va a romper
-- ============================================================================
-- 1. Cuantas filas quedan congeladas y cuantas siguen libres.
--
--    NO llamar a fn_presentacion_tiene_movimientos una vez por fila: son 8.891
--    llamadas y, aunque con los indices del 11 cada una tarde 0,3 ms, el
--    planificador no puede combinarlas y el dashboard corta. Se hace con UNION
--    + LEFT JOIN, que resuelve las 8.891 en una pasada:
--
--   WITH mov AS (
--     SELECT DISTINCT id_presentacion AS p FROM app_dat_inventario_productos
--      WHERE id_presentacion IS NOT NULL
--     UNION
--     SELECT DISTINCT id_presentacion FROM app_dat_recepcion_productos
--      WHERE id_presentacion IS NOT NULL
--     UNION
--     SELECT DISTINCT id_presentacion FROM app_dat_extraccion_productos
--      WHERE id_presentacion IS NOT NULL
--     UNION
--     SELECT DISTINCT id_presentacion FROM app_dat_control_productos
--      WHERE id_presentacion IS NOT NULL)
--   SELECT count(*) FILTER (WHERE m.p IS NOT NULL) AS congeladas,
--          count(*) FILTER (WHERE m.p IS NULL)     AS libres,
--          count(*)                                AS total
--     FROM app_dat_producto_presentacion pp
--     LEFT JOIN mov m ON m.p = pp.id;
--
--   -- medido en produccion 2026-08-26, 320 ms:
--   --   congeladas 7486 | libres 1405 | total 8891
--   --
--   -- (una version anterior de esta nota decia 7.434 / 1.457: ese numero salia
--   --  de mirar SOLO el ledger. Las 52 de diferencia son presentaciones que
--   --  aparecen en un detalle de recepcion/extraccion/control pero no en el
--   --  ledger. El trigger las protege igual, y hace bien.)
--
-- 2. Cuanto historico reinterpretaria un cambio de factor concreto (correr esto
--    ANTES de usar la salida de emergencia):
--
--   SELECT pp.id, np.denominacion, pp.cantidad AS factor_actual,
--          (SELECT count(*) FROM app_dat_inventario_productos ip
--            WHERE ip.id_presentacion = pp.id)              AS filas_ledger,
--          (SELECT min(ip.created_at) FROM app_dat_inventario_productos ip
--            WHERE ip.id_presentacion = pp.id)              AS desde,
--          (SELECT sum(ip.cantidad) FROM app_dat_inventario_productos ip
--            WHERE ip.id_presentacion = pp.id)              AS cantidad_acumulada
--     FROM app_dat_producto_presentacion pp
--     JOIN app_nom_presentacion np ON np.id = pp.id_presentacion
--    WHERE pp.id = 11053;   -- <- el id a cambiar
--
--
-- ============================================================================
-- DESPUES DE APLICAR
-- ============================================================================
-- 1. El trigger existe y no se piso el que ya estaba:
--
--   SELECT t.tgname, p.proname, pg_get_triggerdef(t.oid) AS def
--     FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
--    WHERE t.tgrelid = 'public.app_dat_producto_presentacion'::regclass
--      AND NOT t.tgisinternal
--    ORDER BY t.tgname;
--   -- esperado: DOS filas, trg_congelar_factor_presentacion (BEFORE) y
--   --           trg_registrar_precio_costo (AFTER, el que ya existia)
--
-- 2. Que precio_promedio siga pasando (es el camino caliente de cada recepcion):
--
--   BEGIN;
--     UPDATE app_dat_producto_presentacion
--        SET precio_promedio = precio_promedio
--      WHERE id = (SELECT id FROM app_dat_producto_presentacion
--                   WHERE public.fn_presentacion_tiene_movimientos(id) LIMIT 1);
--   ROLLBACK;
--   -- esperado: UPDATE 1, sin error
--
--
-- ============================================================================
-- IMPACTO EN LA APP (hay que acompañarlo, si no el usuario ve un error crudo)
-- ============================================================================
-- Estos tres sitios hoy pueden intentar lo que el trigger rechaza. Con el
-- trigger puesto van a fallar con el mensaje de arriba en vez de corromper el
-- historico, pero conviene que la UI lo prevenga:
--
--   ventiq_admin_app/lib/screens/add_product_screen.dart:6519
--     .update({'cantidad': cantidad}) sobre presentaciones NO base
--   ventiq_admin_app/lib/screens/add_product_screen.dart:6101
--     .update({... 'es_base': true, 'cantidad': ...}) sobre la base
--   ventiq_admin_app/lib/screens/add_product_screen.dart:6473
--     .delete() de las presentaciones que el usuario quito de la lista
--
-- Lo minimo: llamar `fn_presentacion_tiene_movimientos(id)` al cargar la
-- pantalla de edicion, y con true poner el campo de cantidad en readOnly con un
-- texto tipo "esta presentacion ya tiene movimientos; el factor no se puede
-- cambiar". Eso es trabajo de la Fase 2 (UI); el trigger es la red de seguridad
-- que va debajo y no depende de que la UI se acuerde.
