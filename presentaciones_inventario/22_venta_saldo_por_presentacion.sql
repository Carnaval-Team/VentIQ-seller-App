-- ============================================================================
-- 22 · Venta: el saldo se lee de la presentación vendida (Fase 4)
-- ============================================================================
-- FASE 4 de docs/PLAN_PRESENTACIONES_INVENTARIO.md:
--   «Descuento: filtrando **ubicación y presentación**. Prohibido "último
--    movimiento del producto".»
--
-- ----------------------------------------------------------------------------
-- El bug
-- ----------------------------------------------------------------------------
-- `fn_registrar_venta` y `fn_registrar_venta_mesa` escriben la fila del ledger
-- con el saldo anterior leído así:
--
--     FROM (
--       SELECT cantidad_final
--       FROM app_dat_inventario_productos
--       WHERE id_producto = (v_producto->>'id_producto')::BIGINT
--         AND COALESCE(id_variante, 0) = COALESCE(..., 0)
--         AND COALESCE(id_ubicacion, 0) = COALESCE(v_id_ubicacion_resuelto, 0)
--       ORDER BY id desc, created_at DESC
--       LIMIT 1
--     ) ip;
--
-- Filtra por producto, variante y ubicación — **pero no por presentación**. Es
-- literalmente el patrón que el plan prohíbe: «el último movimiento del
-- producto». El `INSERT` que lo usa sí escribe `v_producto_presentacion_id` en
-- `id_presentacion`, así que la fila nueva dice ser de una presentación pero
-- arrastra el saldo de otra.
--
-- Medido en producción con el producto **217 "azúcar refino"** (ubicación 37):
--
--     Bolsa (336, factor 1)   cantidad_final 100   fila 10923  (2025-10-11)
--     Bulto (337, factor 10)  cantidad_final   0   fila  2774  (2025-09-20)
--
--   Vendiendo 1 **Bulto**, el subselect de hoy devuelve:
--       id_presentacion 336, cantidad_final 100   ← la BOLSA, fila 10923
--   porque es el `id` más alto de la ubicación.
--
--   Con el filtro de presentación devuelve:
--       cantidad_final 0                          ← el Bulto, correcto
--
-- Consecuencia: la venta de 1 Bulto escribiría `cantidad_inicial = 100` y
-- `cantidad_final = 99` en una fila marcada como Bulto. El saldo del Bulto pasa
-- de 0 a 99 de la nada, y el de la Bolsa queda congelado en 100 aunque su última
-- fila ya no sea la más reciente. **Inventa 99 Bultos = 990 Bolsas** de la nada.
--
-- Por qué no ha estallado todavía: solo hay **3 combinaciones
-- producto+ubicación con más de una presentación** en todo el ledger (productos
-- 217, 3046 y 9753). Con una sola presentación por ubicación el subselect acierta
-- por accidente. El bug espera a que alguien configure un segundo empaque — que
-- es exactamente lo que habilita este plan.
--
-- ----------------------------------------------------------------------------
-- El arreglo
-- ----------------------------------------------------------------------------
-- Una línea en cada función: el mismo `COALESCE(x, 0) = COALESCE(y, 0)` que ya
-- usan para variante y ubicación, aplicado a la presentación.
--
--     AND COALESCE(id_presentacion, 0) = COALESCE(v_producto_presentacion_id, 0)
--
-- `v_producto_presentacion_id` ya está resuelto más arriba en ambas funciones (es
-- lo que se escribe en el `INSERT`), con su cascada de fallback cuando el cliente
-- manda NULL. No se toca esa resolución: el cliente puede seguir mandando NULL y
-- el servidor elige la base, que es la decisión 4 del plan.
--
-- El `COALESCE(..., 0)` es necesario y no defensivo por gusto: hay filas
-- históricas de inventario con `id_presentacion IS NULL`, y con `=` a secas
-- (NULL = NULL → NULL) no casarían nunca, así que toda venta de un producto sin
-- presentación empezaría a leer saldo 0 y a escribir negativos.
--
-- ----------------------------------------------------------------------------
-- ⚠️ COMPATIBILIDAD CON LA APP EN PRODUCCIÓN (crítico)
-- ----------------------------------------------------------------------------
-- La app vieja sigue en producción y **no se puede romper**. Este archivo es
-- compatible hacia atrás, pero el primer intento NO lo era y por poco introduzco
-- un bug peor que el que arreglaba. Queda documentado porque el patrón se repite:
--
-- El bloque es `INSERT INTO ... SELECT ... FROM (subselect) ip`. En Postgres, si
-- el subselect del `FROM` **no devuelve filas, el INSERT no inserta nada** — sin
-- error, sin aviso. Verificado:
--
--     INSERT INTO demo(saldo)
--     SELECT COALESCE(ip.cantidad_final, 0)
--       FROM (SELECT cantidad_final FROM app_dat_inventario_productos
--              WHERE id_producto = 217 AND COALESCE(id_ubicacion,0) = 37
--                AND COALESCE(id_presentacion,0) = 999999   -- sin filas
--              ORDER BY id DESC LIMIT 1) ip;
--     -- filas insertadas: 0
--
-- Antes del parche el filtro era solo (producto, variante, ubicación), que casi
-- siempre encuentra algo. Al añadir la presentación, la **primera venta de una
-- presentación que nunca tuvo movimiento en esa ubicación** deja el subselect
-- vacío → la venta se registra en `app_dat_extraccion_productos` pero **no
-- descuenta inventario**, y nadie se enteraría hasta el próximo conteo físico.
--
-- Eso es un fallo silencioso peor que el original: el bug viejo inventaba stock
-- en 3 combinaciones conocidas; el mío habría dejado de descontar en cualquier
-- producto recién configurado, con la app vieja intacta y sin ningún síntoma.
--
-- Solución: envolver el subselect en un **COALESCE escalar**, que siempre
-- devuelve exactamente una fila (0 cuando no hay historial):
--
--     FROM (
--       SELECT COALESCE((
--         SELECT cantidad_final FROM app_dat_inventario_productos
--          WHERE ... AND COALESCE(id_presentacion, 0) = COALESCE(v_producto_presentacion_id, 0)
--          ORDER BY id desc, created_at DESC LIMIT 1
--       ), 0) AS cantidad_final
--     ) ip;
--
-- Con eso, saldo previo 0 → la venta escribe `cantidad_inicial 0` y
-- `cantidad_final -cantidad`, que es el comportamiento correcto para stock que
-- nunca se registró (y deja el descuadre visible en negativo, no oculto).
--
-- Censo del riesgo real: de las **5.000 ventas más recientes**, solo **1** no
-- tenía fila previa de su presentación en esa ubicación — y esa misma tampoco
-- tenía fila previa de ninguna presentación, así que ya estaba en el caso vacío
-- antes del parche. El impacto en datos históricos es nulo; la protección es para
-- lo que viene.
--
-- Resto de la compatibilidad, verificada:
--   · La firma no cambia → la app vieja llama igual.
--   · El cliente puede seguir mandando `id_presentacion: null`: la cascada de
--     fallback de las líneas 110-139 sigue intacta y elige una presentación.
--   · `COALESCE(id_presentacion, 0)` a los dos lados → las filas históricas con
--     `id_presentacion IS NULL` siguen casando (`0 = 0`).
--   · No-regresión medida: 200 productos de una sola presentación, saldo viejo =
--     saldo nuevo en los 200.
--
-- ----------------------------------------------------------------------------
-- Lo que este archivo NO cambia
-- ----------------------------------------------------------------------------
-- · **No** toca el rebalanceo. Vender 1 Bulto cuando solo hay Bolsas sigue sin
--   abrir/empaquetar en estas RPC; eso lo hace `fn_descontar_con_rebalanceo`
--   (`07`), que la venta todavía no llama. Este archivo solo garantiza que el
--   saldo que se lee y se escribe sea el de la presentación correcta.
-- · **No** cambia la firma ni el contrato. La app no se toca.
-- · **No** toca `fn_registrar_venta_old` (1 lectura, sin uso desde la app).
--
-- Idempotente: `DO` block que lee `pg_get_functiondef` de cada función viva y
-- aborta si el parche no queda exactamente una vez por función. Se aplica en dos
-- pasadas porque cada una tiene su propio ancla y su propia guarda.
-- ============================================================================

