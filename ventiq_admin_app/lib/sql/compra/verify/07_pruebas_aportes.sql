-- ============================================================================
-- verify/07_pruebas_aportes.sql — pruebas de DINERO de los aportes de inversores
--
-- REQUIERE: 03a, 03b, 04 y 07 aplicados en `newa`.
--
-- Qué prueba (compra de 2.000 en modo inversores):
--   1. X aporta 800 y Y aporta 700 → restante 500 y **no deja pagar**;
--   2. aportar 600 (exceso) → rechazo;
--   3. Z aporta los 500 → cubierto, `Pagar` habilitado → `pagada`;
--   4. el pago escribe sus filas `origen='aporte'` y **no** mueve el fondo
--      (0 movimientos con `id_compra`, saldo de la tienda intacto);
--   5. reservar del fondo la misma compra → rechazo por exclusividad;
--   6. devolver el aporte de X → `devuelto`, sin tocar el fondo, idempotente;
--   7. anular con aportes vigentes → rechazo; devueltos todos → anula y
--      **devuelve 0 al fondo** (el dinero nunca salió de él);
--   8. cancelar con aportes vigentes → rechazo;
--   9. los triggers rechazan la escritura directa (reserva del fondo, pago del
--      fondo, aporte en compra del fondo, cargo con `origen_pago='fondo'`) y el
--      cambio de `modo_liquidacion`;
--  10. el interés sólo existe en naturaleza `pasivo`.
--  11. defensas de la revisión adversarial: compra de inversores con total 0 no
--      se paga, el ajuste tardío se registra con `origen_pago = 'externo'` sin
--      mover `total_financiado`, no se devuelve con la compra recibida, y las
--      escrituras directas (convertir un pago de aporte en pago del fondo,
--      reescribir el aporte, resucitarlo, borrarlo, descongelar el total,
--      apuntar un pago al aporte de otra compra) se rechazan.
-- Termina en ROLLBACK: no deja datos (los inversores de prueba incluidos).
-- ============================================================================

BEGIN;

SET LOCAL request.jwt.claims = '{"sub":"3d7bae51-d5db-4523-a196-522a41b006d9","role":"authenticated"}';

CREATE TEMP TABLE _res (
    n        integer,
    chequeo  text,
    esperado text,
    actual   text,
    ok       boolean
) ON COMMIT DROP;

DO $$
DECLARE
    v_prov      bigint;
    v_prod      bigint;
    v_ubi       bigint;
    v_inv_x     bigint;
    v_inv_y     bigint;
    v_inv_z     bigint;
    v_comp      bigint;
    v_comp_b    bigint;
    v_comp_f    bigint;
    v_ap_x      bigint;
    v_ap_y      bigint;
    v_ap_z      bigint;
    v_res       jsonb;
    v_msg       text;
    v_estado    text;
    v_modo      text;
    v_total     numeric;
    v_aportado  numeric;
    v_devuelto  numeric;
    v_faltante  numeric;
    v_saldo_a   numeric;
    v_saldo_d   numeric;
    v_n         integer;
    v_n2        integer;
    v_aporte    record;
    v_ajuste    record;
    v_comp_d    bigint;
    v_comp_e    bigint;
    v_ap_b      bigint;
    v_ap_e      bigint;
    v_sqlstate  text;
    v_tipo_fle  bigint;
