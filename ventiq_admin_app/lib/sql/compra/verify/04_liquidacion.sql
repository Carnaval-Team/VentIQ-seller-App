-- ============================================================================
-- verify/04_liquidacion.sql — Fase 4: reserva y pago de la compra
--
-- REQUIERE: 04_compra_liquidacion.sql aplicado en `newa`
--           (qhprswhhfasrikhawjoz) y 03a/03b ya en su sitio.
--
-- SOLO LECTURA: SELECT / information_schema / pg_catalog / pg_proc /
-- pg_constraint / pg_indexes / pg_policies. Ni DDL ni DML.
-- UNA sola sentencia (README, regla 8): un CTE no sobrevive a otra sentencia,
-- así que el resumen va como fila UNION ALL con n = 99.
--
-- Contrastado contra `newa` antes de entregarlo: las firmas de abajo son las
-- que la base tiene de verdad, no las que el .sql pretendía crear. Ojo con la
-- cabecera del 04: su comentario dice "12 args" pero la función quedó con 13
-- (p_id_compra y p_tasa incluidas). Aquí manda el catálogo.
--
-- Comprobaciones de INVARIANTE (siguen valiendo con datos nuevos):
--   n=1..3    tablas, RLS y política SELECT
--   n=4..6    ledger: columnas id_compra/tasa, su FK y el CHECK de tipo
--   n=7       las 5 RPC con su firma exacta
--   n=8..9    _fdi_aplicar_movimiento: 13 args, una sola firma, devuelve bigint
--   n=10..11  el aplicador no lo ejecutan anon ni authenticated
--   n=12..18  invariantes de dinero sobre los datos vivos
--   n=19      conciliación del fondo (misma lógica que fn_fdi_conciliacion)
--   n=20..21  (informativas) devolución de compra y volumen de datos
-- ============================================================================

with
-- Firmas exactas tal como quedaron en `newa` (pg_proc.oid::regprocedure).
firmas as (
    select * from (values
        ('disponible', 'public.fn_fdi_disponible(bigint)'),
        ('reservar',   'public.fn_fdi_compra_reservar(bigint,jsonb,uuid)'),
        ('pagar',      'public.fn_fdi_compra_pagar(bigint,numeric)'),
        ('liberar',    'public.fn_fdi_compra_liberar(bigint,text)'),
        ('anular',     'public.fn_fdi_compra_anular(bigint,text)')
    ) v(nombre, firma)
),

-- El aplicador creció a 13 argumentos; se nombra una vez y se reutiliza.
aplicador as (
    select to_regprocedure(
        'public._fdi_aplicar_movimiento(bigint,bigint,smallint,text,numeric,character varying,bigint,bigint,bigint,text,uuid,bigint,numeric)') as oid
),

-- Reservas activas agregadas por (cuenta, medio, moneda) contra su saldo.
reserva_vs_saldo as (
    select r.id_tienda, r.id_cuenta, r.id_medio_pago, r.moneda,
           sum(r.monto) as reservado,
           s.saldo
      from public.fdi_dat_compra_reserva r
      left join public.fdi_dat_saldo s
             on s.id_cuenta = r.id_cuenta
            and s.id_medio_pago = r.id_medio_pago
            and s.moneda = r.moneda
     where r.estado = 'activa'
     group by r.id_tienda, r.id_cuenta, r.id_medio_pago, r.moneda, s.saldo
),

-- Compras pagadas: ¿cuadra Σ pagos con el total financiado?
pago_vs_total as (
    select c.id, c.total_financiado, coalesce(sum(p.monto_eq_total), 0) as pagado
      from public.fdi_dat_compra c
      left join public.fdi_dat_compra_pago p on p.id_compra = c.id
     where c.estado = 'pagada'
     group by c.id, c.total_financiado
),

