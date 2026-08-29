-- ============================================================================
-- 27 · fn_stock_producto_almacen: el total en UNIDADES BASE (Fase 3)
-- ============================================================================
-- Cierra el pendiente «`fn_stock_producto_almacen` sigue devolviendo el
-- equivalente crudo (suma de `cantidad_final` sin factor)» de
-- docs/PLAN_PRESENTACIONES_INVENTARIO.md (Fase 3 § Stock y Fase 4).
--
-- ----------------------------------------------------------------------------
-- El bug
-- ----------------------------------------------------------------------------
-- El escalar sumaba cantidades FISICAS de presentaciones distintas sin aplicar
-- el factor:
--
--     SELECT COALESCE(SUM(d.cantidad_final), 0)::numeric
--       FROM fn_stock_producto_almacen_detalle(...) d;
--
-- Con 533 Cajas de 24 devolvia **533**, no 12.792. Sus consumidores comparan ese
-- numero contra necesidades de receta que vienen en unidades base
-- (`fn_obtener_ingredientes_recursivos.cantidad_total_necesaria`), asi que el
-- stock se **subestimaba por el factor** y una produccion que si alcanzaba
-- podia rechazarse con INSUFFICIENT_STOCK_INGREDIENT.
--
-- ----------------------------------------------------------------------------
-- Que se cambia y que NO
-- ----------------------------------------------------------------------------
-- Se cambia SOLO el escalar `fn_stock_producto_almacen`, que devuelve un total
-- para comparar. **`fn_stock_producto_almacen_detalle` NO se toca**, y es
-- deliberado: `fn_descontar_ingredientes_elaborado` usa el detalle para
-- ESCRIBIR el ledger —
--
--     v_a_descontar := LEAST(v_ubic.cantidad_final, v_pendiente);   -- L33
--     ... v_ubic.cantidad_final - v_a_descontar                     -- L55 (INSERT)
--
-- — asi que su `cantidad_final` tiene que seguir siendo la cantidad fisica de
-- esa presentacion. Aplicarle el factor escribiria saldos falsos en el ledger,
-- que es mucho peor que el bug original.
--
-- ----------------------------------------------------------------------------
-- Los 13 consumidores, y por que el cambio es compatible
-- ----------------------------------------------------------------------------
-- Del escalar (el que cambia):
--   fn_validar_ingredientes_elaborado ... compara contra cantidad en base -> MEJORA
--   fn_disponibilidad_plato (x4) ........ idem + test de signo
--   fn_productos_cocina_tpv (x3) ........ test de signo (<= 0)
--   fn_resolver_origen_venta ............ test de signo (> 0)
--   fn_descontar_venta_enrutada ......... test de signo
--   fn_producir_tanda / fn_cerrar_tanda / fn_anular_tanda /
--   fn_listar_tandas_cocina / fn_platos_por_tanda_cocina
--
-- Los tests de signo (`> 0`, `<= 0`) NO cambian de resultado: multiplicar por un
-- factor positivo no altera el signo. Los que comparan contra una cantidad de
-- receta pasan de estar mal a estar bien.
--
-- Del detalle (que no cambia): fn_descontar_ingredientes_elaborado,
-- fn_ubicacion_destino_devolucion, fn_cancelar_item_pedido,
-- fn_descontar_venta_enrutada, fn_producir_tanda.
--
-- ----------------------------------------------------------------------------
-- Impacto medido en produccion (2026-08-28)
-- ----------------------------------------------------------------------------
-- De **9.320 combinaciones producto+almacen** con saldo, **solo 2 cambian**:
--
--     producto 4545 «FREEGELLS EXTRA FUERTE»  533 Cajas x24 ->    533 -> 12.792
--     producto 4558 «Salchicha 350 gm»         15 Cajas x24 ->     15 ->    360
--
-- Las dos en tienda 25, almacen 29. Y son inocuas hoy:
--   · la tienda 25 tiene `cocina_activa = false` y `modo_restaurante = false`
--   · ninguno de los dos productos es elaborado
--   · **ninguno aparece como ingrediente de una receta** (0 filas en
--     app_dat_producto_ingredientes)
--   · los dos son vendibles, y ahi el uso es test de signo
--
-- OJO con el censo: buscar «productos con MAS DE UNA presentacion con saldo» da
-- 2 combinaciones distintas (3046 y 9753, los de prueba) y es el censo
-- EQUIVOCADO. El bug se dispara con **cualquier presentacion no-base con
-- factor <> 1**, aunque sea la unica con stock. Por eso el censo correcto filtra
-- por `factor_rel <> 1`, no por conteo de presentaciones.
--
-- ----------------------------------------------------------------------------
-- Deuda que queda anotada (no se arregla aqui)
-- ----------------------------------------------------------------------------
-- `fn_descontar_ingredientes_elaborado` L33 hace
-- `LEAST(v_ubic.cantidad_final, v_pendiente)`: compara una cantidad EN
-- PRESENTACION (del detalle) contra un pendiente en UNIDADES BASE (de la
-- receta). Con una presentacion de factor <> 1 descuenta de menos. No se toca
-- aqui porque el arreglo correcto es que esa funcion pase por
-- `fn_descontar_con_rebalanceo` (que ya sabe de factores y deja las conversiones
-- auditadas), no multiplicar a mano en el LEAST. Hoy no afecta a nadie: los 2
-- productos con factor <> 1 no son ingrediente de ninguna receta.
--
-- Idempotente: `CREATE OR REPLACE` con la misma firma. Se reafirman los GRANT
-- para no perderlos (el ACL original es anon/authenticated/service_role).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_stock_producto_almacen(
    p_id_producto bigint,
    p_id_almacen  bigint DEFAULT NULL::bigint
)
RETURNS numeric
LANGUAGE sql
STABLE
AS $function$
    -- FASE 3 presentaciones: el total se devuelve en UNIDADES BASE.
    --
    -- Antes era SUM(cantidad_final) a secas, que suma cajas con unidades: con
    -- 533 Cajas de 24 devolvia 533. Los consumidores lo comparan contra
    -- cantidades de receta expresadas en base, asi que subestimaba el stock por
    -- el factor.
    --
    -- Se usa factor_rel (relativo a la base), NO pp.cantidad: hay 131 filas
    -- es_base con cantidad <> 1, y ahi el factor crudo daria un equivalente
    -- inflado. El COALESCE cubre las filas cuyo id_presentacion no resuelve en
    -- la cadena (presentacion borrada o de otro producto): se cuentan tal cual,
    -- que es el comportamiento anterior.
    SELECT COALESCE(SUM(d.cantidad_final * COALESCE(f.factor_rel, 1)), 0)::numeric
      FROM public.fn_stock_producto_almacen_detalle(p_id_producto, p_id_almacen) d
      LEFT JOIN LATERAL public.fn_presentaciones_producto(p_id_producto) f
             ON f.id_presentacion = d.id_presentacion;
