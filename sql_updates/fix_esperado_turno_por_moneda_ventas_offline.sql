-- ============================================================================
-- fn_esperado_turno_por_moneda / fn_desglose_monedas_turno: pertenencia de la venta al turno
-- ============================================================================
-- Proyecto: newa (probado). Para main: aplicar con el pase, junto a las demás funciones M01.
--
-- Problema (turno 21 de newa, 20/11/2026, segundo turno del día, completamente offline):
--   Las ventas hechas offline se suben al reconectar, así que su created_at es la hora de la
--   sincronización (14:06:44) y NO la hora de la venta. El cierre offline pone
--   fecha_cierre = hora del cierre en el dispositivo (14:06:05). La función contaba una venta
--   solo si created_at <= fecha_cierre, de modo que TODAS quedaban fuera:
--     * CUP:  efectivo_esperado 0.0 en lugar de 15 200 (diferencia +14 450 en vez de -750).
--     * USD:  no devolvía fila (esperado 0 y sin inicial), así que el trigger y
--             fn_cerrar_turno_offline_monedas nunca copiaron el efectivo_real USD (quedó NULL)
--             y el esperado de 23.10 que había quedado de una evaluación anterior (cuando
--             fecha_cierre aún era now()) no se actualizó.
--   Las ventas, pagos y líneas subieron bien por moneda: el error estaba solo en el cuadre.
--
-- Segundo defecto (mismo turno): fn_esperado_turno_por_moneda tampoco restaba los egresos
--   en efectivo (app_dat_entregas_parciales_caja). El turno 21 tiene un egreso de 750 CUP
--   (id 4, subido bien y con moneda CUP): el esperado correcto es 15 200 - 750 = 14 450, que
--   es justo lo que contó el cajero (diferencia 0, no -750). El TPV ya los descuenta por
--   moneda; ahora el servidor también (egresos no digitales, cada uno en su moneda).
--
-- Cambio: la venta pertenece al turno por rango de id de operación (criterio ya documentado en
-- fix_reporte_ventas_por_turno_sin_cierre.sql):
--   * desde la operación de apertura (id > id_operacion_apertura);
--   * hasta la operación de cierre (id < id_operacion_cierre) si existe; si no, hasta la
--     apertura siguiente del mismo TPV y vendedor; si tampoco, sin tope (turno abierto o en
--     cierre: aún no hay turno posterior);
--   * turno sin id_operacion_apertura: se mantiene el rango por fecha anterior.
--   Misma firma, mismo RETURNS, mismo search_path. CREATE OR REPLACE conserva permisos.
--   fn_desglose_monedas_turno solo cambia en la rama p_criterio_resumen = false (la que usaba
--   la ventana por fecha); la rama de resumen diario queda igual.
--
-- No recalcula ventas, pagos ni liquidaciones: solo el esperado por moneda del cierre.
-- Idempotente.
-- ============================================================================

BEGIN;

