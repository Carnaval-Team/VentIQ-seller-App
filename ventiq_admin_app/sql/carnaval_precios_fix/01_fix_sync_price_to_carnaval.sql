-- =============================================================
-- CARNAVAL - Precios: el trigger deja de imponer 5.35% / 11%
--
-- 01_fix_sync_price_to_carnaval
--
-- Aplicar en: Supabase > SQL Editor
-- Idempotente: CREATE OR REPLACE (no toca tablas ni datos).
--
--
-- PROBLEMA DIAGNOSTICADO
-- ----------------------
-- public.app_dat_precio_venta tiene el trigger
-- trigger_sync_price_to_carnaval (AFTER INSERT OR UPDATE) que
-- llama a sync_price_to_carnaval(). Esa funcion tenia los
-- porcientos HARDCODEADOS:
--
--     precio_descuento := ROUND(base * 1.0535)   -- +5.35%
--     price            := base * 1.11            -- +11%
--
-- Ignoraba app_dat_precio_general_tienda, que es justamente la
-- tabla que edita la app (vista de gestion de precios). Por eso
-- la tienda 177, configurada a 5% / 30%, veia sus productos
-- volver al 11% cada vez que alguien tocaba un precio de venta:
-- cualquier UPDATE sobre app_dat_precio_venta disparaba el
-- trigger y recalculaba con el 11% fijo.
--
-- Comprobado en produccion (tienda 177, 245 productos ligados):
--   213 productos al 30% (config real, puestos el 07/08)
--    16 productos al 11% exacto, con carnavalapp.Productos
--       .updated_at igual a la fecha en que se les toco el
--       precio de venta -> la firma del trigger.
--   Ej: base 210 -> price 233.1 (=210*1.11) y
--       precio_descuento 221 (=ROUND(210*1.0535)).
--
--
-- DOS BUGS ADICIONALES QUE SE CORRIGEN
-- ------------------------------------
-- 1. La condicion era una tautologia y nunca entraba al ELSE:
--
--        IF v_id_tienda != 1 or v_id_tienda != 177 THEN
--
--    Todo numero es distinto de 1 O distinto de 177, asi que
--    siempre era TRUE. El caso especial "tiendas 1 y 177 cobran
--    el efectivo igual al precio base" nunca funciono. Ya no
--    hace falta: si una tienda quiere efectivo = base, pone 0
--    en su porciento y la config manda.
--
-- 2. No excluia los productos con proveedor = 3, que estan
--    bloqueados por el trigger carnavalapp.productos_block_
--    proveedor_3 (RAISE EXCEPTION). Como el sync corre dentro
--    de la misma transaccion, editar el precio de venta de uno
--    de esos productos ABORTA la operacion completa. Afecta a
--    90 productos de la tienda 148 y 1 de la 20.
--    fn_update_carnaval_product_prices ya los excluia; ahora
--    este sync tambien.
--
--
-- QUE NO CAMBIA
-- -------------
-- - No se toca ninguna tabla, ni el trigger, ni codigo Dart.
-- - Las 21 tiendas con productos ligados que NO tienen fila en
--   app_dat_precio_general_tienda siguen con 5.35% / 11% por
--   defecto: para ellas el comportamiento es el de hoy.
-- - El precio manual desde la vista de precios de Carnaval
--   sigue siendo un ajuste puntual: si luego cambia el precio
--   de venta en Inventtia, el trigger lo recalcula (decision
--   confirmada por el usuario).
--
-- QUE SI CAMBIA, A PROPOSITO
-- --------------------------
-- - Los porcientos salen de app_dat_precio_general_tienda de la
--   tienda del producto (precio_venta_carnaval = efectivo,
--   precio_venta_carnaval_transferencia = transferencia).
-- - `price` ahora se redondea igual que precio_descuento, para
--   que el trigger y el cambio global/selectivo de precios
--   (rpc_apply_*_price_change, que ya usaban ROUND) produzcan
--   EL MISMO numero. Antes el trigger dejaba 233.1 y el cambio
--   global 233 para el mismo producto.
-- - Tienda 177: su efectivo pasa de 5.35% (hardcodeado) a 5%
--   (su config real). Diferencia de 0.35 puntos.
-- =============================================================


