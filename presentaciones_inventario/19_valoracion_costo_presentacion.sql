-- ============================================================================
-- 19 · Valoración de inventario: el costo de la presentación correcta
-- ============================================================================
-- FASE 3 de docs/PLAN_PRESENTACIONES_INVENTARIO.md (§ "Stock" → valoración).
--
-- ----------------------------------------------------------------------------
-- El bug: dos espacios de ids con el mismo nombre
-- ----------------------------------------------------------------------------
-- `fn_inventory_valuation_rows` buscaba el costo así:
--
--     latest_costo AS (
--         SELECT DISTINCT ON (pp.id_producto, pp.id_presentacion)
--                pp.id_producto, pp.id_presentacion, pp.precio_promedio
--           FROM app_dat_producto_presentacion pp
--          WHERE pp.precio_promedio IS NOT NULL AND pp.precio_promedio > 0
--          ORDER BY pp.id_producto, pp.id_presentacion, pp.created_at DESC
--     )
--     ...
--     LEFT JOIN latest_costo lc
--            ON lc.id_producto = li.id_producto
--           AND lc.id_presentacion = li.id_presentacion   -- ← aquí
--
-- `app_dat_producto_presentacion` tiene DOS columnas de id:
--   · `pp.id`              → la fila (producto + presentación + factor). Esto es
--                            lo que el ledger guarda en `id_presentacion`.
--   · `pp.id_presentacion` → FK al nomenclador `app_nom_presentacion`
--                            (1=Unidad, 3=Caja, 4=Bolsa, 7=Bulto...).
--
-- El JOIN comparaba `pp.id_presentacion` (nomenclador, valores 1..~20) contra
-- `li.id_presentacion` (fila, valores en los miles). **Nunca casaban**: medido,
-- 0 de 6.647 filas con stock encontraban su costo por esa vía.
--
-- Como el `LEFT JOIN` no falla, todo caía silenciosamente al fallback:
--
--     latest_costo_fallback AS (
--         SELECT DISTINCT ON (pp.id_producto) pp.id_producto, pp.precio_promedio
--           ... ORDER BY pp.id_producto, pp.created_at DESC
--     )
--
-- que es "el costo de CUALQUIER presentación del producto, la más reciente por
-- created_at". Con todas las presentaciones creadas en el mismo instante (es lo
-- normal: se guardan juntas al crear el producto) ese `DISTINCT ON` elige una
-- **arbitraria**.
--
-- Resultado: **5.861 de 6.647 filas con stock se valoraban con el costo de otra
-- presentación**, no con el suyo.
--
-- Ejemplo medido (tienda 189, producto 6841):
--   fila 6946  Bolsa  factor 1   es_base  precio_promedio 186.64   ← el correcto
--   fila 6947  Bulto  factor 10           precio_promedio   9.80   ← el que usaba
--
--   12 Bolsas en stock:  valor antes  117.60 USD   (12 × 9.80)
--                        valor después 2.239,68 USD (12 × 186.64)
--
-- Un factor 19× en una sola fila. Y no es un error de redondeo en un reporte:
-- estas RPC alimentan `fn_warehouses_valuation_summary`,
-- `fn_warehouse_valuation_zones` y `fn_zone_valuation_products` (las tres la
-- llaman), o sea toda la pantalla de valoración de inventario.
--
-- Nótese que el bug NO era simétrico: el costo elegido podía ser mayor o menor.
-- Otro caso medido: producto 4485, 794 unidades, 0,0525 → 0,048 (el valor baja).
-- Por eso nadie lo detectó: no producía un número absurdo, producía un número
-- plausible y equivocado.
--
-- ----------------------------------------------------------------------------
-- La guarda extra: id_presentacion apuntando a OTRO producto
-- ----------------------------------------------------------------------------
-- Al arreglar el JOIN aparece un riesgo nuevo. Hay **6 filas de inventario con
-- stock (4 productos) cuyo `id_presentacion` es una fila que pertenece a otro
-- producto** — datos corruptos previos:
--
--   producto 3046 "aaa"  (tienda 69)  → id_presentacion 3101, que es del 3017
--   producto 4720 "Pqt Pechuga..."    → id_presentacion 4720, del 4623 (¡un
--                                        BLOWER FAN de otra categoría!)
--   producto 9753 "fer" (tienda 179)  → id_presentacion 9894, del 9757
--
-- Casar solo por `pp.id = li.id_presentacion` le habría dado a esas filas el
-- costo de un producto ajeno. Con `AND lc.id_producto = li.id_producto` no
-- encuentran costo propio y caen al fallback del **mismo** producto, que es lo
-- correcto mientras el dato esté sucio.
--
-- ----------------------------------------------------------------------------
-- Lo que este archivo NO arregla
-- ----------------------------------------------------------------------------
-- **14 productos con stock (20 filas) siguen con costo ambiguo**: su fila de
-- inventario no casa con ninguna presentación con `precio_promedio > 0`, así que
-- dependen del fallback, y tienen varias presentaciones con costos distintos.
-- Para esos el fallback elige por `created_at DESC` y sigue siendo arbitrario.
-- No se puede resolver en SQL: hay que cargarles el costo de su presentación.
-- Consulta de censo al final (V5) para listarlos.
--
-- Idempotente: `CREATE OR REPLACE`, generado desde la función viva con un DO
-- block que aborta si los conteos no dan exactos (igual que el 16, 17 y 18).
-- ============================================================================

