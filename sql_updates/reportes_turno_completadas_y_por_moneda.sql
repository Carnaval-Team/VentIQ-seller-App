-- ============================================================================
-- Reportes de turno: solo operaciones completadas + resumen por moneda
-- ============================================================================
-- Proyecto: newa (probado). Para main: aplicar con el pase, DESPUES de
-- fix_reportes_turno_ventas_offline.sql (hallazgo C12) y antes de publicar el admin.
--
-- Regla de negocio: para sumar cuentan solo las operaciones completadas (último estado = 2)
-- y las monedas distintas nunca se mezclan: cada importe se muestra en la moneda en que se
-- cobró.
--
-- 1) fn_operacion_completada(operación): último estado de la operación = 2.
-- 2) Las funciones de reporte por turno parcheadas en C12 filtran además por ese estado
--    (una venta cancelada, p. ej. la 137 del turno 21, ya no suma al efectivo). Mismo
--    mecanismo que C12: reemplazos exactos sobre la definición vigente, aborta si el número
--    de ocurrencias no coincide, idempotente.
-- 3) fn_turnos_por_moneda(ids): una fila por turno y moneda con ventas, efectivo, digital,
--    egresos en efectivo, fondo inicial, esperado, contado y diferencia, todo en la moneda
--    nativa. Es la fuente del admin para el cuadre de caja: los escalares de
--    fn_listar_turnos_admin siguen existiendo (contrato intacto) pero suman monedas.
--    SECURITY INVOKER: las tablas de turno, operaciones y pagos tienen RLS, así que solo
--    salen los turnos que el usuario puede ver.
--    Esperado = fondo + efectivo cobrado - egresos no digitales (mismo criterio que
--    fn_esperado_turno_por_moneda y el cierre del TPV).
--
-- No recalcula ventas, pagos ni liquidaciones. Idempotente. Sin tablas nuevas.
-- ============================================================================

BEGIN;

DO $chk$
BEGIN
    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION 'Ejecutar como postgres (actual: %)', current_user;
    END IF;
    IF to_regprocedure('public.fn_operacion_en_turno(bigint,bigint,timestamp with time zone)') IS NULL THEN
        RAISE EXCEPTION 'Falta fn_operacion_en_turno: aplicar antes fix_reportes_turno_ventas_offline.sql';
    END IF;
END
$chk$;

-- 1) Helper ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_operacion_completada(p_id_operacion bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.app_dat_estado_operacion eo
    where eo.id_operacion = p_id_operacion
      and eo.estado = 2
      and eo.id = (select max(eo2.id) from public.app_dat_estado_operacion eo2
                   where eo2.id_operacion = p_id_operacion)
  );
$function$;

REVOKE ALL ON FUNCTION public.fn_operacion_completada(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_operacion_completada(bigint) TO authenticated, service_role;

-- 2) Parche de las funciones de reporte ---------------------------------------
DO $patch$
DECLARE
    v_spec  jsonb := $j$[
      {"sig": "public.fn_listar_turnos_admin(bigint,bigint,bigint,smallint,timestamp with time zone,timestamp with time zone,boolean,text,integer,integer)",
       "reps": [{"old": "AND public.fn_operacion_en_turno(f.id, o.id, o.created_at)",
                 "new": "AND public.fn_operacion_en_turno(f.id, o.id, o.created_at) AND public.fn_operacion_completada(o.id)", "n": 3}]},
      {"sig": "public.fn_resumen_turno_por_id(bigint)",
       "reps": [{"old": "AND public.fn_operacion_en_turno(ct.id, o.id, o.created_at)",
                 "new": "AND public.fn_operacion_en_turno(ct.id, o.id, o.created_at) AND public.fn_operacion_completada(o.id)", "n": 3}]},
      {"sig": "public.fn_resumen_turno_kpi_corregido(bigint)",
       "reps": [{"old": "AND public.fn_operacion_en_turno(ct.id, o.id, o.created_at)",
                 "new": "AND public.fn_operacion_en_turno(ct.id, o.id, o.created_at) AND public.fn_operacion_completada(o.id)", "n": 3}]},
      {"sig": "public.fn_resumen_turno_kpi(bigint,bigint,timestamp with time zone,timestamp with time zone)",
       "reps": [{"old": "AND public.fn_operacion_en_turno(v_turno.id, o.id, o.created_at)",
                 "new": "AND public.fn_operacion_en_turno(v_turno.id, o.id, o.created_at) AND public.fn_operacion_completada(o.id)", "n": 3}]},
      {"sig": "public.fn_productos_vendidos_por_turno(bigint)",
       "reps": [{"old": "AND public.fn_operacion_en_turno(p_id_turno, o.id, o.created_at)",
                 "new": "AND public.fn_operacion_en_turno(p_id_turno, o.id, o.created_at) AND public.fn_operacion_completada(o.id)", "n": 1}]},
      {"sig": "public.fn_productos_vendidos_por_turno_v2(bigint)",
       "reps": [{"old": "AND public.fn_operacion_en_turno(p_id_turno, o.id, o.created_at)",
                 "new": "AND public.fn_operacion_en_turno(p_id_turno, o.id, o.created_at) AND public.fn_operacion_completada(o.id)", "n": 1}]}
    ]$j$;
    v_f     jsonb;
    v_r     jsonb;
    v_oid   regprocedure;
    v_def   text;
    v_old   text;
    v_n     integer;
