-- ============================================================================
-- 25 · La venta abre y arma empaques (rebalanceo en fn_registrar_venta)
-- ============================================================================
-- Ultimo tramo de la Fase 4: vender 5 Cajas cuando solo hay Unidades ahora
-- empaqueta solo (en cadena si hace falta), y vender 1 Unidad cuando solo hay
-- Cajas abre una.
--
-- APLICADO en produccion y verificado (ver «Estado» al final).
--
-- ----------------------------------------------------------------------------
-- Que faltaba
-- ----------------------------------------------------------------------------
-- `fn_rebalancear_presentaciones` (03) y `fn_descontar_con_rebalanceo` (07)
-- existen y estan probadas desde la Fase 0, pero **la venta nunca las llamaba**.
-- El `22` arreglo de que presentacion se lee el saldo y el `24` la cantidad que
-- va al BOM; lo que quedaba es que la venta pudiera convertir.
--
-- ----------------------------------------------------------------------------
-- ⚠️ CORRECCION IMPORTANTE: la venta SI valida stock
-- ----------------------------------------------------------------------------
-- Durante el analisis se creyo que la venta no validaba stock, porque el INSERT
-- hace `cantidad_final - cantidad` sin comprobar nada. **Es falso.** La
-- validacion existe, en otro sitio:
--
--     CHECK (fn_validar_cantidad_final_inventario(id_producto, cantidad_final))
--       -> constraint `chk_cantidad_final_conditional` en
--          app_dat_inventario_productos
--
-- Y esa funcion lee una bandera POR TIENDA:
-- `app_dat_configuracion_tienda.permite_vender_aun_sin_disponibilidad`.
--   · false → `cantidad_final >= 0` obligatorio (la venta ya falla hoy)
--   · true  → cualquier cantidad vale (la tienda vende en negativo a proposito)
--
-- Verificado con la funcion viva, SIN parche: vender 999.999 de PETROLEO (10474)
-- en la tienda 45 ya devuelve
-- «Error al registrar venta: new row ... violates check constraint».
--
-- Los 5 saldos negativos vivos del ledger no son «ausencia de validacion»: son
-- las tiendas que tienen la bandera encendida.
--
-- ----------------------------------------------------------------------------
-- Las DOS guardas de compatibilidad
-- ----------------------------------------------------------------------------
-- `fn_rebalancear_presentaciones` aborta con `INSUFFICIENT_STOCK_CONVERTIBLE`
-- cuando no alcanza ni convirtiendo. Enchufarla a secas cambiaria el
-- comportamiento de ventas que hoy pasan, asi que lleva dos guardas.
--
-- **Guarda 1 — solo multipresentacion** (`v_n_pres > 1`)
--
-- Con una sola presentacion no hay nada que convertir ni validacion que aporte
-- (el CHECK ya esta). Medicion sobre ventas REALES de barra, 30 dias, usando
-- `cantidad_inicial` de la fila del ledger (el saldo que habia ANTES de cada
-- venta):
--
--     ventas de barra ................................. 17.374
--     el saldo previo alcanzaba ....................... 17.354
--     el saldo previo NO alcanzaba .................... 20   (0,12 %)
--     de esas 20, con otra presentacion que convertir .. 0
--
-- Las 20 son de **4 productos de UNA sola presentacion** (PETROLEO x17 en la
-- tienda 45, «plancha cubana», «Compresor Hyundai», «PUNTA DE RABO DE GATO»).
-- La guarda las deja pasar exactamente como hoy.
--
-- Reparto del catalogo: **8.699 productos de una sola presentacion** (se saltan
-- por completo) y **94 multipresentacion** (los que este plan habilita).
-- Reconfirmado por PostgREST: 8.905 filas de `app_dat_producto_presentacion`,
-- 8.793 productos distintos.
--
-- **Guarda 2 — respetar `permite_vender_aun_sin_disponibilidad`**
--
-- Si el rebalanceo no alcanza, se consulta la bandera de la tienda:
--   · false → se aborta con el error del helper (la tienda ya rechazaba hoy,
--             solo que con el mensaje feo del CHECK; ahora dice cuanto se puede
--             servir)
--   · true  → **se deja pasar** al INSERT y decide el CHECK, igual que hoy
--
-- Sin esta guarda se rompian las tiendas que encendieron la bandera a proposito:
--
--     permite_negativo = false → 66 tiendas, 59 productos multipresentacion
--     permite_negativo = true  →  2 tiendas, 31 productos multipresentacion
--
-- Esos 31 productos en 2 tiendas son exactamente los que se habrian bloqueado.
--
-- ⚠️ Ojo con una medicion equivocada: usar `fn_preview_rebalanceo` sobre ventas
-- historicas da **369 de 3.000** «rechazadas», y es falso. La preview mira el
-- saldo de HOY, no el que habia cuando se hizo la venta. La fuente correcta es
-- `cantidad_inicial` del ledger.
--
-- ----------------------------------------------------------------------------
-- Por que solo en barra no elaborada
-- ----------------------------------------------------------------------------
-- Las otras tres rutas no decrementan el SKU en ese INSERT (el `CASE` deja el
-- saldo igual): en elaborado y en cocina lo hace `fn_descontar_venta_enrutada`
-- sobre la receta o la porcion. Rebalancear el SKU ahi no tendria sentido y
-- ademas duplicaria movimientos.
--
-- ----------------------------------------------------------------------------
-- Compatibilidad con la app en produccion
-- ----------------------------------------------------------------------------
-- · Ninguna firma cambia; `RETURNS jsonb` y `prosecdef` intactos.
-- · `id_presentacion: null` de la app vieja sigue funcionando: la cascada de
--   fallback resuelve la base ANTES de este bloque, y con la base el rebalanceo
--   no tiene nada que hacer (ya es el saldo propio).
-- · Producto de una sola presentacion → se salta (98,9 % del catalogo).
-- · Tienda con la bandera encendida → se salta el rechazo.
-- · El error nuevo (`INSUFFICIENT_STOCK_CONVERTIBLE`) viaja en el mismo `jsonb`
--   con `status: 'error'` que la app ya sabe manejar; no es una excepcion nueva.
--
-- Idempotente: se salta si `fn_rebalancear_presentaciones` ya aparece en el
-- cuerpo, y aborta si los anclajes no estan exactamente una vez.
--
-- ⚠️ PITFALL de la guarda de conteo: `v_n_pres` y `v_permite_neg` aparecen
-- **3** veces cada una en el cuerpo parchado (declaracion + 2 usos), no 4.
-- Contar mal aborta el DO block — que es lo correcto, pero cuesta un intento.
-- ============================================================================

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

        IF position('fn_rebalancear_presentaciones(' in v_def) > 0 THEN
            v_total := v_total + 1;
            CONTINUE;   -- ya aplicado
        END IF;

        -- 1) variables nuevas
        v_new := replace(v_def,
            E'    v_descuento_bom JSONB;   -- resultado de fn_descontar_venta_enrutada\r\n',
            E'    v_descuento_bom JSONB;   -- resultado de fn_descontar_venta_enrutada\r\n'
         || E'    v_rebal_sku     JSONB;   -- resultado de fn_rebalancear_presentaciones\r\n'
         || E'    v_n_pres        INT;     -- presentaciones del producto (guarda 1)\r\n'
         || E'    v_permite_neg   BOOLEAN; -- permite_vender_aun_sin_disponibilidad (guarda 2)\r\n');

        -- 2) rebalanceo ANTES del INSERT que decrementa el SKU
        v_new := replace(v_new,
            E'      -- Actualizar inventario usando el ID de extracción correcto\r\n',
            E'      -- FASE 4 - Abrir o armar empaques para servir la venta.\r\n'
         || E'      -- Guardas de compatibilidad: solo multipresentacion, y si no\r\n'
         || E'      -- alcanza se respeta permite_vender_aun_sin_disponibilidad.\r\n'
         || E'      SELECT count(*) INTO v_n_pres FROM app_dat_producto_presentacion pp\r\n'
         || E'       WHERE pp.id_producto = (v_producto->>''id_producto'')::BIGINT;\r\n'
         || E'\r\n'
         || E'      IF v_es_elaborado = false AND v_origen_venta = ''barra''\r\n'
         || E'         AND COALESCE(v_n_pres, 0) > 1 THEN\r\n'
         || E'        v_rebal_sku := public.fn_rebalancear_presentaciones(\r\n'
         || E'          p_id_producto := (v_producto->>''id_producto'')::BIGINT,\r\n'
         || E'          p_id_ubicacion := v_id_ubicacion_resuelto,\r\n'
         || E'          p_id_presentacion := v_producto_presentacion_id,\r\n'
         || E'          p_cantidad := (v_producto->>''cantidad'')::NUMERIC,\r\n'
         || E'          p_id_variante := NULLIF(v_producto->>''id_variante'', '''')::BIGINT,\r\n'
         || E'          p_id_opcion_variante := NULLIF(v_producto->>''id_opcion_variante'', '''')::BIGINT,\r\n'
         || E'          p_id_operacion := v_id_operacion,\r\n'
         || E'          p_uuid := p_uuid,\r\n'
         || E'          p_motivo := ''venta''\r\n'
         || E'        );\r\n'
         || E'\r\n'
         || E'        IF (v_rebal_sku->>''status'') <> ''success'' THEN\r\n'
         || E'          SELECT COALESCE(ct.permite_vender_aun_sin_disponibilidad, false)\r\n'
         || E'            INTO v_permite_neg FROM app_dat_producto p2\r\n'
         || E'            JOIN app_dat_configuracion_tienda ct ON ct.id_tienda = p2.id_tienda\r\n'
         || E'           WHERE p2.id = (v_producto->>''id_producto'')::BIGINT;\r\n'
         || E'\r\n'
         || E'          IF COALESCE(v_permite_neg, false) = false THEN\r\n'
         || E'            RETURN v_rebal_sku || jsonb_build_object(\r\n'
         || E'              ''id_producto'', (v_producto->>''id_producto'')::BIGINT,\r\n'
         || E'              ''id_ubicacion'', v_id_ubicacion_resuelto);\r\n'
         || E'          END IF;\r\n'
         || E'        END IF;\r\n'
         || E'      END IF;\r\n'
         || E'\r\n'
         || E'      -- Actualizar inventario usando el ID de extracción correcto\r\n');

        SELECT count(*) INTO v_n
          FROM regexp_matches(v_new, 'fn_rebalancear_presentaciones\(', 'g');
        IF v_n <> 1 THEN
            RAISE EXCEPTION '% : esperaba 1 rebalanceo, hay %', v_f, v_n;
        END IF;

        -- 3 = declaracion + 2 usos. NO 4.
        SELECT count(*) INTO v_n FROM regexp_matches(v_new, 'v_permite_neg', 'g');
        IF v_n <> 3 THEN
            RAISE EXCEPTION '% : esperaba 3 usos de v_permite_neg, hay %', v_f, v_n;
        END IF;

        EXECUTE v_new;
        v_total := v_total + 1;
    END LOOP;

    IF v_total <> 2 THEN
        RAISE EXCEPTION 'Esperaba parchear 2 funciones, parcheo %', v_total;
    END IF;

    RAISE NOTICE 'Venta: rebalanceo de presentaciones activo (2 funciones)';
