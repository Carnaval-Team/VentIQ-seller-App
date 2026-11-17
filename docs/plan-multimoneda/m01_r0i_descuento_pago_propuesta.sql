BEGIN;

-- BORRADOR M01-R0i descuento y traslado de pago. NO EJECUTAR.
-- Crea dos funciones nuevas. No reemplaza cuerpos existentes.
-- El actor es auth.uid(). El replay no vuelve a rebajar ni a mover el pago.
-- Una clave vieja sin evidencia se retiene. No crea columnas.

SET LOCAL app.m01_r0i_descuento_pago_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r0i_descuento_pago_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador R0i-descuento-pago: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF has_schema_privilege('anon', 'public', 'CREATE')
       OR has_schema_privilege('authenticated', 'public', 'CREATE') THEN
        RAISE EXCEPTION 'public permite CREATE a roles no confiables';
    END IF;
    IF to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta el predicado S01';
    END IF;
    IF to_regprocedure('public.fn_m01_aplicar_descuento_manual(uuid,bigint,integer,numeric)') IS NOT NULL
       OR to_regprocedure('public.fn_m01_mover_pago_venta(uuid,bigint,bigint,bigint,numeric,text,numeric)') IS NOT NULL THEN
        RAISE EXCEPTION 'La funcion de descuento o de traslado ya existe';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'public.app_dat_operacion_offline_idempotencia'::regclass
          AND attname = 'm01_solicitud' AND atttypid = 'jsonb'::regtype AND NOT attisdropped
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'public.app_dat_operacion_offline_idempotencia'::regclass
          AND attname = 'm01_id_tienda' AND atttypid = 'bigint'::regtype AND NOT attisdropped
    ) THEN
        RAISE EXCEPTION 'Falta la evidencia compartida de idempotencia';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_class
        WHERE oid = 'public.app_dat_operacion_offline_idempotencia'::regclass
          AND (NOT relrowsecurity OR relowner <> 'postgres'::regrole)
    ) OR has_any_column_privilege('authenticated', 'public.app_dat_operacion_offline_idempotencia', 'INSERT') THEN
        RAISE EXCEPTION 'Falta el aislamiento M01 de idempotencia';
    END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.fn_m01_aplicar_descuento_manual(
    p_client_uuid uuid,
    p_id_operacion bigint,
    p_tipo_descuento integer,
    p_valor_descuento numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_request jsonb;
    v_existing public.app_dat_operacion_offline_idempotencia%ROWTYPE;
    v_store bigint;
    v_tpv bigint;
    v_seller bigint;
    v_cliente bigint;
    v_base numeric;
    v_desc numeric;
    v_final numeric;
    v_pago record;
    v_moneda text;
    v_tasa numeric;
    v_equiv numeric;
    v_equiv_nuevo numeric;
    v_monto_nativo numeric;
    v_base_nativo numeric;
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL OR p_id_operacion IS NULL
       OR p_tipo_descuento NOT IN (1, 2) OR p_valor_descuento IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_request := jsonb_build_object(
        'version', 1,
        'id_operacion', p_id_operacion,
        'tipo_descuento', p_tipo_descuento,
        'valor_descuento', p_valor_descuento
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));
    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'descuento_manual'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
           OR v_existing.m01_id_tienda IS NULL
           OR v_existing.id_operacion IS DISTINCT FROM p_id_operacion THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        SELECT COALESCE(ov.precio_con_descuento_total, ov.importe_total)
        INTO v_final
        FROM public.app_dat_operacion_venta ov
        WHERE ov.id_operacion = p_id_operacion;
        RETURN jsonb_build_object(
            'success', true, 'idempotent', true,
            'precio_final', v_final
        );
    END IF;

    SELECT o.id_tienda, ov.id_tpv, ov.id_cliente,
           COALESCE(ov.precio_con_descuento_total, ov.importe_total)
    INTO v_store, v_tpv, v_cliente, v_base
    FROM public.app_dat_operaciones o
    JOIN public.app_dat_operacion_venta ov ON ov.id_operacion = o.id
    WHERE o.id = p_id_operacion
    FOR UPDATE OF ov;
    IF NOT FOUND OR v_store IS NULL OR v_tpv IS NULL OR v_base IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    SELECT s.id INTO v_seller
    FROM public.app_dat_vendedor s
    JOIN public.app_dat_trabajadores w ON w.id = s.id_trabajador
    WHERE s.uuid = v_actor AND s.id_tpv = v_tpv
      AND w.uuid = v_actor AND w.deleted_at IS NULL
      AND w.id_tienda = v_store;
    IF v_seller IS NULL
       AND public.fn_config_tienda_puede_escribir(v_store) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF v_seller IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    v_desc := CASE
        WHEN p_tipo_descuento = 1 THEN v_base * (p_valor_descuento / 100)
        ELSE p_valor_descuento
    END;
    IF v_desc < 0 THEN
        v_desc := 0;
    END IF;
    v_final := GREATEST(v_base - v_desc, 0);

    INSERT INTO public.app_dat_descuentos_vendedor (
        id_vendedor, uuid_usuario, id_operacion, monto_real, monto_descontado,
        tipo_descuento, valor_descuento, id_cliente, id_producto
    ) VALUES (
        v_seller, v_actor, p_id_operacion, v_base, v_desc,
        p_tipo_descuento, p_valor_descuento, v_cliente, NULL
    );
    UPDATE public.app_dat_operacion_venta
    SET precio_con_descuento_total = v_final
    WHERE id_operacion = p_id_operacion;

    SELECT pv.id, pv.monto, pv.moneda, pv.tasa_cambio, pv.tasa_usd, pv.monto_cup_equivalente
    INTO v_pago
    FROM public.app_dat_pago_venta pv
    WHERE pv.id_operacion_venta = p_id_operacion
    ORDER BY CASE
        WHEN upper(btrim(COALESCE(pv.moneda, 'CUP'))) = 'CUP' THEN pv.monto
        ELSE COALESCE(pv.monto_cup_equivalente, 0)
    END DESC, pv.id
    LIMIT 1
    FOR UPDATE;
    IF FOUND THEN
        v_moneda := upper(btrim(COALESCE(v_pago.moneda, 'CUP')));
        v_tasa := COALESCE(NULLIF(v_pago.tasa_cambio, 0), NULLIF(v_pago.tasa_usd, 0), 0);
        v_equiv := CASE
            WHEN v_moneda = 'CUP' THEN v_pago.monto
            ELSE COALESCE(v_pago.monto_cup_equivalente, 0)
        END;
        v_equiv_nuevo := GREATEST(v_equiv - v_desc, 0);
        IF v_moneda = 'CUP' THEN
            v_monto_nativo := v_equiv_nuevo;
            v_base_nativo := v_base;
        ELSIF v_tasa <= 0 THEN
            v_monto_nativo := v_pago.monto;
            v_base_nativo := v_base;
        ELSE
            v_monto_nativo := v_equiv_nuevo / v_tasa;
            v_base_nativo := v_base / v_tasa;
        END IF;
        UPDATE public.app_dat_pago_venta
        SET monto = v_monto_nativo,
            importe_sin_descuento = v_base_nativo,
            monto_cup_equivalente = v_equiv_nuevo
        WHERE id = v_pago.id;
    END IF;

    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, p_id_operacion, 'descuento_manual', v_actor, v_request, v_store);
    RETURN jsonb_build_object(
        'success', true, 'idempotent', false,
        'monto_base', v_base,
        'monto_descontado', v_desc,
        'precio_final', v_final
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_m01_mover_pago_venta(
    p_client_uuid uuid,
    p_id_operacion bigint,
    p_id_medio_origen bigint,
    p_id_medio_destino bigint,
    p_monto numeric,
    p_moneda text DEFAULT NULL,
    p_tasa numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_request jsonb;
    v_existing public.app_dat_operacion_offline_idempotencia%ROWTYPE;
    v_store bigint;
    v_tpv bigint;
    v_src record;
    v_dst record;
    v_moneda text;
    v_tasa numeric;
    v_base numeric;
    v_nuevo numeric;
    v_tipo smallint;
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL OR p_id_operacion IS NULL
       OR p_id_medio_origen IS NULL OR p_id_medio_destino IS NULL
       OR p_monto IS NULL OR p_monto <= 0
       OR p_id_medio_origen = p_id_medio_destino THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_request := jsonb_build_object(
        'version', 1,
        'id_operacion', p_id_operacion,
        'medio_origen', p_id_medio_origen,
        'medio_destino', p_id_medio_destino,
        'monto', p_monto,
        'moneda', upper(btrim(COALESCE(p_moneda, ''))),
        'tasa', p_tasa
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));
    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'mover_pago'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
           OR v_existing.m01_id_tienda IS NULL
           OR v_existing.id_operacion IS DISTINCT FROM p_id_operacion THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object(
            'success', true, 'idempotent', true, 'moved_amount', p_monto
        );
    END IF;

    SELECT o.id_tienda, ov.id_tpv
    INTO v_store, v_tpv
    FROM public.app_dat_operaciones o
    JOIN public.app_dat_operacion_venta ov ON ov.id_operacion = o.id
    WHERE o.id = p_id_operacion
    FOR SHARE OF o, ov;
    IF NOT FOUND OR v_store IS NULL OR v_tpv IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF public.fn_config_tienda_puede_escribir(v_store) IS DISTINCT FROM true
       AND NOT EXISTS (
            SELECT 1
            FROM public.app_dat_vendedor s
            JOIN public.app_dat_trabajadores w ON w.id = s.id_trabajador
            WHERE s.uuid = v_actor AND s.id_tpv = v_tpv
              AND w.uuid = v_actor AND w.deleted_at IS NULL
              AND w.id_tienda = v_store
       ) THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    SELECT pv.id, pv.monto, pv.moneda, pv.tasa_cambio, pv.tasa_usd, pv.monto_cup_equivalente
    INTO v_src
    FROM public.app_dat_pago_venta pv
    WHERE pv.id_operacion_venta = p_id_operacion
      AND pv.id_medio_pago = p_id_medio_origen
      AND (p_moneda IS NULL OR upper(btrim(COALESCE(pv.moneda, 'CUP'))) = upper(btrim(p_moneda)))
    ORDER BY pv.id
    LIMIT 1
    FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'El pago origen no fue encontrado');
    END IF;
    IF p_monto > v_src.monto THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'El monto a mover no puede ser mayor al saldo del método origen'
        );
    END IF;
    v_moneda := upper(btrim(COALESCE(v_src.moneda, 'CUP')));
    v_tasa := CASE
        WHEN v_moneda = 'CUP' THEN 1
        ELSE COALESCE(NULLIF(v_src.tasa_cambio, 0), NULLIF(v_src.tasa_usd, 0), 0)
    END;
    IF v_tasa <= 0 THEN
        RETURN jsonb_build_object('success', false, 'message', 'El pago origen no tiene una tasa válida');
    END IF;
    IF p_tasa IS NOT NULL AND v_moneda <> 'CUP' AND v_tasa IS DISTINCT FROM p_tasa THEN
        RETURN jsonb_build_object('success', false, 'message', 'El pago origen no fue encontrado');
    END IF;
    v_base := p_monto * v_tasa;
    v_nuevo := v_src.monto - p_monto;
    IF v_nuevo <= 0.0001 THEN
        DELETE FROM public.app_dat_pago_venta WHERE id = v_src.id;
    ELSE
        UPDATE public.app_dat_pago_venta
        SET monto = v_nuevo,
            monto_cup_equivalente = GREATEST(COALESCE(v_src.monto_cup_equivalente, v_src.monto * v_tasa) - v_base, 0)
        WHERE id = v_src.id;
    END IF;

    SELECT pv.id, pv.monto, pv.monto_cup_equivalente
    INTO v_dst
    FROM public.app_dat_pago_venta pv
    WHERE pv.id_operacion_venta = p_id_operacion
      AND pv.id_medio_pago = p_id_medio_destino
      AND upper(btrim(COALESCE(pv.moneda, 'CUP'))) = v_moneda
      AND (
          v_moneda = 'CUP'
          OR COALESCE(NULLIF(pv.tasa_cambio, 0), NULLIF(pv.tasa_usd, 0), 0) = v_tasa
      )
    ORDER BY pv.id
    LIMIT 1
    FOR UPDATE;
    IF FOUND THEN
        UPDATE public.app_dat_pago_venta
        SET monto = v_dst.monto + p_monto,
            monto_cup_equivalente = COALESCE(v_dst.monto_cup_equivalente, 0) + v_base
        WHERE id = v_dst.id;
    ELSE
        v_tipo := CASE WHEN p_id_medio_destino = 1 THEN 1 ELSE 2 END;
        INSERT INTO public.app_dat_pago_venta (
            id_operacion_venta, id_medio_pago, monto, moneda, tasa_cambio, tasa_usd,
            monto_cup_equivalente, tipo_pago, referencia_pago, creado_por
        ) VALUES (
            p_id_operacion, p_id_medio_destino, p_monto, v_moneda, v_tasa,
            CASE WHEN v_moneda = 'USD' THEN v_tasa ELSE NULL END,
            v_base, v_tipo, 'Ajuste Inventtia Caja', v_actor
        );
    END IF;

    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, p_id_operacion, 'mover_pago', v_actor, v_request, v_store);
    RETURN jsonb_build_object(
        'success', true, 'idempotent', false,
        'source_amount', v_src.monto,
        'new_source_amount', GREATEST(v_nuevo, 0),
        'moved_amount', p_monto
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_m01_aplicar_descuento_manual(uuid,bigint,integer,numeric)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_aplicar_descuento_manual(uuid,bigint,integer,numeric)
    TO authenticated;
REVOKE ALL ON FUNCTION public.fn_m01_mover_pago_venta(uuid,bigint,bigint,bigint,numeric,text,numeric)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_mover_pago_venta(uuid,bigint,bigint,bigint,numeric,text,numeric)
    TO authenticated;

COMMIT;
