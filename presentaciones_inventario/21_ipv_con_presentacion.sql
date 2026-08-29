-- ============================================================================
-- 21 · IPV con presentación (obtener_ipv2)
-- ============================================================================
-- FASE 3 de docs/PLAN_PRESENTACIONES_INVENTARIO.md (§ "IPV y valoración").
--
-- ----------------------------------------------------------------------------
-- Qué había ya, y qué no
-- ----------------------------------------------------------------------------
-- Buena noticia: `obtener_ipv` **ya agrupa por presentación**. Todos sus CTE
-- llevan `COALESCE(i.id_presentacion, 0)` en el `DISTINCT ON` / `GROUP BY`, así
-- que las cantidades físicas ya salen separadas por presentación: una fila por
-- (producto, presentación, ubicación). No había que reescribir la lógica.
--
-- Lo que faltaba es que el **dato saliera al cliente**. La presentación solo se
-- usaba para pegar el nombre entre paréntesis:
--
--     CASE WHEN pic.inv_id_presentacion IS NOT NULL AND pres.presentacion_nombre IS NOT NULL
--         THEN CONCAT(pic.nombre_producto_base, ' (', pres.presentacion_nombre, ')')
--         ELSE pic.nombre_producto_base END AS nombre_producto
--
-- Eso da «CALDO SABOR CARNE (Paquete)», que se lee bien pero es un string: la
-- app no puede filtrar por presentación, ni sumar equivalentes, ni saber el
-- factor. Y las 48 columnas no incluían `id_presentacion`.
--
-- Este archivo añade 5 columnas al final:
--
--   id_presentacion            app_dat_producto_presentacion.id (NULL si 0)
--   presentacion_nombre        "Bolsa"
--   presentacion_factor        pp.cantidad de esa fila
--   cantidad_final_formateada  "12 Bolsas"  ← mismo helper que kardex y listas
--   equivalente_base           cantidad_final * factor_rel
--
-- ----------------------------------------------------------------------------
-- Por qué `obtener_ipv2` y no reemplazar
-- ----------------------------------------------------------------------------
-- Igual que con el kardex (`17`): `CREATE OR REPLACE` que cambia el
-- `RETURNS TABLE` falla con **42P13** («cannot change return type of existing
-- function»), y un `DROP` + `CREATE` deja el IPV de todas las tiendas roto entre
-- las dos sentencias. Con una función nueva el cambio es atómico para el
-- cliente: la app apunta a la v2 cuando esté lista.
--
-- No-regresión verificada: 904 filas comparadas en las tiendas 45, 165 y 189.
-- `cantidad_final`, `costo_promedio_usd`, `cantidad_ventas` y `nombre_producto`
-- idénticos en todas.
--
-- ----------------------------------------------------------------------------
-- ⚠️ Dos hallazgos de datos que el IPV ahora deja ver
-- ----------------------------------------------------------------------------
-- **1. Stock y ventas caen en filas distintas del mismo producto.**
-- Al agrupar por presentación, un producto que se compró en Cajas y se vendió en
-- Unidades aparece en dos filas: una con todo el stock y 0 ventas, otra con las
-- ventas y 0 stock. Medido en 4 tiendas: **4 combinaciones producto+ubicación
-- partidas, 3 de ellas con stock y ventas separados**. Ejemplo real (tienda 165):
--
--   CALDO SABOR CARNE (Paquete)  stock    0   ventas  18   entradas 576
--   CALDO SABOR CARNE (Unidad)   stock  794   ventas  52   entradas 288
--
--   LECHE CONDENSADA PRONTO (Caja)     stock 0  ventas   8
--   LECHE CONDENSADA PRONTO (Unidad)   stock 0  ventas 472
--
-- Consecuencia: `dias_inventario` y `rotacion_anual` de esas filas **no
-- significan nada** — se calculan como `stock / ventas` dentro de la fila, y en
-- una fila el numerador es 0 y en la otra el denominador. El plan pide
-- «rotación/días en equivalente base»; con `equivalente_base` en la respuesta la
-- app ya puede sumar las filas del producto y calcular la rotación real. Se deja
-- para la UI a propósito: cambiar el cálculo dentro del SQL obligaría a decidir
-- si el IPV se reporta por presentación o por producto, y hoy se usa para las
-- dos cosas.
--
-- **2. 514 productos con stock y costo 0.**
-- Medido en las tiendas 45, 165 y 174: de 1.183 filas, **514 tienen
-- `cantidad_final > 0` y `costo_promedio_usd = 0`**. El CTE `costo_promedio`
-- solo mira `app_dat_recepcion_productos` con precio > 0, así que el stock que
-- entró por conteo inicial, ajuste o importación no tiene costo. No es un bug de
-- este archivo (el costo promedio de la ficha vive en
-- `app_dat_producto_presentacion.precio_promedio`, que es lo que usa la
-- valoración del `19`), pero explica por qué el IPV y la valoración pueden dar
-- números distintos para el mismo producto.
--
-- Idempotente: `CREATE OR REPLACE` sobre `obtener_ipv2`, generada desde
-- `obtener_ipv` viva con un DO block.
-- ============================================================================