-- -------------------------------------------------------------
-- Porcientos de Carnaval aplicables a una tienda.
--
-- Devuelve el par (efectivo, transferencia). Si la tienda no
-- tiene configuracion, devuelve los valores historicos que el
-- trigger tenia hardcodeados, para no alterar el comportamiento
-- de las tiendas que hoy funcionan con ellos.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_carnaval_porcientos_tienda(
    p_id_tienda BIGINT,
    OUT o_pct_efectivo      NUMERIC,
    OUT o_pct_transferencia NUMERIC
)
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    -- Se leen en variables aparte y solo se copian a los OUT si
    -- la tienda tiene fila. Un SELECT INTO sin resultados pone
    -- las variables destino en NULL: no conserva lo que tenian
    -- antes. Asignar los defaults primero NO alcanza.
    v_efectivo      NUMERIC;
    v_transferencia NUMERIC;
BEGIN
    -- Valores por defecto = los que el trigger usaba fijos.
    o_pct_efectivo      := 5.35;
    o_pct_transferencia := 11;

    IF p_id_tienda IS NULL THEN
        RETURN;
    END IF;

    SELECT pg.precio_venta_carnaval,
           pg.precio_venta_carnaval_transferencia
      INTO v_efectivo, v_transferencia
      FROM public.app_dat_precio_general_tienda pg
     WHERE pg.id_tienda = p_id_tienda
     LIMIT 1;

    IF NOT FOUND THEN
        RETURN;   -- tienda sin configuracion: se queda con los defaults
    END IF;

    -- Una columna nula en la config tampoco debe anular el precio.
    o_pct_efectivo      := COALESCE(v_efectivo, o_pct_efectivo);
    o_pct_transferencia := COALESCE(v_transferencia, o_pct_transferencia);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_carnaval_porcientos_tienda(BIGINT)
    TO anon, authenticated, service_role;


-- -------------------------------------------------------------
-- Trigger de sincronizacion de precios hacia Carnaval.
--
-- Se mantiene el mismo nombre, la misma firma y el mismo
-- trigger (trigger_sync_price_to_carnaval): solo cambia de
-- donde salen los porcientos.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_price_to_carnaval()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_id_vendedor_app   BIGINT;
    v_id_tienda         BIGINT;
    v_base_price        NUMERIC;
    v_pct_efectivo      NUMERIC;
    v_pct_transferencia NUMERIC;
    v_precio_descuento  NUMERIC;
    v_precio_oficial    NUMERIC;
BEGIN
    IF TG_OP NOT IN ('INSERT', 'UPDATE') THEN
        RETURN NEW;
    END IF;

    v_base_price := NEW.precio_venta_cup;

    -- Sin precio base no hay nada que sincronizar.
    IF v_base_price IS NULL OR v_base_price <= 0 THEN
        RETURN NEW;
    END IF;

    SELECT p.id_vendedor_app, p.id_tienda
      INTO v_id_vendedor_app, v_id_tienda
      FROM public.app_dat_producto p
     WHERE p.id = NEW.id_producto;

    -- El producto no esta publicado en Carnaval.
    IF v_id_vendedor_app IS NULL THEN
        RETURN NEW;
    END IF;

    -- Porcientos configurados a la tienda (o los historicos).
    SELECT o_pct_efectivo, o_pct_transferencia
      INTO v_pct_efectivo, v_pct_transferencia
      FROM public.fn_carnaval_porcientos_tienda(v_id_tienda);

    -- Cinturon de seguridad: nunca escribir un precio nulo en
    -- Carnaval. Si por lo que sea no hay porcientos, se deja el
    -- precio de Carnaval como estaba.
    IF v_pct_efectivo IS NULL OR v_pct_transferencia IS NULL THEN
        RETURN NEW;
    END IF;

    -- Misma formula que rpc_apply_global_price_change y
    -- rpc_apply_selected_price_change, para que el trigger y el
    -- cambio de precios desde la app coincidan.
    v_precio_descuento := ROUND(v_base_price * (1 + v_pct_efectivo      / 100));
    v_precio_oficial   := ROUND(v_base_price * (1 + v_pct_transferencia / 100));

    -- proveedor = 3 esta bloqueado por
    -- carnavalapp.productos_block_proveedor_3 (RAISE EXCEPTION).
    -- Excluirlo evita abortar la transaccion del precio local.
    UPDATE carnavalapp."Productos"
       SET price            = v_precio_oficial,
           precio_descuento = v_precio_descuento,
           updated_at       = NOW()
     WHERE id = v_id_vendedor_app
       AND COALESCE(proveedor, 0) <> 3;

    RETURN NEW;
