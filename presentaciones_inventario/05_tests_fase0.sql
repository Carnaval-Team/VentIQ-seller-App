-- ============================================================================
-- 05 · Fase 0 · Tests de stock mixto y rebalanceo
-- ============================================================================
-- Plan: docs/PLAN_PRESENTACIONES_INVENTARIO.md  (Fase 0.2, "Tests SQL minimos")
-- Proyecto Supabase: vsieeihstajlrdvpuooh
--
-- COMO SE CORRE
-- -------------
-- Pegar TODO este archivo en el SQL Editor y ejecutarlo de una vez. Empieza con
-- BEGIN y termina con ROLLBACK: crea un producto de prueba, ejercita los
-- helpers y lo deshace todo. NO deja rastro en produccion (comprobado: la
-- secuencia de ids avanza, nada mas).
--
-- Requiere que ya esten aplicados 01, 02 y 03.
--
-- El resultado es UNA fila con un jsonb. Cada clave lleva la expectativa en el
-- nombre, asi que se compara contra lo que dice el nombre y no hay que rehacer
-- la aritmetica de cabeza.
--
--
-- DATOS DE PRUEBA
-- ---------------
-- Producto sintetico con la cadena del plan:
--     Pallet  x120   (nivel 1)
--     Caja    x12    (nivel 2)
--     Unidad  x1     (nivel 3, base)
-- 1 pallet = 10 cajas = 120 unidades.
--
-- Se crea en la tienda 55 y en la ubicacion 74, que existen. El producto lleva
-- id_vendedor_app NULL y mostrar_en_catalogo = false a proposito: asi los
-- triggers de marketplace y de notificacion salen por su early-return y el test
-- mide solo el inventario.
--
--
-- LOS 5 TESTS DEL PLAN
-- --------------------
--   T1  entrar 4 cajas + 4 u (caja=12)          -> saldos 4 y 4; equivalente 52
--   T2  vender 1 u con 4 cajas y 0 sueltas      -> 3 cajas + 11 u
--   T3  vender 1 caja con 0 cajas y 20 u        -> 0 cajas + 8 u
--   T4  vender 1 u con solo 1 pallet            -> 0 pallet, 9 cajas, 11 u
--   T5  stock insuficiente en equivalente base  -> error, sin saldos negativos
--
-- Extras que cubren los riesgos que lista el plan:
--   T6  el egreso NO abre nada si el saldo propio alcanza
--   T7  el kardex distingue la conversion de la venta (id_conversion)
--   T8  producto de una sola presentacion sigue funcionando (sin regresion)
--   T9  multi-ubicacion: consume el saldo propio de una ubicacion y abre en otra
--       (en un segundo BEGIN/ROLLBACK al final del archivo)
-- ============================================================================

BEGIN;

-- ── Preparacion ─────────────────────────────────────────────────────────────
CREATE TEMP TABLE _r(k text, v jsonb);
CREATE TEMP TABLE _ctx(
    id_producto  bigint,
    id_ubicacion bigint,
    id_pallet    bigint,
    id_caja      bigint,
    id_unidad    bigint,
    id_simple    bigint,   -- producto de control, una sola presentacion
    id_pres_simple bigint
);

-- Producto de 3 niveles. Categoria 115 = la del producto real 1140 (tienda 55).
WITH nuevo AS (
    INSERT INTO public.app_dat_producto (
        id_tienda, id_categoria, denominacion, sku,
        es_vendible, es_inventariable, es_servicio, es_elaborado,
        mostrar_en_catalogo, created_at
    )
    SELECT 55, 115,
           'ZZ TEST presentaciones mixtas', 'ZZ-TEST-MIX',
           true, true, false, false, false, NOW()
    RETURNING id
)
INSERT INTO _ctx (id_producto, id_ubicacion) SELECT nuevo.id, 74 FROM nuevo;

-- Cadena Pallet / Caja / Unidad. app_nom_presentacion: 7 = Bulto (se usa como
-- "Pallet" porque el catalogo no tiene Pallet), 3 = Caja, 1 = Unidad.
WITH ins AS (
    INSERT INTO public.app_dat_producto_presentacion
        (id_producto, id_presentacion, cantidad, es_base, precio_promedio, created_at)
    SELECT c.id_producto, v.nom, v.factor, v.base, 10.0, NOW()
      FROM _ctx c
      CROSS JOIN (VALUES (7, 120.0, false), (3, 12.0, false), (1, 1.0, true))
                 AS v(nom, factor, base)
    RETURNING id, id_presentacion
)
UPDATE _ctx SET
    id_pallet = (SELECT id FROM ins WHERE id_presentacion = 7),
    id_caja   = (SELECT id FROM ins WHERE id_presentacion = 3),
    id_unidad = (SELECT id FROM ins WHERE id_presentacion = 1);

