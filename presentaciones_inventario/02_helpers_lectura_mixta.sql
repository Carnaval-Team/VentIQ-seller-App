-- ============================================================================
-- 02 · Fase 0 · Helpers de LECTURA de stock mixto
-- ============================================================================
-- Plan: docs/PLAN_PRESENTACIONES_INVENTARIO.md  (Fase 0.1, parte de lectura)
-- Proyecto Supabase: vsieeihstajlrdvpuooh
-- Aplicar en: SQL Editor del dashboard. Idempotente (CREATE OR REPLACE).
-- Depende de: nada (el 01 no es requisito para leer, solo para convertir).
--
-- SOLO LECTURA. Ninguna de estas funciones escribe. No tocan funciones
-- existentes. Son la unica fuente de verdad para:
--
--   fn_presentaciones_producto   cadena ordenada Pallet > Caja > Unidad + factores
--   fn_stock_saldos_presentacion saldo vigente por presentacion
--   fn_equivalente_base          total en unidades base (para dinero y rotacion)
--   fn_formatear_stock_mixto     "4 Cajas + 4 Unidades"
--   fn_stock_mixto_json          payload unico que consume Flutter
--
-- EL FACTOR ES RELATIVO A LA BASE, NO ABSOLUTO
-- --------------------------------------------
-- app_dat_producto_presentacion.cantidad NO siempre vale 1 en la fila es_base.
-- Verificado en produccion: 131 filas es_base tienen cantidad <> 1 (ej. producto
-- 7075 "Cerveza Coronita": Unidad con cantidad = 24.0, es_base = true).
-- Por eso el factor util es SIEMPRE:
--
--     factor_rel = pp.cantidad / cantidad_de_la_fila_base
--
-- Con eso la base queda en 1.0 por construccion y "Caja x24 / Unidad x1" y
-- "Caja x24 / Unidad x24" (base mal capturada) no dan resultados distintos
-- cuando solo hay una presentacion. Multiplicar por pp.cantidad a secas, como
-- hace hoy fn_inventario_resumen_*, es el bug que el plan describe.
--
-- RESOLUCION DE LA BASE (defensiva, con datos reales sucios)
-- ---------------------------------------------------------
-- Verificado en produccion: 9 productos NO tienen ninguna fila es_base y 1
-- producto tiene VARIAS. La cascada es:
--   1. la fila es_base de menor id (mismo criterio que ya usa
--      fn_producto_json_a_presentacion_base: ORDER BY pp.id LIMIT 1)
--   2. si no hay es_base, la fila de menor cantidad (la mas chica es la base
--      natural), desempatando por id
--
-- CONTRATO DE IDs
-- ---------------
-- id_presentacion = app_dat_producto_presentacion.id  (NUNCA app_nom_presentacion.id)
-- Verificado: las 308.375 filas de app_dat_inventario_productos apuntan a
-- app_dat_producto_presentacion.id; 0 apuntan al catalogo. El contrato ya se
-- cumple en los datos, aqui se documenta y se valida.
--
-- SALDO VIGENTE = ULTIMA FILA POR CLAVE
-- -------------------------------------
-- app_dat_inventario_productos es un ledger de snapshots: cada fila lleva
-- cantidad_final. El saldo vigente de una clave
-- (producto, variante, opcion, ubicacion, presentacion) es el cantidad_final
-- de su fila mas reciente por id DESC. Es el mismo criterio de
-- fn_stock_producto_almacen_detalle, y hay indice para eso
-- (idx_inv_prod_combo, idx_inventario_productos_optimized).
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 2.1 fn_presentaciones_producto
-- Cadena de presentaciones de un producto, de la mas grande a la mas chica.
--
-- nivel = 1 es la mas grande (Cajon), nivel = N la mas chica (Unidad).
-- Abrir  -> pasa de nivel n a nivel n+1 (siguiente mas chica).
-- Empaquetar -> pasa de nivel n a nivel n-1 (siguiente mas grande).
--
-- factor_hijo = cuantas unidades de la SIGUIENTE presentacion mas chica salen
-- de una de esta. Es lo que se necesita para abrir/empaquetar un solo escalon
-- sin saltar a base. Para el nivel mas chico es NULL.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_presentaciones_producto(
    p_id_producto bigint
)
RETURNS TABLE (
    id_presentacion      bigint,   -- app_dat_producto_presentacion.id
    id_nom_presentacion  bigint,   -- app_nom_presentacion.id (solo display)
    nombre               varchar,
    factor               numeric,  -- pp.cantidad tal cual esta en la tabla
    factor_rel           numeric,  -- factor relativo a la base (base = 1)
    es_base              boolean,  -- la base REAL resuelta por la cascada
    es_fraccionable      boolean,
    sku_codigo           varchar,
    nivel                integer,  -- 1 = mas grande
    id_presentacion_hijo bigint,   -- siguiente mas chica (NULL si es la ultima)
    factor_hijo          numeric,  -- cuantos hijos salen de uno de estos
    id_presentacion_padre bigint,  -- siguiente mas grande (NULL si es la primera)
    factor_padre         numeric   -- cuantos de estos hacen un padre
)
LANGUAGE sql
STABLE
AS $$
    WITH base AS (
        -- Cascada de resolucion de la base. Un solo scan, sin subconsultas
        -- correlacionadas: ordena por (es_base primero, menor factor, menor id)
        -- y toma la primera.
        SELECT pp.id, pp.cantidad
          FROM public.app_dat_producto_presentacion pp
         WHERE pp.id_producto = p_id_producto
         ORDER BY pp.es_base DESC, pp.cantidad ASC, pp.id ASC
         LIMIT 1
    ),
    cadena AS (
        SELECT
            pp.id                                        AS id_presentacion,
            pp.id_presentacion                           AS id_nom_presentacion,
            COALESCE(np.denominacion, 'Presentacion')::varchar AS nombre,
            pp.cantidad                                  AS factor,
            -- round(): la division numeric arrastra 20 decimales de ruido
            -- (24/1 = 24.0000000000000000) que despues se filtra al JSON de la app.
            round(pp.cantidad / NULLIF(b.cantidad, 0), 6) AS factor_rel,
            (pp.id = b.id)                               AS es_base,
            COALESCE(np.es_fraccionable, false)          AS es_fraccionable,
            np.sku_codigo                                AS sku_codigo,
            ROW_NUMBER() OVER (ORDER BY pp.cantidad DESC, pp.id ASC)::int AS nivel
          FROM public.app_dat_producto_presentacion pp
          CROSS JOIN base b
          LEFT JOIN public.app_nom_presentacion np ON np.id = pp.id_presentacion
         WHERE pp.id_producto = p_id_producto
    )
    SELECT
        c.id_presentacion,
        c.id_nom_presentacion,
        c.nombre,
        c.factor,
        c.factor_rel,
        c.es_base,
        c.es_fraccionable,
        c.sku_codigo,
        c.nivel,
        LEAD(c.id_presentacion) OVER (ORDER BY c.nivel)  AS id_presentacion_hijo,
        CASE WHEN LEAD(c.factor_rel) OVER (ORDER BY c.nivel) > 0
             THEN round(c.factor_rel / LEAD(c.factor_rel) OVER (ORDER BY c.nivel), 6)
        END                                              AS factor_hijo,
        LAG(c.id_presentacion) OVER (ORDER BY c.nivel)   AS id_presentacion_padre,
        CASE WHEN c.factor_rel > 0
             THEN round(LAG(c.factor_rel) OVER (ORDER BY c.nivel) / c.factor_rel, 6)
        END                                              AS factor_padre
      FROM cadena c
     ORDER BY c.nivel;