-- ── Pasada 1 · el filtro de presentación ────────────────────────────────────
DO $do$
DECLARE
    v_firmas text[] := ARRAY[
        'public.fn_registrar_venta(bigint,uuid,jsonb,text,text,text,smallint,bigint)',
        'public.fn_registrar_venta_mesa(bigint,uuid,jsonb,text,text,text,smallint,bigint,bigint)'
    ];
    v_f     text;
    v_def   text;
    v_new   text;
    v_n     int;
    v_total int := 0;
BEGIN
    FOREACH v_f IN ARRAY v_firmas LOOP
        v_def := pg_get_functiondef(v_f::regprocedure);

        -- Si ya está parchada (reejecución), no se toca: idempotencia.
        IF position('COALESCE(id_presentacion, 0) = COALESCE(v_producto_presentacion_id, 0)'
                    in v_def) > 0 THEN
            v_total := v_total + 1;
            CONTINUE;
        END IF;

        -- El ancla incluye el ORDER BY para no tocar por error otro subselect
        -- que filtre por ubicacion (ambas funciones tienen varios).
        v_new := replace(v_def,
            E'          AND COALESCE(id_ubicacion, 0) = COALESCE(v_id_ubicacion_resuelto, 0)\r\n'
         || E'        ORDER BY id desc, created_at DESC\r\n',
            E'          AND COALESCE(id_ubicacion, 0) = COALESCE(v_id_ubicacion_resuelto, 0)\r\n'
         || E'          AND COALESCE(id_presentacion, 0) = COALESCE(v_producto_presentacion_id, 0)\r\n'
         || E'        ORDER BY id desc, created_at DESC\r\n');

        SELECT count(*) INTO v_n
          FROM regexp_matches(v_new,
               'COALESCE\(id_presentacion, 0\) = COALESCE\(v_producto_presentacion_id, 0\)', 'g');

        IF v_n <> 1 THEN
            RAISE EXCEPTION '% : esperaba 1 parche, hay %. Cambio la funcion?', v_f, v_n;
        END IF;

        EXECUTE v_new;
        v_total := v_total + 1;
    END LOOP;

    IF v_total <> 2 THEN
        RAISE EXCEPTION 'Esperaba parchear 2 funciones, parcheo %', v_total;
    END IF;

    RAISE NOTICE 'Venta: saldo anterior leido de la presentacion vendida (2 funciones)';
