-- ============================================================================
-- 26 · fn_inventario_detallado_optimizado: reservado por presentacion + fan-out
--      del precio de venta
-- ============================================================================
-- Cierra el pendiente «fn_inventario_detallado_optimizado — 37 menciones de
-- id_presentacion, sin auditar» de docs/PLAN_PRESENTACIONES_INVENTARIO.md.
--
-- Resultado de la auditoria: la funcion esta BIEN en lo principal. Los cuatro
-- CTE de movimientos (entradas_periodo, extracciones_periodo, ventas_periodo,
-- costo_promedio_productos) agrupan por COALESCE(id_presentacion, 0) y sus
-- cuatro LEFT JOIN casan por esa clave; el DISTINCT ON del saldo tambien la
-- incluye. NO aplana a la presentacion base.
--
-- Pero tiene DOS bugs, los dos medidos contra produccion.
--
-- ----------------------------------------------------------------------------
-- BUG 1 · el stock reservado se cuenta DOS VECES (este si es de presentaciones)
-- ----------------------------------------------------------------------------
-- `stock_reservado` es el unico CTE que NO agrupa por presentacion:
--
--     SELECT ep.id_producto, id_variante, id_opcion_variante, ep.id_ubicacion,
--            SUM(ep.cantidad) AS reservado
--       ...
--      GROUP BY ep.id_producto, ..., ep.id_ubicacion      -- <- sin presentacion
--
-- y su JOIN tampoco la incluye. Cuando un producto tiene dos presentaciones con
-- saldo en la MISMA ubicacion, la fila de reservado casa con las dos y el
-- total se duplica.
--
-- Medido en produccion:
--     combinaciones producto+ubicacion afectadas ......      3
--     filas que reciben el reservado ..................      6
--     reservado real .................................. 15.460,30
--     reservado que reportaba la funcion .............. 30.920,60   (x2 exacto)
--
-- Los 3 casos: producto 9753 «fer» (tienda 179, ubicacion 192, 15.000),
-- 3046 «aaa» (tienda 69, ubicacion 110, 77) y 217 «azucar refino»
-- (tienda 11, ubicacion 37, 383,30).
--
-- A diferencia de otros pendientes del plan, este NO es «hoy inocuo»: ya esta
-- mal con los datos actuales.
--
-- ----------------------------------------------------------------------------
-- BUG 2 · fan-out del precio de venta (NO es de presentaciones, es peor)
-- ----------------------------------------------------------------------------
-- `productos_base` hace:
--
--     LEFT JOIN app_dat_precio_venta pv ON p.id = pv.id_producto
--         AND (pv.id_variante IS NULL OR pv.id_variante = 0)
--         AND (pv.fecha_hasta IS NULL OR pv.fecha_hasta >= CURRENT_DATE)
--
-- sin desempatar. Si el producto tiene varias filas de precio ACTIVAS a la vez,
-- el JOIN casa con TODAS y el SELECT DISTINCT no las colapsa, porque el precio
-- difiere en cada una. Cada fila de precio multiplica todas las filas de
-- inventario del producto.
--
-- Medido: el producto 217 tiene **7 filas** con fecha_hasta IS NULL y precios
-- 196 / 104,18 / 99,22 / 94,50 / 94,50 / 105 / 100. La funcion devolvia
-- **18 filas** donde debian ser 6 (3 combinaciones con saldo x 6 precios
-- distintos), todas identicas en cantidad y reservado.
--
-- Alcance del problema de datos (no de esta funcion):
--     productos con precio activo ...................... 8.798
--     con mas de una fila activa ....................... 2.198
--     con precios DISTINTOS simultaneos ................ 1.040
--     maximo de filas activas en un producto ...........    24
--
-- Se comprobo que las funciones VIVAS no sufren el fan-out porque desempatan
-- con DISTINCT ON o LATERAL. Contra el producto 217:
--     fn_inventory_valuation_rows ........  3 filas   OK
--     obtener_ipv2 .......................  4 filas   OK
--     obtener_ipv (v1) ...................  4 filas   OK
--     fn_inventario_detallado_optimizado .. 18 filas   <- solo esta
--
-- ----------------------------------------------------------------------------
-- Por que este arreglo es seguro
-- ----------------------------------------------------------------------------
-- La funcion NO LA LLAMA NADIE: 0 consumidores en pg_proc.prosrc y 0 en Dart
-- (buscado en los dos proyectos). No puede haber regresion porque no hay nada
-- que regresionar. Se arregla ahora que esta medido, para que no sea una trampa
-- el dia que alguien la conecte a una pantalla.
--
-- ----------------------------------------------------------------------------
-- Metodo
-- ----------------------------------------------------------------------------
-- La funcion tiene 21.806 caracteres y ~425 lineas, con un UNION ALL posicional
-- entre productos_con_inventario y productos_sin_inventario: reescribirla a mano
-- desalinea el UNION y el error sale 200 lineas mas abajo como un cast
-- imposible. Igual que el `17` y el `25`, este archivo NO contiene el cuerpo:
-- es un DO block que baja el pg_get_functiondef vivo, aplica 4 sustituciones y
-- **aborta si alguna no encuentra su anclaje**.
--
-- Idempotente: si ya esta parcheada, las guardas de conteo lo detectan y el
-- bloque sale sin tocar nada.
--
-- ----------------------------------------------------------------------------
-- CORRECCION EN CALIENTE (26b) · el COALESCE(...,0) era peor que el bug
-- ----------------------------------------------------------------------------
-- El primer intento mapeaba `id_presentacion IS NULL` a `0` en stock_reservado.
-- Eso cambio "duplicado" por "PERDIDO": el `0` no casa con ninguna presentacion
-- real, asi que las reservas sin presentacion desaparecian del reporte. Medido
-- en el 217/ubicacion 37, que tiene el reservado partido:
--     presentacion 336 .... 192,15
--     presentacion NULL ... 191,15
--     -> antes del 26: 383,30 duplicado en las 2 filas
--     -> con el 26 solo: 192,15 (los 191,15 se perdian)
--     -> con el 26b:    383,30 correcto
--
-- La causa: `null` NO significa "ninguna presentacion", significa **la
-- presentacion base** (contrato de la Fase 1). Se resuelve con la cascada de
-- `fn_presentaciones_producto`, igual que hace el resto del sistema.
--
-- Alcance del null en reservas pendientes:
--     filas pendientes ....................... 197.903
--     con id_presentacion NULL ...............   2.854  (1,4 %)
--     combos producto+ubicacion afectados ....     149
--        · con UNA sola presentacion .........      72  <- el null ES esa
--        · multipresentacion .................       1  <- el 217/37
--        · sin saldo (no salen en el reporte) .      76
--
-- ----------------------------------------------------------------------------
-- DEUDA QUE SE DEJA A PROPOSITO
-- ----------------------------------------------------------------------------
-- Los otros tres CTE (entradas_periodo, extracciones_periodo, ventas_periodo)
-- tienen el MISMO patron `COALESCE(id_presentacion, 0)` y sus JOIN comparan
-- contra `tp.id_presentacion`, que viene del ledger y nunca es nulo — asi que
-- ahi el `0` tampoco casa nunca y las lineas sin presentacion se pierden.
--
-- NO se arreglan, y la razon es que solo afecta a datos CONGELADOS. Los nulos
-- dejaron de entrar cuando se cerro la Fase 1:
--     2026-08 .. 20.607 filas ..  0 nulos
--     2026-07 .. 23.625 ........  0
--     2026-06 .. 19.371 ........  0
--     2026-05 .. 24.745 ........  0
--     2026-04 .. 22.976 ........ 13  (0,06 %)
--     2026-03 .. 19.267 ........ 33
-- Cuatro meses seguidos sin un solo nulo. De los 2.854 pendientes con null,
-- **2.725 (96 %) son de septiembre-octubre 2025**.
--
-- Arreglar esos tres CTE seria trabajo sobre historico que ya no crece. El
-- reservado si se arreglo porque el `26` lo habia EMPEORADO.
-- ============================================================================

