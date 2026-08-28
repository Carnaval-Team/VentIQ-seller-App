-- ============================================================================
-- 13 · Tests del congelado de factor (NO modifica nada: BEGIN ... ROLLBACK)
-- ============================================================================
-- Plan: docs/PLAN_PRESENTACIONES_INVENTARIO.md (Fase 2.0)
-- Correr DESPUES de aplicar el 12.
--
-- Requiere los indices del archivo 11 (ya aplicados). Sin ellos este archivo da
-- TIMEOUT: fue exactamente lo que paso en la primera corrida, y de ahi salio el
-- archivo 11. Ver la nota del bloque D2.
--
-- Todo va dentro de BEGIN/ROLLBACK. La particularidad de estos tests es que la
-- mayoria espera que algo FALLE, y en plpgsql un RAISE aborta la transaccion.
-- Por eso cada intento va envuelto en su propio bloque BEGIN ... EXCEPTION, que
-- actua como subtransaccion: captura el error, lo guarda y sigue.
--
-- Requisitos: tienda 55, categoria 115, app_nom_presentacion 1 = Unidad,
-- 3 = Caja, 7 = Bulto. El 12 aplicado.
-- ============================================================================

BEGIN;

CREATE TEMP TABLE _r(k text, v jsonb);
CREATE TEMP TABLE _ctx(
  id_producto   bigint,
  id_caja       bigint,   -- va a tener movimientos
  id_unidad     bigint,   -- va a tener movimientos (es la base)
  id_virgen     bigint    -- presentacion SIN movimientos Y SIN precio_costo
);

-- ── Producto de prueba con cadena Caja 12 / Unidad 1 ───────────────────────
WITH n AS (
  INSERT INTO app_dat_producto (id_tienda, id_categoria, denominacion, sku,
    es_vendible, es_inventariable, es_servicio, es_elaborado,
    mostrar_en_catalogo, created_at)
  SELECT 55, 115, 'ZZ TEST congelar factor', 'ZZ-FREEZE',
         true, true, false, false, false, NOW()
  RETURNING id)
INSERT INTO _ctx (id_producto) SELECT id FROM n;

WITH i AS (
  INSERT INTO app_dat_producto_presentacion
    (id_producto, id_presentacion, cantidad, es_base, precio_promedio, created_at)
  SELECT c.id_producto, v.nom, v.f, v.b, 10.0, NOW()
    FROM _ctx c
    CROSS JOIN (VALUES (3, 12.0, false), (1, 1.0, true)) AS v(nom, f, b)
  RETURNING id, id_presentacion)
UPDATE _ctx SET
  id_caja   = (SELECT id FROM i WHERE id_presentacion = 3),
  id_unidad = (SELECT id FROM i WHERE id_presentacion = 1);

-- Una tercera presentacion que NUNCA se mueve: es el control del test.
-- Se usa el id 7 (Bulto) del catalogo.
--
-- OJO: precio_promedio = 0 a proposito. Con un precio > 0, el trigger
-- preexistente `trg_registrar_precio_costo` inserta una fila en
-- app_dat_precio_costo, y entonces el DELETE de B3 falla por la FK
-- `app_dat_precio_costo_id_presentacion_fkey` (SQLSTATE 23503) en vez de por
-- nuestro trigger. Eso es comportamiento PREEXISTENTE, ajeno a este archivo;
-- ver la nota al final. Aca queremos aislar el trigger nuevo.
WITH i AS (
  INSERT INTO app_dat_producto_presentacion
    (id_producto, id_presentacion, cantidad, es_base, precio_promedio, created_at)
  SELECT c.id_producto, 7, 120.0, false, 0, NOW() FROM _ctx c
  RETURNING id)
UPDATE _ctx SET id_virgen = (SELECT id FROM i);

-- ── Movimiento SOLO en la Caja ─────────────────────────────────────────────
-- En dos sentencias separadas a proposito: dentro de UN mismo SELECT, Postgres
-- no garantiza el orden de evaluacion de las subconsultas, asi que
-- fn_presentacion_tiene_movimientos puede correr ANTES del
-- fn_ingresar_presentacion y devolver false. Es el mismo artefacto que aparecio
-- en el C0_setup del 09.
INSERT INTO _r SELECT 'C0_ingreso', to_jsonb(x)
  FROM (SELECT public.fn_ingresar_presentacion(
                 (SELECT id_producto FROM _ctx), 74,
                 (SELECT id_caja FROM _ctx), 4, 1)->>'status' AS ingreso_caja) x;

