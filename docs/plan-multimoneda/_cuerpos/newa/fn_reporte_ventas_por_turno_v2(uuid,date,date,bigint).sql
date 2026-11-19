CREATE OR REPLACE FUNCTION public.fn_reporte_ventas_por_turno_v2(p_uuid_usuario uuid DEFAULT NULL::uuid, p_fecha_desde date DEFAULT NULL::date, p_fecha_hasta date DEFAULT NULL::date, p_id_tienda bigint DEFAULT NULL::bigint)
 RETURNS TABLE(id_turno bigint, id_tpv bigint, tpv_nombre character varying, estado_turno smallint, fecha_apertura timestamp with time zone, fecha_cierre timestamp with time zone, uuid_usuario uuid, nombres character varying, apellidos character varying, nombre_completo character varying, total_ventas bigint, total_productos_vendidos numeric, total_dinero_efectivo numeric, total_dinero_transferencia numeric, total_dinero_general numeric, total_importe_ventas numeric, productos_diferentes_vendidos bigint, primera_venta timestamp with time zone, ultima_venta timestamp with time zone, desglose_monedas jsonb, total_base numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
      with base as (
        select * from public.fn_reporte_ventas_por_turno(
          p_uuid_usuario, p_fecha_desde, p_fecha_hasta, p_id_tienda)
      )
      select b.*, d.desglose_monedas, d.total_base
      from base b
      cross join lateral public.fn_desglose_monedas_turno(b.id_turno, false) d;
    $function$

