BEGIN;

-- BORRADOR MC-024. NO EJECUTAR en main.
-- Calcula la línea con la misma regla que el cliente y valida el snapshot
-- recibido. No consulta el precio vigente ni lo escribe encima del snapshot.

SET LOCAL app.m01_r13_calcular_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r13_calcular_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador MC-024: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF to_regprocedure('public.fn_m01_calcular_linea(jsonb)') IS NOT NULL
       OR to_regprocedure('public.fn_m01_validar_linea_v1(jsonb)') IS NOT NULL THEN
        RAISE EXCEPTION 'El calculador de linea v1 ya existe';
    END IF;
END;
$preflight$;

CREATE FUNCTION public.fn_m01_calcular_linea(p_linea jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_moneda text := p_linea->>'currency';
    v_tipo text := COALESCE(p_linea->>'automatic_type', 'none');
    v_cantidad numeric;
    v_precio numeric;
    v_auto numeric;
    v_manual numeric;
    v_tasa numeric;
    v_antes numeric;
    v_unit numeric;
    v_bruto numeric;
    v_previo numeric;
    v_nominal numeric;
    v_neto numeric;
    v_cup numeric;
BEGIN
    IF p_linea IS NULL OR jsonb_typeof(p_linea) IS DISTINCT FROM 'object' THEN
        RETURN jsonb_build_object('status', 'error', 'error_code', 'INVALID_DECIMAL');
    END IF;
    IF v_moneda IS DISTINCT FROM 'CUP' AND v_moneda IS DISTINCT FROM 'USD' THEN
        RETURN jsonb_build_object('status', 'error', 'error_code', 'UNSUPPORTED_CURRENCY');
    END IF;
    IF jsonb_typeof(p_linea->'quantity') IS DISTINCT FROM 'string'
       OR jsonb_typeof(p_linea->'unit_price') IS DISTINCT FROM 'string'
       OR jsonb_typeof(p_linea->'automatic_value') IS DISTINCT FROM 'string'
       OR jsonb_typeof(p_linea->'manual_unit_discount') IS DISTINCT FROM 'string'
       OR jsonb_typeof(p_linea->'rate_cup') IS DISTINCT FROM 'string' THEN
        RETURN jsonb_build_object('status', 'error', 'error_code', 'DECIMAL_STRING_REQUIRED');
    END IF;
    BEGIN
        v_cantidad := (p_linea->>'quantity')::numeric;
        v_precio := (p_linea->>'unit_price')::numeric;
        v_auto := (p_linea->>'automatic_value')::numeric;
        v_manual := (p_linea->>'manual_unit_discount')::numeric;
        v_tasa := (p_linea->>'rate_cup')::numeric;
    EXCEPTION
        WHEN invalid_text_representation OR numeric_value_out_of_range THEN
            RETURN jsonb_build_object('status', 'error', 'error_code', 'INVALID_DECIMAL');
    END;
    IF v_cantidad::text = 'NaN' OR v_precio::text = 'NaN' OR v_auto::text = 'NaN'
       OR v_manual::text = 'NaN' OR v_tasa::text = 'NaN'
       OR v_manual < 0 OR v_auto < 0 OR v_cantidad <= 0 THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'error_code', CASE WHEN v_cantidad <= 0 THEN 'INVALID_QUANTITY' ELSE 'INVALID_DECIMAL' END
        );
    END IF;
    IF v_precio <= 0 THEN
        RETURN jsonb_build_object('status', 'error', 'error_code', 'NATIVE_PRICE_UNAVAILABLE');
    END IF;
    IF v_moneda = 'CUP' AND v_tasa <> 1 THEN
        RETURN jsonb_build_object('status', 'error', 'error_code', 'INVALID_DECIMAL');
    END IF;
    IF v_moneda = 'USD' AND v_tasa <= 0 THEN
        RETURN jsonb_build_object('status', 'error', 'error_code', 'SNAPSHOT_EVIDENCE_REQUIRED');
    END IF;
    IF v_tipo IN ('discount_percent', 'surcharge_percent')
       AND (v_auto > 100 OR v_auto <> trunc(v_auto)) THEN
        RETURN jsonb_build_object('status', 'error', 'error_code', 'INVALID_DECIMAL');
    END IF;
    v_antes := CASE v_tipo
        WHEN 'none' THEN v_precio
        WHEN 'discount_percent' THEN v_precio * (1 - v_auto / 100)
        WHEN 'discount_unit' THEN v_precio - v_auto
        WHEN 'surcharge_percent' THEN v_precio * (1 + v_auto / 100)
        WHEN 'surcharge_unit' THEN v_precio + v_auto
        ELSE NULL
    END;
    IF v_antes IS NULL OR v_antes < v_manual THEN
        RETURN jsonb_build_object('status', 'error', 'error_code', 'INVALID_DECIMAL');
    END IF;
    v_unit := v_antes - v_manual;
    v_bruto := round(v_cantidad * v_precio, 2);
    v_previo := round(v_cantidad * v_antes, 2);
    v_nominal := v_cantidad * v_manual;
    v_neto := round(v_cantidad * v_unit, 2);
    v_cup := round(v_neto * v_tasa, 2);
    RETURN jsonb_build_object(
        'status', 'success',
        'unit_net', v_unit,
        'line_gross', v_bruto,
        'subtotal_before_manual', v_previo,
        'manual_nominal', v_nominal,
        'line_net', v_neto,
        'cup_net', v_cup,
        'rounding_delta', v_neto - (v_cantidad * v_unit),
        'es_gratuidad', v_neto = 0,
        'unit_before_manual', v_antes,
        'rate_cup', v_tasa
    );
