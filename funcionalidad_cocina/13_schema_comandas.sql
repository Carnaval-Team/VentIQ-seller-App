-- ============================================================================
-- 13 · Fase 2 · Schema de comandas + campos de servicio en el item de cuenta
-- ============================================================================
-- Proyecto Supabase: vsieeihstajlrdvpuooh
--
-- HALLAZGOS DEL 12 QUE DEFINEN ESTE DISENO (verificados contra produccion)
-- -----------------------------------------------------------------------
--
-- 1. NINGUNA funcion del flujo de cuenta abierta toca inventario.
--    fn_agregar_item_cuenta_mesa (2873 chars) solo inserta o consolida la
--    linea. fn_abrir / fn_cancelar / fn_marcar_cuenta_cerrada tampoco:
--    toca_inventario = false en las tres. Y 12.6 devolvio 0 triggers.
--
--    Es decir: hoy la cuenta abierta es puramente contable. TODO el inventario
--    se mueve al cobrar, dentro de fn_registrar_venta_mesa. Eso confirma que
--    "pedir != cobrar" es un cambio de fondo, no un ajuste.
--
-- 2. fn_cerrar_cuenta_mesa NO EXISTE.
--    El plan la menciona (2.3), pero no esta en la base. El ciclo real es:
--      fn_abrir_cuenta_mesa -> fn_agregar_item_cuenta_mesa (xN)
--        -> [la app llama fn_registrar_venta_mesa con los productos]
--        -> fn_marcar_cuenta_cerrada(id_cuenta, id_operacion_venta)
--    Por tanto el "no re-descontar al cobrar" se implementa en
--    fn_registrar_venta_mesa (la que ya enruta desde el 11), no en una funcion
--    de cierre que no existe.
--
-- 3. fn_agregar_item_cuenta_mesa CONSOLIDA lineas iguales.
--    Si se agrega un bistec y luego otro, no crea dos filas: hace
--    cantidad = cantidad + 1 sobre la existente. Eso choca con las comandas:
--    la primera unidad ya se mando a cocina, la segunda tambien tiene que
--    mandarse, pero la linea es la misma.
--
--    Solucion adoptada: la comanda NO se cuelga de la linea de cuenta, se
--    cuelga de la CANTIDAD PEDIDA. app_dat_comanda_item lleva su propia
--    cantidad y su referencia a la linea; una linea con cantidad 2 puede tener
--    dos comanda_item de 1, o uno de 2, segun como se fue pidiendo. Asi la
--    consolidacion de la cuenta (que es correcta para cobrar) no destruye el
--    historial de lo que se mando a cocina.
--
-- ORDEN DE APLICACION
-- -------------------
--   1. Aplicar este archivo completo (es idempotente).
--   2. Correr la VERIFICACION del final.
--   3. Despues el 14 (logica de pedir) y el 15 (cobro sin re-descontar).
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 13.1 Enum de estados de preparacion
--
-- Se usan smallint con CHECK en vez de un tipo ENUM de Postgres: el resto del
-- esquema ya trabaja asi (app_dat_mesa_cuenta_abierta.estado es smallint), y
-- agregar valores a un ENUM en produccion es mas incomodo que ampliar un CHECK.
--
-- Decidido en el plan: NO mezclar estos estados con los de venta (1-4).
--
--   1 pendiente   la comanda llego a la cocina, nadie la ha tomado
--   2 en_prep     un cocinero la esta preparando
--   3 listo       lista para recoger / pasar
--   4 entregado   servida al cliente
--   5 cancelado   anulada antes de servir
-- ----------------------------------------------------------------------------


