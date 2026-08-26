-- =============================================================
-- CARNAVAL - Precios: el global pasa a ser PISO (limite inferior)
--
-- 02_piso_global_y_trigger_global
--
-- Aplicar en: Supabase > SQL Editor
-- DESPUES de 01_fix_sync_price_to_carnaval.sql
-- Idempotente: CREATE OR REPLACE (no toca tablas ni datos).
--
--
-- REGLA DE NEGOCIO QUE IMPLEMENTA
-- -------------------------------
-- public.precio_global_productos_carnaval (una sola fila) deja
-- de ser "el porciento que se le aplica a todo el mundo" y pasa
-- a ser el LIMITE INFERIOR: ninguna tienda puede vender en
-- Carnaval por debajo de ese margen.
--
--   porciento final = GREATEST(porciento de la tienda, global)
--   sin config de tienda -> se usa el global tal cual
--
-- Aplica a los dos porcientos por separado (efectivo y
-- transferencia): cada uno tiene su propio piso.
--
--
-- POR QUE HACIA FALTA TOCAR EL TRIGGER DEL GLOBAL
-- -----------------------------------------------
-- fn_update_carnaval_product_prices() (trigger
-- trg_update_carnaval_prices sobre precio_global_productos_
-- carnaval) recorria TODOS los productos ligados de TODAS las
-- tiendas y les imponia el porciento global, ignorando la
-- configuracion individual. Eso explica el episodio del
-- 21/05/2026, cuando decenas de tiendas quedaron al 18% de
-- golpe. Con el piso, editar el global ya no arrasa: solo
-- levanta a quien este por debajo.
--
--
-- IMPACTO MEDIDO ANTES DE APLICAR (global actual 5% / 18%)
-- --------------------------------------------------------
-- El piso SUBE el porciento de transferencia de:
--   - 21 tiendas sin fila en app_dat_precio_general_tienda,
--     que pasan del 11% historico al 18% del piso. Las mayores:
--     147 (95 productos), 148 (92), 152 (68), 153 (68),
--     156 (39), 163 (35), 160 (33), 151 (21), 2 (18), 158 (15).
--   - 3 tiendas configuradas por debajo del piso:
--     146: 5% -> 18%, 45: 11.1% -> 18%, 11: 16% -> 18%.
--
-- NO cambian (ya estan en el piso o encima):
--   177 (30%), 196 (30%), 173 (18%), 174 (18%).
--
-- El cambio no reescribe precios por si solo: cada producto
-- toma el porciento nuevo cuando se le vuelve a tocar el precio
-- de venta, o cuando se edita el global (que si dispara el
-- recalculo masivo por diseno).
--
--
-- DOS DIVERGENCIAS QUE SE UNIFICAN DE PASO
-- ----------------------------------------
-- fn_update_carnaval_product_prices tenia dos criterios propios
-- que daban un precio distinto al del resto del sistema para el
-- mismo producto:
--
-- 1. Tomaba el precio base con
--       WHERE pv.fecha_desde <= CURRENT_DATE
--       ORDER BY pv.fecha_desde DESC
--    mientras sync_price_to_carnaval y las rpc_apply_* usan
--    ORDER BY created_at DESC. Hay filas con created_at de
--    agosto 7 y fecha_desde de agosto 25, asi que los dos
--    criterios NO devuelven la misma fila. Se unifica a
--    created_at DESC.
--
-- 2. Redondeaba la transferencia con
--       CEIL(base * (1+pct/100) / 5) * 5
--    (al alza al multiplo de 5 siguiente) mientras el resto usa
--    ROUND. Se unifica a ROUND, igual que en 01.
--
-- Si el redondeo a multiplo de 5 se quiere de vuelta, debe
-- aplicarse en los tres sitios a la vez, no solo aqui.
-- =============================================================


-- -------------------------------------------------------------
-- Porcientos aplicables a una tienda, con el global como piso.
--
-- Reemplaza la version de 01: misma firma, misma forma de
-- llamarla, pero ahora el suelo lo pone
-- precio_global_productos_carnaval en vez de las constantes
-- historicas 5.35 / 11.
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
    v_piso_efectivo      NUMERIC;
    v_piso_transferencia NUMERIC;
    v_efectivo           NUMERIC;
    v_transferencia      NUMERIC;