DO $chk$
BEGIN
    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION 'Ejecutar como postgres (actual: %)', current_user;
    END IF;
    IF to_regprocedure('public.fn_esperado_turno_por_moneda(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta fn_esperado_turno_por_moneda';
    END IF;
    IF to_regprocedure('public.fn_desglose_monedas_turno(bigint,boolean)') IS NULL THEN
        RAISE EXCEPTION 'Falta fn_desglose_monedas_turno';
    END IF;
END
$chk$;

CREATE OR REPLACE FUNCTION public.fn_esperado_turno_por_moneda(p_id_turno bigint)
 RETURNS TABLE(moneda text, esperado numeric)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with turno as (
    select ct.id, ct.id_tpv, ct.creado_por, ct.fecha_apertura,
           coalesce(ct.fecha_cierre, now()) as fecha_fin,
           ct.id_operacion_apertura as op_apertura,
           ct.id_operacion_cierre as op_cierre,
           -- Primera operación del siguiente turno del mismo vendedor y TPV: tope para
           -- turnos sin operación de cierre.
           (select min(n.id_operacion_apertura)
              from public.app_dat_caja_turno n
             where n.id_tpv = ct.id_tpv
               and n.id_vendedor = ct.id_vendedor
               and n.id_operacion_apertura > ct.id_operacion_apertura) as op_siguiente,
           coalesce(ct.efectivo_inicial, 0) as inicial_cup,
           coalesce(ct.efectivo_inicial_usd, 0) as inicial_usd
    from public.app_dat_caja_turno ct where ct.id = p_id_turno
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
      on o.uuid = t.creado_por
     -- La venta offline se crea al sincronizar (created_at posterior al cierre del
     -- dispositivo): manda el orden de las operaciones, no la hora de creación.
     and case
           when t.op_apertura is not null then
             o.id > t.op_apertura
             and case
                   when t.op_cierre is not null then o.id < t.op_cierre
                   when t.op_siguiente is not null then o.id < t.op_siguiente
                   else true
                 end
           else o.created_at >= t.fecha_apertura and o.created_at <= t.fecha_fin
         end
    join public.app_dat_operacion_venta ov on ov.id_operacion = o.id and ov.id_tpv = t.id_tpv
    join public.app_dat_pago_venta pv on pv.id_operacion_venta = ov.id_operacion
    join public.app_nom_medio_pago mp on mp.id = pv.id_medio_pago
    where mp.es_efectivo and mp.es_activo
      and exists (select 1 from public.app_dat_estado_operacion eo
                  where eo.id_operacion = o.id and eo.estado = 2
                    and eo.id = (select max(eo2.id) from public.app_dat_estado_operacion eo2 where eo2.id_operacion = o.id))
    group by 1
  ),
  -- Egresos del turno que salieron de la caja en efectivo, cada uno en SU moneda
  -- (mismo criterio que el cierre del TPV: solo el medio digital no sale del cajón).
  egresos as (
    select upper(trim(coalesce(nullif(epc.moneda, ''), 'CUP'))) as moneda,
           sum(epc.monto_entrega) as egreso_nativo
    from public.app_dat_entregas_parciales_caja epc
    left join public.app_nom_medio_pago mp on mp.id = epc.id_medio_pago
    where epc.id_turno = p_id_turno
      and not coalesce(mp.es_digital, false)
    group by 1
  ),
  mov as (
    select coalesce(p.moneda, e.moneda) as moneda,
           coalesce(p.efectivo_nativo, 0) - coalesce(e.egreso_nativo, 0) as neto
    from pagos p full join egresos e on e.moneda = p.moneda
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
  select b.moneda, b.inicial + coalesce(m.neto, 0)
  from base b left join mov m on m.moneda = b.moneda
  union all
  select m.moneda, m.neto
  from mov m where not exists (select 1 from base b where b.moneda = m.moneda);
$function$;

CREATE OR REPLACE FUNCTION public.fn_desglose_monedas_turno(p_id_turno bigint, p_criterio_resumen boolean)
 RETURNS TABLE(desglose_monedas jsonb, total_base numeric)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with turno as (
    select ct.id, ct.id_tpv, ct.id_vendedor, ct.creado_por, ct.fecha_apertura,
           coalesce(ct.fecha_cierre, now()) as fecha_fin,
           ct.id_operacion_apertura as op_apertura,
           ct.id_operacion_cierre as op_cierre,
           (select min(n.id_operacion_apertura)
              from public.app_dat_caja_turno n
             where n.id_tpv = ct.id_tpv
               and n.id_vendedor = ct.id_vendedor
               and n.id_operacion_apertura > ct.id_operacion_apertura) as op_siguiente
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
     -- Criterio de turno (no resumen): rango por id de operación; la venta offline
     -- se crea al sincronizar, después de la fecha de cierre del dispositivo.
     and (p_criterio_resumen
          or case
               when t.op_apertura is not null then
                 o.id > t.op_apertura
                 and case
                       when t.op_cierre is not null then o.id < t.op_cierre
                       when t.op_siguiente is not null then o.id < t.op_siguiente
                       else true
                     end
               else o.created_at <= t.fecha_fin
             end)
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
BEGIN
    IF (SELECT prosrc FROM pg_proc
         WHERE oid = to_regprocedure('public.fn_esperado_turno_por_moneda(bigint)'))
       NOT LIKE '%op_siguiente%' THEN
        RAISE EXCEPTION 'fn_esperado_turno_por_moneda no quedó con el criterio nuevo';
    END IF;
    IF (SELECT prosrc FROM pg_proc
         WHERE oid = to_regprocedure('public.fn_desglose_monedas_turno(bigint,boolean)'))
       NOT LIKE '%op_siguiente%' THEN
        RAISE EXCEPTION 'fn_desglose_monedas_turno no quedó con el criterio nuevo';
    END IF;
END
$ver$;

COMMIT;
