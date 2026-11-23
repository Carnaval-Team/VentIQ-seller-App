-- ============================================================================
-- verify/07_aportes.sql — Fase 7: aportes de inversores (07)
--
-- REQUIERE: 07_aportes_inversores.sql aplicado en `newa`
--           (qhprswhhfasrikhawjoz).
--
-- SOLO LECTURA: SELECT / information_schema / pg_catalog / pg_proc. Ni DDL ni
-- DML, ni una llamada a las funciones que escriben.
-- UNA sola sentencia (README, regla 8): el resumen va como fila UNION ALL 99.
--
-- Comprobaciones de INVARIANTE (siguen valiendo con datos nuevos):
--   n=1   la tabla `fdi_dat_compra_aporte` existe
--   n=2   sus columnas del contrato están (13 de 13)
--   n=3   `monto_eq_total` es columna GENERADA: no se puede falsear
--   n=4   RLS activa y una sola política, SELECT, para authenticated
--   n=5   `idempotency_key` único y parcial (no bloquea las filas sin clave)
--   n=6   el inversor es de la misma tienda que la compra (FK compuesta)
--   n=7   CHECK de devolución (devuelto ⇒ fecha y motivo)
--   n=8   `fdi_dat_compra_pago.id_cuenta`/`id_medio_pago` admiten NULL (aporte)
--   n=9   CHECK `fdi_pago_fuente_check`: fondo con cuenta, medio y movimiento;
--         aporte sin cuenta, sin medio y sin movimiento
--   n=10  FK (id_aporte, id_compra) al aporte (un pago no apunta al aporte de
--         otra compra)
--   n=11  los 6 triggers de exclusividad existen
--   n=12  las 3 RPC existen, son SECURITY DEFINER y sólo `authenticated` las
--         puede ejecutar
--   n=13  `fn_fdi_compra_pagar` tiene la rama de aportes (7a) y escribe
--         `id_aporte` (sin debitar el fondo)
--   n=14  `fn_fdi_compra_anular` salta los pagos con aporte (CONTINUE) y exige
--         devolverlos antes
--   n=15  `fn_fdi_compra_cancelar` exige devolver los aportes
--   n=16  `fn_fdi_compra_liberar` rechaza el modo inversores
--   n=17  AISLAMIENTO estructural: el aporte no tiene cuenta, medio, movimiento
--         ni saldo (no puede tocar el libro del fondo ni por error)
--   n=18  AISLAMIENTO de código: ninguna RPC de aportes menciona
--         `fdi_dat_saldo` ni `fdi_dat_movimiento`
--   n=19  ninguna compra de inversores tiene reservas del fondo
--   n=20  ningún pago de una compra de inversores tiene `origen = 'fondo'`
--   n=21  `pagada` en modo inversores ⇒ Σ pagos = `total_financiado`
--   n=22  Σ aportes vigentes ≤ `total_financiado` en todas las compras
--   n=23  ninguna compra mezcla aportes con reservas del fondo
--   n=24  ningún movimiento del libro apunta a una compra de inversores
--   n=25  coherencia de la devolución y del equivalente
--   n=26  ningún aporte vive en una compra que no sea modo inversores
--   n=27  ningún pago apunta al aporte de otra compra
--   n=28  un faltante sobre una compra pagada sólo existe si hay una devolución
--         con documento (nunca un hueco sin rastro)
--   n=29  el trigger del aporte cubre INSERT, UPDATE y DELETE
--   n=30  índice único (id, id_compra) que sostiene la FK compuesta
--   n=31  el ajuste tardío elige `externo`/`declarado` en modo inversores
--   n=32  (informativa) volumen de la fase 7
--   n=99  resumen
--
-- NOTA: las comprobaciones 19-28 son estructurales; con cero compras de
-- inversores pasan por vacío. Eso no demuestra el flujo: lo demuestra
-- `verify/07_pruebas_aportes.sql` (transaccional, 42 comprobaciones con dinero).
--
-- SI 07 NO ESTÁ APLICADO, este script ABORTA con `42P01: relation
-- "public.fdi_dat_compra_aporte" does not exist` en vez de devolver las filas en
-- rojo. Es deliberado: degradar a «ausente» exigiría leer la tabla por SQL
-- dinámico, y eso obliga a partir la sentencia en dos (regla 8 del README). El
-- error es la señal, y la cabecera ya declara el requisito.
-- ============================================================================

