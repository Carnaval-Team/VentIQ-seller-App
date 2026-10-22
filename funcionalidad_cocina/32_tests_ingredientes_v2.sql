-- ============================================================================
-- 32 · Fase 1 · Tests transaccionales de la cadena _v2 de ingredientes
-- ============================================================================
-- Proyectos Supabase: debug qhprswhhfasrikhawjoz + produccion vsieeihstajlrdvpuooh
-- Requiere: 30_ingredientes_por_equivalente_base.sql y 31_ingredientes_v2_rutas.sql.
--
-- ----------------------------------------------------------------------------
-- COMO CORRERLO (importante)
-- ----------------------------------------------------------------------------
-- El MCP de Supabase de produccion de esta sesion es de SOLO LECTURA
-- (`current_user = supabase_read_only_user`, `default_transaction_read_only = on`):
-- cualquier DDL/DML falla con 25006 "cannot execute ... in a read-only
-- transaction". Por eso esta suite NO se pudo ejecutar desde el MCP; hay que
-- correrla con un rol de escritura (SQL Editor del dashboard, o el MCP del
-- proyecto debug) y SIEMPRE dentro de BEGIN ... ROLLBACK.
--
-- Si 30 y 31 YA estan aplicados:
--     pegar cada bloque (BEGIN ... ROLLBACK) por separado.
-- Si NO estan aplicados (probar sin dejar nada):
--     BEGIN;
--     <contenido completo de 30_ingredientes_por_equivalente_base.sql>
--     <contenido completo de 31_ingredientes_v2_rutas.sql>
--     <este archivo>
--     ROLLBACK;
--
-- Nada de aqui escribe de verdad: todos los bloques cierran con ROLLBACK, y las
-- fixtures (presentaciones, ubicaciones y filas de ledger sinteticas) se van con
-- el. Los ids de fixture son 9990000xx para no chocar con datos reales.
--
-- ----------------------------------------------------------------------------
-- DATOS REALES USADOS (medidos en produccion 2026-10-21, solo lectura)
-- ----------------------------------------------------------------------------
--   product 10924 "dfg"      tienda 223 | 1 presentacion: pp 11101 = Unidad (nom 1)
--                                         cantidad 1, es_base, factor_rel 1
--   product 11007 "cerveza cristal" tienda 223, almacen 331, ubicacion 349:
--        Cajon  (pp 11200, x30) = 13   -> 390 base
--        Caja   (pp 11198, x24) = 30   -> 720 base
--        Blister(pp 11199, x6)  = 23   -> 138 base
--        Unidad (pp 11197, x1)  =  2   ->   2 base
--        equivalente 1250; 30/24 = 1.25 NO es entero => maximo con empaques
--        enteros = 860 (390 no es abrible, 720+138+2 si)
--   elaborado 10800 "tacos" tienda 223, cocina 39 "Cocina caliente" (almacen 333),
--        receta/unidad: 10798 "Harina 1" x 0.03 | 10799 "Sal Yodada" x 0.003
--        stock almacen 331: Harina 770, Sal 766.9999 | almacen 333: 1230 / 1232.9993
--        pp 10943 = Unidad (nom 1) cantidad 1, es_base | saldo 1 en ubicacion 350
--   TPV 224 (tienda 223, almacen 331) ligado a la cocina 39; vendedor de la
--        tienda: uuid 5016cee9-3665-452d-ba75-6d38900e3a1a
--   app_nom_presentacion: Unidad 1 | Paquete 2 | Caja 3 | Bulto 7 | Kilogramo 15 |
--        Gramo 16 | Blister 22 | Cajon 23
--
-- ----------------------------------------------------------------------------
-- IDENTIDAD PARA LA GUARDA (C9)
-- ----------------------------------------------------------------------------
-- fn_ejecutar_entrega_fisica_v3 (y con ella toda la cadena) llama a
-- check_user_has_access_to_tienda, que usa auth.uid(). En el SQL Editor auth.uid()
-- es NULL y la guarda aborta con "Acceso denegado": por eso cada bloque simula al
-- vendedor real de la tienda 223 con request.jwt.claims. Corriendo como
-- `authenticated` hay que anadir `SET LOCAL role authenticated;` antes.
-- ============================================================================


-- ############################################################################
-- ⚠️ AVISO · ESTE ARCHIVO SON PRUEBAS CON FIXTURES DE PRODUCCIÓN
-- (producto 10924/11007/10800, almacén 331, tienda 223, vendedor
--  5016cee9-...). En un proyecto donde esos datos no existan (p. ej. debug
--  `qhprswhhfasrikhawjoz`), NO lo apliques: no contiene DDL y sus bloques
--  fallarán por fixture ausente. En debug se prueban los objetos de 30/31 con
--  `docs/APLICACION_PRESENTACIONES_INGREDIENTES.md` §4 (caso real).
-- ############################################################################

-- ============================================================================
-- BLOQUE 0 · CASO REAL DE §2-bis REPLICADO (empate 2000 u / 2000 kg)
-- El defecto: el bucle viejo compara la cantidad FISICA (2000) con el pendiente
-- en BASE (6000) y deja el Kilogramo en CERO. Aqui se exige que NO quede en cero
-- y que se consuman exactamente 6000 base.
-- ============================================================================
BEGIN;
SELECT set_config('request.jwt.claims', '{"sub":"5016cee9-3665-452d-ba75-6d38900e3a1a","role":"authenticated"}', true);

-- Fixture: presentacion "Kilogramo" (x1000) sobre la base Unidad de 10924.
INSERT INTO public.app_dat_producto_presentacion (id, id_producto, id_presentacion, cantidad, es_base)
VALUES (999000001, 10924, 15, 1000, false);

