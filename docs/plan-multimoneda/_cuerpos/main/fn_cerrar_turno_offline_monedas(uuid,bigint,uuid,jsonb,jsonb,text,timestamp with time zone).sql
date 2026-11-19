CREATE OR REPLACE FUNCTION public.fn_cerrar_turno_offline_monedas(p_client_uuid uuid, p_id_tpv bigint, p_usuario uuid, p_productos jsonb, p_efectivo_real_por_moneda jsonb, p_observaciones text DEFAULT NULL::text, p_fecha_cierre timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_res      jsonb;
  v_turno_id bigint;
  v_cup      numeric;
  v_usd      numeric;
  v_esperado record;
begin
  if p_efectivo_real_por_moneda is null
     or jsonb_typeof(p_efectivo_real_por_moneda) <> 'object' then
    raise exception 'Se esperaba un objeto {"MONEDA": monto} de efectivo real';
  end if;

  v_cup := coalesce(public.fn_jsonb_monto(p_efectivo_real_por_moneda, 'CUP'), 0);
  v_usd := coalesce(public.fn_jsonb_monto(p_efectivo_real_por_moneda, 'USD'), 0);

  -- Resolver ANTES de cerrar: el resultado de la RPC vigente no trae el turno.
  select ct.id into v_turno_id
  from public.app_dat_caja_turno ct
  where ct.id_tpv = p_id_tpv and ct.estado = 1 and ct.creado_por = p_usuario
  order by ct.fecha_apertura desc
  limit 1;

  v_res := public.fn_cerrar_turno_offline_usd(
    p_client_uuid        := p_client_uuid,
    p_id_tpv             := p_id_tpv,
    p_efectivo_real      := v_cup,
    p_usuario            := p_usuario,
    p_productos          := p_productos,
    p_observaciones      := p_observaciones,
    p_fecha_cierre       := p_fecha_cierre,
    p_efectivo_real_usd  := v_usd);

  if (v_res->>'status') = 'success' and v_turno_id is not null then
    for v_esperado in
      select moneda, esperado from public.fn_esperado_turno_por_moneda(v_turno_id)
    loop
      insert into public.app_dat_caja_turno_moneda
        (id_turno, moneda, efectivo_inicial, efectivo_esperado, efectivo_real)
      values (v_turno_id, v_esperado.moneda,
              coalesce((select m.efectivo_inicial
                        from public.app_dat_caja_turno_moneda m
                        where m.id_turno = v_turno_id
                          and m.moneda = v_esperado.moneda), 0),
              v_esperado.esperado,
              public.fn_jsonb_monto(p_efectivo_real_por_moneda, v_esperado.moneda))
      on conflict (id_turno, moneda) do update
        set efectivo_esperado = excluded.efectivo_esperado,
            efectivo_real     = coalesce(excluded.efectivo_real,
                                         public.app_dat_caja_turno_moneda.efectivo_real),
            updated_at        = now();
    end loop;
  end if;

  return v_res;
end $function$