INSERT INTO _r SELECT 'C0_estado', to_jsonb(x)
  FROM (SELECT
    public.fn_presentacion_tiene_movimientos((SELECT id_caja   FROM _ctx)) AS caja_esp_true,
    public.fn_presentacion_tiene_movimientos((SELECT id_virgen FROM _ctx)) AS virgen_esp_false) x;


-- ════════════════════════════════════════════════════════════════════════════
-- BLOQUE A · lo que DEBE fallar (presentacion con movimientos)
-- ════════════════════════════════════════════════════════════════════════════

-- A1 · cambiar el factor: el caso central
DO $$
DECLARE v_msg TEXT; v_state TEXT;
BEGIN
  BEGIN
    UPDATE app_dat_producto_presentacion
       SET cantidad = 24
     WHERE id = (SELECT id_caja FROM _ctx);
    INSERT INTO _r VALUES ('A1_cambiar_factor_esp_ERROR',
      jsonb_build_object('resultado', 'PASO (MAL: deberia fallar)'));
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT, v_state = RETURNED_SQLSTATE;
    INSERT INTO _r VALUES ('A1_cambiar_factor_esp_ERROR',
      jsonb_build_object('resultado', 'rechazado OK',
                         'sqlstate', v_state, 'message', v_msg));
  END;
END $$;

-- A2 · cambiar es_base (mueve el punto de referencia de toda la cadena)
DO $$
DECLARE v_msg TEXT; v_state TEXT;
BEGIN
  BEGIN
    UPDATE app_dat_producto_presentacion
       SET es_base = true
     WHERE id = (SELECT id_caja FROM _ctx);
    INSERT INTO _r VALUES ('A2_cambiar_es_base_esp_ERROR',
      jsonb_build_object('resultado', 'PASO (MAL: deberia fallar)'));
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT, v_state = RETURNED_SQLSTATE;
    INSERT INTO _r VALUES ('A2_cambiar_es_base_esp_ERROR',
      jsonb_build_object('resultado', 'rechazado OK',
                         'sqlstate', v_state, 'message', v_msg));
  END;
END $$;

-- A3 · cambiar id_presentacion (convertir una Caja historica en Bulto)
DO $$
DECLARE v_msg TEXT; v_state TEXT;
BEGIN
  BEGIN
    UPDATE app_dat_producto_presentacion
       SET id_presentacion = 7
     WHERE id = (SELECT id_caja FROM _ctx);
    INSERT INTO _r VALUES ('A3_cambiar_id_presentacion_esp_ERROR',
      jsonb_build_object('resultado', 'PASO (MAL: deberia fallar)'));
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT, v_state = RETURNED_SQLSTATE;
    INSERT INTO _r VALUES ('A3_cambiar_id_presentacion_esp_ERROR',
      jsonb_build_object('resultado', 'rechazado OK',
                         'sqlstate', v_state, 'message', v_msg));
  END;
END $$;

-- A4 · borrar la fila
DO $$
DECLARE v_msg TEXT; v_state TEXT;
BEGIN
  BEGIN
    DELETE FROM app_dat_producto_presentacion
     WHERE id = (SELECT id_caja FROM _ctx);
    INSERT INTO _r VALUES ('A4_borrar_esp_ERROR',
      jsonb_build_object('resultado', 'PASO (MAL: deberia fallar)'));
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT, v_state = RETURNED_SQLSTATE;
    INSERT INTO _r VALUES ('A4_borrar_esp_ERROR',
      jsonb_build_object('resultado', 'rechazado OK',
                         'sqlstate', v_state, 'message', v_msg));
  END;
END $$;


-- ════════════════════════════════════════════════════════════════════════════
-- BLOQUE B · lo que DEBE seguir funcionando
-- ════════════════════════════════════════════════════════════════════════════

-- B1 · precio_promedio sobre una presentacion CON movimientos.
-- Es el camino caliente: pasa en cada recepcion. Si esto se rompe, se rompe
-- el guardado de precios de todo el sistema.
DO $$
DECLARE v_msg TEXT;
BEGIN
  BEGIN
    UPDATE app_dat_producto_presentacion
       SET precio_promedio = 99.5
     WHERE id = (SELECT id_caja FROM _ctx);
    INSERT INTO _r VALUES ('B1_precio_promedio_con_mov_esp_OK',
      jsonb_build_object('resultado', 'paso OK',
                         'precio', (SELECT precio_promedio
                                      FROM app_dat_producto_presentacion
                                     WHERE id = (SELECT id_caja FROM _ctx))));
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    INSERT INTO _r VALUES ('B1_precio_promedio_con_mov_esp_OK',
      jsonb_build_object('resultado', 'FALLO (MAL)', 'message', v_msg));
  END;