DO $do$
DECLARE
    v_def text;
    v_new text;
    v_n1  int;
    v_n2  int;
    v_g   int;
BEGIN
    v_def := pg_get_functiondef(
        'public.fn_inventory_valuation_rows(bigint)'::regprocedure
    );

    -- 1 · el CTE indexa por la FILA (pp.id), no por el nomenclador.
    --
    -- Se cae el DISTINCT ON: pp.id es la clave primaria, así que ya hay una sola
    -- fila por valor y el DISTINCT ON no aportaba nada (era, de hecho, parte del
    -- disfraz: parecía que desambiguaba algo).
    v_new := replace(v_def,
        E'    latest_costo AS (\r\n'
     || E'        SELECT DISTINCT ON (pp.id_producto, pp.id_presentacion)\r\n'
     || E'            pp.id_producto,\r\n'
     || E'            pp.id_presentacion,\r\n'
     || E'            pp.precio_promedio\r\n'
     || E'        FROM app_dat_producto_presentacion pp\r\n'
     || E'        WHERE pp.precio_promedio IS NOT NULL AND pp.precio_promedio > 0\r\n'
     || E'        ORDER BY pp.id_producto, pp.id_presentacion, pp.created_at DESC\r\n'
     || E'    ),\r\n',
        E'    latest_costo AS (\r\n'
     || E'        -- FASE 3 presentaciones: se indexa por pp.id (la FILA), que es\r\n'
     || E'        -- lo que el ledger guarda en id_presentacion.\r\n'
     || E'        --\r\n'
     || E'        -- Antes se casaba contra pp.id_presentacion, que es la FK al\r\n'
     || E'        -- nomenclador (1=Unidad, 3=Caja...). Dos espacios de ids con el\r\n'
     || E'        -- mismo nombre: el JOIN no casaba NUNCA (0 de 6.647 filas) y\r\n'
     || E'        -- todo caia al fallback "cualquier presentacion del producto".\r\n'
     || E'        SELECT pp.id AS id_producto_presentacion,\r\n'
     || E'               pp.id_producto,\r\n'
     || E'               pp.precio_promedio\r\n'
     || E'          FROM app_dat_producto_presentacion pp\r\n'
     || E'         WHERE pp.precio_promedio IS NOT NULL AND pp.precio_promedio > 0\r\n'
     || E'    ),\r\n');

    -- 2 · el JOIN, con la guarda de producto.
    --
    -- La guarda no es defensiva por gusto: 6 filas con stock apuntan a una
    -- presentacion de otro producto. Sin ella heredarian su costo.
    v_new := replace(v_new,
        E'    LEFT JOIN latest_costo lc\r\n'
     || E'           ON lc.id_producto = li.id_producto\r\n'
     || E'          AND lc.id_presentacion = li.id_presentacion\r\n',
        E'    LEFT JOIN latest_costo lc\r\n'
     || E'           ON lc.id_producto_presentacion = li.id_presentacion\r\n'
     || E'          AND lc.id_producto              = li.id_producto\r\n');

    SELECT count(*) INTO v_n1 FROM regexp_matches(v_new, 'id_producto_presentacion', 'g');
    SELECT count(*) INTO v_n2 FROM regexp_matches(v_new, 'lc\.id_presentacion', 'g');
    SELECT count(*) INTO v_g  FROM regexp_matches(v_new, 'lc\.id_producto              = li\.id_producto', 'g');

    IF v_n1 <> 2 THEN
        RAISE EXCEPTION 'CTE+JOIN: esperaba 2 id_producto_presentacion, hay %. Cambio la funcion?', v_n1;
    END IF;
    IF v_n2 <> 0 THEN
        RAISE EXCEPTION 'Quedo % referencia(s) a lc.id_presentacion (el JOIN viejo)', v_n2;
    END IF;
    IF v_g <> 1 THEN
        RAISE EXCEPTION 'Falta la guarda de producto en el JOIN (hay %)', v_g;
    END IF;

    EXECUTE v_new;
    RAISE NOTICE 'fn_inventory_valuation_rows corregida: costo por presentacion';
END $do$;


-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================

