-- ============================================================================
-- 05c_carril_b.sql — Fase 5c: cerrar el carril B
--
-- REQUIERE: 05a aplicado.
--
-- Cierra tres agujeros del carril "recepción directa":
--
-- 1. DOBLE USO DEL DESEMBOLSO. Al cancelar una recepción financiada, la
--    inversión volvía a 'pendiente' con el saldo YA debitado y podía
--    re-vincularse a otra recepción. Ahora se marca
--    `requiere_revision = true` con motivo `recepcion_cancelada`, y
--    `fn_fdi_vincular_recepcion` rechaza esas inversiones.
--
-- 2. REINTENTO SOBRE UNA CANCELADA. Con la misma clave, la RPC devolvía
--    `duplicada: true` sobre una operación cancelada, y la app lo pintaba
--    como éxito. Ahora lanza error explicando que hay que generar otra clave.
--
-- 3. COMPRA Y CARRIL DIRECTO. `fn_fdi_registrar_recepcion` acepta
--    `p_id_compra` pero lo RECHAZA: una recepción con compra pertenece al
--    carril A. El parámetro existe para que la regla quede en la base.
--
-- El dinero NO se devuelve automáticamente al cancelar (política del módulo):
-- la inversión queda marcada para revisión y se resuelve con
-- `fn_fdi_resolver_revision` o anulándola después.
--
-- ROLLBACK: 05c_carril_b_rollback.sql
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Motivo de revisión nuevo
-- ---------------------------------------------------------------------------
ALTER TABLE public.fdi_dat_inversion
    DROP CONSTRAINT IF EXISTS fdi_dat_inversion_motivo_revision_check;
ALTER TABLE public.fdi_dat_inversion
    ADD CONSTRAINT fdi_dat_inversion_motivo_revision_check
    CHECK (motivo_revision IN ('completado_con_faltante','vencida','recepcion_cancelada'));

-- ---------------------------------------------------------------------------
-- 2) Marcar la inversión al desvincular una recepción financiada
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_desvincular_recepcion(p_id_operacion bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id_inversion bigint;
    v_financiada   boolean;
BEGIN
    SELECT (fdi_idempotency_key IS NOT NULL) INTO v_financiada
    FROM public.app_dat_operacion_recepcion WHERE id_operacion = p_id_operacion;

    DELETE FROM public.fdi_dat_inversion_recepcion
    WHERE id_operacion = p_id_operacion
    RETURNING id_inversion INTO v_id_inversion;

    IF v_id_inversion IS NOT NULL THEN
        -- Una recepción financiada que se desvincula deja dinero ya debitado:
        -- no puede volver a usarse. Se marca para revisión.
        IF COALESCE(v_financiada, false) THEN
            UPDATE public.fdi_dat_inversion
               SET requiere_revision = true,
                   motivo_revision   = 'recepcion_cancelada',
                   updated_at        = now()
             WHERE id = v_id_inversion
               AND estado <> 'anulado';
        END IF;
        PERFORM public.fn_fdi_recalcular_inversion(v_id_inversion);
    END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3) Vincular rechaza inversiones marcadas por cancelación
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_vincular_recepcion(
    p_id_operacion     bigint,
    p_id_inversion     bigint,
    p_monto            numeric,
    p_moneda           text,
    p_tasa_a_ref       numeric DEFAULT 1,
    p_confirmar_exceso boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_inv       record;
    v_op_tienda bigint;
    v_monto_ref numeric;
BEGIN
    SELECT * INTO v_inv FROM public.fdi_dat_inversion WHERE id = p_id_inversion FOR UPDATE;
    IF v_inv.id IS NULL THEN
        RAISE EXCEPTION 'Inversión % no encontrada', p_id_inversion USING ERRCODE = 'P0002';
    END IF;
    IF v_inv.estado = 'anulado' THEN
        RAISE EXCEPTION 'La inversión % está anulada y no admite recepciones', p_id_inversion
            USING ERRCODE = '22023';
    END IF;
    IF v_inv.requiere_revision AND v_inv.motivo_revision = 'recepcion_cancelada' THEN
        RAISE EXCEPTION 'La inversión % viene de una recepción cancelada: su dinero ya se debitó y no puede reutilizarse sin resolver la revisión',
            p_id_inversion USING ERRCODE = '22023';
    END IF;

    SELECT id_tienda INTO v_op_tienda FROM public.app_dat_operaciones WHERE id = p_id_operacion;
    IF v_op_tienda IS NULL OR v_op_tienda <> v_inv.id_tienda THEN
        RAISE EXCEPTION 'La recepción % no pertenece a la tienda de la inversión', p_id_operacion
            USING ERRCODE = 'P0002';
    END IF;
    IF p_monto IS NULL OR p_monto <= 0 THEN
        RAISE EXCEPTION 'El monto de la recepción debe ser > 0' USING ERRCODE = 'P0002';
    END IF;

    IF p_moneda = v_inv.moneda_referencia THEN p_tasa_a_ref := 1; END IF;
    IF p_tasa_a_ref IS NULL OR p_tasa_a_ref <= 0 THEN
        RAISE EXCEPTION 'La tasa a la moneda de referencia debe ser > 0' USING ERRCODE = 'P0002';
    END IF;
    v_monto_ref := round(p_monto * p_tasa_a_ref, 2);

    IF v_inv.monto_recibido_ref + v_monto_ref > v_inv.monto_total_ref
       AND NOT p_confirmar_exceso THEN
        RETURN jsonb_build_object('status','requires_confirmation','code','exceso_recepcion',
            'monto_total_ref',v_inv.monto_total_ref,'monto_recibido_ref',v_inv.monto_recibido_ref,
            'monto_nuevo_ref',v_monto_ref);
    END IF;

    INSERT INTO public.fdi_dat_inversion_recepcion (id_inversion, id_operacion, monto_recepcion,
        moneda_recepcion, tasa_a_ref, monto_ref, confirmada_con_exceso, created_by)
    VALUES (p_id_inversion, p_id_operacion, p_monto, p_moneda, p_tasa_a_ref, v_monto_ref,
        v_inv.monto_recibido_ref + v_monto_ref > v_inv.monto_total_ref, auth.uid());

    PERFORM public.fn_fdi_recalcular_inversion(p_id_inversion);
    RETURN jsonb_build_object('status','ok','monto_ref',v_monto_ref);
END;
$$;

-- ---------------------------------------------------------------------------
-- 4) Carril B conoce la compra y rechaza reintentos sobre canceladas
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.fn_fdi_registrar_recepcion(jsonb, jsonb, uuid);