-- Producto de control: una sola presentacion (el caso del 99.7 % del catalogo).
WITH nuevo AS (
    INSERT INTO public.app_dat_producto (
        id_tienda, id_categoria, denominacion, sku,
        es_vendible, es_inventariable, es_servicio, es_elaborado,
        mostrar_en_catalogo, created_at
    )
    SELECT 55, 115,
           'ZZ TEST una presentacion', 'ZZ-TEST-UNI',
           true, true, false, false, false, NOW()
    RETURNING id
)
UPDATE _ctx SET id_simple = (SELECT id FROM nuevo);

WITH ins AS (
    INSERT INTO public.app_dat_producto_presentacion
        (id_producto, id_presentacion, cantidad, es_base, precio_promedio, created_at)
    SELECT c.id_simple, 1, 1.0, true, 5.0, NOW() FROM _ctx c
    RETURNING id
)
UPDATE _ctx SET id_pres_simple = (SELECT id FROM ins);

INSERT INTO _r SELECT '00_contexto', to_jsonb(x) FROM (SELECT * FROM _ctx) x;

INSERT INTO _r SELECT '00_cadena_esp_pallet120_caja12_unidad1', jsonb_agg(to_jsonb(x))
  FROM (SELECT p.nivel, p.nombre, p.factor_rel, p.es_base, p.factor_hijo
          FROM _ctx c, public.fn_presentaciones_producto(c.id_producto) p
         ORDER BY p.nivel) x;


-- ============================================================================
-- T1 · Entrar 4 cajas + 4 unidades -> dos saldos, equivalente 52
-- ============================================================================
INSERT INTO _r SELECT 'T1_a_ingresar_4_cajas', public.fn_ingresar_presentacion(
    p_id_producto     := (SELECT id_producto FROM _ctx),
    p_id_ubicacion    := (SELECT id_ubicacion FROM _ctx),
    p_id_presentacion := (SELECT id_caja FROM _ctx),
    p_cantidad        := 4,
    p_origen_cambio   := 1);

INSERT INTO _r SELECT 'T1_b_ingresar_4_unidades', public.fn_ingresar_presentacion(
    p_id_producto     := (SELECT id_producto FROM _ctx),
    p_id_ubicacion    := (SELECT id_ubicacion FROM _ctx),
    p_id_presentacion := (SELECT id_unidad FROM _ctx),
    p_cantidad        := 4,
    p_origen_cambio   := 1);

INSERT INTO _r SELECT 'T1_c_esp_4Cajas_mas_4Unidades_equiv_52',
    (SELECT public.fn_stock_mixto_json(c.id_producto, NULL, c.id_ubicacion) FROM _ctx c);


-- ============================================================================
-- T2 · Vender 1 unidad con 4 cajas y 0 sueltas -> 3 cajas + 11 unidades
-- ============================================================================
-- Primero se dejan 0 sueltas para reproducir el caso exacto del plan.
INSERT INTO _r SELECT 'T2_a_consumir_las_4_sueltas', public.fn_descontar_con_rebalanceo(
    p_id_producto     := (SELECT id_producto FROM _ctx),
    p_id_ubicacion    := (SELECT id_ubicacion FROM _ctx),
    p_id_presentacion := (SELECT id_unidad FROM _ctx),
    p_cantidad        := 4,
    p_origen_cambio   := 3,
    p_motivo          := 'test T2 preparacion');

INSERT INTO _r SELECT 'T2_b_estado_esp_4Cajas',
    (SELECT public.fn_stock_mixto_json(c.id_producto, NULL, c.id_ubicacion) FROM _ctx c);

INSERT INTO _r SELECT 'T2_c_vender_1_unidad_esp_estrategia_abrir', public.fn_descontar_con_rebalanceo(
    p_id_producto     := (SELECT id_producto FROM _ctx),
    p_id_ubicacion    := (SELECT id_ubicacion FROM _ctx),
    p_id_presentacion := (SELECT id_unidad FROM _ctx),
    p_cantidad        := 1,
    p_origen_cambio   := 3,
    p_motivo          := 'test T2 venta');

INSERT INTO _r SELECT 'T2_d_esp_3Cajas_mas_11Unidades_equiv_47',
    (SELECT public.fn_stock_mixto_json(c.id_producto, NULL, c.id_ubicacion) FROM _ctx c);


