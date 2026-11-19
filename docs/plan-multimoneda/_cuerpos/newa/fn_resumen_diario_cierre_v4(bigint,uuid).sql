CREATE OR REPLACE FUNCTION public.fn_resumen_diario_cierre_v4(id_tpv_param bigint DEFAULT NULL::bigint, id_usuario_param uuid DEFAULT NULL::uuid)
 RETURNS TABLE(ventas_totales numeric, efectivo_inicial numeric, efectivo_real numeric, efectivo_esperado numeric, productos_vendidos numeric, ticket_promedio numeric, porcentaje_efectivo numeric, porcentaje_otros numeric, operaciones_totales integer, operaciones_por_hora numeric, promedio_operaciones_por_hora numeric, conciliacion_estado text, efectivo_real_ajustado numeric, diferencia_ajustada numeric, turno_id bigint, fecha_apertura timestamp with time zone, horas_transcurridas numeric, productos_vendidos_base numeric, productos_vendidos_desglose text, ventas_usd numeric, efectivo_usd_esperado numeric, digital_usd numeric, desglose_monedas jsonb, total_base numeric)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with base as (
    select * from public.fn_resumen_diario_cierre_v3(id_tpv_param, id_usuario_param)
  )
  select b.*, d.desglose_monedas, d.total_base
  from base b cross join lateral public.fn_desglose_monedas_turno(b.turno_id, false) d;
$function$

