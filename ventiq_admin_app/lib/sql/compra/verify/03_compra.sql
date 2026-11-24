-- ============================================================================
-- verify/03_compra.sql — Fase 3: la compra como documento
--
-- SOLO LECTURA: SELECT / information_schema / pg_catalog. Ni DDL ni DML.
-- UNA sola sentencia (README, regla 8): un CTE no sobrevive a otra sentencia,
-- así que el resumen va como fila UNION ALL con n = 99.
--
-- REQUIERE: 03a_compra_esquema.sql y 03b_compra_rpcs.sql aplicados.
-- Contrastado contra `newa` (qhprswhhfasrikhawjoz) antes de entregarlo.
--
-- Comprobaciones de INVARIANTE (siguen valiendo con datos nuevos):
--   n=1..6  tablas, RLS, políticas, índice de factura, columna generada, triggers
--   n=7..9  RPC: firmas, SECURITY DEFINER y que `anon` no las ejecute
--   n=10..13 coherencia de totales sobre los datos vivos
--   n=14    (informativa) `anon` no debería ejecutar la función de recálculo
-- ============================================================================

with
-- Firmas exactas tal como quedaron en `newa` (pg_proc.oid::regprocedure).
firmas as (
    select * from (values
        ('crear',    'public.fn_fdi_compra_crear(bigint,bigint,text,date,text,numeric,jsonb,jsonb,text,text,text,uuid)'),
        ('editar',   'public.fn_fdi_compra_editar(bigint,text,date,text,numeric,jsonb,jsonb,text)'),
        ('listar',   'public.fn_fdi_compra_listar(bigint,text,bigint,date,date,text)'),
        ('detalle',  'public.fn_fdi_compra_detalle(bigint)'),
        ('cancelar', 'public.fn_fdi_compra_cancelar(bigint,text)')
    ) v(nombre, firma)
),

-- Totales guardados vs. los que salen de las líneas y los ajustes.
calc as (
    select c.id,
           c.total_mercancia, c.total_ajustes, c.total_financiado, c.costo_aterrizado,
           coalesce(l.merc, 0)     as merc,
           coalesce(a.aj_tot, 0)   as aj_tot,
           coalesce(a.aj_fondo, 0) as aj_fondo
      from public.fdi_dat_compra c
      left join (select id_compra, sum(costo_linea) as merc
                   from public.fdi_dat_compra_linea
                  group by id_compra) l
             on l.id_compra = c.id
      left join (select id_compra,
                        sum(monto_capitalizado) as aj_tot,
                        sum(monto_capitalizado) filter (where origen_pago = 'fondo') as aj_fondo
                   from public.fdi_dat_compra_ajuste
                  group by id_compra) a
             on a.id_compra = c.id
),

