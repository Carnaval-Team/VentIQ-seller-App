-- Gastos del fondo con destino distinto de una inversión pura.
-- Añade el tipo de movimiento `gasto` y la RPC fn_fdi_gasto.

BEGIN;

ALTER TABLE public.fdi_dat_movimiento
  DROP CONSTRAINT IF EXISTS fdi_dat_movimiento_tipo_check;

ALTER TABLE public.fdi_dat_movimiento
  ADD CONSTRAINT fdi_dat_movimiento_tipo_check CHECK ((tipo)::text = ANY ((ARRAY[
    'liquidacion'::character varying,
    'transferencia_salida'::character varying,
    'transferencia_entrada'::character varying,
    'comision_transferencia'::character varying,
    'extraccion_inversion'::character varying,
    'ingreso_manual'::character varying,
    'ajuste'::character varying,
    'ajuste_correccion'::character varying,
    'gasto'::character varying
  ])::text[]));

CREATE OR REPLACE FUNCTION public.fn_fdi_gasto(
    p_id_tienda       bigint,
    p_id_cuenta       bigint,
    p_id_medio_pago   smallint,
    p_moneda          text,
    p_monto           numeric,
    p_destino         text,
    p_motivo          text DEFAULT NULL,
    p_idempotency_key uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_destino text := btrim(COALESCE(p_destino, ''));
    v_motivo  text := NULLIF(btrim(COALESCE(p_motivo, '')), '');
    v_obs     text;
BEGIN
    IF NOT public.fn_user_is_gerente_or_superadmin(p_id_tienda) THEN
        RAISE EXCEPTION 'Solo gerente o superadmin' USING ERRCODE = '42501';
    END IF;
    IF p_monto IS NULL OR p_monto <= 0 THEN
        RAISE EXCEPTION 'El monto del gasto debe ser mayor que 0' USING ERRCODE = 'P0002';
    END IF;
    IF v_destino = '' THEN
        RAISE EXCEPTION 'Indica el destino del gasto' USING ERRCODE = 'P0002';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.fdi_dat_cuenta
        WHERE id = p_id_cuenta AND id_tienda = p_id_tienda AND activo
    ) THEN
        RAISE EXCEPTION 'La cuenta no existe, no es de la tienda o está inactiva'
            USING ERRCODE = 'P0002';
    END IF;
    IF p_idempotency_key IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.fdi_dat_movimiento
        WHERE id_tienda = p_id_tienda
          AND tipo = 'gasto'
          AND observacion LIKE '%idem:' || p_idempotency_key::text
    ) THEN
        RETURN jsonb_build_object('status', 'ok', 'duplicada', true);
    END IF;

    v_obs := 'Destino: ' || v_destino
        || CASE WHEN v_motivo IS NOT NULL THEN ' · ' || v_motivo ELSE '' END
        || CASE WHEN p_idempotency_key IS NOT NULL
                THEN ' · idem:' || p_idempotency_key::text ELSE '' END;

    -- Descuenta del saldo; falla si no alcanza.
    PERFORM public._fdi_aplicar_movimiento(
        p_id_tienda, p_id_cuenta, p_id_medio_pago, p_moneda, -p_monto,
        'gasto',
        p_observacion := v_obs
    );

    RETURN jsonb_build_object('status', 'ok');
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fdi_gasto(
    bigint, bigint, smallint, text, numeric, text, text, uuid
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_fdi_gasto(
    bigint, bigint, smallint, text, numeric, text, text, uuid
) TO authenticated, service_role;

COMMIT;
