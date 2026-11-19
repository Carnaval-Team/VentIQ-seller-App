CREATE OR REPLACE FUNCTION public.fn_cerrar_turno_tpv_monedas(p_id_tpv bigint, p_usuario uuid, p_productos jsonb, p_efectivo_real_por_moneda jsonb, p_observaciones text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_turno   record;
  v_ok      boolean;
  v_cup     numeric;
  v_usd     numeric;
begin
  if p_efectivo_real_por_moneda is null
     or jsonb_typeof(p_efectivo_real_por_moneda) <> 'object' then
    raise exception 'Se esperaba un objeto {"MONEDA": monto} de efectivo real';
  end if;

  select * into v_turno
  from public.app_dat_caja_turno
  where id_tpv = p_id_tpv and estado = 1 and creado_por = p_usuario
  order by fecha_apertura desc
  limit 1;
  if not found then
    return false;
  end if;

  v_cup := coalesce(public.fn_jsonb_monto(p_efectivo_real_por_moneda, 'CUP'), 0);
  v_usd := coalesce(public.fn_jsonb_monto(p_efectivo_real_por_moneda, 'USD'), 0);

  -- Reutiliza la RPC vigente: cierra el turno y las columnas legacy.
  v_ok := public.fn_cerrar_turno_tpv_usd(
            p_id_tpv            := p_id_tpv,
            p_efectivo_real     := v_cup,
            p_usuario           := p_usuario,
            p_productos         := p_productos,
            p_observaciones     := p_observaciones,
            p_efectivo_real_usd := v_usd);
  if not coalesce(v_ok, false) then
    return false;
  end if;

  -- Esperado por divisa = efectivo inicial de esa divisa + pagos EN EFECTIVO de
  -- esa divisa dentro de la ventana del turno (mismo criterio que _v2).
  with pagos as (
    select upper(trim(pv.moneda)) as moneda,
           sum(pv.monto) as efectivo_nativo
    from public.app_dat_operaciones o
    join public.app_dat_operacion_venta ov on ov.id_operacion = o.id
    join public.app_dat_pago_venta pv on pv.id_operacion_venta = ov.id_operacion
    join public.app_nom_medio_pago mp on mp.id = pv.id_medio_pago
    where ov.id_tpv = p_id_tpv
      and o.uuid = p_usuario
      and o.created_at >= v_turno.fecha_apertura
      and mp.es_efectivo and mp.es_activo
      and exists (
        select 1 from public.app_dat_estado_operacion eo
        where eo.id_operacion = o.id and eo.estado = 2
          and eo.id = (select max(eo2.id) from public.app_dat_estado_operacion eo2
                       where eo2.id_operacion = o.id))
    group by 1
  ),
  inicial as (
    select moneda, efectivo_inicial
    from public.app_dat_caja_turno_moneda
    where id_turno = v_turno.id
  ),
  esperado as (
    select coalesce(i.moneda, p.moneda) as moneda,
           coalesce(i.efectivo_inicial, 0) as inicial,
           coalesce(i.efectivo_inicial, 0) + coalesce(p.efectivo_nativo, 0) as esperado
    from inicial i
    full join pagos p on p.moneda = i.moneda
  )
  insert into public.app_dat_caja_turno_moneda
    (id_turno, moneda, efectivo_inicial, efectivo_esperado, efectivo_real)
  select v_turno.id, e.moneda, e.inicial, e.esperado,
         coalesce(public.fn_jsonb_monto(p_efectivo_real_por_moneda, e.moneda), 0)
  from esperado e
  where exists (select 1 from public.monedas m where m.codigo = e.moneda)
  on conflict (id_turno, moneda) do update
    set efectivo_esperado = excluded.efectivo_esperado,
        efectivo_real     = excluded.efectivo_real,
        updated_at        = now();

  return true;
end $function$

