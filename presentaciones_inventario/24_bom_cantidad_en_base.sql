-- ============================================================================
-- 24 · BOM y porciones: convertir la cantidad vendida a unidades base
-- ============================================================================
-- Cierra el riesgo que ABRE la Fase 4 en la app: ahora que el TPV manda
-- `cantidad` EN LA PRESENTACION ELEGIDA (2 = 2 Bultos, no 20 Bolsas), toda ruta
-- que interprete esa cantidad como unidades base se equivoca por el factor.
--
-- ----------------------------------------------------------------------------
-- El riesgo
-- ----------------------------------------------------------------------------
-- `fn_registrar_venta` y `fn_registrar_venta_mesa` pasan la cantidad cruda a
-- `fn_descontar_venta_enrutada`, que la usa como unidades base en dos rutas:
--
--   · `descontar = 'ingredientes'` → `fn_descontar_ingredientes_elaborado`
--     multiplica la receta por esa cantidad. Vender 1 Caja de 24 croquetas
--     descontaria ingredientes para **1** croqueta.
--   · `cocina_por_tanda` → valida y descuenta PORCIONES preparadas. Vender
--     1 Caja descontaria 1 porcion del almacen de la cocina.
--
-- La linea del ledger del SKU propio **no** tiene este problema: ahi la cantidad
-- en la presentacion es exactamente lo que se quiere guardar (es el punto de la
-- Fase 4). El problema es solo donde la cantidad se usa como magnitud fisica
-- comun: recetas y porciones.
--
-- Censo de exposicion en produccion:
--   · **4 productos elaborados** con mas de una presentacion o factor ≠ 1:
--       219 «croqueta» (tienda 11, 2 presentaciones, factor max 24)
--       220 «pan de la casa» (tienda 11, 2 pres., factor max 24)
--       9925 «Pan Boom 40g» (tienda 216, 2 pres., factor max 50)
--       9635 «Pizza de Queso Gouda» (tienda 174, 4 pres., todas factor 1)
--   · 50 servicios (no mueven inventario, no aplica)
--   · 221 productos normales con factor ≠ 1 (van por SKU propio, no aplica)
--
-- O sea: **3 productos** en los que vender un empaque habria descontado la
-- receta de una sola unidad. Poco, pero es materia prima real y el error es
-- silencioso: la venta sale bien y el inventario de MP se queda alto.
--
-- ----------------------------------------------------------------------------
-- La solucion
-- ----------------------------------------------------------------------------
-- Helper nuevo `fn_cantidad_en_base(id_presentacion, cantidad)` y un solo
-- cambio en cada funcion de venta: la cantidad que se le pasa al descuento
-- enrutado va convertida.
--
-- El helper usa `factor_rel` de `fn_presentaciones_producto`, **no**
-- `pp.cantidad`: hay 131 filas `es_base` con factor 12/24/30 donde `cantidad`
-- no es el equivalente real. Verificado con la presentacion 4445 (base con
-- factor 30): `fn_cantidad_en_base(4445, 2)` = **2**, no 60.
--
-- Casos verificados en produccion:
--   fn_cantidad_en_base(337, 2)      = 20        (Bulto factor 10 → 20 Bolsas)
--   fn_cantidad_en_base(336, 2)      = 2         (Bolsa, es la base)
--   fn_cantidad_en_base(NULL, 5)     = 5         (sin presentacion, pasa igual)
--   fn_cantidad_en_base(99999999, 3) = 3         (presentacion inexistente)
--   fn_cantidad_en_base(4445, 2)     = 2         (base con factor 30)
--   fn_cantidad_en_base(337, NULL)   = NULL
--
-- Los dos fallbacks (NULL y presentacion inexistente) devuelven la cantidad sin
-- tocar: es exactamente el comportamiento anterior a este archivo, asi que una
-- app vieja que manda `id_presentacion: null` sigue funcionando igual.
--
-- ----------------------------------------------------------------------------
-- Compatibilidad con la app en produccion
-- ----------------------------------------------------------------------------
-- · Ninguna firma cambia.
-- · La app **vieja** manda cantidades ya en unidades base y con la presentacion
--   base (o null). Con la base, `factor_rel = 1` y la conversion es identidad;
--   con null, tambien. **Cero cambio de comportamiento para la app vieja.**
-- · La app **nueva** manda la presentacion elegida y su cantidad, y aqui se
--   convierte. Las dos conviven contra la misma RPC.
-- · No se toca la linea del ledger del SKU: sigue guardando la cantidad en su
--   presentacion, que es el objetivo de la Fase 4.
--
-- ⚠️ LO QUE ESTE ARCHIVO NO HACE
-- La venta sigue **sin llamar al rebalanceo**: vender 1 Bulto cuando solo hay
-- Bolsas no abre empaques (`fn_descontar_con_rebalanceo` existe pero
-- `fn_registrar_venta` no la invoca). Y `fn_stock_producto_almacen` sigue
-- SUMANDO `cantidad_final` de presentaciones distintas sin factor — hoy no
-- afecta a nadie (1 sola combinacion producto+almacen con >1 presentacion en
-- todo el ledger, y es el producto de prueba 3046 con dos filas base de factor
-- 1), pero es el proximo bug cuando se configure un empaque real en un
-- elaborado. Queda anotado en el plan.
--
-- Idempotente: el helper es `CREATE OR REPLACE`; el parche de las funciones de
-- venta se salta si ya esta aplicado y aborta si no encuentra el ancla.
-- ============================================================================

