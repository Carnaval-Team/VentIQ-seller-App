-- ============================================================================
-- 09 · Fase 1 · Tests (NO modifica nada: BEGIN ... ROLLBACK)
-- ============================================================================
-- Plan: docs/PLAN_PRESENTACIONES_INVENTARIO.md  (Fase 1)
-- Correr DESPUES de aplicar 06, 07 y 08.
--
-- Todo va dentro de BEGIN/ROLLBACK: crea productos de prueba, los ejercita
-- contra las RPC reales y lo deshace. Al final de cada bloque hay un unico
-- SELECT con el resultado en JSON.
--
-- El nombre de cada clave lleva la expectativa dentro (esp_...), asi que la
-- diferencia entre lo que se esperaba y lo que salio se ve sin leer el script.
--
-- REQUISITOS DEL ENTORNO (verificados el 2026-08-26; si cambian, ajustar):
--   - tienda 55 existe, categoria 115 existe
--   - almacen 74 tiene la ubicacion 74; almacen 73 tiene las 75 y 76
--   - app_nom_presentacion: 1 = Unidad, 3 = Caja, 7 = Bulto
--   - app_nom_motivo_recepcion: 1 = Compra, 2 = Transferencia
--   - app_nom_motivo_extraccion: 2 = Consumo interno, 7 = Transferencia
--   - app_nom_tipo_operacion: 3 = ajuste, 7/8 = transferencia salida/entrada,
--     19 = transferencia de productos, 20 = cambio de presentacion
--   - v_uuid mas abajo debe ser un uuid que exista en auth.users, porque
--     app_dat_operaciones.uuid tiene FK contra esa tabla. El que viene puesto
--     se saco de una operacion real de la tienda 55. Si falla con
--     'app_dat_operaciones_uuid_fkey', reemplazarlo por el resultado de:
--       SELECT uuid FROM app_dat_operaciones WHERE id_tienda=55 AND uuid IS NOT NULL
--        ORDER BY id DESC LIMIT 1;
-- ============================================================================


-- ============================================================================
-- BLOQUE A · Recepcion (archivo 06)
-- ============================================================================

BEGIN;

CREATE TEMP TABLE _r(k text, v jsonb);
CREATE TEMP TABLE _ctx(id_producto bigint, id_otro bigint,
                       id_pallet bigint, id_caja bigint, id_unidad bigint,
                       id_pres_otro bigint);
CREATE TEMP TABLE _u(u uuid);

INSERT INTO _u VALUES ('f895ceb3-668c-4fd8-81e9-0c2294a72734'::uuid);

-- Producto con cadena Bulto 120 / Caja 12 / Unidad 1
WITH n AS (
  INSERT INTO app_dat_producto (id_tienda, id_categoria, denominacion, sku,
    es_vendible, es_inventariable, es_servicio, es_elaborado,
    mostrar_en_catalogo, created_at)
  SELECT 55, 115, 'ZZ TEST F1 recepcion', 'ZZ-F1-REC',
         true, true, false, false, false, NOW()
  RETURNING id)
INSERT INTO _ctx (id_producto) SELECT id FROM n;

WITH i AS (
  INSERT INTO app_dat_producto_presentacion
    (id_producto, id_presentacion, cantidad, es_base, precio_promedio, created_at)
  SELECT c.id_producto, v.nom, v.f, v.b, 10.0, NOW()
    FROM _ctx c
    CROSS JOIN (VALUES (7, 120.0, false), (3, 12.0, false), (1, 1.0, true))
      AS v(nom, f, b)
  RETURNING id, id_presentacion)
UPDATE _ctx SET
  id_pallet = (SELECT id FROM i WHERE id_presentacion = 7),
  id_caja   = (SELECT id FROM i WHERE id_presentacion = 3),
  id_unidad = (SELECT id FROM i WHERE id_presentacion = 1);

-- Segundo producto, solo para probar el rechazo de presentacion ajena
WITH n AS (
  INSERT INTO app_dat_producto (id_tienda, id_categoria, denominacion, sku,
    es_vendible, es_inventariable, es_servicio, es_elaborado,
    mostrar_en_catalogo, created_at)
  SELECT 55, 115, 'ZZ TEST F1 otro', 'ZZ-F1-OTRO',
         true, true, false, false, false, NOW()
  RETURNING id)
UPDATE _ctx SET id_otro = (SELECT id FROM n);

