BEGIN;

-- BORRADOR MC-011, alta protegida. NO EJECUTAR en main.
-- Inserta una vigencia nueva. El CUP es obligatorio. El USD vacío queda
-- vacío y no se copia de una vigencia anterior. No reescribe filas viejas.

SET LOCAL app.m01_r11_guardar_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r11_guardar_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador MC-011 alta: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF to_regprocedure('public.fn_m01_resolver_precio_tpv(bigint,bigint)') IS NULL
       OR to_regprocedure('public.fn_m01_tienda_precio_tpv(bigint,bigint)') IS NULL
       OR to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta el resolver de precio TPV';
    END IF;
    IF to_regprocedure('public.fn_m01_guardar_precio_tpv(bigint,bigint,numeric,numeric)') IS NOT NULL THEN
        RAISE EXCEPTION 'El alta de precio TPV ya existe';
    END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.fn_m01_guardar_precio_tpv(
    p_id_tpv bigint,
    p_id_producto bigint,
    p_precio_cup numeric,
    p_precio_usd numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_tienda bigint;
    v_id bigint;
    v_cup numeric;
    v_usd numeric;
BEGIN
    IF v_actor IS NULL OR p_id_tpv IS NULL OR p_id_producto IS NULL
       OR p_precio_cup IS NULL OR p_precio_cup <= 0
       OR p_precio_cup = 'NaN'::numeric
       OR (p_precio_usd IS NOT NULL AND (
            p_precio_usd <= 0 OR p_precio_usd = 'NaN'::numeric
       )) THEN
        RAISE EXCEPTION 'Precio invalido' USING ERRCODE = '22023';
    END IF;
    v_tienda := public.fn_m01_tienda_precio_tpv(p_id_tpv, p_id_producto);
    IF v_tienda IS NULL
       OR public.fn_config_tienda_puede_escribir(v_tienda) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    SELECT t.id, t.precio_venta_cup, t.precio_venta_usd
      INTO v_id, v_cup, v_usd
    FROM public.app_dat_precio_tpv t
    WHERE t.id_tpv = p_id_tpv
      AND t.id_producto = p_id_producto
      AND t.deleted_at IS NULL
      AND t.es_activo
      AND t.fecha_desde <= CURRENT_DATE
      AND (t.fecha_hasta IS NULL OR t.fecha_hasta >= CURRENT_DATE)
    ORDER BY t.id DESC
    LIMIT 1;
    IF FOUND
       AND v_cup IS NOT DISTINCT FROM p_precio_cup
       AND v_usd IS NOT DISTINCT FROM p_precio_usd THEN
        RETURN jsonb_build_object(
            'success', true,
            'idempotent', true,
            'id_precio_tpv', v_id
        );
    END IF;
    INSERT INTO public.app_dat_precio_tpv (
        id_producto, id_tpv, precio_venta_cup, precio_venta_usd, fecha_desde, es_activo
    ) VALUES (
        p_id_producto, p_id_tpv, p_precio_cup, p_precio_usd, CURRENT_DATE, true
    )
    RETURNING id INTO v_id;
    RETURN jsonb_build_object(
        'success', true,
        'idempotent', false,
        'id_precio_tpv', v_id
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_m01_guardar_precio_tpv(bigint, bigint, numeric, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_guardar_precio_tpv(bigint, bigint, numeric, numeric) TO authenticated;

COMMIT;
