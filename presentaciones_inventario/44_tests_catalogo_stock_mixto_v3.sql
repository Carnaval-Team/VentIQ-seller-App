-- ============================================================================
-- 44 · Tests del catalogo con stock mixto (v3 / v2 / helper)
-- ============================================================================
-- Todos los bloques son de SOLO LECTURA: no crean datos, no escriben el ledger.
-- Los que necesitan JWT van con BEGIN/ROLLBACK y `SET LOCAL role authenticated`
-- + `request.jwt.claims`, simulando al vendedor. Sin eso la guarda
-- `check_user_has_access_to_tienda` aborta con «Acceso denegado», que es
-- justamente lo que prueba el bloque E.
--
-- UUID usado: 5016cee9-3665-452d-ba75-6d38900e3a1a (vendedor del TPV 224,
-- tienda 223 "Restaurant perla negra"). Sustituir si se corre en otra tienda.
--
-- Datos reales usados como referencia (verificados en produccion 2026-09-14):
--   producto 11007 "cerveza cristal", tienda 223, almacen 331:
--     Cajon x30 = 13 | Caja x24 = 48 | Blister x6 = 73 | Unidad x1 = 19
--     fisico 153   equivalente base 1999
--   producto   ??? "prod azucar multiipresentacion", misma tienda/almacen:
--     Caja x? = 49 | Bulto x? = 2.8
--     fisico 51.8  equivalente base 1190
-- ============================================================================


-- ============================================================================
-- BLOQUE A · fn_catalogo_stock_meta, el helper
-- ============================================================================

-- A1 · El caso reportado por el usuario: 153 fisico vs 1999 base, texto mixto.
--      Esperado: texto "13 Cajones + 48 Cajas + 73 Blisteres + 19 Unidades",
--                fisico 153, equiv 1999, mixto true, n_pres 4, filas 4.
SELECT (m->>'stock_texto')                       AS texto,
       (m->>'stock_texto_corto')                 AS texto_corto,
       (m->>'stock_total_fisico')::numeric       AS fisico,
       (m->>'stock_equivalente_base')::numeric   AS equiv,
       (m->>'stock_mixto')::boolean              AS mixto,
       (m->>'stock_n_presentaciones')::int       AS n_pres,
       (m->>'stock_filas')::int                  AS filas,
       (m->>'stock_con_variantes')::boolean      AS con_variantes
  FROM public.fn_catalogo_stock_meta(11007, 331) AS m;

-- A2 · El desglose viene ORDENADO de mayor a menor empaque (nivel 1 = Cajon)
--      y cada fila lleva su factor_rel y su equivalente.
SELECT e.value->>'nivel'            AS nivel,
       e.value->>'nombre'           AS nombre,
       (e.value->>'cantidad')::numeric      AS saldo,
       (e.value->>'factor_rel')::numeric    AS factor_rel,
       (e.value->>'equivalente_base')::numeric AS equiv
  FROM public.fn_catalogo_stock_meta(11007, 331) AS m,
       jsonb_array_elements(m->'stock_desglose') AS e(value)
 ORDER BY (e.value->>'nivel')::int;

-- A3 · Suma de control: los equivalentes del desglose suman el total.
--      Esperado: cuadra = true.
SELECT (sum((e.value->>'equivalente_base')::numeric) = (m->>'stock_equivalente_base')::numeric) AS cuadra
  FROM public.fn_catalogo_stock_meta(11007, 331) AS m,
       jsonb_array_elements(m->'stock_desglose') AS e(value);

-- A4 · Casos borde: SIEMPRE devuelve jsonb (nunca NULL) y con filas = 0.
--      - almacen de otra tienda (1 = Carnaval) -> no filtra datos ajenos
--      - producto inexistente
--      - producto sin stock en ese almacen (332 es el otro TPV de la tienda)
--      - almacen NULL
SELECT 'almacen_ajeno'      AS caso, (m->>'stock_filas')::int AS filas,
       (m->>'stock_mixto')::boolean AS mixto, (m->>'stock_texto') AS texto
  FROM public.fn_catalogo_stock_meta(10798, 1) AS m