-- ============================================================================
-- T3 · Vender 1 caja con 0 cajas y 20 unidades -> 0 cajas + 8 unidades
-- ============================================================================
-- Se limpia el saldo del test anterior y se deja exactamente 0 cajas y 20 u.
INSERT INTO _r SELECT 'T3_a_vaciar_cajas', public.fn_descontar_con_rebalanceo(
    p_id_producto     := (SELECT id_producto FROM _ctx),
    p_id_ubicacion    := (SELECT id_ubicacion FROM _ctx),
    p_id_presentacion := (SELECT id_caja FROM _ctx),
    p_cantidad        := 3,
    p_origen_cambio   := 3,
    p_motivo          := 'test T3 preparacion');

INSERT INTO _r SELECT 'T3_b_vaciar_unidades', public.fn_descontar_con_rebalanceo(
    p_id_producto     := (SELECT id_producto FROM _ctx),
    p_id_ubicacion    := (SELECT id_ubicacion FROM _ctx),
    p_id_presentacion := (SELECT id_unidad FROM _ctx),
    p_cantidad        := 11,
    p_origen_cambio   := 3,
    p_motivo          := 'test T3 preparacion');

INSERT INTO _r SELECT 'T3_c_ingresar_20_unidades', public.fn_ingresar_presentacion(
    p_id_producto     := (SELECT id_producto FROM _ctx),
    p_id_ubicacion    := (SELECT id_ubicacion FROM _ctx),
    p_id_presentacion := (SELECT id_unidad FROM _ctx),
    p_cantidad        := 20,
    p_origen_cambio   := 1);

INSERT INTO _r SELECT 'T3_d_estado_esp_20Unidades',
    (SELECT public.fn_stock_mixto_json(c.id_producto, NULL, c.id_ubicacion) FROM _ctx c);

INSERT INTO _r SELECT 'T3_e_vender_1_caja_esp_estrategia_empaquetar', public.fn_descontar_con_rebalanceo(
    p_id_producto     := (SELECT id_producto FROM _ctx),
    p_id_ubicacion    := (SELECT id_ubicacion FROM _ctx),
    p_id_presentacion := (SELECT id_caja FROM _ctx),
    p_cantidad        := 1,
    p_origen_cambio   := 3,
    p_motivo          := 'test T3 venta');

INSERT INTO _r SELECT 'T3_f_esp_8Unidades_equiv_8',
    (SELECT public.fn_stock_mixto_json(c.id_producto, NULL, c.id_ubicacion) FROM _ctx c);


-- ============================================================================
-- T4 · Cadena de 3 niveles: vender 1 unidad con solo 1 pallet
--      -> 0 pallet, 9 cajas, 11 unidades  (dos conversiones en cadena)
-- ============================================================================
INSERT INTO _r SELECT 'T4_a_vaciar_unidades', public.fn_descontar_con_rebalanceo(
    p_id_producto     := (SELECT id_producto FROM _ctx),
    p_id_ubicacion    := (SELECT id_ubicacion FROM _ctx),
    p_id_presentacion := (SELECT id_unidad FROM _ctx),
    p_cantidad        := 8,
    p_origen_cambio   := 3,
    p_motivo          := 'test T4 preparacion');

INSERT INTO _r SELECT 'T4_b_ingresar_1_pallet', public.fn_ingresar_presentacion(
    p_id_producto     := (SELECT id_producto FROM _ctx),
    p_id_ubicacion    := (SELECT id_ubicacion FROM _ctx),
    p_id_presentacion := (SELECT id_pallet FROM _ctx),
    p_cantidad        := 1,
    p_origen_cambio   := 1);

INSERT INTO _r SELECT 'T4_c_estado_esp_1Bulto_equiv_120',
    (SELECT public.fn_stock_mixto_json(c.id_producto, NULL, c.id_ubicacion) FROM _ctx c);

INSERT INTO _r SELECT 'T4_d_vender_1_unidad_esp_2_conversiones', public.fn_descontar_con_rebalanceo(
    p_id_producto     := (SELECT id_producto FROM _ctx),
    p_id_ubicacion    := (SELECT id_ubicacion FROM _ctx),
    p_id_presentacion := (SELECT id_unidad FROM _ctx),
    p_cantidad        := 1,
    p_origen_cambio   := 3,
    p_motivo          := 'test T4 venta');

