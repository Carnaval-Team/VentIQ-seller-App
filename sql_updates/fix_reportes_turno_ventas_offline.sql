-- ============================================================================
-- Reportes de turno: pertenencia de la venta al turno por id de operación
-- ============================================================================
-- Proyecto: newa (probado). Para main: aplicar con el pase, DESPUES de
-- fix_esperado_turno_por_moneda_ventas_offline.sql y antes de publicar admin/TPV.
--
-- Problema (hallazgo C11/C12): las ventas hechas offline se crean al sincronizar
-- (created_at = hora de subida) y el cierre offline fija fecha_cierre con la hora del
-- dispositivo. Los reportes que acotan con `created_at <= fecha_cierre` dejan fuera todas
-- las ventas de un turno offline. Turno 21 de newa: fn_resumen_turno_por_id devolvía
-- ventas_totales 0, operaciones 0, efectivo_esperado 0 con 6 ventas (15 200 CUP + 23.10 USD).
--
-- Cambio:
--   1. fn_operacion_en_turno(turno, operacion, created_at): helper STABLE con el criterio
--      ya documentado (fix_reporte_ventas_por_turno_sin_cierre.sql): id > operación de
--      apertura y id < operación de cierre; sin cierre, id < apertura siguiente del mismo
--      TPV y vendedor; sin tope si no hay turno posterior. Un turno sin
--      id_operacion_apertura conserva el rango por fecha.
--   2. Se sustituye SOLO el tope superior por fecha en: fn_listar_turnos_admin,
--      fn_resumen_turno_por_id (y su _v2, que delega), fn_resumen_turno_kpi (y su _v2),
--      fn_resumen_turno_kpi_corregido, fn_productos_vendidos_por_turno y su _v2.
--      El resto de cada función queda igual: se parchea la definición vigente con
--      reemplazos exactos y se aborta si el número de ocurrencias no es el esperado
--      (evita parchear una versión distinta, p. ej. la de main).
--   3. fn_desglose_monedas_turno: la rama de resumen (p_criterio_resumen = true) no tenía
--      ningún tope superior: el desglose de un turno incluía las ventas del vendedor de
--      todos los turnos posteriores. Ahora ambas ramas usan el mismo helper; cambia solo
--      el uuid (vendedor del turno en resumen, creado_por en cierre) y el filtro por tipo
--      venta de la rama resumen.
--
-- No recalcula ventas, pagos ni liquidaciones. Los egresos de estas funciones ya se
-- ligan por id_turno. Idempotente.
-- ============================================================================

BEGIN;

DO $chk$
BEGIN
    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION 'Ejecutar como postgres (actual: %)', current_user;
    END IF;
    IF to_regprocedure('public.fn_desglose_monedas_turno(bigint,boolean)') IS NULL THEN
        RAISE EXCEPTION 'Falta fn_desglose_monedas_turno';
    END IF;
END
$chk$;

-- 1) Helper ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_operacion_en_turno(
    p_id_turno bigint,
    p_id_operacion bigint,
    p_created_at timestamptz
) RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case
           when t.id_operacion_apertura is not null then
             p_id_operacion > t.id_operacion_apertura
             and case
                   when t.id_operacion_cierre is not null
                     then p_id_operacion < t.id_operacion_cierre
                   else p_id_operacion < coalesce((
                          select min(n.id_operacion_apertura)
                            from public.app_dat_caja_turno n
                           where n.id_tpv = t.id_tpv
                             and n.id_vendedor = t.id_vendedor
                             and n.id_operacion_apertura > t.id_operacion_apertura
                        ), 9223372036854775807)
                 end
           else p_created_at >= t.fecha_apertura
                and p_created_at <= coalesce(t.fecha_cierre, now())
         end
  from public.app_dat_caja_turno t
  where t.id = p_id_turno;
$function$;

REVOKE ALL ON FUNCTION public.fn_operacion_en_turno(bigint, bigint, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_operacion_en_turno(bigint, bigint, timestamptz) TO authenticated, service_role;

-- 2) Parche de las funciones de reporte ---------------------------------------
DO $patch$
DECLARE
    v_spec  jsonb := $j$[
      {"sig": "public.fn_listar_turnos_admin(bigint,bigint,bigint,smallint,timestamp with time zone,timestamp with time zone,boolean,text,integer,integer)",
       "reps": [{"old": "AND o.created_at <= COALESCE(f.fecha_cierre, now())",
                 "new": "AND public.fn_operacion_en_turno(f.id, o.id, o.created_at)", "n": 3}]},
      {"sig": "public.fn_resumen_turno_por_id(bigint)",
       "reps": [{"old": "AND (o.created_at <= ct.fecha_cierre OR ct.fecha_cierre IS NULL)",
                 "new": "AND public.fn_operacion_en_turno(ct.id, o.id, o.created_at)", "n": 2},
                {"old": "AND (o.created_at <= COALESCE(ct.fecha_cierre, NOW()))",
                 "new": "AND public.fn_operacion_en_turno(ct.id, o.id, o.created_at)", "n": 1}]},
      {"sig": "public.fn_resumen_turno_kpi_corregido(bigint)",
       "reps": [{"old": "AND (o.created_at <= COALESCE(ct.fecha_cierre, NOW()))",
                 "new": "AND public.fn_operacion_en_turno(ct.id, o.id, o.created_at)", "n": 3}]},
      {"sig": "public.fn_resumen_turno_kpi(bigint,bigint,timestamp with time zone,timestamp with time zone)",
       "reps": [{"old": "AND (v_turno.fecha_cierre IS NULL OR o.created_at <= v_turno.fecha_cierre)",
                 "new": "AND public.fn_operacion_en_turno(v_turno.id, o.id, o.created_at)", "n": 3}]},
      {"sig": "public.fn_productos_vendidos_por_turno(bigint)",
       "reps": [{"old": "AND o.created_at <= ti.fecha_cierre",
                 "new": "AND public.fn_operacion_en_turno(p_id_turno, o.id, o.created_at)", "n": 1}]},
      {"sig": "public.fn_productos_vendidos_por_turno_v2(bigint)",
       "reps": [{"old": "AND o.created_at <= ti.fecha_cierre",
                 "new": "AND public.fn_operacion_en_turno(p_id_turno, o.id, o.created_at)", "n": 1}]}
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
        IF position('fn_operacion_en_turno' IN v_def) > 0 THEN
            RAISE NOTICE 'Ya parcheada: %', v_f->>'sig';
            CONTINUE;
        END IF;
        FOR v_r IN SELECT * FROM jsonb_array_elements(v_f->'reps') LOOP
            v_old := v_r->>'old';
            v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
            IF v_n <> (v_r->>'n')::integer THEN
                RAISE EXCEPTION '% : "%" aparece % veces (esperadas %). La definición no es la que este script parchea; revisar a mano.',
                    v_f->>'sig', v_old, v_n, v_r->>'n';
            END IF;
            v_def := replace(v_def, v_old, v_r->>'new');
        END LOOP;
        EXECUTE v_def;
    END LOOP;
END
$patch$;

-- 3) Desglose por moneda: mismo criterio en las dos ramas -----------------------
CREATE OR REPLACE FUNCTION public.fn_desglose_monedas_turno(p_id_turno bigint, p_criterio_resumen boolean)
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
     -- La venta offline se crea al sincronizar (después de la fecha de cierre del
     -- dispositivo): manda el orden de las operaciones, no la hora de creación.
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

COMMIT;