END $do$;


-- ── Pasada 2 · COALESCE escalar para no dejar de descontar ───────────────────
--
-- Sin esto, la primera venta de una presentación sin historial en esa ubicación
-- deja el subselect vacío y el `INSERT ... SELECT` no escribe NADA: la venta no
-- descuenta inventario, sin error. Ver la sección de COMPATIBILIDAD arriba.
DO $do$
DECLARE
    v_firmas text[] := ARRAY[
        'public.fn_registrar_venta(bigint,uuid,jsonb,text,text,text,smallint,bigint)',
        'public.fn_registrar_venta_mesa(bigint,uuid,jsonb,text,text,text,smallint,bigint,bigint)'
    ];
    v_f     text;
    v_def   text;
    v_new   text;
    v_n     int;
    v_total int := 0;
BEGIN
    FOREACH v_f IN ARRAY v_firmas LOOP
        v_def := pg_get_functiondef(v_f::regprocedure);

        IF position('), 0) AS cantidad_final' in v_def) > 0 THEN
            v_total := v_total + 1;
            CONTINUE;   -- ya envuelto
        END IF;

        v_new := replace(v_def,
            E'      FROM (\r\n'
         || E'        SELECT cantidad_final\r\n'
         || E'        FROM app_dat_inventario_productos\r\n'
         || E'        WHERE id_producto = (v_producto->>''id_producto'')::BIGINT\r\n'
         || E'          AND COALESCE(id_variante, 0) = COALESCE(NULLIF(v_producto->>''id_variante'', '''')::BIGINT, 0)\r\n'
         || E'          AND COALESCE(id_ubicacion, 0) = COALESCE(v_id_ubicacion_resuelto, 0)\r\n'
         || E'          AND COALESCE(id_presentacion, 0) = COALESCE(v_producto_presentacion_id, 0)\r\n'
         || E'        ORDER BY id desc, created_at DESC\r\n'
         || E'        LIMIT 1\r\n'
         || E'      ) ip;\r\n',
            E'      FROM (\r\n'
         || E'        -- COALESCE escalar: SIEMPRE devuelve una fila.\r\n'
         || E'        -- Sin esto, una presentacion sin movimientos previos deja el\r\n'
         || E'        -- subselect vacio y el INSERT ... SELECT no escribe NADA: la venta\r\n'
         || E'        -- no descuenta inventario y no hay error visible.\r\n'
         || E'        SELECT COALESCE((\r\n'
         || E'          SELECT cantidad_final\r\n'
         || E'          FROM app_dat_inventario_productos\r\n'
         || E'          WHERE id_producto = (v_producto->>''id_producto'')::BIGINT\r\n'
         || E'            AND COALESCE(id_variante, 0) = COALESCE(NULLIF(v_producto->>''id_variante'', '''')::BIGINT, 0)\r\n'
         || E'            AND COALESCE(id_ubicacion, 0) = COALESCE(v_id_ubicacion_resuelto, 0)\r\n'
         || E'            AND COALESCE(id_presentacion, 0) = COALESCE(v_producto_presentacion_id, 0)\r\n'
         || E'          ORDER BY id desc, created_at DESC\r\n'
         || E'          LIMIT 1\r\n'
         || E'        ), 0) AS cantidad_final\r\n'
         || E'      ) ip;\r\n');

        SELECT count(*) INTO v_n FROM regexp_matches(v_new, '\), 0\) AS cantidad_final', 'g');
        IF v_n <> 1 THEN
            RAISE EXCEPTION '% : esperaba 1 envoltura, hay %', v_f, v_n;
        END IF;

        EXECUTE v_new;
        v_total := v_total + 1;
    END LOOP;

    IF v_total <> 2 THEN
        RAISE EXCEPTION 'Esperaba envolver 2 funciones, envolvio %', v_total;
    END IF;

    RAISE NOTICE 'Venta: subselect de saldo con COALESCE escalar (2 funciones)';