BEGIN
    -- Piso global. La tabla tiene una sola fila.
    SELECT g.porciento_efectivo, g.porciento_transferencia
      INTO v_piso_efectivo, v_piso_transferencia
      FROM public.precio_global_productos_carnaval g
     ORDER BY g.id
     LIMIT 1;

    -- Sin fila de global se cae a los valores historicos, para
    -- no dejar la sincronizacion sin porcientos.
    v_piso_efectivo      := COALESCE(v_piso_efectivo, 5.35);
    v_piso_transferencia := COALESCE(v_piso_transferencia, 11);

    o_pct_efectivo      := v_piso_efectivo;
    o_pct_transferencia := v_piso_transferencia;

    IF p_id_tienda IS NULL THEN
        RETURN;
    END IF;

    -- Se lee en variables aparte: un SELECT INTO sin filas pone
    -- los destinos en NULL, no conserva su valor anterior.
    SELECT pg.precio_venta_carnaval,
           pg.precio_venta_carnaval_transferencia
      INTO v_efectivo, v_transferencia
      FROM public.app_dat_precio_general_tienda pg
     WHERE pg.id_tienda = p_id_tienda
     LIMIT 1;

    IF NOT FOUND THEN
        RETURN;   -- sin config: se queda con el global
    END IF;

    -- La tienda puede cobrar mas que el piso, nunca menos.
    o_pct_efectivo      := GREATEST(COALESCE(v_efectivo, v_piso_efectivo),
                                    v_piso_efectivo);
    o_pct_transferencia := GREATEST(COALESCE(v_transferencia, v_piso_transferencia),
                                    v_piso_transferencia);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_carnaval_porcientos_tienda(BIGINT)
    TO anon, authenticated, service_role;


-- -------------------------------------------------------------
-- Recalculo masivo al cambiar el piso global.
--
-- Mismo nombre y mismo trigger (trg_update_carnaval_prices).
-- Ahora respeta la configuracion de cada tienda y solo levanta
-- a los que quedaron por debajo del piso nuevo.
--
-- Se hace en un solo UPDATE con JOIN en vez del bucle fila a
-- fila anterior: mismo resultado, una sola pasada.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_update_carnaval_product_prices()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actualizados INTEGER := 0;
BEGIN
    WITH productos AS (
        SELECT p.id_vendedor_app,
               -- Mismo criterio que sync_price_to_carnaval:
               -- el precio mas reciente por created_at.
               (SELECT pv.precio_venta_cup
                  FROM public.app_dat_precio_venta pv
                 WHERE pv.id_producto = p.id
                 ORDER BY pv.created_at DESC
                 LIMIT 1)                       AS precio_base,
               -- El porciento de la tienda no puede bajar del
               -- global que se acaba de guardar (NEW).
               GREATEST(COALESCE(pg.precio_venta_carnaval,
                                 NEW.porciento_efectivo),
                        NEW.porciento_efectivo)  AS pct_efectivo,
               GREATEST(COALESCE(pg.precio_venta_carnaval_transferencia,
                                 NEW.porciento_transferencia),
                        NEW.porciento_transferencia) AS pct_transferencia
        FROM public.app_dat_producto p
        LEFT JOIN public.app_dat_precio_general_tienda pg
               ON pg.id_tienda = p.id_tienda
        WHERE p.id_vendedor_app IS NOT NULL
          AND p.deleted_at IS NULL
    )
    UPDATE carnavalapp."Productos" cp
       SET price            = ROUND(pr.precio_base * (1 + pr.pct_transferencia / 100)),
           precio_descuento = ROUND(pr.precio_base * (1 + pr.pct_efectivo      / 100)),
           updated_at       = NOW()
      FROM productos pr
     WHERE cp.id = pr.id_vendedor_app
       AND pr.precio_base IS NOT NULL
       AND pr.precio_base > 0
       -- proveedor = 3 esta bloqueado por
       -- carnavalapp.productos_block_proveedor_3 (RAISE EXCEPTION):
       -- incluirlo abortaria toda la operacion.
       AND COALESCE(cp.proveedor, 0) <> 3;

    GET DIAGNOSTICS v_actualizados = ROW_COUNT;
    RAISE NOTICE '[piso_global] Productos recalculados: %.', v_actualizados;

    RETURN NEW;
