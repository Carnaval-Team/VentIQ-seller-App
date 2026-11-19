CREATE OR REPLACE FUNCTION public.fn_reporte_ventas_por_moneda(p_id_tienda bigint, p_desde date, p_hasta date, p_id_tpv bigint DEFAULT NULL::bigint)
 RETURNS TABLE(moneda text, operaciones bigint, importe_nativo numeric, importe_base numeric, efectivo_nativo numeric, digital_nativo numeric, tasa_promedio numeric, moneda_consolidacion text, importe_consolidado numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with cons as (select * from public.fn_moneda_consolidacion(p_id_tienda)),
  agg as (
    select upper(trim(pv.moneda)) as moneda,
           count(distinct pv.id_operacion_venta) as operaciones,
           sum(pv.monto) as importe_nativo,
           sum(pv.monto_cup_equivalente) as importe_base,
           sum(pv.monto) filter (where mp.es_efectivo) as efectivo_nativo,
           sum(pv.monto) filter (where not coalesce(mp.es_efectivo, false)) as digital_nativo,
           round(sum(pv.monto_cup_equivalente) / nullif(sum(pv.monto), 0), 4) as tasa_promedio
    from public.app_dat_pago_venta pv
    join public.app_dat_operacion_venta ov on ov.id_operacion = pv.id_operacion_venta
    join public.app_dat_operaciones o on o.id = ov.id_operacion
    join public.app_nom_medio_pago mp on mp.id = pv.id_medio_pago
    where o.id_tienda = p_id_tienda
      and o.created_at::date between p_desde and p_hasta
      and (p_id_tpv is null or ov.id_tpv = p_id_tpv)
      -- Solo ventas COMPLETADAS. Sin esto el reporte cuenta pagos de
      -- operaciones abiertas (último estado <> 2) y deja de cuadrar con los
      -- totales del resto de informes, que sí filtran así.
      and exists (select 1 from public.app_dat_estado_operacion eo
                  where eo.id_operacion = o.id and eo.estado = 2
                    and eo.id = (select max(eo2.id) from public.app_dat_estado_operacion eo2
                                 where eo2.id_operacion = o.id))
    group by 1
  )
  select a.moneda,
         a.operaciones,
         a.importe_nativo,
         a.importe_base,
         a.efectivo_nativo,
         a.digital_nativo,
         a.tasa_promedio,
         c.moneda::text,
         case when a.moneda = c.moneda
              then a.importe_nativo            -- exacto: es la divisa que se cobró
              else a.importe_base * c.tasa_cup -- aproximado: cambio de hoy
         end::numeric
  from agg a cross join cons c
  order by a.importe_base desc;
$function$

