-- ============================================================================
-- verify/06c_pruebas_aterrizaje.sql — pruebas de DINERO del costo aterrizado
--
-- REQUIERE: 06a, 06b y 06c aplicados en `newa`.
--
-- Qué es: las cifras de salida de la fase 6 del plan, comprobadas de verdad.
-- El script crea sus propias compras, recepciones y vínculos y **termina en
-- ROLLBACK**: no deja una sola fila. Devuelve una fila por comprobación con
-- `ok` / `falla` y un resumen `n = 99`, como el resto de `verify/`.
--
-- Comprobaciones:
--   1. Compra de 2.000 (2 líneas de 50 u a 20) con ajuste Importadora 15 %;
--      recepción completa y vínculo con 15 % y reembolso de la mitad.
--      Cargo = 150 y el reparto escribe 1 fila por línea que suma 150.
--   2. Resumen de la compra: valor vinculado 2.000, cargo 150, % efectivo 7,5,
--      % declarado 15, cargo esperado 300, desvío −150 y aterrizado **2.150**.
--   3. El cargo de la wallet no genera ningún movimiento del fondo.
--   4. Costo aterrizado por línea = 20 + 75/50 = **21,50** en las dos líneas.
--   5. Ajuste global (flete 100.000 con 100 u pedidas y 60 recibidas):
--      se aplican **60.000** y quedan **40.000 por asignar**.
--   6. El reparto es idempotente: repetirlo deja 2 filas y 150, no 4.
--
-- No valida la UI ni el promedio (`_v2`), que necesitan stock y operación
-- completada; eso es el E2E del dueño.
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
    v_tipo_imp bigint;
    v_tipo_fle bigint;
    v_compa    bigint;
    v_compb    bigint;
    v_op_a     bigint;
    v_op_b     bigint;
    v_link_a   bigint;
    v_link_b   bigint;
    v_res      jsonb;
    v_lineas   jsonb;
    v_suma     numeric;
    v_filas    integer;
    v_aterr    numeric;
    v_otra     numeric;
