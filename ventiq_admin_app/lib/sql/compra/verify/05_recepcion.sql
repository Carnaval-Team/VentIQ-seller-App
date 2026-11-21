-- ============================================================================
-- verify/05_recepcion.sql — Fase 5: recepción contra compra
--
-- REQUIERE: 05a_compra_recepcion.sql y 05c_carril_b.sql aplicados en `newa`
--           (qhprswhhfasrikhawjoz), con 04 ya en su sitio.
--
-- SOLO LECTURA: SELECT / information_schema / pg_catalog / pg_proc /
-- pg_constraint / pg_indexes. Ni DDL ni DML.
-- UNA sola sentencia (README, regla 8): un CTE no sobrevive a otra sentencia,
-- así que el resumen va como fila UNION ALL con n = 99.
--
-- Contrastado contra `newa` antes de entregarlo: las firmas de abajo son las
-- que la base tiene de verdad, no las que el .sql pretendía crear. En
-- particular `fn_fdi_registrar_recepcion` quedó con UNA firma de 4 args
-- (jsonb, jsonb, uuid, bigint) y `p_id_compra` con DEFAULT NULL::bigint; la de
-- 3 args fue dropeada por 05c.
--
-- Comprobaciones de INVARIANTE (siguen valiendo con datos nuevos):
--   n=1..3    columnas de importadora con su NOT NULL/DEFAULT, sus 2 CHECK y
--             `app_dat_operacion_recepcion.fecha_operacion`
--   n=4..5    las 2 RPC nuevas con su firma exacta, jsonb y SECURITY DEFINER
--   n=6..7    `fn_fdi_registrar_recepcion`: una sola firma, 4 args, y
--             `p_id_compra` es el 4º argumento con DEFAULT
--   n=8       el CHECK de `motivo_revision` admite `recepcion_cancelada`
--   n=9..10   `fn_fdi_desvincular_recepcion` marca el motivo y
--             `fn_fdi_vincular_recepcion` lo rechaza (ambos por cuerpo)
--   n=11      ninguna línea con `recibido > cantidad` sin exceso confirmado
--   n=12..13  Σ `cantidad_recibida` por línea = lo que reporta
--             `fn_fdi_compra_recepcion_pendiente` (ni líneas de menos ni de más)
--   n=14..15  `completada` ⇒ pendiente 0 en todas sus líneas;
--             `entrega_parcial` ⇒ pendiente total > 0
--   n=16      `monto_importadora = round(base × pct / 100, 2) − reembolso`
--   n=17      UNIQUE(id_operacion, id_compra), sin duplicados y sin que una
--             recepción se reparta entre dos compras
--   n=18      conciliación del fondo (réplica de fn_fdi_conciliacion), 0 descuadres
--   n=19..21  (informativas) volumen, cargos de importadora y capacidad de
--             persistir el exceso confirmado en el vínculo
--   n=99      resumen
--
-- NOTA sobre n=11 / n=21: `fdi_dat_compra_recepcion` NO tiene columna de
-- exceso confirmado. El único rastro persistido de "exceso confirmado" es
-- `fdi_dat_inversion_recepcion.confirmada_con_exceso` (carril B), así que el
-- indulto de n=11 se apoya ahí. Un exceso confirmado en carril A puro no es
-- distinguible de un exceso real: n=11 lo marca como fallo (lado estricto).
-- ============================================================================

with
-- Firmas exactas tal como quedaron en `newa` (pg_proc.oid::regprocedure).
firmas as (
    select * from (values
        ('pendiente',   'public.fn_fdi_compra_recepcion_pendiente(bigint)'),
        ('vincular',    'public.fn_fdi_compra_vincular_recepcion(bigint,bigint,jsonb,boolean,numeric,numeric,numeric,text)'),
        ('registrar',   'public.fn_fdi_registrar_recepcion(jsonb,jsonb,uuid,bigint)'),
        ('desvincular', 'public.fn_fdi_desvincular_recepcion(bigint)')
    ) v(nombre, firma)
),