WITH i AS (
  INSERT INTO app_dat_producto_presentacion
    (id_producto, id_presentacion, cantidad, es_base, precio_promedio, created_at)
  SELECT c.id_otro, 1, 1.0, true, 5.0, NOW() FROM _ctx c
  RETURNING id)
UPDATE _ctx SET id_pres_otro = (SELECT id FROM i);


-- A1 · recepcion MIXTA: 4 cajas + 4 unidades en la misma operacion
INSERT INTO _r SELECT 'A1_recepcion_mixta_esp_success',
  public.fn_registrar_recepcion_con_inventario(
    'Proveedor X', 55, NULL, 1, 'test F1 mixta',
    (SELECT jsonb_build_array(
       jsonb_build_object('id_producto', c.id_producto, 'id_ubicacion', 74,
                          'id_presentacion', c.id_caja,   'cantidad', 4,
                          'precio_unitario', 120),
       jsonb_build_object('id_producto', c.id_producto, 'id_ubicacion', 74,
                          'id_presentacion', c.id_unidad, 'cantidad', 4,
                          'precio_unitario', 10))
     FROM _ctx c),
    'Almacenero', (SELECT u FROM _u), 'USD');

INSERT INTO _r SELECT 'A1_esp_4Cajas_mas_4Unidades_equiv_52',
  (SELECT public.fn_stock_mixto_json(c.id_producto, NULL, 74) FROM _ctx c);

INSERT INTO _r SELECT 'A1_ledger_esp_2filas_cada_una_con_su_presentacion',
  jsonb_agg(to_jsonb(x))
  FROM (SELECT ip.id_presentacion, ip.cantidad_inicial AS ini,
               ip.cantidad_final AS fin, ip.origen_cambio,
               (ip.id_recepcion IS NOT NULL) AS ligado_a_recepcion
          FROM app_dat_inventario_productos ip, _ctx c
         WHERE ip.id_producto = c.id_producto
         ORDER BY ip.id) x;


-- A2 · TRES lineas de la MISMA presentacion en una recepcion (2+3+4 = 9 cajas)
-- Es el caso que el viejo `ORDER BY created_at DESC` no podia resolver: los tres
-- movimientos comparten NOW(), asi que el desempate quedaba al plan de ejecucion.
INSERT INTO _r SELECT 'A2_tres_lineas_misma_presentacion_esp_success',
  public.fn_registrar_recepcion_con_inventario(
    'Proveedor X', 55, NULL, 1, 'test F1 empate',
    (SELECT jsonb_build_array(
       jsonb_build_object('id_producto', c.id_producto, 'id_ubicacion', 75,
                          'id_presentacion', c.id_caja, 'cantidad', 2,
                          'precio_unitario', 120),
       jsonb_build_object('id_producto', c.id_producto, 'id_ubicacion', 75,
                          'id_presentacion', c.id_caja, 'cantidad', 3,
                          'precio_unitario', 120),
       jsonb_build_object('id_producto', c.id_producto, 'id_ubicacion', 75,
                          'id_presentacion', c.id_caja, 'cantidad', 4,
                          'precio_unitario', 120))
     FROM _ctx c),
    'Almacenero', (SELECT u FROM _u), 'USD');

INSERT INTO _r SELECT 'A2_saldos_encadenados_esp_0a2_2a5_5a9',
  jsonb_agg(to_jsonb(x))
  FROM (SELECT ip.cantidad_inicial AS ini, ip.cantidad_final AS fin
          FROM app_dat_inventario_productos ip, _ctx c
         WHERE ip.id_producto = c.id_producto AND ip.id_ubicacion = 75
         ORDER BY ip.id) x;


-- A3 · linea SIN id_presentacion: debe resolver la base, no insertar NULL
INSERT INTO _r SELECT 'A3_sin_presentacion_esp_success',
  public.fn_registrar_recepcion_con_inventario(
    'Proveedor X', 55, NULL, 1, 'test F1 sin pres',
    (SELECT jsonb_build_array(
       jsonb_build_object('id_producto', c.id_producto, 'id_ubicacion', 76,
                          'cantidad', 7, 'precio_unitario', 10))
     FROM _ctx c),
    'Almacenero', (SELECT u FROM _u), 'USD');

