-- ============================================================================
-- 03b_compra_rpcs.sql — Fase 3: RPC de la compra
--
-- REQUIERE: 03a_compra_esquema.sql aplicado.
--
--   fn_fdi_compra_crear     · numeración por tienda, líneas, ajustes, idempotencia
--   fn_fdi_compra_editar    · solo mientras la compra está en 'creada'
--   fn_fdi_compra_listar    · filtros por estado/proveedor/fechas/texto
--   fn_fdi_compra_detalle   · compra + líneas + ajustes + historial
--   fn_fdi_compra_cancelar  · sin pagos ni recepciones
--
-- Convención: con sesión se exige gerente/superadmin; sin sesión (service_role,
-- editor SQL) se permite, para poder probar. Escritura solo por estas RPC.
--
-- ROLLBACK: 03b_compra_rpcs_rollback.sql
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- Crear
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_compra_crear(
    p_id_tienda        bigint,
    p_id_proveedor     bigint,
    p_numero_factura   text,
    p_fecha_factura    date,
    p_moneda_total     text,
    p_tasa_factura     numeric,
    p_lineas           jsonb,
    p_ajustes          jsonb DEFAULT '[]'::jsonb,
    p_modo_liquidacion text DEFAULT 'fondo',
    p_politica_pago    text DEFAULT 'al_pagar',
    p_observacion      text DEFAULT NULL,
    p_idempotency_key  uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_moneda   text := upper(btrim(coalesce(p_moneda_total, '')));
    v_tasa     numeric := coalesce(p_tasa_factura, 1);
    v_numero   bigint;
    v_id       bigint;
    v_existe   bigint;
    v_linea    jsonb;
    v_ajuste   jsonb;
    v_merc     numeric := 0;
    v_cant     numeric := 0;
    v_monto    numeric;
BEGIN
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_is_gerente_or_superadmin(p_id_tienda), false) THEN
        RAISE EXCEPTION 'Solo gerente o superadmin' USING ERRCODE = '42501';
    END IF;
    IF v_moneda NOT IN ('USD','CUP','EUR') THEN
        RAISE EXCEPTION 'Moneda inválida: %', p_moneda_total USING ERRCODE = '22023';
    END IF;
    IF v_tasa IS NULL OR v_tasa <= 0 THEN
        RAISE EXCEPTION 'La tasa de factura debe ser > 0' USING ERRCODE = '22023';
    END IF;
    IF p_modo_liquidacion NOT IN ('fondo','inversores') THEN
        RAISE EXCEPTION 'Modo de liquidación inválido' USING ERRCODE = '22023';
    END IF;
    IF p_politica_pago NOT IN ('al_pagar','por_recepcion') THEN
        RAISE EXCEPTION 'Política de pago inválida' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.app_dat_proveedor
                    WHERE id = p_id_proveedor AND idtienda = p_id_tienda) THEN
        RAISE EXCEPTION 'El proveedor % no pertenece a la tienda %', p_id_proveedor, p_id_tienda
            USING ERRCODE = '42501';
    END IF;
    IF p_lineas IS NULL OR jsonb_typeof(p_lineas) IS DISTINCT FROM 'array'
       OR jsonb_array_length(p_lineas) = 0 THEN
        RAISE EXCEPTION 'La compra necesita al menos una línea' USING ERRCODE = '22023';
    END IF;

    IF p_idempotency_key IS NOT NULL THEN
        SELECT id INTO v_existe FROM public.fdi_dat_compra
        WHERE idempotency_key = p_idempotency_key;
        IF v_existe IS NOT NULL THEN
            RETURN jsonb_build_object('status','ok','id_compra',v_existe,'duplicada',true);
        END IF;
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended('fdi_compra_num:' || p_id_tienda, 0));
    SELECT COALESCE(max(numero_compra), 0) + 1 INTO v_numero
    FROM public.fdi_dat_compra WHERE id_tienda = p_id_tienda;

    INSERT INTO public.fdi_dat_compra (
        id_tienda, numero_compra, id_proveedor, numero_factura, fecha_factura,
        moneda_total, tasa_factura, modo_liquidacion, politica_pago, observacion,
        idempotency_key, created_by
    ) VALUES (
        p_id_tienda, v_numero, p_id_proveedor,
        NULLIF(btrim(coalesce(p_numero_factura,'')), ''), p_fecha_factura,
        v_moneda, v_tasa, p_modo_liquidacion, p_politica_pago, p_observacion,
        p_idempotency_key, auth.uid()
    ) RETURNING id INTO v_id;

    FOR v_linea IN SELECT * FROM jsonb_array_elements(p_lineas) LOOP
        IF NOT EXISTS (SELECT 1 FROM public.app_dat_producto
                        WHERE id = (v_linea->>'id_producto')::bigint AND id_tienda = p_id_tienda) THEN
            RAISE EXCEPTION 'Producto % ajeno a la tienda', v_linea->>'id_producto'
                USING ERRCODE = '42501';
        END IF;
        IF (v_linea->>'cantidad')::numeric <= 0
           OR (v_linea->>'costo_unitario')::numeric < 0 THEN
            RAISE EXCEPTION 'Línea inválida: cantidad > 0 y costo >= 0' USING ERRCODE = '22023';
        END IF;

        INSERT INTO public.fdi_dat_compra_linea (
            id_compra, id_tienda, id_producto, id_variante, id_presentacion,
            cantidad, costo_unitario, id_almacen, id_ubicacion
        ) VALUES (
            v_id, p_id_tienda,
            (v_linea->>'id_producto')::bigint,
            (v_linea->>'id_variante')::bigint,
            (v_linea->>'id_presentacion')::bigint,
            (v_linea->>'cantidad')::numeric,
            (v_linea->>'costo_unitario')::numeric,
            (v_linea->>'id_almacen')::bigint,
            (v_linea->>'id_ubicacion')::bigint
        );

        v_merc := v_merc + round((v_linea->>'cantidad')::numeric * (v_linea->>'costo_unitario')::numeric, 2);
        v_cant := v_cant + (v_linea->>'cantidad')::numeric;
    END LOOP;

    IF p_ajustes IS NOT NULL AND jsonb_typeof(p_ajustes) = 'array' THEN
        FOR v_ajuste IN SELECT * FROM jsonb_array_elements(p_ajustes) LOOP
            v_monto := CASE v_ajuste->>'base'
                         WHEN 'porcentaje' THEN round(v_merc * (v_ajuste->>'valor')::numeric / 100, 2)
                         WHEN 'unidad'     THEN round((v_ajuste->>'valor')::numeric * v_cant, 2)
                         ELSE round((v_ajuste->>'valor')::numeric, 2)
                       END;

            INSERT INTO public.fdi_dat_compra_ajuste (
                id_compra, id_tienda, id_tipo_costo, base, valor, reparto,
                monto_capitalizado, afecta_inventario, origen_pago
            ) VALUES (
                v_id, p_id_tienda,
                (v_ajuste->>'id_tipo_costo')::bigint,
                COALESCE(NULLIF(v_ajuste->>'base',''), 'global'),
                (v_ajuste->>'valor')::numeric,
                COALESCE(NULLIF(v_ajuste->>'reparto',''), 'valor'),
                v_monto,
                COALESCE((v_ajuste->>'afecta_inventario')::boolean, true),
                COALESCE(NULLIF(v_ajuste->>'origen_pago',''), 'fondo')
            );
        END LOOP;
    END IF;

    PERFORM public.fn_fdi_compra_recalcular(v_id);

    INSERT INTO public.fdi_hist_estado_compra
        (id_compra, id_tienda, estado_anterior, estado_nuevo, origen, motivo, created_by)
    VALUES (v_id, p_id_tienda, NULL, 'creada', 'automatico', 'Alta de compra', auth.uid());

    RETURN (SELECT jsonb_build_object(
                'status','ok','id_compra',c.id,'numero_compra',c.numero_compra,
                'estado',c.estado,'total_mercancia',c.total_mercancia,
                'total_ajustes',c.total_ajustes,'total_financiado',c.total_financiado,
                'costo_aterrizado',c.costo_aterrizado,'moneda_total',c.moneda_total)
            FROM public.fdi_dat_compra c WHERE c.id = v_id);