-- Réplica exacta de fn_fdi_conciliacion, sin llamarla: saldo vs Σ movimientos
-- y saldo vs el saldo_nuevo del último movimiento, por (tienda, cuenta, medio,
-- moneda).
concat_ as (
    select s.id_tienda, s.id_cuenta, s.id_medio_pago, s.moneda, s.saldo,
           coalesce(m.suma_mov, 0) as suma_mov,
           u.saldo_nuevo           as ultimo_saldo_nuevo,
           round(s.saldo - coalesce(m.suma_mov, 0), 2)         as dif_saldo_vs_mov,
           round(s.saldo - coalesce(u.saldo_nuevo, 0), 2)      as dif_saldo_vs_ultimo
      from public.fdi_dat_saldo s
      left join (select id_tienda, id_cuenta, id_medio_pago, moneda,
                        sum(monto) as suma_mov
                   from public.fdi_dat_movimiento
                  group by 1, 2, 3, 4) m
             on m.id_tienda = s.id_tienda and m.id_cuenta = s.id_cuenta
            and m.id_medio_pago = s.id_medio_pago and m.moneda = s.moneda
      left join (select distinct on (id_tienda, id_cuenta, id_medio_pago, moneda)
                        id_tienda, id_cuenta, id_medio_pago, moneda, saldo_nuevo
                   from public.fdi_dat_movimiento
                  order by id_tienda, id_cuenta, id_medio_pago, moneda, id desc) u
             on u.id_tienda = s.id_tienda and u.id_cuenta = s.id_cuenta
            and u.id_medio_pago = s.id_medio_pago and u.moneda = s.moneda
),