END $do$;


-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================

-- V1 · ⭐ Las 4 marcas de los 4 archivos que tocaron estas funciones.
--      Esperado: 1 / 3 / 3 / 1 / 1 en cada una.
--
--   SELECT p.proname,
--          (SELECT count(*) FROM regexp_matches(p.prosrc, 'fn_rebalancear_presentaciones\(', 'g')) AS rebal_25,
--          (SELECT count(*) FROM regexp_matches(p.prosrc, 'v_n_pres', 'g'))       AS guarda_pres,
--          (SELECT count(*) FROM regexp_matches(p.prosrc, 'v_permite_neg', 'g'))  AS guarda_neg,
--          (SELECT count(*) FROM regexp_matches(p.prosrc, 'fn_cantidad_en_base\(', 'g')) AS bom_24,
--          (SELECT count(*) FROM regexp_matches(p.prosrc,
--             'COALESCE\(id_presentacion, 0\) = COALESCE\(v_producto_presentacion_id, 0\)', 'g')) AS filtro_22,
--          p.prosecdef, pg_get_function_result(p.oid) AS devuelve
--     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname = 'public'
--      AND p.proname IN ('fn_registrar_venta', 'fn_registrar_venta_mesa')
--    ORDER BY 1;
--
--   medido tras aplicar: 1/3/3/1/1 en las dos, prosecdef=false, jsonb.

