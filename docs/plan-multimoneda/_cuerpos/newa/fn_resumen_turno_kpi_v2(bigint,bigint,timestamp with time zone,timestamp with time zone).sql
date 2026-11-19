CREATE OR REPLACE FUNCTION public.fn_resumen_turno_kpi_v2(p_id_tpv bigint, p_id_vendedor bigint, p_fecha_desde timestamp with time zone, p_fecha_hasta timestamp with time zone)
 RETURNS TABLE(turno_id bigint, tpv character varying, vendedor character varying, fecha_apertura timestamp with time zone, fecha_cierre timestamp with time zone, duracion interval, estado_turno smallint, ventas_totales numeric, productos_vendidos bigint, ticket_promedio numeric, efectivo_inicial numeric, efectivo_esperado numeric, efectivo_real numeric, diferencia_efectivo numeric, porcentaje_efectivo numeric, porcentaje_otros numeric, operaciones_totales bigint, operaciones_por_hora numeric, conciliacion_estado text, desglose_monedas jsonb, total_base numeric)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with base as (
    select * from public.fn_resumen_turno_kpi(p_id_tpv, p_id_vendedor, p_fecha_desde, p_fecha_hasta)
  )
  select b.*, d.desglose_monedas, d.total_base
  from base b cross join lateral public.fn_desglose_monedas_turno(b.turno_id, true) d;
$function$