-- Fixture: Unidad 2000 + Kilogramo 2000 en la MISMA ubicacion (el empate de §2-bis).
INSERT INTO public.app_dat_inventario_productos
    (id, id_producto, id_ubicacion, id_presentacion, cantidad_inicial, cantidad_final, origen_cambio, created_at)
SELECT (SELECT COALESCE(MAX(id),0) FROM public.app_dat_inventario_productos) + row_number() OVER (),
       v.id_producto, v.id_ubicacion, v.id_presentacion, v.cantidad, v.cantidad, 4, now()
  FROM (VALUES (10924::bigint, 349::bigint, 11101::bigint,     2000::numeric),
               (10924::bigint, 349::bigint, 999000001::bigint, 2000::numeric)
       ) AS v(id_producto, id_ubicacion, id_presentacion, cantidad);

-- 0.1 · Medida previa: equivalente 2.002.000 y maximo consumible el mismo.
SELECT public.fn_ingrediente_base_alcanzable(10924, 331, 'almacen', 6000) AS kernel;
-- Esperado: status=success | alcanza=true | descomposicion_entera=true
--           saldo_propio=2000 | equivalente_base=2002000 | maximo_producible=2002000
--           cadena: nivel 1 = 999000001 Kilogramo factor_rel 1000 usable=true

-- 0.2 · Consumo de 6000 base.
SELECT public.fn_consumir_ingrediente_base_v2(10924, 331, 6000, 4, NULL, NULL, gen_random_uuid(), 'test_t0') AS consumo;
-- Esperado: status=success | equivalente_consumido=6000 | lineas_afectadas=2
--           conversiones: 1 (Kilogramo 4 -> Unidad 4000, procedencia saldo_y_conversion)

-- 0.3 · Saldos finales por presentacion: EL KILOGRAMO NO QUEDA EN CERO.
SELECT s.id_presentacion, COALESCE(np.denominacion,'?') AS presentacion, SUM(s.saldo) AS saldo_final
  FROM public.fn_stock_saldos_presentacion(10924, 331, NULL, true) s
  LEFT JOIN public.app_dat_producto_presentacion pp ON pp.id = s.id_presentacion
  LEFT JOIN public.app_nom_presentacion np ON np.id = pp.id_presentacion
 GROUP BY 1,2
 ORDER BY 1;
-- Esperado: 11101 Unidad = 0 | 999000001 Kilogramo = 1996   <-- NO 0

-- 0.4 · Sin saldos negativos, equivalencia exacta y conversion auditada.
SELECT count(*) AS filas_negativas
  FROM public.fn_stock_saldos_presentacion(10924, 331, NULL, false) WHERE saldo < 0;
-- Esperado: 0
SELECT public.fn_stock_producto_almacen(10924, 331) AS equivalente_final;
-- Esperado: 1996000  (2002000 - 6000)
SELECT count(*) AS conversiones_auditadas
  FROM public.app_dat_conversion_presentacion WHERE id_producto = 10924;
-- Esperado: 1
ROLLBACK;


-- ============================================================================
-- BLOQUE 1 · RECETA 5000 BASE CON 3 kg EN UNA UBICACION
-- 1a: pide 3000 con 1000 u + 3 kg -> abre 2 kg y quedan 1 kg (enteros)
-- 1b: pide 5000 con lo mismo -> maximo 4000: error explicito y CERO filas nuevas
-- ============================================================================
BEGIN;
SELECT set_config('request.jwt.claims', '{"sub":"5016cee9-3665-452d-ba75-6d38900e3a1a","role":"authenticated"}', true);

INSERT INTO public.app_dat_producto_presentacion (id, id_producto, id_presentacion, cantidad, es_base)
VALUES (999000001, 10924, 15, 1000, false);

INSERT INTO public.app_dat_inventario_productos
    (id, id_producto, id_ubicacion, id_presentacion, cantidad_inicial, cantidad_final, origen_cambio, created_at)
SELECT (SELECT COALESCE(MAX(id),0) FROM public.app_dat_inventario_productos) + row_number() OVER (),
       v.id_producto, v.id_ubicacion, v.id_presentacion, v.cantidad, v.cantidad, 4, now()
  FROM (VALUES (10924::bigint, 349::bigint, 11101::bigint,     1000::numeric),
               (10924::bigint, 349::bigint, 999000001::bigint,    3::numeric)
       ) AS v(id_producto, id_ubicacion, id_presentacion, cantidad);

-- 1a · 3000 base: pasada 1 consume las 1000 u; pasada 2 abre 2 kg (2000 u).
SELECT public.fn_consumir_ingrediente_base_v2(10924, 331, 3000, 4, NULL, NULL, gen_random_uuid(), 'test_t1a') AS consumo_3000;
-- Esperado: status=success | equivalente_consumido=3000 | 1 conversion (2 kg -> 2000 u)
SELECT s.id_presentacion, SUM(s.saldo) AS saldo_final
  FROM public.fn_stock_saldos_presentacion(10924, 331, NULL, true) s
 GROUP BY 1 ORDER BY 1;
-- Esperado: 11101 = 0 | 999000001 = 1   (queda 1 kg = 1000 base; equivalente total 1000)
SELECT public.fn_stock_producto_almacen(10924, 331) AS equivalente_final;
-- Esperado: 1000   (4000 - 3000)