INSERT INTO _r SELECT 'A3_esp_7Unidades_y_0_nulls', to_jsonb(x)
  FROM (SELECT
    (SELECT public.fn_stock_mixto_json(c.id_producto, NULL, 76)->>'texto'
       FROM _ctx c)                                          AS texto,
    (SELECT count(*) FROM app_dat_recepcion_productos rp, _ctx c
      WHERE rp.id_producto = c.id_producto
        AND rp.id_presentacion IS NULL)                      AS rec_null_esp_0,
    (SELECT count(*) FROM app_dat_inventario_productos ip, _ctx c
      WHERE ip.id_producto = c.id_producto
        AND ip.id_presentacion IS NULL)                      AS ledger_null_esp_0) x;


-- A4 y A5 · los dos errores de id_presentacion
INSERT INTO _r SELECT 'A4_presentacion_de_otro_producto_esp_error_V0008',
  public.fn_registrar_recepcion_con_inventario(
    'Proveedor X', 55, NULL, 1, 'test F1 ajena',
    (SELECT jsonb_build_array(
       jsonb_build_object('id_producto', c.id_producto, 'id_ubicacion', 74,
                          'id_presentacion', c.id_pres_otro, 'cantidad', 5,
                          'precio_unitario', 10))
     FROM _ctx c),
    'Almacenero', (SELECT u FROM _u), 'USD');

-- 3 es app_nom_presentacion.id de 'Caja', no el id del vinculo
INSERT INTO _r SELECT 'A5_id_del_catalogo_esp_error_V0008',
  public.fn_registrar_recepcion_con_inventario(
    'Proveedor X', 55, NULL, 1, 'test F1 catalogo',
    (SELECT jsonb_build_array(
       jsonb_build_object('id_producto', c.id_producto, 'id_ubicacion', 74,
                          'id_presentacion', 3, 'cantidad', 5,
                          'precio_unitario', 10))
     FROM _ctx c),
    'Almacenero', (SELECT u FROM _u), 'USD');


-- A6 · despues de los dos errores, nada se movio, y los montos son correctos
INSERT INTO _r SELECT 'A6_intacto_y_montos', to_jsonb(x)
  FROM (SELECT
    (SELECT public.fn_stock_mixto_json(c.id_producto, NULL, 74)->>'texto'
       FROM _ctx c)                                    AS ubic74_esp_4Cajas_4Unidades,
    (SELECT count(*) FROM app_dat_inventario_productos ip, _ctx c
      WHERE ip.id_producto = c.id_producto
        AND ip.cantidad_final < 0)                     AS negativos_esp_0,
    (SELECT jsonb_agg(orr.monto_total ORDER BY orr.id_operacion)
       FROM app_dat_operacion_recepcion orr
      WHERE orr.observaciones LIKE 'test F1%')         AS montos_esp_520_1080_70) x;


-- A7 · las 5 validaciones originales siguen respondiendo igual
INSERT INTO _r SELECT 'A7_validaciones_originales', to_jsonb(x)
  FROM (SELECT
    public.fn_registrar_recepcion_con_inventario('X', 999999, NULL, 1, 't',
      (SELECT jsonb_build_array(jsonb_build_object('id_producto', c.id_producto,
        'cantidad', 1)) FROM _ctx c), 'Y', (SELECT u FROM _u), 'USD')
      ->>'sqlstate'                                    AS tienda_esp_V0001,
    public.fn_registrar_recepcion_con_inventario('X', 55, NULL, 1, 't',
      '[]'::jsonb, 'Y', (SELECT u FROM _u), 'USD')
      ->>'sqlstate'                                    AS vacio_esp_V0002,
    public.fn_registrar_recepcion_con_inventario('X', 55, NULL, 1, 't',
      (SELECT jsonb_build_array(jsonb_build_object('id_producto', c.id_producto,
        'cantidad', 1)) FROM _ctx c), 'Y', (SELECT u FROM _u), 'YEN')
      ->>'sqlstate'                                    AS moneda_esp_V0003,
    public.fn_registrar_recepcion_con_inventario('X', 55, NULL, 99, 't',
      (SELECT jsonb_build_array(jsonb_build_object('id_producto', c.id_producto,
        'cantidad', 1)) FROM _ctx c), 'Y', (SELECT u FROM _u), 'USD')
      ->>'sqlstate'                                    AS motivo_esp_V0004,
    public.fn_registrar_recepcion_con_inventario('X', 55, NULL, 1, 't',
      jsonb_build_array(jsonb_build_object('cantidad', 1)),
      'Y', (SELECT u FROM _u), 'USD')
      ->>'sqlstate'                                    AS item_esp_V0005) x;