UNION ALL
SELECT 'producto_inexistente', (m->>'stock_filas')::int, (m->>'stock_mixto')::boolean, m->>'stock_texto'
  FROM public.fn_catalogo_stock_meta(99999999, 331) AS m
UNION ALL
SELECT 'sin_stock_en_almacen', (m->>'stock_filas')::int, (m->>'stock_mixto')::boolean, m->>'stock_texto'
  FROM public.fn_catalogo_stock_meta(11007, 332) AS m
UNION ALL
SELECT 'almacen_null', (m->>'stock_filas')::int, (m->>'stock_mixto')::boolean, m->>'stock_texto'
  FROM public.fn_catalogo_stock_meta(11007, NULL) AS m;


-- ============================================================================
-- BLOQUE B · No-regresion del catalogo (lo importante: no romper nada)
-- ============================================================================

-- B1 · viva vs v3 sobre TODO el catalogo de la tienda 223: filas, y las 6
--      columnas que la app ya consume + las 4 claves de metadata de antes.
--      Esperado: filas iguales, dif_* = 0.
BEGIN;
SET LOCAL role authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"5016cee9-3665-452d-ba75-6d38900e3a1a","role":"authenticated"}';

WITH viva AS (SELECT * FROM public.get_productos_by_categoria_tpv_search_meta(NULL,223,224,NULL,false)),
     nue  AS (SELECT * FROM public.get_productos_by_categoria_tpv_search_meta_v3(NULL,223,224,NULL,false))
SELECT (SELECT count(*) FROM viva) AS filas_viva,
       (SELECT count(*) FROM nue)  AS filas_v3,
       (SELECT count(*) FROM viva v JOIN nue n USING(id_producto)
         WHERE v.stock_disponible IS DISTINCT FROM n.stock_disponible)   AS dif_stock,
       (SELECT count(*) FROM viva v JOIN nue n USING(id_producto)
         WHERE v.tiene_stock IS DISTINCT FROM n.tiene_stock)             AS dif_tiene_stock,
       (SELECT count(*) FROM viva v JOIN nue n USING(id_producto)
         WHERE v.precio_venta IS DISTINCT FROM n.precio_venta)           AS dif_precio,
       (SELECT count(*) FROM viva v JOIN nue n USING(id_producto)
         WHERE v.denominacion IS DISTINCT FROM n.denominacion)           AS dif_nombre,
       (SELECT count(*) FROM viva v JOIN nue n USING(id_producto)
         WHERE (v.metadata->>'es_elaborado')       IS DISTINCT FROM (n.metadata->>'es_elaborado')
            OR (v.metadata->>'es_servicio')        IS DISTINCT FROM (n.metadata->>'es_servicio')
            OR (v.metadata->>'es_paquete')         IS DISTINCT FROM (n.metadata->>'es_paquete')
            OR (v.metadata->>'reservado_carnaval') IS DISTINCT FROM (n.metadata->>'reservado_carnaval')) AS dif_metadata_base;
ROLLBACK;

-- B2 · Contrato: la v3 tiene las 4 claves de metadata de la viva MAS las 9
--      nuevas, y ninguna clave quedo con valor NULL donde la viva traia dato.
--      Esperado: claves_viva = 4, claves_v3 = 13.
BEGIN;
SET LOCAL role authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"5016cee9-3665-452d-ba75-6d38900e3a1a","role":"authenticated"}';
SELECT (SELECT count(*) FROM (
          SELECT jsonb_object_keys(metadata) FROM public.get_productos_by_categoria_tpv_search_meta(NULL,223,224,NULL,false)
        ) t) AS claves_viva,
       (SELECT count(*) FROM (
          SELECT jsonb_object_keys(metadata) FROM public.get_productos_by_categoria_tpv_search_meta_v3(NULL,223,224,NULL,false)
        ) t) AS claves_v3;
ROLLBACK;