END;
$function$;

CREATE FUNCTION public.fn_m01_validar_linea_v1(p_linea jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_moneda text := p_linea->>'moneda_venta';
    v_precio text := p_linea #>> '{snapshot_precio,valor_publicado}';
    v_tasa text := p_linea #>> '{snapshot_tasa,valor_publicado}';
    v_ajuste jsonb := COALESCE(p_linea->'snapshot_ajustes_automaticos', '[]'::jsonb);
    v_tipo text := 'none';
    v_valor text := '0';
    v_calc jsonb;
BEGIN
    IF jsonb_typeof(p_linea->'cantidad') IS DISTINCT FROM 'string'
       OR jsonb_typeof(p_linea #> '{snapshot_precio,valor_publicado}') IS DISTINCT FROM 'string'
       OR (
            p_linea ? 'precio_unitario_nativo'
            AND jsonb_typeof(p_linea->'precio_unitario_nativo') IS DISTINCT FROM 'string'
       ) THEN
        RETURN jsonb_build_object('status', 'error', 'error_code', 'DECIMAL_STRING_REQUIRED');
    END IF;
    IF v_moneda = 'USD'
       AND (p_linea #>> '{snapshot_tasa,evidencia_publicacion}') IS NULL THEN
        RETURN jsonb_build_object('status', 'error', 'error_code', 'SNAPSHOT_EVIDENCE_REQUIRED');
    END IF;
    IF v_moneda = 'CUP' AND v_tasa IS NULL THEN
        v_tasa := '1';
    END IF;
    IF jsonb_typeof(v_ajuste) = 'array' AND jsonb_array_length(v_ajuste) > 0 THEN
        v_tipo := COALESCE(v_ajuste->0->>'tipo', 'none');
        v_valor := COALESCE(v_ajuste->0->>'valor', '0');
    END IF;
    IF p_linea->>'precio_unitario_nativo' IS NOT NULL
       AND p_linea->>'precio_unitario_nativo' IS DISTINCT FROM v_precio THEN
        RETURN jsonb_build_object('status', 'error', 'error_code', 'SNAPSHOT_INVALID');
    END IF;
    v_calc := public.fn_m01_calcular_linea(jsonb_build_object(
        'currency', v_moneda,
        'quantity', p_linea->>'cantidad',
        'unit_price', v_precio,
        'automatic_type', v_tipo,
        'automatic_value', v_valor,
        'manual_unit_discount', COALESCE(p_linea->>'descuento_manual_unitario_nativo', '0'),
        'rate_cup', v_tasa
    ));
    IF v_calc->>'status' IS DISTINCT FROM 'success' THEN
        RETURN v_calc;
    END IF;
    IF p_linea->>'importe_neto_nativo' IS NOT NULL
       AND (p_linea->>'importe_neto_nativo')::numeric IS DISTINCT FROM (v_calc->>'line_net')::numeric THEN
        RETURN jsonb_build_object('status', 'error', 'error_code', 'SNAPSHOT_INVALID');
    END IF;
    RETURN v_calc || jsonb_build_object('snapshot_aceptado', true);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_m01_calcular_linea(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_m01_validar_linea_v1(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_calcular_linea(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_m01_validar_linea_v1(jsonb) TO authenticated;

COMMIT;
