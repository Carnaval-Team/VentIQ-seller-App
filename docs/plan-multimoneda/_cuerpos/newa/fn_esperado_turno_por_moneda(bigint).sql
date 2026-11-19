CREATE OR REPLACE FUNCTION public.fn_esperado_turno_por_moneda(p_id_turno bigint)
 RETURNS TABLE(moneda text, esperado numeric)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with turno as (
    select id, id_tpv, creado_por, fecha_apertura,
           coalesce(fecha_cierre, now()) as fecha_fin,
           coalesce(efectivo_inicial, 0) as inicial_cup,
           coalesce(efectivo_inicial_usd, 0) as inicial_usd
    from public.app_dat_caja_turno where id = p_id_turno
  ),
  arqueo as (
    select m.moneda, m.efectivo_inicial
    from public.app_dat_caja_turno_moneda m
    where m.id_turno = p_id_turno
  ),
  pagos as (
    select upper(trim(pv.moneda)) as moneda, sum(pv.monto) as efectivo_nativo
    from turno t
    join public.app_dat_operaciones o
      on o.uuid = t.creado_por and o.created_at >= t.fecha_apertura and o.created_at <= t.fecha_fin
    join public.app_dat_operacion_venta ov on ov.id_operacion = o.id and ov.id_tpv = t.id_tpv
    join public.app_dat_pago_venta pv on pv.id_operacion_venta = ov.id_operacion
    join public.app_nom_medio_pago mp on mp.id = pv.id_medio_pago
    where mp.es_efectivo and mp.es_activo
      and exists (select 1 from public.app_dat_estado_operacion eo
                  where eo.id_operacion = o.id and eo.estado = 2
                    and eo.id = (select max(eo2.id) from public.app_dat_estado_operacion eo2 where eo2.id_operacion = o.id))
    group by 1
  ),
  base as (
    select 'CUP'::text as moneda, coalesce((select a.efectivo_inicial from arqueo a where a.moneda='CUP'),
                                           (select t.inicial_cup from turno t), 0) as inicial
    union all
    select 'USD', coalesce((select a.efectivo_inicial from arqueo a where a.moneda='USD'),
                           (select t.inicial_usd from turno t), 0)
    where coalesce((select a.efectivo_inicial from arqueo a where a.moneda='USD'),
                   (select t.inicial_usd from turno t), 0) <> 0
    union all
    select a.moneda, coalesce(a.efectivo_inicial, 0)
    from arqueo a where a.moneda not in ('CUP','USD')
  )
  select b.moneda, b.inicial + coalesce(p.efectivo_nativo, 0)
  from base b left join pagos p on p.moneda = b.moneda
  union all
  select p.moneda, coalesce(p.efectivo_nativo, 0)
  from pagos p where not exists (select 1 from base b where b.moneda = p.moneda);
$function$