-- 1b · 5000 base con el mismo stock (maximo 4000): error y CERO filas nuevas.
SELECT count(*) AS filas_ledger_antes FROM public.app_dat_inventario_productos;
SELECT public.fn_consumir_ingrediente_base_v2(10924, 331, 5000, 4, NULL, NULL, gen_random_uuid(), 'test_t1b') AS consumo_5000;
-- Esperado: status=error | error_code=INSUFFICIENT_STOCK_INGREDIENT | maximo_producible=4000
--           motivo=STOCK_BASE_INSUFICIENTE | cero escrituras
SELECT count(*) AS filas_ledger_despues FROM public.app_dat_inventario_productos;
-- Esperado: igual que filas_ledger_antes
ROLLBACK;


-- ============================================================================
-- BLOQUE 2 · EL kg EN OTRA UBICACION DEL MISMO ALMACEN (pasada 2)
-- Ubicacion A: 5 Unidad | Ubicacion B (nueva): 2 kg. Pide 1000 base.
-- ============================================================================
BEGIN;
SELECT set_config('request.jwt.claims', '{"sub":"5016cee9-3665-452d-ba75-6d38900e3a1a","role":"authenticated"}', true);

INSERT INTO public.app_dat_producto_presentacion (id, id_producto, id_presentacion, cantidad, es_base)
VALUES (999000001, 10924, 15, 1000, false);

-- Ubicacion B del mismo almacen 331 (fixture; se va con el ROLLBACK).
INSERT INTO public.app_dat_layout_almacen (id, id_almacen, id_tipo_layout, denominacion)
VALUES (999000100, 331, (SELECT l.id_tipo_layout FROM public.app_dat_layout_almacen l WHERE l.id = 349), 'TEST Fase1 B');

INSERT INTO public.app_dat_inventario_productos
    (id, id_producto, id_ubicacion, id_presentacion, cantidad_inicial, cantidad_final, origen_cambio, created_at)
SELECT (SELECT COALESCE(MAX(id),0) FROM public.app_dat_inventario_productos) + row_number() OVER (),
       v.id_producto, v.id_ubicacion, v.id_presentacion, v.cantidad, v.cantidad, 4, now()
  FROM (VALUES (10924::bigint, 349::bigint,       11101::bigint,     5::numeric),
               (10924::bigint, 999000100::bigint, 999000001::bigint, 2::numeric)
       ) AS v(id_producto, id_ubicacion, id_presentacion, cantidad);

SELECT public.fn_ingrediente_base_alcanzable(10924, 331, 'almacen', 1000) AS kernel;
-- Esperado: saldo_propio=5 | convertible_base=2000 | maximo_producible=2005 | alcanza=true
--           ubicaciones: 349 saldo_propio 5 convertible 0 | 999000100 saldo_propio 0 convertible 2000

SELECT public.fn_consumir_ingrediente_base_v2(10924, 331, 1000, 4, NULL, NULL, gen_random_uuid(), 'test_t2') AS consumo;
-- Esperado: status=success | equivalente_consumido=1000 | pasada 1 en 349 (5) y pasada 2 en 999000100 (995)
SELECT s.id_ubicacion, s.id_presentacion, SUM(s.saldo) AS saldo_final
  FROM public.fn_stock_saldos_presentacion(10924, 331, NULL, true) s
 GROUP BY 1,2 ORDER BY 1,2;
-- Esperado: 349 / 11101 = 0 | 999000100 / 999000001 = 1 (queda 1 kg) | 999000100 / 11101 = 5
SELECT public.fn_stock_producto_almacen(10924, 331) AS equivalente_final;
-- Esperado: 1005   (2005 - 1000)
ROLLBACK;


-- ============================================================================
-- BLOQUE 3 · 2 UBICACIONES x 2 PRESENTACIONES, BASE EXACTA Y 0 NEGATIVOS
-- A: 7 Unidad + 1 kg | B: 3 Unidad + 2 kg. Pide 2500 base.
-- ============================================================================
BEGIN;
SELECT set_config('request.jwt.claims', '{"sub":"5016cee9-3665-452d-ba75-6d38900e3a1a","role":"authenticated"}', true);

INSERT INTO public.app_dat_producto_presentacion (id, id_producto, id_presentacion, cantidad, es_base)
VALUES (999000001, 10924, 15, 1000, false);

INSERT INTO public.app_dat_layout_almacen (id, id_almacen, id_tipo_layout, denominacion)
VALUES (999000100, 331, (SELECT l.id_tipo_layout FROM public.app_dat_layout_almacen l WHERE l.id = 349), 'TEST Fase1 B');

INSERT INTO public.app_dat_inventario_productos
    (id, id_producto, id_ubicacion, id_presentacion, cantidad_inicial, cantidad_final, origen_cambio, created_at)
SELECT (SELECT COALESCE(MAX(id),0) FROM public.app_dat_inventario_productos) + row_number() OVER (),
       v.id_producto, v.id_ubicacion, v.id_presentacion, v.cantidad, v.cantidad, 4, now()
  FROM (VALUES (10924::bigint, 349::bigint,       11101::bigint,     7::numeric),
               (10924::bigint, 349::bigint,       999000001::bigint, 1::numeric),
               (10924::bigint, 999000100::bigint, 11101::bigint,     3::numeric),
               (10924::bigint, 999000100::bigint, 999000001::bigint, 2::numeric)
       ) AS v(id_producto, id_ubicacion, id_presentacion, cantidad);

SELECT public.fn_consumir_ingrediente_base_v2(10924, 331, 2500, 4, NULL, NULL, gen_random_uuid(), 'test_t3') AS consumo;
-- Esperado: status=success | equivalente_consumido=2500
--           pasada 1: 349 (7) + 999000100 (3) | pasada 2: 999000100 abre 2 kg (2000), 349 abre 1 kg (490)
SELECT s.id_ubicacion, s.id_presentacion, SUM(s.saldo) AS saldo_final
  FROM public.fn_stock_saldos_presentacion(10924, 331, NULL, true) s
 GROUP BY 1,2 ORDER BY 1,2;
