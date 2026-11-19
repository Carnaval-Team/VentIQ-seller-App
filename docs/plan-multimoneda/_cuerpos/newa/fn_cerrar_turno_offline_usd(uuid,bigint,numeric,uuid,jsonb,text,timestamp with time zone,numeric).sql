CREATE OR REPLACE FUNCTION public.fn_cerrar_turno_offline_usd(p_client_uuid uuid, p_id_tpv bigint, p_efectivo_real numeric, p_usuario uuid, p_productos jsonb DEFAULT '[]'::jsonb, p_observaciones text DEFAULT NULL::text, p_fecha_cierre timestamp with time zone DEFAULT NULL::timestamp with time zone, p_efectivo_real_usd numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
    v_result jsonb;
    v_turno_id bigint;
    v_efectivo_esperado_usd numeric := 0;
BEGIN
    IF NULLIF(btrim(COALESCE(current_setting('app.m01_caja_extra', true), '')), '') IS NULL THEN
        PERFORM set_config(
            'app.m01_caja_extra',
            jsonb_build_object('efectivo_usd', p_efectivo_real_usd)::text,
            true
        );
    END IF;
    SELECT id INTO v_turno_id
    FROM public.app_dat_caja_turno
    WHERE id_tpv = p_id_tpv AND estado = 1
    ORDER BY fecha_apertura DESC NULLS LAST
    LIMIT 1;

    v_result := public.fn_cerrar_turno_offline(
        p_client_uuid, p_id_tpv, p_efectivo_real, p_usuario,
        p_productos, p_observaciones, p_fecha_cierre
    );
    IF COALESCE((v_result->>'idempotent')::boolean, false) THEN
        RETURN v_result;
    END IF;

    SELECT COALESCE(SUM(pv.monto), 0) INTO v_efectivo_esperado_usd
    FROM public.app_dat_pago_venta pv
    JOIN public.app_dat_operacion_venta ov ON ov.id_operacion = pv.id_operacion_venta
    JOIN public.app_nom_medio_pago mp ON mp.id = pv.id_medio_pago
    WHERE pv.moneda = 'USD' AND mp.es_efectivo IS TRUE
      AND ov.id_turno_apertura = v_turno_id;

    IF v_turno_id IS NOT NULL AND (v_result->>'status') = 'success' THEN
        UPDATE public.app_dat_caja_turno
        SET efectivo_real_usd = p_efectivo_real_usd,
            diferencia_usd = CASE
                WHEN p_efectivo_real_usd IS NULL THEN NULL
                ELSE p_efectivo_real_usd
                     - (COALESCE(efectivo_inicial_usd, 0) + v_efectivo_esperado_usd)
            END
        WHERE id = v_turno_id;
    END IF;
    RETURN v_result;
END;
$function$