CREATE OR REPLACE FUNCTION public.fn_fdi_registrar_recepcion(
    p_recepcion       jsonb,
    p_fuentes         jsonb,
    p_idempotency_key uuid,
    p_id_compra       bigint DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_tienda    bigint := (p_recepcion->>'p_id_tienda')::bigint;
    v_total     numeric := (p_recepcion->>'p_monto_total')::numeric;
    v_moneda    text := p_recepcion->>'p_moneda_factura';
    v_solicitud jsonb := jsonb_build_object('recepcion', p_recepcion, 'fuentes', p_fuentes);
    v_previa    record;
    v_fuente    jsonb;
    v_producto  jsonb;
    v_saldo     numeric;
    v_monto     numeric;
    v_tasa      numeric;
    v_cubierto  numeric := 0;
    v_inversion bigint;
    v_operacion bigint;
    v_result    jsonb;
    v_vinculo   jsonb;
BEGIN
    IF auth.uid() IS NULL OR NOT COALESCE(public.fn_user_is_gerente_or_superadmin(v_tienda), false)
       OR (p_recepcion->>'p_uuid')::uuid IS DISTINCT FROM auth.uid() THEN
        RAISE EXCEPTION 'Solo gerente o superadmin de la tienda' USING ERRCODE = '42501';
    END IF;

    -- Una recepción con compra pertenece al carril A.
    IF p_id_compra IS NOT NULL THEN
        RAISE EXCEPTION 'Esta recepción viene de la compra %: regístrela desde el carril de compras',
            p_id_compra USING ERRCODE = '22023';
    END IF;

    IF p_idempotency_key IS NULL OR v_total IS NULL OR NOT (v_total > 0 AND v_total < 'Infinity'::numeric)
       OR v_total <> round(v_total, 2) OR v_moneda NOT IN ('USD','CUP','EUR') OR v_moneda IS NULL
       OR p_recepcion->>'p_id_inversion' IS NOT NULL THEN
        RAISE EXCEPTION 'Solicitud de financiación inválida' USING ERRCODE = '22023';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended('fdi-recepcion:' || p_idempotency_key::text, 0));

    SELECT r.id_operacion, r.fdi_solicitud, o.id_tienda, ir.id_inversion, e.estado
      INTO v_previa
    FROM public.app_dat_operacion_recepcion r
    JOIN public.app_dat_operaciones o ON o.id = r.id_operacion
    LEFT JOIN public.fdi_dat_inversion_recepcion ir ON ir.id_operacion = r.id_operacion
    LEFT JOIN LATERAL (
        SELECT est.estado FROM public.app_dat_estado_operacion est
        WHERE est.id_operacion = r.id_operacion ORDER BY est.id DESC LIMIT 1
    ) e ON true
    WHERE r.fdi_idempotency_key = p_idempotency_key;

    IF FOUND THEN
        IF COALESCE(v_previa.estado, 0) IN (3, 4, 5) THEN
            RAISE EXCEPTION 'La recepción con esa clave está cancelada o anulada: genere una clave nueva'
                USING ERRCODE = '22023';
        END IF;
        IF v_previa.id_tienda <> v_tienda OR v_previa.fdi_solicitud IS DISTINCT FROM v_solicitud THEN
            RAISE EXCEPTION 'La clave ya corresponde a otra recepción; revise la operación guardada'
                USING ERRCODE = '22023';
        END IF;
        RETURN jsonb_build_object('status','success','id_operacion',v_previa.id_operacion,
            'id_inversion',v_previa.id_inversion,'duplicada',true);
    END IF;

    IF jsonb_typeof(p_fuentes) IS DISTINCT FROM 'array' OR jsonb_array_length(p_fuentes) = 0 THEN
        RAISE EXCEPTION 'Seleccione fuentes del fondo' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_fuentes) f
               GROUP BY f->>'id_cuenta', f->>'id_medio_pago', f->>'moneda' HAVING count(*) > 1) THEN
        RAISE EXCEPTION 'Fuente del fondo repetida' USING ERRCODE = '22023';
    END IF;
    IF jsonb_typeof(p_recepcion->'p_productos') IS DISTINCT FROM 'array'
       OR jsonb_array_length(p_recepcion->'p_productos') = 0 THEN
        RAISE EXCEPTION 'Debe incluir productos' USING ERRCODE = '22023';
    END IF;

    FOR v_producto IN SELECT * FROM jsonb_array_elements(p_recepcion->'p_productos') LOOP
        IF NOT EXISTS (
            SELECT 1 FROM public.app_dat_layout_almacen l
            JOIN public.app_dat_almacen a ON a.id = l.id_almacen
            WHERE l.id = (v_producto->>'id_ubicacion')::bigint AND a.id_tienda = v_tienda) THEN
            RAISE EXCEPTION 'Ubicación ajena a la tienda' USING ERRCODE = '42501';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM public.app_dat_producto p
                       WHERE p.id = (v_producto->>'id_producto')::bigint AND p.id_tienda = v_tienda)
           OR NOT COALESCE((v_producto->>'cantidad')::numeric > 0
                          AND (v_producto->>'cantidad')::numeric < 'Infinity'::numeric, false)
           OR NOT COALESCE((v_producto->>'precio_unitario')::numeric >= 0
                          AND (v_producto->>'precio_unitario')::numeric < 'Infinity'::numeric, false) THEN
            RAISE EXCEPTION 'Producto de recepción inválido' USING ERRCODE = '22023';
        END IF;
    END LOOP;

    FOR v_fuente IN SELECT * FROM jsonb_array_elements(p_fuentes)
        ORDER BY (value->>'id_cuenta')::bigint, (value->>'id_medio_pago')::smallint, value->>'moneda'
    LOOP
        v_monto := (v_fuente->>'monto')::numeric;
        v_tasa  := (v_fuente->>'tasa_a_ref')::numeric;
        IF v_monto IS NULL OR NOT (v_monto > 0 AND v_monto < 'Infinity'::numeric)
           OR v_monto <> round(v_monto, 2) OR v_tasa IS NULL
           OR NOT (v_tasa > 0 AND v_tasa < 'Infinity'::numeric)
           OR ((v_fuente->>'moneda') = v_moneda AND v_tasa <> 1) THEN
            RAISE EXCEPTION 'Monto o tasa de fuente inválidos' USING ERRCODE = '22023';
        END IF;

        SELECT s.saldo INTO v_saldo FROM public.fdi_dat_saldo s
          JOIN public.fdi_dat_cuenta c ON c.id = s.id_cuenta
          JOIN public.fdi_dat_concepto co ON co.id = c.id_concepto
          JOIN public.app_nom_medio_pago mp ON mp.id = s.id_medio_pago
          WHERE s.id_tienda = v_tienda AND c.id_tienda = v_tienda AND co.id_tienda = v_tienda
            AND c.activo AND co.activo AND mp.es_activo
            AND s.id_cuenta = (v_fuente->>'id_cuenta')::bigint
            AND s.id_medio_pago = (v_fuente->>'id_medio_pago')::smallint
            AND s.moneda = v_fuente->>'moneda'
          FOR UPDATE OF s;

        IF NOT FOUND OR v_saldo < v_monto THEN
            RAISE EXCEPTION 'Saldo insuficiente o fuente inactiva; actualice los saldos del fondo'
                USING ERRCODE = 'P0002';
        END IF;
        v_cubierto := v_cubierto + round(v_monto * v_tasa, 2);
    END LOOP;

    IF v_cubierto <> v_total THEN
        RAISE EXCEPTION 'Las fuentes deben cubrir exactamente el monto de recepción'
            USING ERRCODE = '22023';
    END IF;

    v_result := public.fn_fdi_crear_inversion(
        v_tienda, ('Recepción ' || p_idempotency_key::text)::varchar,
        NULL::text, 'Financiación directa de recepción', v_moneda, p_fuentes, p_idempotency_key);
    IF v_result->>'status' IS DISTINCT FROM 'ok' OR COALESCE((v_result->>'duplicada')::boolean, false) THEN
        RAISE EXCEPTION 'No se pudo crear la financiación de recepción';
    END IF;
    v_inversion := (v_result->>'id_inversion')::bigint;

    UPDATE public.fdi_dat_inversion_fuente SET monto_ref = round(monto * tasa_a_ref, 2)
     WHERE id_inversion = v_inversion;
    UPDATE public.fdi_dat_inversion SET monto_total_ref = v_total WHERE id = v_inversion;

    v_result := public.fn_registrar_recepcion_con_inventario(
        p_entregado_por := p_recepcion->>'p_entregado_por',
        p_id_tienda := v_tienda,
        p_monto_total := v_total,
        p_motivo := (p_recepcion->>'p_motivo')::integer,
        p_observaciones := p_recepcion->>'p_observaciones',
        p_productos := p_recepcion->'p_productos',
        p_recibido_por := p_recepcion->>'p_recibido_por',
        p_uuid := auth.uid(),
        p_moneda_factura := v_moneda,
        p_id_inversion := NULL::bigint,
        p_tasa_inversion := NULL::numeric,
        p_confirmar_exceso_inversion := false);

    IF v_result->>'status' IS DISTINCT FROM 'success' OR v_result->>'id_operacion' IS NULL THEN
        RAISE EXCEPTION 'No se registró la recepción: %', COALESCE(v_result->>'message', v_result::text);
    END IF;
    v_operacion := (v_result->>'id_operacion')::bigint;

    v_vinculo := public.fn_fdi_vincular_recepcion(v_operacion, v_inversion, v_total, v_moneda, 1::numeric, false);
    IF v_vinculo->>'status' IS DISTINCT FROM 'ok' THEN
        RAISE EXCEPTION 'No se vinculó la recepción: %', v_vinculo;
    END IF;

    UPDATE public.app_dat_operacion_recepcion
       SET fdi_idempotency_key = p_idempotency_key, fdi_solicitud = v_solicitud
     WHERE id_operacion = v_operacion;
    UPDATE public.fdi_dat_inversion SET identificador = 'Recepción ' || v_operacion::text
     WHERE id = v_inversion;

    RETURN v_result || jsonb_build_object('id_inversion', v_inversion, 'financiada_fondo', true);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fdi_registrar_recepcion(jsonb, jsonb, uuid, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_registrar_recepcion(jsonb, jsonb, uuid, bigint) TO authenticated;

DO $$
DECLARE v integer;
BEGIN
    SELECT count(*) INTO v FROM pg_constraint
    WHERE conrelid='public.fdi_dat_inversion'::regclass
      AND conname='fdi_dat_inversion_motivo_revision_check'
      AND pg_get_constraintdef(oid) LIKE '%recepcion_cancelada%';
    IF v <> 1 THEN RAISE EXCEPTION 'Falta el motivo recepcion_cancelada'; END IF;

    SELECT count(*) INTO v FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_fdi_registrar_recepcion';
    IF v <> 1 THEN RAISE EXCEPTION 'Quedaron % firmas de fn_fdi_registrar_recepcion', v; END IF;

    SELECT count(*) INTO v FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_fdi_registrar_recepcion' AND p.pronargs = 4;
    IF v <> 1 THEN RAISE EXCEPTION 'La RPC debe tener 4 args (con p_id_compra)'; END IF;
END;
$$;

COMMIT;