END;
$$;


-- =============================================================
-- VERIFICACION
-- =============================================================

-- 1) Piso global vigente
SELECT id, porciento_efectivo AS piso_efectivo,
       porciento_transferencia AS piso_transferencia, updated_at
FROM public.precio_global_productos_carnaval
ORDER BY id;

-- 2) Porciento final por tienda y de donde sale. 'PISO' = la
--    tienda estaba por debajo y el global la levanta.
WITH g AS (
    SELECT porciento_efectivo AS piso_ef,
           porciento_transferencia AS piso_tr
    FROM public.precio_global_productos_carnaval
    ORDER BY id LIMIT 1
),
t AS (
    SELECT p.id_tienda, COUNT(*) AS productos
    FROM public.app_dat_producto p
    WHERE p.id_vendedor_app IS NOT NULL
      AND p.deleted_at IS NULL
    GROUP BY p.id_tienda
)
SELECT t.id_tienda,
       t.productos,
       pg.precio_venta_carnaval_transferencia AS pct_configurado,
       g.piso_tr                              AS piso,
       (SELECT o_pct_transferencia
          FROM public.fn_carnaval_porcientos_tienda(t.id_tienda)) AS pct_final,
       CASE
           WHEN pg.id_tienda IS NULL THEN 'SIN CONFIG -> usa el piso'
           WHEN pg.precio_venta_carnaval_transferencia < g.piso_tr THEN 'PISO lo levanta'
           ELSE 'config propia'
       END AS origen
FROM t
CROSS JOIN g
LEFT JOIN public.app_dat_precio_general_tienda pg ON pg.id_tienda = t.id_tienda
ORDER BY t.productos DESC;

-- 3) Ninguna tienda debe quedar por debajo del piso. Esta
--    consulta debe devolver 0 filas.
WITH g AS (
    SELECT porciento_efectivo AS piso_ef,
           porciento_transferencia AS piso_tr
    FROM public.precio_global_productos_carnaval
    ORDER BY id LIMIT 1
)
SELECT t.id_tienda,
       (SELECT o_pct_efectivo      FROM public.fn_carnaval_porcientos_tienda(t.id_tienda)) AS ef,
       (SELECT o_pct_transferencia FROM public.fn_carnaval_porcientos_tienda(t.id_tienda)) AS tr,
       g.piso_ef, g.piso_tr
FROM (
    SELECT DISTINCT p.id_tienda
    FROM public.app_dat_producto p
    WHERE p.id_vendedor_app IS NOT NULL AND p.deleted_at IS NULL
) t
CROSS JOIN g
WHERE (SELECT o_pct_efectivo      FROM public.fn_carnaval_porcientos_tienda(t.id_tienda)) < g.piso_ef
   OR (SELECT o_pct_transferencia FROM public.fn_carnaval_porcientos_tienda(t.id_tienda)) < g.piso_tr;

-- 4) Prueba en vivo del recalculo masivo, DENTRO de una
--    transaccion para poder deshacerla. Reescribe el global con
--    su mismo valor y comprueba que 177 conserva su 30% y una
--    tienda sin config queda en el piso.
--
-- BEGIN;
--   UPDATE public.precio_global_productos_carnaval
--      SET porciento_efectivo      = porciento_efectivo,
--          porciento_transferencia = porciento_transferencia
--    WHERE id = 1;
--
--   -- 177 (config 30%) debe seguir al 30%
--   SELECT cp.price, cp.precio_descuento
--     FROM carnavalapp."Productos" cp
--    WHERE cp.id = (SELECT id_vendedor_app FROM public.app_dat_producto WHERE id = 5272);
-- ROLLBACK;