base as (

  -- 1) Las 6 tablas
  select 1 as n, 'tablas_6' as chequeo,
    'fdi_dat_compra, _linea, _ajuste, fdi_hist_estado_compra, _recepcion, _recepcion_linea' as esperado,
    (select count(*)::text from information_schema.tables
      where table_schema = 'public' and table_type = 'BASE TABLE'
        and table_name in ('fdi_dat_compra','fdi_dat_compra_linea','fdi_dat_compra_ajuste',
                           'fdi_hist_estado_compra','fdi_dat_compra_recepcion',
                           'fdi_dat_compra_recepcion_linea')) || ' de 6' as actual,
    (select count(*) = 6 from information_schema.tables
      where table_schema = 'public' and table_type = 'BASE TABLE'
        and table_name in ('fdi_dat_compra','fdi_dat_compra_linea','fdi_dat_compra_ajuste',
                           'fdi_hist_estado_compra','fdi_dat_compra_recepcion',
                           'fdi_dat_compra_recepcion_linea')) as ok

  union all
  -- 2) RLS activo en las 6
  select 2, 'rls_activo_6',
    'relrowsecurity = true en las 6',
    (select count(*)::text from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
      where ns.nspname = 'public' and c.relrowsecurity
        and c.relname in ('fdi_dat_compra','fdi_dat_compra_linea','fdi_dat_compra_ajuste',
                          'fdi_hist_estado_compra','fdi_dat_compra_recepcion',
                          'fdi_dat_compra_recepcion_linea')) || ' de 6',
    (select count(*) = 6 from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
      where ns.nspname = 'public' and c.relrowsecurity
        and c.relname in ('fdi_dat_compra','fdi_dat_compra_linea','fdi_dat_compra_ajuste',
                          'fdi_hist_estado_compra','fdi_dat_compra_recepcion',
                          'fdi_dat_compra_recepcion_linea'))

  union all
  -- 3) Cada tabla con su política SELECT (<tabla>_select)
  select 3, 'politicas_select_6',
    'una política SELECT por tabla, con nombre <tabla>_select',
    (select count(*)::text from pg_policies
      where schemaname = 'public' and cmd = 'SELECT'
        and tablename in ('fdi_dat_compra','fdi_dat_compra_linea','fdi_dat_compra_ajuste',
                          'fdi_hist_estado_compra','fdi_dat_compra_recepcion',
                          'fdi_dat_compra_recepcion_linea')
        and policyname = tablename || '_select') || ' de 6',
    (select count(*) = 6 from pg_policies
      where schemaname = 'public' and cmd = 'SELECT'
        and tablename in ('fdi_dat_compra','fdi_dat_compra_linea','fdi_dat_compra_ajuste',
                          'fdi_hist_estado_compra','fdi_dat_compra_recepcion',
                          'fdi_dat_compra_recepcion_linea')
        and policyname = tablename || '_select')

  union all
  -- 4) Índice único parcial de factura (UNIQUE + WHERE en su definición)
  select 4, 'indice_factura_unico_parcial',
    'idx_fdi_compra_factura: UNIQUE ... WHERE numero_factura IS NOT NULL',
    coalesce((select case
                       when indexdef like '%UNIQUE%' and indexdef like '%WHERE%'
                        and indexdef like '%numero_factura%' then 'UNIQUE + parcial'
                       else 'definición inesperada: ' || indexdef
                     end
                from pg_indexes
               where schemaname = 'public' and tablename = 'fdi_dat_compra'
                 and indexname = 'idx_fdi_compra_factura'), 'no existe'),
    coalesce((select indexdef like '%UNIQUE%' and indexdef like '%WHERE%'
                     and indexdef like '%numero_factura%'
                from pg_indexes
               where schemaname = 'public' and tablename = 'fdi_dat_compra'
                 and indexname = 'idx_fdi_compra_factura'), false)

  union all
  -- 5) costo_linea es columna generada
  select 5, 'costo_linea_generada',
    'fdi_dat_compra_linea.costo_linea GENERATED ALWAYS AS ... STORED',
    coalesce((select is_generated || ' · ' || coalesce(generation_expression, '-')
                from information_schema.columns
               where table_schema = 'public' and table_name = 'fdi_dat_compra_linea'
                 and column_name = 'costo_linea'), 'no existe'),
    coalesce((select is_generated = 'ALWAYS'
                     and generation_expression like '%cantidad%'
                     and generation_expression like '%costo_unitario%'
                from information_schema.columns
               where table_schema = 'public' and table_name = 'fdi_dat_compra_linea'
                 and column_name = 'costo_linea'), false)

  union all
  -- 6) Los 2 triggers de recálculo, cada uno en su tabla y habilitados (tgenabled = 'O')
  select 6, 'triggers_recalculo_2',
    'trg_fdi_compra_recalc_linea / _ajuste, habilitados y en su tabla',
    (select count(*)::text from pg_trigger
      where not tgisinternal
        and tgname in ('trg_fdi_compra_recalc_linea','trg_fdi_compra_recalc_ajuste')
        and tgrelid in (to_regclass('public.fdi_dat_compra_linea'),
                        to_regclass('public.fdi_dat_compra_ajuste'))
        and tgenabled = 'O') || ' de 2 habilitados',
    (select count(*) = 2 from pg_trigger
      where not tgisinternal
        and tgname in ('trg_fdi_compra_recalc_linea','trg_fdi_compra_recalc_ajuste')
        and tgrelid in (to_regclass('public.fdi_dat_compra_linea'),
                        to_regclass('public.fdi_dat_compra_ajuste'))
        and tgenabled = 'O')

  union all
  -- 7) Las 5 RPC existen con su firma exacta
  select 7, 'rpcs_5_firmas',
    'crear / editar / listar / detalle / cancelar, con su firma exacta',
    'faltan: ' || coalesce((select string_agg(f.nombre, ', ' order by f.nombre)
                              from firmas f
                             where to_regprocedure(f.firma) is null), 'ninguna'),
    (select bool_and(to_regprocedure(f.firma) is not null) from firmas f)

  union all
  -- 8) La creación es SECURITY DEFINER
  select 8, 'crear_security_definer',
    'fn_fdi_compra_crear prosecdef = true',
    coalesce((select case when p.prosecdef then 'SECURITY DEFINER'
                          else 'SECURITY INVOKER' end
                from pg_proc p
               where p.oid = to_regprocedure(
                       'public.fn_fdi_compra_crear(bigint,bigint,text,date,text,numeric,jsonb,jsonb,text,text,text,uuid)')),
             'no existe'),
    coalesce((select p.prosecdef from pg_proc p
               where p.oid = to_regprocedure(
                       'public.fn_fdi_compra_crear(bigint,bigint,text,date,text,numeric,jsonb,jsonb,text,text,text,uuid)')),
             false)

  union all
  -- 9) anon no ejecuta ninguna RPC. has_function_privilege resuelve grants
  --    directos y los heredados vía PUBLIC, que es como se cuela un grant.
  select 9, 'anon_sin_execute_rpcs',
    'anon sin EXECUTE en las 5 RPC',
    'pueden: ' || coalesce((select string_agg(f.nombre, ', ' order by f.nombre)
                              from firmas f
                             where coalesce(has_function_privilege(
                                       'anon', to_regprocedure(f.firma), 'EXECUTE'), false)),
                           'ninguna'),
    not coalesce((select bool_or(coalesce(has_function_privilege(
                          'anon', to_regprocedure(f.firma), 'EXECUTE'), false))
                    from firmas f), false)

  union all
  -- 10) total_mercancia = Σ costo_linea
  select 10, 'totales_mercancia',
    'total_mercancia = Σ costo_linea (|dif| < 0.005)',
    (select count(*)::text from calc where abs(total_mercancia - merc) >= 0.005)
      || ' de ' || (select count(*)::text from calc) || ' compras descuadradas'
      || coalesce(' (ids: ' || (select string_agg(id::text, ', ' order by id)
                                  from calc where abs(total_mercancia - merc) >= 0.005) || ')', ''),
    (select count(*) = 0 from calc where abs(total_mercancia - merc) >= 0.005)

  union all
  -- 11) total_ajustes = Σ monto_capitalizado
  select 11, 'totales_ajustes',
    'total_ajustes = Σ monto_capitalizado (|dif| < 0.005)',
    (select count(*)::text from calc where abs(total_ajustes - aj_tot) >= 0.005)
      || ' de ' || (select count(*)::text from calc) || ' compras descuadradas'
      || coalesce(' (ids: ' || (select string_agg(id::text, ', ' order by id)
                                  from calc where abs(total_ajustes - aj_tot) >= 0.005) || ')', ''),
    (select count(*) = 0 from calc where abs(total_ajustes - aj_tot) >= 0.005)

  union all
  -- 12) total_financiado = total_mercancia + Σ ajustes con origen_pago = 'fondo'
  select 12, 'totales_financiado',
    'total_financiado = total_mercancia + Σ ajustes origen_pago=fondo (|dif| < 0.005)',
    (select count(*)::text
       from calc where abs(total_financiado - (total_mercancia + aj_fondo)) >= 0.005)
      || ' de ' || (select count(*)::text from calc) || ' compras descuadradas'
      || coalesce(' (ids: ' || (select string_agg(id::text, ', ' order by id)
                                  from calc
                                 where abs(total_financiado - (total_mercancia + aj_fondo)) >= 0.005) || ')', ''),
    (select count(*) = 0
       from calc where abs(total_financiado - (total_mercancia + aj_fondo)) >= 0.005)

  union all
  -- 13) costo_aterrizado = total_mercancia + total_ajustes (TODOS los ajustes)
  select 13, 'totales_costo_aterrizado',
    'costo_aterrizado = total_mercancia + total_ajustes (|dif| < 0.005)',
    (select count(*)::text
       from calc where abs(costo_aterrizado - (total_mercancia + total_ajustes)) >= 0.005)
      || ' de ' || (select count(*)::text from calc) || ' compras descuadradas'
      || coalesce(' (ids: ' || (select string_agg(id::text, ', ' order by id)
                                  from calc
                                 where abs(costo_aterrizado - (total_mercancia + total_ajustes)) >= 0.005) || ')', ''),
    (select count(*) = 0
       from calc where abs(costo_aterrizado - (total_mercancia + total_ajustes)) >= 0.005)

  union all
  -- 14) INFORMATIVA: fn_fdi_compra_recalcular es SECURITY DEFINER y escribe
  --     totales; no es una RPC de la API. Si anon la alcanza (grant PUBLIC
  --     heredado), cualquiera puede forzar un recálculo. No cuenta como falla
  --     porque el contrato de la fase solo habla de las 5 RPC, pero conviene
  --     revocarla: REVOKE ALL ON FUNCTION public.fn_fdi_compra_recalcular(bigint)
  --     FROM PUBLIC, anon;
  select 14, 'anon_sin_execute_recalculo',
    'anon no ejecuta fn_fdi_compra_recalcular (informativa)',
    case
      when to_regprocedure('public.fn_fdi_compra_recalcular(bigint)') is null then 'no existe'
      when coalesce(has_function_privilege('anon',
             to_regprocedure('public.fn_fdi_compra_recalcular(bigint)'), 'EXECUTE'), false)
        then 'anon SÍ puede ejecutarla (grant PUBLIC por defecto) · REVOKE pendiente'
      else 'anon no puede ejecutarla'
    end,
    null

)

select
  n, chequeo, esperado, actual,
  case when ok is null then 'info'
       when ok then 'ok'
       else 'falla' end as estado
from base

union all

select
  99,
  'RESUMEN',
  (select count(*) filter (where ok is true)::text || ' ok · '
        || count(*) filter (where ok is false)::text || ' falla · '
        || count(*) filter (where ok is null)::text || ' info'
     from base),
  case when (select count(*) filter (where ok is false) from base) = 0
       then 'sin fallas' else 'REVISAR' end,
  case when (select count(*) filter (where ok is false) from base) = 0
       then 'ok' else 'falla' end

order by n;