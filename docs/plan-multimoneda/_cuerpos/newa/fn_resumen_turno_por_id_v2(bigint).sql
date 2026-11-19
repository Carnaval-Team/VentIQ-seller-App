CREATE OR REPLACE FUNCTION public.fn_resumen_turno_por_id_v2(p_turno_id bigint)
 RETURNS TABLE(turno_id bigint, tpv character varying, vendedor character varying, fecha_apertura timestamp with time zone, fecha_cierre timestamp with time zone, duracion interval, estado_turno smallint, estado_descripcion character varying, ventas_totales numeric, productos_vendidos numeric, ticket_promedio numeric, efectivo_inicial numeric, efectivo_esperado numeric, efectivo_real numeric, diferencia_efectivo numeric, porcentaje_efectivo numeric, porcentaje_otros numeric, operaciones_totales bigint, operaciones_por_hora numeric, conciliacion_estado character varying, total_egresos_parciales numeric, efectivo_real_ajustado numeric, diferencia_ajustada numeric, desglose_monedas jsonb, total_base numeric)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with base as (select * from public.fn_resumen_turno_por_id(p_turno_id))
  select b.*, d.desglose_monedas, d.total_base
  from base b cross join lateral public.fn_desglose_monedas_turno(b.turno_id, true) d;
$function$

