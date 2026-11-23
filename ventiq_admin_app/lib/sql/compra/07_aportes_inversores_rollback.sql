-- ============================================================================
-- 07_aportes_inversores_rollback.sql — deshace la fase 7
--
-- QUÉ DEJA COMO ESTABA (fase 4):
--   · `fdi_dat_compra_pago.id_cuenta` e `id_medio_pago` vuelven a NOT NULL.
--   · `fdi_dat_compra_pago` pierde `fdi_pago_fuente_check`, la FK del aporte y
--     su índice.
--   · `fn_fdi_compra_pagar` / `_liberar` / `_cancelar` / `_anular` recuperan el
--     cuerpo de 04 (sin rama de aportes).
--   · Se borran los 4 triggers de exclusividad, las 3 RPC de aportes y la
--     tabla `fdi_dat_compra_aporte`.
--
-- HONESTIDAD: no se ejecuta si hay aportes registrados. Un aporte es dinero de
-- un inversor; borrarlo desde un script de rollback sería destruir el rastro.
-- Devuelva o anule primero, o exporte la tabla.
--
-- NO toca `fdi_dat_inversor`, `fdi_dat_inversor_reparto` ni `fdi_dat_saldo`
-- (la fase 7 nunca las modificó).
-- ============================================================================

DO $$
DECLARE
    v_n bigint;
BEGIN
    IF to_regclass('public.fdi_dat_compra_aporte') IS NOT NULL THEN
        EXECUTE 'SELECT count(*) FROM public.fdi_dat_compra_aporte' INTO v_n;
        IF v_n > 0 THEN
            RAISE EXCEPTION '07 rollback: hay % aportes registrados; expórtelos o anúlelos antes de desinstalar',
                v_n USING ERRCODE = '2B000';
        END IF;
    END IF;
    IF to_regclass('public.fdi_dat_compra_pago') IS NOT NULL THEN
        EXECUTE 'SELECT count(*) FROM public.fdi_dat_compra_pago WHERE origen = ''aporte''' INTO v_n;
        IF v_n > 0 THEN
            RAISE EXCEPTION '07 rollback: hay % pagos con origen aporte; no se puede volver a NOT NULL',
                v_n USING ERRCODE = '2B000';
        END IF;
    END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1) Triggers y funciones de apoyo
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_fdi_compra_modo_inmutable ON public.fdi_dat_compra;
DROP TRIGGER IF EXISTS trg_fdi_pago_coherente ON public.fdi_dat_compra_pago;
DROP TRIGGER IF EXISTS trg_fdi_reserva_solo_fondo ON public.fdi_dat_compra_reserva;
DROP TRIGGER IF EXISTS trg_fdi_ajuste_solo_fondo ON public.fdi_dat_compra_ajuste;
DROP TRIGGER IF EXISTS trg_fdi_recepcion_solo_fondo ON public.fdi_dat_compra_recepcion;
DROP TRIGGER IF EXISTS trg_fdi_aporte_inversores ON public.fdi_dat_compra_aporte;

DROP FUNCTION IF EXISTS public.fn_fdi_compra_modo_inmutable();
DROP FUNCTION IF EXISTS public.fn_fdi_pago_coherente();
DROP FUNCTION IF EXISTS public.fn_fdi_reserva_solo_fondo();
DROP FUNCTION IF EXISTS public.fn_fdi_cargo_solo_fondo();
DROP FUNCTION IF EXISTS public.fn_fdi_aporte_validar();

-- ---------------------------------------------------------------------------
-- 2) RPC de aportes
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.fn_fdi_compra_aporte_devolver(bigint, text);
DROP FUNCTION IF EXISTS public.fn_fdi_compra_aporte_registrar(
    bigint, bigint, text, numeric, numeric, text, numeric, text, text, uuid);
DROP FUNCTION IF EXISTS public.fn_fdi_compra_aportes(bigint);

-- ---------------------------------------------------------------------------
-- 3) `fdi_dat_compra_pago` vuelve a exigir cuenta y medio de pago
-- ---------------------------------------------------------------------------
ALTER TABLE public.fdi_dat_compra_pago
    DROP CONSTRAINT IF EXISTS fdi_pago_fuente_check;