-- ── Helper ───────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_cantidad_en_base(
    p_id_presentacion bigint,
    p_cantidad        numeric
)
RETURNS numeric
LANGUAGE sql
STABLE
SET search_path = public
AS $fn$
    -- factor_rel y no pp.cantidad: 131 filas es_base tienen factor 12/24/30 y
    -- ahi `cantidad` no es el equivalente real (fn_presentaciones_producto
    -- calcula cantidad / cantidad_de_la_base).
    --
    -- Sin presentacion o con una que no existe, se devuelve la cantidad tal
    -- cual: es el comportamiento previo y lo que necesita la app vieja.
    SELECT CASE
             WHEN p_cantidad IS NULL THEN NULL
             WHEN p_id_presentacion IS NULL THEN p_cantidad
             ELSE p_cantidad * COALESCE(
                    (SELECT f.factor_rel
                       FROM public.app_dat_producto_presentacion pp
                       CROSS JOIN LATERAL public.fn_presentaciones_producto(pp.id_producto) f
                      WHERE pp.id = p_id_presentacion
                        AND f.id_presentacion = p_id_presentacion
                      LIMIT 1),
                    1)
           END;
$fn$;

COMMENT ON FUNCTION public.fn_cantidad_en_base(bigint, numeric) IS
    'Convierte una cantidad expresada en una presentacion a unidades base usando factor_rel. Devuelve la cantidad sin tocar si la presentacion es NULL o no existe. Ver presentaciones_inventario/24.';

GRANT EXECUTE ON FUNCTION public.fn_cantidad_en_base(bigint, numeric)
  TO anon, authenticated, service_role;


-- ── Parche de las dos funciones de venta ─────────────────────────────────────

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

        IF position('fn_cantidad_en_base(' in v_def) > 0 THEN
            v_total := v_total + 1;
            CONTINUE;   -- ya parchada
        END IF;

        -- Solo la cantidad que va al descuento enrutado (recetas y porciones).
        -- La del INSERT del ledger NO se toca: ahi la cantidad en la
        -- presentacion es justamente lo que se quiere guardar.
        v_new := replace(v_def,
            E'        p_cantidad          := (v_producto->>''cantidad'')::NUMERIC,\r\n',
            E'        p_cantidad          := public.fn_cantidad_en_base(\r\n'
         || E'                                 v_producto_presentacion_id,\r\n'
         || E'                                 (v_producto->>''cantidad'')::NUMERIC),\r\n');

        SELECT count(*) INTO v_n
          FROM regexp_matches(v_new, 'fn_cantidad_en_base\(', 'g');

        IF v_n <> 1 THEN
            RAISE EXCEPTION '% : esperaba 1 conversion, hay %. Cambio la funcion?', v_f, v_n;
        END IF;

        EXECUTE v_new;
        v_total := v_total + 1;
    END LOOP;

    IF v_total <> 2 THEN
        RAISE EXCEPTION 'Esperaba parchear 2 funciones, parcheo %', v_total;
    END IF;

    RAISE NOTICE 'Venta: cantidad convertida a base para BOM/porciones (2 funciones)';