$$;

COMMENT ON FUNCTION public.fn_presentaciones_producto(bigint) IS
    'Cadena de presentaciones de un producto ordenada de la mas grande a la mas '
    'chica, con factor relativo a la base y los factores de un escalon '
    '(abrir = hijo, empaquetar = padre). id_presentacion es '
    'app_dat_producto_presentacion.id.';

GRANT EXECUTE ON FUNCTION public.fn_presentaciones_producto(bigint)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 2.2 fn_stock_saldos_presentacion
-- Saldo vigente por presentacion. Una fila por
-- (ubicacion, variante, opcion, presentacion).
--
-- p_id_ubicacion NOT NULL -> una sola ubicacion (lo que usa el rebalanceo)
-- p_id_almacen   NOT NULL -> todas las ubicaciones de ese almacen
-- ambos NULL              -> todo el producto, en toda la tienda
--
-- p_incluir_cero: el rebalanceo necesita ver la fila con saldo 0 para saber
-- cual es su cantidad_inicial; la UI no. Por defecto se omiten los ceros,
-- igual que fn_stock_producto_almacen_detalle.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_stock_saldos_presentacion(
    p_id_producto   bigint,
    p_id_almacen    bigint  DEFAULT NULL,
    p_id_ubicacion  bigint  DEFAULT NULL,
    p_incluir_cero  boolean DEFAULT false
)
RETURNS TABLE (
    id_ubicacion        bigint,
    id_almacen          bigint,
    id_variante         bigint,
    id_opcion_variante  bigint,
    id_presentacion     bigint,
    presentacion_nombre varchar,
    sku_codigo          varchar,
    factor_rel          numeric,
    es_base             boolean,
    nivel               integer,
    saldo               numeric,
    equivalente_base    numeric,
    sku_producto        varchar,
    sku_ubicacion       varchar
)
LANGUAGE sql
STABLE
AS $$
    WITH vigente AS (
        SELECT DISTINCT ON (
                   ip.id_ubicacion,
                   COALESCE(ip.id_variante, 0),
                   COALESCE(ip.id_opcion_variante, 0),
                   ip.id_presentacion
               )
               ip.id_ubicacion,
               la.id_almacen,
               ip.id_variante,
               ip.id_opcion_variante,
               ip.id_presentacion,
               COALESCE(ip.cantidad_final, 0) AS saldo,
               ip.sku_producto,
               ip.sku_ubicacion
          FROM public.app_dat_inventario_productos ip
          JOIN public.app_dat_layout_almacen la ON la.id = ip.id_ubicacion
         WHERE ip.id_producto = p_id_producto
           AND la.deleted_at IS NULL
           AND (p_id_ubicacion IS NULL OR ip.id_ubicacion = p_id_ubicacion)
           AND (p_id_almacen   IS NULL OR la.id_almacen   = p_id_almacen)
         ORDER BY
               ip.id_ubicacion,
               COALESCE(ip.id_variante, 0),
               COALESCE(ip.id_opcion_variante, 0),
               ip.id_presentacion,
               ip.id DESC
    )
    SELECT
        v.id_ubicacion,
        v.id_almacen,
        v.id_variante,
        v.id_opcion_variante,
        v.id_presentacion,
        c.nombre                        AS presentacion_nombre,
        c.sku_codigo,
        c.factor_rel,
        c.es_base,
        c.nivel,
        v.saldo,
        (v.saldo * COALESCE(c.factor_rel, 1)) AS equivalente_base,
        v.sku_producto,
        v.sku_ubicacion
      FROM vigente v
      LEFT JOIN public.fn_presentaciones_producto(p_id_producto) c
             ON c.id_presentacion = v.id_presentacion
     WHERE p_incluir_cero OR v.saldo <> 0
     ORDER BY v.id_ubicacion, COALESCE(c.nivel, 999), v.id_presentacion;