SELECT jsonb_pretty(jsonb_object_agg(k, v)) AS bloque_a_recepcion FROM _r;

ROLLBACK;


-- ============================================================================
-- BLOQUE B · Extraccion y transferencia (archivo 07)
-- ============================================================================

BEGIN;

CREATE TEMP TABLE _r(k text, v jsonb);
CREATE TEMP TABLE _ctx(id_producto bigint, id_otro bigint,
                       id_caja bigint, id_unidad bigint, id_pres_otro bigint);
CREATE TEMP TABLE _u(u uuid);

INSERT INTO _u VALUES ('f895ceb3-668c-4fd8-81e9-0c2294a72734'::uuid);

WITH n AS (
  INSERT INTO app_dat_producto (id_tienda, id_categoria, denominacion, sku,
    es_vendible, es_inventariable, es_servicio, es_elaborado,
    mostrar_en_catalogo, created_at)
  SELECT 55, 115, 'ZZ TEST F1 egreso', 'ZZ-F1-EGR',
         true, true, false, false, false, NOW()
  RETURNING id)
INSERT INTO _ctx (id_producto) SELECT id FROM n;

WITH i AS (
  INSERT INTO app_dat_producto_presentacion
    (id_producto, id_presentacion, cantidad, es_base, precio_promedio, created_at)
  SELECT c.id_producto, v.nom, v.f, v.b, 10.0, NOW()
    FROM _ctx c
    CROSS JOIN (VALUES (3, 12.0, false), (1, 1.0, true)) AS v(nom, f, b)
  RETURNING id, id_presentacion)
UPDATE _ctx SET
  id_caja   = (SELECT id FROM i WHERE id_presentacion = 3),
  id_unidad = (SELECT id FROM i WHERE id_presentacion = 1);

WITH n AS (
  INSERT INTO app_dat_producto (id_tienda, id_categoria, denominacion, sku,
    es_vendible, es_inventariable, es_servicio, es_elaborado,
    mostrar_en_catalogo, created_at)
  SELECT 55, 115, 'ZZ TEST F1 egr otro', 'ZZ-F1-EGR2',
         true, true, false, false, false, NOW()
  RETURNING id)
UPDATE _ctx SET id_otro = (SELECT id FROM n);

WITH i AS (
  INSERT INTO app_dat_producto_presentacion
    (id_producto, id_presentacion, cantidad, es_base, precio_promedio, created_at)
  SELECT c.id_otro, 1, 1.0, true, 5.0, NOW() FROM _ctx c
  RETURNING id)
UPDATE _ctx SET id_pres_otro = (SELECT id FROM i);


-- B0 · stock inicial: 4 cajas y CERO sueltas
INSERT INTO _r SELECT 'B0_stock_inicial', to_jsonb(x)
  FROM (SELECT
    public.fn_ingresar_presentacion((SELECT id_producto FROM _ctx), 74,
      (SELECT id_caja FROM _ctx), 4, 1)->>'status'      AS ingreso,
    (SELECT public.fn_stock_mixto_json(c.id_producto, NULL, 74)->>'texto'
       FROM _ctx c)                                     AS esp_4Cajas) x;


-- B1 · extraer 1 UNIDAD sin sueltas. Antes escribia cantidad_final = -1.
INSERT INTO _r SELECT 'B1_extraer_1u_esp_success_abriendo_caja',
  public.fn_crear_extraccion_con_movimiento(
    'Jefe', 1::smallint, 2, 55, 'test F1 abrir',
    (SELECT jsonb_build_array(
       jsonb_build_object('id_producto', c.id_producto, 'id_ubicacion', 74,
                          'id_presentacion', c.id_unidad, 'cantidad', 1))
     FROM _ctx c),
    (SELECT u FROM _u));

INSERT INTO _r SELECT 'B1_esp_3Cajas_mas_11Unidades',
  (SELECT public.fn_stock_mixto_json(c.id_producto, NULL, 74) FROM _ctx c);