-- Líneas según la RPC (fuente de verdad del "falta por llegar").
linea_fn as (
    select c.id                        as id_compra,
           (e->>'id_linea')::bigint    as id_linea,
           (e->>'cantidad')::numeric   as cantidad,
           (e->>'recibido')::numeric   as recibido,
           (e->>'pendiente')::numeric  as pendiente
      from public.fdi_dat_compra c
      cross join lateral jsonb_array_elements(
            coalesce(public.fn_fdi_compra_recepcion_pendiente(c.id)->'lineas', '[]'::jsonb)) e
),

-- Las mismas líneas calculadas contra el catálogo.
linea_sql as (
    select l.id as id_linea, l.id_compra, l.cantidad,
           coalesce(sum(rl.cantidad_recibida), 0)                    as recibido,
           round(l.cantidad - coalesce(sum(rl.cantidad_recibida), 0), 4) as pendiente
      from public.fdi_dat_compra_linea l
      left join public.fdi_dat_compra_recepcion_linea rl on rl.id_compra_linea = l.id
     group by l.id, l.id_compra, l.cantidad
),

deriva as (
    select s.id_linea, s.id_compra, s.cantidad, s.recibido, s.pendiente,
           f.id_linea is null as falta_en_fn,
           f.recibido          as f_recibido,
           f.pendiente         as f_pendiente
      from linea_sql s
      left join linea_fn f on f.id_linea = s.id_linea and f.id_compra = s.id_compra
),

-- Sobre-recepción y su único indulto persistido (exceso confirmado del vínculo).
exceso as (
    select s.id_linea,
           s.recibido > s.cantidad + 0.00005 as excede,
           exists (
               select 1
                 from public.fdi_dat_compra_recepcion_linea rl
                 join public.fdi_dat_compra_recepcion r   on r.id = rl.id_compra_recepcion
                 join public.fdi_dat_inversion_recepcion ir on ir.id_operacion = r.id_operacion
                where rl.id_compra_linea = s.id_linea
                  and ir.confirmada_con_exceso
           ) as exceso_confirmado
      from linea_sql s
),

-- Pendiente agregado por compra, con la misma lógica que usa la RPC de estado.
estado_pend as (
    select c.id, c.estado,
           coalesce(sum(greatest(d.cantidad - d.recibido, 0)), 0)             as pendiente_total,
           count(*) filter (where d.recibido < d.cantidad - 0.00005)          as lineas_con_pendiente
      from public.fdi_dat_compra c
      left join linea_sql d on d.id_compra = c.id
     group by c.id, c.estado
),