with

aportes as (
    select a.id, a.id_compra, a.id_tienda, a.id_inversor, a.estado,
           a.monto, a.tasa_a_total, a.monto_eq_total,
           a.devuelto_at, a.motivo_devolucion
      from public.fdi_dat_compra_aporte a
),

compras_inv as (
    select c.id, c.total_financiado, c.estado
      from public.fdi_dat_compra c
     where c.modo_liquidacion = 'inversores'
),

suma_aporte as (
    select a.id_compra,
           coalesce(sum(a.monto_eq_total) filter (where a.estado = 'aportado'), 0) as vigente
      from aportes a
     group by a.id_compra
),

suma_pago as (
    select p.id_compra, coalesce(sum(p.monto), 0) as pagado
      from public.fdi_dat_compra_pago p
     group by p.id_compra
),

base as (

  select 1 as n, 'tabla_aporte' as chequeo,
    'fdi_dat_compra_aporte existe' as esperado,
    coalesce((select count(*)::text from information_schema.tables
               where table_schema = 'public' and table_name = 'fdi_dat_compra_aporte'), '0') as actual,
    (select count(*) = 1 from information_schema.tables
      where table_schema = 'public' and table_name = 'fdi_dat_compra_aporte') as ok

  union all
  select 2, 'columnas_contrato',
    '13 de 13',
    (select count(*)::text from information_schema.columns
      where table_schema = 'public' and table_name = 'fdi_dat_compra_aporte'
        and column_name in ('id_compra','id_tienda','id_inversor','naturaleza','moneda',
                            'monto','tasa_a_total','monto_eq_total','tasa_interes',
                            'comprobante','observacion','estado','idempotency_key')) || ' de 13',
    (select count(*) = 13 from information_schema.columns
      where table_schema = 'public' and table_name = 'fdi_dat_compra_aporte'
        and column_name in ('id_compra','id_tienda','id_inversor','naturaleza','moneda',
                            'monto','tasa_a_total','monto_eq_total','tasa_interes',
                            'comprobante','observacion','estado','idempotency_key'))

  union all
  select 3, 'equivalente_generado',
    'monto_eq_total GENERATED ALWAYS',
    coalesce((select c.is_generated from information_schema.columns c
               where c.table_schema = 'public' and c.table_name = 'fdi_dat_compra_aporte'
                 and c.column_name = 'monto_eq_total'), 'falta'),
    coalesce((select c.is_generated = 'ALWAYS' from information_schema.columns c
               where c.table_schema = 'public' and c.table_name = 'fdi_dat_compra_aporte'
                 and c.column_name = 'monto_eq_total'), false)

  union all
  select 4, 'rls_solo_select',
    'RLS activa y 1 política SELECT',
    coalesce((select count(*)::text from pg_policies
               where schemaname = 'public' and tablename = 'fdi_dat_compra_aporte'), '0')
      || ' política(s), '
      || coalesce((select count(*)::text from pg_policies
                    where schemaname = 'public' and tablename = 'fdi_dat_compra_aporte'
                      and cmd = 'SELECT'), '0') || ' SELECT',
    coalesce((select relrowsecurity from pg_class
               where oid = 'public.fdi_dat_compra_aporte'::regclass), false)
    and (select count(*) = 1 from pg_policies
          where schemaname = 'public' and tablename = 'fdi_dat_compra_aporte')
    and (select count(*) = 1 from pg_policies
          where schemaname = 'public' and tablename = 'fdi_dat_compra_aporte' and cmd = 'SELECT')

  union all
  select 5, 'idempotencia_unica',
    'IDX único parcial sobre idempotency_key',
    coalesce((select count(*)::text from pg_index i
               where i.indexrelid = to_regclass('public.idx_fdi_aporte_idem')
                 and i.indisunique and i.indpred is not null), '0'),
    coalesce((select i.indisunique and i.indpred is not null from pg_index i
               where i.indexrelid = to_regclass('public.idx_fdi_aporte_idem')), false)

  union all
  select 6, 'fk_inversor_tienda',
    'FK (id_inversor, id_tienda) → fdi_dat_inversor',
    coalesce((select count(*)::text from pg_constraint
               where conrelid = 'public.fdi_dat_compra_aporte'::regclass
                 and contype = 'f'
                 and confrelid = 'public.fdi_dat_inversor'::regclass
                 and pg_get_constraintdef(oid) like '%(id_inversor, id_tienda)%'), '0'),
    coalesce((select count(*) = 1 from pg_constraint
               where conrelid = 'public.fdi_dat_compra_aporte'::regclass
                 and contype = 'f'
                 and confrelid = 'public.fdi_dat_inversor'::regclass
                 and pg_get_constraintdef(oid) like '%(id_inversor, id_tienda)%'), false)

  union all
  select 7, 'check_devolucion',
    'devuelto ⇒ fecha y motivo no vacío',
    coalesce((select case when pg_get_constraintdef(oid) like '%motivo_devolucion%'
                          then 'presente' else 'sin motivo' end
                from pg_constraint
               where conrelid = 'public.fdi_dat_compra_aporte'::regclass
                 and conname = 'fdi_aporte_devolucion_check'), 'falta'),
    exists (select 1 from pg_constraint
             where conrelid = 'public.fdi_dat_compra_aporte'::regclass
               and conname = 'fdi_aporte_devolucion_check'
               and pg_get_constraintdef(oid) like '%motivo_devolucion%')

  union all
  select 8, 'pago_cuenta_opcional',
    'id_cuenta e id_medio_pago admiten NULL',
    (select count(*)::text from information_schema.columns
      where table_schema = 'public' and table_name = 'fdi_dat_compra_pago'
        and column_name in ('id_cuenta','id_medio_pago') and is_nullable = 'YES') || ' de 2',
    (select count(*) = 2 from information_schema.columns
      where table_schema = 'public' and table_name = 'fdi_dat_compra_pago'
        and column_name in ('id_cuenta','id_medio_pago') and is_nullable = 'YES')

  union all
  select 9, 'pago_fuente_check',
    'fondo con cuenta, medio y movimiento; aporte sin nada de eso',
    coalesce((select case
                        when pg_get_constraintdef(oid) like '%id_aporte IS NOT NULL%'
                         and pg_get_constraintdef(oid) like '%id_cuenta IS NULL%'
                         and pg_get_constraintdef(oid) like '%id_movimiento IS NULL%'
                        then 'completa' else 'incompleta' end
                from pg_constraint
               where conrelid = 'public.fdi_dat_compra_pago'::regclass
                 and conname = 'fdi_pago_fuente_check'), 'falta'),
    exists (select 1 from pg_constraint
             where conrelid = 'public.fdi_dat_compra_pago'::regclass
               and conname = 'fdi_pago_fuente_check'
               and pg_get_constraintdef(oid) like '%id_aporte IS NOT NULL%'
               and pg_get_constraintdef(oid) like '%id_cuenta IS NULL%'
               and pg_get_constraintdef(oid) like '%id_movimiento IS NULL%'
               -- H1: la rama del fondo exige movimiento, o un UPDATE podría
               -- convertir un pago de aporte en pago del fondo con saldo inventado.
               and pg_get_constraintdef(oid) like '%id_movimiento IS NOT NULL%')

  union all
  select 10, 'pago_fk_aporte',
    'FK (id_aporte, id_compra) al aporte',
    coalesce((select count(*)::text from pg_constraint
               where conrelid = 'public.fdi_dat_compra_pago'::regclass
                 and contype = 'f'
                 and confrelid = 'public.fdi_dat_compra_aporte'::regclass), '0'),
    coalesce((select count(*) = 1 from pg_constraint
               where conrelid = 'public.fdi_dat_compra_pago'::regclass
                 and contype = 'f'
                 and confrelid = 'public.fdi_dat_compra_aporte'::regclass
                 and pg_get_constraintdef(oid) like '%(id_aporte, id_compra)%'), false)

  union all
  select 11, 'triggers_exclusividad',
    '6 de 6',
    (select count(*)::text from pg_trigger t
      where not t.tgisinternal
        and t.tgname in ('trg_fdi_aporte_inversores','trg_fdi_reserva_solo_fondo',
                         'trg_fdi_pago_coherente','trg_fdi_compra_modo_inmutable',
                         'trg_fdi_ajuste_solo_fondo','trg_fdi_recepcion_solo_fondo')) || ' de 6',
    (select count(*) = 6 from pg_trigger t
      where not t.tgisinternal
        and t.tgname in ('trg_fdi_aporte_inversores','trg_fdi_reserva_solo_fondo',
                         'trg_fdi_pago_coherente','trg_fdi_compra_modo_inmutable',
                         'trg_fdi_ajuste_solo_fondo','trg_fdi_recepcion_solo_fondo'))

  union all
  select 12, 'rpc_firmas',
    '3 RPC definer, ejecutables sólo por authenticated',
    (select count(*)::text from pg_proc p
      where p.oid in ('public.fn_fdi_compra_aportes(bigint)'::regprocedure,
                      'public.fn_fdi_compra_aporte_registrar(bigint,bigint,text,numeric,numeric,text,numeric,text,text,uuid)'::regprocedure,
                      'public.fn_fdi_compra_aporte_devolver(bigint,text)'::regprocedure)
        and p.prosecdef) || ' de 3 definer',
    (select count(*) = 3 from pg_proc p
      where p.oid in ('public.fn_fdi_compra_aportes(bigint)'::regprocedure,
                      'public.fn_fdi_compra_aporte_registrar(bigint,bigint,text,numeric,numeric,text,numeric,text,text,uuid)'::regprocedure,
                      'public.fn_fdi_compra_aporte_devolver(bigint,text)'::regprocedure)
        and p.prosecdef)
    and has_function_privilege('authenticated', 'public.fn_fdi_compra_aportes(bigint)', 'EXECUTE')
    and has_function_privilege('authenticated', 'public.fn_fdi_compra_aporte_devolver(bigint,text)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.fn_fdi_compra_aportes(bigint)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.fn_fdi_compra_aporte_devolver(bigint,text)', 'EXECUTE')

  union all
  select 13, 'pagar_rama_aportes',
    'fn_fdi_compra_pagar tiene el bloque 7a y escribe id_aporte',
    coalesce((select case when position('7a) Modo inversores' in p.prosrc) > 0 then '7a' else 'sin 7a' end
                from pg_proc p
               where p.oid = 'public.fn_fdi_compra_pagar(bigint,numeric)'::regprocedure), 'falta'),
    coalesce((select position('7a) Modo inversores' in p.prosrc) > 0
               and position('id_aporte' in p.prosrc) > 0
               and position('Los aportes cubren' in p.prosrc) > 0
                from pg_proc p
               where p.oid = 'public.fn_fdi_compra_pagar(bigint,numeric)'::regprocedure), false)

  union all
  select 14, 'anular_salta_aporte',
    'CONTINUE para origen aporte y guarda «devuélvalos antes de anular»',
    coalesce((select case when position('CONTINUE' in p.prosrc) > 0 then 'CONTINUE' else 'sin CONTINUE' end
                from pg_proc p
               where p.oid = 'public.fn_fdi_compra_anular(bigint,text)'::regprocedure), 'falta'),
    coalesce((select position('CONTINUE' in p.prosrc) > 0
               and position('devuélvalos antes de anular' in p.prosrc) > 0
               and position('devolucion_compra' in p.prosrc) > 0
                from pg_proc p
               where p.oid = 'public.fn_fdi_compra_anular(bigint,text)'::regprocedure), false)

  union all
  select 15, 'cancelar_guarda_aporte',
    'fn_fdi_compra_cancelar exige devolver los aportes',
    coalesce((select case when position('devuélvalos antes de cancelar' in p.prosrc) > 0
                          then 'guarda' else 'sin guarda' end
                from pg_proc p
               where p.oid = 'public.fn_fdi_compra_cancelar(bigint,text)'::regprocedure), 'falta'),
    coalesce((select position('devuélvalos antes de cancelar' in p.prosrc) > 0
                from pg_proc p
               where p.oid = 'public.fn_fdi_compra_cancelar(bigint,text)'::regprocedure), false)

  union all
  select 16, 'liberar_guarda_aporte',
    'fn_fdi_compra_liberar rechaza el modo inversores',
    coalesce((select case when position('devuelva los aportes en vez de liberar' in p.prosrc) > 0
                          then 'guarda' else 'sin guarda' end
                from pg_proc p
               where p.oid = 'public.fn_fdi_compra_liberar(bigint,text)'::regprocedure), 'falta'),
    coalesce((select position('devuelva los aportes en vez de liberar' in p.prosrc) > 0
                from pg_proc p
               where p.oid = 'public.fn_fdi_compra_liberar(bigint,text)'::regprocedure), false)

  union all
  select 17, 'aislamiento_columnas',
    'el aporte no tiene cuenta, medio, movimiento ni saldo',
    (select count(*)::text from information_schema.columns
      where table_schema = 'public' and table_name = 'fdi_dat_compra_aporte'
        and column_name in ('id_cuenta','id_medio_pago','id_movimiento','id_saldo')) || ' de 0',
    (select count(*) = 0 from information_schema.columns
      where table_schema = 'public' and table_name = 'fdi_dat_compra_aporte'
        and column_name in ('id_cuenta','id_medio_pago','id_movimiento','id_saldo'))

  union all
  select 18, 'aislamiento_codigo',
    'ninguna RPC de aportes menciona fdi_dat_saldo ni fdi_dat_movimiento',
    (select count(*)::text from pg_proc p
      where p.oid in ('public.fn_fdi_compra_aportes(bigint)'::regprocedure,
                      'public.fn_fdi_compra_aporte_registrar(bigint,bigint,text,numeric,numeric,text,numeric,text,text,uuid)'::regprocedure,
                      'public.fn_fdi_compra_aporte_devolver(bigint,text)'::regprocedure)
        and (position('fdi_dat_saldo' in p.prosrc) > 0 or position('fdi_dat_movimiento' in p.prosrc) > 0))
      || ' de 0 con el libro',
    (select count(*) = 0 from pg_proc p
      where p.oid in ('public.fn_fdi_compra_aportes(bigint)'::regprocedure,
                      'public.fn_fdi_compra_aporte_registrar(bigint,bigint,text,numeric,numeric,text,numeric,text,text,uuid)'::regprocedure,
                      'public.fn_fdi_compra_aporte_devolver(bigint,text)'::regprocedure)
        and (position('fdi_dat_saldo' in p.prosrc) > 0 or position('fdi_dat_movimiento' in p.prosrc) > 0))

  union all
  select 19, 'inversores_sin_reservas',
    '0 compras de inversores con reserva del fondo',
    (select count(*)::text
       from compras_inv c
       join public.fdi_dat_compra_reserva r on r.id_compra = c.id),
    (select count(*) = 0
       from compras_inv c
       join public.fdi_dat_compra_reserva r on r.id_compra = c.id)

  union all
  select 20, 'inversores_sin_pago_fondo',
    '0 pagos con origen fondo en compras de inversores',
    (select count(*)::text from compras_inv c
       join public.fdi_dat_compra_pago p on p.id_compra = c.id
      where p.origen = 'fondo'),
    (select count(*) = 0 from compras_inv c
       join public.fdi_dat_compra_pago p on p.id_compra = c.id
      where p.origen = 'fondo')

  union all
  select 21, 'pagada_cuadra_pagos',
    'pagada en modo inversores ⇒ Σ pagos = total_financiado',
    (select count(*)::text from compras_inv c
      where c.estado in ('pagada','entrega_parcial','completada')
        and abs(coalesce((select p.pagado from suma_pago p where p.id_compra = c.id), 0)
                - c.total_financiado) > 0.009) || ' descuadre(s)',
    (select count(*) = 0 from compras_inv c
      where c.estado in ('pagada','entrega_parcial','completada')
        and abs(coalesce((select p.pagado from suma_pago p where p.id_compra = c.id), 0)
                - c.total_financiado) > 0.009)

  union all
  select 22, 'aporte_no_excede',
    'Σ aportes vigentes ≤ total_financiado',
    (select count(*)::text from compras_inv c
      where coalesce((select s.vigente from suma_aporte s where s.id_compra = c.id), 0)
            > c.total_financiado + 0.009) || ' exceso(s)',
    (select count(*) = 0 from compras_inv c
      where coalesce((select s.vigente from suma_aporte s where s.id_compra = c.id), 0)
            > c.total_financiado + 0.009)

  union all
  select 23, 'no_coexisten',
    '0 compras con aportes y reservas a la vez',
    (select count(*)::text from compras_inv c
      where exists (select 1 from aportes a where a.id_compra = c.id)
        and exists (select 1 from public.fdi_dat_compra_reserva r where r.id_compra = c.id)),
    (select count(*) = 0 from compras_inv c
      where exists (select 1 from aportes a where a.id_compra = c.id)
        and exists (select 1 from public.fdi_dat_compra_reserva r where r.id_compra = c.id))

  union all
  select 24, 'sin_movimientos_del_libro',
    '0 movimientos del fondo con id_compra de una compra de inversores',
    (select count(*)::text from public.fdi_dat_movimiento m
       join compras_inv c on c.id = m.id_compra),
    (select count(*) = 0 from public.fdi_dat_movimiento m
       join compras_inv c on c.id = m.id_compra)

  union all
  select 25, 'devolucion_y_equivalente_coherentes',
    'devuelto ⇔ fecha y motivo; equivalente = round(monto × tasa, 2)',
    (select count(*)::text from aportes a
      where (a.estado = 'devuelto') <> (a.devuelto_at is not null)
         or (a.estado = 'devuelto' and (a.motivo_devolucion is null
                                        or btrim(a.motivo_devolucion) = ''))
         or a.monto_eq_total is distinct from round(a.monto * a.tasa_a_total, 2))
      || ' incoherencia(s)',
    (select count(*) = 0 from aportes a
      where (a.estado = 'devuelto') <> (a.devuelto_at is not null)
         or (a.estado = 'devuelto' and (a.motivo_devolucion is null
                                        or btrim(a.motivo_devolucion) = ''))
         or a.monto_eq_total is distinct from round(a.monto * a.tasa_a_total, 2))

  union all
  -- 26) Un aporte sólo vive en una compra de inversores (caza el UPDATE de modo
  --     con todos los aportes devueltos, que sacaría la compra de estos chequeos).
  select 26, 'aporte_solo_en_inversores',
    '0 aportes en compras que no sean modo inversores',
    (select count(*)::text from aportes a
       join public.fdi_dat_compra c on c.id = a.id_compra
      where c.modo_liquidacion <> 'inversores'),
    (select count(*) = 0 from aportes a
       join public.fdi_dat_compra c on c.id = a.id_compra
      where c.modo_liquidacion <> 'inversores')

  union all
  -- 27) El pago apunta al aporte de SU compra, no al de otra.
  select 27, 'pago_aporte_de_su_compra',
    '0 pagos cuyo aporte pertenezca a otra compra',
    (select count(*)::text
       from public.fdi_dat_compra_pago p
       join aportes a on a.id = p.id_aporte
      where a.id_compra <> p.id_compra),
    (select count(*) = 0
       from public.fdi_dat_compra_pago p
       join aportes a on a.id = p.id_aporte
      where a.id_compra <> p.id_compra)

  union all
  -- 28) Un faltante sobre una compra ya pagada sólo se explica por una
  --     devolución con documento (la devolución posterior al pago es una
  --     decisión del dueño; lo que no se admite es un hueco sin rastro).
  select 28, 'faltante_pagado_explicado',
    '0 compras pagadas con faltante y sin ningún aporte devuelto',
    (select count(*)::text from compras_inv c
      where c.estado in ('pagada','entrega_parcial','completada')
        and coalesce((select s.vigente from suma_aporte s where s.id_compra = c.id), 0)
            < c.total_financiado - 0.009
        and not exists (select 1 from aportes a
                         where a.id_compra = c.id and a.estado = 'devuelto')),
    (select count(*) = 0 from compras_inv c
      where c.estado in ('pagada','entrega_parcial','completada')
        and coalesce((select s.vigente from suma_aporte s where s.id_compra = c.id), 0)
            < c.total_financiado - 0.009
        and not exists (select 1 from aportes a
                         where a.id_compra = c.id and a.estado = 'devuelto'))

  union all
  -- 29) El trigger del aporte cubre INSERT, UPDATE y DELETE (H2/H5).
  select 29, 'trigger_aporte_completo',
    'BEFORE INSERT OR UPDATE OR DELETE',
    coalesce((select case
                        when t.tgtype & 4 = 4 and t.tgtype & 16 = 16 and t.tgtype & 8 = 8
                        then 'INSERT/UPDATE/DELETE' else 'parcial' end
                from pg_trigger t
               where t.tgname = 'trg_fdi_aporte_inversores' and not t.tgisinternal), 'falta'),
    coalesce((select t.tgtype & 4 = 4 and t.tgtype & 16 = 16 and t.tgtype & 8 = 8
                from pg_trigger t
               where t.tgname = 'trg_fdi_aporte_inversores' and not t.tgisinternal), false)

  union all
  -- 30) Índice único que hace posible la FK compuesta del pago.
  select 30, 'indice_uq_aporte',
    'uq_fdi_aporte_id_compra único sobre (id, id_compra)',
    coalesce((select count(*)::text from pg_index i
               where i.indexrelid = to_regclass('public.uq_fdi_aporte_id_compra')
                 and i.indisunique), '0'),
    coalesce((select i.indisunique from pg_index i
               where i.indexrelid = to_regclass('public.uq_fdi_aporte_id_compra')), false)

  union all
  -- 31) El ajuste tardío de una compra de inversores no lo paga el fondo (D1).
  select 31, 'ajuste_tardio_por_modo',
    'fn_fdi_compra_ajuste_agregar elige externo/declarado en modo inversores',
    coalesce((select case when position('''inversores'' THEN ''externo''' in p.prosrc) > 0
                          then 'por modo' else 'fijo en fondo' end
                from pg_proc p
               where p.oid = 'public.fn_fdi_compra_ajuste_agregar(bigint,bigint,text,numeric,text,boolean,uuid)'::regprocedure), 'falta'),
    coalesce((select position('''inversores'' THEN ''externo''' in p.prosrc) > 0
                from pg_proc p
               where p.oid = 'public.fn_fdi_compra_ajuste_agregar(bigint,bigint,text,numeric,text,boolean,uuid)'::regprocedure), false)

  union all
  -- 32) Informativa: si todo es 0, las comprobaciones 19-28 pasan por vacío.
  select 32, 'volumen',
    'informativa',
    (select count(*)::text from compras_inv) || ' compra(s) de inversores · '
      || (select count(*)::text from aportes where estado = 'aportado') || ' aporte(s) vigente(s) · '
      || (select count(*)::text from aportes where estado = 'devuelto') || ' devuelto(s) · '
      || coalesce((select sum(monto_eq_total)::text from aportes where estado = 'aportado'), '0')
      || ' cubierto vs '
      || coalesce((select sum(total_financiado)::text from compras_inv), '0') || ' a financiar',
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