-- Esperado: recepcion (oc=1, 0->4), conversion salida (oc=20, 4->3),
-- conversion entrada (oc=20, 0->12) y egreso (oc=2, 12->11).
INSERT INTO _r SELECT 'B1_ledger_esp_1_20_20_2', jsonb_agg(to_jsonb(x))
  FROM (SELECT ip.origen_cambio AS oc, ip.cantidad_inicial AS ini,
               ip.cantidad_final AS fin,
               (ip.id_conversion IS NOT NULL) AS conv,
               (ip.id_extraccion IS NOT NULL) AS ext
          FROM app_dat_inventario_productos ip, _ctx c
         WHERE ip.id_producto = c.id_producto
         ORDER BY ip.id) x;


-- B2 · pedir mas de lo convertible: error y NADA escrito
INSERT INTO _r SELECT 'B2_pedir_500u_esp_error',
  public.fn_crear_extraccion_con_movimiento(
    'Jefe', 1::smallint, 2, 55, 'test F1 insuf',
    (SELECT jsonb_build_array(
       jsonb_build_object('id_producto', c.id_producto, 'id_ubicacion', 74,
                          'id_presentacion', c.id_unidad, 'cantidad', 500))
     FROM _ctx c),
    (SELECT u FROM _u));

INSERT INTO _r SELECT 'B2_esp_intacto_sin_operacion', to_jsonb(x)
  FROM (SELECT
    (SELECT public.fn_stock_mixto_json(c.id_producto, NULL, 74)->>'texto'
       FROM _ctx c)                                     AS texto,
    (SELECT count(*) FROM app_dat_inventario_productos ip, _ctx c
      WHERE ip.id_producto = c.id_producto
        AND ip.cantidad_final < 0)                      AS negativos_esp_0,
    (SELECT count(*) FROM app_dat_operacion_extraccion oe
      WHERE oe.observaciones LIKE 'test F1 insuf%')     AS operacion_esp_0) x;


-- B3 y B4 · validaciones nuevas de la extraccion
INSERT INTO _r SELECT 'B3_sin_id_ubicacion_esp_error',
  public.fn_crear_extraccion_con_movimiento(
    'Jefe', 1::smallint, 2, 55, 'test F1 sinubic',
    (SELECT jsonb_build_array(
       jsonb_build_object('id_producto', c.id_producto,
                          'id_presentacion', c.id_unidad, 'cantidad', 1))
     FROM _ctx c),
    (SELECT u FROM _u));

INSERT INTO _r SELECT 'B4_presentacion_ajena_esp_error',
  public.fn_crear_extraccion_con_movimiento(
    'Jefe', 1::smallint, 2, 55, 'test F1 ajena',
    (SELECT jsonb_build_array(
       jsonb_build_object('id_producto', c.id_producto, 'id_ubicacion', 74,
                          'id_presentacion', c.id_pres_otro, 'cantidad', 1))
     FROM _ctx c),
    (SELECT u FROM _u));


-- B5 · EL CRITERIO DE ACEPTACION: transferir 2 cajas no las convierte a 24 u
INSERT INTO _r SELECT 'B5_transferir_2cajas_74a75',
  public.fn_transferir_inventario_entre_layouts(74, 75,
    (SELECT jsonb_build_array(
       jsonb_build_object('id_producto', c.id_producto,
                          'id_presentacion', c.id_caja, 'cantidad', 2))
     FROM _ctx c),
    'Jefe', 'test F1 tr1', 55, (SELECT u FROM _u), true, 'USD', 'A', 'B', 'C');

INSERT INTO _r SELECT 'B5_resultado', to_jsonb(x)
  FROM (SELECT
    (SELECT public.fn_stock_mixto_json(c.id_producto, NULL, 74)->>'texto'
       FROM _ctx c)  AS origen74_esp_1Caja_11Unidades,
    (SELECT public.fn_stock_mixto_json(c.id_producto, NULL, 75)->>'texto'
       FROM _ctx c)  AS destino75_esp_2Cajas_NO_24Unidades) x;


-- B6 · transferir 1 caja teniendo 1 caja + 11 sueltas: usa la caja entera
INSERT INTO _r SELECT 'B6_transferir_1caja_74a76',
  public.fn_transferir_inventario_entre_layouts(74, 76,
    (SELECT jsonb_build_array(
       jsonb_build_object('id_producto', c.id_producto,
                          'id_presentacion', c.id_caja, 'cantidad', 1))
     FROM _ctx c),
    'Jefe', 'test F1 tr2', 55, (SELECT u FROM _u), true, 'USD', 'A', 'B', 'C');