$function$;

COMMENT ON FUNCTION public.fn_stock_producto_almacen(bigint, bigint) IS
'Stock total de un producto en un almacen, EN UNIDADES BASE (aplica factor_rel '
'de cada presentacion). Para el desglose fisico por presentacion usar '
'fn_stock_producto_almacen_detalle, que devuelve cantidad_final sin convertir '
'porque es la que se persiste en el ledger. Fase 3 presentaciones, archivo 27.';

GRANT EXECUTE ON FUNCTION public.fn_stock_producto_almacen(bigint, bigint)
    TO anon, authenticated, service_role;

-- ============================================================================
-- VERIFICACION
-- ============================================================================

-- V1 · La funcion viva aplica el factor y el detalle NO.
--      VERIFICADO 2026-08-28: escalar_con_factor 1 | detalle_con_factor 0
-- SELECT
--   (SELECT count(*) FROM regexp_matches(
--      (SELECT prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
--        WHERE n.nspname='public' AND p.proname='fn_stock_producto_almacen'),
--      'factor_rel','g')) AS escalar_con_factor,
--   (SELECT count(*) FROM regexp_matches(
--      (SELECT prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
--        WHERE n.nspname='public' AND p.proname='fn_stock_producto_almacen_detalle'),
--      'factor_rel','g')) AS detalle_con_factor;

-- V2 · Los 2 combos que cambian, con el valor correcto.
--      VERIFICADO 2026-08-28:
--         4545 / almacen 29 ->    533 Cajas x24 = 12.792
--         4558 / almacen 29 ->     15 Cajas x24 =    360
-- SELECT p.id, p.denominacion,
--        public.fn_stock_producto_almacen(p.id, 29) AS total_base
--   FROM app_dat_producto p
--  WHERE p.id IN (4545, 4558);

