BEGIN;

-- BORRADOR MC-011. NO EJECUTAR en main.
-- Resuelve el precio vigente de mayor id. El USD sale de esa misma fila
-- o del general vigente de esa moneda. No reutiliza un USD de otra vigencia.

SET LOCAL app.m01_r11_resolver_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r11_resolver_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador MC-011: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF to_regprocedure('public.fn_m01_tienda_precio_tpv(bigint,bigint)') IS NULL
       OR to_regprocedure('public.fn_config_tienda_puede_leer(bigint)') IS NULL
       OR to_regclass('public.app_v_precio_venta_base_vigente') IS NULL THEN
        RAISE EXCEPTION 'Falta el vinculo TPV/producto o el precio general vigente';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'public.app_dat_precio_tpv'::regclass
          AND attname = 'precio_venta_usd'
          AND NOT attisdropped
    ) OR to_regprocedure('public.fn_m01_resolver_precio_tpv(bigint,bigint)') IS NOT NULL THEN
        RAISE EXCEPTION 'El resolver de precio TPV ya existe o falta la columna USD';
    END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.fn_m01_resolver_precio_tpv(
    p_id_tpv bigint,
    p_id_producto bigint
)
RETURNS TABLE (
    precio_cup numeric,
    origen_cup text,
    precio_usd numeric,
    origen_usd text,
    id_precio_tpv bigint,
    id_precio_general bigint,
    fecha_desde date
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_tienda bigint;
    v_tpv_id bigint;
    v_tpv_cup numeric;
    v_tpv_usd numeric;
    v_tpv_desde date;
    v_cup numeric;
    v_usd numeric;
    v_general_id bigint;
    v_general_cup numeric;
    v_general_usd numeric;
BEGIN
    IF auth.uid() IS NULL OR p_id_tpv IS NULL OR p_id_producto IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_tienda := public.fn_m01_tienda_precio_tpv(p_id_tpv, p_id_producto);
    IF v_tienda IS NULL
       OR public.fn_config_tienda_puede_leer(v_tienda) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    SELECT t.id, t.precio_venta_cup, t.precio_venta_usd, t.fecha_desde
      INTO v_tpv_id, v_tpv_cup, v_tpv_usd, v_tpv_desde
    FROM public.app_dat_precio_tpv t
    WHERE t.id_tpv = p_id_tpv
      AND t.id_producto = p_id_producto
      AND t.deleted_at IS NULL
      AND t.es_activo
      AND t.fecha_desde <= CURRENT_DATE
      AND (t.fecha_hasta IS NULL OR t.fecha_hasta >= CURRENT_DATE)
    ORDER BY t.id DESC
    LIMIT 1;
    SELECT g.id, g.precio_venta_cup, g.precio_venta_usd
      INTO v_general_id, v_general_cup, v_general_usd
    FROM public.app_v_precio_venta_base_vigente g
    WHERE g.id_producto = p_id_producto;
    IF v_tpv_cup IS NOT NULL THEN
        v_cup := v_tpv_cup;
        origen_cup := 'tpv';
    ELSIF v_general_cup IS NOT NULL AND v_general_cup > 0 THEN
        v_cup := v_general_cup;
        origen_cup := 'general';
    ELSE
        origen_cup := 'no_disponible';
    END IF;
    IF v_tpv_id IS NOT NULL AND v_tpv_usd IS NOT NULL THEN
        v_usd := v_tpv_usd;
        origen_usd := 'tpv';
    ELSIF v_general_usd IS NOT NULL AND v_general_usd > 0 THEN
        v_usd := v_general_usd;
        origen_usd := 'general';
    ELSE
        origen_usd := 'no_disponible';
    END IF;
    precio_cup := v_cup;
    precio_usd := v_usd;
    id_precio_tpv := v_tpv_id;
    id_precio_general := v_general_id;
    fecha_desde := v_tpv_desde;
    RETURN NEXT;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_m01_resolver_precio_tpv(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_resolver_precio_tpv(bigint, bigint) TO authenticated;

COMMIT;
