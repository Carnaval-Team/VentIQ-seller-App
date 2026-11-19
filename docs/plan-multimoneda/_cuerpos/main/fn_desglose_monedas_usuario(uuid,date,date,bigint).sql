CREATE OR REPLACE FUNCTION public.fn_desglose_monedas_usuario(p_uuid_usuario uuid, p_fecha_desde date, p_fecha_hasta date, p_id_tienda bigint)
 RETURNS TABLE(desglose_monedas jsonb, total_base numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with cons as (select * from public.fn_moneda_consolidacion(p_id_tienda)),
  pagos as (
    select upper(trim(pv.moneda)) as moneda,
           count(distinct pv.id_operacion_venta) as operaciones,
           sum(pv.monto) as importe_nativo,
           sum(pv.monto_cup_equivalente) as importe_base,
           sum(pv.monto) filter (where mp.es_efectivo) as efectivo_nativo,
           sum(pv.monto) filter (where not coalesce(mp.es_efectivo, false)) as digital_nativo
    from public.app_dat_pago_venta pv
    join public.app_dat_operacion_venta ov on ov.id_operacion = pv.id_operacion_venta
    join public.app_dat_operaciones o on o.id = ov.id_operacion
    join public.app_nom_medio_pago mp on mp.id = pv.id_medio_pago
    where (p_uuid_usuario is null or o.uuid = p_uuid_usuario)
      and (p_id_tienda is null or o.id_tienda = p_id_tienda)
      and (p_fecha_desde is null or o.created_at::date >= p_fecha_desde)
      and (p_fecha_hasta is null or o.created_at::date <= p_fecha_hasta)
      -- Mismo criterio que el informe al que acompaña: solo ventas completadas.
      and exists (select 1 from public.app_dat_estado_operacion eo
                  where eo.id_operacion = o.id and eo.estado = 2
                    and eo.id = (select max(eo2.id) from public.app_dat_estado_operacion eo2
                                 where eo2.id_operacion = o.id))
    group by 1
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'moneda', p.moneda,
           'operaciones', p.operaciones,
           'importe_nativo', p.importe_nativo,
           'importe_base', p.importe_base,
           'efectivo_nativo', coalesce(p.efectivo_nativo, 0),
           'digital_nativo', coalesce(p.digital_nativo, 0),
           'tasa_promedio', round(p.importe_base / nullif(p.importe_nativo, 0), 4),
           'moneda_consolidacion', c.moneda,
           'importe_consolidado', case when p.moneda = c.moneda
                                       then p.importe_nativo
                                       else p.importe_base * c.tasa_cup end
         ) order by p.importe_base desc), '[]'::jsonb),
         coalesce(sum(p.importe_base), 0)
  from pagos p cross join cons c;
$function$

