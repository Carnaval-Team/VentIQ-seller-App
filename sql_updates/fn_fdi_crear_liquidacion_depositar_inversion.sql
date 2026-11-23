CREATE OR REPLACE FUNCTION public.fn_fdi_crear_liquidacion(
    p_id_tienda            bigint,
    p_desde                date,
    p_hasta                date,
    p_modo                 text,
    p_id_cuenta_destino    bigint,
    p_detalle              jsonb,
    p_tasa_validacion      numeric DEFAULT NULL,
    p_confirmar_diferencia boolean DEFAULT false,
    p_observacion          text   DEFAULT NULL,
    p_idempotency_key      uuid   DEFAULT NULL,
    p_repartir_igual       boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_existente        bigint;
    v_id_liquidacion   bigint;
    v_cuenta           record;
    v_id_tienda_cuenta bigint;
    v_id_tipo_venta    bigint;
    v_modo             text := lower(coalesce(nullif(trim(p_modo), ''), 'creacion'));
    v_tasa_fallback    numeric;
    v_venta_total      numeric;
    v_costo_total      numeric;
    v_ganancia         numeric;
    v_cant_ordenes     integer;
    v_equiv_retirada   numeric := 0;
    v_diferencia       numeric;
    v_det              jsonb;
    v_id_medio         smallint;
    v_moneda           text;
    v_retirada         numeric;
    v_vendido          numeric;
    v_inversion        numeric;
    v_depositar        boolean;
    v_id_detalle       bigint;
BEGIN
    IF NOT public.fn_user_is_gerente_or_superadmin(p_id_tienda) THEN
        RAISE EXCEPTION 'Solo gerente o superadmin puede liquidar' USING ERRCODE = '42501';
    END IF;

    -- Idempotencia: misma clave → misma liquidación.
    IF p_idempotency_key IS NOT NULL THEN
        SELECT id INTO v_existente
        FROM public.fdi_dat_liquidacion
        WHERE idempotency_key = p_idempotency_key;
        IF v_existente IS NOT NULL THEN
            RETURN jsonb_build_object('status', 'ok', 'id_liquidacion', v_existente, 'duplicada', true);
        END IF;
    END IF;

    SELECT c.id_tienda INTO v_id_tienda_cuenta
    FROM public.fdi_dat_cuenta c WHERE c.id = p_id_cuenta_destino AND c.activo;
    IF v_id_tienda_cuenta IS NULL OR v_id_tienda_cuenta <> p_id_tienda THEN
        RAISE EXCEPTION 'La cuenta destino % no existe o no es de la tienda %',
            p_id_cuenta_destino, p_id_tienda USING ERRCODE = 'P0002';
    END IF;

    SELECT tc.tasa INTO v_tasa_fallback
    FROM public.tasas_conversion tc
    WHERE tc.moneda_origen = 'USD' AND tc.moneda_destino = 'CUP'
    ORDER BY tc.fecha_actualizacion DESC LIMIT 1;

    -- Recalcular en servidor: pagos y totales solo de órdenes elegibles.
    CREATE TEMP TABLE _fdi_elig ON COMMIT DROP AS
    SELECT * FROM public._fdi_ops_elegibles(p_id_tienda, p_desde, p_hasta, v_modo);

    SELECT count(*) INTO v_cant_ordenes FROM _fdi_elig;
    IF v_cant_ordenes = 0 THEN
        RAISE EXCEPTION 'No hay órdenes elegibles para liquidar en el periodo'
            USING ERRCODE = 'P0002';
    END IF;

    CREATE TEMP TABLE _fdi_pagos ON COMMIT DROP AS
    SELECT pv.id_medio_pago,
           COALESCE(NULLIF(TRIM(pv.moneda), ''), 'CUP') AS moneda,
           SUM(pv.monto) AS monto_vendido,
           SUM(COALESCE(pv.monto_cup_equivalente, pv.monto)) AS monto_cup
    FROM _fdi_elig e
    JOIN public.app_dat_pago_venta pv ON pv.id_operacion_venta = e.id
    GROUP BY pv.id_medio_pago, COALESCE(NULLIF(TRIM(pv.moneda), ''), 'CUP');

    SELECT COALESCE(sum(monto_cup), 0) INTO v_venta_total FROM _fdi_pagos;

    SELECT COALESCE(SUM(l.cantidad * COALESCE(c.costo_usd, 0)
                        * COALESCE(t.tasa, v_tasa_fallback, 1)), 0)
    INTO v_costo_total
    FROM (
        SELECT ep.id_producto, ep.id_presentacion, ep.cantidad, e.ts_op
        FROM _fdi_elig e
        JOIN public.app_dat_extraccion_productos ep ON ep.id_operacion = e.id
        WHERE ep.cantidad > 0
    ) l
    CROSS JOIN LATERAL (
        SELECT COALESCE(
            (SELECT pc.precio_costo_usd FROM public.app_dat_precio_costo pc
             WHERE pc.id_presentacion = l.id_presentacion AND pc.created_at <= l.ts_op
             ORDER BY pc.created_at DESC LIMIT 1),
            (SELECT pp.precio_promedio FROM public.app_dat_producto_presentacion pp
             WHERE pp.id = l.id_presentacion),
            (SELECT pb.precio_promedio FROM public.app_dat_producto_presentacion pb
             WHERE pb.id_producto = l.id_producto AND pb.es_base = true
             ORDER BY pb.id LIMIT 1),
            0) AS costo_usd
    ) c
    CROSS JOIN LATERAL (
        SELECT tc.valor_cambio AS tasa
        FROM public.tasa_cambio_extraoficial tc
        WHERE tc.id_tienda = p_id_tienda AND tc.activo = true
          AND tc.created_at::date <= l.ts_op::date
        ORDER BY tc.created_at DESC LIMIT 1
    ) t;

    v_ganancia := v_venta_total - v_costo_total;

    -- Validar el detalle enviado: cada retirada <= vendido en ese medio/moneda.
    FOR v_det IN SELECT * FROM jsonb_array_elements(COALESCE(p_detalle, '[]'::jsonb))
    LOOP
        v_id_medio := (v_det->>'id_medio_pago')::smallint;
        v_moneda   := COALESCE(NULLIF(TRIM(v_det->>'moneda'), ''), 'CUP');
        v_retirada := COALESCE((v_det->>'monto_ganancia_retirada')::numeric, 0);

        SELECT monto_vendido INTO v_vendido
        FROM _fdi_pagos
        WHERE id_medio_pago = v_id_medio AND moneda = v_moneda;

        IF v_vendido IS NULL THEN
            RAISE EXCEPTION 'Detalle con medio/moneda sin ventas: % %',
                v_id_medio, v_moneda USING ERRCODE = 'P0002';
        END IF;
        IF v_retirada < 0 OR v_retirada > v_vendido THEN
            RAISE EXCEPTION 'Ganancia a retirar (%) fuera de rango para % %',
                v_retirada, v_id_medio, v_moneda USING ERRCODE = 'P0002';
        END IF;

        -- Montos nativos: sin tasa solo se acumula CUP para columnas legacy.
        IF p_tasa_validacion IS NOT NULL THEN
            v_equiv_retirada := v_equiv_retirada + v_retirada *
                CASE WHEN v_moneda = 'CUP' THEN 1 ELSE p_tasa_validacion END;
        ELSIF v_moneda = 'CUP' THEN
            v_equiv_retirada := v_equiv_retirada + v_retirada;
        END IF;
    END LOOP;

    IF p_tasa_validacion IS NOT NULL THEN
        v_diferencia := v_equiv_retirada - v_ganancia;
        IF abs(COALESCE(v_diferencia, 0)) > 0.01 AND NOT p_confirmar_diferencia THEN
            RETURN jsonb_build_object(
                'status', 'requires_confirmation',
                'code', 'diferencia_ganancia',
                'ganancia_reporte', v_ganancia,
                'ganancia_retirada_equivalente', v_equiv_retirada,
                'diferencia', v_diferencia);
        END IF;
    ELSE
        v_diferencia := 0;
    END IF;

    INSERT INTO public.fdi_dat_liquidacion (
        id_tienda, idempotency_key, fecha_desde, fecha_hasta, modo_filtro,
        venta_total, costo_total, ganancia_reporte,
        tasa_validacion, ganancia_retirada_equivalente, diferencia_ganancia,
        confirmada_con_diferencia, repartir_igual, id_cuenta_destino,
        cantidad_ordenes, observacion, created_by
    ) VALUES (
        p_id_tienda, p_idempotency_key, p_desde, p_hasta, v_modo,
        v_venta_total, v_costo_total, v_ganancia,
        p_tasa_validacion, v_equiv_retirada, v_diferencia,
        abs(COALESCE(v_diferencia, 0)) > 0.01, p_repartir_igual,
        p_id_cuenta_destino,
        v_cant_ordenes, p_observacion, auth.uid()
    ) RETURNING id INTO v_id_liquidacion;

    -- Detalle por medio/moneda y movimientos al saldo destino.
    -- depositar_inversion (default true): si false, el sobrante no entra al FDI
    -- (queda fuera del módulo; el fondo de caja es independiente).
    v_equiv_retirada := 0;
    FOR v_id_medio, v_moneda, v_vendido IN
        SELECT id_medio_pago, moneda, monto_vendido FROM _fdi_pagos
    LOOP
        SELECT
            COALESCE((d->>'monto_ganancia_retirada')::numeric, 0),
            CASE
              WHEN d ? 'monto_inversion' THEN (d->>'monto_inversion')::numeric
              WHEN d ? 'depositar_inversion' AND NOT (d->>'depositar_inversion')::boolean
                THEN 0
              ELSE NULL
            END
        INTO v_retirada, v_inversion
        FROM jsonb_array_elements(COALESCE(p_detalle, '[]'::jsonb)) d
        WHERE (d->>'id_medio_pago')::smallint = v_id_medio
          AND COALESCE(NULLIF(TRIM(d->>'moneda'), ''), 'CUP') = v_moneda
        LIMIT 1;

        v_retirada := COALESCE(v_retirada, 0);
        -- Sin monto_inversion explícito: depósito = vendido − ganancia (legado).
        IF v_inversion IS NULL THEN
            v_inversion := v_vendido - v_retirada;
        END IF;
        IF v_inversion < 0 OR v_inversion > v_vendido - v_retirada + 0.01 THEN
            RAISE EXCEPTION 'Inversión a depositar (%) fuera de rango para % %',
                v_inversion, v_id_medio, v_moneda USING ERRCODE = 'P0002';
        END IF;
        v_depositar := v_inversion > 0;

        INSERT INTO public.fdi_dat_liquidacion_detalle (
            id_liquidacion, id_medio_pago, moneda,
            monto_vendido, monto_ganancia_retirada, monto_inversion
        ) VALUES (
            v_id_liquidacion, v_id_medio, v_moneda,
            v_vendido, v_retirada, v_inversion
        ) RETURNING id INTO v_id_detalle;

        -- El trigger de inversores puede ajustar centavos de la ganancia;
        -- la inversión pedida se conserva (reparto mixto).
        SELECT COALESCE(sum(monto), 0) INTO v_retirada
        FROM public.fdi_dat_inversor_reparto WHERE id_detalle = v_id_detalle;
        UPDATE public.fdi_dat_liquidacion_detalle
        SET monto_ganancia_retirada = v_retirada
        WHERE id = v_id_detalle;
        IF p_tasa_validacion IS NOT NULL THEN
            v_equiv_retirada := v_equiv_retirada + v_retirada *
                CASE WHEN v_moneda = 'CUP' THEN 1 ELSE p_tasa_validacion END;
        ELSIF v_moneda = 'CUP' THEN
            v_equiv_retirada := v_equiv_retirada + v_retirada;
        END IF;

        IF v_inversion > 0 THEN
            PERFORM public._fdi_aplicar_movimiento(
                p_id_tienda, p_id_cuenta_destino, v_id_medio, v_moneda,
                v_inversion, 'liquidacion',
                p_id_liquidacion := v_id_liquidacion,
                p_observacion := 'Liquidación ' || p_desde || ' a ' || p_hasta);
        END IF;
    END LOOP;

    IF p_tasa_validacion IS NOT NULL THEN
        v_diferencia := v_equiv_retirada - v_ganancia;
    ELSE
        v_diferencia := 0;
    END IF;
    UPDATE public.fdi_dat_liquidacion
    SET ganancia_retirada_equivalente = v_equiv_retirada,
        diferencia_ganancia = v_diferencia
    WHERE id = v_id_liquidacion;

    -- Órdenes liquidadas (bloqueo de doble liquidación).
    INSERT INTO public.fdi_dat_liquidacion_orden (id_liquidacion, id_operacion_venta)
    SELECT v_id_liquidacion, e.id FROM _fdi_elig e;

    RETURN jsonb_build_object(
        'status', 'ok',
        'id_liquidacion', v_id_liquidacion,
        'cantidad_ordenes', v_cant_ordenes,
        'venta_total', v_venta_total,
        'costo_total', v_costo_total,
        'ganancia_reporte', v_ganancia,
        'diferencia', v_diferencia);
END;
$$;
