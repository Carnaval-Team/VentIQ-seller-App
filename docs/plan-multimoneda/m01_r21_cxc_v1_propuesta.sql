BEGIN;

-- BORRADOR MC-042 y MC-043. NO EJECUTAR en main.
-- La deuda nueva es una fila por linea y moneda. No suma CUP con USD.
-- El primer cobro fija el medio. Uno posterior tiene que usar el mismo.
-- El flag apagado rechaza el alta antes de escribir.

SET LOCAL app.m01_r21_cxc_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r21_cxc_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador MC-042: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF to_regclass('public.app_dat_obligacion_linea_v1') IS NOT NULL THEN
        RAISE EXCEPTION 'La obligacion v1 ya existe';
    END IF;
END;
$preflight$;

CREATE TABLE public.app_dat_obligacion_linea_v1 (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_tienda bigint NOT NULL,
    id_cliente bigint,
    id_operacion bigint NOT NULL,
    id_linea_cliente uuid NOT NULL,
    moneda text NOT NULL,
    monto_nativo numeric NOT NULL,
    saldo_nativo numeric NOT NULL,
    id_medio_pago smallint,
    version_monetaria text NOT NULL DEFAULT 'producto-v1',
    created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    CONSTRAINT m01_obligacion_moneda CHECK (moneda IN ('CUP', 'USD')),
    CONSTRAINT m01_obligacion_version CHECK (version_monetaria = 'producto-v1'),
    CONSTRAINT m01_obligacion_saldo CHECK (saldo_nativo >= 0 AND saldo_nativo <= monto_nativo)
);

CREATE UNIQUE INDEX m01_obligacion_linea
    ON public.app_dat_obligacion_linea_v1 (id_linea_cliente);

ALTER TABLE public.app_dat_obligacion_linea_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_dat_obligacion_linea_v1 FORCE ROW LEVEL SECURITY;

CREATE POLICY app_dat_obligacion_linea_v1_select
    ON public.app_dat_obligacion_linea_v1
    FOR SELECT TO authenticated
    USING (public.fn_config_tienda_puede_leer(id_tienda));

CREATE POLICY app_dat_obligacion_linea_v1_sin_escritura
    ON public.app_dat_obligacion_linea_v1
    FOR ALL TO authenticated
    USING (false)
    WITH CHECK (false);

CREATE FUNCTION public.fn_m01_cxc_registrar_v1(p_solicitud jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_tienda bigint;
    v_flag boolean;
    v_id bigint;
BEGIN
    IF v_actor IS NULL OR p_solicitud->>'version_monetaria' IS DISTINCT FROM 'producto-v1' THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_tienda := (p_solicitud->>'id_tienda')::bigint;
    IF public.fn_config_tienda_puede_leer(v_tienda) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    SELECT permitir_moneda_por_producto INTO v_flag
    FROM public.app_dat_configuracion_tienda
    WHERE id_tienda = v_tienda;
    IF v_flag IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Activacion de moneda por producto no autorizada' USING ERRCODE = '42501';
    END IF;
    IF p_solicitud->>'moneda' NOT IN ('CUP', 'USD') THEN
        RAISE EXCEPTION 'UNSUPPORTED_CURRENCY' USING ERRCODE = '22023';
    END IF;
    INSERT INTO public.app_dat_obligacion_linea_v1 (
        id_tienda, id_cliente, id_operacion, id_linea_cliente,
        moneda, monto_nativo, saldo_nativo
    ) VALUES (
        v_tienda,
        NULLIF(p_solicitud->>'id_cliente', '')::bigint,
        (p_solicitud->>'id_operacion')::bigint,
        (p_solicitud->>'id_linea_cliente')::uuid,
        p_solicitud->>'moneda',
        (p_solicitud->>'monto_nativo')::numeric,
        (p_solicitud->>'monto_nativo')::numeric
    ) RETURNING id INTO v_id;
    RETURN jsonb_build_object('status', 'success', 'id_obligacion', v_id);
END;
$function$;

CREATE FUNCTION public.fn_m01_cxc_saldo_v1(p_id_cliente bigint)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog
AS $function$
    SELECT COALESCE(jsonb_agg(fila.dato), '[]'::jsonb)
    FROM (
        SELECT jsonb_build_object(
            'moneda', o.moneda,
            'saldo_nativo', sum(o.saldo_nativo)
        ) AS dato
        FROM public.app_dat_obligacion_linea_v1 o
        WHERE o.id_cliente = p_id_cliente
          AND o.version_monetaria = 'producto-v1'
        GROUP BY o.moneda
    ) fila;
$function$;

CREATE FUNCTION public.fn_m01_cxc_liquidar_v1(p_solicitud jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_fila public.app_dat_obligacion_linea_v1%ROWTYPE;
    v_monto numeric;
    v_medio smallint;
BEGIN
    IF v_actor IS NULL OR p_solicitud->>'version_monetaria' IS DISTINCT FROM 'producto-v1' THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_monto := (p_solicitud->>'monto_nativo')::numeric;
    v_medio := (p_solicitud->>'id_medio_pago')::smallint;
    SELECT * INTO v_fila
    FROM public.app_dat_obligacion_linea_v1
    WHERE id_linea_cliente = (p_solicitud->>'id_linea_cliente')::uuid
    FOR UPDATE;
    IF NOT FOUND OR v_monto IS NULL OR v_monto <= 0 THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF public.fn_config_tienda_puede_leer(v_fila.id_tienda) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF p_solicitud->>'moneda' IS DISTINCT FROM v_fila.moneda THEN
        RAISE EXCEPTION 'MONEDA_DISTINTA' USING ERRCODE = '23514';
    END IF;
    IF v_fila.id_medio_pago IS NOT NULL AND v_fila.id_medio_pago IS DISTINCT FROM v_medio THEN
        RAISE EXCEPTION 'MEDIO_DISTINTO' USING ERRCODE = '23514';
    END IF;
    IF v_monto > v_fila.saldo_nativo THEN
        RAISE EXCEPTION 'EXCEDE_SALDO' USING ERRCODE = '23514';
    END IF;
    UPDATE public.app_dat_obligacion_linea_v1
    SET saldo_nativo = saldo_nativo - v_monto,
        id_medio_pago = COALESCE(id_medio_pago, v_medio)
    WHERE id = v_fila.id;
    RETURN jsonb_build_object(
        'status', 'success',
        'moneda', v_fila.moneda,
        'saldo_nativo', v_fila.saldo_nativo - v_monto
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_m01_cxc_registrar_v1(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_m01_cxc_saldo_v1(bigint) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_m01_cxc_liquidar_v1(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_cxc_registrar_v1(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_m01_cxc_saldo_v1(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_m01_cxc_liquidar_v1(jsonb) TO authenticated;

COMMIT;