-- Esperado: 349 / 11101 = 510 | 349 / 999000001 = 0 | 999000100 / 11101 = 0 | 999000100 / 999000001 = 0
SELECT public.fn_stock_producto_almacen(10924, 331) AS equivalente_final,
       (SELECT count(*) FROM public.fn_stock_saldos_presentacion(10924, 331, NULL, false) WHERE saldo < 0) AS negativos;
-- Esperado: equivalente_final = 510  (3010 - 2500) | negativos = 0
SELECT count(*) AS filas_fraccionarias
  FROM public.fn_stock_saldos_presentacion(10924, 331, NULL, true) s
  LEFT JOIN public.fn_presentaciones_producto(10924) f ON f.id_presentacion = s.id_presentacion
 WHERE s.id_presentacion <> 11101 AND s.saldo <> trunc(s.saldo);
-- Esperado: 0 (ninguna presentacion no-base queda fraccionaria)
ROLLBACK;


-- ============================================================================
-- BLOQUE 4 · CADENA NO DIVISIBLE (Caja x24 > Bulto x5 > Unidad x1)
-- 30/24 = 1.25 no es entero: NUNCA se sirve 1,25 Cajas ni 4,8 Bultos.
-- 4a: solo Caja (no abrible) + 2 Unidad -> error explicito, CERO filas
-- 4b: con 3 Bultos -> maximo 17; 15 se sirven enteros
-- ============================================================================
BEGIN;
SELECT set_config('request.jwt.claims', '{"sub":"5016cee9-3665-452d-ba75-6d38900e3a1a","role":"authenticated"}', true);

INSERT INTO public.app_dat_producto_presentacion (id, id_producto, id_presentacion, cantidad, es_base)
VALUES (999000002, 10924, 3, 24, false),   -- Caja x24
       (999000003, 10924, 7,  5, false);   -- Bulto x5

INSERT INTO public.app_dat_inventario_productos
    (id, id_producto, id_ubicacion, id_presentacion, cantidad_inicial, cantidad_final, origen_cambio, created_at)
SELECT (SELECT COALESCE(MAX(id),0) FROM public.app_dat_inventario_productos) + row_number() OVER (),
       v.id_producto, v.id_ubicacion, v.id_presentacion, v.cantidad, v.cantidad, 4, now()
  FROM (VALUES (10924::bigint, 349::bigint, 999000002::bigint, 4::numeric),
               (10924::bigint, 349::bigint, 11101::bigint,     2::numeric)
       ) AS v(id_producto, id_ubicacion, id_presentacion, cantidad);

-- 4a · equivalente 98 pero maximo abrible 2 (la Caja no se puede abrir).
SELECT public.fn_ingrediente_base_alcanzable(10924, 331, 'almacen', 20) AS kernel;
-- Esperado: status=success | alcanza=false | descomposicion_entera=false
--           equivalente_base=98 | maximo_producible=2 | motivo=CADENA_NO_DIVISIBLE_EN_ENTEROS
--           cadena nivel 1 (Caja 24) usable=false | nivel 2 (Bulto 5) usable=true | nivel 3 (Unidad 1) usable=true
SELECT count(*) AS filas_ledger_antes FROM public.app_dat_inventario_productos;
SELECT public.fn_consumir_ingrediente_base_v2(10924, 331, 20, 4, NULL, NULL, gen_random_uuid(), 'test_t4a') AS consumo;
-- Esperado: status=error | error_code=INSUFFICIENT_STOCK_INGREDIENT | cantidad_disponible=2
--           motivo=CADENA_NO_DIVISIBLE_EN_ENTEROS | CERO escrituras
SELECT count(*) AS filas_ledger_despues FROM public.app_dat_inventario_productos;
-- Esperado: igual que filas_ledger_antes

-- 4b · Se anaden 3 Bultos: maximo 2 + 15 = 17; se sirven 15 ENTEROS.
INSERT INTO public.app_dat_inventario_productos
    (id, id_producto, id_ubicacion, id_presentacion, cantidad_inicial, cantidad_final, origen_cambio, created_at)
SELECT (SELECT COALESCE(MAX(id),0) FROM public.app_dat_inventario_productos) + 1,
       10924, 349, 999000003, 3, 3, 4, now();

SELECT public.fn_consumir_ingrediente_base_v2(10924, 331, 15, 4, NULL, NULL, gen_random_uuid(), 'test_t4b') AS consumo_15;
-- Esperado: status=success | equivalente_consumido=15 | 1 conversion (3 Bultos -> 15 u)
SELECT s.id_presentacion, SUM(s.saldo) AS saldo_final
  FROM public.fn_stock_saldos_presentacion(10924, 331, NULL, true) s
 GROUP BY 1 ORDER BY 1;
-- Esperado: 11101 (Unidad) = 2 | 999000002 (Caja) = 4 | 999000003 (Bulto) = 0
--           la Caja NO se toco: 4 Cajas siguen ahi (no se puede abrir)
SELECT public.fn_stock_producto_almacen(10924, 331) AS equivalente_final;
-- Esperado: 98 + 15 - 15 = 98   (2 u + 4 Cajas x24)
ROLLBACK;


-- ============================================================================
-- BLOQUE 5 · INSUFICIENCIA REAL CON 0 FILAS NUEVAS (datos reales, 11007/331)
-- Maximo consumible con empaques enteros = 860 (la relacion Cajon 30 / Caja 24
-- no es entera). Pedir 1000 debe fallar SIN escribir; 860 debe funcionar.
-- ============================================================================
BEGIN;
SELECT set_config('request.jwt.claims', '{"sub":"5016cee9-3665-452d-ba75-6d38900e3a1a","role":"authenticated"}', true);