BEGIN
    SELECT id INTO v_prov FROM public.app_dat_proveedor
     WHERE idtienda = 9 ORDER BY id LIMIT 1;
    SELECT id INTO v_prod FROM public.app_dat_producto
     WHERE id_tienda = 9 ORDER BY id LIMIT 1;
    SELECT l.id INTO v_ubi
      FROM public.app_dat_layout_almacen l
      JOIN public.app_dat_almacen a ON a.id = l.id_almacen
     WHERE a.id_tienda = 9 ORDER BY l.id LIMIT 1;
    SELECT id INTO v_tipo_imp FROM public.app_cont_tipo_costo
     WHERE lower(btrim(denominacion)) = 'importadora' LIMIT 1;
    SELECT id INTO v_tipo_fle FROM public.app_cont_tipo_costo
     WHERE lower(btrim(denominacion)) = 'flete' LIMIT 1;

    IF v_prov IS NULL OR v_prod IS NULL OR v_ubi IS NULL
       OR v_tipo_imp IS NULL OR v_tipo_fle IS NULL THEN
        INSERT INTO _res VALUES (0, 'fixtures',
            'proveedor, producto y ubicación de la tienda 9; tipos Importadora y Flete',
            format('prov=%s prod=%s ubi=%s imp=%s fle=%s', v_prov, v_prod, v_ubi, v_tipo_imp, v_tipo_fle),
            false);
        RETURN;
    END IF;

    -- ── Compra A: 2.000 de mercancía, Importadora 15 % ─────────────────────
    v_res := public.fn_fdi_compra_crear(
        p_id_tienda      => 9,
        p_id_proveedor   => v_prov,
        p_numero_factura => 'PRUEBA-06C-A',
        p_fecha_factura  => current_date,
        p_moneda_total   => 'USD',
        p_tasa_factura   => 1,
        p_lineas         => jsonb_build_array(
            jsonb_build_object('id_producto', v_prod, 'cantidad', 50, 'costo_unitario', 20, 'id_ubicacion', v_ubi),
            jsonb_build_object('id_producto', v_prod, 'cantidad', 50, 'costo_unitario', 20, 'id_ubicacion', v_ubi)),
        p_ajustes        => jsonb_build_array(
            jsonb_build_object('id_tipo_costo', v_tipo_imp, 'base', 'porcentaje',
                               'valor', 15, 'reparto', 'valor', 'origen_pago', 'wallet_importadora')),
        p_idempotency_key => gen_random_uuid());
    v_compa := (v_res ->> 'id_compra')::bigint;
    UPDATE public.fdi_dat_compra SET estado = 'pagada' WHERE id = v_compa;

    -- Recepción completa de las 100 unidades (50 + 50) a 20.
    v_res := public.fn_fdi_recepcion_con_costos(
        jsonb_build_object(
            'p_id_tienda', 9, 'p_monto_total', 2000, 'p_motivo', 1,
            'p_observaciones', 'prueba 06c · compra A',
            'p_productos', jsonb_build_array(
                jsonb_build_object('id_producto', v_prod, 'cantidad', 50, 'precio_unitario', 20, 'id_ubicacion', v_ubi),
                jsonb_build_object('id_producto', v_prod, 'cantidad', 50, 'precio_unitario', 20, 'id_ubicacion', v_ubi)),
            'p_recibido_por', '', 'p_entregado_por', '', 'p_moneda_factura', 'USD'),
        '[]'::jsonb, '[]'::jsonb, gen_random_uuid());
    v_op_a := (v_res ->> 'id_operacion')::bigint;

    SELECT jsonb_agg(jsonb_build_object('id_compra_linea', l.id, 'cantidad_recibida', l.cantidad))
      INTO v_lineas
      FROM public.fdi_dat_compra_linea l WHERE l.id_compra = v_compa;

    -- 15 % de 2.000 = 300; reembolso de la mitad = 150 de cargo efectivo.
    v_res := public.fn_fdi_compra_vincular_recepcion(
        p_id_operacion => v_op_a, p_id_compra => v_compa,
        p_lineas => v_lineas, p_confirmar_exceso => false,
        p_pct_importadora => 15, p_base_importadora => 2000,
        p_reembolso_importadora => 150, p_origen_pago => 'wallet_importadora');
    v_link_a := (v_res ->> 'id_compra_recepcion')::bigint;
    INSERT INTO _res VALUES (1, 'cargo_del_vinculo', '150.00',
        (v_res ->> 'cargo_importadora'), (v_res ->> 'cargo_importadora')::numeric = 150);

    -- ── Reparto ───────────────────────────────────────────────────────────
    v_res := public.fn_fdi_compra_repartir_aterrizaje(v_link_a);
    SELECT count(*), COALESCE(sum(monto_usd), 0)
      INTO v_filas, v_suma
      FROM public.app_dat_recepcion_producto_costo
     WHERE id_compra_recepcion = v_link_a;
    INSERT INTO _res VALUES (2, 'reparto_filas_y_suma', '2 filas / 150.00',
        format('%s filas / %s', v_filas, v_suma),
        v_filas = 2 AND abs(v_suma - 150) < 0.005);
    INSERT INTO _res VALUES (3, 'reparto_status', 'ok', COALESCE(v_res ->> 'status', 'NULL'),
        COALESCE(v_res ->> 'status', '') = 'ok');

    -- ── Resumen de la compra ──────────────────────────────────────────────
    v_res := public.fn_fdi_compra_costo_resumen(v_compa);
    INSERT INTO _res VALUES (4, 'resumen_valor_y_cargo', '2000.00 / 150.00',
        format('%s / %s', v_res ->> 'valor_vinculado', v_res ->> 'cargo_importadora'),
        (v_res ->> 'valor_vinculado')::numeric = 2000
        AND (v_res ->> 'cargo_importadora')::numeric = 150);
    INSERT INTO _res VALUES (5, 'resumen_pct_efectivo', '7.5000',
        COALESCE(v_res ->> 'pct_importadora_efectivo', 'NULL'),
        (v_res ->> 'pct_importadora_efectivo')::numeric = 7.5);
    INSERT INTO _res VALUES (6, 'resumen_pct_declarado', '15',
        COALESCE(v_res ->> 'pct_importadora_declarado', 'NULL'),
        (v_res ->> 'pct_importadora_declarado')::numeric = 15);
    INSERT INTO _res VALUES (7, 'resumen_cargo_esperado', '300.00',
        COALESCE(v_res ->> 'cargo_esperado', 'NULL'),
        (v_res ->> 'cargo_esperado')::numeric = 300);
    INSERT INTO _res VALUES (8, 'resumen_desvio', '-150.00',
        COALESCE(v_res ->> 'desvio_importadora', 'NULL'),
        (v_res ->> 'desvio_importadora')::numeric = -150);
    INSERT INTO _res VALUES (9, 'resumen_aterrizado', '2150.00',
        COALESCE(v_res ->> 'total_aterrizado', 'NULL'),
        (v_res ->> 'total_aterrizado')::numeric = 2150);
    INSERT INTO _res VALUES (10, 'resumen_ajustes_globales_cero', '0',
        COALESCE(v_res ->> 'ajustes_globales', 'NULL'),
        (v_res ->> 'ajustes_globales')::numeric = 0);

    -- Costo aterrizado por línea: 20 + 75/50 = 21,50.
    SELECT max((x ->> 'costo_aterrizado_unit')::numeric),
           min((x ->> 'costo_aterrizado_unit')::numeric)
      INTO v_aterr, v_otra
      FROM jsonb_array_elements(v_res -> 'lineas') x;
    INSERT INTO _res VALUES (11, 'costo_aterrizado_unit_linea', '21.5000 en las 2 líneas',
        format('max=%s min=%s', v_aterr, v_otra),
        v_aterr = 21.5 AND v_otra = 21.5);
    INSERT INTO _res VALUES (12, 'lineas_del_resumen', '2',
        jsonb_array_length(v_res -> 'lineas')::text,
        jsonb_array_length(v_res -> 'lineas') = 2);

    -- El cargo de la wallet no mueve el fondo.
    INSERT INTO _res VALUES (13, 'fondo_no_paga_el_cargo', '0 movimientos',
        (SELECT count(*)::text FROM public.fdi_dat_movimiento WHERE id_compra = v_compa),
        (SELECT count(*) FROM public.fdi_dat_movimiento WHERE id_compra = v_compa) = 0);

    -- Idempotencia del reparto.
    PERFORM public.fn_fdi_compra_repartir_aterrizaje(v_link_a);
    SELECT count(*), COALESCE(sum(monto_usd), 0)
      INTO v_filas, v_suma
      FROM public.app_dat_recepcion_producto_costo
     WHERE id_compra_recepcion = v_link_a;
    INSERT INTO _res VALUES (14, 'reparto_idempotente', '2 filas / 150.00',
        format('%s filas / %s', v_filas, v_suma),
        v_filas = 2 AND abs(v_suma - 150) < 0.005);

    -- ── Compra B: flete global 100.000 con 100 u pedidas y 60 recibidas ───
    v_res := public.fn_fdi_compra_crear(
        p_id_tienda      => 9,
        p_id_proveedor   => v_prov,
        p_numero_factura => 'PRUEBA-06C-B',
        p_fecha_factura  => current_date,
        p_moneda_total   => 'USD',
        p_tasa_factura   => 1,
        p_lineas         => jsonb_build_array(
            jsonb_build_object('id_producto', v_prod, 'cantidad', 100, 'costo_unitario', 10, 'id_ubicacion', v_ubi)),
        p_ajustes        => jsonb_build_array(
            jsonb_build_object('id_tipo_costo', v_tipo_fle, 'base', 'global',
                               'valor', 100000, 'reparto', 'cantidad', 'origen_pago', 'fondo')),
        p_idempotency_key => gen_random_uuid());
    v_compb := (v_res ->> 'id_compra')::bigint;
    UPDATE public.fdi_dat_compra SET estado = 'pagada' WHERE id = v_compb;

    -- Recepción parcial: 60 de 100 unidades.
    v_res := public.fn_fdi_recepcion_con_costos(
        jsonb_build_object(
            'p_id_tienda', 9, 'p_monto_total', 600, 'p_motivo', 1,
            'p_observaciones', 'prueba 06c · compra B',
            'p_productos', jsonb_build_array(
                jsonb_build_object('id_producto', v_prod, 'cantidad', 60, 'precio_unitario', 10, 'id_ubicacion', v_ubi)),
            'p_recibido_por', '', 'p_entregado_por', '', 'p_moneda_factura', 'USD'),
        '[]'::jsonb, '[]'::jsonb, gen_random_uuid());
    v_op_b := (v_res ->> 'id_operacion')::bigint;

    SELECT jsonb_agg(jsonb_build_object('id_compra_linea', l.id, 'cantidad_recibida', 60))
      INTO v_lineas
      FROM public.fdi_dat_compra_linea l WHERE l.id_compra = v_compb;

    v_res := public.fn_fdi_compra_vincular_recepcion(
        p_id_operacion => v_op_b, p_id_compra => v_compb,
        p_lineas => v_lineas, p_confirmar_exceso => false,
        p_pct_importadora => 0, p_base_importadora => 600,
        p_reembolso_importadora => 0, p_origen_pago => 'wallet_importadora');
    v_link_b := (v_res ->> 'id_compra_recepcion')::bigint;

    v_res := public.fn_fdi_compra_costo_resumen(v_compb);
    INSERT INTO _res VALUES (15, 'flete_avance', '100 pedidas / 60 recibidas / 0.600000',
        format('%s / %s / %s', v_res ->> 'pedido_cantidad', v_res ->> 'recibido_cantidad', v_res ->> 'pct_recibido'),
        (v_res ->> 'pedido_cantidad')::numeric = 100
        AND (v_res ->> 'recibido_cantidad')::numeric = 60
        AND (v_res ->> 'pct_recibido')::numeric = 0.6);
    INSERT INTO _res VALUES (16, 'flete_aplicado', '60000.00',
        COALESCE(v_res ->> 'ajustes_aplicados', 'NULL'),
        (v_res ->> 'ajustes_aplicados')::numeric = 60000);
    INSERT INTO _res VALUES (17, 'flete_por_asignar', '40000.00',
        COALESCE(v_res ->> 'ajustes_por_asignar', 'NULL'),
        (v_res ->> 'ajustes_por_asignar')::numeric = 40000);
    INSERT INTO _res VALUES (18, 'flete_total_aterrizado', '60600.00',
        COALESCE(v_res ->> 'total_aterrizado', 'NULL'),
        (v_res ->> 'total_aterrizado')::numeric = 60600);
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