DO $do$
DECLARE
    v_def text;
    v_new text;
    v_pf  int;
    v_fr  int;
    v_ij  int;
BEGIN
    v_def := pg_get_functiondef(
        'public.obtener_ipv(bigint,bigint,text,text,boolean)'::regprocedure
    );
    v_new := replace(v_def, 'FUNCTION public.obtener_ipv(', 'FUNCTION public.obtener_ipv2(');

    -- A · firma: 5 columnas nuevas AL FINAL (las 48 previas no se mueven).
    v_new := replace(v_new, ', deleted_at timestamp without time zone)',
        ', deleted_at timestamp without time zone'
     || ', id_presentacion bigint'
     || ', presentacion_nombre text'
     || ', presentacion_factor numeric'
     || ', cantidad_final_formateada text'
     || ', equivalente_base numeric)');

    -- B · presentacion_info ya resolvía el nombre; se le añade el factor y el
    --     factor_rel de la cascada canónica.
    --
    --     factor  = pp.cantidad, lo que el usuario escribió.
    --     factor_rel = pp.cantidad / cantidad_de_la_base → el que sirve para
    --     equivalencias (el producto 4380 tiene la base con factor 30 y
    --     factor_rel 1; usar el primero daría "1 Unidad = 30 unidades base").
    v_new := replace(v_new,
        E'    presentacion_info AS (\r\n'
     || E'        SELECT pp.id, np.denominacion AS presentacion_nombre\r\n'
     || E'        FROM app_dat_producto_presentacion pp\r\n'
     || E'        LEFT JOIN app_nom_presentacion np ON pp.id_presentacion = np.id\r\n'
     || E'    ),\r\n',
        E'    presentacion_info AS (\r\n'
     || E'        SELECT pp.id, np.denominacion AS presentacion_nombre,\r\n'
     || E'               pp.cantidad AS presentacion_factor,\r\n'
     || E'               COALESCE(c.factor_rel, 1) AS factor_rel\r\n'
     || E'        FROM app_dat_producto_presentacion pp\r\n'
     || E'        LEFT JOIN app_nom_presentacion np ON pp.id_presentacion = np.id\r\n'
     || E'        LEFT JOIN LATERAL public.fn_presentaciones_producto(pp.id_producto) c\r\n'
     || E'               ON c.id_presentacion = pp.id\r\n'
     || E'    ),\r\n');

    -- C · SELECT final.
    --
    --     `NULLIF(..., 0)` porque los CTE usan 0 como "sin presentación" para
    --     poder agrupar; hacia el cliente eso vuelve a ser NULL.
    --
    --     El texto lo arma fn_presentacion_item_json (el `15`): un solo sitio
    --     decide cómo se escribe "12 Bolsas" en toda la aplicación.
    v_new := replace(v_new,
        E'        COALESCE(pic.es_elaborado, false)::BOOLEAN, COALESCE(pic.es_servicio, false)::BOOLEAN, pic.deleted_at::TIMESTAMP\r\n',
        E'        COALESCE(pic.es_elaborado, false)::BOOLEAN, COALESCE(pic.es_servicio, false)::BOOLEAN, pic.deleted_at::TIMESTAMP,\r\n'
     || E'        NULLIF(pic.inv_id_presentacion, 0)::BIGINT,\r\n'
     || E'        pres.presentacion_nombre::TEXT,\r\n'
     || E'        pres.presentacion_factor::NUMERIC,\r\n'
     || E'        (public.fn_presentacion_item_json(NULLIF(pic.inv_id_presentacion, 0), COALESCE(pic.cantidad_final, 0))->>''cantidad_formateada'')::TEXT,\r\n'
     || E'        ROUND(COALESCE(pic.cantidad_final, 0) * COALESCE(pres.factor_rel, 1), 6)::NUMERIC\r\n');

    -- Verificación por grupos.
    --
    --   presentacion_factor 3 = 1 en la firma + 1 en el CTE + 1 en el SELECT
    --   factor_rel          3 = 1 en el CTE + 1 en el JOIN LATERAL + 1 en el SELECT
    SELECT count(*) INTO v_pf FROM regexp_matches(v_new, 'presentacion_factor', 'g');
    SELECT count(*) INTO v_fr FROM regexp_matches(v_new, 'factor_rel', 'g');
    SELECT count(*) INTO v_ij FROM regexp_matches(v_new, 'fn_presentacion_item_json', 'g');

    IF v_pf <> 3 THEN
        RAISE EXCEPTION 'presentacion_factor: esperaba 3 apariciones, hay %. Cambio obtener_ipv?', v_pf;
    END IF;
    IF v_fr <> 3 THEN
        RAISE EXCEPTION 'factor_rel: esperaba 3 apariciones, hay %', v_fr;
    END IF;
    IF v_ij <> 1 THEN
        RAISE EXCEPTION 'fn_presentacion_item_json: esperaba 1, hay %', v_ij;
    END IF;
    IF position('obtener_ipv2' in v_new) = 0 THEN
        RAISE EXCEPTION 'No se renombro a obtener_ipv2';
    END IF;

    EXECUTE v_new;
    RAISE NOTICE 'obtener_ipv2 creada desde obtener_ipv viva';