-- V2 · ⭐⭐ Ensayo funcional de los 6 casos (ROLLBACK). Datos usados:
--
--   producto 1073 «ala», tienda 47 (NO permite negativo), ubicacion 63:
--     Unidad  1189  factor 1   es_base   saldo 2400
--     Blister 1190  factor 12            sin saldo
--     Caja    1191  factor 24            sin saldo
--   producto 217 «azucar refino», tienda 11 (SI permite negativo), ubicacion 37:
--     Bolsa 336 factor 1 es_base = 100 · Bulto 337 factor 10 = 0
--   producto 10474 «PETROLEO», tienda 45, UNA sola presentacion
--
--   BEGIN;
--     CREATE TEMP TABLE r(caso text, status text, error_code text, msg text) ON COMMIT DROP;
--
--     -- 1) 5 Cajas del 1073 -> EMPAQUETA EN CADENA y pasa
--     DO $$ DECLARE v jsonb; BEGIN
--       v := public.fn_registrar_venta(56,'b12bb482-5119-4cc4-ae0a-a18bdc503edd'::uuid,
--              jsonb_build_array(jsonb_build_object('id_producto',1073,'id_ubicacion',63,
--              'id_presentacion',1191,'cantidad',5,'precio_unitario',100,'sku_producto','X')),
--              null,null,null,2::smallint,null);
--       INSERT INTO r VALUES ('1_multi_5_cajas_empaqueta', v->>'status', coalesce(v->>'error_code','-'), left(coalesce(v->>'message',''),95));
--     EXCEPTION WHEN OTHERS THEN INSERT INTO r VALUES ('1_multi_5_cajas_empaqueta','EXCEPTION',SQLSTATE,left(SQLERRM,95)); END $$;
--
--     -- 2) 500 Cajas -> RECHAZO con el mensaje del helper
--     -- 3) 50 Bultos del 217 en tienda 11 (permite negativo) -> PASA como hoy
--     -- 4) 999999 de PETROLEO (una sola pres.) -> error de CHECK, igual que hoy
--     -- 5) app vieja: sin 'id_presentacion' -> PASA
--     -- 6) 5 Bolsas (la base, alcanza) -> PASA
--
--     SELECT * FROM r ORDER BY caso;
--   ROLLBACK;
--
--   Resultado medido contra la funcion viva YA PARCHADA:
--     1_multi_5_cajas_empaqueta ....... success
--     2_multi_500_cajas_rechazo ....... error INSUFFICIENT_STOCK_CONVERTIBLE
--                                       «Stock insuficiente de Caja: se piden 500
--                                        y el convertible alcanza para 95»
--     3_permite_neg_pasa .............. success      <- guarda 2
--     4_una_pres_check_igual_que_hoy .. error de CHECK constraint  <- guarda 1
--     5_app_vieja_pres_null ........... success
--     6_base_alcanza .................. success

