-- ============================================================================
-- 12_compra_contrato_rollback.sql — revierte 12_compra_contrato.sql
--
-- Devuelve `fn_fdi_compra_crear` y `fn_fdi_compra_editar` a su cuerpo anterior
-- (factura opcional, tasa por defecto 1, reparto 'valor', origen 'fondo') y
-- retira el helper de tasa de la tienda.
--
-- OJO: el rollback deja el servidor otra vez sin las validaciones nuevas. No lo
-- ejecute con la app nueva desplegada.
-- ============================================================================

DROP FUNCTION IF EXISTS public.fn_fdi_tasa_cup_por_usd_tienda(bigint);

CREATE OR REPLACE FUNCTION public.fn_fdi_compra_crear(
    p_id_tienda bigint,
    p_id_proveedor bigint,
    p_numero_factura text,
    p_fecha_factura date,
    p_moneda_total text,
    p_tasa_factura numeric,
    p_lineas jsonb,
    p_ajustes jsonb DEFAULT '[]'::jsonb,
    p_modo_liquidacion text DEFAULT 'fondo'::text,
    p_politica_pago text DEFAULT 'al_pagar'::text,
    p_observacion text DEFAULT NULL::text,
    p_idempotency_key uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_moneda text := upper(btrim(coalesce(p_moneda_total, '')));
    v_tasa numeric := coalesce(p_tasa_factura, 1);
    v_numero bigint; v_id bigint; v_existe bigint;
    v_linea jsonb; v_ajuste jsonb; v_merc numeric := 0; v_cant numeric := 0; v_monto numeric;
BEGIN
    IF auth.uid() IS NOT NULL AND NOT COALESCE(public.fn_user_is_gerente_or_superadmin(p_id_tienda), false) THEN
        RAISE EXCEPTION 'Solo gerente o superadmin' USING ERRCODE = '42501'; END IF;
    IF v_moneda NOT IN ('USD','CUP','EUR') THEN
        RAISE EXCEPTION 'Moneda inválida: %', p_moneda_total USING ERRCODE = '22023'; END IF;
    IF v_tasa IS NULL OR v_tasa <= 0 THEN
        RAISE EXCEPTION 'La tasa de factura debe ser > 0' USING ERRCODE = '22023'; END IF;
    IF p_modo_liquidacion NOT IN ('fondo','inversores') THEN
        RAISE EXCEPTION 'Modo de liquidación inválido' USING ERRCODE = '22023'; END IF;
    IF p_politica_pago NOT IN ('al_pagar','por_recepcion') THEN
        RAISE EXCEPTION 'Política de pago inválida' USING ERRCODE = '22023'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.app_dat_proveedor WHERE id = p_id_proveedor AND idtienda = p_id_tienda) THEN
        RAISE EXCEPTION 'El proveedor % no pertenece a la tienda %', p_id_proveedor, p_id_tienda USING ERRCODE = '42501'; END IF;
    IF p_lineas IS NULL OR jsonb_typeof(p_lineas) IS DISTINCT FROM 'array' OR jsonb_array_length(p_lineas) = 0 THEN
        RAISE EXCEPTION 'La compra necesita al menos una línea' USING ERRCODE = '22023'; END IF;

    IF p_idempotency_key IS NOT NULL THEN
        SELECT id INTO v_existe FROM public.fdi_dat_compra WHERE idempotency_key = p_idempotency_key;
        IF v_existe IS NOT NULL THEN
            RETURN jsonb_build_object('status','ok','id_compra',v_existe,'duplicada',true); END IF;
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended('fdi_compra_num:' || p_id_tienda, 0));
    SELECT COALESCE(max(numero_compra), 0) + 1 INTO v_numero
    FROM public.fdi_dat_compra WHERE id_tienda = p_id_tienda;

    INSERT INTO public.fdi_dat_compra (id_tienda, numero_compra, id_proveedor, numero_factura,
        fecha_factura, moneda_total, tasa_factura, modo_liquidacion, politica_pago, observacion,
        idempotency_key, created_by)
    VALUES (p_id_tienda, v_numero, p_id_proveedor,
        NULLIF(btrim(coalesce(p_numero_factura,'')), ''), p_fecha_factura, v_moneda, v_tasa,
        p_modo_liquidacion, p_politica_pago, p_observacion, p_idempotency_key, auth.uid())
    RETURNING id INTO v_id;

    FOR v_linea IN SELECT * FROM jsonb_array_elements(p_lineas) LOOP
        IF NOT EXISTS (SELECT 1 FROM public.app_dat_producto WHERE id = (v_linea->>'id_producto')::bigint AND id_tienda = p_id_tienda) THEN
            RAISE EXCEPTION 'Producto % ajeno a la tienda', v_linea->>'id_producto' USING ERRCODE = '42501'; END IF;
        IF (v_linea->>'cantidad')::numeric <= 0 OR (v_linea->>'costo_unitario')::numeric < 0 THEN
            RAISE EXCEPTION 'Línea inválida: cantidad > 0 y costo >= 0' USING ERRCODE = '22023'; END IF;
        INSERT INTO public.fdi_dat_compra_linea (id_compra, id_tienda, id_producto, id_variante,
            id_presentacion, cantidad, costo_unitario, id_almacen, id_ubicacion)
        VALUES (v_id, p_id_tienda, (v_linea->>'id_producto')::bigint, (v_linea->>'id_variante')::bigint,
            (v_linea->>'id_presentacion')::bigint, (v_linea->>'cantidad')::numeric,
            (v_linea->>'costo_unitario')::numeric, (v_linea->>'id_almacen')::bigint,
            (v_linea->>'id_ubicacion')::bigint);
        v_merc := v_merc + round((v_linea->>'cantidad')::numeric * (v_linea->>'costo_unitario')::numeric, 2);
        v_cant := v_cant + (v_linea->>'cantidad')::numeric;
    END LOOP;

    IF p_ajustes IS NOT NULL AND jsonb_typeof(p_ajustes) = 'array' THEN
        FOR v_ajuste IN SELECT * FROM jsonb_array_elements(p_ajustes) LOOP
            v_monto := CASE v_ajuste->>'base'
                         WHEN 'porcentaje' THEN round(v_merc * (v_ajuste->>'valor')::numeric / 100, 2)
                         WHEN 'unidad' THEN round((v_ajuste->>'valor')::numeric * v_cant, 2)
                         ELSE round((v_ajuste->>'valor')::numeric, 2) END;
            INSERT INTO public.fdi_dat_compra_ajuste (id_compra, id_tienda, id_tipo_costo, base, valor,
                reparto, monto_capitalizado, afecta_inventario, origen_pago)
            VALUES (v_id, p_id_tienda, (v_ajuste->>'id_tipo_costo')::bigint,
                COALESCE(NULLIF(v_ajuste->>'base',''), 'global'), (v_ajuste->>'valor')::numeric,
                COALESCE(NULLIF(v_ajuste->>'reparto',''), 'valor'), v_monto,
                COALESCE((v_ajuste->>'afecta_inventario')::boolean, true),
                COALESCE(NULLIF(v_ajuste->>'origen_pago',''), 'fondo'));
        END LOOP;
    END IF;

    PERFORM public.fn_fdi_compra_recalcular(v_id);

    INSERT INTO public.fdi_hist_estado_compra (id_compra, id_tienda, estado_anterior, estado_nuevo, origen, motivo, created_by)
    VALUES (v_id, p_id_tienda, NULL, 'creada', 'automatico', 'Alta de compra', auth.uid());

    RETURN (SELECT jsonb_build_object('status','ok','id_compra',c.id,'numero_compra',c.numero_compra,
                'estado',c.estado,'total_mercancia',c.total_mercancia,'total_ajustes',c.total_ajustes,
                'total_financiado',c.total_financiado,'costo_aterrizado',c.costo_aterrizado,'moneda_total',c.moneda_total)
            FROM public.fdi_dat_compra c WHERE c.id = v_id);