BEGIN
    SELECT id INTO v_prov FROM public.app_dat_proveedor
     WHERE idtienda = 9 ORDER BY id LIMIT 1;
    SELECT id INTO v_prod FROM public.app_dat_producto
     WHERE id_tienda = 9 ORDER BY id LIMIT 1;
    SELECT l.id INTO v_ubi
      FROM public.app_dat_layout_almacen l
      JOIN public.app_dat_almacen a ON a.id = l.id_almacen
     WHERE a.id_tienda = 9 ORDER BY l.id LIMIT 1;
    SELECT id INTO v_tipo_fle FROM public.app_cont_tipo_costo
     WHERE lower(btrim(denominacion)) = 'flete' LIMIT 1;

    IF v_prov IS NULL OR v_prod IS NULL OR v_ubi IS NULL OR v_tipo_fle IS NULL THEN
        INSERT INTO _res VALUES (0, 'fixtures',
            'proveedor, producto, ubicación y tipo Flete de la tienda 9',
            format('prov=%s prod=%s ubi=%s flete=%s', v_prov, v_prod, v_ubi, v_tipo_fle), false);
        RETURN;
    END IF;

    -- Inversores de prueba para la tienda 9 (los 6 reales son de las tiendas 4
    -- y 8). El ROLLBACK los borra.
    INSERT INTO public.fdi_dat_inversor (id_tienda, nombre, porcentaje, activo)
    VALUES (9, 'PRUEBA X', 40, true) RETURNING id INTO v_inv_x;
    INSERT INTO public.fdi_dat_inversor (id_tienda, nombre, porcentaje, activo)
    VALUES (9, 'PRUEBA Y', 35, true) RETURNING id INTO v_inv_y;
    INSERT INTO public.fdi_dat_inversor (id_tienda, nombre, porcentaje, activo)
    VALUES (9, 'PRUEBA Z', 25, true) RETURNING id INTO v_inv_z;

    -- Saldo total de la tienda antes de nada: el fondo no debe moverse.
    SELECT COALESCE(sum(saldo), 0) INTO v_saldo_a
      FROM public.fdi_dat_saldo WHERE id_tienda = 9;

    -- Compra A: 200 u a 10 = 2.000, modo inversores.
    v_res := public.fn_fdi_compra_crear(
        p_id_tienda        => 9,
        p_id_proveedor     => v_prov,
        p_numero_factura   => 'PRUEBA-07',
        p_fecha_factura    => current_date,
        p_moneda_total     => 'USD',
        p_tasa_factura     => 1,
        p_lineas           => jsonb_build_array(
            jsonb_build_object('id_producto', v_prod, 'cantidad', 200,
                               'costo_unitario', 10, 'id_ubicacion', v_ubi)),
        p_ajustes          => '[]'::jsonb,
        p_modo_liquidacion => 'inversores',
        p_idempotency_key  => gen_random_uuid());
    v_comp := (v_res ->> 'id_compra')::bigint;

    SELECT modo_liquidacion, estado, total_financiado
      INTO v_modo, v_estado, v_total
      FROM public.fdi_dat_compra WHERE id = v_comp;
    INSERT INTO _res VALUES (1, 'compra_inversores', 'inversores / creada / 2000.00',
        v_modo || ' / ' || v_estado || ' / ' || v_total::text,
        v_modo = 'inversores' AND v_estado = 'creada' AND v_total = 2000);

    -- 1) X aporta 800.
    v_res := public.fn_fdi_compra_aporte_registrar(
        p_id_compra   => v_comp,
        p_id_inversor => v_inv_x,
        p_moneda      => 'USD',
        p_monto       => 800,
        p_idempotency_key => gen_random_uuid());
    v_ap_x := (v_res ->> 'id')::bigint;
    INSERT INTO _res VALUES (2, 'aporte_x', 'ok / 800.00 / faltan 1200.00',
        coalesce(v_res->>'status','?') || ' / ' || coalesce(v_res->>'monto_eq_total','?')
        || ' / faltan ' || coalesce(v_res->>'faltante','?'),
        v_res->>'status' = 'ok'
        AND (v_res->>'monto_eq_total')::numeric = 800
        AND (v_res->>'faltante')::numeric = 1200);

    -- Y aporta 700. La compra sigue en `creada` (el pago es explícito).
    v_res := public.fn_fdi_compra_aporte_registrar(
        p_id_compra   => v_comp,
        p_id_inversor => v_inv_y,
        p_moneda      => 'USD',
        p_monto       => 700,
        p_idempotency_key => gen_random_uuid());
    v_ap_y := (v_res ->> 'id')::bigint;

    v_res := public.fn_fdi_compra_aportes(v_comp);
    v_aportado := (v_res->>'aportado')::numeric;
    v_faltante := (v_res->>'faltante')::numeric;
    INSERT INTO _res VALUES (3, 'restante_500', '1500.00 / 500.00 / 75.00 / true',
        v_aportado::text || ' / ' || v_faltante::text || ' / ' || (v_res->>'pct')
        || ' / ' || (v_res->>'puede_registrar'),
        v_aportado = 1500 AND v_faltante = 500 AND (v_res->>'pct')::numeric = 75
        AND (v_res->>'puede_registrar') = 'true');
    INSERT INTO _res VALUES (4, 'pagar_bloqueado', 'false / menciona 500',
        (v_res->>'puede_pagar') || ' / ' || coalesce(v_res->>'motivo_bloqueo','NULL'),
        (v_res->>'puede_pagar') = 'false'
        AND (v_res->>'motivo_bloqueo') LIKE '%500%');

    -- 1b) Pagar sin cubrir el 100 % → error explícito.
    BEGIN
        v_res := public.fn_fdi_compra_pagar(p_id_compra => v_comp);
        v_msg := 'sin error';
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    INSERT INTO _res VALUES (5, 'pagar_incompleto_rechazado', 'faltan 500',
        v_msg, v_msg LIKE '%faltan 500%');

    -- 2) Aportar 600 de más → rechazo.
    BEGIN
        v_res := public.fn_fdi_compra_aporte_registrar(
            p_id_compra   => v_comp,
            p_id_inversor => v_inv_z,
            p_moneda      => 'USD',
            p_monto       => 600,
            p_idempotency_key => gen_random_uuid());
        v_msg := 'sin error';
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    INSERT INTO _res VALUES (6, 'exceso_rechazado', 'sólo faltan 500',
        v_msg, v_msg LIKE '%sólo faltan 500%');

    -- 3) Z aporta los 500 restantes.
    v_res := public.fn_fdi_compra_aporte_registrar(
        p_id_compra   => v_comp,
        p_id_inversor => v_inv_z,
        p_moneda      => 'USD',
        p_monto       => 500,
        p_idempotency_key => gen_random_uuid());
    v_ap_z := (v_res ->> 'id')::bigint;

    v_res := public.fn_fdi_compra_aportes(v_comp);
    INSERT INTO _res VALUES (7, 'cubierto_100', '2000.00 / 0 / true',
        (v_res->>'aportado') || ' / ' || (v_res->>'faltante') || ' / ' || (v_res->>'puede_pagar'),
        (v_res->>'aportado')::numeric = 2000
        AND (v_res->>'faltante')::numeric = 0
        AND (v_res->>'puede_pagar') = 'true');

    -- 5a) Exclusividad: reservar del fondo la misma compra → rechazo.
    BEGIN
        v_res := public.fn_fdi_compra_reservar(
            p_id_compra => v_comp, p_fuentes => '[]'::jsonb);
        v_msg := 'sin error';
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    INSERT INTO _res VALUES (8, 'reservar_fondo_rechazado', 'se liquida con inversores',
        v_msg, v_msg LIKE '%se liquida con inversores%');

    -- 3b) Pagar cubierto.
    v_res := public.fn_fdi_compra_pagar(p_id_compra => v_comp);
    SELECT estado INTO v_estado FROM public.fdi_dat_compra WHERE id = v_comp;
    INSERT INTO _res VALUES (9, 'pagada', 'ok / pagada / 2000.00',
        coalesce(v_res->>'status','?') || ' / ' || v_estado || ' / ' || coalesce(v_res->>'pagado','?'),
        v_res->>'status' = 'ok' AND v_estado = 'pagada'
        AND (v_res->>'pagado')::numeric = 2000);

    -- 4) El pago es de aportes, sin cuenta ni medio, y sin movimiento.
    SELECT count(*) FILTER (WHERE origen = 'aporte' AND id_aporte IS NOT NULL
                               AND id_cuenta IS NULL AND id_medio_pago IS NULL
                               AND id_movimiento IS NULL),
           count(*) FILTER (WHERE origen = 'fondo')
      INTO v_n, v_n2
      FROM public.fdi_dat_compra_pago WHERE id_compra = v_comp;
    INSERT INTO _res VALUES (10, 'pagos_de_aporte', '3 aporte / 0 fondo',
        v_n || ' aporte / ' || v_n2 || ' fondo', v_n = 3 AND v_n2 = 0);

    SELECT count(*) INTO v_n FROM public.fdi_dat_movimiento WHERE id_compra = v_comp;
    INSERT INTO _res VALUES (11, 'sin_movimientos_del_fondo', '0', v_n::text, v_n = 0);

    SELECT count(*) INTO v_n FROM public.fdi_dat_compra_reserva WHERE id_compra = v_comp;
    INSERT INTO _res VALUES (12, 'sin_reservas', '0', v_n::text, v_n = 0);

    SELECT COALESCE(sum(saldo), 0) INTO v_saldo_d
      FROM public.fdi_dat_saldo WHERE id_tienda = 9;
    INSERT INTO _res VALUES (13, 'saldo_intacto', v_saldo_a::text, v_saldo_d::text,
        v_saldo_d = v_saldo_a);

    -- El invariante de la fase 4 sigue valiendo: pagada ⇒ Σ pagos = total.
    SELECT COALESCE(sum(monto), 0) INTO v_n2 FROM public.fdi_dat_compra_pago WHERE id_compra = v_comp;
    INSERT INTO _res VALUES (14, 'pagada_cuadra_pagos', '2000.00', v_n2::text, v_n2 = 2000);

    -- Reintento del pago: duplicada, sin filas nuevas.
    v_res := public.fn_fdi_compra_pagar(p_id_compra => v_comp);
    SELECT count(*) INTO v_n FROM public.fdi_dat_compra_pago WHERE id_compra = v_comp;
    INSERT INTO _res VALUES (15, 'pago_reintento_duplicado', 'true / 3',
        coalesce(v_res->>'duplicada','NULL') || ' / ' || v_n::text,
        v_res->>'duplicada' = 'true' AND v_n = 3);

    -- 6) Devolver el aporte de X (con la compra ya pagada: el E2E lo pide).
    v_res := public.fn_fdi_compra_aporte_devolver(
        p_id_aporte => v_ap_x, p_motivo => 'prueba 07: retiro del inversor');
    SELECT * INTO v_aporte FROM public.fdi_dat_compra_aporte WHERE id = v_ap_x;
    INSERT INTO _res VALUES (16, 'devolucion_x', 'devuelto / 1200.00 / 800.00',
        v_aporte.estado || ' / ' || coalesce(v_res->>'aportado','?')
        || ' / ' || coalesce(v_res->>'devuelto','?'),
        v_aporte.estado = 'devuelto'
        AND (v_res->>'aportado')::numeric = 1200
        AND (v_res->>'devuelto')::numeric = 800
        AND v_aporte.devuelto_at IS NOT NULL
        AND v_aporte.motivo_devolucion IS NOT NULL);

    -- La devolución no mueve el fondo.
    SELECT COALESCE(sum(saldo), 0) INTO v_saldo_d
      FROM public.fdi_dat_saldo WHERE id_tienda = 9;
    INSERT INTO _res VALUES (17, 'devolucion_sin_movimiento', v_saldo_a::text,
        v_saldo_d::text, v_saldo_d = v_saldo_a);

    -- Idempotencia de la devolución.
    v_res := public.fn_fdi_compra_aporte_devolver(
        p_id_aporte => v_ap_x, p_motivo => 'reintento');
    INSERT INTO _res VALUES (18, 'devolucion_reintento', 'true',
        coalesce(v_res->>'duplicada','NULL'), v_res->>'duplicada' = 'true');

    -- 7) Anular con aportes vigentes → rechazo.
    BEGIN
        v_res := public.fn_fdi_compra_anular(
            p_id_compra => v_comp, p_motivo => 'prueba 07: anular');
        v_msg := 'sin error';
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    INSERT INTO _res VALUES (19, 'anular_con_aportes_rechazado', 'devuélvalos antes de anular',
        v_msg, v_msg LIKE '%devuélvalos antes de anular%');

    -- Devolver Y y Z, anular.
    PERFORM public.fn_fdi_compra_aporte_devolver(p_id_aporte => v_ap_y, p_motivo => 'prueba 07');
    PERFORM public.fn_fdi_compra_aporte_devolver(p_id_aporte => v_ap_z, p_motivo => 'prueba 07');
    v_res := public.fn_fdi_compra_anular(p_id_compra => v_comp, p_motivo => 'prueba 07: anular');
    SELECT estado INTO v_estado FROM public.fdi_dat_compra WHERE id = v_comp;
    INSERT INTO _res VALUES (20, 'anulada_sin_devolver_al_fondo', 'anulada / 0.00',
        v_estado || ' / ' || coalesce(v_res->>'devuelto','?'),
        v_estado = 'anulada' AND (v_res->>'devuelto')::numeric = 0);

    SELECT COALESCE(sum(saldo), 0) INTO v_saldo_d
      FROM public.fdi_dat_saldo WHERE id_tienda = 9;
    INSERT INTO _res VALUES (21, 'anular_sin_movimiento', v_saldo_a::text,
        v_saldo_d::text, v_saldo_d = v_saldo_a);

    -- 8) Cancelar con aportes vigentes: compra B de 500.
    v_res := public.fn_fdi_compra_crear(
        p_id_tienda        => 9,
        p_id_proveedor     => v_prov,
        p_numero_factura   => 'PRUEBA-07B',
        p_fecha_factura    => current_date,
        p_moneda_total     => 'USD',
        p_tasa_factura     => 1,
        p_lineas           => jsonb_build_array(
            jsonb_build_object('id_producto', v_prod, 'cantidad', 100,
                               'costo_unitario', 5, 'id_ubicacion', v_ubi)),
        p_ajustes          => '[]'::jsonb,
        p_modo_liquidacion => 'inversores',
        p_idempotency_key  => gen_random_uuid());
    v_comp_b := (v_res ->> 'id_compra')::bigint;

    -- 10) Interés: sólo en `pasivo`.
    BEGIN
        v_res := public.fn_fdi_compra_aporte_registrar(
            p_id_compra    => v_comp_b,
            p_id_inversor  => v_inv_x,
            p_moneda       => 'USD',
            p_monto        => 50,
            p_naturaleza   => 'anticipo',
            p_tasa_interes => 0.05,
            p_idempotency_key => gen_random_uuid());
        v_msg := 'sin error';
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    INSERT INTO _res VALUES (22, 'interes_solo_pasivo', 'devenga interés',
        v_msg, v_msg LIKE '%devenga interés%');

    v_res := public.fn_fdi_compra_aporte_registrar(
        p_id_compra    => v_comp_b,
        p_id_inversor  => v_inv_x,
        p_moneda       => 'USD',
        p_monto        => 50,
        p_naturaleza   => 'pasivo',
        p_tasa_interes => 0.05,
        p_observacion  => 'prueba 07: pasivo con interés',
        p_idempotency_key => gen_random_uuid());
    v_res := public.fn_fdi_compra_aportes(v_comp_b);
    INSERT INTO _res VALUES (23, 'interes_pasivo_estimado', 'pasivo / 2.50',
        (v_res->'aportes'->0->>'naturaleza') || ' / ' || (v_res->'aportes'->0->>'interes_estimado'),
        (v_res->'aportes'->0->>'naturaleza') = 'pasivo'
        AND (v_res->'aportes'->0->>'interes_estimado')::numeric = 2.50);

    BEGIN
        v_res := public.fn_fdi_compra_cancelar(
            p_id_compra => v_comp_b, p_motivo => 'prueba 07: cancelar');
        v_msg := 'sin error';
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    INSERT INTO _res VALUES (24, 'cancelar_con_aporte_rechazado', 'devuélvalos antes de cancelar',
        v_msg, v_msg LIKE '%devuélvalos antes de cancelar%');

    -- Escritura directa: reserva del fondo en compra de inversores.
    BEGIN
        INSERT INTO public.fdi_dat_compra_reserva (
            id_compra, id_tienda, id_cuenta, id_medio_pago, moneda,
            monto, tasa_a_total, monto_eq_total, estado)
        VALUES (v_comp_b, 9, 9, 1, 'USD', 10, 1, 10, 'activa');
        v_msg := 'sin error';
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    INSERT INTO _res VALUES (25, 'trigger_reserva_directa', 'no admite reservas del fondo',
        v_msg, v_msg LIKE '%no admite reservas del fondo%');

    -- Escritura directa: pago del fondo en compra de inversores.
    BEGIN
        INSERT INTO public.fdi_dat_compra_pago (
            id_compra, id_tienda, id_cuenta, id_medio_pago, moneda,
            monto, tasa_a_total, monto_eq_total, origen)
        VALUES (v_comp_b, 9, 9, 1, 'USD', 10, 1, 10, 'fondo');
        v_msg := 'sin error';
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    INSERT INTO _res VALUES (26, 'trigger_pago_fondo_directo', 'ningún pago sale del fondo',
        v_msg, v_msg LIKE '%ningún pago sale del fondo%');

    -- Escritura directa: cargo con origen_pago fondo en compra de inversores.
    BEGIN
        INSERT INTO public.fdi_dat_compra_ajuste (
            id_compra, id_tienda, base, valor, reparto, monto_capitalizado,
            afecta_inventario, origen_pago, estado)
        VALUES (v_comp_b, 9, 'global', 10, 'valor', 10, true, 'fondo', 'declarado');
        v_msg := 'sin error';
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    INSERT INTO _res VALUES (27, 'trigger_cargo_fondo', 'ningún cargo lo paga el fondo',
        v_msg, v_msg LIKE '%ningún cargo lo paga el fondo%');

    -- Escritura directa: cambio de modo con dinero comprometido.
    BEGIN
        UPDATE public.fdi_dat_compra SET modo_liquidacion = 'fondo' WHERE id = v_comp_b;
        v_msg := 'sin error';
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    INSERT INTO _res VALUES (28, 'modo_inmutable', 'ya tiene dinero comprometido',
        v_msg, v_msg LIKE '%ya tiene dinero comprometido%');

    -- Aporte en una compra del fondo.
    v_res := public.fn_fdi_compra_crear(
        p_id_tienda        => 9,
        p_id_proveedor     => v_prov,
        p_numero_factura   => 'PRUEBA-07F',
        p_fecha_factura    => current_date,
        p_moneda_total     => 'USD',
        p_tasa_factura     => 1,
        p_lineas           => jsonb_build_array(
            jsonb_build_object('id_producto', v_prod, 'cantidad', 10,
                               'costo_unitario', 10, 'id_ubicacion', v_ubi)),
        p_ajustes          => '[]'::jsonb,
        p_modo_liquidacion => 'fondo',
        p_idempotency_key  => gen_random_uuid());
    v_comp_f := (v_res ->> 'id_compra')::bigint;

    BEGIN
        INSERT INTO public.fdi_dat_compra_aporte (
            id_compra, id_tienda, id_inversor, naturaleza, moneda, monto, tasa_a_total)
        VALUES (v_comp_f, 9, v_inv_x, 'anticipo', 'USD', 10, 1);
        v_msg := 'sin error';
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    INSERT INTO _res VALUES (29, 'trigger_aporte_en_fondo', 'no admite aportes de inversores',
        v_msg, v_msg LIKE '%no admite aportes de inversores%');

    -- El resumen de la compra B sigue coherente tras los intentos fallidos.
    v_res := public.fn_fdi_compra_aportes(v_comp_b);
    INSERT INTO _res VALUES (30, 'resumen_coherente', '500.00 / 450.00 / 50.00',
        (v_res->>'total') || ' / ' || (v_res->>'aportado') || ' / ' || (v_res->>'faltante'),
        (v_res->>'total')::numeric = 500
        AND (v_res->>'aportado')::numeric = 50
        AND (v_res->>'faltante')::numeric = 450
        AND jsonb_array_length(v_res->'aportes') = 1);

    -- ======================================================================
    -- 11) Defensas de la revisión adversarial
    -- ======================================================================

    -- 31) Compra de inversores sin total a financiar: no se puede pagar.
    v_res := public.fn_fdi_compra_crear(
        p_id_tienda        => 9,
        p_id_proveedor     => v_prov,
        p_numero_factura   => 'PRUEBA-07D',
        p_fecha_factura    => current_date,
        p_moneda_total     => 'USD',
        p_tasa_factura     => 1,
        p_lineas           => jsonb_build_array(
            jsonb_build_object('id_producto', v_prod, 'cantidad', 10,
                               'costo_unitario', 0, 'id_ubicacion', v_ubi)),
        p_ajustes          => '[]'::jsonb,
        p_modo_liquidacion => 'inversores',
        p_idempotency_key  => gen_random_uuid());
    v_comp_d := (v_res ->> 'id_compra')::bigint;
    BEGIN
        v_res := public.fn_fdi_compra_pagar(p_id_compra => v_comp_d);
        v_msg := 'sin error';
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    INSERT INTO _res VALUES (31, 'pagar_total_cero_rechazado', 'no tiene total a financiar',
        v_msg, v_msg LIKE '%no tiene total a financiar%');

    -- 32) El ajuste tardío de una compra de inversores se registra sin fondo.
    SELECT id INTO v_ap_b FROM public.fdi_dat_compra_aporte WHERE id_compra = v_comp_b;
    UPDATE public.fdi_dat_compra SET estado = 'completada' WHERE id = v_comp_b;

    v_res := public.fn_fdi_compra_ajuste_agregar(
        p_id_compra      => v_comp_b,
        p_id_tipo_costo  => v_tipo_fle,
        p_base           => 'global',
        p_valor          => 100,
        p_reparto        => 'cantidad',
        p_afecta_inventario => true,
        p_idempotency_key => gen_random_uuid());
    SELECT * INTO v_ajuste FROM public.fdi_dat_compra_ajuste
     WHERE id_compra = v_comp_b AND origen_pago <> 'fondo' ORDER BY id DESC LIMIT 1;
    SELECT total_financiado INTO v_total FROM public.fdi_dat_compra WHERE id = v_comp_b;
    INSERT INTO _res VALUES (32, 'ajuste_tardio_inversores', 'externo / declarado / 100.00 / total 500.00',
        v_ajuste.origen_pago || ' / ' || v_ajuste.estado || ' / '
        || v_ajuste.monto_capitalizado::text || ' / total ' || v_total::text,
        v_ajuste.origen_pago = 'externo'
        AND v_ajuste.estado = 'declarado'
        AND v_ajuste.monto_capitalizado = 100
        AND v_total = 500);

    -- 33) Con la mercancía recibida no se devuelven aportes.
    BEGIN
        v_res := public.fn_fdi_compra_aporte_devolver(
            p_id_aporte => v_ap_b, p_motivo => 'prueba 07: con la compra recibida');
        v_msg := 'sin error';
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    INSERT INTO _res VALUES (33, 'devolver_en_completada_rechazado', 'sólo creada o pagada',
        v_msg, v_msg LIKE '%sólo creada o pagada%');

    -- 34) Convertir un pago de aporte en pago del fondo (crearía dinero).
    BEGIN
        UPDATE public.fdi_dat_compra_pago
           SET origen = 'fondo', id_cuenta = 9, id_medio_pago = 1, id_aporte = NULL
         WHERE id = (SELECT min(p.id) FROM public.fdi_dat_compra_pago p
                      WHERE p.id_compra = v_comp AND p.origen = 'aporte');
        v_msg := 'sin error';
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    INSERT INTO _res VALUES (34, 'pago_aporte_a_fondo_rechazado', 'ningún pago sale del fondo',
        v_msg, v_msg LIKE '%ningún pago sale del fondo%');

    -- 35) El importe de un aporte registrado no se reescribe.
    BEGIN
        UPDATE public.fdi_dat_compra_aporte SET monto = 999 WHERE id = v_ap_x;
        v_msg := 'sin error';
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    INSERT INTO _res VALUES (35, 'aporte_monto_inmutable', 'es inmutable',
        v_msg, v_msg LIKE '%es inmutable%');

    -- 36) Un aporte devuelto no resucita.
    BEGIN
        UPDATE public.fdi_dat_compra_aporte
           SET estado = 'aportado', devuelto_at = NULL, motivo_devolucion = NULL,
               updated_at = now()
         WHERE id = v_ap_x;
        v_msg := 'sin error';
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    INSERT INTO _res VALUES (36, 'aporte_devuelto_no_resucita', 'no se reactiva',
        v_msg, v_msg LIKE '%no se reactiva%');

    -- 37) Un aporte no se borra.
    BEGIN
        DELETE FROM public.fdi_dat_compra_aporte WHERE id = v_ap_x;
        v_msg := 'sin error';
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    INSERT INTO _res VALUES (37, 'aporte_no_se_borra', 'devuélvalo',
        v_msg, v_msg LIKE '%no se borra%');

    -- 38) `total_financiado` está congelado fuera de `creada`.
    BEGIN
        UPDATE public.fdi_dat_compra SET total_financiado = 1 WHERE id = v_comp;
        v_msg := 'sin error';
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    INSERT INTO _res VALUES (38, 'total_financiado_congelado', 'está congelado',
        v_msg, v_msg LIKE '%congelado%');

    -- 39) Moneda distinta sin tasa declarada: se rechaza (no se asume 1:1).
    v_res := public.fn_fdi_compra_crear(
        p_id_tienda        => 9,
        p_id_proveedor     => v_prov,
        p_numero_factura   => 'PRUEBA-07E',
        p_fecha_factura    => current_date,
        p_moneda_total     => 'USD',
        p_tasa_factura     => 1,
        p_lineas           => jsonb_build_array(
            jsonb_build_object('id_producto', v_prod, 'cantidad', 10,
                               'costo_unitario', 10, 'id_ubicacion', v_ubi)),
        p_ajustes          => '[]'::jsonb,
        p_modo_liquidacion => 'inversores',
        p_idempotency_key  => gen_random_uuid());
    v_comp_e := (v_res ->> 'id_compra')::bigint;
    BEGIN
        v_res := public.fn_fdi_compra_aporte_registrar(
            p_id_compra   => v_comp_e,
            p_id_inversor => v_inv_x,
            p_moneda      => 'CUP',
            p_monto       => 1000,
            p_idempotency_key => gen_random_uuid());
        v_msg := 'sin error';
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    INSERT INTO _res VALUES (39, 'tasa_obligatoria_si_moneda_distinta', 'Indique la tasa',
        v_msg, v_msg LIKE '%Indique la tasa%');

    -- 40) Cubierto el 100 %, ya no se puede registrar otro aporte.
    v_res := public.fn_fdi_compra_aporte_registrar(
        p_id_compra   => v_comp_e,
        p_id_inversor => v_inv_x,
        p_moneda      => 'USD',
        p_monto       => 100,
        p_idempotency_key => gen_random_uuid());
    v_ap_e := (v_res ->> 'id')::bigint;
    v_res := public.fn_fdi_compra_aportes(v_comp_e);
    INSERT INTO _res VALUES (40, 'puede_registrar_false_al_cubrir', 'false / true / false',
        (v_res->>'puede_registrar') || ' / ' || (v_res->>'puede_pagar')
        || ' / ' || (v_res->>'puede_devolver'),
        (v_res->>'puede_registrar') = 'false'
        AND (v_res->>'puede_pagar') = 'true'
        AND (v_res->>'puede_devolver') = 'true');

    -- 41) Un pago no puede apuntar al aporte de otra compra.
    BEGIN
        INSERT INTO public.fdi_dat_compra_pago (
            id_compra, id_tienda, moneda, monto, tasa_a_total, monto_eq_total,
            origen, id_aporte)
        VALUES (v_comp_b, 9, 'USD', 100, 1, 100, 'aporte', v_ap_e);
        v_msg := 'sin error';
        v_sqlstate := '00000';
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
        GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE;
    END;
    INSERT INTO _res VALUES (41, 'pago_aporte_de_otra_compra_rechazado', '23503',
        v_sqlstate, v_sqlstate = '23503');

    -- 42) Los aportes de la compra A siguen intactos tras todos los intentos.
    SELECT count(*) FILTER (WHERE estado = 'devuelto'), count(*)
      INTO v_n, v_n2
      FROM public.fdi_dat_compra_aporte WHERE id_compra = v_comp;
    INSERT INTO _res VALUES (42, 'aportes_intactos', '3 devueltos de 3',
        v_n || ' de ' || v_n2, v_n = 3 AND v_n2 = 3);
END;
$$;

SELECT n, chequeo, esperado, actual, ok FROM _res
UNION ALL
SELECT 99, 'RESUMEN', '0 fallos',
       (SELECT count(*)::text FROM _res WHERE NOT ok) || ' fallo(s) de '
         || (SELECT count(*)::text FROM _res) || ' comprobaciones',
       (SELECT count(*) = 0 FROM _res WHERE NOT ok)
ORDER BY n;

ROLLBACK;