BEGIN
    FOR v_f IN SELECT * FROM jsonb_array_elements(v_spec) LOOP
        v_oid := to_regprocedure(v_f->>'sig');
        IF v_oid IS NULL THEN
            RAISE EXCEPTION 'Falta la función %', v_f->>'sig';
        END IF;
        v_def := pg_get_functiondef(v_oid);
        IF position('fn_operacion_completada' IN v_def) > 0 THEN
            RAISE NOTICE 'Ya parcheada: %', v_f->>'sig';
            CONTINUE;
        END IF;
        FOR v_r IN SELECT * FROM jsonb_array_elements(v_f->'reps') LOOP
            v_old := v_r->>'old';
            v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
            IF v_n <> (v_r->>'n')::integer THEN
                RAISE EXCEPTION '% : "%" aparece % veces (esperadas %). Aplicar antes fix_reportes_turno_ventas_offline.sql o revisar a mano.',
                    v_f->>'sig', v_old, v_n, v_r->>'n';
            END IF;
            v_def := replace(v_def, v_old, v_r->>'new');
        END LOOP;
        EXECUTE v_def;
    END LOOP;
END
$patch$;

-- 3) Resumen por turno y moneda ------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_turnos_por_moneda(p_ids bigint[])
 RETURNS TABLE(
   id_turno bigint,
   moneda text,
   operaciones bigint,
   ventas_nativo numeric,
   efectivo_nativo numeric,
   digital_nativo numeric,
   egresos_nativo numeric,
   inicial_nativo numeric,
   esperado_nativo numeric,
   real_nativo numeric,
   diferencia_nativo numeric
 )
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with t as (
    select ct.id, ct.id_tpv, ct.creado_por, ct.fecha_apertura,
           ct.id_operacion_apertura as op_apertura,
           coalesce(ct.id_operacion_cierre, (
             select min(n.id_operacion_apertura)
               from public.app_dat_caja_turno n
              where n.id_tpv = ct.id_tpv
                and n.id_vendedor = ct.id_vendedor
                and n.id_operacion_apertura > ct.id_operacion_apertura
           ), 9223372036854775807) as op_hasta,
           coalesce(ct.efectivo_inicial, 0) as inicial_cup,
           coalesce(ct.efectivo_inicial_usd, 0) as inicial_usd
    from public.app_dat_caja_turno ct
    where ct.id = any(p_ids)
  ),
  pagos as (
    select t.id as id_turno,
           upper(trim(pv.moneda)) as moneda,
           count(distinct pv.id_operacion_venta) as operaciones,
           sum(pv.monto) as ventas,
           sum(pv.monto) filter (where mp.es_efectivo) as efectivo,
           sum(pv.monto) filter (where not mp.es_efectivo) as digital
    from t
    join public.app_dat_operacion_venta ov on ov.id_tpv = t.id_tpv
    join public.app_dat_operaciones o
      on o.id = ov.id_operacion
     and o.uuid = t.creado_por
     and o.created_at >= t.fecha_apertura
     and (t.op_apertura is null or (o.id > t.op_apertura and o.id < t.op_hasta))
     and public.fn_operacion_en_turno(t.id, o.id, o.created_at)
     and public.fn_operacion_completada(o.id)
    join public.app_dat_pago_venta pv on pv.id_operacion_venta = ov.id_operacion
    join public.app_nom_medio_pago mp on mp.id = pv.id_medio_pago
    group by 1, 2
  ),
  egresos as (
    select epc.id_turno,
           upper(trim(coalesce(nullif(epc.moneda, ''), 'CUP'))) as moneda,
           sum(epc.monto_entrega) as egreso
    from public.app_dat_entregas_parciales_caja epc
    join t on t.id = epc.id_turno
    left join public.app_nom_medio_pago mp on mp.id = epc.id_medio_pago
    where not coalesce(mp.es_digital, false)
    group by 1, 2
  ),
  arqueo as (
    select m.id_turno, upper(trim(m.moneda)) as moneda, m.efectivo_inicial, m.efectivo_real
    from public.app_dat_caja_turno_moneda m
    join t on t.id = m.id_turno
  ),
  claves as (
    select id_turno, moneda from pagos
    union select id_turno, moneda from egresos
    union select id_turno, moneda from arqueo
  ),
  filas as (
    select c.id_turno, c.moneda,
           coalesce(p.operaciones, 0) as operaciones,
           coalesce(p.ventas, 0) as ventas,
           coalesce(p.efectivo, 0) as efectivo,
           coalesce(p.digital, 0) as digital,
           coalesce(e.egreso, 0) as egreso,
           coalesce(a.efectivo_inicial,
                    case c.moneda when 'CUP' then t.inicial_cup
                                  when 'USD' then t.inicial_usd
                                  else 0 end) as inicial,
           a.efectivo_real as real
    from claves c
    join t on t.id = c.id_turno
    left join pagos p on p.id_turno = c.id_turno and p.moneda = c.moneda
    left join egresos e on e.id_turno = c.id_turno and e.moneda = c.moneda
    left join arqueo a on a.id_turno = c.id_turno and a.moneda = c.moneda
  )
  select f.id_turno, f.moneda, f.operaciones, f.ventas, f.efectivo, f.digital,
         f.egreso, f.inicial,
         f.inicial + f.efectivo - f.egreso as esperado,
         f.real,
         case when f.real is null then null
              else f.real - (f.inicial + f.efectivo - f.egreso) end as diferencia
  from filas f
  where f.moneda <> ''
  order by f.id_turno, f.moneda;
$function$;

REVOKE ALL ON FUNCTION public.fn_turnos_por_moneda(bigint[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_turnos_por_moneda(bigint[]) TO authenticated, service_role;

COMMIT;