$$;

COMMENT ON FUNCTION public.fn_stock_saldos_presentacion(bigint, bigint, bigint, boolean) IS
    'Saldo vigente por presentacion (ultima fila del ledger por clave). saldo esta '
    'en unidades DE ESA presentacion; equivalente_base = saldo * factor_rel.';

GRANT EXECUTE ON FUNCTION public.fn_stock_saldos_presentacion(bigint, bigint, bigint, boolean)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 2.3 fn_equivalente_base
-- Total del producto expresado en unidades base. SOLO para dinero, rotacion,
-- dias de cobertura y para responder "el equivalente alcanza?".
--
-- NUNCA usar este numero como "cantidad en almacen" en un reporte: la cantidad
-- fisica es el desglose mixto. Este es el equivalente.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_equivalente_base(
    p_id_producto  bigint,
    p_id_almacen   bigint DEFAULT NULL,
    p_id_ubicacion bigint DEFAULT NULL
)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(SUM(s.equivalente_base), 0)::numeric
      FROM public.fn_stock_saldos_presentacion(
               p_id_producto, p_id_almacen, p_id_ubicacion, false) s;
$$;

COMMENT ON FUNCTION public.fn_equivalente_base(bigint, bigint, bigint) IS
    'Suma de saldos convertida a unidades base. Para valorar y comparar, no para '
    'mostrar como cantidad de almacen.';