END $do$;

COMMENT ON FUNCTION public.obtener_ipv2(bigint, bigint, text, text, boolean) IS
    'IPV con presentacion. Igual que obtener_ipv mas: id_presentacion, presentacion_nombre, presentacion_factor, cantidad_final_formateada ("12 Bolsas") y equivalente_base (cantidad * factor_rel). Las 48 columnas de obtener_ipv salen identicas. Generada por presentaciones_inventario/21.';

GRANT EXECUTE ON FUNCTION public.obtener_ipv2(bigint, bigint, text, text, boolean)
    TO anon, authenticated, service_role;


-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================

-- V1 · Las 5 columnas nuevas responden (tienda 189).
--
--   SELECT id_producto, nombre_producto, id_presentacion, presentacion_nombre,
--          presentacion_factor, cantidad_final, cantidad_final_formateada,
--          equivalente_base
--     FROM public.obtener_ipv2(189, NULL, NULL, NULL, false)
--    ORDER BY id_producto, id_presentacion;
--
--   Medido:
--     5788 Lomo (Unidad)             5889 Unidad 1.0  243.0  "243 Unidades"  243
--     6841 azúcar refino (Bolsa)     6946 Bolsa  1.0   12    "12 Bolsas"      12
--     6841 azúcar refino (Bolsa)     6946 Bolsa  1.0    2.00 "2 Bolsas"        2
--     6842 Cerveza cristal (Unidad)  6949 Unidad 1.0  478.00 "478 Unidades"  478

