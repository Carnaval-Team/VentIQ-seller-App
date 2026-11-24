-- ============================================================================
-- verify/06d_pruebas_ajuste.sql — pruebas de DINERO del ajuste tardío
--
-- REQUIERE: 06a, 06b, 06c y 06d aplicados en `newa`.
--
-- Qué prueba: un costo que llega **después de pagar** la compra (flete global
-- de 100 sobre una compra de 1.000 ya completada):
--   1. el ajuste nace `por_financiar` y **no** mueve `total_financiado`;
--   2. al financiarlo, el fondo paga el importe con su propia reserva y pago;
--   3. el costo se reparte sobre lo recibido y el costo unitario del producto
--      sube monto/unidades (100 / 100 = 1);
--   4. el reintento no vuelve a pagar (`duplicada: true`).
-- Termina en ROLLBACK: no deja datos.
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
    v_prov     bigint;
    v_prod     bigint;
    v_ubi      bigint;
    v_tipo_fle bigint;
    v_comp     bigint;
    v_op       bigint;
    v_link     bigint;
    v_aj       bigint;
    v_res      jsonb;
    v_lineas   jsonb;
    v_ajuste   jsonb;
    v_estado_aj text;
    v_aj_monto numeric;
    v_compra   record;
    v_saldo_a  numeric;
    v_saldo_d  numeric;
    v_pp_antes numeric;
    v_pp_desp  numeric;
    v_base_pp  bigint;
    v_n        integer;
    v_filas    integer;
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
            format('prov=%s prod=%s ubi=%s flete=%s', v_prov, v_prod, v_ubi, v_tipo_fle),
            false);
        RETURN;
    END IF;

    -- Compra de 1.000 (100 u a 10), sin ajustes.
    v_res := public.fn_fdi_compra_crear(
        p_id_tienda      => 9,
        p_id_proveedor   => v_prov,
        p_numero_factura => 'PRUEBA-06D',
        p_fecha_factura  => current_date,
        p_moneda_total   => 'USD',
        p_tasa_factura   => 1,
        p_lineas         => jsonb_build_array(
            jsonb_build_object('id_producto', v_prod, 'cantidad', 100,
                               'costo_unitario', 10, 'id_ubicacion', v_ubi)),
        p_ajustes        => '[]'::jsonb,
        p_idempotency_key => gen_random_uuid());
    v_comp := (v_res ->> 'id_compra')::bigint;
    UPDATE public.fdi_dat_compra SET estado = 'pagada' WHERE id = v_comp;

    -- Recepción completa (100 u) y vínculo sin cargo.
    v_res := public.fn_fdi_recepcion_con_costos(
        jsonb_build_object(
            'p_id_tienda', 9, 'p_monto_total', 1000, 'p_motivo', 1,
            'p_observaciones', 'prueba 06d',
            'p_productos', jsonb_build_array(
                jsonb_build_object('id_producto', v_prod, 'cantidad', 100,
                                   'precio_unitario', 10, 'id_ubicacion', v_ubi)),
            'p_recibido_por', '', 'p_entregado_por', '', 'p_moneda_factura', 'USD'),
        '[]'::jsonb, '[]'::jsonb, gen_random_uuid());
    v_op := (v_res ->> 'id_operacion')::bigint;

    SELECT jsonb_agg(jsonb_build_object('id_compra_linea', l.id, 'cantidad_recibida', 100))
      INTO v_lineas
      FROM public.fdi_dat_compra_linea l WHERE l.id_compra = v_comp;

    v_res := public.fn_fdi_compra_vincular_recepcion(
        p_id_operacion => v_op, p_id_compra => v_comp,
        p_lineas => v_lineas, p_confirmar_exceso => false,
        p_pct_importadora => 0, p_base_importadora => 1000,
        p_reembolso_importadora => 0, p_origen_pago => 'wallet_importadora');
    v_link := (v_res ->> 'id_compra_recepcion')::bigint;

    SELECT * INTO v_compra FROM public.fdi_dat_compra WHERE id = v_comp;
    INSERT INTO _res VALUES (1, 'compra_completada', 'completada',
        v_compra.estado, v_compra.estado = 'completada');

    -- Ajuste tardío: flete global 100.
    v_res := public.fn_fdi_compra_ajuste_agregar(
        p_id_compra      => v_comp,
        p_id_tipo_costo  => v_tipo_fle,
        p_base           => 'global',
        p_valor          => 100,
        p_reparto        => 'cantidad',
        p_afecta_inventario => true,
        p_idempotency_key => gen_random_uuid());
    v_aj := (v_res ->> 'id_ajuste')::bigint;

    SELECT estado, monto_capitalizado INTO v_estado_aj, v_aj_monto
      FROM public.fdi_dat_compra_ajuste WHERE id = v_aj;
    INSERT INTO _res VALUES (2, 'ajuste_por_financiar', 'por_financiar / 100.00',
        v_estado_aj || ' / ' || v_aj_monto::text,
        v_estado_aj = 'por_financiar' AND v_aj_monto = 100);

    SELECT total_financiado, total_ajustes, costo_aterrizado
      INTO v_compra FROM public.fdi_dat_compra WHERE id = v_comp;
    INSERT INTO _res VALUES (3, 'total_financiado_inmutable', '1000.00',
        v_compra.total_financiado::text,
        v_compra.total_financiado = 1000);
    INSERT INTO _res VALUES (4, 'costo_aterrizado_crece', '1100.00',
        v_compra.costo_aterrizado::text,
        v_compra.costo_aterrizado = 1100);

    -- Saldo y costo del producto antes de financiar.
    SELECT saldo INTO v_saldo_a FROM public.fdi_dat_saldo
     WHERE id_cuenta = 9 AND id_medio_pago = 1 AND moneda = 'USD';
    SELECT id, COALESCE(precio_promedio, 0) INTO v_base_pp, v_pp_antes
      FROM public.fn_presentaciones_producto(v_prod) f
      JOIN public.app_dat_producto_presentacion pp ON pp.id = f.id_presentacion
     WHERE f.es_base LIMIT 1;
    IF v_base_pp IS NULL THEN
        INSERT INTO _res VALUES (5, 'presentacion_base', 'existe', 'no', false);
        RETURN;
    END IF;

    -- Financiar con una fuente del fondo (USD, tasa 1).
    v_res := public.fn_fdi_compra_ajuste_financiar(
        p_id_ajuste => v_aj,
        p_fuentes => jsonb_build_array(jsonb_build_object(
            'id_cuenta', 9, 'id_medio_pago', 1, 'moneda', 'USD',
            'monto', 100, 'tasa', 1)),
        p_idempotency_key => gen_random_uuid());

    INSERT INTO _res VALUES (5, 'financiado', 'ok / 100.00',
        coalesce(v_res->>'status', '?') || ' / ' || coalesce(v_res->>'financiado', '?'),
        coalesce(v_res->>'status', '') = 'ok'
        AND (v_res->>'financiado')::numeric = 100);

    SELECT estado INTO v_estado_aj FROM public.fdi_dat_compra_ajuste WHERE id = v_aj;
    INSERT INTO _res VALUES (6, 'ajuste_financiado', 'financiado',
        v_estado_aj, v_estado_aj = 'financiado');

    SELECT saldo INTO v_saldo_d FROM public.fdi_dat_saldo
     WHERE id_cuenta = 9 AND id_medio_pago = 1 AND moneda = 'USD';
    INSERT INTO _res VALUES (7, 'saldo_descontado', (v_saldo_a - 100)::text,
        v_saldo_d::text, v_saldo_d = v_saldo_a - 100);

    SELECT count(*) INTO v_n FROM public.fdi_dat_movimiento
     WHERE id_compra = v_comp AND tipo = 'pago_compra' AND monto = -100;
    INSERT INTO _res VALUES (8, 'movimiento_pago', '1', v_n::text, v_n = 1);

    SELECT count(*) INTO v_n FROM public.fdi_dat_compra_reserva
     WHERE id_ajuste = v_aj AND estado = 'consumida';
    INSERT INTO _res VALUES (9, 'reserva_propia', '1 consumida', v_n::text, v_n = 1);

    SELECT count(*) INTO v_n FROM public.fdi_dat_compra_pago
     WHERE id_ajuste = v_aj;
    INSERT INTO _res VALUES (10, 'pago_propio', '1', v_n::text, v_n = 1);

    SELECT count(*), coalesce(sum(monto_usd), 0) INTO v_filas, v_pp_desp
      FROM public.app_dat_recepcion_producto_costo WHERE id_ajuste = v_aj;
    INSERT INTO _res VALUES (11, 'costo_repartido', '1 fila / 100.00',
        v_filas || ' / ' || v_pp_desp,
        v_filas = 1 AND v_pp_desp = 100);

    SELECT precio_promedio INTO v_pp_desp
      FROM public.app_dat_producto_presentacion WHERE id = v_base_pp;
    INSERT INTO _res VALUES (12, 'precio_promedio_sube', (v_pp_antes + 1)::text,
        v_pp_desp::text, abs(v_pp_desp - (v_pp_antes + 1)) < 0.0001);

    -- Reintento: no vuelve a pagar.
    v_res := public.fn_fdi_compra_ajuste_financiar(
        p_id_ajuste => v_aj,
        p_fuentes => jsonb_build_array(jsonb_build_object(
            'id_cuenta', 9, 'id_medio_pago', 1, 'moneda', 'USD',
            'monto', 100, 'tasa', 1)),
        p_idempotency_key => gen_random_uuid());
    SELECT count(*) INTO v_n FROM public.fdi_dat_movimiento
     WHERE id_compra = v_comp AND tipo = 'pago_compra';
    INSERT INTO _res VALUES (13, 'reintento_duplicada', 'true / 1 movimiento',
        coalesce(v_res->>'duplicada', 'NULL') || ' / ' || v_n::text,
        v_res->>'duplicada' = 'true' AND v_n = 1);

    SELECT count(*) INTO v_n FROM public.app_dat_recepcion_producto_costo
     WHERE id_ajuste = v_aj;
    INSERT INTO _res VALUES (14, 'reintento_sin_filas_nuevas', '1', v_n::text, v_n = 1);
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