INSERT INTO _r SELECT 'B6_resultado', to_jsonb(x)
  FROM (SELECT
    (SELECT public.fn_stock_mixto_json(c.id_producto, NULL, 74)->>'texto'
       FROM _ctx c)  AS origen74_esp_11Unidades,
    (SELECT public.fn_stock_mixto_json(c.id_producto, NULL, 76)->>'texto'
       FROM _ctx c)  AS destino76_esp_1Caja) x;


-- B7 · transferir 1 caja con solo 11 sueltas: 12 > 11, error sin pata suelta
INSERT INTO _r SELECT 'B7_transferir_1caja_con_11u_esp_error',
  public.fn_transferir_inventario_entre_layouts(74, 75,
    (SELECT jsonb_build_array(
       jsonb_build_object('id_producto', c.id_producto,
                          'id_presentacion', c.id_caja, 'cantidad', 1))
     FROM _ctx c),
    'Jefe', 'test F1 tr3', 55, (SELECT u FROM _u), true, 'USD', 'A', 'B', 'C');


-- B8 · transferir 6 unidades con saldo propio: sin conversiones
INSERT INTO _r SELECT 'B8_transferir_6u_74a75',
  public.fn_transferir_inventario_entre_layouts(74, 75,
    (SELECT jsonb_build_array(
       jsonb_build_object('id_producto', c.id_producto,
                          'id_presentacion', c.id_unidad, 'cantidad', 6))
     FROM _ctx c),
    'Jefe', 'test F1 tr4', 55, (SELECT u FROM _u), true, 'USD', 'A', 'B', 'C');

INSERT INTO _r SELECT 'B8_estado_final', to_jsonb(x)
  FROM (SELECT
    (SELECT public.fn_stock_mixto_json(c.id_producto, NULL, 74)->>'texto'
       FROM _ctx c)                                     AS u74_esp_5Unidades,
    (SELECT public.fn_stock_mixto_json(c.id_producto, NULL, 75)->>'texto'
       FROM _ctx c)                                     AS u75_esp_2Cajas_6Unidades,
    (SELECT public.fn_stock_mixto_json(c.id_producto, NULL, 76)->>'texto'
       FROM _ctx c)                                     AS u76_esp_1Caja,
    (SELECT count(*) FROM app_dat_inventario_productos ip, _ctx c
      WHERE ip.id_producto = c.id_producto
        AND ip.cantidad_final < 0)                      AS negativos_esp_0,
    (SELECT count(*) FROM app_dat_extraccion_productos ep, _ctx c
      WHERE ep.id_producto = c.id_producto
        AND ep.id_presentacion IS NULL)                 AS ext_null_esp_0) x;

SELECT jsonb_pretty(jsonb_object_agg(k, v)) AS bloque_b_egresos FROM _r;

ROLLBACK;


-- ============================================================================
-- BLOQUE C · Ajuste de inventario (archivo 08)
-- ============================================================================

BEGIN;

CREATE TEMP TABLE _r(k text, v jsonb);
CREATE TEMP TABLE _ctx(id_producto bigint, id_otro bigint,
                       id_caja bigint, id_unidad bigint, id_pres_otro bigint);
CREATE TEMP TABLE _u(u uuid);
CREATE TEMP TABLE _t(tipo bigint);

INSERT INTO _u VALUES ('f895ceb3-668c-4fd8-81e9-0c2294a72734'::uuid);
INSERT INTO _t SELECT id FROM app_nom_tipo_operacion
  WHERE denominacion ILIKE '%ajuste%' ORDER BY id LIMIT 1;

WITH n AS (
  INSERT INTO app_dat_producto (id_tienda, id_categoria, denominacion, sku,
    es_vendible, es_inventariable, es_servicio, es_elaborado,
    mostrar_en_catalogo, created_at)
  SELECT 55, 115, 'ZZ TEST F1 ajuste', 'ZZ-F1-AJU',
         true, true, false, false, false, NOW()
  RETURNING id)
INSERT INTO _ctx (id_producto) SELECT id FROM n;

WITH i AS (
  INSERT INTO app_dat_producto_presentacion
    (id_producto, id_presentacion, cantidad, es_base, precio_promedio, created_at)
  SELECT c.id_producto, v.nom, v.f, v.b, 10.0, NOW()
    FROM _ctx c
    CROSS JOIN (VALUES (3, 12.0, false), (1, 1.0, true)) AS v(nom, f, b)
  RETURNING id, id_presentacion)