-- B3 · Los productos mixtos de la tienda: el texto y el equivalente.
--      Esperado hoy: 2 productos ("cerveza cristal" 153/1999 y
--      "prod azucar multiipresentacion" 51.8/1190).
BEGIN;
SET LOCAL role authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"5016cee9-3665-452d-ba75-6d38900e3a1a","role":"authenticated"}';
SELECT n.denominacion,
       n.stock_disponible                                      AS numero_de_hoy,
       n.metadata->>'stock_texto'                              AS texto_nuevo,
       (n.metadata->>'stock_equivalente_base')::numeric         AS equiv_base,
       (n.metadata->>'stock_total_fisico')::numeric             AS fisico
  FROM public.get_productos_by_categoria_tpv_search_meta_v3(NULL,223,224,NULL,false) n
 WHERE (n.metadata->>'stock_mixto')::boolean = true
 ORDER BY n.denominacion;
ROLLBACK;

-- B4 · Un producto de UNA sola presentacion: fisico == stock_disponible de la
--      viva y mixto = false. Cero regresion visual.
--      Esperado en las 3 primeras filas: fisico = numero_de_hoy, mixto falso.
BEGIN;
SET LOCAL role authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"5016cee9-3665-452d-ba75-6d38900e3a1a","role":"authenticated"}';
SELECT v.denominacion,
       v.stock_disponible,
       (v.metadata->>'stock_total_fisico')::numeric AS fisico,
       (v.metadata->>'stock_mixto')::boolean        AS mixto
  FROM public.get_productos_by_categoria_tpv_search_meta_v3(NULL,223,224,NULL,false) v
 WHERE (v.metadata->>'stock_mixto')::boolean = false
 ORDER BY v.denominacion
 LIMIT 5;
ROLLBACK;

-- B5 · El buscador tambien (mismo contrato, con text_search). Se busca la
--      palabra del caso reportado.
--      Esperado: sale "cerveza cristal" con su texto mixto.
BEGIN;
SET LOCAL role authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"5016cee9-3665-452d-ba75-6d38900e3a1a","role":"authenticated"}';
SELECT v.denominacion, v.metadata->>'stock_texto' AS texto
  FROM public.get_productos_by_categoria_tpv_search_meta_v3(NULL,223,224,'cristal',false) v;
ROLLBACK;


-- ============================================================================
-- BLOQUE C · v2 de casa matriz: el fan-out del precio
-- ============================================================================

-- C1 · La viva repite el producto si tiene varias filas de precio activo.
--      Aqui no hay ninguno en la tienda 223, asi que las dos dan lo mismo.
--      Para ver el bug hay que correrlo en una tienda con precios duplicados
--      (el 26 lo midio: 2.198 productos con mas de una fila activa, 1.040 con
--      precios distintos, hasta 24 filas en un producto).
--      Esperado: filas_viva = filas_v2 y duplicados = 0 en la 223.
BEGIN;
SET LOCAL role authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"5016cee9-3665-452d-ba75-6d38900e3a1a","role":"authenticated"}';
WITH viva AS (SELECT id_producto, count(*) AS n FROM public.get_productos_by_categoria_tpv(NULL,223,224,false) GROUP BY id_producto),
     nue  AS (SELECT id_producto, count(*) AS n FROM public.get_productos_by_categoria_tpv_v2(NULL,223,224,false) GROUP BY id_producto)
SELECT (SELECT sum(n) FROM viva) AS filas_viva,
       (SELECT sum(n) FROM nue)  AS filas_v2,
       (SELECT count(*) FROM viva WHERE n > 1) AS duplicados_viva,
       (SELECT count(*) FROM nue  WHERE n > 1) AS duplicados_v2;
ROLLBACK;

-- C2 · Cuantos productos de TODA la base tienen mas de un precio activo: es la
--      exposicion real del bug que arregla la v2. Solo lectura, sin JWT.
SELECT count(*) AS productos_con_precio_multiplicado,
       max(n)   AS max_filas_de_un_producto
  FROM (
    SELECT id_producto, count(*) AS n
      FROM app_dat_precio_venta
     WHERE (fecha_hasta IS NULL OR fecha_hasta >= CURRENT_DATE)
     GROUP BY id_producto
    HAVING count(*) > 1
  ) t;


-- ============================================================================
-- BLOQUE D · Seguridad: ACL, search_path y aislamiento entre tiendas
-- ============================================================================