-- ----------------------------------------------------------------------------
-- 13.2 app_dat_comanda · cabecera
--
-- Una comanda es "lo que una cocina tiene que preparar de una cuenta, en un
-- momento dado". Se agrupa por (cuenta, cocina) y por disparo: si el mesero
-- pide entradas y 20 minutos despues los platos fuertes, son dos comandas
-- distintas aunque sea la misma cuenta y la misma cocina. Eso es lo que la
-- cocina necesita ver: tandas de trabajo, no un acumulado.
--
-- id_cuenta es NULLABLE a proposito: en Fase 5 puede haber comandas de venta
-- directa de mostrador (sin cuenta de mesa).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_dat_comanda (
    id              bigserial PRIMARY KEY,
    id_tienda       bigint      NOT NULL REFERENCES public.app_dat_tienda(id),
    id_cocina       bigint      NOT NULL REFERENCES public.app_dat_cocina(id),
    id_cuenta       bigint      REFERENCES public.app_dat_mesa_cuenta_abierta(id),
    id_mesa         bigint      REFERENCES public.app_dat_mesas(id),
    id_tpv          bigint      REFERENCES public.app_dat_tpv(id),

    -- Numero visible para cantar la comanda ("marchando la 12"). Correlativo
    -- por tienda y dia, lo asigna fn_disparar_comanda.
    numero          integer,

    estado          smallint    NOT NULL DEFAULT 1
                    CHECK (estado BETWEEN 1 AND 5),

    -- uuid del vendedor que la disparo, para saber a quien avisar cuando este
    -- lista. No es FK: el resto del esquema usa uuid suelto igual.
    uuid_vendedor   uuid,
    notas           text,

    -- Marcas de tiempo por estado. Son las que pide la industria (Lightspeed
    -- KDS documenta "timestamps for when the order is received, started and
    -- finished") y las que permiten medir tiempo de preparacion real.
    created_at      timestamptz NOT NULL DEFAULT now(),
    started_at      timestamptz,
    ready_at        timestamptz,
    delivered_at    timestamptz,
    cancelled_at    timestamptz,
    updated_at      timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.app_dat_comanda IS
    'Cabecera de comanda: lo que una cocina debe preparar de una cuenta en un disparo.';
COMMENT ON COLUMN public.app_dat_comanda.numero IS
    'Correlativo visible por tienda y dia, para cantar la comanda.';
COMMENT ON COLUMN public.app_dat_comanda.estado IS
    '1 pendiente, 2 en preparacion, 3 listo, 4 entregado, 5 cancelado.';

-- El KDS pregunta siempre "que tengo pendiente en MI cocina": ese es el indice
-- que importa. Se acota a estados vivos con un indice parcial para que no
-- crezca con el historico.
CREATE INDEX IF NOT EXISTS idx_comanda_cocina_activa
    ON public.app_dat_comanda (id_cocina, created_at)
 WHERE estado IN (1, 2, 3);

CREATE INDEX IF NOT EXISTS idx_comanda_cuenta
    ON public.app_dat_comanda (id_cuenta)
 WHERE id_cuenta IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_comanda_tienda_fecha
    ON public.app_dat_comanda (id_tienda, created_at DESC);


-- ----------------------------------------------------------------------------
-- 13.3 app_dat_comanda_item · lineas
--
-- Cada linea es un plato a preparar. Lleva su propia cantidad y su propio
-- estado: el plan pide poder marcar "estado a nivel de item Y de ticket", que
-- es como funcionan los KDS reales (una guarnicion puede estar lista antes que
-- el plato fuerte).
--
-- id_item_cuenta apunta a la linea de la cuenta para poder reflejar el estado
-- de servicio en la nota del mesero. NO es unico: por la consolidacion de
-- fn_agregar_item_cuenta_mesa, una linea de cuenta con cantidad 3 puede tener
-- varias comanda_item si se pidio en varios momentos.
--
-- ON DELETE SET NULL en id_item_cuenta: si el mesero borra la linea de la
-- cuenta, la comanda NO desaparece (la cocina puede haberla cocinado ya). Queda
-- huerfana y se cancela explicitamente, que es auditable.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_dat_comanda_item (
    id                bigserial PRIMARY KEY,
    id_comanda        bigint      NOT NULL
                      REFERENCES public.app_dat_comanda(id) ON DELETE CASCADE,
    id_item_cuenta    bigint      REFERENCES public.app_dat_mesa_cuenta_item(id)
                      ON DELETE SET NULL,

    id_producto       bigint      NOT NULL REFERENCES public.app_dat_producto(id),
    id_variante       bigint,
    id_opcion_variante bigint,
    id_presentacion   bigint,

    -- Denominacion congelada: si el admin renombra el plato despues, el ticket
    -- historico debe seguir diciendo lo que se pidio.
    denominacion      text        NOT NULL,
    cantidad          numeric(14,3) NOT NULL CHECK (cantidad > 0),

    -- 'al_pedido' o 'por_tanda'. Congelado tambien: define si esta linea
    -- consumio materia prima o una porcion ya hecha.
    modo_elaboracion  text        NOT NULL DEFAULT 'al_pedido'
                      CHECK (modo_elaboracion IN ('al_pedido', 'por_tanda')),

    estado            smallint    NOT NULL DEFAULT 1
                      CHECK (estado BETWEEN 1 AND 5),

    -- Nota del comensal ("sin cebolla", "al punto"). El plan lo pide explicito:
    -- "easily convey and display special requests or dietary restrictions".
    notas             text,

    -- Traza del movimiento de inventario que genero esta linea al pedirse.
    -- Guarda lo que devolvio fn_descontar_venta_enrutada: de que almacen salio,
    -- que se descontó y en que ubicaciones. Es la prueba de que el cobro NO
    -- debe volver a descontarlo.
    movimiento_stock  jsonb,

    created_at        timestamptz NOT NULL DEFAULT now(),
    started_at        timestamptz,
    ready_at          timestamptz,
    delivered_at      timestamptz,
    updated_at        timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.app_dat_comanda_item IS
    'Linea de comanda: un plato a preparar, con su cantidad y su estado propio.';
COMMENT ON COLUMN public.app_dat_comanda_item.id_item_cuenta IS
    'Linea de cuenta origen. NO unico: la cuenta consolida, la comanda no.';
COMMENT ON COLUMN public.app_dat_comanda_item.movimiento_stock IS
    'Resultado de fn_descontar_venta_enrutada al pedir. Prueba de que ya se descontó.';

CREATE INDEX IF NOT EXISTS idx_comanda_item_comanda
    ON public.app_dat_comanda_item (id_comanda);

CREATE INDEX IF NOT EXISTS idx_comanda_item_cuenta
    ON public.app_dat_comanda_item (id_item_cuenta)
 WHERE id_item_cuenta IS NOT NULL;


-- ----------------------------------------------------------------------------
-- 13.4 Campos de servicio en app_dat_mesa_cuenta_item
--
-- Los cuatro que pide el plan (2.1), mas uno.
--
-- origen_stock guarda la clasificacion que resolvio fn_resolver_origen_venta al
-- pedir: 'tpv' (barra), 'tanda', 'al_pedido' o 'servicio'. Se congela en la
-- linea porque el cobro necesita saber que se hizo AL PEDIR, no lo que se
-- resolveria ahora (la cocina pudo desactivarse entretanto).
--
-- El campo extra es stock_movido: la bandera explicita de "esta linea ya
-- descontó inventario". Podria inferirse de origen_stock IS NOT NULL, pero
-- tenerlo aparte hace que el cobro sea una comprobacion trivial y auditable, y
-- permite el caso "linea agregada antes de aplicar la Fase 2" (NULL = legado,
-- se descuenta al cobrar como siempre).
-- ----------------------------------------------------------------------------
ALTER TABLE public.app_dat_mesa_cuenta_item
    ADD COLUMN IF NOT EXISTS origen_stock text
        CHECK (origen_stock IN ('tpv', 'tanda', 'al_pedido', 'servicio')),
    ADD COLUMN IF NOT EXISTS id_cocina bigint
        REFERENCES public.app_dat_cocina(id),
    ADD COLUMN IF NOT EXISTS id_comanda_item bigint
        REFERENCES public.app_dat_comanda_item(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS estado_servicio smallint
        CHECK (estado_servicio BETWEEN 1 AND 5),
    ADD COLUMN IF NOT EXISTS stock_movido boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.app_dat_mesa_cuenta_item.origen_stock IS
    'Clasificacion al pedir: tpv | tanda | al_pedido | servicio. NULL = linea legado.';
COMMENT ON COLUMN public.app_dat_mesa_cuenta_item.estado_servicio IS
    'Espejo del estado de la comanda, para pintar la nota del mesero.';
COMMENT ON COLUMN public.app_dat_mesa_cuenta_item.stock_movido IS
    'true si el inventario ya se descontó al pedir. El cobro NO debe repetirlo.';

CREATE INDEX IF NOT EXISTS idx_cuenta_item_comanda
    ON public.app_dat_mesa_cuenta_item (id_comanda_item)
 WHERE id_comanda_item IS NOT NULL;


-- ----------------------------------------------------------------------------
-- 13.5 Trigger de updated_at
--
-- Las dos tablas nuevas siguen la convencion del esquema. Se reusa el patron
-- de trigger que ya existe para otras tablas en vez de inventar otro.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_comanda_touch()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_comanda_updated ON public.app_dat_comanda;
CREATE TRIGGER trg_comanda_updated
    BEFORE UPDATE ON public.app_dat_comanda
    FOR EACH ROW EXECUTE FUNCTION public.trg_comanda_touch();

DROP TRIGGER IF EXISTS trg_comanda_item_updated ON public.app_dat_comanda_item;
CREATE TRIGGER trg_comanda_item_updated
    BEFORE UPDATE ON public.app_dat_comanda_item
    FOR EACH ROW EXECUTE FUNCTION public.trg_comanda_touch();


-- ----------------------------------------------------------------------------
-- 13.6 Coherencia cocina <-> tienda
--
-- Igual que el trigger del 07 para tpv_cocina: impedir que una comanda apunte a
-- una cocina de otra tienda. Es el tipo de error que solo aparece con dos
-- tiendas en produccion y entonces ya hay datos sucios.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_validar_comanda_cocina()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_tienda_cocina bigint;
BEGIN
    SELECT id_tienda INTO v_tienda_cocina
      FROM public.app_dat_cocina
     WHERE id = NEW.id_cocina;

    IF v_tienda_cocina IS NULL THEN
        RAISE EXCEPTION 'La cocina % no existe', NEW.id_cocina
            USING ERRCODE = 'P0001';
    END IF;

    IF v_tienda_cocina <> NEW.id_tienda THEN
        RAISE EXCEPTION
            'La cocina % pertenece a la tienda %, no a la %',
            NEW.id_cocina, v_tienda_cocina, NEW.id_tienda
            USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_comanda_cocina_tienda ON public.app_dat_comanda;
CREATE TRIGGER trg_comanda_cocina_tienda
    BEFORE INSERT OR UPDATE OF id_cocina, id_tienda ON public.app_dat_comanda
    FOR EACH ROW EXECUTE FUNCTION public.trg_validar_comanda_cocina();


-- ============================================================================
-- VERIFICACION
-- ============================================================================

-- (a) Las dos tablas nuevas deben existir -> 2 filas
SELECT c.relname AS tabla,
       (SELECT count(*) FROM pg_attribute a
         WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped) AS columnas
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public'
   AND c.relname IN ('app_dat_comanda', 'app_dat_comanda_item')
 ORDER BY c.relname;

-- (b) Los 5 campos nuevos del item de cuenta -> 5 filas
SELECT a.attname AS columna,
       format_type(a.atttypid, a.atttypmod) AS tipo
  FROM pg_attribute a
  JOIN pg_class c ON c.oid = a.attrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public'
   AND c.relname = 'app_dat_mesa_cuenta_item'
   AND a.attname IN ('origen_stock', 'id_cocina', 'id_comanda_item',
                     'estado_servicio', 'stock_movido')
 ORDER BY a.attnum;

-- (c) Indices creados -> 6 filas
SELECT indexname, tablename
  FROM pg_indexes
 WHERE schemaname = 'public'
   AND indexname IN (
        'idx_comanda_cocina_activa', 'idx_comanda_cuenta',
        'idx_comanda_tienda_fecha', 'idx_comanda_item_comanda',
        'idx_comanda_item_cuenta', 'idx_cuenta_item_comanda'
   )
 ORDER BY tablename, indexname;

-- (d) Triggers -> 3 filas
SELECT c.relname AS tabla, t.tgname AS trigger_
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE NOT t.tgisinternal
   AND n.nspname = 'public'
   AND c.relname IN ('app_dat_comanda', 'app_dat_comanda_item')
 ORDER BY c.relname, t.tgname;


-- ----------------------------------------------------------------------------
-- PRUEBA FUNCIONAL (transaccion revertida)
--
-- Comprueba las reglas que el schema debe garantizar por si mismo, sin
-- necesidad de la logica del 14.
-- ----------------------------------------------------------------------------
/*
BEGIN;

    SELECT public.fn_crear_cocina(11, 'PRUEBA Cocina 13') AS cocina;

    -- 1. Comanda valida
    INSERT INTO app_dat_comanda (id_tienda, id_cocina, id_mesa, id_tpv, numero)
    SELECT 11, c.id, 1, 18, 1
      FROM app_dat_cocina c WHERE c.denominacion = 'PRUEBA Cocina 13'
    RETURNING id, estado, created_at;
    -- esperado: 1 fila, estado 1 (pendiente)

    -- 2. Item de comanda
    INSERT INTO app_dat_comanda_item
        (id_comanda, id_producto, denominacion, cantidad, modo_elaboracion, notas)
    SELECT co.id, 219, 'croqueta', 2, 'al_pedido', 'sin sal'
      FROM app_dat_comanda co
      JOIN app_dat_cocina c ON c.id = co.id_cocina
     WHERE c.denominacion = 'PRUEBA Cocina 13'
    RETURNING id, estado, cantidad;
    -- esperado: 1 fila, estado 1, cantidad 2

    -- 3. Estado invalido debe fallar
    DO $$
    BEGIN
        UPDATE app_dat_comanda SET estado = 9
         WHERE id = (SELECT max(id) FROM app_dat_comanda);
        RAISE EXCEPTION 'FALLO: acepto estado 9';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK: rechazo estado fuera de rango';
    END $$;

    -- 4. Cantidad cero debe fallar
    DO $$
    BEGIN
        INSERT INTO app_dat_comanda_item
            (id_comanda, id_producto, denominacion, cantidad)
        SELECT max(id), 219, 'croqueta', 0 FROM app_dat_comanda;
        RAISE EXCEPTION 'FALLO: acepto cantidad 0';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK: rechazo cantidad no positiva';
    END $$;

    -- 5. modo_elaboracion invalido debe fallar
    DO $$
    BEGIN
        INSERT INTO app_dat_comanda_item
            (id_comanda, id_producto, denominacion, cantidad, modo_elaboracion)
        SELECT max(id), 219, 'croqueta', 1, 'inventado' FROM app_dat_comanda;
        RAISE EXCEPTION 'FALLO: acepto modo inventado';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK: rechazo modo_elaboracion invalido';
    END $$;

    -- 6. El trigger debe rechazar cocina de otra tienda
    DO $$
    DECLARE v_otra bigint;
    BEGIN
        SELECT id INTO v_otra FROM app_dat_cocina
         WHERE id_tienda <> 11 AND deleted_at IS NULL LIMIT 1;

        IF v_otra IS NULL THEN
            RAISE NOTICE 'SALTADO: no hay cocinas de otra tienda para probar';
        ELSE
            BEGIN
                INSERT INTO app_dat_comanda (id_tienda, id_cocina)
                VALUES (11, v_otra);
                RAISE EXCEPTION 'FALLO: acepto cocina de otra tienda';
            EXCEPTION WHEN sqlstate 'P0001' THEN
                RAISE NOTICE 'OK: rechazo cocina de otra tienda';
            END;
        END IF;
    END $$;

    -- 7. updated_at debe refrescarse solo
    SELECT id, created_at = updated_at AS iguales_al_crear
      FROM app_dat_comanda ORDER BY id DESC LIMIT 1;

    UPDATE app_dat_comanda SET estado = 2, started_at = now()
     WHERE id = (SELECT max(id) FROM app_dat_comanda);

    SELECT id, updated_at > created_at AS updated_at_avanzo
      FROM app_dat_comanda ORDER BY id DESC LIMIT 1;
    -- esperado: true

    -- 8. Los campos nuevos del item de cuenta aceptan los valores esperados
    UPDATE app_dat_mesa_cuenta_item
       SET origen_stock = 'al_pedido',
           estado_servicio = 1,
           stock_movido = true,
           id_cocina = (SELECT id FROM app_dat_cocina
                         WHERE denominacion = 'PRUEBA Cocina 13')
     WHERE id = 1
    RETURNING id, origen_stock, estado_servicio, stock_movido;

    -- 9. origen_stock invalido debe fallar
    DO $$
    BEGIN
        UPDATE app_dat_mesa_cuenta_item SET origen_stock = 'inventado' WHERE id = 1;
        RAISE EXCEPTION 'FALLO: acepto origen_stock invalido';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK: rechazo origen_stock invalido';
    END $$;

    -- 10. Borrar la linea de cuenta NO debe borrar la comanda_item
    --     (ON DELETE SET NULL: la cocina pudo haberlo cocinado ya)
    INSERT INTO app_dat_comanda_item
        (id_comanda, id_item_cuenta, id_producto, denominacion, cantidad)
    SELECT max(id), 1, 219, 'croqueta', 1 FROM app_dat_comanda
    RETURNING id AS item_ligado;

    DELETE FROM app_dat_mesa_cuenta_item WHERE id = 1;

    SELECT count(*) AS comanda_items_vivos,
           count(id_item_cuenta) AS con_linea_de_cuenta
      FROM app_dat_comanda_item;
    -- esperado: comanda_items_vivos > 0 y con_linea_de_cuenta = 0
    -- La comanda sobrevive huerfana, no desaparece en silencio.

ROLLBACK;
*/

-- Tras el ROLLBACK: 0 filas
-- SELECT id, denominacion FROM app_dat_cocina WHERE denominacion LIKE 'PRUEBA%';
-- SELECT count(*) FROM app_dat_comanda;