base as (

  -- 1) Las 2 tablas de liquidación
  select 1 as n, 'tablas_2' as chequeo,
    'fdi_dat_compra_reserva, fdi_dat_compra_pago' as esperado,
    (select count(*)::text from information_schema.tables
      where table_schema = 'public' and table_type = 'BASE TABLE'
        and table_name in ('fdi_dat_compra_reserva','fdi_dat_compra_pago')) || ' de 2' as actual,
    (select count(*) = 2 from information_schema.tables
      where table_schema = 'public' and table_type = 'BASE TABLE'
        and table_name in ('fdi_dat_compra_reserva','fdi_dat_compra_pago')) as ok

  union all
  -- 2) RLS activo en las 2
  select 2, 'rls_activo_2',
    'relrowsecurity = true en las 2',
    (select count(*)::text from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
      where ns.nspname = 'public' and c.relrowsecurity
        and c.relname in ('fdi_dat_compra_reserva','fdi_dat_compra_pago')) || ' de 2',
    (select count(*) = 2 from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
      where ns.nspname = 'public' and c.relrowsecurity
        and c.relname in ('fdi_dat_compra_reserva','fdi_dat_compra_pago'))

  union all
  -- 3) Cada tabla con política SELECT a authenticated filtrada por tienda
  select 3, 'politicas_select_2',
    'una política SELECT por tabla (<tabla>_select), a authenticated, con fn_user_can_access_tienda(id_tienda)',
    'faltan: ' || coalesce((select string_agg(t.nombre, ', ' order by t.nombre)
                              from (values ('fdi_dat_compra_reserva'),('fdi_dat_compra_pago')) t(nombre)
                             where not exists (
                               select 1 from pg_policies p
                                where p.schemaname = 'public' and p.cmd = 'SELECT'
                                  and p.tablename = t.nombre
                                  and p.policyname = t.nombre || '_select'
                                  and p.roles::text = '{authenticated}'
                                  and coalesce(p.qual, '') like '%fn_user_can_access_tienda%')), 'ninguna'),
    (select count(*) = 2
       from (values ('fdi_dat_compra_reserva'),('fdi_dat_compra_pago')) t(nombre)
      where exists (
        select 1 from pg_policies p
         where p.schemaname = 'public' and p.cmd = 'SELECT'
           and p.tablename = t.nombre
           and p.policyname = t.nombre || '_select'
           and p.roles::text = '{authenticated}'
           and coalesce(p.qual, '') like '%fn_user_can_access_tienda%'))

  union all
  -- 4) El ledger ganó id_compra y tasa
  select 4, 'movimiento_columnas_2',
    'fdi_dat_movimiento.id_compra bigint y .tasa numeric',
    (select count(*)::text from information_schema.columns
      where table_schema = 'public' and table_name = 'fdi_dat_movimiento'
        and column_name in ('id_compra','tasa')) || ' de 2',
    (select count(*) = 2 from information_schema.columns
      where table_schema = 'public' and table_name = 'fdi_dat_movimiento'
        and column_name in ('id_compra','tasa'))

  union all
  -- 5) id_compra apunta a la compra (FK presente, no solo la columna)
  select 5, 'movimiento_id_compra_fkey',
    'FK fdi_dat_movimiento.id_compra → fdi_dat_compra.id',
    coalesce((select pg_get_constraintdef(con.oid)
                from pg_constraint con
               where con.contype = 'f'
                 and con.conrelid = 'public.fdi_dat_movimiento'::regclass
                 and con.confrelid = 'public.fdi_dat_compra'::regclass), 'no existe'),
    exists (select 1 from pg_constraint con
             where con.contype = 'f'
               and con.conrelid = 'public.fdi_dat_movimiento'::regclass
               and con.confrelid = 'public.fdi_dat_compra'::regclass)

  union all
  -- 6) El CHECK de tipo admite pago_compra y devolucion_compra (y está validado)
  select 6, 'check_tipo_admite_2',
    'fdi_dat_movimiento_tipo_check incluye pago_compra y devolucion_compra, convalidado',
    coalesce((select case when pg_get_constraintdef(con.oid) like '%pago_compra%'
                           and pg_get_constraintdef(con.oid) like '%devolucion_compra%'
                          then case when con.convalidated then 'admite los 2 y está validado'
                                    else 'admite los 2 pero NOT VALID' end
                          else 'definición inesperada: ' || pg_get_constraintdef(con.oid) end
                from pg_constraint con
               where con.contype = 'c' and con.conname = 'fdi_dat_movimiento_tipo_check'
                 and con.conrelid = 'public.fdi_dat_movimiento'::regclass), 'no existe'),
    coalesce((select con.convalidated
                and pg_get_constraintdef(con.oid) like '%pago_compra%'
                and pg_get_constraintdef(con.oid) like '%devolucion_compra%'
                from pg_constraint con
               where con.contype = 'c' and con.conname = 'fdi_dat_movimiento_tipo_check'
                 and con.conrelid = 'public.fdi_dat_movimiento'::regclass), false)

  union all
  -- 7) Las 5 RPC existen con su firma exacta
  select 7, 'rpcs_5_firmas',
    'disponible / reservar / pagar / liberar / anular, con su firma exacta',
    'faltan: ' || coalesce((select string_agg(f.nombre, ', ' order by f.nombre)
                              from firmas f
                             where to_regprocedure(f.firma) is null), 'ninguna'),
    (select bool_and(to_regprocedure(f.firma) is not null) from firmas f)

  union all
  -- 8) _fdi_aplicar_movimiento: una sola firma y de 13 argumentos
  select 8, 'aplicador_13_args_una_firma',
    'exactamente 1 firma de _fdi_aplicar_movimiento, con pronargs = 13',
    (select count(*)::text || ' firma(s); la de 13 args ' 
       || case when (select oid from aplicador) is not null then 'existe' else 'NO existe' end
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = '_fdi_aplicar_movimiento'),
    (select count(*) = 1
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = '_fdi_aplicar_movimiento')
    and (select oid from aplicador) is not null
    and (select p.pronargs = 13 from pg_proc p where p.oid = (select oid from aplicador))

  union all
  -- 9) Devuelve bigint (el id del movimiento), no void
  select 9, 'aplicador_devuelve_bigint',
    'prorettype = bigint',
    coalesce((select format_type(p.prorettype, null)
                from pg_proc p where p.oid = (select oid from aplicador)), 'no existe'),
    coalesce((select p.prorettype = 'bigint'::regtype
                from pg_proc p where p.oid = (select oid from aplicador)), false)

  union all
  -- 10) anon no lo ejecuta. has_function_privilege resuelve grants directos
  --     y los heredados vía PUBLIC, que es como se cuela un grant.
  select 10, 'anon_sin_execute_aplicador',
    'anon sin EXECUTE en _fdi_aplicar_movimiento',
    coalesce((select 'anon ' || case when has_function_privilege('anon', (select oid from aplicador), 'EXECUTE')
                                      then 'SÍ puede ejecutarlo' else 'no puede ejecutarlo' end), 'no existe'),
    coalesce((select not has_function_privilege('anon', (select oid from aplicador), 'EXECUTE')), false)

  union all
  -- 11) authenticated tampoco: solo las RPC lo llaman (SECURITY DEFINER)
  select 11, 'authenticated_sin_execute_aplicador',
    'authenticated sin EXECUTE en _fdi_aplicar_movimiento',
    coalesce((select 'authenticated ' || case when has_function_privilege('authenticated', (select oid from aplicador), 'EXECUTE')
                                               then 'SÍ puede ejecutarlo' else 'no puede ejecutarlo' end), 'no existe'),
    coalesce((select not has_function_privilege('authenticated', (select oid from aplicador), 'EXECUTE')), false)

  union all
  -- 12) Dinero: toda reserva consumida dejó rastro de su movimiento
  select 12, 'reservas_consumidas_con_movimiento',
    'estado = consumida ⇒ id_movimiento NOT NULL',
    (select count(*)::text from public.fdi_dat_compra_reserva
      where estado = 'consumida' and id_movimiento is null)
      || ' consumidas sin movimiento'
      || coalesce(' (ids: ' || (select string_agg(id::text, ', ' order by id)
                                  from public.fdi_dat_compra_reserva
                                 where estado = 'consumida' and id_movimiento is null) || ')', ''),
    (select count(*) = 0 from public.fdi_dat_compra_reserva
      where estado = 'consumida' and id_movimiento is null)

  union all
  -- 13) Dinero: las reservas activas nunca sobre-reservan una clave del saldo
  select 13, 'reservas_activas_cubiertas',
    'Σ reservas activas por (cuenta, medio, moneda) ≤ saldo de esa clave',
    (select count(*)::text from reserva_vs_saldo
      where reservado > coalesce(saldo, 0) + 0.005)
      || ' claves sobre-reservadas'
      || coalesce(' (claves: ' || (select string_agg(id_cuenta || '/' || id_medio_pago || '/' || moneda
                                                     || ' reservado=' || reservado
                                                     || ' saldo=' || coalesce(saldo::text, 'sin fila'), ', '
                                                     order by id_cuenta, id_medio_pago, moneda)
                                   from reserva_vs_saldo
                                  where reservado > coalesce(saldo, 0) + 0.005) || ')', ''),
    (select count(*) = 0 from reserva_vs_saldo
      where reservado > coalesce(saldo, 0) + 0.005)

  union all
  -- 14) Dinero: una compra pagada siempre tiene al menos un pago
  select 14, 'compras_pagadas_con_pago',
    'estado = pagada ⇒ ≥ 1 fila en fdi_dat_compra_pago',
    (select count(*)::text from public.fdi_dat_compra c
      where c.estado = 'pagada'
        and not exists (select 1 from public.fdi_dat_compra_pago p where p.id_compra = c.id))
      || ' pagadas sin pago'
      || coalesce(' (ids: ' || (select string_agg(c.id::text, ', ' order by c.id)
                                  from public.fdi_dat_compra c
                                 where c.estado = 'pagada'
                                   and not exists (select 1 from public.fdi_dat_compra_pago p
                                                    where p.id_compra = c.id)) || ')', ''),
    (select count(*) = 0 from public.fdi_dat_compra c
      where c.estado = 'pagada'
        and not exists (select 1 from public.fdi_dat_compra_pago p where p.id_compra = c.id))

  union all
  -- 15) Dinero: Σ pagos.monto_eq_total = total_financiado, al centavo
  select 15, 'pagos_cuadran_total',
    'estado = pagada ⇒ Σ pagos.monto_eq_total = total_financiado (|dif| < 0.005)',
    (select count(*)::text from pago_vs_total where abs(total_financiado - pagado) >= 0.005)
      || ' de ' || (select count(*)::text from pago_vs_total) || ' pagadas descuadradas'
      || coalesce(' (ids: ' || (select string_agg(id::text, ', ' order by id)
                                  from pago_vs_total
                                 where abs(total_financiado - pagado) >= 0.005) || ')', ''),
    (select count(*) = 0 from pago_vs_total where abs(total_financiado - pagado) >= 0.005)

  union all
  -- 16) Dinero: una compra pagada no puede quedarse con reservas vivas
  select 16, 'pagadas_sin_reservas_activas',
    'estado = pagada ⇒ 0 reservas en estado activa',
    (select count(distinct c.id)::text
       from public.fdi_dat_compra c
       join public.fdi_dat_compra_reserva r
         on r.id_compra = c.id and r.estado = 'activa'
      where c.estado = 'pagada') || ' pagadas con reservas activas'
      || coalesce(' (ids: ' || (select string_agg(distinct c.id::text, ', ' order by c.id::text)
                                  from public.fdi_dat_compra c
                                  join public.fdi_dat_compra_reserva r
                                    on r.id_compra = c.id and r.estado = 'activa'
                                 where c.estado = 'pagada') || ')', ''),
    (select count(*) = 0 from public.fdi_dat_compra c
       join public.fdi_dat_compra_reserva r
         on r.id_compra = c.id and r.estado = 'activa'
      where c.estado = 'pagada')

  union all
  -- 17) Dinero: todo débito del fondo por compra queda ligado a su compra
  select 17, 'mov_pago_compra_con_id_compra',
    'tipo = pago_compra ⇒ id_compra NOT NULL',
    (select count(*)::text from public.fdi_dat_movimiento
      where tipo = 'pago_compra' and id_compra is null)
      || ' movimientos pago_compra sin id_compra'
      || coalesce(' (ids: ' || (select string_agg(id::text, ', ' order by id)
                                  from public.fdi_dat_movimiento
                                 where tipo = 'pago_compra' and id_compra is null) || ')', ''),
    (select count(*) = 0 from public.fdi_dat_movimiento
      where tipo = 'pago_compra' and id_compra is null)

  union all
  -- 18) Dinero: cada pago y cada reserva apuntan a un movimiento existente
  select 18, 'rastro_movimientos_existe',
    'reserva/pago.id_movimiento NOT NULL ⇒ ese movimiento existe en el ledger',
    (select count(*)::text
       from public.fdi_dat_compra_reserva r
      where r.id_movimiento is not null
        and not exists (select 1 from public.fdi_dat_movimiento m where m.id = r.id_movimiento))
      || ' reservas huérfanas · '
      || (select count(*)::text
            from public.fdi_dat_compra_pago p
           where p.id_movimiento is not null
             and not exists (select 1 from public.fdi_dat_movimiento m where m.id = p.id_movimiento))
      || ' pagos huérfanos',
    (select count(*) = 0 from public.fdi_dat_compra_reserva r
      where r.id_movimiento is not null
        and not exists (select 1 from public.fdi_dat_movimiento m where m.id = r.id_movimiento))
    and (select count(*) = 0 from public.fdi_dat_compra_pago p
          where p.id_movimiento is not null
            and not exists (select 1 from public.fdi_dat_movimiento m where m.id = p.id_movimiento))

  union all
  -- 19) La conciliación del fondo sigue cuadrada, con la lógica de
  --     fn_fdi_conciliacion (no se llama a la función: se replica el cálculo
  --     para no depender de un id_tienda ni de los permisos de la sesión).
  select 19, 'conciliacion_0_descuadres',
    'saldo = Σ movimientos y saldo = saldo_nuevo del último, por (tienda, cuenta, medio, moneda)',
    (select count(*)::text from concat_
      where abs(dif_saldo_vs_mov) >= 0.005 or abs(dif_saldo_vs_ultimo) >= 0.005)
      || ' de ' || (select count(*)::text from concat_) || ' claves descuadradas'
      || coalesce(' (claves: ' || (select string_agg(id_cuenta || '/' || id_medio_pago || '/' || moneda
                                                     || ' dif_mov=' || dif_saldo_vs_mov
                                                     || ' dif_ultimo=' || dif_saldo_vs_ultimo, ', '
                                                     order by id_cuenta, id_medio_pago, moneda)
                                   from concat_
                                  where abs(dif_saldo_vs_mov) >= 0.005
                                     or abs(dif_saldo_vs_ultimo) >= 0.005) || ')', ''),
    (select count(*) = 0 from concat_
      where abs(dif_saldo_vs_mov) >= 0.005 or abs(dif_saldo_vs_ultimo) >= 0.005)

  union all
  -- 20) INFORMATIVA: mismo criterio para la devolución. No la exige el
  --     contrato de la fase, pero una devolución sin compra es dinero perdido:
  --     si sale distinto de 0, hay que mirarlo.
  select 20, 'mov_devolucion_compra_con_id_compra',
    'tipo = devolucion_compra ⇒ id_compra NOT NULL (informativa)',
    (select count(*)::text from public.fdi_dat_movimiento
      where tipo = 'devolucion_compra' and id_compra is null)
      || ' devoluciones sin id_compra (de '
      || (select count(*)::text from public.fdi_dat_movimiento where tipo = 'devolucion_compra') || ')',
    null

  union all
  -- 21) INFORMATIVA: volumen real sobre el que se evalúan los invariantes.
  --     Si todo está en 0, las comprobaciones 12..18 pasan por vacío.
  select 21, 'volumen_datos',
    'cuántas filas hay detrás de los invariantes (informativa)',
    (select count(*)::text from public.fdi_dat_compra_reserva)     || ' reservas · '
    || (select count(*)::text from public.fdi_dat_compra_pago)     || ' pagos · '
    || (select count(*)::text from public.fdi_dat_movimiento
         where tipo in ('pago_compra','devolucion_compra'))        || ' movimientos de compra · '
    || (select count(*)::text from public.fdi_dat_compra)          || ' compras',
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