CREATE OR REPLACE FUNCTION public.fn_apertura_turno_offline_monedas(p_client_uuid uuid, p_id_tpv bigint, p_id_vendedor bigint, p_usuario uuid, p_maneja_inventario boolean, p_productos jsonb, p_efectivo_inicial_por_moneda jsonb, p_observaciones text DEFAULT NULL::text, p_fecha_apertura timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
    v_res jsonb;
    v_turno_id bigint;
    v_cup numeric;
    v_usd numeric;
BEGIN
    IF p_efectivo_inicial_por_moneda IS NULL
       OR jsonb_typeof(p_efectivo_inicial_por_moneda) <> 'object' THEN
        RAISE EXCEPTION 'Se esperaba un objeto {"MONEDA": monto} de efectivo inicial';
    END IF;
    v_cup := COALESCE(public.fn_jsonb_monto(p_efectivo_inicial_por_moneda, 'CUP'), 0);
    v_usd := COALESCE(public.fn_jsonb_monto(p_efectivo_inicial_por_moneda, 'USD'), 0);
    PERFORM set_config(
        'app.m01_caja_extra',
        jsonb_build_object(
            'efectivo_por_moneda', p_efectivo_inicial_por_moneda,
            'efectivo_usd', v_usd
        )::text,
        true
    );
    v_res := public.fn_apertura_turno_offline_usd(
        p_client_uuid := p_client_uuid,
        p_efectivo_inicial := v_cup,
        p_id_tpv := p_id_tpv,
        p_id_vendedor := p_id_vendedor,
        p_usuario := p_usuario,
        p_maneja_inventario := p_maneja_inventario,
        p_productos := p_productos,
        p_observaciones := p_observaciones,
        p_fecha_apertura := p_fecha_apertura,
        p_efectivo_inicial_usd := v_usd
    );
    IF COALESCE((v_res->>'idempotent')::boolean, false) THEN
        RETURN v_res;
    END IF;
    IF (v_res->>'status') = 'success' THEN
        v_turno_id := NULLIF(v_res->>'id_turno', '')::bigint;
        IF v_turno_id IS NOT NULL THEN
            INSERT INTO public.app_dat_caja_turno_moneda (id_turno, moneda, efectivo_inicial)
            SELECT v_turno_id, upper(btrim(e.key)),
                   public.fn_jsonb_monto(p_efectivo_inicial_por_moneda, e.key)
            FROM jsonb_each(p_efectivo_inicial_por_moneda) e
            WHERE public.fn_jsonb_monto(p_efectivo_inicial_por_moneda, e.key) IS NOT NULL
              AND EXISTS (
                  SELECT 1 FROM public.monedas m WHERE m.codigo = upper(btrim(e.key))
              )
            ON CONFLICT (id_turno, moneda) DO UPDATE
                SET efectivo_inicial = excluded.efectivo_inicial,
                    updated_at = now();
        END IF;
    END IF;
    RETURN v_res;
END;
$function$

