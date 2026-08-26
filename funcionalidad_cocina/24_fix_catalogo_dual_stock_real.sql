
-- ============================================================================
-- 24 · FIX del catalogo dual: anti-duplicado por stock REAL, no historico
--
-- Encontrado durante el QA del usuario en la tienda 223 (Restaurant perla
-- negra). Sintoma reportado: "los platos de cocina no aparecen en el vendedor".
--
-- CAUSA
-- -----
-- app_dat_inventario_productos es APPEND-ONLY: cada movimiento inserta una fila
-- nueva con su cantidad_final; el stock actual es el ultimo movimiento por
-- ubicacion/presentacion (que es lo que calcula fn_stock_producto_almacen).
--
-- El anti-duplicado de fn_productos_cocina_tpv (del 09) estaba escrito asi:
--
--   AND NOT EXISTS (
--        SELECT 1 FROM app_dat_inventario_productos ip
--          JOIN app_dat_layout_almacen la ON la.id = ip.id_ubicacion
--         WHERE ip.id_producto = p.id
--           AND la.id_almacen = v_almacen_tpv
--           AND ip.cantidad_final > 0)
--
-- Eso pregunta "ALGUNA VEZ tuvo stock en la barra", no "tiene stock AHORA".
--
-- MEDIDO en la tienda 223, producto 10813 'cerdo grille' (almacen de barra 331):
--
--   fin=1 origen=1 15:03  -> entrada
--   fin=1 origen=3 15:21
--   fin=0 origen=4 16:05  -> venta, queda en CERO
--   fin=0 origen=3 16:05
--
-- Stock real = 0, pero la fila historica de las 15:03 con cantidad_final=1 hace
-- que el EXISTS se cumpla para siempre. Resultado: el plato quedo INVENDIBLE.
-- No salia por barra (stock 0) ni por cocina (excluido por el anti-duplicado),
-- y no habia forma de recuperarlo salvo borrar historico de inventario.
--
-- Es un bug de diseno, no de datos: le pasa a CUALQUIER plato de cocina en
-- cuanto se vende una vez desde la barra. La tienda 11 no lo destapo porque
-- alli los platos nunca tuvieron ficha de inventario en el almacen del TPV.
-- ============================================================================

DO $do$
DECLARE
    v_def text; v_new text;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_def
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'fn_productos_cocina_tpv';

    IF v_def IS NULL THEN RAISE EXCEPTION 'fn_productos_cocina_tpv no existe'; END IF;

    IF v_def LIKE '%fn_stock_producto_almacen(p.id, v_almacen_tpv)%' THEN
        RAISE NOTICE 'ya usa el stock real, nada que hacer'; RETURN;
    END IF;

    -- regexp y no replace() literal porque el cuerpo vivo tiene CRLF
    v_new := regexp_replace(
        v_def,
        'AND NOT EXISTS \(\s*SELECT 1\s*FROM app_dat_inventario_productos ip\s*JOIN app_dat_layout_almacen la ON la\.id = ip\.id_ubicacion\s*WHERE ip\.id_producto = p\.id\s*AND la\.id_almacen = v_almacen_tpv\s*AND la\.deleted_at IS NULL\s*AND ip\.cantidad_final > 0\s*\)',
        'AND fn_stock_producto_almacen(p.id, v_almacen_tpv) <= 0',
        'g'
    );

    IF v_new = v_def THEN
        RAISE EXCEPTION 'el regexp no encontro el predicado anti-duplicado';
    END IF;

    EXECUTE v_new;
    RAISE NOTICE 'fn_productos_cocina_tpv ahora compara el stock real de la barra';
END
$do$;


-- ============================================================================
-- NOTA sobre el lado Dart (ya aplicado en ventiq_app)
--
-- Con el fix, un plato con stock 0 en la barra sale en las DOS RPC: la de barra
-- lo lista porque tiene ficha de inventario (con stock 0), y la de cocina
-- porque su stock de barra es 0. La app concatenaba las dos listas a pelo, asi
-- que aparecia DUPLICADO.
--
-- Se resolvio en product_service.dart con _unirCatalogos(), que descarta la
-- version de barra cuando el mismo id_producto viene por cocina. Gana cocina a
-- proposito: lo que importa es la disponibilidad por receta (32 raciones), no
-- el cero de la barra. Al reves el vendedor veria "agotado" con la despensa
-- llena.
--
-- No se arregla en SQL porque son dos RPC independientes y la union la hace la
-- app; meter aqui la exclusion nos devolveria al bug original.
-- ============================================================================


-- ============================================================================
-- VERIFICACION
-- ============================================================================

-- (a) El predicado quedo cambiado
SELECT CASE WHEN pg_get_functiondef(p.oid) LIKE '%fn_stock_producto_almacen(p.id, v_almacen_tpv)%'
            THEN 'OK usa stock real' ELSE 'FALLO sigue con el EXISTS historico' END AS estado
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'fn_productos_cocina_tpv';

-- (b) Ningun plato de cocina queda invisible por historico en NINGUNA tienda.
--     Antes del fix esta consulta devolvia 'tienda 223: cerdo grille'.
SELECT COALESCE(string_agg(DISTINCT 'tienda ' || p.id_tienda || ': ' || p.denominacion, ', '),
                '(ninguno: correcto)') AS platos_invisibles
  FROM app_dat_producto p
  JOIN app_dat_cocina co ON co.id = p.id_cocina AND co.deleted_at IS NULL AND co.activa
  JOIN app_dat_tpv_cocina tc ON tc.id_cocina = co.id
  JOIN app_dat_tpv t ON t.id = tc.id_tpv
 WHERE p.deleted_at IS NULL AND p.es_vendible
   AND EXISTS (SELECT 1 FROM app_dat_inventario_productos ip
                 JOIN app_dat_layout_almacen la ON la.id = ip.id_ubicacion
                WHERE ip.id_producto = p.id AND la.id_almacen = t.id_almacen
                  AND la.deleted_at IS NULL AND ip.cantidad_final > 0)
   AND public.fn_stock_producto_almacen(p.id, t.id_almacen) <= 0;

-- (c) Comprobacion manual por tienda/TPV: barra y cocina, y su interseccion.
--     Sustituir <TIENDA> y <TPV>. La interseccion NO tiene que estar vacia
--     (para eso esta _unirCatalogos en Dart), pero cada plato debe salir con su
--     disponibilidad de cocina en la app, no con el cero de la barra.
-- SELECT 'cocina' AS lista, denominacion, stock_disponible
--   FROM public.fn_productos_cocina_tpv(NULL, <TIENDA>, <TPV>)
-- UNION ALL
-- SELECT 'barra', denominacion, stock_disponible
--   FROM public.get_productos_by_categoria_tpv_search_meta_v2(<TIENDA>, <TPV>, NULL, NULL, false)
--  ORDER BY denominacion, lista;