-- 5.1 · Medida: equivalente 1250 pero maximo abrible 860.
SELECT (public.fn_ingrediente_base_alcanzable(11007, 331, 'almacen', 1000))->>'alcanza'           AS alcanza_1000,
       (public.fn_ingrediente_base_alcanzable(11007, 331, 'almacen', 1000))->>'maximo_producible' AS maximo_1000,
       (public.fn_ingrediente_base_alcanzable(11007, 331, 'almacen', 1000))->>'motivo'            AS motivo_1000,
       (public.fn_ingrediente_base_alcanzable(11007, 331, 'almacen', 1000))->>'equivalente_base'  AS equivalente;
-- Esperado: alcanza_1000=false | maximo_1000=860 | motivo_1000=CADENA_NO_DIVISIBLE_EN_ENTEROS | equivalente=1250

-- 5.2 · Pedir 1000: error y CERO filas nuevas.
SELECT count(*) AS filas_antes FROM public.app_dat_inventario_productos WHERE id_producto = 11007;
SELECT public.fn_consumir_ingrediente_base_v2(11007, 331, 1000, 4, NULL, NULL, gen_random_uuid(), 'test_t5') AS consumo_1000;
-- Esperado: status=error | error_code=INSUFFICIENT_STOCK_INGREDIENT
--           cantidad_disponible=860 | maximo_producible=860 | presenteacion=Unidad | CERO escrituras
SELECT count(*) AS filas_despues FROM public.app_dat_inventario_productos WHERE id_producto = 11007;
-- Esperado: igual que filas_antes

-- 5.3 · Pedir 860: success, quedan 13 Cajones intactos.
SELECT public.fn_consumir_ingrediente_base_v2(11007, 331, 860, 4, NULL, NULL, gen_random_uuid(), 'test_t5b') AS consumo_860;
-- Esperado: status=success | equivalente_consumido=860
SELECT s.id_presentacion, s.presentacion_nombre, s.saldo
  FROM public.fn_stock_saldos_presentacion(11007, 331, NULL, true) s
 ORDER BY s.id_presentacion;
-- Esperado: 11197 Unidad 0 | 11198 Caja 0 | 11199 Blister 0 | 11200 Cajon 13
SELECT public.fn_stock_producto_almacen(11007, 331) AS equivalente_final;
-- Esperado: 390  (1250 - 860)
ROLLBACK;


-- ============================================================================
-- BLOQUE 6 · PRODUCTO DE UNA SOLA PRESENTACION: VIVA vs _v2 (no regresion)
-- Elaborado real 10800 "tacos" (almacen 331): Harina 10798 x0.03 y Sal 10799 x0.003
-- por unidad. Con 10 unidades las dos cadenas deben consumir exactamente lo mismo.
-- ============================================================================
BEGIN;
SELECT set_config('request.jwt.claims', '{"sub":"5016cee9-3665-452d-ba75-6d38900e3a1a","role":"authenticated"}', true);
SELECT public.fn_stock_producto_almacen(10798, 331) AS harina_antes,
       public.fn_stock_producto_almacen(10799, 331) AS sal_antes,
       (SELECT count(*) FROM public.app_dat_inventario_productos) AS filas_antes;
SELECT public.fn_descontar_ingredientes_elaborado(10800, 10, 331, NULL, 4) AS viva;
SELECT public.fn_stock_producto_almacen(10798, 331) AS harina_despues,
       public.fn_stock_producto_almacen(10799, 331) AS sal_despues,
       (SELECT count(*) FROM public.app_dat_inventario_productos) AS filas_despues;
-- Esperado (viva): harina 770 -> 769.7 (-0.3) | sal 766.9999 -> 766.9699 (-0.03) | filas +2
ROLLBACK;

BEGIN;
SELECT set_config('request.jwt.claims', '{"sub":"5016cee9-3665-452d-ba75-6d38900e3a1a","role":"authenticated"}', true);
SELECT public.fn_stock_producto_almacen(10798, 331) AS harina_antes,
       public.fn_stock_producto_almacen(10799, 331) AS sal_antes,
       (SELECT count(*) FROM public.app_dat_inventario_productos) AS filas_antes;
SELECT public.fn_descontar_ingredientes_elaborado_v2(10800, 10, 331, NULL, 4) AS v2;
SELECT public.fn_stock_producto_almacen(10798, 331) AS harina_despues,
       public.fn_stock_producto_almacen(10799, 331) AS sal_despues,
       (SELECT count(*) FROM public.app_dat_inventario_productos) AS filas_despues;
-- Esperado (_v2): IDENTICO a la viva (harina -0.3, sal -0.03, filas +2)
--                 y status=success con lineas_afectadas=2, ingredientes_consumidos=2
ROLLBACK;


-- ============================================================================
-- BLOQUE 7 · 1 CAJA DE ELABORADO -> RECETA x FACTOR
-- Fixture: se agrega 11007 a la receta de 10800 con cantidad_necesaria = 60
-- (60 base por unidad de elaborado). Con 24 unidades (1 Caja de 24, factor 24)
-- el requerimiento debe ser 24 x 60 = 1440.
-- ============================================================================
BEGIN;
SELECT set_config('request.jwt.claims', '{"sub":"5016cee9-3665-452d-ba75-6d38900e3a1a","role":"authenticated"}', true);

INSERT INTO public.app_dat_producto_ingredientes (id, id_producto_elaborado, id_ingrediente, cantidad_necesaria, unidad_medida)
VALUES ((SELECT COALESCE(MAX(id),0)+1 FROM public.app_dat_producto_ingredientes), 10800, 11007, 60, NULL);