INSERT INTO _r SELECT 'T4_e_esp_9Cajas_mas_11Unidades_equiv_119',
    (SELECT public.fn_stock_mixto_json(c.id_producto, NULL, c.id_ubicacion) FROM _ctx c);


-- ============================================================================
-- T5 · Stock insuficiente en equivalente base -> error, sin saldos negativos
-- ============================================================================
INSERT INTO _r SELECT 'T5_a_pedir_200_unidades_esp_error', public.fn_descontar_con_rebalanceo(
    p_id_producto     := (SELECT id_producto FROM _ctx),
    p_id_ubicacion    := (SELECT id_ubicacion FROM _ctx),
    p_id_presentacion := (SELECT id_unidad FROM _ctx),
    p_cantidad        := 200,
    p_origen_cambio   := 3,
    p_motivo          := 'test T5');

INSERT INTO _r SELECT 'T5_b_pedir_5_pallets_esp_error', public.fn_descontar_con_rebalanceo(
    p_id_producto     := (SELECT id_producto FROM _ctx),
    p_id_ubicacion    := (SELECT id_ubicacion FROM _ctx),
    p_id_presentacion := (SELECT id_pallet FROM _ctx),
    p_cantidad        := 5,
    p_origen_cambio   := 3,
    p_motivo          := 'test T5');

INSERT INTO _r SELECT 'T5_c_saldos_intactos_esp_9Cajas_11Unidades',
    (SELECT public.fn_stock_mixto_json(c.id_producto, NULL, c.id_ubicacion) FROM _ctx c);

INSERT INTO _r SELECT 'T5_d_sin_negativos_esp_0', to_jsonb(x) FROM (
    SELECT count(*) AS filas_negativas
      FROM public.app_dat_inventario_productos ip, _ctx c
     WHERE ip.id_producto = c.id_producto AND ip.cantidad_final < 0) x;


-- ============================================================================
-- T6 · Si el saldo propio alcanza, NO se abre nada
-- ============================================================================
INSERT INTO _r SELECT 'T6_a_vender_2_cajas_esp_estrategia_ninguna', public.fn_descontar_con_rebalanceo(
    p_id_producto     := (SELECT id_producto FROM _ctx),
    p_id_ubicacion    := (SELECT id_ubicacion FROM _ctx),
    p_id_presentacion := (SELECT id_caja FROM _ctx),
    p_cantidad        := 2,
    p_origen_cambio   := 3,
    p_motivo          := 'test T6');

INSERT INTO _r SELECT 'T6_b_esp_7Cajas_mas_11Unidades',
    (SELECT public.fn_stock_mixto_json(c.id_producto, NULL, c.id_ubicacion) FROM _ctx c);


-- ============================================================================
-- T7 · El kardex distingue conversion de venta
-- ============================================================================
INSERT INTO _r SELECT 'T7_a_ledger_por_tipo', jsonb_agg(to_jsonb(x)) FROM (
    SELECT CASE WHEN ip.id_conversion IS NOT NULL THEN 'conversion'
                WHEN ip.origen_cambio = 1 THEN 'entrada'
                ELSE 'egreso' END AS tipo,
           ip.origen_cambio,
           count(*) AS filas
      FROM public.app_dat_inventario_productos ip, _ctx c
     WHERE ip.id_producto = c.id_producto
     GROUP BY 1, 2
     ORDER BY 1, 2) x;

INSERT INTO _r SELECT 'T7_b_conversiones_esp_abrir_x3_empaquetar_x1', jsonb_agg(to_jsonb(x)) FROM (
    SELECT cp.tipo,
           po.denominacion AS de,
           pd.denominacion AS a,
           cp.cantidad_origen,
           cp.cantidad_destino,
           (SELECT count(*) FROM public.app_dat_inventario_productos ip
             WHERE ip.id_conversion = cp.id) AS patas_en_ledger
      FROM public.app_dat_conversion_presentacion cp
      JOIN _ctx c ON c.id_producto = cp.id_producto
      JOIN public.app_dat_producto_presentacion ppo ON ppo.id = cp.id_presentacion_origen
      JOIN public.app_nom_presentacion po ON po.id = ppo.id_presentacion
      JOIN public.app_dat_producto_presentacion ppd ON ppd.id = cp.id_presentacion_destino
      JOIN public.app_nom_presentacion pd ON pd.id = ppd.id_presentacion
     ORDER BY cp.id) x;