END;
$$;

-- ---------------------------------------------------------------------------
-- Editar (solo en 'creada')
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_compra_editar(
    p_id_compra       bigint,
    p_numero_factura  text,
    p_fecha_factura   date,
    p_moneda_total    text,
    p_tasa_factura    numeric,
    p_lineas          jsonb,
    p_ajustes         jsonb DEFAULT '[]'::jsonb,
    p_observacion     text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_c        record;
    v_moneda   text := upper(btrim(coalesce(p_moneda_total, '')));
    v_linea    jsonb;
    v_ajuste   jsonb;
    v_merc     numeric := 0;
    v_cant     numeric := 0;
    v_monto    numeric;
BEGIN
    SELECT * INTO v_c FROM public.fdi_dat_compra WHERE id = p_id_compra FOR UPDATE;
    IF v_c.id IS NULL THEN
        RAISE EXCEPTION 'Compra % no encontrada', p_id_compra USING ERRCODE = 'P0002';
    END IF;
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_is_gerente_or_superadmin(v_c.id_tienda), false) THEN
        RAISE EXCEPTION 'Solo gerente o superadmin' USING ERRCODE = '42501';
    END IF;
    IF v_c.estado <> 'creada' THEN
        RAISE EXCEPTION 'Solo se edita una compra en estado creada (actual: %)', v_c.estado
            USING ERRCODE = '22023';
    END IF;
    IF v_moneda NOT IN ('USD','CUP','EUR') OR p_tasa_factura IS NULL OR p_tasa_factura <= 0 THEN
        RAISE EXCEPTION 'Moneda o tasa inválidas' USING ERRCODE = '22023';
    END IF;
    IF p_lineas IS NULL OR jsonb_array_length(p_lineas) = 0 THEN
        RAISE EXCEPTION 'La compra necesita al menos una línea' USING ERRCODE = '22023';
    END IF;

    UPDATE public.fdi_dat_compra
       SET numero_factura = NULLIF(btrim(coalesce(p_numero_factura,'')), ''),
           fecha_factura  = p_fecha_factura,
           moneda_total   = v_moneda,
           tasa_factura   = p_tasa_factura,
           observacion    = p_observacion,
           updated_at     = now()
     WHERE id = p_id_compra;

    DELETE FROM public.fdi_dat_compra_ajuste WHERE id_compra = p_id_compra;
    DELETE FROM public.fdi_dat_compra_linea  WHERE id_compra = p_id_compra;

    FOR v_linea IN SELECT * FROM jsonb_array_elements(p_lineas) LOOP
        IF NOT EXISTS (SELECT 1 FROM public.app_dat_producto
                        WHERE id = (v_linea->>'id_producto')::bigint AND id_tienda = v_c.id_tienda) THEN
            RAISE EXCEPTION 'Producto % ajeno a la tienda', v_linea->>'id_producto'
                USING ERRCODE = '42501';
        END IF;
        INSERT INTO public.fdi_dat_compra_linea (
            id_compra, id_tienda, id_producto, id_variante, id_presentacion,
            cantidad, costo_unitario, id_almacen, id_ubicacion
        ) VALUES (
            p_id_compra, v_c.id_tienda,
            (v_linea->>'id_producto')::bigint,
            (v_linea->>'id_variante')::bigint,
            (v_linea->>'id_presentacion')::bigint,
            (v_linea->>'cantidad')::numeric,
            (v_linea->>'costo_unitario')::numeric,
            (v_linea->>'id_almacen')::bigint,
            (v_linea->>'id_ubicacion')::bigint
        );
        v_merc := v_merc + round((v_linea->>'cantidad')::numeric * (v_linea->>'costo_unitario')::numeric, 2);
        v_cant := v_cant + (v_linea->>'cantidad')::numeric;
    END LOOP;

    IF p_ajustes IS NOT NULL AND jsonb_typeof(p_ajustes) = 'array' THEN
        FOR v_ajuste IN SELECT * FROM jsonb_array_elements(p_ajustes) LOOP
            v_monto := CASE v_ajuste->>'base'
                         WHEN 'porcentaje' THEN round(v_merc * (v_ajuste->>'valor')::numeric / 100, 2)
                         WHEN 'unidad'     THEN round((v_ajuste->>'valor')::numeric * v_cant, 2)
                         ELSE round((v_ajuste->>'valor')::numeric, 2)
                       END;
            INSERT INTO public.fdi_dat_compra_ajuste (
                id_compra, id_tienda, id_tipo_costo, base, valor, reparto,
                monto_capitalizado, afecta_inventario, origen_pago
            ) VALUES (
                p_id_compra, v_c.id_tienda,
                (v_ajuste->>'id_tipo_costo')::bigint,
                COALESCE(NULLIF(v_ajuste->>'base',''), 'global'),
                (v_ajuste->>'valor')::numeric,
                COALESCE(NULLIF(v_ajuste->>'reparto',''), 'valor'),
                v_monto,
                COALESCE((v_ajuste->>'afecta_inventario')::boolean, true),
                COALESCE(NULLIF(v_ajuste->>'origen_pago',''), 'fondo')
            );
        END LOOP;
    END IF;

    PERFORM public.fn_fdi_compra_recalcular(p_id_compra);

    RETURN (SELECT jsonb_build_object('status','ok','id_compra',c.id,
                'total_mercancia',c.total_mercancia,'total_financiado',c.total_financiado,
                'costo_aterrizado',c.costo_aterrizado)
            FROM public.fdi_dat_compra c WHERE c.id = p_id_compra);
