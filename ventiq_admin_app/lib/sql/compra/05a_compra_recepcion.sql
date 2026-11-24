-- ============================================================================
-- 05a_compra_recepcion.sql — Fase 5: recepción contra compra
--
-- REQUIERE: 04 aplicado.
--
-- Qué hace:
--   · Añade el cargo de importadora al vínculo compra↔recepción (porcentaje,
--     base, monto y reembolso, con su origen de pago).
--   · `fn_fdi_compra_recepcion_pendiente`: por línea, comprado / recibido /
--     pendiente. Es la fuente de verdad del "falta por llegar".
--   · `fn_fdi_compra_vincular_recepcion`: enlaza una recepción ya registrada a
--     su compra, valida cantidades y mueve el estado.
--
-- El stock NO se mueve aquí: lo aplica la recepción con
-- `fn_contabilizar_recepcion_inventario`, que es la única que propaga id_lote.
--
-- ROLLBACK: 05a_compra_recepcion_rollback.sql
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Cargo de importadora por recepción + fecha de operación
-- ---------------------------------------------------------------------------
ALTER TABLE public.fdi_dat_compra_recepcion
    ADD COLUMN IF NOT EXISTS pct_importadora       numeric(7,4) NOT NULL DEFAULT 0
        CHECK (pct_importadora >= 0 AND pct_importadora <= 100),
    ADD COLUMN IF NOT EXISTS base_importadora      numeric(14,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS monto_importadora     numeric(14,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS reembolso_importadora numeric(14,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS origen_pago           text NOT NULL DEFAULT 'wallet_importadora'
        CHECK (origen_pago IN ('fondo','wallet_importadora','wallet_proveedor','externo'));

ALTER TABLE public.app_dat_operacion_recepcion
    ADD COLUMN IF NOT EXISTS fecha_operacion date;

-- ---------------------------------------------------------------------------
-- 2) Pendiente por línea
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_compra_recepcion_pendiente(p_id_compra bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_c record;
    v jsonb;
BEGIN
    SELECT * INTO v_c FROM public.fdi_dat_compra WHERE id = p_id_compra;
    IF v_c.id IS NULL THEN
        RAISE EXCEPTION 'Compra % no encontrada', p_id_compra USING ERRCODE = 'P0002';
    END IF;
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_can_access_tienda(v_c.id_tienda), false) THEN
        RAISE EXCEPTION 'Sin acceso a la compra %', p_id_compra USING ERRCODE = '42501';
    END IF;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'id_linea', x.id,
                'id_producto', x.id_producto,
                'producto', x.producto,
                'cantidad', x.cantidad,
                'costo_unitario', x.costo_unitario,
                'recibido', x.recibido,
                'pendiente', round(x.cantidad - x.recibido, 4)
            ) ORDER BY x.id), '[]'::jsonb)
      INTO v
    FROM (
        SELECT l.id, l.id_producto, pr.denominacion AS producto, l.cantidad, l.costo_unitario,
               COALESCE((SELECT sum(rl.cantidad_recibida)
                         FROM public.fdi_dat_compra_recepcion_linea rl
                         WHERE rl.id_compra_linea = l.id), 0) AS recibido
        FROM public.fdi_dat_compra_linea l
        JOIN public.app_dat_producto pr ON pr.id = l.id_producto
        WHERE l.id_compra = p_id_compra
    ) x;

    RETURN jsonb_build_object('id_compra', p_id_compra, 'estado', v_c.estado, 'lineas', v);
END;
$$;