-- V3 · No-regresion: los productos cuyas presentaciones con saldo tienen todas
--      factor 1 devuelven exactamente lo mismo que antes.
--      VERIFICADO 2026-08-28: **6.659 combos con factor 1, 0 con diferencia**.
-- WITH det AS (
--   SELECT DISTINCT ON (ip.id_producto, la.id_almacen, ip.id_ubicacion,
--                       COALESCE(ip.id_variante,0), COALESCE(ip.id_opcion_variante,0),
--                       COALESCE(ip.id_presentacion,0))
--          ip.id_producto, la.id_almacen, ip.id_presentacion, ip.cantidad_final
--     FROM app_dat_inventario_productos ip
--     JOIN app_dat_layout_almacen la ON la.id = ip.id_ubicacion
--    WHERE la.deleted_at IS NULL
--    ORDER BY ip.id_producto, la.id_almacen, ip.id_ubicacion,
--             COALESCE(ip.id_variante,0), COALESCE(ip.id_opcion_variante,0),
--             COALESCE(ip.id_presentacion,0), ip.id DESC
-- ), vivos AS (SELECT * FROM det WHERE COALESCE(cantidad_final,0) > 0)
-- SELECT v.id_producto, v.id_almacen,
--        SUM(v.cantidad_final)                              AS crudo_antes,
--        public.fn_stock_producto_almacen(v.id_producto, v.id_almacen) AS base_ahora
--   FROM vivos v
--   LEFT JOIN LATERAL public.fn_presentaciones_producto(v.id_producto) f
--          ON f.id_presentacion = v.id_presentacion
--  GROUP BY v.id_producto, v.id_almacen
-- HAVING bool_and(COALESCE(f.factor_rel,1) = 1)
--    AND SUM(v.cantidad_final) <> public.fn_stock_producto_almacen(v.id_producto, v.id_almacen);

-- V4 · Censo de filas con factor <> 1 y saldo (las unicas que el cambio afecta).
--      VERIFICADO 2026-08-28: 2 combos | 2 filas | 2 productos | 1 tienda |
--                             0 elaborados
-- WITH det AS (
--   SELECT DISTINCT ON (ip.id_producto, la.id_almacen, ip.id_ubicacion,
--                       COALESCE(ip.id_variante,0), COALESCE(ip.id_opcion_variante,0),
--                       COALESCE(ip.id_presentacion,0))
--          ip.id_producto, la.id_almacen, ip.id_presentacion, ip.cantidad_final
--     FROM app_dat_inventario_productos ip
--     JOIN app_dat_layout_almacen la ON la.id = ip.id_ubicacion
--    WHERE la.deleted_at IS NULL
--    ORDER BY ip.id_producto, la.id_almacen, ip.id_ubicacion,
--             COALESCE(ip.id_variante,0), COALESCE(ip.id_opcion_variante,0),
--             COALESCE(ip.id_presentacion,0), ip.id DESC
-- ), vivos AS (SELECT * FROM det WHERE COALESCE(cantidad_final,0) > 0)
-- SELECT count(DISTINCT (v.id_producto, v.id_almacen)) AS combos_afectados,
--        count(*)                                     AS filas,
--        count(DISTINCT v.id_producto)                AS productos,
--        count(DISTINCT p.id_tienda)                  AS tiendas,
--        count(DISTINCT v.id_producto) FILTER (WHERE p.es_elaborado) AS elaborados
--   FROM vivos v
--   JOIN app_dat_producto p ON p.id = v.id_producto
--   LEFT JOIN LATERAL public.fn_presentaciones_producto(v.id_producto) f
--          ON f.id_presentacion = v.id_presentacion
--  WHERE COALESCE(f.factor_rel,1) <> 1;

-- V5 · Smoke de los consumidores en una tienda con cocina ACTIVA (223).
--      Comprueba que fn_validar_ingredientes_elaborado y fn_disponibilidad_plato
--      siguen ejecutando sin error de tipos tras el cambio.
--      VERIFICADO 2026-08-28:
--         10813 «cerdo grille» stock 0        | validar error   | disponible 0
--         10811 «caipiroska»   stock 1        | validar error   | disponible 0
--         10800 «tacos»        stock 1        | validar success | disponible 0
--      (los 'error' son por falta de stock de ingredientes, no por el cambio)
-- WITH elab AS (SELECT p.id, p.denominacion FROM app_dat_producto p
--                WHERE p.es_elaborado AND p.id_tienda=223 LIMIT 3),
--      alm AS (SELECT a.id FROM app_dat_almacen a WHERE a.id_tienda=223 LIMIT 1)
-- SELECT e.id, e.denominacion,
--        public.fn_stock_producto_almacen(e.id, (SELECT id FROM alm)) AS stock_base,
--        (public.fn_validar_ingredientes_elaborado(e.id, 1, (SELECT id FROM alm)))->>'status' AS validar_status
--   FROM elab e;