-- V3 · ⭐ La cadena de conversiones que deja el caso (1) en el ledger:
--
--   SELECT ip.id_presentacion, np.denominacion, ip.cantidad_inicial,
--          ip.cantidad_final, ip.origen_cambio, ip.id_conversion
--     FROM app_dat_inventario_productos ip
--     JOIN app_dat_producto_presentacion pp ON pp.id = ip.id_presentacion
--     JOIN app_nom_presentacion np ON np.id = pp.id_presentacion
--    WHERE ip.id_producto = 1073 AND ip.id_ubicacion = 63
--    ORDER BY ip.id DESC LIMIT 6;
--
--   medido (vender 5 Cajas = 120 Unidades, dos conversiones encadenadas):
--
--     Unidad  2400 -> 2280   origen_cambio 20  id_conversion 20
--     Blister    0 ->   10   origen_cambio 20  id_conversion 20
--     Blister   10 ->    0   origen_cambio 20  id_conversion 21
--     Caja       0 ->    5   origen_cambio 20  id_conversion 21
--     Caja       5 ->    0   origen_cambio  3  (la venta)
--
--   Cada eslabon con su `id_conversion` propio: por eso `obtener_ipv` no lo lee
--   como ajustes sueltos.

-- V4 · No-regresion historica: las 20 ventas que no alcanzaban siguen pasando.
--
--   WITH casos AS (
--     SELECT ep.id_producto, count(*) veces,
--            (SELECT count(*) FROM app_dat_producto_presentacion pp
--              WHERE pp.id_producto = ep.id_producto) n_pres
--       FROM app_dat_extraccion_productos ep
--       JOIN app_dat_inventario_productos ip ON ip.id_extraccion = ep.id
--       JOIN app_dat_producto p ON p.id = ep.id_producto
--      WHERE ep.created_at > now() - interval '30 days'
--        AND ip.origen_cambio = 3
--        AND COALESCE(p.es_elaborado,false) = false
--        AND COALESCE(p.es_servicio,false) = false
--        AND ip.cantidad_inicial < ep.cantidad
--      GROUP BY 1)
--   SELECT sum(veces) AS ventas_sin_saldo_previo,
--          sum(veces) FILTER (WHERE n_pres > 1)  AS afectadas_por_la_validacion,
--          sum(veces) FILTER (WHERE n_pres <= 1) AS se_saltan_por_la_guarda
--     FROM casos;
--   -- medido: 20 / 0 / 20 . `afectadas_por_la_validacion` DEBE ser 0.