DO $mig$
DECLARE
    v_src   text;
    v_new   text;
    v_n     int;
BEGIN
    v_src := pg_get_functiondef(
        'public.fn_inventario_detallado_optimizado(bigint,date,date,bigint,bigint)'::regprocedure
    );

    -- ¿Ya parcheada? Se comprueban LOS DOS fixes: el LATERAL del precio y la
    -- resolucion del null a la base. Mirar solo uno dejaria el otro sin aplicar
    -- si alguien ejecuto una version intermedia de este archivo.
    IF v_src LIKE '%FASE 3 presentaciones: precio sin fan-out%'
       AND v_src LIKE '%fn_presentaciones_producto(ep.id_producto)%' THEN
        RAISE NOTICE '26: ya aplicado (precio + reservado), no se toca nada';
        RETURN;
    END IF;

    v_new := v_src;

    -- ------------------------------------------------------------------
    -- FIX 1 · precio de venta: LEFT JOIN -> LEFT JOIN LATERAL ... LIMIT 1
    -- ------------------------------------------------------------------
    -- Se elige la fila mas reciente por (fecha_desde, id). No se cambia el
    -- criterio de "activo" (id_variante nulo/0 y fecha_hasta abierta o futura),
    -- solo se deja de multiplicar filas cuando hay varias.
    v_new := regexp_replace(
        v_new,
        'LEFT JOIN app_dat_precio_venta pv ON p\.id = pv\.id_producto\s*\r?\n'
        '\s*AND \(pv\.id_variante IS NULL OR pv\.id_variante = 0\)\s*\r?\n'
        '\s*AND \(pv\.fecha_hasta IS NULL OR pv\.fecha_hasta >= CURRENT_DATE\)',
        E'-- FASE 3 presentaciones: precio sin fan-out.\n'
        '        -- Un LEFT JOIN plano casaba con TODAS las filas de precio\n'
        '        -- activas (2.198 productos tienen mas de una, 1.040 con precios\n'
        '        -- distintos) y multiplicaba las filas de inventario. Se toma\n'
        '        -- solo la mas reciente.\n'
        '        LEFT JOIN LATERAL (\n'
        '            SELECT pv_i.precio_venta_cup\n'
        '              FROM app_dat_precio_venta pv_i\n'
        '             WHERE pv_i.id_producto = p.id\n'
        '               AND (pv_i.id_variante IS NULL OR pv_i.id_variante = 0)\n'
        '               AND (pv_i.fecha_hasta IS NULL OR pv_i.fecha_hasta >= CURRENT_DATE)\n'
        '             ORDER BY pv_i.fecha_desde DESC NULLS LAST, pv_i.id DESC\n'
        '             LIMIT 1\n'
        '        ) pv ON TRUE',
        'g'
    );

    SELECT count(*) INTO v_n FROM regexp_matches(v_new, 'LEFT JOIN LATERAL \(', 'g');
    IF v_n <> 1 THEN
        RAISE EXCEPTION '26 FIX1: se esperaba 1 LEFT JOIN LATERAL, hay %', v_n;
    END IF;

    -- ------------------------------------------------------------------
    -- FIX 2 · stock_reservado: añadir la presentacion al SELECT
    -- ------------------------------------------------------------------
    -- OJO: el null se resuelve a la presentacion BASE, no a 0. Mapearlo a 0
    -- hace que la fila no case con ninguna presentacion real y el reservado
    -- se PIERDA (ver "CORRECCION EN CALIENTE (26b)" en la cabecera).
    v_new := regexp_replace(
        v_new,
        '(\s*)ep\.id_ubicacion,(\s*\r?\n\s*)SUM\(ep\.cantidad\) AS reservado',
        E'\\1ep.id_ubicacion,\\2-- FASE 3: la presentacion entra en la clave. Sin ella, la fila\\2'
        '-- de reservado casaba con TODAS las presentaciones del producto\\2'
        '-- en esa ubicacion y el total se contaba dos veces (medido:\\2'
        '-- 15.460,30 real -> 30.920,60 reportado en 3 combinaciones).\\2'
        '-- El null es la presentacion BASE (contrato Fase 1), no "ninguna".\\2'
        'COALESCE(ep.id_presentacion, (SELECT c.id_presentacion FROM public.fn_presentaciones_producto(ep.id_producto) c WHERE c.es_base LIMIT 1)) AS id_presentacion,\\2'
        'SUM(ep.cantidad) AS reservado',
        'g'
    );

    -- ------------------------------------------------------------------
    -- FIX 3 · stock_reservado: añadir la presentacion al GROUP BY
    -- ------------------------------------------------------------------
    v_new := regexp_replace(
        v_new,
        'GROUP BY ep\.id_producto, COALESCE\(ep\.id_variante, 0\), COALESCE\(ep\.id_opcion_variante, 0\), ep\.id_ubicacion',
        'GROUP BY ep.id_producto, COALESCE(ep.id_variante, 0), COALESCE(ep.id_opcion_variante, 0), ep.id_ubicacion, COALESCE(ep.id_presentacion, (SELECT c.id_presentacion FROM public.fn_presentaciones_producto(ep.id_producto) c WHERE c.es_base LIMIT 1))',
        'g'
    );

    -- ------------------------------------------------------------------
    -- FIX 4 · stock_reservado: añadir la presentacion al JOIN
    -- ------------------------------------------------------------------
    v_new := regexp_replace(
        v_new,
        '(\s*)AND COALESCE\(tp\.id_ubicacion, 0\) = sr\.id_ubicacion',
        E'\\1AND COALESCE(tp.id_ubicacion, 0) = sr.id_ubicacion'
        '\\1AND COALESCE(tp.id_presentacion, 0) = sr.id_presentacion',
        'g'
    );

    -- Guardas de conteo: las 3 piezas del reservado tienen que estar.
    --
    -- Son DOS resoluciones a base (el SELECT y el GROUP BY). Si sale 1, el
    -- regex de una de las dos no encontro su anclaje y el GROUP BY quedaria
    -- inconsistente con el SELECT -> error de agregacion en tiempo de ejecucion.
    SELECT count(*) INTO v_n
      FROM regexp_matches(v_new, 'fn_presentaciones_producto\(ep\.id_producto\)', 'g');
    IF v_n <> 2 THEN
        RAISE EXCEPTION '26 FIX2/3: se esperaban 2 resoluciones a base en stock_reservado, hay %', v_n;
    END IF;

    -- Ningun COALESCE(...,0) puede quedar en stock_reservado: perderia el
    -- reservado de las filas sin presentacion en vez de duplicarlo.
    IF v_new LIKE '%COALESCE(ep.id_presentacion, 0) AS id_presentacion,%' THEN
        RAISE EXCEPTION '26: el SELECT de stock_reservado sigue mapeando el null a 0';
    END IF;

    SELECT count(*) INTO v_n
      FROM regexp_matches(v_new, 'COALESCE\(tp\.id_presentacion, 0\) = sr\.id_presentacion', 'g');
    IF v_n <> 1 THEN
        RAISE EXCEPTION '26 FIX4: se esperaba 1 JOIN con presentacion, hay %', v_n;
    END IF;

    -- El fan-out viejo no puede quedar.
    IF v_new LIKE '%LEFT JOIN app_dat_precio_venta pv ON p.id = pv.id_producto%' THEN
        RAISE EXCEPTION '26: el LEFT JOIN plano de precio_venta sigue presente';
    END IF;

    -- La firma y el RETURNS TABLE no se tocan: 28 columnas, mismos tipos.
    IF v_new NOT LIKE '%tiene_inventario boolean)%' THEN
        RAISE EXCEPTION '26: el RETURNS TABLE cambio, abortando';
    END IF;

    EXECUTE v_new;
    RAISE NOTICE '26: fn_inventario_detallado_optimizado parcheada (4 fixes)';