GRANT EXECUTE ON FUNCTION public.fn_equivalente_base(bigint, bigint, bigint)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 2.4 fn_plural_presentacion
-- Pluralizacion minima en espanol para el texto mixto. Es COSMETICO: si una
-- palabra sale rara no rompe ningun calculo.
--
-- Reglas, en orden:
--   cantidad = 1            -> singular tal cual
--   termina en 's'          -> igual        (Libras -> Libras)
--   termina en 'on'/'ón'    -> 'ones'       (Cajon -> Cajones, Galon -> Galones)
--   termina en vocal        -> + 's'        (Caja -> Cajas, Metro -> Metros)
--   resto (consonante)      -> + 'es'       (Unidad -> Unidades)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_plural_presentacion(
    p_nombre   text,
    p_cantidad numeric
)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN p_nombre IS NULL OR btrim(p_nombre) = '' THEN ''
        WHEN ABS(COALESCE(p_cantidad, 0)) = 1         THEN p_nombre
        WHEN right(lower(p_nombre), 1) = 's'          THEN p_nombre
        WHEN right(lower(p_nombre), 2) IN ('on', 'ón')
             THEN left(p_nombre, length(p_nombre) - 2) || 'ones'
        WHEN right(lower(p_nombre), 1) IN ('a','e','i','o','u')
             THEN p_nombre || 's'
        ELSE p_nombre || 'es'
    END;
$$;

COMMENT ON FUNCTION public.fn_plural_presentacion(text, numeric) IS
    'Pluralizacion cosmetica del nombre de una presentacion para el texto mixto.';

GRANT EXECUTE ON FUNCTION public.fn_plural_presentacion(text, numeric)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 2.5 fn_formatear_stock_mixto (version PURA, sobre jsonb)
-- "4 Cajas + 4 Unidades". Omite las presentaciones con saldo 0.
--
-- Se separa la version pura de la que consulta la base para que Flutter pueda
-- formatear offline con la misma regla exacta (el helper Dart de la Fase 2
-- replica esta funcion, no una parecida).
--
-- Entrada: [{"nombre":"Caja","cantidad":4}, {"nombre":"Unidad","cantidad":4}]
--          El ORDEN del array manda: se respeta tal cual llega (de mayor a
--          menor lo pone quien consulta).
-- p_abreviar: usa sku_codigo si viene en el objeto ("4 CAJ + 4 UNI"), util
--             cuando no cabe el nombre largo (chips, FAB, tickets).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_formatear_stock_mixto(
    p_saldos    jsonb,
    p_abreviar  boolean DEFAULT false,
    p_vacio     text    DEFAULT 'Sin stock'
)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT COALESCE(
        NULLIF(
            string_agg(
                -- rtrim(...,'.'): to_char con FM deja el punto suelto en los
                -- enteros ("4." en vez de "4"). Verificado en produccion.
                rtrim(trim(to_char(x.cantidad, 'FM9999999990.999')), '.') || ' ' ||
                CASE
                    WHEN p_abreviar AND COALESCE(x.sku, '') <> '' THEN x.sku
                    ELSE public.fn_plural_presentacion(x.nombre, x.cantidad)
                END,
                ' + ' ORDER BY x.orden
            ),
            ''
        ),
        p_vacio
    )
      FROM (
        SELECT
            COALESCE(e.value->>'nombre', 'Presentacion')          AS nombre,
            e.value->>'sku_codigo'                                AS sku,
            COALESCE((e.value->>'cantidad')::numeric, 0)          AS cantidad,
            e.ordinality                                          AS orden
          FROM jsonb_array_elements(COALESCE(p_saldos, '[]'::jsonb))
               WITH ORDINALITY AS e(value, ordinality)
      ) x
     WHERE x.cantidad <> 0;
$$;