END;
$$;

-- ---------------------------------------------------------------------------
-- Listar
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_compra_listar(
    p_id_tienda     bigint,
    p_estado        text DEFAULT NULL,
    p_id_proveedor  bigint DEFAULT NULL,
    p_desde         date DEFAULT NULL,
    p_hasta         date DEFAULT NULL,
    p_texto         text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v jsonb;
BEGIN
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_can_access_tienda(p_id_tienda), false) THEN
        RAISE EXCEPTION 'Sin acceso a la tienda %', p_id_tienda USING ERRCODE = '42501';
    END IF;

    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.numero_compra DESC), '[]'::jsonb)
      INTO v
    FROM (
        SELECT c.id, c.numero_compra, c.id_proveedor, p.denominacion AS proveedor,
               c.numero_factura, c.fecha_factura, c.moneda_total,
               c.total_mercancia, c.total_ajustes, c.total_financiado, c.costo_aterrizado,
               c.modo_liquidacion, c.politica_pago, c.estado,
               c.observacion, c.created_at,
               (SELECT count(*) FROM public.fdi_dat_compra_linea l WHERE l.id_compra = c.id) AS lineas
        FROM public.fdi_dat_compra c
        JOIN public.app_dat_proveedor p ON p.id = c.id_proveedor
        WHERE c.id_tienda = p_id_tienda
          AND (p_estado IS NULL OR c.estado = p_estado)
          AND (p_id_proveedor IS NULL OR c.id_proveedor = p_id_proveedor)
          AND (p_desde IS NULL OR c.fecha_factura >= p_desde)
          AND (p_hasta IS NULL OR c.fecha_factura <= p_hasta)
          AND (p_texto IS NULL OR btrim(p_texto) = ''
               OR c.numero_factura ILIKE '%' || p_texto || '%'
               OR p.denominacion ILIKE '%' || p_texto || '%')
    ) x;

    RETURN v;
