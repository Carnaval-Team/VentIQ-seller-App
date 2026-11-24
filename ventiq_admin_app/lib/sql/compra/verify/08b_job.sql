-- ============================================================================
-- verify/08b_job.sql — Fase 8b: la conciliación corre sola
--
-- REQUIERE: 08b_conciliacion_job.sql aplicado en `newa`.
--
-- SOLO LECTURA y UNA sola sentencia (README, regla 8): el resumen va como fila
-- UNION ALL con n = 99.
--
--   n=1  la bitácora existe con sus columnas
--   n=2  RLS activa y una sola política, SELECT, para authenticated
--   n=3  las 2 RPC existen, son SECURITY DEFINER y el job no lo puede lanzar un
--        usuario normal (`authenticated` sin EXECUTE en `_registrar`)
--   n=4  el job `fdi-conciliacion-diaria` está programado a las 03:00
--   n=5  la última corrida de cada tienda no dejó descuadres
--   n=6  `diferencia_total` guardada = la que se deduce de su `detalle`
--   n=7  no quedan corridas de más de 90 días (la poda funciona)
--   n=8  R1 sigue viva y sin cambios de firma
--   n=9  (informativa) volumen de la bitácora
--   n=99 resumen
-- ============================================================================

with

ultimas as (
    select e.*
      from public.fdi_dat_conciliacion_ejecucion e
      join (select id_tienda, max(ejecutada_at) as momento
              from public.fdi_dat_conciliacion_ejecucion
             group by id_tienda) u
        on u.id_tienda = e.id_tienda and u.momento = e.ejecutada_at
),

recalculado as (
    select e.id,
           round(coalesce(sum(
               abs(coalesce((f ->> 'dif_saldo_vs_mov')::numeric, 0))
             + abs(coalesce((f ->> 'dif_saldo_vs_ultimo')::numeric, 0))), 0), 2) as dif
      from public.fdi_dat_conciliacion_ejecucion e
      left join lateral jsonb_array_elements(coalesce(e.detalle -> 'filas', '[]'::jsonb)) f on true
     group by e.id
),

base as (

  select 1 as n, 'tabla_bitacora' as chequeo,
    'fdi_dat_conciliacion_ejecucion con sus 8 columnas' as esperado,
    (select count(*)::text from information_schema.columns
      where table_schema = 'public' and table_name = 'fdi_dat_conciliacion_ejecucion'
        and column_name in ('id','id_tienda','ejecutada_at','claves','descuadres',
                            'diferencia_total','origen','detalle')) || ' de 8' as actual,
    (select count(*) = 8 from information_schema.columns
      where table_schema = 'public' and table_name = 'fdi_dat_conciliacion_ejecucion'
        and column_name in ('id','id_tienda','ejecutada_at','claves','descuadres',
                            'diferencia_total','origen','detalle')) as ok

  union all
  select 2, 'rls_solo_select',
    'RLS activa y 1 política SELECT',
    coalesce((select relrowsecurity::text from pg_class
               where oid = 'public.fdi_dat_conciliacion_ejecucion'::regclass), 'falta')
      || ' / ' || coalesce((select count(*)::text from pg_policies
                             where schemaname = 'public'
                               and tablename = 'fdi_dat_conciliacion_ejecucion'), '0') || ' política(s)',
    coalesce((select relrowsecurity from pg_class
               where oid = 'public.fdi_dat_conciliacion_ejecucion'::regclass), false)
    and (select count(*) = 1 from pg_policies
          where schemaname = 'public' and tablename = 'fdi_dat_conciliacion_ejecucion'
            and cmd = 'SELECT')

  union all
  select 3, 'rpcs_y_permisos',
    '2 RPC definer; el job no lo lanza authenticated',
    coalesce((select count(*)::text from pg_proc p
               where p.oid in ('public.fn_fdi_conciliacion_registrar()'::regprocedure,
                               'public.fn_fdi_conciliacion_ultima(bigint)'::regprocedure)
                 and p.prosecdef), '0') || ' de 2 definer',
    (select count(*) = 2 from pg_proc p
      where p.oid in ('public.fn_fdi_conciliacion_registrar()'::regprocedure,
                      'public.fn_fdi_conciliacion_ultima(bigint)'::regprocedure)
        and p.prosecdef)
    and not has_function_privilege('authenticated', 'public.fn_fdi_conciliacion_registrar()', 'EXECUTE')
    and has_function_privilege('authenticated', 'public.fn_fdi_conciliacion_ultima(bigint)', 'EXECUTE')

  union all
  select 4, 'job_programado',
    'fdi-conciliacion-diaria a las 03:00',
    coalesce((select count(*)::text || ' job(s)'
                from cron.job where jobname = 'fdi-conciliacion-diaria'), '0 job(s)')
      || ' / ' || coalesce((select schedule from cron.job where jobname = 'fdi-conciliacion-diaria'), '—'),
    exists (select 1 from cron.job
             where jobname = 'fdi-conciliacion-diaria' and schedule = '0 3 * * *')

  union all
  select 5, 'ultima_corrida_sin_descuadres',
    '0 tiendas con descuadres en su última corrida',
    (select count(*)::text from ultimas where descuadres > 0) || ' tienda(s)',
    (select count(*) = 0 from ultimas where descuadres > 0)

  union all
  select 6, 'diferencia_total_coherente',
    'la guardada = la que sale del detalle (todas las corridas)',
    (select count(*)::text
       from public.fdi_dat_conciliacion_ejecucion e
       join recalculado r on r.id = e.id
      where abs(e.diferencia_total - r.dif) > 0.009) || ' incoherente(s)',
    (select count(*) = 0
       from public.fdi_dat_conciliacion_ejecucion e
       join recalculado r on r.id = e.id
      where abs(e.diferencia_total - r.dif) > 0.009)

  union all
  select 7, 'poda_90_dias',
    '0 corridas de más de 90 días',
    (select count(*)::text from public.fdi_dat_conciliacion_ejecucion
      where ejecutada_at < now() - interval '90 days') || ' vieja(s)',
    (select count(*) = 0 from public.fdi_dat_conciliacion_ejecucion
      where ejecutada_at < now() - interval '90 days')

  union all
  select 8, 'r1_intacta',
    'fn_fdi_conciliacion(bigint) sigue existiendo (una sola)',
    coalesce((select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where n.nspname = 'public' and p.proname = 'fn_fdi_conciliacion'), '0'),
    (select count(*) = 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'fn_fdi_conciliacion')

  union all
  -- 9) Informativa
  select 9, 'volumen',
    'informativa',
    (select count(*)::text from public.fdi_dat_conciliacion_ejecucion) || ' corrida(s) · '
      || (select count(*)::text from ultimas) || ' tienda(s) con última corrida · '
      || coalesce((select max(ejecutada_at)::text from public.fdi_dat_conciliacion_ejecucion), '—'),
    true
)

select * from base
union all
select 99 as n, 'RESUMEN' as chequeo,
       '0 fallos' as esperado,
       (select count(*)::text from base where not ok) || ' fallo(s) de '
         || (select count(*)::text from base) || ' comprobaciones' as actual,
       (select count(*) = 0 from base where not ok) as ok
  from (select 1) z
order by n;