END $$;

-- B2 · cambiar el factor de una presentacion SIN movimientos.
-- Corregir un typo recien creado tiene que seguir siendo libre: son 1.457 filas
-- en produccion.
DO $$
DECLARE v_msg TEXT;
BEGIN
  BEGIN
    UPDATE app_dat_producto_presentacion
       SET cantidad = 144
     WHERE id = (SELECT id_virgen FROM _ctx);
    INSERT INTO _r VALUES ('B2_factor_sin_mov_esp_OK',
      jsonb_build_object('resultado', 'paso OK',
                         'cantidad', (SELECT cantidad
                                        FROM app_dat_producto_presentacion
                                       WHERE id = (SELECT id_virgen FROM _ctx))));
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    INSERT INTO _r VALUES ('B2_factor_sin_mov_esp_OK',
      jsonb_build_object('resultado', 'FALLO (MAL)', 'message', v_msg));
  END;
END $$;

-- B3 · borrar una presentacion SIN movimientos y SIN precio_costo
--
-- Ver la nota del setup: si la presentacion tuviera precio_promedio > 0, el
-- trigger preexistente le habria creado una fila en app_dat_precio_costo y el
-- DELETE fallaria con SQLSTATE 23503 (violacion de FK), no por nuestro trigger.
-- Es una limitacion que YA existia antes de este archivo.
DO $$
DECLARE v_msg TEXT;
BEGIN
  BEGIN
    DELETE FROM app_dat_producto_presentacion
     WHERE id = (SELECT id_virgen FROM _ctx);
    INSERT INTO _r VALUES ('B3_borrar_sin_mov_esp_OK',
      jsonb_build_object('resultado', 'paso OK',
                         'quedan', (SELECT count(*)
                                      FROM app_dat_producto_presentacion pp, _ctx c
                                     WHERE pp.id_producto = c.id_producto)));
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    INSERT INTO _r VALUES ('B3_borrar_sin_mov_esp_OK',
      jsonb_build_object('resultado', 'FALLO (MAL)', 'message', v_msg));
  END;
END $$;

-- B4 · INSERT de una presentacion nueva (nunca se bloquea)
DO $$
DECLARE v_msg TEXT; v_id BIGINT;
BEGIN
  BEGIN
    INSERT INTO app_dat_producto_presentacion
      (id_producto, id_presentacion, cantidad, es_base, precio_promedio, created_at)
    SELECT c.id_producto, 7, 120.0, false, 10.0, NOW() FROM _ctx c
    RETURNING id INTO v_id;
    INSERT INTO _r VALUES ('B4_insert_esp_OK',
      jsonb_build_object('resultado', 'paso OK', 'id_nuevo', v_id));
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    INSERT INTO _r VALUES ('B4_insert_esp_OK',
      jsonb_build_object('resultado', 'FALLO (MAL)', 'message', v_msg));
  END;
END $$;


-- ════════════════════════════════════════════════════════════════════════════
-- BLOQUE C · la salida de emergencia
-- ════════════════════════════════════════════════════════════════════════════

-- C1 · con la variable en 'on', el cambio pasa
DO $$
DECLARE v_msg TEXT;
BEGIN
  BEGIN
    SET LOCAL ventiq.permitir_cambio_factor = 'on';
    UPDATE app_dat_producto_presentacion
       SET cantidad = 24
     WHERE id = (SELECT id_caja FROM _ctx);
    INSERT INTO _r VALUES ('C1_escape_on_esp_OK',
      jsonb_build_object('resultado', 'paso OK',
                         'cantidad', (SELECT cantidad
                                        FROM app_dat_producto_presentacion
                                       WHERE id = (SELECT id_caja FROM _ctx))));
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    INSERT INTO _r VALUES ('C1_escape_on_esp_OK',
      jsonb_build_object('resultado', 'FALLO (MAL)', 'message', v_msg));
  END;
END $$;