END $do$;


-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================

-- V1 · ⭐ El helper convierte bien y no rompe los casos borde:
--
--   SELECT 'bulto_337_x2'          AS caso, public.fn_cantidad_en_base(337, 2)      AS v
--   UNION ALL SELECT 'bolsa_336_x2',        public.fn_cantidad_en_base(336, 2)
--   UNION ALL SELECT 'null_pres_x5',        public.fn_cantidad_en_base(NULL, 5)
--   UNION ALL SELECT 'inexistente_x3',      public.fn_cantidad_en_base(99999999, 3)
--   UNION ALL SELECT 'base_factor30_x2',    public.fn_cantidad_en_base(4445, 2);
--
--   medido: 20 / 2 / 5 / 3 / 2
--   El ultimo es el importante: la presentacion 4445 es base con factor 30, y
--   usar `pp.cantidad` habria dado 60.

-- V2 · ⭐ El parche esta en las dos funciones (debe dar 1 y 1):
--
--   SELECT p.proname,
--          (SELECT count(*) FROM regexp_matches(p.prosrc, 'fn_cantidad_en_base\(', 'g')) AS parche
--     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname = 'public'
--      AND p.proname IN ('fn_registrar_venta', 'fn_registrar_venta_mesa')
--    ORDER BY 1;

-- V3 · La linea del ledger NO se convirtio (sigue guardando la presentacion).
--      Debe seguir habiendo UNA sola conversion por funcion, y el INSERT debe
--      seguir usando la cantidad cruda:
--
--   SELECT p.proname,
--          (SELECT count(*) FROM regexp_matches(p.prosrc,
--             'COALESCE\(ip\.cantidad_final, 0\) - \(v_producto->>''cantidad''\)::NUMERIC', 'g')) AS ledger_crudo
--     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname = 'public'
--      AND p.proname IN ('fn_registrar_venta', 'fn_registrar_venta_mesa')
--    ORDER BY 1;
--   -- esperado: 1 en cada una

-- V4 · Los 3 productos elaborados que estaban en riesgo:
--
--   WITH pres AS (
--     SELECT pp.id_producto, count(*) n_pres, max(pp.cantidad) max_factor
--       FROM app_dat_producto_presentacion pp GROUP BY pp.id_producto)
--   SELECT p.id, p.denominacion, p.id_tienda, pr.n_pres, pr.max_factor
--     FROM app_dat_producto p JOIN pres pr ON pr.id_producto = p.id
--    WHERE p.es_elaborado AND (pr.n_pres > 1 OR pr.max_factor <> 1)
--    ORDER BY p.id;
--   -- medido: 219 croqueta (24), 220 pan de la casa (24), 9925 Pan Boom (50),
--   --         9635 Pizza (4 pres. de factor 1, sin riesgo real)

-- V5 · Compatibilidad con la app vieja: mandar la presentacion BASE debe dar
--      exactamente la misma cantidad que antes.
--
--   SELECT pp.id, np.denominacion, pp.cantidad AS factor,
--          public.fn_cantidad_en_base(pp.id, 7) AS convertida
--     FROM app_dat_producto_presentacion pp
--     LEFT JOIN app_nom_presentacion np ON np.id = pp.id_presentacion
--    WHERE pp.es_base
--    LIMIT 20;
--   -- `convertida` debe ser 7 en todas: factor_rel de la base es 1 por
--   -- definicion, incluso en las 131 filas con pp.cantidad = 12/24/30.
