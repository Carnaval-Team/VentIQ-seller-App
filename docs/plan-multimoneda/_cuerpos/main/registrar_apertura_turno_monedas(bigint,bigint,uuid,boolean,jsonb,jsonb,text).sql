CREATE OR REPLACE FUNCTION public.registrar_apertura_turno_monedas(p_id_tpv bigint, p_id_vendedor bigint, p_usuario uuid, p_maneja_inventario boolean, p_productos jsonb, p_efectivo_inicial_por_moneda jsonb, p_observaciones text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_operacion_id bigint;
  v_turno_id     bigint;
  v_cup  numeric;
  v_usd  numeric;
begin
  if p_efectivo_inicial_por_moneda is null
     or jsonb_typeof(p_efectivo_inicial_por_moneda) <> 'object' then
    raise exception 'Se esperaba un objeto {"MONEDA": monto} de efectivo inicial';
  end if;

  -- Reutiliza la RPC vigente: escribe el turno y las columnas legacy.
  v_cup := coalesce(public.fn_jsonb_monto(p_efectivo_inicial_por_moneda, 'CUP'), 0);
  v_usd := coalesce(public.fn_jsonb_monto(p_efectivo_inicial_por_moneda, 'USD'), 0);

  v_operacion_id := public.registrar_apertura_turno_usd(
            p_efectivo_inicial      := v_cup,
            p_id_tpv                := p_id_tpv,
            p_id_vendedor           := p_id_vendedor,
            p_usuario               := p_usuario,
            p_maneja_inventario     := p_maneja_inventario,
            p_productos             := p_productos,
            p_observaciones         := p_observaciones,
            p_efectivo_inicial_usd  := v_usd);


  -- La RPC vigente devuelve el id de la OPERACIÓN de apertura, NO el del turno
  -- (la app lo consume como 'operacion_id'). Hay que resolver el turno real
  -- antes de escribir el arqueo por divisa.
  select ct.id into v_turno_id
  from public.app_dat_caja_turno ct
  where ct.id_operacion_apertura = v_operacion_id
  order by ct.id desc
  limit 1;
  if v_turno_id is null then
    select ct.id into v_turno_id from public.app_dat_caja_turno ct
    where ct.id = v_operacion_id limit 1;
  end if;
  if v_turno_id is null then
    raise exception 'No se pudo resolver el turno recién abierto (operacion_apertura=%)', v_operacion_id;
  end if;
  insert into public.app_dat_caja_turno_moneda (id_turno, moneda, efectivo_inicial)
  select v_turno_id, upper(trim(e.key)), public.fn_jsonb_monto(p_efectivo_inicial_por_moneda, e.key)
  from jsonb_each(p_efectivo_inicial_por_moneda) e
  where public.fn_jsonb_monto(p_efectivo_inicial_por_moneda, e.key) is not null
    and exists (select 1 from public.monedas m where m.codigo = upper(trim(e.key)))
  on conflict (id_turno, moneda) do update
    set efectivo_inicial = excluded.efectivo_inicial,
        updated_at = now();

  return v_operacion_id;
end $function$