-- D1 · ACL por aclexplode. Esperado: una fila por funcion, grantee authenticated.
--      (NO usar information_schema.routine_privileges con rol postgres: da una
--       fila por cada concesion implicita y un falso "esta todo concedido".)
SELECT p.proname, g.grantee::regrole::text AS grantee, g.privilege_type
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  CROSS JOIN LATERAL aclexplode(p.proacl) AS g
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_catalogo_stock_meta',
                     'get_productos_by_categoria_tpv_search_meta_v3',
                     'get_productos_by_categoria_tpv_v2')
 ORDER BY p.proname, grantee;

-- D2 · search_path fijo (anti search_path hijacking) + SECURITY DEFINER.
--      Esperado: las 3 con proconfig {search_path=} y prosecdef true.
SELECT p.proname, p.prosecdef, p.proconfig
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_catalogo_stock_meta',
                     'get_productos_by_categoria_tpv_search_meta_v3',
                     'get_productos_by_categoria_tpv_v2')
 ORDER BY p.proname;

-- D3 · Aislamiento entre tiendas: el vendedor es de la 223, pedir la 11 tiene
--      que ABORTAR la transaccion con «Acceso denegado».
--      Esperado: ERROR P0001 (no una lista vacia).
BEGIN;
SET LOCAL role authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"5016cee9-3665-452d-ba75-6d38900e3a1a","role":"authenticated"}';
SELECT * FROM public.get_productos_by_categoria_tpv_search_meta_v3(NULL, 11, NULL, NULL, false);
ROLLBACK;

-- D4 · Sin JWT (rol anon) tambien tiene que negar: no hay GRANT para anon.
--      Esperado: ERROR P0001. El REVOKE de PUBLIC ya se aplico, asi que el
--      fallo real puede ser 42501 (permiso denegado) ANTES de la guarda.
BEGIN;
SET LOCAL role anon;
SELECT * FROM public.get_productos_by_categoria_tpv_search_meta_v3(NULL, 223, 224, NULL, false);
ROLLBACK;


-- ============================================================================
-- BLOQUE E · Lo que este archivo NO toca (regresion de las funciones vivas)
-- ============================================================================

-- E1 · Las vivas siguen con su cuerpo y su ACL de siempre.
--      Esperado: search_meta largo 10.058 y proconfig NULL (sin SET search_path),
--                tpv largo 5.110. Si el largo cambio, alguien las reemplazo.
SELECT p.proname, p.oid::regprocedure AS firma, length(p.prosrc) AS largo,
       p.prosecdef AS secdef, p.proconfig
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('get_productos_by_categoria_tpv_search_meta',
                     'get_productos_by_categoria_tpv')
 ORDER BY p.proname;

-- E2 · La viva sigue devolviendo 4 claves de metadata (no le agregamos las 9).
--      Esperado: 4.
BEGIN;
SET LOCAL role authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"5016cee9-3665-452d-ba75-6d38900e3a1a","role":"authenticated"}';
SELECT count(*) AS claves_metadata_viva
  FROM (
    SELECT jsonb_object_keys(metadata) FROM public.get_productos_by_categoria_tpv_search_meta(NULL,223,224,NULL,false)
  ) t;
ROLLBACK;


-- ============================================================================
-- BLOQUE F · El pitfall que se comio la primera version de este archivo
-- ============================================================================

-- F1 · `SET search_path = ''` + una guarda que resuelve tablas SIN calificar
--      = 42P01. Se corrigio con
--      `PERFORM set_config('search_path','public, pg_catalog',false);` ANTES
--      de la guarda. Esta prueba confirma que las 3 funciones nuevas la llevan:
--      si el cuerpo NO contiene el set_config, devuelve 'FALTA'.
SELECT p.proname,
       CASE WHEN p.prosrc LIKE '%set_config(''search_path''%'
            THEN 'OK lleva set_config antes de la guarda'
            ELSE 'FALTA set_config: la guarda fallara con 42P01'
       END AS estado
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_catalogo_stock_meta',
                     'get_productos_by_categoria_tpv_search_meta_v3',
                     'get_productos_by_categoria_tpv_v2')
 ORDER BY p.proname;