END
$mig$;

-- ============================================================================
-- VERIFICACION
-- ============================================================================

-- V1 · Las marcas del parche estan en la funcion viva.
--      VERIFICADO 2026-08-28: lateral_precio 1 | resuelve_base 2 |
--                             join_reservado 1 | fanout_viejo 0 | returns_ok t
-- SELECT
--   (SELECT count(*) FROM regexp_matches(p.prosrc,'LEFT JOIN LATERAL \(','g')) AS lateral_precio,
--   (SELECT count(*) FROM regexp_matches(p.prosrc,'fn_presentaciones_producto\(ep\.id_producto\)','g')) AS resuelve_base,
--   (SELECT count(*) FROM regexp_matches(p.prosrc,'COALESCE\(tp\.id_presentacion, 0\) = sr\.id_presentacion','g')) AS join_reservado,
--   (SELECT count(*) FROM regexp_matches(p.prosrc,'LEFT JOIN app_dat_precio_venta pv ON p\.id','g')) AS fanout_viejo,
--   pg_get_function_result(p.oid) LIKE '%tiene_inventario boolean)' AS returns_ok
-- FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
-- WHERE n.nspname='public' AND p.proname='fn_inventario_detallado_optimizado';

-- V2 · Producto 217 (7 precios activos, 2 presentaciones, 3 ubicaciones con saldo).
--      Antes del parche: 18 filas (3 combinaciones x 6 precios distintos) con el
--      reservado duplicado.
--      VERIFICADO 2026-08-28 -> 3 filas:
--         ubic 37: cant 100,0 | reservado 383,30 | disp 0    | precio 196,00
--         ubic 40: cant  18,0 | reservado   2,00 | disp 16,0 | precio 196,00
--         ubic 41: cant   3,0 | reservado   0    | disp  3,0 | precio 196,00
-- SELECT id_ubicacion, cantidad_final, stock_reservado, stock_disponible,
--        precio_venta_cup
--   FROM public.fn_inventario_detallado_optimizado(11, NULL, NULL, NULL, 217)
--  ORDER BY id_ubicacion, cantidad_final;