-- Cada conversion tiene EXACTAMENTE 2 patas y su neto en equivalente base es 0:
-- abrir una caja no crea ni destruye mercancia.
INSERT INTO _r SELECT 'T7_c_conversiones_neutras_esp_todas_0', jsonb_agg(to_jsonb(x)) FROM (
    SELECT cp.id,
           cp.tipo,
           round(SUM((ip.cantidad_final - ip.cantidad_inicial) * pr.factor_rel), 6) AS neto_equiv_base
      FROM public.app_dat_conversion_presentacion cp
      JOIN _ctx c ON c.id_producto = cp.id_producto
      JOIN public.app_dat_inventario_productos ip ON ip.id_conversion = cp.id
      JOIN public.fn_presentaciones_producto((SELECT id_producto FROM _ctx)) pr
             ON pr.id_presentacion = ip.id_presentacion
     GROUP BY cp.id, cp.tipo
     ORDER BY cp.id) x;


-- ============================================================================
-- T8 · Producto de una sola presentacion: sin regresiones
-- ============================================================================
INSERT INTO _r SELECT 'T8_a_ingresar_10', public.fn_ingresar_presentacion(
    p_id_producto     := (SELECT id_simple FROM _ctx),
    p_id_ubicacion    := (SELECT id_ubicacion FROM _ctx),
    p_id_presentacion := (SELECT id_pres_simple FROM _ctx),
    p_cantidad        := 10,
    p_origen_cambio   := 1);

INSERT INTO _r SELECT 'T8_b_vender_3_esp_ninguna_conversion', public.fn_descontar_con_rebalanceo(
    p_id_producto     := (SELECT id_simple FROM _ctx),
    p_id_ubicacion    := (SELECT id_ubicacion FROM _ctx),
    p_id_presentacion := (SELECT id_pres_simple FROM _ctx),
    p_cantidad        := 3,
    p_origen_cambio   := 3,
    p_motivo          := 'test T8');

INSERT INTO _r SELECT 'T8_c_esp_7_Unidades_equiv_7',
    (SELECT public.fn_stock_mixto_json(c.id_simple, NULL, c.id_ubicacion) FROM _ctx c);

INSERT INTO _r SELECT 'T8_d_pedir_100_esp_error', public.fn_descontar_con_rebalanceo(
    p_id_producto     := (SELECT id_simple FROM _ctx),
    p_id_ubicacion    := (SELECT id_ubicacion FROM _ctx),
    p_id_presentacion := (SELECT id_pres_simple FROM _ctx),
    p_cantidad        := 100,
    p_origen_cambio   := 3,
    p_motivo          := 'test T8');


-- ── Resultado ───────────────────────────────────────────────────────────────
SELECT jsonb_pretty(jsonb_object_agg(k, v)) AS resultado FROM _r;

ROLLBACK;


-- ============================================================================
-- T9 · Multi-ubicacion: fn_descontar_con_rebalanceo_almacen
-- ============================================================================
-- Bloque aparte porque necesita un almacen con DOS ubicaciones. Se usa el 73,
-- que tiene las ubicaciones 75 ('Principal') y 76 ('primcipal').
--
-- Escenario: 3 unidades sueltas en la 75 y 2 cajas de 12 en la 76.
-- Pedir 10 unidades debe: consumir las 3 de la 75 (sin abrir nada) y abrir UNA
-- caja en la 76 para las 7 que faltan. Resultado: 1 Caja + 5 Unidades.
--
-- Esto es lo que arregla el bug del plan: la logica vieja tomaba "el ultimo
-- movimiento del producto", veia 3 unidades y decia stock insuficiente.

BEGIN;

CREATE TEMP TABLE _r9(k text, v jsonb);
CREATE TEMP TABLE _ctx9(id_producto bigint, id_caja bigint, id_unidad bigint);

WITH nuevo AS (
    INSERT INTO public.app_dat_producto (
        id_tienda, id_categoria, denominacion, sku,
        es_vendible, es_inventariable, es_servicio, es_elaborado,
        mostrar_en_catalogo, created_at)
    SELECT 55, 115, 'ZZ TEST almacen multi ubic', 'ZZ-TEST-ALM',
           true, true, false, false, false, NOW()
    RETURNING id
)
INSERT INTO _ctx9 (id_producto) SELECT id FROM nuevo;

WITH ins AS (
    INSERT INTO public.app_dat_producto_presentacion
        (id_producto, id_presentacion, cantidad, es_base, precio_promedio, created_at)
    SELECT c.id_producto, v.nom, v.factor, v.base, 10.0, NOW()
      FROM _ctx9 c
      CROSS JOIN (VALUES (3, 12.0, false), (1, 1.0, true)) AS v(nom, factor, base)
    RETURNING id, id_presentacion
)
UPDATE _ctx9 SET
    id_caja   = (SELECT id FROM ins WHERE id_presentacion = 3),
    id_unidad = (SELECT id FROM ins WHERE id_presentacion = 1);