END;
$$;


-- =============================================================
-- VERIFICACION
-- =============================================================

-- 1) Las funciones quedaron con la firma esperada y el trigger
--    sigue apuntando a sync_price_to_carnaval.
SELECT p.proname,
       pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('sync_price_to_carnaval', 'fn_carnaval_porcientos_tienda');

SELECT t.tgname, pg_get_triggerdef(t.oid) AS def
FROM pg_trigger t
WHERE t.tgrelid = 'public.app_dat_precio_venta'::regclass
  AND NOT t.tgisinternal;

-- 2) Porcientos que se aplicaran por tienda. Las tiendas sin
--    fila en app_dat_precio_general_tienda deben mostrar
--    5.35 / 11 (el comportamiento historico).
SELECT t.id_tienda,
       (SELECT o_pct_efectivo      FROM public.fn_carnaval_porcientos_tienda(t.id_tienda)) AS pct_efectivo,
       (SELECT o_pct_transferencia FROM public.fn_carnaval_porcientos_tienda(t.id_tienda)) AS pct_transferencia,
       (pg.id_tienda IS NOT NULL)  AS tiene_config,
       COUNT(*)                    AS productos_ligados
FROM (
    SELECT DISTINCT p.id_tienda
    FROM public.app_dat_producto p
    WHERE p.id_vendedor_app IS NOT NULL
      AND p.deleted_at IS NULL
) t
JOIN public.app_dat_producto p2
     ON  p2.id_tienda      = t.id_tienda
     AND p2.id_vendedor_app IS NOT NULL
     AND p2.deleted_at     IS NULL
LEFT JOIN public.app_dat_precio_general_tienda pg ON pg.id_tienda = t.id_tienda
GROUP BY t.id_tienda, pg.id_tienda
ORDER BY t.id_tienda;

-- 3) Desviacion actual por tienda entre el precio de Carnaval y
--    el porciento configurado. Sirve como foto ANTES/DESPUES:
--    tras aplicar este script los productos que se vuelvan a
--    tocar deben caer en pct_real = pct_configurado.
--    (No se corrige el historico: el backfill queda pendiente
--     por decision del usuario.)
WITH base AS (
    SELECT p.id_tienda,
           p.id_vendedor_app,
           (SELECT pv.precio_venta_cup
              FROM public.app_dat_precio_venta pv
             WHERE pv.id_producto = p.id
             ORDER BY pv.created_at DESC
             LIMIT 1) AS precio_cup
    FROM public.app_dat_producto p
    WHERE p.id_vendedor_app IS NOT NULL
      AND p.deleted_at IS NULL
)
SELECT b.id_tienda,
       ROUND((cp.price::numeric / NULLIF(b.precio_cup, 0) - 1) * 100, 0) AS pct_real_transferencia,
       (SELECT o_pct_transferencia FROM public.fn_carnaval_porcientos_tienda(b.id_tienda)) AS pct_configurado,
       COUNT(*) AS productos
FROM base b
JOIN carnavalapp."Productos" cp ON cp.id = b.id_vendedor_app
WHERE b.precio_cup > 0
GROUP BY 1, 2, 3
ORDER BY 1, 4 DESC;

-- 4) Prueba en vivo (opcional, DENTRO de una transaccion para
--    poder deshacerla). Reescribe el mismo precio de un producto
--    de la tienda 177 y comprueba que Carnaval queda al 30%.
--
-- BEGIN;
--   UPDATE public.app_dat_precio_venta
--      SET precio_venta_cup = precio_venta_cup
--    WHERE id = (SELECT pv.id
--                  FROM public.app_dat_precio_venta pv
--                  JOIN public.app_dat_producto p ON p.id = pv.id_producto
--                 WHERE p.id = 5272
--                 ORDER BY pv.created_at DESC LIMIT 1);
--
--   SELECT price, precio_descuento, updated_at
--     FROM carnavalapp."Productos"
--    WHERE id = (SELECT id_vendedor_app FROM public.app_dat_producto WHERE id = 5272);
-- ROLLBACK;
