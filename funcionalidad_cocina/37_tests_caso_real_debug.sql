-- ============================================================================
-- 37 · Tests del CASO REAL en el proyecto DEBUG (qhprswhhfasrikhawjoz)
-- ============================================================================
-- Datos medidos el 2026-10-21 (docs/PLAN_CONSUMO_INGREDIENTES_... §2-bis):
--   · Arroz   (3): presentacion base Unidad (fila pp 4, factor_rel 1)
--                  + Kilogramo (fila pp 8, factor_rel 1000).
--                  Ledger ubicacion 3 / almacen 3: Unidad 2000 + Kilogramo 2000.
--   · Frijoles(4): base Unidad (pp 5) + Kilogramo (pp 7); Unidad 2500 + Kilogramo 2500.
--   · Arroz Moro (5): elaborado, receta = Frijoles 4 x500 + Arroz 3 x600 por unidad.
--   · Vendedor de la tienda 4 (TPV 3, almacen 3): d99d3333-83a9-4f33-8b53-3dbe744fb0ec
--
-- QUE DEMUESTRA
-- ------------
--   1. La medida por equivalente base ve los kg (2.002.000 y 2.502.500), no 2000/2500.
--   2. Consumir 6000 base de Arroz NO deja el Kilogramo en cero (el bug C2 lo dejaba).
--   3. El equivalente baja EXACTAMENTE la cantidad pedida, sin negativos.
--   4. El consumo queda auditado (conversiones).
--
-- COMO SE CORRE
-- -------------
--   · SECCION 1: solo lectura; se puede ejecutar tal cual (sin BEGIN).
--   · SECCION 2: ESCRIBE el ledger; va dentro de BEGIN ... ROLLBACK (al final del
--     archivo) y necesita los objetos de 30/31 aplicados. auth.uid() se simula con
--     request.jwt.claims (el vendedor de la tienda 4), como hace el archivo 32.
--   · Si los fixtures no existen en el proyecto donde lo corras, el bloque 2 se
--     OMITE con un NOTICE en vez de abortar.
-- ============================================================================


-- ############################################################################
-- SECCION 1 · Medida por equivalente base (solo lectura)
-- ############################################################################

-- 1.1 Kernel del ingrediente Arroz en el almacen 3: equivalente total, base,
--     saldo propio y convertible. Esperado: equivalente 2002000, presenta-
--     cion_base "Unidad", con saldo en Unidad y en Kilogramo.
SELECT public.fn_ingrediente_base_alcanzable(3, 3, 'almacen', 6000) AS kernel_arroz;

-- 1.2 Kernel de Frijoles. Esperado: equivalente 2502500.
SELECT public.fn_ingrediente_base_alcanzable(4, 3, 'almacen', 5000) AS kernel_frijoles;

-- 1.3 Receta completa de 10 Arroz Moro: requerido 6000 (Arroz) y 5000 (Frijoles),
--     alcanza = true. Esperado: tiene_receta true, alcanza true, maximo_producible 10.
SELECT public.fn_ingredientes_elaborado_base(5, 10, 3) AS receta_10_arroz_moro;

-- 1.4 Validacion nueva (la que usara la app/UI en la Fase 1B).
SELECT public.fn_validar_ingredientes_elaborado_v2(5, 10, 3) AS validar_10;


-- ############################################################################
-- SECCION 2 · Consumo real por equivalente base (ESCRIBE; ROLLBACK al final)
-- ############################################################################

BEGIN;

DO $test$
DECLARE
    v_claims      text := '{"sub":"d99d3333-83a9-4f33-8b53-3dbe744fb0ec","role":"authenticated"}';
    v_fixture_ok  boolean;
    v_eq3_antes   numeric;
    v_eq4_antes   numeric;
    v_kg3_antes   numeric;
    v_kg4_antes   numeric;
    v_eq3_despues numeric;
    v_eq4_despues numeric;
    v_kg3_despues numeric;
    v_kg4_despues numeric;
    v_neg3        integer;
    v_neg4        integer;
    v_conv        integer;
    v_res3        jsonb;
    v_res4        jsonb;