INSERT INTO _r9 SELECT 'T9_a_ubicaciones_almacen_73', jsonb_agg(to_jsonb(x))
  FROM (SELECT la.id, la.denominacion
          FROM public.app_dat_layout_almacen la
         WHERE la.id_almacen = 73 AND la.deleted_at IS NULL
         ORDER BY la.id) x;

INSERT INTO _r9 SELECT 'T9_b_ubic75_3_unidades', public.fn_ingresar_presentacion(
    (SELECT id_producto FROM _ctx9), 75, (SELECT id_unidad FROM _ctx9), 3, 1);

INSERT INTO _r9 SELECT 'T9_c_ubic76_2_cajas', public.fn_ingresar_presentacion(
    (SELECT id_producto FROM _ctx9), 76, (SELECT id_caja FROM _ctx9), 2, 1);

INSERT INTO _r9 SELECT 'T9_d_almacen_esp_2Cajas_3Unidades_equiv_27',
    (SELECT public.fn_stock_mixto_json(c.id_producto, 73, NULL) FROM _ctx9 c);

INSERT INTO _r9 SELECT 'T9_e_pedir_10u_esp_2_movimientos_1_apertura',
    public.fn_descontar_con_rebalanceo_almacen(
        p_id_producto     := (SELECT id_producto FROM _ctx9),
        p_id_almacen      := 73,
        p_id_presentacion := (SELECT id_unidad FROM _ctx9),
        p_cantidad        := 10,
        p_origen_cambio   := 3,
        p_motivo          := 'test T9');

INSERT INTO _r9 SELECT 'T9_f_esp_1Caja_mas_5Unidades_equiv_17',
    (SELECT public.fn_stock_mixto_json(c.id_producto, 73, NULL) FROM _ctx9 c);

INSERT INTO _r9 SELECT 'T9_g_detalle_esp_todo_en_ubic76', jsonb_agg(to_jsonb(x))
  FROM (SELECT s.id_ubicacion, s.presentacion_nombre, s.saldo
          FROM _ctx9 c, public.fn_stock_saldos_presentacion(c.id_producto, 73, NULL, false) s
         ORDER BY s.id_ubicacion, s.nivel) x;

INSERT INTO _r9 SELECT 'T9_h_pedir_100u_esp_error_warehouse',
    public.fn_descontar_con_rebalanceo_almacen(
        (SELECT id_producto FROM _ctx9), 73, (SELECT id_unidad FROM _ctx9),
        100, 3, NULL, NULL, NULL, NULL, NULL, 'test T9');

-- 2 cajas = 24 equivalentes y solo hay 17: rechaza antes de tocar nada.
INSERT INTO _r9 SELECT 'T9_i_pedir_2cajas_esp_error',
    public.fn_descontar_con_rebalanceo_almacen(
        (SELECT id_producto FROM _ctx9), 73, (SELECT id_caja FROM _ctx9),
        2, 3, NULL, NULL, NULL, NULL, NULL, 'test T9');

INSERT INTO _r9 SELECT 'T9_j_intacto_esp_1Caja_mas_5Unidades',
    (SELECT public.fn_stock_mixto_json(c.id_producto, 73, NULL) FROM _ctx9 c);

SELECT jsonb_pretty(jsonb_object_agg(k, v)) AS resultado_t9 FROM _r9;

ROLLBACK;

-- ============================================================================
-- DESPUES DEL ROLLBACK · comprobar que produccion quedo intacta
-- ============================================================================
-- Correr esto como consulta aparte. Todo debe dar 0.
--
--   SELECT (SELECT count(*) FROM public.app_dat_producto
--            WHERE denominacion LIKE 'ZZ TEST%')                  AS productos_test,
--          (SELECT count(*) FROM public.app_dat_conversion_presentacion
--            WHERE motivo LIKE 'test %')                          AS conversiones_test,
--          (SELECT count(*) FROM public.app_dat_inventario_productos
--            WHERE origen_cambio = 20)                            AS ledger_conversion;
--
-- Nota: la secuencia de app_dat_producto y de app_dat_conversion_presentacion
-- avanza aunque se haga ROLLBACK (las secuencias no son transaccionales). Es
-- normal y no rompe nada.