END $do$;


-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================

-- V1 · ⭐ El parche está en las dos funciones. Debe dar 1 y 1:
--
--   SELECT p.proname,
--          (SELECT count(*) FROM regexp_matches(p.prosrc,
--             'COALESCE\(id_presentacion, 0\) = COALESCE\(v_producto_presentacion_id, 0\)', 'g')) AS parche
--     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname = 'public'
--      AND p.proname IN ('fn_registrar_venta', 'fn_registrar_venta_mesa')
--    ORDER BY 1;

-- V2 · ⭐ El caso medido: producto 217, ubicación 37.
--
--   Estado (una fila por presentación, la más reciente de cada una):
--     SELECT ip.id_presentacion, np.denominacion, ip.cantidad_final, ip.id
--       FROM app_dat_inventario_productos ip
--       JOIN app_dat_producto_presentacion pp ON pp.id = ip.id_presentacion
--       JOIN app_nom_presentacion np ON np.id = pp.id_presentacion
--      WHERE ip.id_producto = 217 AND ip.id_ubicacion = 37
--        AND ip.id IN (SELECT max(i2.id) FROM app_dat_inventario_productos i2
--                       WHERE i2.id_producto = 217 AND i2.id_ubicacion = 37
--                       GROUP BY i2.id_presentacion);
--     -- 336 Bolsa 100.0 (fila 10923) / 337 Bulto 0.0 (fila 2774)
--
--   Lo que leía ANTES (sin filtro de presentación), vendiendo un Bulto:
--     SELECT ip.id_presentacion, ip.cantidad_final, ip.id
--       FROM app_dat_inventario_productos ip
--      WHERE ip.id_producto = 217 AND COALESCE(ip.id_variante,0) = 0
--        AND COALESCE(ip.id_ubicacion,0) = 37
--      ORDER BY ip.id DESC, ip.created_at DESC LIMIT 1;
--     -- medido: id_presentacion 336, cantidad_final 100, fila 10923  ← la BOLSA
--
--   Lo que lee AHORA:
--     ... AND COALESCE(ip.id_presentacion,0) = 337 ...
--     -- medido: cantidad_final 0   ← el BULTO, correcto