END; $function$;

CREATE OR REPLACE FUNCTION public.fn_fdi_compra_editar(
    p_id_compra bigint,
    p_numero_factura text,
    p_fecha_factura date,
    p_moneda_total text,
    p_tasa_factura numeric,
    p_lineas jsonb,
    p_ajustes jsonb DEFAULT '[]'::jsonb,
    p_observacion text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_c record; v_moneda text := upper(btrim(coalesce(p_moneda_total, '')));
    v_linea jsonb; v_ajuste jsonb; v_merc numeric := 0; v_cant numeric := 0; v_monto numeric;
BEGIN
    SELECT * INTO v_c FROM public.fdi_dat_compra WHERE id = p_id_compra FOR UPDATE;
    IF v_c.id IS NULL THEN RAISE EXCEPTION 'Compra % no encontrada', p_id_compra USING ERRCODE = 'P0002'; END IF;
    IF auth.uid() IS NOT NULL AND NOT COALESCE(public.fn_user_is_gerente_or_superadmin(v_c.id_tienda), false) THEN
        RAISE EXCEPTION 'Solo gerente o superadmin' USING ERRCODE = '42501'; END IF;
    IF v_c.estado <> 'creada' THEN
        RAISE EXCEPTION 'Solo se edita una compra en estado creada (actual: %)', v_c.estado USING ERRCODE = '22023'; END IF;
    IF v_moneda NOT IN ('USD','CUP','EUR') OR p_tasa_factura IS NULL OR p_tasa_factura <= 0 THEN
        RAISE EXCEPTION 'Moneda o tasa inválidas' USING ERRCODE = '22023'; END IF;
    IF p_lineas IS NULL OR jsonb_array_length(p_lineas) = 0 THEN
        RAISE EXCEPTION 'La compra necesita al menos una línea' USING ERRCODE = '22023'; END IF;

    UPDATE public.fdi_dat_compra SET numero_factura = NULLIF(btrim(coalesce(p_numero_factura,'')), ''),
        fecha_factura = p_fecha_factura, moneda_total = v_moneda, tasa_factura = p_tasa_factura,
        observacion = p_observacion, updated_at = now() WHERE id = p_id_compra;

    DELETE FROM public.fdi_dat_compra_ajuste WHERE id_compra = p_id_compra;
    DELETE FROM public.fdi_dat_compra_linea WHERE id_compra = p_id_compra;

    FOR v_linea IN SELECT * FROM jsonb_array_elements(p_lineas) LOOP
        IF NOT EXISTS (SELECT 1 FROM public.app_dat_producto WHERE id = (v_linea->>'id_producto')::bigint AND id_tienda = v_c.id_tienda) THEN
            RAISE EXCEPTION 'Producto % ajeno a la tienda', v_linea->>'id_producto' USING ERRCODE = '42501'; END IF;
        INSERT INTO public.fdi_dat_compra_linea (id_compra, id_tienda, id_producto, id_variante,
            id_presentacion, cantidad, costo_unitario, id_almacen, id_ubicacion)
        VALUES (p_id_compra, v_c.id_tienda, (v_linea->>'id_producto')::bigint,
            (v_linea->>'id_variante')::bigint, (v_linea->>'id_presentacion')::bigint,
            (v_linea->>'cantidad')::numeric, (v_linea->>'costo_unitario')::numeric,
            (v_linea->>'id_almacen')::bigint, (v_linea->>'id_ubicacion')::bigint);
        v_merc := v_merc + round((v_linea->>'cantidad')::numeric * (v_linea->>'costo_unitario')::numeric, 2);
        v_cant := v_cant + (v_linea->>'cantidad')::numeric;
    END LOOP;

    IF p_ajustes IS NOT NULL AND jsonb_typeof(p_ajustes) = 'array' THEN
        FOR v_ajuste IN SELECT * FROM jsonb_array_elements(p_ajustes) LOOP
            v_monto := CASE v_ajuste->>'base'
                         WHEN 'porcentaje' THEN round(v_merc * (v_ajuste->>'valor')::numeric / 100, 2)
                         WHEN 'unidad' THEN round((v_ajuste->>'valor')::numeric * v_cant, 2)
                         ELSE round((v_ajuste->>'valor')::numeric, 2) END;
            INSERT INTO public.fdi_dat_compra_ajuste (id_compra, id_tienda, id_tipo_costo, base, valor,
                reparto, monto_capitalizado, afecta_inventario, origen_pago)
            VALUES (p_id_compra, v_c.id_tienda, (v_ajuste->>'id_tipo_costo')::bigint,
                COALESCE(NULLIF(v_ajuste->>'base',''), 'global'), (v_ajuste->>'valor')::numeric,
                COALESCE(NULLIF(v_ajuste->>'reparto',''), 'valor'), v_monto,
                COALESCE((v_ajuste->>'afecta_inventario')::boolean, true),
                COALESCE(NULLIF(v_ajuste->>'origen_pago',''), 'fondo'));
        END LOOP;
    END IF;

    PERFORM public.fn_fdi_compra_recalcular(p_id_compra);

    RETURN (SELECT jsonb_build_object('status','ok','id_compra',c.id,'total_mercancia',c.total_mercancia,
                'total_financiado',c.total_financiado,'costo_aterrizado',c.costo_aterrizado)
            FROM public.fdi_dat_compra c WHERE c.id = p_id_compra);
END; $function$;

NOTIFY pgrst, 'reload schema';