UPDATE _ctx SET
  id_caja   = (SELECT id FROM i WHERE id_presentacion = 3),
  id_unidad = (SELECT id FROM i WHERE id_presentacion = 1);

WITH n AS (
  INSERT INTO app_dat_producto (id_tienda, id_categoria, denominacion, sku,
    es_vendible, es_inventariable, es_servicio, es_elaborado,
    mostrar_en_catalogo, created_at)
  SELECT 55, 115, 'ZZ TEST F1 aju otro', 'ZZ-F1-AJU2',
         true, true, false, false, false, NOW()
  RETURNING id)
UPDATE _ctx SET id_otro = (SELECT id FROM n);

WITH i AS (
  INSERT INTO app_dat_producto_presentacion
    (id_producto, id_presentacion, cantidad, es_base, precio_promedio, created_at)
  SELECT c.id_otro, 1, 1.0, true, 5.0, NOW() FROM _ctx c
  RETURNING id)
UPDATE _ctx SET id_pres_otro = (SELECT id FROM i);


INSERT INTO _r SELECT 'C0_setup', to_jsonb(x)
  FROM (SELECT (SELECT tipo FROM _t)                    AS tipo_ajuste_esp_3,
    public.fn_ingresar_presentacion((SELECT id_producto FROM _ctx), 74,
      (SELECT id_caja FROM _ctx), 4, 1)->>'status'      AS ingreso,
    (SELECT public.fn_stock_mixto_json(c.id_producto, NULL, 74)->>'texto'
       FROM _ctx c)                                     AS esp_4Cajas) x;


-- C1 · subir unidades 0 -> 5
INSERT INTO _r SELECT 'C1_subir_unidades_0a5',
  public.fn_insertar_ajuste_inventario2(
    (SELECT id_producto FROM _ctx), 74, (SELECT id_unidad FROM _ctx),
    0, 5, 'Conteo', 'test F1 ajuste subir',
    (SELECT u FROM _u), (SELECT tipo FROM _t));

INSERT INTO _r SELECT 'C1_estado', to_jsonb(x)
  FROM (SELECT (SELECT public.fn_stock_mixto_json(c.id_producto, NULL, 74)->>'texto'
                  FROM _ctx c) AS esp_4Cajas_5Unidades) x;


-- C2 · bajar unidades 5 -> 2
INSERT INTO _r SELECT 'C2_bajar_unidades_5a2_esp_diferencia_menos3',
  public.fn_insertar_ajuste_inventario2(
    (SELECT id_producto FROM _ctx), 74, (SELECT id_unidad FROM _ctx),
    5, 2, 'Conteo', 'test F1 ajuste bajar',
    (SELECT u FROM _u), (SELECT tipo FROM _t));


-- C3 · EL BUG PRINCIPAL: declarar 99 cuando el saldo real es 2.
-- Antes escribia una fila 99 -> 3 y rompia la cadena de saldos (202 casos
-- historicos en produccion). Ahora manda el saldo real y lo deja anotado.
INSERT INTO _r SELECT 'C3_declarado_99_real_2_esp_diferencia_mas1_desfase_true',
  public.fn_insertar_ajuste_inventario2(
    (SELECT id_producto FROM _ctx), 74, (SELECT id_unidad FROM _ctx),
    99, 3, 'Conteo', 'test F1 ajuste desfase',
    (SELECT u FROM _u), (SELECT tipo FROM _t));

INSERT INTO _r SELECT 'C3_observacion_esp_con_saldo_declarado_99', to_jsonb(x)
  FROM (SELECT o.observaciones FROM app_dat_operaciones o
         WHERE o.observaciones LIKE 'test F1 ajuste desfase%') x;


-- C4 · diferencia 0: no debe crecer el ledger
INSERT INTO _r SELECT 'C4_diferencia_0_no_escribe_ledger', to_jsonb(x)
  FROM (SELECT
    (SELECT count(*) FROM app_dat_inventario_productos ip, _ctx c
      WHERE ip.id_producto = c.id_producto)             AS antes,
    public.fn_insertar_ajuste_inventario2(
      (SELECT id_producto FROM _ctx), 74, (SELECT id_caja FROM _ctx),
      4, 4, 'Conteo', 'test F1 ajuste igual',
      (SELECT u FROM _u), (SELECT tipo FROM _t))->>'status'  AS st,
    (SELECT count(*) FROM app_dat_inventario_productos ip, _ctx c
      WHERE ip.id_producto = c.id_producto)             AS despues_esp_igual) x;