-- V1 · ⭐ El caso más grande medido (tienda 189, producto 6841 "Bolsa"/"Bulto").
--
--   SELECT id_producto, id_presentacion, cantidad, precio_costo_usd, valor_costo_usd
--     FROM public.fn_inventory_valuation_rows(189)
--    WHERE id_producto = 6841;
--
--   antes:   precio_costo_usd 9.80     valor  117.60   (usaba el Bulto)
--   después: precio_costo_usd 186.64   valor 2239.68   (usa la Bolsa, su fila)
--
--   Las presentaciones del 6841 para comparar:
--     SELECT pp.id, np.denominacion, pp.cantidad, pp.es_base, pp.precio_promedio
--       FROM app_dat_producto_presentacion pp
--       JOIN app_nom_presentacion np ON np.id = pp.id_presentacion
--      WHERE pp.id_producto = 6841;
--     -- 6946 Bolsa 1  es_base 186.64  ← el stock está en esta
--     -- 6947 Bulto 10          9.80   ← esta era la que se usaba

-- V2 · No-regresión: 7 tiendas (45, 69, 165, 179, 189, 204, 11), 1.056 filas.
--
--   Comparando antes/después con clave (tienda, producto, presentación, layout):
--     filas: 1.056 = 1.056       ← el JOIN no multiplica ni pierde filas
--     cambia precio_costo_usd: 6
--     cambia cantidad:         0  (con la clave completa; sin id_layout salían
--                                 "1" por filas legítimamente repetidas en
--                                 zonas distintas — no es un duplicado)
--
--   Las 6 filas que cambian, todas por la razón esperada:
--     t189 6841/6946   12 u     9.80 → 186.64
--     t189 6842/6949  478 u     0.96 →   2.50
--     t189 6841/6946    2 u     9.80 → 186.64
--     t165 4483/4549   57 u     3.52 →   3.6667
--     t165 4503/4579  750 u     0.113→   0.12
--     t165 4485/4553  794 u     0.0525→  0.048   ← baja: el bug no era simétrico

-- V3 · Ninguna fila casa por el camino viejo (la prueba de que el JOIN estaba
--      muerto). Debe dar 0:
--
--   WITH li AS (
--     SELECT DISTINCT ON (ip.id_producto, COALESCE(ip.id_variante,0),
--                         COALESCE(ip.id_opcion_variante,0),
--                         ip.id_presentacion, ip.id_ubicacion)
--            ip.id_producto, ip.id_presentacion, ip.cantidad_final
--       FROM app_dat_inventario_productos ip
--      WHERE ip.id_ubicacion IS NOT NULL
--      ORDER BY ip.id_producto, COALESCE(ip.id_variante,0),
--               COALESCE(ip.id_opcion_variante,0), ip.id_presentacion,
--               ip.id_ubicacion, ip.id DESC)
--   SELECT count(*) AS casan_por_nomenclador
--     FROM li
--     JOIN app_dat_producto_presentacion pp
--       ON pp.id_producto = li.id_producto
--      AND pp.id_presentacion = li.id_presentacion
--    WHERE COALESCE(li.cantidad_final,0) > 0;
--   -- medido: 0   (y 5.861 casan por pp.id = li.id_presentacion)

-- V4 · Las 6 filas con id_presentacion de OTRO producto (por qué la guarda).
--
--   SELECT li.id_producto, p.denominacion, li.id_presentacion,
--          pp.id_producto AS dueno_real, p2.denominacion AS producto_dueno
--     FROM (...li como arriba...) li
--     JOIN app_dat_producto p  ON p.id  = li.id_producto
--     JOIN app_dat_producto_presentacion pp ON pp.id = li.id_presentacion
--     JOIN app_dat_producto p2 ON p2.id = pp.id_producto
--    WHERE COALESCE(li.cantidad_final,0) > 0
--      AND pp.id_producto <> li.id_producto;
--
--   medido: 6 filas / 4 productos. El más llamativo:
--     producto 4720 "Pqt Pechuga De Pollo 2 Kg" → presentación del 4623
--                                                 "BLOWER FAN Peugeot 206"

-- V5 · ⚠️ PENDIENTE DE DATO, no de código: productos con costo ambiguo.
--
--   Estas filas no casan con ninguna presentación con precio_promedio > 0, así
--   que siguen dependiendo del fallback, y su producto tiene varios costos
--   distintos → el fallback elige uno arbitrario por created_at.
--
--   WITH amb AS (
--     SELECT pp.id_producto, count(DISTINCT pp.precio_promedio) AS costos
--       FROM app_dat_producto_presentacion pp
--      WHERE pp.precio_promedio IS NOT NULL AND pp.precio_promedio > 0
--      GROUP BY 1 HAVING count(*) > 1)
--   SELECT count(*) AS filas, count(DISTINCT li.id_producto) AS productos
--     FROM (...li...) li JOIN amb ON amb.id_producto = li.id_producto
--    WHERE COALESCE(li.cantidad_final,0) > 0 AND amb.costos > 1;
--   -- medido: 20 filas, 14 productos
--
--   Arreglo: cargarle precio_promedio a la presentación en la que está el stock.