ALTER TABLE public.fdi_dat_compra_pago
    DROP CONSTRAINT IF EXISTS fdi_pago_aporte_fk;

DROP INDEX IF EXISTS public.idx_fdi_pago_aporte;

ALTER TABLE public.fdi_dat_compra_pago
    ALTER COLUMN id_cuenta     SET NOT NULL,
    ALTER COLUMN id_medio_pago SET NOT NULL;

-- ---------------------------------------------------------------------------
-- 3b) `fn_fdi_compra_ajuste_agregar` vuelve a su cuerpo de 06d
--     (origen de pago y estado fijos en 'fondo' / 'por_financiar')
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_def   text;
    v_src   text;
    v_pos   integer;
    v_ancla text := 'CASE WHEN v_c.modo_liquidacion = ''inversores'' THEN ''externo'' ELSE ''fondo'' END,
        CASE WHEN v_c.modo_liquidacion = ''inversores'' THEN ''declarado'' ELSE ''por_financiar'' END';
BEGIN
    IF to_regprocedure('public.fn_fdi_compra_ajuste_agregar(bigint,bigint,text,numeric,text,boolean,uuid)') IS NULL THEN
        RETURN; -- 06d tampoco está instalado: nada que restaurar
    END IF;

    v_def := pg_get_functiondef(
        'public.fn_fdi_compra_ajuste_agregar(bigint,bigint,text,numeric,text,boolean,uuid)'::regprocedure);

    v_pos := position(v_ancla in v_def);
    IF v_pos = 0 THEN
        RETURN; -- no trae el parche de la fase 7
    END IF;
    IF position(v_ancla in substr(v_def, v_pos + length(v_ancla))) > 0 THEN
        RAISE EXCEPTION '07 rollback: el ancla del ajuste aparece más de una vez';
    END IF;

    v_src := replace(v_def, v_ancla, '''fondo'', ''por_financiar''');
    EXECUTE v_src;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4) Cuerpos de la fase 4 (sin rama de aportes)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_compra_pagar(
    p_id_compra bigint,
    p_tasa_pago numeric DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_c     record;
    v_r     record;
    v_mov   bigint;
    v_total numeric := 0;
BEGIN
    SELECT * INTO v_c FROM public.fdi_dat_compra WHERE id = p_id_compra FOR UPDATE;
    IF v_c.id IS NULL THEN
        RAISE EXCEPTION 'Compra % no encontrada', p_id_compra USING ERRCODE = 'P0002';
    END IF;
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_is_gerente_or_superadmin(v_c.id_tienda), false) THEN
        RAISE EXCEPTION 'Solo gerente o superadmin' USING ERRCODE = '42501';
    END IF;
    IF v_c.estado = 'pagada' THEN
        RETURN jsonb_build_object('status','ok','duplicada',true,'id_compra',p_id_compra);
    END IF;
    IF v_c.estado <> 'reservada' THEN
        RAISE EXCEPTION 'Solo se paga una compra reservada (actual: %)', v_c.estado
            USING ERRCODE = '22023';
    END IF;

    SELECT COALESCE(sum(monto_eq_total), 0) INTO v_total
    FROM public.fdi_dat_compra_reserva
    WHERE id_compra = p_id_compra AND estado = 'activa';

    IF v_total <> v_c.total_financiado THEN
        RAISE EXCEPTION 'Las reservas cubren % y la compra necesita %', v_total, v_c.total_financiado
            USING ERRCODE = '22023';
    END IF;

    FOR v_r IN
        SELECT * FROM public.fdi_dat_compra_reserva
        WHERE id_compra = p_id_compra AND estado = 'activa'
        ORDER BY id
    LOOP
        v_mov := public._fdi_aplicar_movimiento(
            v_c.id_tienda, v_r.id_cuenta, v_r.id_medio_pago, v_r.moneda,
            -v_r.monto, 'pago_compra',
            p_observacion := 'Pago compra #' || v_c.numero_compra,
            p_id_compra := p_id_compra,
            p_tasa := v_r.tasa_a_total);

        UPDATE public.fdi_dat_compra_reserva
           SET estado = 'consumida', id_movimiento = v_mov, updated_at = now()
         WHERE id = v_r.id;

        INSERT INTO public.fdi_dat_compra_pago (
            id_compra, id_tienda, id_cuenta, id_medio_pago, moneda,
            monto, tasa_a_total, monto_eq_total, origen, id_movimiento, created_by
        ) VALUES (
            p_id_compra, v_c.id_tienda, v_r.id_cuenta, v_r.id_medio_pago, v_r.moneda,
            v_r.monto, v_r.tasa_a_total, v_r.monto_eq_total, 'fondo', v_mov, auth.uid()
        );
    END LOOP;

    UPDATE public.fdi_dat_compra SET estado = 'pagada', updated_at = now()
     WHERE id = p_id_compra;

    INSERT INTO public.fdi_hist_estado_compra
        (id_compra, id_tienda, estado_anterior, estado_nuevo, origen, motivo, created_by)
    VALUES (p_id_compra, v_c.id_tienda, 'reservada', 'pagada', 'automatico',
            'Pago de la compra', auth.uid());

    RETURN jsonb_build_object('status','ok','id_compra',p_id_compra,'estado','pagada',
        'pagado',v_total);
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_fdi_compra_liberar(
    p_id_compra bigint,
    p_motivo    text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_c record;
    v_n integer;
BEGIN
    IF p_motivo IS NULL OR btrim(p_motivo) = '' THEN
        RAISE EXCEPTION 'El motivo es obligatorio' USING ERRCODE = '22023';
    END IF;
    SELECT * INTO v_c FROM public.fdi_dat_compra WHERE id = p_id_compra FOR UPDATE;
    IF v_c.id IS NULL THEN
        RAISE EXCEPTION 'Compra % no encontrada', p_id_compra USING ERRCODE = 'P0002';
    END IF;
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_is_gerente_or_superadmin(v_c.id_tienda), false) THEN
        RAISE EXCEPTION 'Solo gerente o superadmin' USING ERRCODE = '42501';
    END IF;
    IF v_c.estado <> 'reservada' THEN
        RAISE EXCEPTION 'Solo se liberan reservas de una compra reservada (actual: %)', v_c.estado
            USING ERRCODE = '22023';
    END IF;

    UPDATE public.fdi_dat_compra_reserva
       SET estado = 'liberada', updated_at = now()
     WHERE id_compra = p_id_compra AND estado = 'activa';
    GET DIAGNOSTICS v_n = ROW_COUNT;

    UPDATE public.fdi_dat_compra SET estado = 'creada', updated_at = now()
     WHERE id = p_id_compra;

    INSERT INTO public.fdi_hist_estado_compra
        (id_compra, id_tienda, estado_anterior, estado_nuevo, origen, motivo, created_by)
    VALUES (p_id_compra, v_c.id_tienda, 'reservada', 'creada', 'manual', btrim(p_motivo), auth.uid());

    RETURN jsonb_build_object('status','ok','id_compra',p_id_compra,'liberadas',v_n,'estado','creada');
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_fdi_compra_cancelar(p_id_compra bigint, p_motivo text)
RETURNS jsonb
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
    IF v_c.estado NOT IN ('creada','reservada') THEN
        RAISE EXCEPTION 'Solo se cancela una compra creada o reservada (actual: %). Si está pagada, usar anular.',
            v_c.estado USING ERRCODE = '22023';
    END IF;
    IF EXISTS (SELECT 1 FROM public.fdi_dat_compra_recepcion WHERE id_compra = p_id_compra) THEN
        RAISE EXCEPTION 'La compra ya tiene recepciones' USING ERRCODE = '22023';
    END IF;

    UPDATE public.fdi_dat_compra_reserva
       SET estado = 'liberada', updated_at = now()
     WHERE id_compra = p_id_compra AND estado = 'activa';

    UPDATE public.fdi_dat_compra SET estado = 'cancelada', updated_at = now() WHERE id = p_id_compra;

    INSERT INTO public.fdi_hist_estado_compra
        (id_compra, id_tienda, estado_anterior, estado_nuevo, origen, motivo, created_by)
    VALUES (p_id_compra, v_c.id_tienda, v_c.estado, 'cancelada', 'manual', btrim(p_motivo), auth.uid());

    RETURN jsonb_build_object('status','ok','id_compra',p_id_compra,'estado','cancelada');
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_fdi_compra_anular(
    p_id_compra bigint,
    p_motivo    text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_c        record;
    v_p        record;
    v_devuelto numeric := 0;
BEGIN
    IF p_motivo IS NULL OR btrim(p_motivo) = '' THEN
        RAISE EXCEPTION 'El motivo es obligatorio' USING ERRCODE = '22023';
    END IF;
    SELECT * INTO v_c FROM public.fdi_dat_compra WHERE id = p_id_compra FOR UPDATE;
    IF v_c.id IS NULL THEN
        RAISE EXCEPTION 'Compra % no encontrada', p_id_compra USING ERRCODE = 'P0002';
    END IF;
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_is_gerente_or_superadmin(v_c.id_tienda), false) THEN
        RAISE EXCEPTION 'Solo gerente o superadmin' USING ERRCODE = '42501';
    END IF;
    IF v_c.estado = 'anulada' THEN
        RETURN jsonb_build_object('status','ok','duplicada',true,'devuelto',0);
    END IF;
    IF v_c.estado <> 'pagada' THEN
        RAISE EXCEPTION 'Solo se anula una compra pagada (actual: %)', v_c.estado
            USING ERRCODE = '22023';
    END IF;
    IF EXISTS (SELECT 1 FROM public.fdi_dat_compra_recepcion WHERE id_compra = p_id_compra) THEN
        RAISE EXCEPTION 'La compra ya tiene recepciones; no se anula sin resolver el inventario'
            USING ERRCODE = '22023';
    END IF;

    FOR v_p IN SELECT * FROM public.fdi_dat_compra_pago WHERE id_compra = p_id_compra ORDER BY id LOOP
        PERFORM public._fdi_aplicar_movimiento(
            v_c.id_tienda, v_p.id_cuenta, v_p.id_medio_pago, v_p.moneda,
            v_p.monto, 'devolucion_compra',
            p_observacion := 'Anulación compra #' || v_c.numero_compra || '. Motivo: ' || btrim(p_motivo),
            p_id_compra := p_id_compra,
            p_tasa := v_p.tasa_a_total);
        v_devuelto := v_devuelto + v_p.monto;
    END LOOP;

    UPDATE public.fdi_dat_compra SET estado = 'anulada', updated_at = now()
     WHERE id = p_id_compra;

    INSERT INTO public.fdi_hist_estado_compra
        (id_compra, id_tienda, estado_anterior, estado_nuevo, origen, motivo, created_by)
    VALUES (p_id_compra, v_c.id_tienda, 'pagada', 'anulada', 'manual', btrim(p_motivo), auth.uid());

    RETURN jsonb_build_object('status','ok','id_compra',p_id_compra,'estado','anulada',
        'devuelto',v_devuelto);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fdi_compra_pagar(bigint, numeric) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_fdi_compra_liberar(bigint, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_fdi_compra_anular(bigint, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_fdi_compra_cancelar(bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_compra_pagar(bigint, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_fdi_compra_liberar(bigint, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_fdi_compra_anular(bigint, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_fdi_compra_cancelar(bigint, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 5) Tabla
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS public.fdi_dat_compra_aporte;

DO $$
BEGIN
    IF to_regclass('public.fdi_dat_compra_aporte') IS NOT NULL THEN
        RAISE EXCEPTION '07 rollback: la tabla sigue existiendo';
    END IF;
    IF to_regprocedure('public.fn_fdi_compra_aportes(bigint)') IS NOT NULL THEN
        RAISE EXCEPTION '07 rollback: fn_fdi_compra_aportes sigue existiendo';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
                WHERE NOT t.tgisinternal
                  AND t.tgname IN ('trg_fdi_aporte_inversores','trg_fdi_reserva_solo_fondo',
                                   'trg_fdi_pago_coherente','trg_fdi_compra_modo_inmutable',
                                   'trg_fdi_ajuste_solo_fondo','trg_fdi_recepcion_solo_fondo')) THEN
        RAISE EXCEPTION '07 rollback: quedan triggers de la fase 7';
    END IF;
    RAISE NOTICE '07 rollback: fase 7 desinstalada; la fase 4 quedó como estaba.';
END;
$$;