-- C5 · bajar cajas 4 -> 0
INSERT INTO _r SELECT 'C5_bajar_cajas_4a0',
  public.fn_insertar_ajuste_inventario2(
    (SELECT id_producto FROM _ctx), 74, (SELECT id_caja FROM _ctx),
    4, 0, 'Conteo', 'test F1 ajuste c0',
    (SELECT u FROM _u), (SELECT tipo FROM _t));


-- C6 · id_presentacion NULL: resuelve la base (Unidad)
INSERT INTO _r SELECT 'C6_presentacion_null_resuelve_base',
  public.fn_insertar_ajuste_inventario2(
    (SELECT id_producto FROM _ctx), 74, NULL,
    0, 9, 'Conteo', 'test F1 ajuste null',
    (SELECT u FROM _u), (SELECT tipo FROM _t));

INSERT INTO _r SELECT 'C6_estado', to_jsonb(x)
  FROM (SELECT (SELECT public.fn_stock_mixto_json(c.id_producto, NULL, 74)->>'texto'
                  FROM _ctx c) AS esp_9Unidades) x;


-- C7 y C8 · los dos errores de id_presentacion
INSERT INTO _r SELECT 'C7_presentacion_ajena_esp_error',
  public.fn_insertar_ajuste_inventario2(
    (SELECT id_producto FROM _ctx), 74, (SELECT id_pres_otro FROM _ctx),
    0, 1, 'Conteo', 'test F1 aju ajena',
    (SELECT u FROM _u), (SELECT tipo FROM _t));

INSERT INTO _r SELECT 'C8_id_del_catalogo_esp_error',
  public.fn_insertar_ajuste_inventario2(
    (SELECT id_producto FROM _ctx), 74, 3,
    0, 1, 'Conteo', 'test F1 aju cat',
    (SELECT u FROM _u), (SELECT tipo FROM _t));


-- C9 · integridad: ningun negativo, ninguna presentacion NULL y sobre todo
-- ningun ajuste que rompa la cadena de saldos.
INSERT INTO _r SELECT 'C9_integridad', to_jsonb(x)
  FROM (SELECT
    (SELECT count(*) FROM app_dat_inventario_productos ip, _ctx c
      WHERE ip.id_producto = c.id_producto
        AND ip.cantidad_final < 0)                      AS negativos_esp_0,
    (SELECT count(*) FROM app_dat_inventario_productos ip, _ctx c
      WHERE ip.id_producto = c.id_producto
        AND ip.id_presentacion IS NULL)                 AS pres_null_esp_0,
    (SELECT count(*) FROM app_dat_inventario_productos i2, _ctx c
      WHERE i2.id_producto = c.id_producto
        AND i2.origen_cambio = 3
        AND i2.cantidad_inicial <> COALESCE((
              SELECT i3.cantidad_final
                FROM app_dat_inventario_productos i3
               WHERE i3.id_producto = i2.id_producto
                 AND i3.id_ubicacion IS NOT DISTINCT FROM i2.id_ubicacion
                 AND i3.id_presentacion IS NOT DISTINCT FROM i2.id_presentacion
                 AND i3.id < i2.id
               ORDER BY i3.id DESC LIMIT 1), 0))        AS cadena_rota_esp_0) x;

SELECT jsonb_pretty(jsonb_object_agg(k, v)) AS bloque_c_ajuste FROM _r;

ROLLBACK;


-- ============================================================================
-- DESPUES DE LOS ROLLBACK · comprobar que produccion quedo intacta
-- ============================================================================
-- Correr como consulta aparte. Todo debe dar 0.
--
--   SELECT
--     (SELECT count(*) FROM app_dat_producto
--       WHERE denominacion LIKE 'ZZ TEST F1%')            AS productos_test,
--     (SELECT count(*) FROM app_dat_operaciones
--       WHERE observaciones LIKE 'test F1%')              AS operaciones_test,
--     (SELECT count(*) FROM app_dat_conversion_presentacion
--       WHERE motivo IN ('extraccion','ajuste'))          AS conversiones_test;
--
-- Nota: las secuencias (app_dat_producto.id, app_dat_operaciones.id,
-- app_dat_conversion_presentacion.id) avanzan aunque se haga ROLLBACK, porque
-- no son transaccionales. Es normal y no rompe nada.
