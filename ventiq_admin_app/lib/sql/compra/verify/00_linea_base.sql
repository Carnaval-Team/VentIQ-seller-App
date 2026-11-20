-- ============================================================================
-- verify/00_linea_base.sql — Semáforo de deriva de las bases
--
-- SOLO LECTURA. No modifica nada.
-- Ejecutar primero en `newa` (qhprswhhfasrikhawjoz) y, cuando toque, en Main.
--
-- Devuelve una fila por comprobación con: qué se espera, qué hay, y ok/falla.
-- Las comprobaciones marcadas `info` no fallan: solo reportan un estado que
-- otra fase cambiará a propósito.
-- ============================================================================

with base as (

  select
    1 as n,
    'fdi_tablas' as chequeo,
    '15 tablas fdi_*' as esperado,
    (select count(*)::text
       from information_schema.tables
      where table_schema = 'public'
        and table_type = 'BASE TABLE'
        and table_name like 'fdi\_%') as actual,
    (select count(*) = 15
       from information_schema.tables
      where table_schema = 'public'
        and table_type = 'BASE TABLE'
        and table_name like 'fdi\_%') as ok

  union all
  select
    2,
    'fdi_dat_movimiento.tipo',
    'CHECK admite ''gasto''',
    case when exists (
      select 1 from pg_constraint
       where conrelid = 'public.fdi_dat_movimiento'::regclass
         and conname  = 'fdi_dat_movimiento_tipo_check'
         and pg_get_constraintdef(oid) like '%gasto%'
    ) then 'si' else 'no' end,
    exists (
      select 1 from pg_constraint
       where conrelid = 'public.fdi_dat_movimiento'::regclass
         and conname  = 'fdi_dat_movimiento_tipo_check'
         and pg_get_constraintdef(oid) like '%gasto%'
    )

  union all
  select
    3,
    'fn_registrar_recepcion_con_inventario',
    '1 sola firma de 12 args',
    (select count(*)::text from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
      where ns.nspname = 'public' and p.proname = 'fn_registrar_recepcion_con_inventario')
      || ' firma(s); args='
      || coalesce((select string_agg(p.pronargs::text, '+' order by p.pronargs)
                     from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
                    where ns.nspname = 'public' and p.proname = 'fn_registrar_recepcion_con_inventario'), '-'),
    (select count(*) = 1
       from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
      where ns.nspname = 'public' and p.proname = 'fn_registrar_recepcion_con_inventario')
    and
    (select coalesce(min(p.pronargs), 0) = 12
       from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
      where ns.nspname = 'public' and p.proname = 'fn_registrar_recepcion_con_inventario')

  union all
  select
    4,
    'fn_fdi_registrar_recepcion + columnas de idempotencia',
    'funcion (jsonb,jsonb,uuid) y fdi_idempotency_key/fdi_solicitud',
    'funcion=' || case when to_regprocedure('public.fn_fdi_registrar_recepcion(jsonb,jsonb,uuid)') is null
                       then 'no' else 'si' end
      || '; idem=' || case when exists (select 1 from information_schema.columns
                                         where table_schema='public' and table_name='app_dat_operacion_recepcion'
                                           and column_name='fdi_idempotency_key') then 'si' else 'no' end
      || '; solicitud=' || case when exists (select 1 from information_schema.columns
                                             where table_schema='public' and table_name='app_dat_operacion_recepcion'
                                               and column_name='fdi_solicitud') then 'si' else 'no' end,
    to_regprocedure('public.fn_fdi_registrar_recepcion(jsonb,jsonb,uuid)') is not null
    and exists (select 1 from information_schema.columns
                 where table_schema='public' and table_name='app_dat_operacion_recepcion'
                   and column_name='fdi_idempotency_key')
    and exists (select 1 from information_schema.columns
                 where table_schema='public' and table_name='app_dat_operacion_recepcion'
                   and column_name='fdi_solicitud')

  union all
  select
    5,
    'app_dat_recepcion_productos.costo_real',
    'is_generated = NEVER',
    coalesce((select is_generated from information_schema.columns
               where table_schema='public' and table_name='app_dat_recepcion_productos'
                 and column_name='costo_real'), 'no existe'),
    coalesce((select is_generated = 'NEVER' from information_schema.columns
               where table_schema='public' and table_name='app_dat_recepcion_productos'
                 and column_name='costo_real'), false)

  union all
  select
    6,
    'modulo de costos adicionales',
    'app_dat_producto_costo + app_dat_recepcion_producto_costo',
    'producto_costo=' || case when to_regclass('public.app_dat_producto_costo') is null then 'no' else 'si' end
      || '; recepcion_producto_costo=' || case when to_regclass('public.app_dat_recepcion_producto_costo') is null then 'no' else 'si' end
      || '; tipos_costo=' || coalesce((select count(*)::text from public.app_cont_tipo_costo), 'n/a'),
    to_regclass('public.app_dat_producto_costo') is not null
    and to_regclass('public.app_dat_recepcion_producto_costo') is not null

  union all
  select
    7,
    'facturas de importadora/proveedor',
    'info: moneda e id_compra (los añade la fase 6)',
    'imp.moneda=' || case when exists (select 1 from information_schema.columns
                                        where table_schema='public' and table_name='imp_dat_factura'
                                          and column_name='moneda') then 'si' else 'no' end
      || '; imp.id_compra=' || case when exists (select 1 from information_schema.columns
                                                 where table_schema='public' and table_name='imp_dat_factura'
                                                   and column_name='id_compra') then 'si' else 'no' end
      || '; prv.moneda=' || case when exists (select 1 from information_schema.columns
                                               where table_schema='public' and table_name='prv_dat_factura'
                                                 and column_name='moneda') then 'si' else 'no' end
      || '; prv.id_compra=' || case when exists (select 1 from information_schema.columns
                                                  where table_schema='public' and table_name='prv_dat_factura'
                                                    and column_name='id_compra') then 'si' else 'no' end,
    null::boolean

  union all
  select
    8,
    'fn_fdi_crear_liquidacion',
    '11 args (p_repartir_igual)',
    (select coalesce(string_agg(p.pronargs::text, '+' order by p.pronargs), 'no existe')
       from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
      where ns.nspname = 'public' and p.proname = 'fn_fdi_crear_liquidacion'),
    (select count(*) = 1 from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
      where ns.nspname = 'public' and p.proname = 'fn_fdi_crear_liquidacion')
    and
    (select coalesce(min(p.pronargs), 0) = 11
       from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
      where ns.nspname = 'public' and p.proname = 'fn_fdi_crear_liquidacion')
)

select
  n,
  chequeo,
  esperado,
  actual,
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