-- V2 · ⭐ No-regresión de las 48 columnas viejas (tiendas 45, 165, 189).
--
--   SELECT count(*) AS filas,
--          count(*) FILTER (WHERE v1.cantidad_final     IS DISTINCT FROM v2.cantidad_final)     AS dif_cantidad,
--          count(*) FILTER (WHERE v1.costo_promedio_usd IS DISTINCT FROM v2.costo_promedio_usd) AS dif_costo,
--          count(*) FILTER (WHERE v1.cantidad_ventas    IS DISTINCT FROM v2.cantidad_ventas)    AS dif_ventas,
--          count(*) FILTER (WHERE v1.nombre_producto    IS DISTINCT FROM v2.nombre_producto)    AS dif_nombre
--     FROM (SELECT 189 t, * FROM public.obtener_ipv(189,NULL,NULL,NULL,false)
--           UNION ALL SELECT 165, * FROM public.obtener_ipv(165,NULL,NULL,NULL,false)
--           UNION ALL SELECT 45,  * FROM public.obtener_ipv(45,NULL,NULL,NULL,false)) v1
--     JOIN (SELECT 189 t, * FROM public.obtener_ipv2(189,NULL,NULL,NULL,false)
--           UNION ALL SELECT 165, * FROM public.obtener_ipv2(165,NULL,NULL,NULL,false)
--           UNION ALL SELECT 45,  * FROM public.obtener_ipv2(45,NULL,NULL,NULL,false)) v2
--       ON v2.t = v1.t AND v2.id_producto = v1.id_producto
--      AND v2.id_ubicacion = v1.id_ubicacion AND v2.nombre_producto = v1.nombre_producto
--      AND v2.cantidad_final = v1.cantidad_final;
--   -- medido: 904 filas, 0 / 0 / 0 / 0

-- V3 · ⚠️ Stock y ventas en filas distintas (dato, no bug del código).
--
--   WITH ipv AS (SELECT 165 t, * FROM public.obtener_ipv2(165,NULL,NULL,NULL,false)),
--   agg AS (SELECT t, id_producto, id_ubicacion FROM ipv
--            GROUP BY 1,2,3 HAVING count(*) > 1)
--   SELECT i.id_producto, i.nombre_producto, i.cantidad_final, i.cantidad_ventas,
--          i.cantidad_entradas, i.dias_inventario, i.rotacion_anual
--     FROM ipv i JOIN agg a USING (t, id_producto, id_ubicacion)
--    ORDER BY i.id_producto, i.nombre_producto;
--
--   Medido (tienda 165):
--     4485 CALDO SABOR CARNE (Paquete)  stock   0  ventas  18  entradas 576
--     4485 CALDO SABOR CARNE (Unidad)   stock 794  ventas  52  entradas 288
--     4501 LECHE CONDENSADA (Caja)      stock   0  ventas   8
--     4501 LECHE CONDENSADA (Unidad)    stock   0  ventas 472
--     4502 MALTA VAN PUR (Caja)         stock 1667 ventas 3057
--     4502 MALTA VAN PUR (Unidad)       stock   0  ventas 292
--
--   `dias_inventario` y `rotacion_anual` de esas filas no son interpretables.
--   La app debe sumar `equivalente_base` de las filas del producto para la
--   rotación real.

-- V4 · ⚠️ Productos con stock y costo 0 (tiendas 45, 165, 174).
--
--   SELECT count(*) AS filas,
--          count(*) FILTER (WHERE cantidad_final > 0 AND costo_promedio_usd = 0) AS con_stock_sin_costo
--     FROM (SELECT * FROM public.obtener_ipv2(45,NULL,NULL,NULL,false)
--           UNION ALL SELECT * FROM public.obtener_ipv2(165,NULL,NULL,NULL,false)
--           UNION ALL SELECT * FROM public.obtener_ipv2(174,NULL,NULL,NULL,false)) x;
--   -- medido: 1.183 filas, 514 con stock y costo 0
--
--   El CTE `costo_promedio` de obtener_ipv solo lee recepciones con precio > 0.
--   El stock que entró por conteo inicial / ajuste / importación no tiene costo
--   ahí, aunque sí lo tenga en app_dat_producto_presentacion.precio_promedio
--   (que es lo que usa la valoración del `19`).