-- V5 · Exposicion de la guarda 2 (tiendas que venden en negativo a proposito):
--
--   WITH multi AS (
--     SELECT pp.id_producto, p.id_tienda
--       FROM app_dat_producto_presentacion pp
--       JOIN app_dat_producto p ON p.id = pp.id_producto
--      GROUP BY 1,2 HAVING count(*) > 1)
--   SELECT ct.permite_vender_aun_sin_disponibilidad AS permite_negativo,
--          count(DISTINCT ct.id_tienda) AS tiendas,
--          count(DISTINCT m.id_producto) AS productos_multipresentacion
--     FROM app_dat_configuracion_tienda ct
--     LEFT JOIN multi m ON m.id_tienda = ct.id_tienda
--    GROUP BY 1 ORDER BY 1;
--   -- medido: false -> 66 tiendas / 59 productos
--   --         true  ->  2 tiendas / 31 productos  (los que la guarda 2 protege)


-- ============================================================================
-- ESTADO
-- ============================================================================
-- **APLICADO** en produccion (proyecto vsieeihstajlrdvpuooh) y verificado:
--   · V1 → 1/3/3/1/1 en las dos funciones, firma y prosecdef intactos
--   · V2 → los 6 casos con el resultado esperado
--   · V3 → cadena de 2 conversiones auditada con id_conversion 20 y 21
--
-- Con esto la Fase 4 queda cerrada: la venta guarda la presentacion vendida
-- (22), convierte la cantidad para el BOM (24) y abre/arma empaques (25).