-- 7.1 · La receta escala linealmente con la cantidad en base.
SELECT (i.value->>'cantidad_requerida_base')::numeric AS requerido_11007
  FROM public.fn_ingredientes_elaborado_base(10800, 10, 331, 'almacen') b,
       jsonb_array_elements(b->'ingredientes') i(value)
 WHERE (i.value->>'id_ingrediente')::bigint = 11007;
-- Esperado: 600   (10 x 60)
SELECT (i.value->>'cantidad_requerida_base')::numeric AS requerido_11007
  FROM public.fn_ingredientes_elaborado_base(10800, 24, 331, 'almacen') b,
       jsonb_array_elements(b->'ingredientes') i(value)
 WHERE (i.value->>'id_ingrediente')::bigint = 11007;
-- Esperado: 1440  (24 x 60 = 1 Caja x factor 24)
SELECT public.fn_cantidad_en_base(11198, 1) AS una_caja_de_11007_en_base;
-- Esperado: 24

-- 7.2 · Con 10 unidades alcanza (600 <= 860); con 24 NO (1440 > 860) y la
--       validacion lo dice con la MISMA unidad (base) que usaria el consumo.
SELECT public.fn_validar_ingredientes_elaborado_v2(10800, 10, 331) AS valida_10;
SELECT public.fn_validar_ingredientes_elaborado_v2(10800, 24, 331) AS valida_24;
-- Esperado: valida_10 -> status=success
--           valida_24 -> status=error | error_code=INSUFFICIENT_STOCK_INGREDIENT
--                        id_ingrediente=11007 | cantidad_requerida=1440 | cantidad_disponible=860
--                        presentacion=Unidad | unidad=Unidad | maximo_producible_elaborado=14
ROLLBACK;


-- ============================================================================
-- BLOQUE 8 · PRESENTACION BASE CON cantidad <> 1 (no se asume factor = 1)
-- Fixture: la base Unidad de 10924 pasa a cantidad 12 y se agrega "Unidad 1".
-- La cadena queda con el ultimo factor_rel = 1/12 = 0,0833 (no 1): INVALIDA.
-- Validacion y consumo deben rechazarla SIN escribir.
-- ============================================================================
BEGIN;
SELECT set_config('request.jwt.claims', '{"sub":"5016cee9-3665-452d-ba75-6d38900e3a1a","role":"authenticated"}', true);

UPDATE public.app_dat_producto_presentacion SET cantidad = 12 WHERE id = 11101;
INSERT INTO public.app_dat_producto_presentacion (id, id_producto, id_presentacion, cantidad, es_base)
VALUES (999000005, 10924, 1, 1, false);

INSERT INTO public.app_dat_inventario_productos
    (id, id_producto, id_ubicacion, id_presentacion, cantidad_inicial, cantidad_final, origen_cambio, created_at)
SELECT (SELECT COALESCE(MAX(id),0) FROM public.app_dat_inventario_productos) + 1,
       10924, 349, 999000005, 100, 100, 4, now();

SELECT public.fn_ingrediente_base_alcanzable(10924, 331, 'almacen', 5) AS kernel;
-- Esperado: status=error | error_code=INVALID_PRESENTATION_CHAIN
--           cadena: nivel 1 = 11101 factor_rel 1 | nivel 2 = 999000005 factor_rel 0.083333
SELECT count(*) AS filas_antes FROM public.app_dat_inventario_productos;
SELECT public.fn_consumir_ingrediente_base_v2(10924, 331, 5, 4, NULL, NULL, gen_random_uuid(), 'test_t8') AS consumo;
-- Esperado: status=error | error_code=INVALID_PRESENTATION_CHAIN | CERO escrituras
--           (NO se interpreta 5 como "5 Unidad": la base es 12 y el ultimo factor no es 1)
SELECT count(*) AS filas_despues FROM public.app_dat_inventario_productos;
-- Esperado: igual que filas_antes
ROLLBACK;


-- ============================================================================
-- BLOQUE 9 · SALDOS NEGATIVOS PREEXISTENTES: VALIDACION Y CONSUMO DECIDEN IGUAL
-- Fixture: -3 Unidad (fila mas reciente) + 1 kg sobre 10924, y 10924 como
-- ingrediente de 10800. Ni la validacion ni el consumo pueden aceptar.
-- ============================================================================
BEGIN;
SELECT set_config('request.jwt.claims', '{"sub":"5016cee9-3665-452d-ba75-6d38900e3a1a","role":"authenticated"}', true);

INSERT INTO public.app_dat_producto_presentacion (id, id_producto, id_presentacion, cantidad, es_base)
VALUES (999000001, 10924, 15, 1000, false);
INSERT INTO public.app_dat_producto_ingredientes (id, id_producto_elaborado, id_ingrediente, cantidad_necesaria, unidad_medida)
VALUES ((SELECT COALESCE(MAX(id),0)+1 FROM public.app_dat_producto_ingredientes), 10800, 10924, 5, NULL);

INSERT INTO public.app_dat_inventario_productos
    (id, id_producto, id_ubicacion, id_presentacion, cantidad_inicial, cantidad_final, origen_cambio, created_at)
SELECT (SELECT COALESCE(MAX(id),0) FROM public.app_dat_inventario_productos) + row_number() OVER (),
       v.id_producto, v.id_ubicacion, v.id_presentacion, v.cantidad, v.cantidad, 4, now()
  FROM (VALUES (10924::bigint, 349::bigint, 11101::bigint,     (-3)::numeric),
               (10924::bigint, 349::bigint, 999000001::bigint,   1::numeric)
       ) AS v(id_producto, id_ubicacion, id_presentacion, cantidad);