-- V3 · El reservado total ya no se duplica en las 3 combinaciones medidas.
--      VERIFICADO 2026-08-28: reportado = real en las tres.
--         producto 217  ubic  37 -> real    383,30 | reportado    383,30
--         producto 3046 ubic 110 -> real     77    | reportado     77
--         producto 9753 ubic 192 -> real 15.000    | reportado 15.000
-- WITH saldos AS (
--   SELECT DISTINCT ON (ip.id_producto, COALESCE(ip.id_variante,0),
--                       COALESCE(ip.id_opcion_variante,0),
--                       COALESCE(ip.id_presentacion,0), COALESCE(ip.id_ubicacion,0))
--          ip.id_producto, ip.id_ubicacion, ip.id_presentacion
--     FROM app_dat_inventario_productos ip
--    WHERE ip.id_ubicacion IS NOT NULL
--    ORDER BY ip.id_producto, COALESCE(ip.id_variante,0),
--             COALESCE(ip.id_opcion_variante,0), COALESCE(ip.id_presentacion,0),
--             COALESCE(ip.id_ubicacion,0), ip.id DESC
-- ), multi AS (
--   SELECT id_producto, id_ubicacion FROM saldos
--    GROUP BY 1,2 HAVING count(*) > 1
-- ), reservas AS (
--   SELECT ep.id_producto, ep.id_ubicacion, SUM(ep.cantidad) AS real_reservado
--     FROM app_dat_extraccion_productos ep
--     JOIN app_dat_operaciones o ON ep.id_operacion=o.id
--     JOIN app_dat_estado_operacion eo ON o.id=eo.id_operacion
--    WHERE eo.estado = 1
--    GROUP BY 1,2
-- )
-- SELECT m.id_producto, m.id_ubicacion, r.real_reservado
--   FROM multi m JOIN reservas r
--     ON r.id_producto=m.id_producto AND r.id_ubicacion=m.id_ubicacion;

-- V4 · Ningun producto de una tienda entera devuelve filas duplicadas por precio.
--      VERIFICADO 2026-08-28 en 3 tiendas: tienda 11 -> 0, tienda 45 -> 0,
--      tienda 47 -> 0 combinaciones duplicadas.
-- SELECT id_producto, id_ubicacion, cantidad_final, count(*) AS repetidas
--   FROM public.fn_inventario_detallado_optimizado(11, NULL, NULL, NULL, NULL)
--  WHERE tiene_inventario
--  GROUP BY 1,2,3
-- HAVING count(*) > 1
--  LIMIT 20;
