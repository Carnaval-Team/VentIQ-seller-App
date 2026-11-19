CREATE OR REPLACE FUNCTION public.fn_cerrar_turno_offline_monedas(p_client_uuid uuid, p_id_tpv bigint, p_usuario uuid, p_productos jsonb, p_efectivo_real_por_moneda jsonb, p_observaciones text DEFAULT NULL::text, p_fecha_cierre timestamp with time zone DEFAULT NULL::timestamp with time zone)
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
    v_esperado record;
BEGIN
    IF p_efectivo_real_por_moneda IS NULL
       OR jsonb_typeof(p_efectivo_real_por_moneda) <> 'object' THEN
        RAISE EXCEPTION 'Se esperaba un objeto {"MONEDA": monto} de efectivo real';
    END IF;
    v_cup := COALESCE(public.fn_jsonb_monto(p_efectivo_real_por_moneda, 'CUP'), 0);
    v_usd := COALESCE(public.fn_jsonb_monto(p_efectivo_real_por_moneda, 'USD'), 0);
    PERFORM set_config(
        'app.m01_caja_extra',
        jsonb_build_object(
            'efectivo_por_moneda', p_efectivo_real_por_moneda,
            'efectivo_usd', v_usd
        )::text,
        true
    );
    SELECT ct.id INTO v_turno_id
    FROM public.app_dat_caja_turno ct
    WHERE ct.id_tpv = p_id_tpv AND ct.estado = 1 AND ct.creado_por = p_usuario
    ORDER BY ct.fecha_apertura DESC
    LIMIT 1;
    v_res := public.fn_cerrar_turno_offline_usd(
        p_client_uuid := p_client_uuid,
        p_id_tpv := p_id_tpv,
        p_efectivo_real := v_cup,
        p_usuario := p_usuario,
        p_productos := p_productos,
        p_observaciones := p_observaciones,
        p_fecha_cierre := p_fecha_cierre,
        p_efectivo_real_usd := v_usd
    );
    IF COALESCE((v_res->>'idempotent')::boolean, false) THEN
        RETURN v_res;
    END IF;
    IF (v_res->>'status') = 'success' AND v_turno_id IS NOT NULL THEN
        FOR v_esperado IN
            SELECT moneda, esperado FROM public.fn_esperado_turno_por_moneda(v_turno_id)
        LOOP
            INSERT INTO public.app_dat_caja_turno_moneda
                (id_turno, moneda, efectivo_inicial, efectivo_esperado, efectivo_real)
            VALUES (
                v_turno_id, v_esperado.moneda,
                COALESCE((
                    SELECT m.efectivo_inicial
                    FROM public.app_dat_caja_turno_moneda m
                    WHERE m.id_turno = v_turno_id AND m.moneda = v_esperado.moneda
                ), 0),
                v_esperado.esperado,
                public.fn_jsonb_monto(p_efectivo_real_por_moneda, v_esperado.moneda)
            )
            ON CONFLICT (id_turno, moneda) DO UPDATE
                SET efectivo_esperado = excluded.efectivo_esperado,
                    efectivo_real = COALESCE(
                        excluded.efectivo_real,
                        public.app_dat_caja_turno_moneda.efectivo_real
                    ),
                    updated_at = now();
        END LOOP;
    END IF;
    RETURN v_res;
END;
$function$