COMMENT ON FUNCTION public.fn_formatear_stock_mixto(jsonb, boolean, text) IS
    'Formatea [{nombre,cantidad,sku_codigo}] como "4 Cajas + 4 Unidades". Pura: '
    'no consulta la base, para que el cliente Dart pueda replicarla identica.';

GRANT EXECUTE ON FUNCTION public.fn_formatear_stock_mixto(jsonb, boolean, text)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 2.6 fn_stock_mixto_json
-- El payload unico que consumen las apps: desglose fisico + equivalente base +
-- texto ya formateado. Una sola llamada por producto/almacen.
--
-- Suma las ubicaciones del ambito pedido: para "cuanto hay de esto en este
-- almacen" el usuario quiere 4 Cajas, no 2 Cajas en el pasillo A y 2 en el B.
-- El detalle por ubicacion sale de fn_stock_saldos_presentacion.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_stock_mixto_json(
    p_id_producto  bigint,
    p_id_almacen   bigint DEFAULT NULL,
    p_id_ubicacion bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_desglose jsonb;
    v_equiv    numeric;
BEGIN
    SELECT
        COALESCE(jsonb_agg(jsonb_build_object(
            'id_presentacion',  t.id_presentacion,
            'nombre',           t.presentacion_nombre,
            'sku_codigo',       t.sku_codigo,
            'cantidad',         t.saldo,
            'factor_rel',       t.factor_rel,
            'es_base',          t.es_base,
            'nivel',            t.nivel,
            'equivalente_base', t.equivalente_base
        ) ORDER BY t.nivel NULLS LAST, t.id_presentacion), '[]'::jsonb),
        COALESCE(SUM(t.equivalente_base), 0)
    INTO v_desglose, v_equiv
    FROM (
        SELECT
            s.id_presentacion,
            MIN(s.presentacion_nombre)      AS presentacion_nombre,
            MIN(s.sku_codigo)               AS sku_codigo,
            SUM(s.saldo)                    AS saldo,
            MIN(s.factor_rel)               AS factor_rel,
            BOOL_OR(s.es_base)              AS es_base,
            MIN(s.nivel)                    AS nivel,
            SUM(s.equivalente_base)         AS equivalente_base
          FROM public.fn_stock_saldos_presentacion(
                   p_id_producto, p_id_almacen, p_id_ubicacion, false) s
         GROUP BY s.id_presentacion
        HAVING SUM(s.saldo) <> 0
    ) t;

    RETURN jsonb_build_object(
        'id_producto',      p_id_producto,
        'id_almacen',       p_id_almacen,
        'id_ubicacion',     p_id_ubicacion,
        'desglose',         v_desglose,
        'equivalente_base', v_equiv,
        'texto',            public.fn_formatear_stock_mixto(v_desglose, false),
        'texto_corto',      public.fn_formatear_stock_mixto(v_desglose, true)
    );
END;
$$;

COMMENT ON FUNCTION public.fn_stock_mixto_json(bigint, bigint, bigint) IS
    'Payload de stock mixto para las apps: desglose por presentacion, equivalente '
    'en unidades base y texto formateado. Agrega las ubicaciones del ambito.';

GRANT EXECUTE ON FUNCTION public.fn_stock_mixto_json(bigint, bigint, bigint)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 2.7 fn_validar_id_presentacion
-- Cierra la confusion de IDs que documenta el plan: valida que el id que llega
-- en un JSON sea app_dat_producto_presentacion.id DE ESE producto.
--
-- Devuelve el mismo id si es valido. Si no, RAISE con un mensaje que dice
-- exactamente que paso, incluyendo el caso "me mandaste el id del catalogo".
-- Las RPC de escritura de la Fase 1 la llaman por cada linea.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_validar_id_presentacion(
    p_id_producto     bigint,
    p_id_presentacion bigint
)
RETURNS bigint
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_id_producto_real bigint;
    v_nom              varchar;
BEGIN
    IF p_id_presentacion IS NULL THEN
        RAISE EXCEPTION
            'id_presentacion es obligatorio (producto %). Debe ser app_dat_producto_presentacion.id',
            p_id_producto
            USING ERRCODE = '22023';
    END IF;

    SELECT pp.id_producto INTO v_id_producto_real
      FROM public.app_dat_producto_presentacion pp
     WHERE pp.id = p_id_presentacion;

    IF v_id_producto_real IS NULL THEN
        -- Pista concreta: casi siempre es el id del catalogo.
        SELECT np.denominacion INTO v_nom
          FROM public.app_nom_presentacion np
         WHERE np.id = p_id_presentacion;

        IF v_nom IS NOT NULL THEN
            RAISE EXCEPTION
                'id_presentacion % no es app_dat_producto_presentacion.id: es app_nom_presentacion.id (%). Envie el id del vinculo producto-presentacion',
                p_id_presentacion, v_nom
                USING ERRCODE = '22023';
        END IF;

        RAISE EXCEPTION
            'id_presentacion % no existe en app_dat_producto_presentacion',
            p_id_presentacion
            USING ERRCODE = '22023';
    END IF;

    IF v_id_producto_real <> p_id_producto THEN
        RAISE EXCEPTION
            'id_presentacion % pertenece al producto %, no al producto %',
            p_id_presentacion, v_id_producto_real, p_id_producto
            USING ERRCODE = '22023';
    END IF;

    RETURN p_id_presentacion;
END;
$$;

COMMENT ON FUNCTION public.fn_validar_id_presentacion(bigint, bigint) IS
    'Valida que id_presentacion sea app_dat_producto_presentacion.id del producto '
    'indicado. Distingue el error comun de mandar app_nom_presentacion.id.';

GRANT EXECUTE ON FUNCTION public.fn_validar_id_presentacion(bigint, bigint)
    TO anon, authenticated, service_role;


-- ============================================================================
-- VERIFICACION (correr despues de aplicar; no modifica datos)
-- ============================================================================
-- 1. Cadena de un producto real de 3 niveles (1140 "Refresco Rayan":
--    Cajon x576 | Caja x24 | Unidad x1 [base]).
--    Esperado: 3 filas, nivel 1..3, factor_rel 576/24/1,
--    factor_hijo 24 / 24 / NULL  (1 cajon = 24 cajas, 1 caja = 24 unidades).
--
--   SELECT nivel, nombre, factor, factor_rel, es_base,
--          id_presentacion_hijo, factor_hijo, factor_padre
--     FROM public.fn_presentaciones_producto(1140);
--
-- 2. Producto con base mal capturada (7075 "Cerveza Coronita": Unidad x24 base).
--    Esperado: factor_rel = 1.0 aunque factor = 24.0.
--
--   SELECT nombre, factor, factor_rel, es_base
--     FROM public.fn_presentaciones_producto(7075);
--
-- 3. Formateo puro (no toca la base).
--    Esperado: '4 Cajas + 4 Unidades' / '4 CAJ + 4 UNI' / 'Sin stock'
--
--   SELECT public.fn_formatear_stock_mixto(
--            '[{"nombre":"Caja","cantidad":4,"sku_codigo":"CAJ"},
--               {"nombre":"Unidad","cantidad":4,"sku_codigo":"UNI"}]'::jsonb) AS largo,
--          public.fn_formatear_stock_mixto(
--            '[{"nombre":"Caja","cantidad":4,"sku_codigo":"CAJ"},
--               {"nombre":"Unidad","cantidad":4,"sku_codigo":"UNI"}]'::jsonb, true) AS corto,
--          public.fn_formatear_stock_mixto(
--            '[{"nombre":"Caja","cantidad":0}]'::jsonb) AS vacio,
--          public.fn_plural_presentacion('Cajón', 3) AS plural_cajon;
--
-- 4. Saldos y equivalente de un producto con stock real.
--
--   SELECT * FROM public.fn_stock_saldos_presentacion(1140);
--   SELECT public.fn_equivalente_base(1140);
--   SELECT jsonb_pretty(public.fn_stock_mixto_json(1140));
--
-- 5. Validacion de IDs. La primera pasa, las otras dos deben fallar.
--
--   SELECT public.fn_validar_id_presentacion(1140, 1262);  -- OK -> 1262
--   SELECT public.fn_validar_id_presentacion(1140, 3);     -- ERROR: es del catalogo
--   SELECT public.fn_validar_id_presentacion(1140, 1261 + 100000); -- ERROR: no existe