-- C2 · al volver a 'off' vuelve a bloquear.
-- Comprueba que el escape no deja una puerta abierta en la misma transaccion.
DO $$
DECLARE v_msg TEXT; v_state TEXT;
BEGIN
  BEGIN
    SET LOCAL ventiq.permitir_cambio_factor = 'off';
    UPDATE app_dat_producto_presentacion
       SET cantidad = 48
     WHERE id = (SELECT id_caja FROM _ctx);
    INSERT INTO _r VALUES ('C2_escape_off_otra_vez_esp_ERROR',
      jsonb_build_object('resultado', 'PASO (MAL: deberia fallar)'));
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT, v_state = RETURNED_SQLSTATE;
    INSERT INTO _r VALUES ('C2_escape_off_otra_vez_esp_ERROR',
      jsonb_build_object('resultado', 'rechazado OK', 'sqlstate', v_state));
  END;
END $$;


-- ════════════════════════════════════════════════════════════════════════════
-- BLOQUE D · el trigger que ya existia sigue vivo
-- ════════════════════════════════════════════════════════════════════════════

INSERT INTO _r SELECT 'D1_triggers_de_la_tabla', jsonb_agg(to_jsonb(x))
  FROM (SELECT t.tgname, t.tgtype
          FROM pg_trigger t
         WHERE t.tgrelid = 'public.app_dat_producto_presentacion'::regclass
           AND NOT t.tgisinternal
         ORDER BY t.tgname) x;
-- esperado: DOS filas — trg_congelar_factor_presentacion y
--           trg_registrar_precio_costo (el preexistente, no se piso)

-- D2 · cuantas filas quedan congeladas y cuantas libres.
--
-- ESTE ES EL BLOQUE QUE CAUSO EL TIMEOUT en la primera version. Llamaba a
-- fn_presentacion_tiene_movimientos una vez por fila: 8.891 llamadas x 4 Seq
-- Scan cada una = ~18 minutos. El diagnostico dio dos arreglos, los dos ya
-- hechos:
--   1. los indices del archivo 11 (0,3 ms por llamada en vez de 120 ms)
--   2. esta consulta, que no llama a la funcion: junta las presentaciones con
--      movimiento con UNION y las cruza con un LEFT JOIN, una sola pasada.
-- Medido en produccion: 320 ms.
INSERT INTO _r SELECT 'D2_conteo_produccion', to_jsonb(x)
  FROM (
    WITH mov AS (
      SELECT DISTINCT id_presentacion AS p FROM app_dat_inventario_productos
       WHERE id_presentacion IS NOT NULL
      UNION
      SELECT DISTINCT id_presentacion FROM app_dat_recepcion_productos
       WHERE id_presentacion IS NOT NULL
      UNION
      SELECT DISTINCT id_presentacion FROM app_dat_extraccion_productos
       WHERE id_presentacion IS NOT NULL
      UNION
      SELECT DISTINCT id_presentacion FROM app_dat_control_productos
       WHERE id_presentacion IS NOT NULL)
    SELECT count(*) FILTER (WHERE m.p IS NOT NULL) AS congeladas_esp_7486,
           count(*) FILTER (WHERE m.p IS NULL)     AS libres_esp_1405,
           count(*)                                AS total_esp_8891
      FROM app_dat_producto_presentacion pp
      LEFT JOIN mov m ON m.p = pp.id) x;

-- D3 · la funcion resuelve por indice, no por Seq Scan.
-- Es el chequeo de que los indices del 11 estan vivos y el planificador los usa.
-- Si esto tarda mas de unos pocos ms, algun indice quedo INVALIDO.
INSERT INTO _r SELECT 'D3_funcion_es_rapida', to_jsonb(x)
  FROM (SELECT
    (SELECT count(*) FROM pg_index x2
       JOIN pg_class i ON i.oid = x2.indexrelid
      WHERE i.relname IN ('idx_inventario_productos_presentacion',
                          'idx_extraccion_productos_presentacion',
                          'idx_control_productos_presentacion',
                          'idx_recepcion_productos_presentacion',
                          'idx_conv_pres_origen',
                          'idx_conv_pres_destino')
        AND x2.indisvalid)                              AS indices_validos_esp_6,
    public.fn_presentacion_tiene_movimientos(
      (SELECT id_caja FROM _ctx))                       AS caja_esp_true,
    public.fn_presentacion_tiene_movimientos(9999999999) AS inexistente_esp_false,
    public.fn_presentacion_tiene_movimientos(NULL)      AS nulo_esp_false) x;

