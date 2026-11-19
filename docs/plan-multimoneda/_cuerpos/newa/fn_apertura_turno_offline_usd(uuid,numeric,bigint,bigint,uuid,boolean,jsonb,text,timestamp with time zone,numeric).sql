CREATE OR REPLACE FUNCTION public.fn_apertura_turno_offline_usd(p_client_uuid uuid, p_efectivo_inicial numeric, p_id_tpv bigint, p_id_vendedor bigint, p_usuario uuid, p_maneja_inventario boolean DEFAULT false, p_productos jsonb DEFAULT '[]'::jsonb, p_observaciones text DEFAULT NULL::text, p_fecha_apertura timestamp with time zone DEFAULT NULL::timestamp with time zone, p_efectivo_inicial_usd numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
    v_result jsonb;
    v_turno_id bigint;
BEGIN
    IF NULLIF(btrim(COALESCE(current_setting('app.m01_caja_extra', true), '')), '') IS NULL THEN
        PERFORM set_config(
            'app.m01_caja_extra',
            jsonb_build_object('efectivo_usd', p_efectivo_inicial_usd)::text,
            true
        );
    END IF;
    v_result := public.fn_apertura_turno_offline(
        p_client_uuid, p_efectivo_inicial, p_id_tpv, p_id_vendedor, p_usuario,
        p_maneja_inventario, p_productos, p_observaciones, p_fecha_apertura
    );
    IF COALESCE((v_result->>'idempotent')::boolean, false) THEN
        RETURN v_result;
    END IF;
    v_turno_id := NULLIF(v_result->>'id_turno', '')::bigint;
    IF v_turno_id IS NOT NULL THEN
        UPDATE public.app_dat_caja_turno
        SET efectivo_inicial_usd = COALESCE(p_efectivo_inicial_usd, 0)
        WHERE id = v_turno_id;
    END IF;
    RETURN v_result;
END;
$function$