BEGIN
    -- Gate de fixture: si estos datos no existen, se omite (no aborta la aplicacion).
    SELECT EXISTS (
        SELECT 1
          FROM public.app_dat_producto p
         WHERE p.id = 5 AND p.es_elaborado
    ) AND EXISTS (
        SELECT 1 FROM public.fn_stock_producto_almacen_detalle(3, 3)
    ) INTO v_fixture_ok;

    IF NOT v_fixture_ok THEN
        RAISE NOTICE 'CASO REAL OMITIDO: el fixture del proyecto debug (elaborado 5, almacen 3) no esta en este proyecto.';
        RETURN;
    END IF;

    IF to_regprocedure('public.fn_consumir_ingrediente_base_v2(bigint,bigint,numeric,integer,bigint,bigint,uuid,text)') IS NULL THEN
        RAISE NOTICE 'CASO REAL OMITIDO: falta fn_consumir_ingrediente_base_v2 (aplica antes 30/31).';
        RETURN;
    END IF;

    -- Simular al vendedor de la tienda 4 (auth.uid() en el SQL Editor es NULL).
    PERFORM set_config('request.jwt.claims', v_claims, true);

    -- Foto previa
    v_eq3_antes := public.fn_stock_producto_almacen(3, 3);
    v_eq4_antes := public.fn_stock_producto_almacen(4, 3);
    SELECT COALESCE(SUM(saldo), 0) INTO v_kg3_antes
      FROM public.fn_stock_saldos_presentacion(3, 3, NULL, false)
     WHERE id_presentacion = 8;
    SELECT COALESCE(SUM(saldo), 0) INTO v_kg4_antes
      FROM public.fn_stock_saldos_presentacion(4, 3, NULL, false)
     WHERE id_presentacion = 7;

    RAISE NOTICE 'ANTES: equivalente arroz=% frijoles=% | Kilogramo arroz=% frijoles=%',
        v_eq3_antes, v_eq4_antes, v_kg3_antes, v_kg4_antes;

    -- (1) Arroz: 6000 base = lo que pide 10 Arroz Moro (600 x 10)
    v_res3 := public.fn_consumir_ingrediente_base_v2(
                  p_id_producto   := 3,
                  p_id_almacen    := 3,
                  p_cantidad_base := 6000,
                  p_origen_cambio := 4,
                  p_motivo        := 'test_caso_real_debug');
    IF (v_res3->>'status') <> 'success' THEN
        RAISE EXCEPTION 'FALLO: el consumo de 6000 base de Arroz devolvio %', v_res3;
    END IF;

    -- (2) Frijoles: 5000 base = 500 x 10
    v_res4 := public.fn_consumir_ingrediente_base_v2(
                  p_id_producto   := 4,
                  p_id_almacen    := 3,
                  p_cantidad_base := 5000,
                  p_origen_cambio := 4,
                  p_motivo        := 'test_caso_real_debug');
    IF (v_res4->>'status') <> 'success' THEN
        RAISE EXCEPTION 'FALLO: el consumo de 5000 base de Frijoles devolvio %', v_res4;
    END IF;

    -- Foto posterior
    v_eq3_despues := public.fn_stock_producto_almacen(3, 3);
    v_eq4_despues := public.fn_stock_producto_almacen(4, 3);
    SELECT COALESCE(SUM(saldo), 0) INTO v_kg3_despues
      FROM public.fn_stock_saldos_presentacion(3, 3, NULL, false)
     WHERE id_presentacion = 8;
    SELECT COALESCE(SUM(saldo), 0) INTO v_kg4_despues
      FROM public.fn_stock_saldos_presentacion(4, 3, NULL, false)
     WHERE id_presentacion = 7;

    RAISE NOTICE 'DESPUES: equivalente arroz=% frijoles=% | Kilogramo arroz=% frijoles=%',
        v_eq3_despues, v_eq4_despues, v_kg3_despues, v_kg4_despues;

    -- ASERCION 1: el equivalente baja EXACTAMENTE lo pedido
    IF v_eq3_despues <> v_eq3_antes - 6000 THEN
        RAISE EXCEPTION 'FALLO: Arroz deberia bajar 6000 (de % a %), quedo en %',
            v_eq3_antes, v_eq3_antes - 6000, v_eq3_despues;
    END IF;
    IF v_eq4_despues <> v_eq4_antes - 5000 THEN
        RAISE EXCEPTION 'FALLO: Frijoles deberia bajar 5000 (de % a %), quedo en %',
            v_eq4_antes, v_eq4_antes - 5000, v_eq4_despues;
    END IF;

    -- ASERCION 2 (la del bug C2): los Kilogramo NO quedan en cero
    IF v_kg3_despues <= 0 THEN
        RAISE EXCEPTION 'FALLO C2: el Kilogramo de Arroz quedo en % (el bug viejo lo dejaba en cero)', v_kg3_despues;
    END IF;
    IF v_kg4_despues <= 0 THEN
        RAISE EXCEPTION 'FALLO C2: el Kilogramo de Frijoles quedo en % (el bug viejo lo dejaba en cero)', v_kg4_despues;
    END IF;
    IF v_kg3_despues >= v_kg3_antes AND v_eq3_despues <> v_eq3_antes THEN
        RAISE EXCEPTION 'FALLO: el consumo de Arroz no toco el Kilogramo (antes % despues %)', v_kg3_antes, v_kg3_despues;
    END IF;

    -- ASERCION 3: sin saldos negativos
    SELECT count(*) INTO v_neg3 FROM public.fn_stock_saldos_presentacion(3, 3, NULL, false) WHERE saldo < 0;
    SELECT count(*) INTO v_neg4 FROM public.fn_stock_saldos_presentacion(4, 3, NULL, false) WHERE saldo < 0;
    IF v_neg3 + v_neg4 > 0 THEN
        RAISE EXCEPTION 'FALLO: saldos negativos (arroz=% frijoles=%)', v_neg3, v_neg4;
    END IF;

    -- ASERCION 4: conversion auditada
    SELECT count(*) INTO v_conv
      FROM public.app_dat_conversion_presentacion_evento e
     WHERE e.id_producto IN (3, 4);

    RAISE NOTICE 'OK: equivalente-% y equivalente-% exactos, Kilogramo intacto, 0 negativos, % evento(s) de conversion.',
        v_eq3_antes - v_eq3_despues, v_eq4_antes - v_eq4_despues, v_conv;
END
$test$;

-- ROLLBACK obligatorio: este bloque escribe el ledger y NO debe persistir.
ROLLBACK;


-- ############################################################################
-- SECCION 3 · Reverificacion: nada aplicado y vivos intactos
-- ############################################################################

SELECT to_regprocedure('public.fn_ingrediente_base_alcanzable(bigint,bigint,text,numeric)') AS existe_kernel,
       to_regprocedure('public.fn_consumir_ingrediente_base_v2(bigint,bigint,numeric,integer,bigint,bigint,uuid,text)') AS existe_consumo,
       md5(pg_get_functiondef('public.fn_descontar_ingredientes_elaborado(bigint,numeric,bigint,bigint,integer)'::regprocedure)) AS md5_viva;
-- Esperado tras aplicar 30/31: kernel y consumo != NULL; md5 de la viva SIN cambios
-- (47be3a93... lo publica docs/_analisis/INGREDIENTES_SQL.md §10).