-- ============================================================================
-- fn_registrar_egreso_fondo_caja_v2: egreso a Fondo de Caja con moneda
-- ----------------------------------------------------------------------------
-- Problema (hallazgo C6): fn_registrar_egreso_fondo_caja no recibe moneda.
--   * Registra el egreso con fn_registrar_egreso_offline, que lo deja en la
--     moneda base (CUP): un egreso de 20 USD descontaba 20 CUP del cajón.
--   * Suma p_monto_entrega a la cuenta de Fondo de Caja sin mirar su
--     dep_dat_banco.id_moneda: 20 USD podían sumarse como 20 de una cuenta CUP.
--
-- Esta versión es ADITIVA (la firma de 9 parámetros sigue igual para los
-- clientes viejos). La v2:
--   1. exige que la moneda del egreso sea la de la cuenta de Fondo de Caja
--      (no convierte: el egreso cuenta tal cual en el fondo);
--   2. registra el egreso con fn_registrar_egreso_offline_v2_m01 (con su
--      moneda y C14 EGRESO_SIN_SALDO). No llama al nombre antiguo: en Fase 1
--      el _v2 publicado no recibe el rechazo nuevo (regla de oro).
--   3. recarga el fondo igual que la original (idempotente por id_egreso_origen).
--
-- Requiere: promocion_m01/04_egreso_m01.sql ya aplicado,
-- dep_dat_banco, dep_nom_moneda, dep_dat_saldo, dep_dat_recarga_saldo,
-- dep_hist_saldo. Esta v2 no revalida el saldo del cajón.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_registrar_egreso_fondo_caja_v2(
    p_client_uuid UUID,
    p_idtienda INTEGER,
    p_id_turno BIGINT,
    p_monto_entrega NUMERIC,
    p_nombre_recibe CHARACTER VARYING,
    p_nombre_autoriza CHARACTER VARYING,
    p_motivo_entrega TEXT,
    p_id_medio_pago SMALLINT DEFAULT NULL,
    p_uuid_usuario UUID DEFAULT NULL,
    p_moneda TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
    v_id_egreso BIGINT;
    v_id_banco BIGINT;
    v_moneda_banco TEXT;
    v_moneda TEXT;
    v_id_recarga BIGINT;
    v_saldo_anterior NUMERIC(14,2);
    v_saldo_nuevo NUMERIC(14,2);
BEGIN
    IF p_monto_entrega IS NULL OR p_monto_entrega <= 0 THEN
        RAISE EXCEPTION 'El monto del egreso debe ser mayor que cero';
    END IF;

    v_moneda := upper(trim(coalesce(nullif(p_moneda, ''), 'CUP')));

    SELECT b.id, upper(m.codigo)
      INTO v_id_banco, v_moneda_banco
    FROM public.dep_dat_banco b
    JOIN public.dep_nom_moneda m ON m.id = b.id_moneda
    WHERE b.idtienda = p_idtienda
      AND b.activo = TRUE
      AND b.es_predeterminada_fondo_caja = TRUE;

    IF v_id_banco IS NULL THEN
        RAISE EXCEPTION 'La tienda no tiene una cuenta predeterminada activa de Fondo de Caja';
    END IF;

    IF v_moneda_banco <> v_moneda THEN
        RAISE EXCEPTION
            'La cuenta de Fondo de Caja es en % y el egreso es en %: no se puede contabilizar en el fondo',
            v_moneda_banco, v_moneda;
    END IF;

    PERFORM pg_advisory_xact_lock(
        hashtextextended(p_idtienda::TEXT || ':' || v_id_banco::TEXT, 0)
    );

    v_result := public.fn_registrar_egreso_offline_v2_m01(
        p_client_uuid := p_client_uuid,
        p_id_turno := p_id_turno,
        p_monto_entrega := p_monto_entrega,
        p_nombre_recibe := p_nombre_recibe,
        p_nombre_autoriza := p_nombre_autoriza,
        p_motivo_entrega := p_motivo_entrega,
        p_id_medio_pago := p_id_medio_pago,
        p_uuid_usuario := p_uuid_usuario,
        p_moneda := v_moneda
    );

    IF v_result IS NULL OR COALESCE((v_result->>'success')::BOOLEAN, FALSE) = FALSE THEN
        RAISE EXCEPTION 'No se pudo registrar el egreso: %', COALESCE(v_result->>'message', 'error desconocido');
    END IF;

    v_id_egreso := NULLIF(v_result->>'egreso_id', '')::BIGINT;
    IF v_id_egreso IS NULL THEN
        RAISE EXCEPTION 'El registro del egreso no devolvió su identificador';
    END IF;

    SELECT id INTO v_id_recarga
    FROM public.dep_dat_recarga_saldo
    WHERE id_egreso_origen = v_id_egreso;

    IF v_id_recarga IS NULL THEN
        INSERT INTO public.dep_dat_saldo (idtienda, id_banco, saldo_disponible, updated_at)
        VALUES (p_idtienda, v_id_banco, 0, now())
        ON CONFLICT (idtienda, id_banco) DO NOTHING;

        SELECT saldo_disponible INTO v_saldo_anterior
        FROM public.dep_dat_saldo
        WHERE idtienda = p_idtienda AND id_banco = v_id_banco
        FOR UPDATE;

        v_saldo_nuevo := v_saldo_anterior + p_monto_entrega;

        INSERT INTO public.dep_dat_recarga_saldo (
            idtienda, id_banco, monto, fecha_pago, observacion,
            created_at, id_egreso_origen
        ) VALUES (
            p_idtienda, v_id_banco, p_monto_entrega, CURRENT_DATE,
            'Ingreso desde egreso #' || v_id_egreso || ': ' || p_motivo_entrega,
            now(), v_id_egreso
        ) RETURNING id INTO v_id_recarga;

        UPDATE public.dep_dat_saldo
        SET saldo_disponible = v_saldo_nuevo, updated_at = now()
        WHERE idtienda = p_idtienda AND id_banco = v_id_banco;

        INSERT INTO public.dep_hist_saldo (
            idtienda, id_banco, monto_anterior, monto_nuevo, diferencia,
            tipo_operacion, referencia, id_recarga, created_at
        ) VALUES (
            p_idtienda, v_id_banco, v_saldo_anterior, v_saldo_nuevo,
            p_monto_entrega, 'recarga_egreso',
            'Egreso de caja #' || v_id_egreso, v_id_recarga, now()
        );
    END IF;

    RETURN v_result || jsonb_build_object(
        'recarga_id', v_id_recarga,
        'fondo_caja_aplicado', TRUE,
        'id_banco', v_id_banco,
        'moneda', v_moneda
    );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_registrar_egreso_fondo_caja_v2(
    UUID, INTEGER, BIGINT, NUMERIC, CHARACTER VARYING, CHARACTER VARYING, TEXT, SMALLINT, UUID, TEXT
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_registrar_egreso_fondo_caja_v2(
    UUID, INTEGER, BIGINT, NUMERIC, CHARACTER VARYING, CHARACTER VARYING, TEXT, SMALLINT, UUID, TEXT
) TO authenticated;