SELECT jsonb_pretty(jsonb_object_agg(k, v)) AS resultado FROM _r;

ROLLBACK;


-- ============================================================================
-- ENSAYO YA REALIZADO (BEGIN/ROLLBACK contra datos reales, 2026-08-26)
-- ============================================================================
-- Todos los bloques pasaron. Resultados textuales:
--
--   A1  cambiar el factor -> rechazado, SQLSTATE 23001, mensaje:
--       'No se puede cambiar el factor (cantidad: 12 -> 24) de la presentacion
--        "Caja" (id 11083) del producto 10910: ya tiene movimientos de
--        inventario. El factor se interpreta al leer, asi que cambiarlo
--        reinterpreta TODO el historico...'
--   A2  cambiar es_base           -> rechazado, 23001
--   A3  cambiar id_presentacion   -> rechazado, 23001
--   A4  borrar                    -> rechazado, 23001, con el mensaje propio
--       (no la violacion de FK cruda que salia antes)
--   B1  precio_promedio con movimientos -> paso, quedo en 99.5  [el critico]
--   B2  factor sin movimientos          -> paso, quedo en 144
--   B3  borrar sin movimientos          -> paso
--   B4  INSERT nuevo                    -> paso
--   C1  escape 'on'  -> paso, cantidad 24
--   C2  escape 'off' -> vuelve a rechazar, 23001
--   D1  dos triggers: trg_congelar_factor_presentacion y
--       trg_registrar_precio_costo (el preexistente intacto)
--   D2  7486 congeladas / 1405 libres / 8891 total (320 ms)
--   D3  6 indices validos; caja true, id inexistente false, NULL false
--
-- NOTA sobre el SQLSTATE: se escribio `ERRCODE = 'restrict_violation'` y
-- Postgres lo mapea a **23001**, no a 2F003 como decia una version previa de
-- esta nota. Si la app quiere distinguir este rechazo de otros, el codigo a
-- mirar es 23001.
--
-- Dos cosas que este ensayo destapo y estan corregidas arriba:
--
--   (a) `C0_setup` devolvia `caja_esp_true = false`. No era el trigger: dentro
--       de UN mismo SELECT, Postgres no garantiza el orden de evaluacion de las
--       subconsultas, asi que la comprobacion corria antes del ingreso. Se
--       partio en dos sentencias (C0_ingreso / C0_estado) y da true. Es el mismo
--       artefacto que aparecio en el 09.
--
--   (b) `B3` fallaba con
--       'violates foreign key constraint app_dat_precio_costo_id_presentacion_fkey'.
--       Nada que ver con el trigger nuevo: el trigger PREEXISTENTE
--       `trg_registrar_precio_costo` le habia insertado una fila en
--       app_dat_precio_costo al crearla con precio 10.0, y esa FK es NO ACTION.
--       El test ahora crea la presentacion de control con precio 0 para aislar
--       lo que se quiere medir.
--
--       Vale la pena saberlo porque es un limite REAL de produccion, anterior a
--       este trabajo: **una presentacion a la que alguien le puso precio ya no
--       se puede borrar**, aunque nunca se haya movido. Medido:
--         7.486 con movimientos          (las congela este trigger)
--            87 sin movimientos pero con precio_costo  (imborrables por la FK)
--         1.319 borrables de verdad
--       Esas 87 no son un problema que este archivo introduzca ni tenga que
--       resolver; queda anotado para cuando la Fase 2 toque la pantalla de
--       edicion de presentaciones.


-- ============================================================================
-- LECTURA DEL RESULTADO
-- ============================================================================
-- Todo bien si:
--   A1..A4  -> "rechazado OK" con sqlstate 23001 y el mensaje explicando por que
--   B1..B4  -> "paso OK"  (B1 es el critico: precio_promedio no debe romperse)
--   C1      -> "paso OK", cantidad 24
--   C2      -> "rechazado OK"
--   D1      -> exactamente 2 triggers
--   D2      -> 7486 congeladas / 1405 libres / 8891 total
--   D3      -> 6 indices validos, caja true, inexistente false, nulo false
--
-- Cualquier "PASO (MAL...)" o "FALLO (MAL)" significa que el 12 NO esta listo
-- para aplicarse: reportarlo con el mensaje completo.
--
-- Si vuelve a dar timeout, el sospechoso es D3/D2: comprobar primero que los
-- seis indices del archivo 11 esten VALIDOS.