-- V3 · Censo del riesgo (por qué no había estallado).
--
--   WITH pares AS (
--     SELECT ip.id_producto, ip.id_ubicacion, COALESCE(ip.id_variante,0) v
--       FROM app_dat_inventario_productos ip
--      WHERE ip.id_presentacion IS NOT NULL AND ip.id_ubicacion IS NOT NULL
--      GROUP BY 1,2,3 HAVING count(DISTINCT ip.id_presentacion) > 1)
--   SELECT count(*) AS combinaciones, count(DISTINCT id_producto) AS productos
--     FROM pares;
--   -- medido: 3 combinaciones, 3 productos (217, 3046, 9753)
--
--   Con una sola presentación por ubicación el subselect viejo acertaba por
--   accidente. Al habilitar multipresentación, cada producto nuevo es un caso.

-- V4 · Filas con id_presentacion NULL siguen funcionando (por el COALESCE).
--
--   SELECT count(*) AS filas_sin_presentacion
--     FROM app_dat_inventario_productos WHERE id_presentacion IS NULL;
--
--   Para esas, `COALESCE(id_presentacion,0) = COALESCE(NULL,0)` → `0 = 0` → TRUE,
--   igual que antes. Con `id_presentacion = v_producto_presentacion_id` a secas
--   no casarían y toda venta leería saldo 0.

-- V5 · No-regresión funcional: vender un producto de UNA sola presentación debe
--      seguir dando el mismo saldo que antes. Ensayo:
--
--   BEGIN;
--     -- elegir un producto con una sola presentación en su ubicación
--     WITH una AS (
--       SELECT ip.id_producto, ip.id_ubicacion, min(ip.id_presentacion) AS pres
--         FROM app_dat_inventario_productos ip
--        WHERE ip.id_presentacion IS NOT NULL AND ip.id_ubicacion IS NOT NULL
--        GROUP BY 1,2 HAVING count(DISTINCT ip.id_presentacion) = 1
--        LIMIT 1)
--     SELECT (SELECT cantidad_final FROM app_dat_inventario_productos
--              WHERE id_producto = u.id_producto
--                AND COALESCE(id_ubicacion,0) = u.id_ubicacion
--              ORDER BY id DESC LIMIT 1) AS sin_filtro,
--            (SELECT cantidad_final FROM app_dat_inventario_productos
--              WHERE id_producto = u.id_producto
--                AND COALESCE(id_ubicacion,0) = u.id_ubicacion
--                AND COALESCE(id_presentacion,0) = COALESCE(u.pres,0)
--              ORDER BY id DESC LIMIT 1) AS con_filtro
--       FROM una u;
--   ROLLBACK;
--   -- los dos valores deben coincidir
