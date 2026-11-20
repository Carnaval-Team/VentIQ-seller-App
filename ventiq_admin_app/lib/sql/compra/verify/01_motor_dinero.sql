-- ============================================================================
-- verify/01_motor_dinero.sql — Fase 1
--
-- SOLO LECTURA. Una sola sentencia (ver README, regla 8).
-- Devuelve una fila por comprobación y una de resumen (n = 99).
--
-- Las comprobaciones son INVARIANTES, no fotos fijas: siguen valiendo después
-- de crear movimientos nuevos.
-- ============================================================================

with base as (

  select 1 as n, 'escala_saldo' as chequeo,
    'fdi_dat_saldo.saldo numeric(14,2)' as esperado,
    coalesce((select numeric_scale::text from information_schema.columns
               where table_schema='public' and table_name='fdi_dat_saldo'
                 and column_name='saldo'), 'n/a') as actual,
    coalesce((select numeric_scale = 2 from information_schema.columns
               where table_schema='public' and table_name='fdi_dat_saldo'
                 and column_name='saldo'), false) as ok

  union all
  select 2, 'escala_movimiento',
    '3 columnas en escala 2',
    (select count(*)::text from information_schema.columns
      where table_schema='public' and table_name='fdi_dat_movimiento'
        and column_name in ('monto','saldo_anterior','saldo_nuevo')
        and numeric_scale = 2) || ' de 3',
    (select count(*) = 3 from information_schema.columns
      where table_schema='public' and table_name='fdi_dat_movimiento'
        and column_name in ('monto','saldo_anterior','saldo_nuevo')
        and numeric_scale = 2)

  union all
  select 3, 'check_inversion_anulado',
    'estado admite anulado',
    case when exists (select 1 from pg_constraint
                       where conrelid='public.fdi_dat_inversion'::regclass
                         and conname='fdi_dat_inversion_estado_check'
                         and pg_get_constraintdef(oid) like '%anulado%')
         then 'si' else 'no' end,
    exists (select 1 from pg_constraint
             where conrelid='public.fdi_dat_inversion'::regclass
               and conname='fdi_dat_inversion_estado_check'
               and pg_get_constraintdef(oid) like '%anulado%')

  union all
  select 4, 'check_movimiento_devolucion',
    'tipo admite devolucion_inversion',
    case when exists (select 1 from pg_constraint
                       where conrelid='public.fdi_dat_movimiento'::regclass
                         and conname='fdi_dat_movimiento_tipo_check'
                         and pg_get_constraintdef(oid) like '%devolucion_inversion%')
         then 'si' else 'no' end,
    exists (select 1 from pg_constraint
             where conrelid='public.fdi_dat_movimiento'::regclass
               and conname='fdi_dat_movimiento_tipo_check'
               and pg_get_constraintdef(oid) like '%devolucion_inversion%')

  union all
  select 5, 'funciones_nuevas',
    'fn_fdi_inversion_anular + fn_fdi_conciliacion',
    'anular=' || case when to_regprocedure('public.fn_fdi_inversion_anular(bigint,text)') is not null then 'si' else 'no' end
      || '; conciliacion=' || case when to_regprocedure('public.fn_fdi_conciliacion(bigint)') is not null then 'si' else 'no' end,
    to_regprocedure('public.fn_fdi_inversion_anular(bigint,text)') is not null
    and to_regprocedure('public.fn_fdi_conciliacion(bigint)') is not null

  union all
  select 6, 'r1_valida_tienda',
    'el aplicador menciona la validación de tienda',
    case when exists (select 1 from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
                       where ns.nspname='public' and p.proname='_fdi_aplicar_movimiento'
                         and p.prosrc like '%no pertenece a la tienda%')
         then 'si' else 'no' end,
    exists (select 1 from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
             where ns.nspname='public' and p.proname='_fdi_aplicar_movimiento'
               and p.prosrc like '%no pertenece a la tienda%')

  union all
  select 7, 'r3_for_update',
    'vincular recepción bloquea la inversión',
    case when exists (select 1 from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
                       where ns.nspname='public' and p.proname='fn_fdi_vincular_recepcion'
                         and p.prosrc like '%FOR UPDATE%')
         then 'si' else 'no' end,
    exists (select 1 from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
             where ns.nspname='public' and p.proname='fn_fdi_vincular_recepcion'
               and p.prosrc like '%FOR UPDATE%')

  union all
  select 8, 'r7_reparto_sin_bloqueo',
    'el reparto no exige inversores activos',
    case when exists (select 1 from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
                       where ns.nspname='public' and p.proname='fn_fdi_repartir_ganancia'
                         and p.prosrc not like '%No hay inversores activos%')
         then 'si' else 'no' end,
    exists (select 1 from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
             where ns.nspname='public' and p.proname='fn_fdi_repartir_ganancia'
               and p.prosrc not like '%No hay inversores activos%')

  union all
  select 9, 'recalculo_no_resucita_anuladas',
    'el recálculo sale si la inversión está anulada',
    case when exists (select 1 from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
                       where ns.nspname='public' and p.proname='fn_fdi_recalcular_inversion'
                         and p.prosrc like '%anulado%')
         then 'si' else 'no' end,
    exists (select 1 from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
             where ns.nspname='public' and p.proname='fn_fdi_recalcular_inversion'
               and p.prosrc like '%anulado%')

  union all
  select 10, 'identidad_saldo_movimientos',
    'Σ saldos = Σ movimientos (todas las tiendas)',
    coalesce((select sum(saldo)::text from public.fdi_dat_saldo), '0')
      || ' vs ' || coalesce((select sum(monto)::text from public.fdi_dat_movimiento), '0'),
    coalesce((select sum(saldo) from public.fdi_dat_saldo), 0)
      = coalesce((select sum(monto) from public.fdi_dat_movimiento), 0)

  union all
  select 11, 'conciliacion_por_clave',
    '0 claves descuadradas',
    (select count(*)::text from (
        select s.id_cuenta, s.id_medio_pago, s.moneda, s.saldo,
               coalesce(sum(m.monto), 0) as sm
        from public.fdi_dat_saldo s
        left join public.fdi_dat_movimiento m
          on m.id_cuenta = s.id_cuenta
         and m.id_medio_pago = s.id_medio_pago
         and m.moneda = s.moneda
        group by 1,2,3,4
     ) x where abs(x.saldo - x.sm) >= 0.005) || ' descuadre(s)',
    (select count(*) = 0 from (
        select s.id_cuenta, s.id_medio_pago, s.moneda, s.saldo,
               coalesce(sum(m.monto), 0) as sm
        from public.fdi_dat_saldo s
        left join public.fdi_dat_movimiento m
          on m.id_cuenta = s.id_cuenta
         and m.id_medio_pago = s.id_medio_pago
         and m.moneda = s.moneda
        group by 1,2,3,4
     ) x where abs(x.saldo - x.sm) >= 0.005)

)

select
  n, chequeo, esperado, actual,
  case when ok is null then 'info' when ok then 'ok' else 'falla' end as estado
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