SELECT public.fn_ingrediente_base_alcanzable(10924, 331, 'almacen', 5) AS kernel;
-- Esperado: status=error | error_code=NEGATIVE_STOCK_PRESENTACION | id_presentacion=11101 | saldo -3

SELECT public.fn_validar_ingredientes_elaborado_v2(10800, 1, 331) AS validacion;
-- Esperado: status=error | error_code=INSUFFICIENT_STOCK_INGREDIENT
--           motivo_origen=NEGATIVE_STOCK_PRESENTACION | id_ingrediente=10924

SELECT count(*) AS filas_antes FROM public.app_dat_inventario_productos;
SELECT public.fn_consumir_ingrediente_base_v2(10924, 331, 5, 4, NULL, NULL, gen_random_uuid(), 'test_t9') AS consumo;
-- Esperado: status=error | error_code=NEGATIVE_STOCK_PRESENTACION | CERO escrituras
SELECT count(*) AS filas_despues FROM public.app_dat_inventario_productos;
-- Esperado: igual que filas_antes  (las dos capas deciden igual: ninguna acepta)
ROLLBACK;


-- ============================================================================
-- BLOQUE 10 · EMPATE DE cantidad_final: DETERMINISMO DEL RESULTADO
-- El mismo caso de §2-bis con los dos ordenes de insercion posibles. El
-- planificador v2 consume por PRESENTACION y equivalente, no por el orden fisico
-- del detalle (que era el origen del "a veces gramo, a veces kg"), asi que los
-- dos ordenes dan EXACTAMENTE el mismo resultado.
-- ============================================================================
-- 10a · Primero la fila Kilogramo, despues la Unidad.
BEGIN;
SELECT set_config('request.jwt.claims', '{"sub":"5016cee9-3665-452d-ba75-6d38900e3a1a","role":"authenticated"}', true);
INSERT INTO public.app_dat_producto_presentacion (id, id_producto, id_presentacion, cantidad, es_base)
VALUES (999000001, 10924, 15, 1000, false);
INSERT INTO public.app_dat_inventario_productos
    (id, id_producto, id_ubicacion, id_presentacion, cantidad_inicial, cantidad_final, origen_cambio, created_at)
SELECT (SELECT COALESCE(MAX(id),0) FROM public.app_dat_inventario_productos) + row_number() OVER (),
       v.id_producto, v.id_ubicacion, v.id_presentacion, v.cantidad, v.cantidad, 4, now()
  FROM (VALUES (10924::bigint, 349::bigint, 999000001::bigint, 2000::numeric),
               (10924::bigint, 349::bigint, 11101::bigint,     2000::numeric)
       ) AS v(id_producto, id_ubicacion, id_presentacion, cantidad);
SELECT public.fn_ingrediente_base_alcanzable(10924, 331, 'almacen', 6000) AS kernel;
SELECT public.fn_consumir_ingrediente_base_v2(10924, 331, 6000, 4, NULL, NULL, gen_random_uuid(), 'test_t10a') AS consumo;
SELECT s.id_presentacion, SUM(s.saldo) AS saldo_final
  FROM public.fn_stock_saldos_presentacion(10924, 331, NULL, true) s
 GROUP BY 1 ORDER BY 1;
SELECT public.fn_stock_producto_almacen(10924, 331) AS equivalente_final;
-- Esperado: 11101 = 0 | 999000001 = 1996 | equivalente_final = 1996000
ROLLBACK;

-- 10b · Primero la fila Unidad, despues la Kilogramo.
BEGIN;
SELECT set_config('request.jwt.claims', '{"sub":"5016cee9-3665-452d-ba75-6d38900e3a1a","role":"authenticated"}', true);
INSERT INTO public.app_dat_producto_presentacion (id, id_producto, id_presentacion, cantidad, es_base)
VALUES (999000001, 10924, 15, 1000, false);
INSERT INTO public.app_dat_inventario_productos
    (id, id_producto, id_ubicacion, id_presentacion, cantidad_inicial, cantidad_final, origen_cambio, created_at)
SELECT (SELECT COALESCE(MAX(id),0) FROM public.app_dat_inventario_productos) + row_number() OVER (),
       v.id_producto, v.id_ubicacion, v.id_presentacion, v.cantidad, v.cantidad, 4, now()
  FROM (VALUES (10924::bigint, 349::bigint, 11101::bigint,     2000::numeric),
               (10924::bigint, 349::bigint, 999000001::bigint, 2000::numeric)
       ) AS v(id_producto, id_ubicacion, id_presentacion, cantidad);
SELECT public.fn_ingrediente_base_alcanzable(10924, 331, 'almacen', 6000) AS kernel;
SELECT public.fn_consumir_ingrediente_base_v2(10924, 331, 6000, 4, NULL, NULL, gen_random_uuid(), 'test_t10b') AS consumo;
SELECT s.id_presentacion, SUM(s.saldo) AS saldo_final
  FROM public.fn_stock_saldos_presentacion(10924, 331, NULL, true) s
 GROUP BY 1 ORDER BY 1;
SELECT public.fn_stock_producto_almacen(10924, 331) AS equivalente_final;
-- Esperado: IDENTICO a 10a (11101 = 0 | 999000001 = 1996 | 1996000)
ROLLBACK;