-- ---------------------------------------------------------------------------
-- 3) Vincular recepción a la compra
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_compra_vincular_recepcion(
    p_id_operacion   bigint,
    p_id_compra      bigint,
    p_lineas         jsonb,
    p_confirmar_exceso boolean DEFAULT false,
    p_pct_importadora  numeric DEFAULT 0,
    p_base_importadora numeric DEFAULT 0,
    p_reembolso_importadora numeric DEFAULT 0,
    p_origen_pago    text DEFAULT 'wallet_importadora'
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_c        record;
    v_op_tienda bigint;
    v_linea    jsonb;
    v_l        record;
    v_pend     numeric;
    v_recibido numeric;
    v_link     bigint;
    v_pend_total numeric := 0;
    v_nuevo    text;
    v_pct      numeric := COALESCE(p_pct_importadora, 0);
    v_base     numeric := COALESCE(p_base_importadora, 0);
    v_reemb    numeric := COALESCE(p_reembolso_importadora, 0);
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
    IF v_c.estado NOT IN ('reservada','pagada','entrega_parcial') THEN
        RAISE EXCEPTION 'No se recibe una compra en estado %', v_c.estado USING ERRCODE = '22023';
    END IF;

    SELECT id_tienda INTO v_op_tienda FROM public.app_dat_operaciones WHERE id = p_id_operacion;
    IF v_op_tienda IS NULL OR v_op_tienda <> v_c.id_tienda THEN
        RAISE EXCEPTION 'La recepción % no pertenece a la tienda de la compra', p_id_operacion
            USING ERRCODE = 'P0002';
    END IF;
    IF EXISTS (SELECT 1 FROM public.fdi_dat_compra_recepcion WHERE id_operacion = p_id_operacion) THEN
        RAISE EXCEPTION 'La recepción % ya está vinculada a una compra', p_id_operacion
            USING ERRCODE = '22023';
    END IF;

    IF p_lineas IS NULL OR jsonb_typeof(p_lineas) IS DISTINCT FROM 'array'
       OR jsonb_array_length(p_lineas) = 0 THEN
        RAISE EXCEPTION 'Indique las líneas recibidas' USING ERRCODE = '22023';
    END IF;
    IF v_pct < 0 OR v_pct > 100 THEN
        RAISE EXCEPTION 'El porcentaje de importadora debe estar en [0, 100]' USING ERRCODE = '22023';
    END IF;
    IF v_reemb < 0 THEN
        RAISE EXCEPTION 'El reembolso no puede ser negativo' USING ERRCODE = '22023';
    END IF;
    IF p_origen_pago NOT IN ('fondo','wallet_importadora','wallet_proveedor','externo') THEN
        RAISE EXCEPTION 'Origen de pago inválido' USING ERRCODE = '22023';
    END IF;

    v_monto := round(v_base * v_pct / 100, 2) - v_reemb;
    IF v_monto < 0 THEN
        RAISE EXCEPTION 'El reembolso supera el cargo de importadora' USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.fdi_dat_compra_recepcion (
        id_compra, id_tienda, id_operacion, monto_valorizado, moneda, tasa_a_base,
        pct_importadora, base_importadora, monto_importadora, reembolso_importadora,
        origen_pago, created_by
    ) VALUES (
        p_id_compra, v_c.id_tienda, p_id_operacion, 0, v_c.moneda_total, 1,
        v_pct, v_base, v_monto, v_reemb, p_origen_pago, auth.uid()
    ) RETURNING id INTO v_link;

    FOR v_linea IN SELECT * FROM jsonb_array_elements(p_lineas) LOOP
        SELECT l.id, l.id_producto, l.cantidad INTO v_l
        FROM public.fdi_dat_compra_linea l
        WHERE l.id = (v_linea->>'id_compra_linea')::bigint AND l.id_compra = p_id_compra;
        IF v_l.id IS NULL THEN
            RAISE EXCEPTION 'La línea % no pertenece a la compra', v_linea->>'id_compra_linea'
                USING ERRCODE = '22023';
        END IF;

        v_recibido := (v_linea->>'cantidad_recibida')::numeric;
        IF v_recibido IS NULL OR v_recibido <= 0 THEN
            RAISE EXCEPTION 'Cantidad recibida inválida en la línea %', v_l.id USING ERRCODE = '22023';
        END IF;

        SELECT COALESCE(sum(rl.cantidad_recibida), 0) INTO v_pend
        FROM public.fdi_dat_compra_recepcion_linea rl WHERE rl.id_compra_linea = v_l.id;
        v_pend := v_l.cantidad - v_pend;

        IF v_recibido > v_pend AND NOT p_confirmar_exceso THEN
            RAISE EXCEPTION 'La línea % tiene pendiente % y se intentan recibir %. Confirma el exceso si es intencionado.',
                v_l.id, v_pend, v_recibido USING ERRCODE = '22023';
        END IF;

        INSERT INTO public.fdi_dat_compra_recepcion_linea (
            id_compra_recepcion, id_tienda, id_compra_linea, cantidad_recibida,
            costo_unitario_aplicado
        ) VALUES (
            v_link, v_c.id_tienda, v_l.id, v_recibido,
            (SELECT costo_unitario FROM public.fdi_dat_compra_linea WHERE id = v_l.id)
        );
    END LOOP;

    -- Estado resultante, calculado sobre todas las líneas de la compra
    SELECT COALESCE(sum(GREATEST(l.cantidad - COALESCE((
                SELECT sum(rl.cantidad_recibida) FROM public.fdi_dat_compra_recepcion_linea rl
                WHERE rl.id_compra_linea = l.id), 0), 0)), 0)
      INTO v_pend_total
    FROM public.fdi_dat_compra_linea l WHERE l.id_compra = p_id_compra;

    v_nuevo := CASE WHEN v_pend_total <= 0 THEN 'completada' ELSE 'entrega_parcial' END;

    UPDATE public.fdi_dat_compra
       SET estado = v_nuevo, updated_at = now()
     WHERE id = p_id_compra;

    INSERT INTO public.fdi_hist_estado_compra
        (id_compra, id_tienda, estado_anterior, estado_nuevo, origen, motivo, created_by)
    VALUES (p_id_compra, v_c.id_tienda, v_c.estado, v_nuevo, 'automatico',
            'Recepción ' || p_id_operacion, auth.uid());

    RETURN jsonb_build_object('status','ok','id_compra',p_id_compra,'id_operacion',p_id_operacion,
        'estado',v_nuevo,'pendiente_total',v_pend_total,'id_compra_recepcion',v_link,
        'cargo_importadora',v_monto);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fdi_compra_recepcion_pendiente(bigint) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_fdi_compra_vincular_recepcion(bigint,bigint,jsonb,boolean,numeric,numeric,numeric,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_compra_recepcion_pendiente(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_fdi_compra_vincular_recepcion(bigint,bigint,jsonb,boolean,numeric,numeric,numeric,text) TO authenticated;

DO $$
DECLARE v integer;
BEGIN
    SELECT count(*) INTO v FROM information_schema.columns
    WHERE table_schema='public' AND table_name='fdi_dat_compra_recepcion'
      AND column_name IN ('pct_importadora','base_importadora','monto_importadora',
                          'reembolso_importadora','origen_pago');
    IF v <> 5 THEN RAISE EXCEPTION 'Faltan columnas de importadora: % de 5', v; END IF;

    SELECT count(*) INTO v FROM information_schema.columns
    WHERE table_schema='public' AND table_name='app_dat_operacion_recepcion'
      AND column_name='fecha_operacion';
    IF v <> 1 THEN RAISE EXCEPTION 'Falta fecha_operacion'; END IF;

    SELECT count(*) INTO v FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname IN ('fn_fdi_compra_recepcion_pendiente',
        'fn_fdi_compra_vincular_recepcion');
    IF v <> 2 THEN RAISE EXCEPTION 'Faltan RPC de recepción: % de 2', v; END IF;
END;
$$;

COMMIT;