-- Réplica exacta de fn_fdi_conciliacion, sin llamarla: saldo vs Σ movimientos
-- y saldo vs el saldo_nuevo del último movimiento.
concat_ as (
    select s.id_tienda, s.id_cuenta, s.id_medio_pago, s.moneda, s.saldo,
           coalesce(m.suma_mov, 0)                             as suma_mov,
           u.saldo_nuevo                                       as ultimo_saldo_nuevo,
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

  -- 1) Las 5 columnas de importadora
  select 1 as n, 'columnas_importadora_5' as chequeo,
    'pct/base/monto/reembolso_importadora y origen_pago: NOT NULL y con DEFAULT' as esperado,
    (select count(*)::text from information_schema.columns
      where table_schema = 'public' and table_name = 'fdi_dat_compra_recepcion'
        and column_name in ('pct_importadora','base_importadora','monto_importadora',
                            'reembolso_importadora','origen_pago')
        and is_nullable = 'NO' and column_default is not null) || ' de 5' as actual,
    (select count(*) = 5 from information_schema.columns
      where table_schema = 'public' and table_name = 'fdi_dat_compra_recepcion'
        and column_name in ('pct_importadora','base_importadora','monto_importadora',
                            'reembolso_importadora','origen_pago')
        and is_nullable = 'NO' and column_default is not null) as ok

  union all
  -- 2) Los 2 CHECK: rango del porcentaje y origen de pago
  select 2, 'check_importadora_2',
    'CHECK pct_importadora en [0,100] y CHECK origen_pago con fondo/wallet_importadora/wallet_proveedor/externo',
    (select coalesce(string_agg(conname, ', ' order by conname), 'ninguno')
       from pg_constraint
      where conrelid = 'public.fdi_dat_compra_recepcion'::regclass and contype = 'c'
        and conname in ('fdi_dat_compra_recepcion_pct_importadora_check',
                        'fdi_dat_compra_recepcion_origen_pago_check')),
    -- Ojo: pg_get_constraintdef imprime `<= (100)::numeric`, con paréntesis, así
    -- que LIKE '%<= 100%' no engancha. El rango va por regex, y el límite de
    -- palabra es `\y` (en ARE, `\b` es backspace, no frontera de palabra).
    (select count(*) = 2 from pg_constraint cn
      where cn.conrelid = 'public.fdi_dat_compra_recepcion'::regclass
        and cn.contype = 'c'
        and (   (cn.conname = 'fdi_dat_compra_recepcion_pct_importadora_check'
                 and pg_get_constraintdef(cn.oid) ~ 'pct_importadora\s*>=\s*\(?0\y'
                 and pg_get_constraintdef(cn.oid) ~ 'pct_importadora\s*<=\s*\(?100\y')
             or (cn.conname = 'fdi_dat_compra_recepcion_origen_pago_check'
                 and pg_get_constraintdef(cn.oid) like '%wallet_proveedor%'
                 and pg_get_constraintdef(cn.oid) like '%externo%')))

  union all
  -- 3) fecha_operacion en la recepción
  select 3, 'fecha_operacion',
    'app_dat_operacion_recepcion.fecha_operacion, date y nullable',
    (select coalesce(string_agg(data_type || ' nullable=' || is_nullable, ', '), 'ausente')
       from information_schema.columns
      where table_schema = 'public' and table_name = 'app_dat_operacion_recepcion'
        and column_name = 'fecha_operacion'),
    exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'app_dat_operacion_recepcion'
               and column_name = 'fecha_operacion'
               and data_type = 'date' and is_nullable = 'YES')

  union all
  -- 4) RPC del pendiente
  select 4, 'rpc_pendiente',
    'fn_fdi_compra_recepcion_pendiente(bigint) -> jsonb, SECURITY DEFINER',
    coalesce((select p.oid::regprocedure::text || ' -> ' || pg_get_function_result(p.oid)
                     || ', definer=' || p.prosecdef
                from pg_proc p
               where p.oid = to_regprocedure('public.fn_fdi_compra_recepcion_pendiente(bigint)')),
             'ausente'),
    coalesce((select p.prosecdef and pg_get_function_result(p.oid) = 'jsonb'
                from pg_proc p
               where p.oid = to_regprocedure('public.fn_fdi_compra_recepcion_pendiente(bigint)')),
             false)

  union all
  -- 5) RPC del vínculo, con su firma exacta de 8 args
  select 5, 'rpc_vincular_firma',
    'fn_fdi_compra_vincular_recepcion(bigint,bigint,jsonb,boolean,numeric,numeric,numeric,text) -> jsonb',
    coalesce((select p.oid::regprocedure::text
                from pg_proc p
               where p.oid = to_regprocedure('public.fn_fdi_compra_vincular_recepcion(bigint,bigint,jsonb,boolean,numeric,numeric,numeric,text)')),
             'ausente'),
    to_regprocedure('public.fn_fdi_compra_vincular_recepcion(bigint,bigint,jsonb,boolean,numeric,numeric,numeric,text)') is not null

  union all
  -- 6) Una sola firma de fn_fdi_registrar_recepcion y con 4 args
  select 6, 'registrar_una_firma_4',
    'exactamente 1 firma de fn_fdi_registrar_recepcion, de 4 args (la de 3 fue dropeada)',
    (select count(*)::text from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
      where ns.nspname = 'public' and p.proname = 'fn_fdi_registrar_recepcion') || ' firma(s), '
      || (select count(*)::text from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
           where ns.nspname = 'public' and p.proname = 'fn_fdi_registrar_recepcion'
             and p.pronargs = 4) || ' de 4 args',
    (select count(*) = 1 from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
      where ns.nspname = 'public' and p.proname = 'fn_fdi_registrar_recepcion')
    and
    (select count(*) = 1 from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
      where ns.nspname = 'public' and p.proname = 'fn_fdi_registrar_recepcion'
        and p.pronargs = 4)

  union all
  -- 7) p_id_compra es el 4º argumento y tiene DEFAULT
  select 7, 'registrar_p_id_compra_default',
    'proargnames = p_recepcion, p_fuentes, p_idempotency_key, p_id_compra y DEFAULT en el 4º',
    coalesce((select array_to_string(p.proargnames, ',')
                     || ' | defaults=' || coalesce(pg_get_expr(p.proargdefaults, 0), 'ninguno')
                from pg_proc p
               where p.oid = to_regprocedure('public.fn_fdi_registrar_recepcion(jsonb,jsonb,uuid,bigint)')),
             'ausente'),
    coalesce((select p.proargnames[4] = 'p_id_compra' and p.proargdefaults is not null
                from pg_proc p
               where p.oid = to_regprocedure('public.fn_fdi_registrar_recepcion(jsonb,jsonb,uuid,bigint)')),
             false)

  union all
  -- 8) El CHECK de motivo_revision admite recepcion_cancelada
  select 8, 'check_motivo_revision',
    'fdi_dat_inversion_motivo_revision_check incluye recepcion_cancelada',
    coalesce((select pg_get_constraintdef(oid) from pg_constraint
               where conrelid = 'public.fdi_dat_inversion'::regclass
                 and conname = 'fdi_dat_inversion_motivo_revision_check'),
             'ausente'),
    (select count(*) = 1 from pg_constraint
      where conrelid = 'public.fdi_dat_inversion'::regclass
        and conname = 'fdi_dat_inversion_motivo_revision_check'
        and pg_get_constraintdef(oid) like '%recepcion_cancelada%')

  union all
  -- 9) Desvincular marca la inversión
  select 9, 'desvincular_marca_revision',
    'fn_fdi_desvincular_recepcion escribe motivo_revision = recepcion_cancelada',
    coalesce((select (p.prosrc like '%recepcion_cancelada%')::text
                     || ' (prosrc ' || length(p.prosrc) || ' bytes)'
                from pg_proc p
               where p.oid = to_regprocedure('public.fn_fdi_desvincular_recepcion(bigint)')),
             'ausente'),
    coalesce((select p.prosrc like '%recepcion_cancelada%'
                from pg_proc p
               where p.oid = to_regprocedure('public.fn_fdi_desvincular_recepcion(bigint)')),
             false)

  union all
  -- 10) Vincular rechaza las inversiones marcadas
  select 10, 'vincular_rechaza_marcadas',
    'fn_fdi_vincular_recepcion menciona recepcion_cancelada para rechazarla',
    coalesce((select (p.prosrc like '%recepcion_cancelada%')::text
                     || ' (prosrc ' || length(p.prosrc) || ' bytes)'
                from pg_proc p
               where p.oid = to_regprocedure('public.fn_fdi_vincular_recepcion(bigint,bigint,numeric,text,numeric,boolean)')),
             'ausente'),
    coalesce((select p.prosrc like '%recepcion_cancelada%'
                from pg_proc p
               where p.oid = to_regprocedure('public.fn_fdi_vincular_recepcion(bigint,bigint,numeric,text,numeric,boolean)')),
             false)

  union all
  -- 11) INVARIANTE: nadie recibe más de lo comprado sin exceso confirmado
  select 11, 'sin_sobre_recepcion',
    'ninguna línea con recibido > cantidad, salvo exceso confirmado en el vínculo',
    (select count(*)::text from exceso where excede) || ' excedidas, '
      || (select count(*)::text from exceso where excede and exceso_confirmado) || ' confirmadas, '
      || (select count(*)::text from exceso where excede and not exceso_confirmado) || ' sin confirmar',
    (select count(*) = 0 from exceso where excede and not exceso_confirmado)

  union all
  -- 12) INVARIANTE: Σ recibida = lo que dice la RPC (recibido y pendiente)
  select 12, 'suma_recibida_igual_a_rpc',
    'recibido y pendiente por línea del catálogo = los de fn_fdi_compra_recepcion_pendiente',
    (select count(*)::text from deriva) || ' líneas, '
      || (select count(*)::text from deriva where falta_en_fn) || ' ausentes en la RPC, '
      || (select count(*)::text from deriva
           where not falta_en_fn
             and (abs(recibido - f_recibido) >= 0.00005
                  or abs(pendiente - f_pendiente) >= 0.00005)) || ' desviadas',
    (select count(*) = 0 from deriva
      where falta_en_fn
         or (not falta_en_fn
             and (abs(recibido - f_recibido) >= 0.00005
                  or abs(pendiente - f_pendiente) >= 0.00005)))

  union all
  -- 13) INVARIANTE: la RPC no inventa líneas que el catálogo no tiene
  select 13, 'rpc_no_inventa_lineas',
    'cada línea que reporta la RPC existe en fdi_dat_compra_linea con el mismo id_compra',
    (select count(*)::text from linea_fn f
      where not exists (select 1 from public.fdi_dat_compra_linea l
                         where l.id = f.id_linea and l.id_compra = f.id_compra)) || ' líneas inventadas',
    (select count(*) = 0 from linea_fn f
      where not exists (select 1 from public.fdi_dat_compra_linea l
                         where l.id = f.id_linea and l.id_compra = f.id_compra))

  union all
  -- 14) INVARIANTE: completada ⇒ pendiente 0 en todas sus líneas
  select 14, 'completada_pendiente_0',
    'toda compra completada tiene pendiente 0 en todas sus líneas',
    (select count(*)::text from estado_pend where estado = 'completada') || ' completadas, '
      || (select count(*)::text from estado_pend
           where estado = 'completada' and lineas_con_pendiente > 0) || ' con pendiente',
    (select count(*) = 0 from estado_pend
      where estado = 'completada' and lineas_con_pendiente > 0)

  union all
  -- 15) INVARIANTE: entrega_parcial ⇒ pendiente > 0
  select 15, 'parcial_pendiente_positivo',
    'toda compra entrega_parcial tiene pendiente total > 0',
    (select count(*)::text from estado_pend where estado = 'entrega_parcial') || ' parciales, '
      || (select count(*)::text from estado_pend
           where estado = 'entrega_parcial' and pendiente_total <= 0.00005) || ' sin pendiente',
    (select count(*) = 0 from estado_pend
      where estado = 'entrega_parcial' and pendiente_total <= 0.00005)

  union all
  -- 16) INVARIANTE: el cargo de importadora cuadra con base × pct − reembolso
  select 16, 'monto_importadora_cuadra',
    'monto_importadora = round(base_importadora × pct_importadora / 100, 2) − reembolso_importadora',
    (select count(*)::text from public.fdi_dat_compra_recepcion) || ' vínculos, '
      || (select count(*)::text from public.fdi_dat_compra_recepcion
           where abs(monto_importadora
                     - (round(base_importadora * pct_importadora / 100.0, 2)
                        - reembolso_importadora)) >= 0.005) || ' descuadrados',
    (select count(*) = 0 from public.fdi_dat_compra_recepcion
      where abs(monto_importadora
                - (round(base_importadora * pct_importadora / 100.0, 2)
                   - reembolso_importadora)) >= 0.005)

  union all
  -- 17) INVARIANTE: UNIQUE(id_operacion, id_compra) y una recepción, una compra
  select 17, 'vinculo_unico_operacion_compra',
    'UNIQUE(id_operacion,id_compra) existe, 0 pares duplicados y ninguna recepción repartida en 2 compras',
    (select count(*)::text from pg_constraint
      where conrelid = 'public.fdi_dat_compra_recepcion'::regclass and contype = 'u'
        and conname = 'fdi_dat_compra_recepcion_id_operacion_id_compra_key') || ' UNIQUE, '
      || (select count(*)::text from (select id_operacion, id_compra
                                        from public.fdi_dat_compra_recepcion
                                       group by 1, 2 having count(*) > 1) d) || ' pares duplicados, '
      || (select count(*)::text from (select id_operacion
                                        from public.fdi_dat_compra_recepcion
                                       group by 1 having count(distinct id_compra) > 1) x) || ' recepciones en >1 compra',
    (select count(*) = 1 from pg_constraint
      where conrelid = 'public.fdi_dat_compra_recepcion'::regclass and contype = 'u'
        and conname = 'fdi_dat_compra_recepcion_id_operacion_id_compra_key')
    and
    (select count(*) = 0 from (select id_operacion, id_compra
                                 from public.fdi_dat_compra_recepcion
                                group by 1, 2 having count(*) > 1) d)
    and
    (select count(*) = 0 from (select id_operacion
                                 from public.fdi_dat_compra_recepcion
                                group by 1 having count(distinct id_compra) > 1) x)

  union all
  -- 18) INVARIANTE: el fondo sigue cuadrado
  select 18, 'conciliacion_fondo_0',
    '0 descuadres: |saldo − Σ movimientos| y |saldo − último saldo_nuevo| < 0.005',
    (select count(*)::text from concat_) || ' claves, '
      || (select count(*)::text from concat_
           where abs(dif_saldo_vs_mov) >= 0.005
              or abs(dif_saldo_vs_ultimo) >= 0.005) || ' descuadres',
    (select count(*) = 0 from concat_
      where abs(dif_saldo_vs_mov) >= 0.005
         or abs(dif_saldo_vs_ultimo) >= 0.005)

  union all
  -- 19) (informativa) volumen de la fase 5
  select 19, 'volumen_fase5',
    'foto de datos, no un fallo',
    'compras=' || (select count(*)::text from public.fdi_dat_compra)
      || ', líneas=' || (select count(*)::text from public.fdi_dat_compra_linea)
      || ', vínculos=' || (select count(*)::text from public.fdi_dat_compra_recepcion)
      || ', líneas recibidas=' || (select count(*)::text from public.fdi_dat_compra_recepcion_linea)
      || ', recepciones=' || (select count(*)::text from public.app_dat_operacion_recepcion)
      || ', completadas=' || (select count(*)::text from public.fdi_dat_compra where estado = 'completada')
      || ', parciales=' || (select count(*)::text from public.fdi_dat_compra where estado = 'entrega_parcial')
      || ', con fecha_operacion=' || (select count(*)::text from public.app_dat_operacion_recepcion
                                       where fecha_operacion is not null),
    true

  union all
  -- 20) (informativa) cuánto cargo de importadora hay registrado
  select 20, 'cargos_importadora',
    'foto de datos, no un fallo',
    (select count(*)::text from public.fdi_dat_compra_recepcion
      where abs(monto_importadora) > 0.004) || ' vínculos con cargo ≠ 0, '
      || (select count(*)::text from public.fdi_dat_compra_recepcion
           where reembolso_importadora > 0) || ' con reembolso, '
      || (select coalesce(string_agg(distinct origen_pago, ', '), 'ninguno')
            from public.fdi_dat_compra_recepcion),
    true

  union all
  -- 21) (informativa) ¿se puede persistir el exceso confirmado en el vínculo?
  select 21, 'exceso_confirmado_capacidad',
    'ideal: columna propia en fdi_dat_compra_recepcion para el exceso confirmado',
    (select count(*)::text from information_schema.columns
      where table_schema = 'public' and table_name = 'fdi_dat_compra_recepcion'
        and column_name ilike '%exceso%') || ' columnas de exceso en el vínculo; '
      || 'indulto tomado de fdi_dat_inversion_recepcion.confirmada_con_exceso',
    true
)

-- 99) Resumen: cuenta las filas con ok = false (las informativas siempre ok).
select * from base
union all
select 99 as n, 'RESUMEN' as chequeo,
       '0 fallos' as esperado,
       (select count(*)::text from base where not ok) || ' fallo(s) de '
         || (select count(*)::text from base) || ' comprobaciones' as actual,
       (select count(*) = 0 from base where not ok) as ok
order by n;