END;
$$;

-- ---------------------------------------------------------------------------
-- Detalle
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_compra_detalle(p_id_compra bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_c record;
BEGIN
    SELECT * INTO v_c FROM public.fdi_dat_compra WHERE id = p_id_compra;
    IF v_c.id IS NULL THEN
        RAISE EXCEPTION 'Compra % no encontrada', p_id_compra USING ERRCODE = 'P0002';
    END IF;
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_can_access_tienda(v_c.id_tienda), false) THEN
        RAISE EXCEPTION 'Sin acceso a la compra %', p_id_compra USING ERRCODE = '42501';
    END IF;

    RETURN jsonb_build_object(
        'compra', to_jsonb(v_c),
        'proveedor', (SELECT jsonb_build_object('id',p.id,'denominacion',p.denominacion)
                      FROM public.app_dat_proveedor p WHERE p.id = v_c.id_proveedor),
        'lineas', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                        'id',l.id,'id_producto',l.id_producto,'id_variante',l.id_variante,
                        'id_presentacion',l.id_presentacion,'cantidad',l.cantidad,
                        'costo_unitario',l.costo_unitario,'costo_linea',l.costo_linea,
                        'id_almacen',l.id_almacen,'id_ubicacion',l.id_ubicacion,
                        'producto',(SELECT pr.denominacion FROM public.app_dat_producto pr WHERE pr.id = l.id_producto)
                    ) ORDER BY l.id)
                    FROM public.fdi_dat_compra_linea l WHERE l.id_compra = p_id_compra), '[]'::jsonb),
        'ajustes', COALESCE((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.id)
                    FROM public.fdi_dat_compra_ajuste a WHERE a.id_compra = p_id_compra), '[]'::jsonb),
        'historial', COALESCE((SELECT jsonb_agg(to_jsonb(h) ORDER BY h.created_at)
                    FROM public.fdi_hist_estado_compra h WHERE h.id_compra = p_id_compra), '[]'::jsonb),
        'recepciones', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.id)
                    FROM public.fdi_dat_compra_recepcion r WHERE r.id_compra = p_id_compra), '[]'::jsonb));
