-- ============================================================================
-- fn_desglose_monedas_turno: alinear cuerpo con newa (C12)
-- ============================================================================
-- Main hoy: md5(LF) = d221a50433bce20d58a8d4b5d3e5d21c
-- Newa:     md5(LF) = b87dab30a8e116f017a042f15c668034
--
-- Diferencia: newa acota ventas con public.fn_operacion_en_turno(...).
-- El C9 del repo (fix_esperado_turno_por_moneda_ventas_offline.sql) aún
-- trae desglose con op_siguiente inline; NO reaplicar ese archivo completo
-- (fn_esperado_turno_por_moneda ya coincide con newa).
--
-- Prerrequisito: public.fn_operacion_en_turno(bigint,bigint,timestamptz)
-- (ya presente en main tras C12).
--
-- Pegar en SQL Editor de main como rol postgres. MCP main = solo lectura.
-- Idempotente: CREATE OR REPLACE conserva grants.
-- ============================================================================

BEGIN;

DO $chk$
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'Ejecutar como postgres (actual: %)', current_user;
  END IF;
  IF to_regprocedure(
       'public.fn_operacion_en_turno(bigint,bigint,timestamp with time zone)'
     ) IS NULL THEN
    RAISE EXCEPTION
      'Falta fn_operacion_en_turno: aplicar antes fix_reportes_turno_ventas_offline.sql';
  END IF;
END
$chk$;

CREATE OR REPLACE FUNCTION public.fn_desglose_monedas_turno(
  p_id_turno bigint,
  p_criterio_resumen boolean
)
RETURNS TABLE(desglose_monedas jsonb, total_base numeric)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  with turno as (
    select ct.id, ct.id_tpv, ct.id_vendedor, ct.creado_por, ct.fecha_apertura
    from public.app_dat_caja_turno ct where ct.id = p_id_turno
  ),
  venta_tipo as (
    select id from public.app_nom_tipo_operacion where lower(denominacion) = 'venta' limit 1
  ),
  pagos as (
    select upper(trim(pv.moneda)) as moneda,
           count(distinct pv.id_operacion_venta) as operaciones,
           sum(pv.monto) as importe_nativo,
           sum(pv.monto * coalesce(pv.tasa_cambio, pv.tasa_usd, 1)) as importe_base,
           sum(pv.monto) filter (where mp.es_efectivo) as efectivo_nativo,
           sum(pv.monto) filter (where not mp.es_efectivo) as digital_nativo,
           min(o.id_tienda) as id_tienda
    from turno t
    join public.app_dat_operaciones o
      on o.created_at >= t.fecha_apertura
     and public.fn_operacion_en_turno(t.id, o.id, o.created_at)
     and o.uuid = case when p_criterio_resumen
                       then (select v.uuid from public.app_dat_vendedor v where v.id = t.id_vendedor)
                       else t.creado_por end
     and (not p_criterio_resumen or o.id_tipo_operacion = (select id from venta_tipo))
    join public.app_dat_operacion_venta ov on ov.id_operacion = o.id and ov.id_tpv = t.id_tpv
    join public.app_dat_pago_venta pv on pv.id_operacion_venta = ov.id_operacion
    join public.app_nom_medio_pago mp on mp.id = pv.id_medio_pago and mp.es_activo
    where exists (select 1 from public.app_dat_estado_operacion eo
                  where eo.id_operacion = o.id and eo.estado = 2
                    and eo.id = (select max(eo2.id) from public.app_dat_estado_operacion eo2 where eo2.id_operacion = o.id))
    group by 1
  ),
  cons as (
    select * from public.fn_moneda_consolidacion((select min(id_tienda) from pagos))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'moneda', p.moneda,
           'operaciones', p.operaciones,
           'importe_nativo', p.importe_nativo,
           'importe_base', p.importe_base,
           'efectivo_nativo', coalesce(p.efectivo_nativo, 0),
           'digital_nativo', coalesce(p.digital_nativo, 0),
           'moneda_consolidacion', c.moneda,
           'importe_consolidado', case when p.moneda = c.moneda
                                       then p.importe_nativo
                                       else p.importe_base * c.tasa_cup end
         ) order by p.importe_base desc), '[]'::jsonb),
         coalesce(sum(p.importe_base), 0)
  from pagos p cross join cons c;
$function$;

DO $ver$
DECLARE
  v_md5 text;
BEGIN
  IF position(
       'fn_operacion_en_turno' in
       pg_get_functiondef('public.fn_desglose_monedas_turno(bigint,boolean)'::regprocedure)
     ) = 0 THEN
    RAISE EXCEPTION 'fn_desglose_monedas_turno no quedó con fn_operacion_en_turno';
  END IF;

  v_md5 := md5(replace(
    pg_get_functiondef('public.fn_desglose_monedas_turno(bigint,boolean)'::regprocedure),
    E'\r\n', E'\n'
  ));
  IF v_md5 <> 'b87dab30a8e116f017a042f15c668034' THEN
    RAISE EXCEPTION
      'md5(LF) inesperado: % (esperado b87dab30a8e116f017a042f15c668034)',
      v_md5;
  END IF;
END
$ver$;

COMMIT;