-- ============================================================================
-- BLOQUE 11 · fn_descontar_venta_enrutada_v2 (datos reales)
-- 11a · rama SKU (11007, TPV 224, almacen 331): 500 base
-- 11b · rama receta (10800, TPV 224 -> cocina 39, almacen 333)
-- ============================================================================
-- 11a · SKU propio.
BEGIN;
SELECT set_config('request.jwt.claims', '{"sub":"5016cee9-3665-452d-ba75-6d38900e3a1a","role":"authenticated"}', true);
SELECT public.fn_resolver_origen_venta(11007, 224) AS ruta;
-- Esperado: origen=barra descontar=sku id_almacen=331
SELECT public.fn_descontar_venta_enrutada_v2(11007, 500, 224, NULL, 4, false) AS descuento;
-- Esperado: status=success | origen=barra | descontado=true | cantidad=500
SELECT public.fn_stock_producto_almacen(11007, 331) AS equivalente_final;
-- Esperado: 750  (1250 - 500); el Cajon (13 x30) sigue intacto
SELECT count(*) AS filas_negativas FROM public.fn_stock_saldos_presentacion(11007, 331, NULL, false) WHERE saldo < 0;
-- Esperado: 0
ROLLBACK;

-- 11b · Rama receta: hay que dejar la barra (almacen 331) en cero para que el
--       enrutado mande a la cocina 39 (almacen 333).
BEGIN;
SELECT set_config('request.jwt.claims', '{"sub":"5016cee9-3665-452d-ba75-6d38900e3a1a","role":"authenticated"}', true);
INSERT INTO public.app_dat_inventario_productos
    (id, id_producto, id_ubicacion, id_presentacion, cantidad_inicial, cantidad_final, origen_cambio, created_at)
SELECT (SELECT COALESCE(MAX(id),0) FROM public.app_dat_inventario_productos) + 1,
       10800, 350, 10943, 1, 0, 2, now();
SELECT public.fn_resolver_origen_venta(10800, 224) AS ruta;
-- Esperado: origen=cocina_al_pedido | descontar=ingredientes | id_almacen=333 | id_cocina=39
SELECT public.fn_descontar_venta_enrutada_v2(10800, 10, 224, NULL, 4, true) AS descuento;
-- Esperado: status=success | origen=cocina_al_pedido | id_almacen=333 | descontado=true
--           ingredientes_consumidos: 10798 (0.3) y 10799 (0.03)
SELECT public.fn_stock_producto_almacen(10798, 333) AS harina_333,
       public.fn_stock_producto_almacen(10799, 333) AS sal_333;
-- Esperado: harina 1230 -> 1229.7 | sal 1232.9993 -> 1232.9693
ROLLBACK;


-- ============================================================================
-- BLOQUE 12 · REVERIFICACION (solo lectura, fuera de transaccion)
-- Debe confirmar que la suite NO dejo NADA aplicado y que las funciones vivas
-- conservan sus md5 de docs/_analisis/INGREDIENTES_SQL.md §10.
-- ============================================================================
SELECT to_regprocedure('public.fn_ejecutar_entrega_fisica_v3(bigint,bigint,bigint,numeric,integer,bigint,bigint,bigint,bigint,uuid,text)') AS v3,
       to_regprocedure('public.fn_ingrediente_base_alcanzable(bigint,bigint,text,numeric)')                                    AS kernel,
       to_regprocedure('public.fn_ingredientes_elaborado_base(bigint,numeric,bigint,text)')                                    AS base,
       to_regprocedure('public.fn_consumir_ingrediente_base_v2(bigint,bigint,numeric,integer,bigint,bigint,uuid,text)')        AS consumir,
       to_regprocedure('public.fn_validar_ingredientes_elaborado_v2(bigint,numeric,bigint)')                                   AS validador,
       to_regprocedure('public.fn_descontar_ingredientes_elaborado_v2(bigint,numeric,bigint,bigint,integer)')                  AS descontador,
       to_regprocedure('public.fn_descontar_venta_enrutada_v2(bigint,numeric,bigint,bigint,integer,boolean)')                  AS enrutador;
-- Esperado tras el ROLLBACK (si se probo con BEGIN ... ROLLBACK): las 7 columnas NULL.
-- Esperado tras aplicar 30 y 31 de verdad: las 7 con firma, no NULL.

SELECT p.proname, md5(pg_get_functiondef(p.oid)) AS md5
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname IN (
   'fn_descontar_ingredientes_elaborado','fn_descontar_venta_enrutada',
   'fn_validar_ingredientes_elaborado','fn_stock_producto_almacen',
   'fn_stock_producto_almacen_detalle','fn_obtener_ingredientes_recursivos',
   'fn_cantidad_en_base','fn_presentaciones_producto','fn_stock_saldos_presentacion',
   'fn_ejecutar_entrega_fisica_v2','fn_preview_entrega_fisica_v2')
 ORDER BY 1;
-- Esperado (identicos a INGREDIENTES_SQL.md §10 y a §2-bis):
--   fn_descontar_ingredientes_elaborado   47be3a93f8d026eba2f5fbfc31b0cd4a
--   fn_descontar_venta_enrutada           d56b117f2c9307a8c6bfaac29ce5e1e8
--   fn_validar_ingredientes_elaborado     c23f85d245c97f89c33e508574fd1aa0
--   fn_stock_producto_almacen             ecad724f55e19af4eb21d4f73d4ccc61
--   fn_stock_producto_almacen_detalle     0c452407ab12122a5b8262efd05a51a9
--   fn_obtener_ingredientes_recursivos    953eabdde12f97b63657339ba0116cfc
--   fn_cantidad_en_base                   8af1cc7f9c90cc52dc330207e6b0f7eb
--   fn_presentaciones_producto            4514c0e9667e3e472608b6dc8d2bd0c3
--   fn_stock_saldos_presentacion          7619323274189428e7dd68bf5c08d478
--   fn_ejecutar_entrega_fisica_v2         9edf415b400a467a1d6627a628fd3376
--   fn_preview_entrega_fisica_v2          c46c5d977095057a7f33b8f7b360e254
-- ============================================================================