END;
$$;

-- ---------------------------------------------------------------------------
-- Cancelar (solo sin pagos ni recepciones)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_compra_cancelar(
    p_id_compra bigint,
    p_motivo    text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_c record;
BEGIN
    IF p_motivo IS NULL OR btrim(p_motivo) = '' THEN
        RAISE EXCEPTION 'El motivo de cancelación es obligatorio' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_c FROM public.fdi_dat_compra WHERE id = p_id_compra FOR UPDATE;
    IF v_c.id IS NULL THEN
        RAISE EXCEPTION 'Compra % no encontrada', p_id_compra USING ERRCODE = 'P0002';
    END IF;
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_is_gerente_or_superadmin(v_c.id_tienda), false) THEN
        RAISE EXCEPTION 'Solo gerente o superadmin' USING ERRCODE = '42501';
    END IF;
    IF v_c.estado = 'cancelada' THEN
        RETURN jsonb_build_object('status','ok','duplicada',true);
    END IF;
    IF v_c.estado <> 'creada' THEN
        RAISE EXCEPTION 'Solo se cancela una compra en estado creada (actual: %)', v_c.estado
            USING ERRCODE = '22023';
    END IF;
    IF EXISTS (SELECT 1 FROM public.fdi_dat_compra_recepcion WHERE id_compra = p_id_compra) THEN
        RAISE EXCEPTION 'La compra ya tiene recepciones' USING ERRCODE = '22023';
    END IF;

    UPDATE public.fdi_dat_compra
       SET estado = 'cancelada', observacion = COALESCE(observacion,'') 
           || CASE WHEN observacion IS NULL OR observacion = '' THEN '' ELSE ' · ' END
           || 'Cancelada: ' || btrim(p_motivo),
           updated_at = now()
     WHERE id = p_id_compra;

    INSERT INTO public.fdi_hist_estado_compra
        (id_compra, id_tienda, estado_anterior, estado_nuevo, origen, motivo, created_by)
    VALUES (p_id_compra, v_c.id_tienda, v_c.estado, 'cancelada', 'manual', btrim(p_motivo), auth.uid());

    RETURN jsonb_build_object('status','ok','id_compra',p_id_compra,'estado','cancelada');
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fdi_compra_crear(bigint,bigint,text,date,text,numeric,jsonb,jsonb,text,text,text,uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_fdi_compra_editar(bigint,text,date,text,numeric,jsonb,jsonb,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_fdi_compra_listar(bigint,text,bigint,date,date,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_fdi_compra_detalle(bigint) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_fdi_compra_cancelar(bigint,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_compra_crear(bigint,bigint,text,date,text,numeric,jsonb,jsonb,text,text,text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_fdi_compra_editar(bigint,text,date,text,numeric,jsonb,jsonb,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_fdi_compra_listar(bigint,text,bigint,date,date,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_fdi_compra_detalle(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_fdi_compra_cancelar(bigint,text) TO authenticated;

DO $$
DECLARE v integer;
BEGIN
    SELECT count(*) INTO v FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('fn_fdi_compra_crear','fn_fdi_compra_editar','fn_fdi_compra_listar',
                        'fn_fdi_compra_detalle','fn_fdi_compra_cancelar');
    IF v <> 5 THEN RAISE EXCEPTION 'Faltan RPC de compra: hay % de 5', v; END IF;
END;
$$;

COMMIT;