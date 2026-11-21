-- ============================================================================
-- verify/06_costos.sql — Fase 6: costo aterrizado (06a + 06b)
--
-- REQUIERE: 06a_costo_aterrizado_base.sql y 06b_aterrizaje.sql aplicados en
--           `newa` (qhprswhhfasrikhawjoz).
--
-- SOLO LECTURA: SELECT / information_schema / pg_catalog / pg_proc. Ni DDL ni
-- DML, ni una llamada a las funciones que escriben.
-- UNA sola sentencia (README, regla 8): un CTE no sobrevive a otra sentencia,
-- así que el resumen va como fila UNION ALL con n = 99.
--
-- No llama a `fn_fdi_compra_repartir_aterrizaje` (escribe) ni a
-- `fn_fdi_recepcion_con_costos` (escribe). De `fn_fdi_compra_recepcion_bases`
-- sólo se comprueba la firma: si no existiera, llamarla rompería el script
-- entero en vez de reportar, y este archivo debe degradar a "ausente".
--
-- Comprobaciones de INVARIANTE (siguen valiendo con datos nuevos):
--   n=1   catálogo con los 4 tipos (Aduana, Flete, Importadora, Seguro),
--         naturaleza 1 y afecta_margen = true
--   n=2   'Importadora' resoluble y NO ambigua (una sola fila): el aterrizaje
--         se niega a elegir si hay dos
--   n=3   columnas del vínculo: las 5 de importadora con NOT NULL y DEFAULT,
--         más confirmada_con_exceso
--   n=4   las 3 funciones de 06b con su firma exacta
--   n=5   las 2 que devuelven jsonb son SECURITY DEFINER y p_tasa_usd tiene
--         DEFAULT NULL (sin tasa se lee la de la operación)
--   n=6   Σ monto_usd del tipo Importadora por recepción = cargo convertido
--         (sólo verificable en vínculos con moneda USD: ver nota)
--   n=7   ninguna fila con id_tipo_costo inexistente en el catálogo
--   n=8   monto_promedio_anterior >= 0 en todas las filas
--   n=9   sin duplicados por (id_recepcion_producto, id_tipo_costo)
--   n=10  monto_usd finito y no negativo
--   n=11  (informativa) vínculos que no son USD y su tasa persistida
--   n=12  (informativa) vínculos en USD sin aterrizaje (fondo, cargo 0 o
--         anteriores a 06b)
--   n=13  (informativa) volumen de la fase 6
--   n=14  `fdi_dat_compra_recepcion.tasa_usd_aplicada` existe y, en vínculos
--         con moneda USD, nunca vale algo distinto de 1; si el vínculo USD ya
--         tiene aterrizaje, vale exactamente 1 (no NULL)
--   n=15  las operaciones con costos capitalizados tienen
--         `app_dat_operacion_recepcion.tasa_cambio_aplicada` no nula (y las
--         dos columnas de tasa de la operación existen)
--   n=16  (D10) `app_dat_recepcion_producto_costo.id_compra_recepcion` existe,
--         es bigint NULL, con FK al vínculo y con índice
--   n=17  (D10) ninguna fila de costo está atribuida a un vínculo cuya
--         operación difiera de la de su línea de recepción
--   n=18  (D9) la moneda del vínculo, cuando está informada, es la de la
--         operación: ninguna discrepancia
--   n=19  los cuerpos aplicados son los de esta versión: `bases` compila en
--         plpgsql, el reparto aborta por moneda y borra por vínculo, y el
--         wrapper exige tasa cuando la factura no es USD
--   n=20  (D10) en una operación con un solo vínculo, ninguna fila de
--         Importadora queda sin atribuir
--   n=99  resumen
--
-- NOTA sobre n=6 — QUÉ SE PUEDE COMPROBAR:
--   `fn_fdi_compra_repartir_aterrizaje` convierte con una tasa que ya **sí se
--   persiste**: `app_dat_operacion_recepcion.tasa_cambio_aplicada` (fuente
--   única, la escribe el wrapper y el propio reparto) y
--   `fdi_dat_compra_recepcion.tasa_usd_aplicada` (la escribe el reparto por el
--   `id` del vínculo). Por eso:
--     · moneda USD  → tasa 1 (la función la fuerza) y el invariante es
--                     Σ monto_usd = monto_importadora. Se comprueba.
--     · moneda ≠ USD → el cargo en USD se recalcula con la tasa de la
--                     operación. n=11 informa de los vínculos con tasa
--                     persistida y de los que aún no la tienen; no falla por
--                     datos anteriores a 06b.
-- ============================================================================

with
-- Id del tipo de costo 'Importadora' (el aterrizaje lo resuelve igual: por
-- denominación, sin caja ni espacios, nunca por id hardcodeado).
tipo_imp as (
    select t.id
      from public.app_cont_tipo_costo t
     where lower(btrim(t.denominacion)) = 'importadora'
     order by t.id
     limit 1
),

catalogo as (
    select count(*) filter (
               where lower(btrim(t.denominacion)) in ('aduana','flete','importadora','seguro')
           ) as tipos,
           count(*) filter (
               where lower(btrim(t.denominacion)) in ('aduana','flete','importadora','seguro')
                 and t.naturaleza = 1
                 and t.afecta_margen
           ) as tipos_ok,
           count(*) filter (where lower(btrim(t.denominacion)) = 'importadora') as importadoras
      from public.app_cont_tipo_costo t
),

-- Costos por recepción, separando el tipo Importadora del resto. Es el respaldo
-- para las filas anteriores a D10 (sin atribución).
por_recepcion as (
    select rp.id_operacion,
           coalesce(sum(c.monto_usd) filter (where c.id_tipo_costo = (select id from tipo_imp)), 0) as suma_imp,
           count(c.id)          filter (where c.id_tipo_costo = (select id from tipo_imp))          as filas_imp,
           count(c.id)                                                                              as filas_todas
      from public.app_dat_recepcion_productos rp
      left join public.app_dat_recepcion_producto_costo c on c.id_recepcion_producto = rp.id
     group by rp.id_operacion
),

-- Costos del aterrizaje por VÍNCULO (D10): es la medida correcta cuando una
-- operación cubre varias compras; el reparto ya escribe esta atribución.
por_vinculo as (
    select c.id_compra_recepcion as id_vinculo,
           coalesce(sum(c.monto_usd) filter (where c.id_tipo_costo = (select id from tipo_imp)), 0) as suma_imp,
           count(*)              filter (where c.id_tipo_costo = (select id from tipo_imp))          as filas_imp
      from public.app_dat_recepcion_producto_costo c
     where c.id_compra_recepcion is not null
     group by c.id_compra_recepcion
),

vinculos as (
    select r.id,
           r.id_operacion,
           r.monto_importadora,
           r.origen_pago,
           upper(btrim(coalesce(r.moneda, ''))) as moneda,
           upper(btrim(coalesce(o.moneda_factura, ''))) as moneda_op,
           r.tasa_usd_aplicada,
           coalesce(pv.suma_imp, pr.suma_imp, 0) as suma_imp,
           coalesce(pv.filas_imp, pr.filas_imp, 0) as filas_imp,
           (select count(*) from public.fdi_dat_compra_recepcion r2
             where r2.id_operacion = r.id_operacion) as n_vinculos_op
      from public.fdi_dat_compra_recepcion r
      left join public.app_dat_operacion_recepcion o on o.id_operacion = r.id_operacion
      left join por_recepcion pr on pr.id_operacion = r.id_operacion
      left join por_vinculo pv on pv.id_vinculo = r.id
),

-- (D10) Cada fila de costo con su vínculo y la operación de su línea: sirve
-- para detectar atribuciones cruzadas entre compras de la misma carga.
costos_por_vinculo as (
    select c.id,
           c.id_recepcion_producto,
           c.id_compra_recepcion,
           r.id_operacion  as id_op_vinculo,
           rp.id_operacion as id_op_linea
      from public.app_dat_recepcion_producto_costo c
      left join public.fdi_dat_compra_recepcion r on r.id = c.id_compra_recepcion
      left join public.app_dat_recepcion_productos rp on rp.id = c.id_recepcion_producto
),

-- (D10) Filas de Importadora sin atribuir en una operación con un solo vínculo:
-- después del backfill de 06b no debe quedar ninguna.
huerfanos_vinculo as (
    select c.id
      from public.app_dat_recepcion_producto_costo c
      join public.app_dat_recepcion_productos rp on rp.id = c.id_recepcion_producto
     where c.id_tipo_costo = (select id from tipo_imp)
       and c.id_compra_recepcion is null
       and (select count(*) from public.fdi_dat_compra_recepcion r
             where r.id_operacion = rp.id_operacion) = 1
),

-- Operaciones con costos capitalizados: por cada línea de recepción con costo
-- (de cualquier tipo), la operación dueña de esa línea.
ops_con_costos as (
    select distinct rp.id_operacion
      from public.app_dat_recepcion_productos rp
      join public.app_dat_recepcion_producto_costo c on c.id_recepcion_producto = rp.id
),

duplicados as (
    select c.id_recepcion_producto, c.id_tipo_costo, count(*) as veces
      from public.app_dat_recepcion_producto_costo c
     group by c.id_recepcion_producto, c.id_tipo_costo
    having count(*) > 1
),

huerfanos as (
    select c.id
      from public.app_dat_recepcion_producto_costo c
     where not exists (select 1 from public.app_cont_tipo_costo t where t.id = c.id_tipo_costo)
),

promedios_raros as (
    select c.id
      from public.app_dat_recepcion_producto_costo c
     where c.monto_promedio_anterior < 0
),

montos_raros as (
    select c.id
      from public.app_dat_recepcion_producto_costo c
     where c.monto_usd < 0
        or c.monto_usd = 'NaN'::numeric
        or c.monto_usd >= 'Infinity'::numeric
),

base as (

  -- 1) Catálogo con los 4 tipos
  select 1 as n, 'catalogo_4_tipos' as chequeo,
    'Aduana, Flete, Importadora y Seguro: naturaleza 1 y afecta_margen true' as esperado,
    (select tipos::text || ' de 4, ' || tipos_ok::text || ' con naturaleza 1 y afecta_margen'
       from catalogo) as actual,
    (select tipos = 4 and tipos_ok = 4 from catalogo) as ok

  union all
  -- 2) 'Importadora' resoluble y sin ambigüedad
  select 2, 'importadora_unica',
    'exactamente 1 fila con denominación Importadora',
    (select importadoras::text || ' fila(s)' from catalogo),
    (select importadoras = 1 from catalogo)

  union all
  -- 3) Columnas del vínculo
  select 3, 'columnas_vinculo',
    'pct/base/monto/reembolso_importadora y origen_pago: NOT NULL con DEFAULT; más confirmada_con_exceso',
    (select count(*)::text || ' de 5 con NOT NULL y DEFAULT, '
            || (select count(*)::text from information_schema.columns
                 where table_schema = 'public' and table_name = 'fdi_dat_compra_recepcion'
                   and column_name = 'confirmada_con_exceso') || ' con confirmada_con_exceso'
       from information_schema.columns
      where table_schema = 'public' and table_name = 'fdi_dat_compra_recepcion'
        and column_name in ('pct_importadora','base_importadora','monto_importadora',
                            'reembolso_importadora','origen_pago')
        and is_nullable = 'NO' and column_default is not null),
    (select count(*) = 5 from information_schema.columns
      where table_schema = 'public' and table_name = 'fdi_dat_compra_recepcion'
        and column_name in ('pct_importadora','base_importadora','monto_importadora',
                            'reembolso_importadora','origen_pago')
        and is_nullable = 'NO' and column_default is not null)
    and
    (select count(*) = 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'fdi_dat_compra_recepcion'
        and column_name = 'confirmada_con_exceso')

  union all
  -- 4) Las 3 funciones de 06b, con firma exacta
  select 4, 'funciones_06b_3',
    'fn_fdi_compra_recepcion_bases(bigint), fn_fdi_compra_repartir_aterrizaje(bigint,numeric), fn_fdi_recepcion_con_costos(jsonb,jsonb,jsonb,uuid)',
    coalesce((select p.oid::regprocedure::text
                from pg_proc p
               where p.oid = to_regprocedure('public.fn_fdi_compra_recepcion_bases(bigint)')), 'falta bases')
      || ' | '
      || coalesce((select p.oid::regprocedure::text
                     from pg_proc p
                    where p.oid = to_regprocedure('public.fn_fdi_compra_repartir_aterrizaje(bigint,numeric)')), 'falta repartir')
      || ' | '
      || coalesce((select p.oid::regprocedure::text
                     from pg_proc p
                    where p.oid = to_regprocedure('public.fn_fdi_recepcion_con_costos(jsonb,jsonb,jsonb,uuid)')), 'falta recepcion_con_costos'),
    to_regprocedure('public.fn_fdi_compra_recepcion_bases(bigint)') is not null
    and to_regprocedure('public.fn_fdi_compra_repartir_aterrizaje(bigint,numeric)') is not null
    and to_regprocedure('public.fn_fdi_recepcion_con_costos(jsonb,jsonb,jsonb,uuid)') is not null

  union all
  -- 5) SECURITY DEFINER, retorno jsonb y DEFAULT de la tasa
  select 5, 'funciones_06b_definer_tasa',
    'las 2 RPC devuelven jsonb y son SECURITY DEFINER; p_tasa_usd con DEFAULT NULL',
    (select count(*)::text from pg_proc p
      where p.oid in (to_regprocedure('public.fn_fdi_compra_repartir_aterrizaje(bigint,numeric)'),
                      to_regprocedure('public.fn_fdi_recepcion_con_costos(jsonb,jsonb,jsonb,uuid)'))
        and p.prosecdef and pg_get_function_result(p.oid) = 'jsonb') || ' de 2 definer+jsonb, default='
      || coalesce((select pg_get_expr(p.proargdefaults, 0) from pg_proc p
                    where p.oid = to_regprocedure('public.fn_fdi_compra_repartir_aterrizaje(bigint,numeric)')),
                  'ausente'),
    (select count(*) = 2 from pg_proc p
      where p.oid in (to_regprocedure('public.fn_fdi_compra_repartir_aterrizaje(bigint,numeric)'),
                      to_regprocedure('public.fn_fdi_recepcion_con_costos(jsonb,jsonb,jsonb,uuid)'))
        and p.prosecdef and pg_get_function_result(p.oid) = 'jsonb')
    and
    (select count(*) = 1 from pg_proc p
      where p.oid = to_regprocedure('public.fn_fdi_compra_repartir_aterrizaje(bigint,numeric)')
        and p.pronargdefaults = 1
        and pg_get_expr(p.proargdefaults, 0) = 'NULL::numeric')

  union all
  -- 6) INVARIANTE: Σ monto_usd del aterrizaje = el cargo (sólo USD)
  --    Se mide por vínculo (D10) y sólo en operaciones de un solo vínculo: con
  --    varias compras en la misma carga, el importe de una no tiene por qué
  --    cuadrar con la suma de todas. La suma por vínculo ya es link-scoped.
  select 6, 'suma_costos_igual_cargo_usd',
    'en vínculos USD de operaciones con un solo vínculo: Σ monto_usd del tipo Importadora = monto_importadora',
    (select count(*)::text from vinculos
      where moneda = 'USD' and n_vinculos_op = 1) || ' vínculos USD, '
      || (select count(*)::text from vinculos
           where moneda = 'USD' and n_vinculos_op = 1 and filas_imp > 0) || ' con aterrizaje, '
      || (select count(*)::text from vinculos
           where moneda = 'USD' and n_vinculos_op = 1 and filas_imp > 0
             and abs(suma_imp - monto_importadora) >= 0.005) || ' descuadrados',
    (select count(*) = 0 from vinculos
      where moneda = 'USD' and n_vinculos_op = 1 and filas_imp > 0
        and abs(suma_imp - monto_importadora) >= 0.005)

  union all
  -- 7) INVARIANTE: ningún tipo de costo inexistente
  select 7, 'sin_tipo_costo_inexistente',
    'toda fila de costo apunta a un id_tipo_costo del catálogo',
    (select count(*)::text from public.app_dat_recepcion_producto_costo) || ' filas, '
      || (select count(*)::text from huerfanos) || ' huérfanas',
    (select count(*) = 0 from huerfanos)

  union all
  -- 8) INVARIANTE: monto_promedio_anterior >= 0
  select 8, 'promedio_anterior_no_negativo',
    'monto_promedio_anterior >= 0 en todas las filas',
    (select count(*)::text from promedios_raros) || ' fila(s) negativa(s)',
    (select count(*) = 0 from promedios_raros)

  union all
  -- 9) INVARIANTE: sin duplicados por (línea de recepción, tipo de costo)
  select 9, 'sin_duplicados_linea_tipo',
    'UNIQUE lógico (id_recepcion_producto, id_tipo_costo): ninguna fila repetida',
    (select count(*)::text from public.app_dat_recepcion_producto_costo) || ' filas, '
      || (select count(*)::text from duplicados) || ' par(es) duplicado(s)',
    (select count(*) = 0 from duplicados)

  union all
  -- 10) INVARIANTE: montos utilizables
  select 10, 'monto_usd_utilizable',
    'monto_usd finito y >= 0 en todas las filas',
    (select count(*)::text from montos_raros) || ' fila(s) con monto negativo o no finito',
    (select count(*) = 0 from montos_raros)

  union all
  -- 11) (informativa) vínculos no-USD y su tasa de operación
  select 11, 'vinculos_no_usd_tasa_persistida',
    'informativa: los vínculos no-USD convierten con la tasa de la operación (tasa_cambio_aplicada)',
    (select count(*)::text from vinculos where moneda <> 'USD') || ' vínculo(s) con moneda distinta de USD ('
      || coalesce((select string_agg(distinct coalesce(nullif(moneda, ''), 'NULL'), ', ')
                     from vinculos where moneda <> 'USD'), 'ninguna') || '), '
      || (select count(*)::text
            from vinculos v
            join public.app_dat_operacion_recepcion o on o.id_operacion = v.id_operacion
           where v.moneda <> 'USD' and o.tasa_cambio_aplicada is not null) || ' con tasa de operación',
    true

  union all
  -- 12) (informativa) vínculos en USD sin filas de aterrizaje
  select 12, 'vinculos_usd_sin_aterrizaje',
    'informativa: fondo, cargo 0, o anteriores a 06b',
    (select count(*)::text from vinculos where moneda = 'USD' and filas_imp = 0) || ' sin filas de Importadora, '
      || (select count(*)::text from vinculos
           where moneda = 'USD' and filas_imp = 0
             and origen_pago IN ('wallet_importadora','externo')
             and abs(monto_importadora) > 0.004) || ' de ellas con cargo ≠ 0 y origen que debería aterrizar',
    true

  union all
  -- 13) (informativa) volumen de la fase 6
  select 13, 'volumen_fase6',
    'foto de datos, no un fallo',
    'tipos_costo=' || (select count(*)::text from public.app_cont_tipo_costo)
      || ', tipos_producto=' || (select count(*)::text from public.app_dat_producto_costo)
      || ', filas_recepcion=' || (select count(*)::text from public.app_dat_recepcion_producto_costo)
      || ', vínculos=' || (select count(*)::text from public.fdi_dat_compra_recepcion)
      || ', vínculos_con_cargo=' || (select count(*)::text from public.fdi_dat_compra_recepcion
                                      where abs(monto_importadora) > 0.004)
      || ', origen_pago=' || coalesce((select string_agg(distinct origen_pago, ', ')
                                         from public.fdi_dat_compra_recepcion), 'ninguno'),
    true

  union all
  -- 14) INVARIANTE: tasa_usd_aplicada del vínculo
  select 14, 'tasa_usd_aplicada_vinculo',
    'la columna existe numeric(18,10); en vínculos USD nunca vale ≠ 1 y, si ya hay aterrizaje, vale exactamente 1',
    (select count(*)::text from information_schema.columns
      where table_schema = 'public' and table_name = 'fdi_dat_compra_recepcion'
        and column_name = 'tasa_usd_aplicada'
        and data_type = 'numeric' and numeric_precision = 18 and numeric_scale = 10) || ' columna, '
      || (select count(*)::text from vinculos
           where moneda = 'USD' and tasa_usd_aplicada is not null
             and tasa_usd_aplicada <> 1) || ' vínculo(s) USD con tasa ≠ 1, '
      || (select count(*)::text from vinculos
           where moneda = 'USD' and filas_imp > 0
             and tasa_usd_aplicada is null) || ' vínculo(s) USD con aterrizaje y tasa NULL',
    (select count(*) = 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'fdi_dat_compra_recepcion'
        and column_name = 'tasa_usd_aplicada'
        and data_type = 'numeric' and numeric_precision = 18 and numeric_scale = 10)
    and
    (select count(*) = 0 from vinculos
      where moneda = 'USD' and tasa_usd_aplicada is not null
        and tasa_usd_aplicada <> 1)
    and
    (select count(*) = 0 from vinculos
      where moneda = 'USD' and filas_imp > 0
        and tasa_usd_aplicada is null)

  union all
  -- 15) INVARIANTE: tasa de la operación en operaciones con costos capitalizados
  select 15, 'tasa_operacion_en_costos_capitalizados',
    'las operaciones con costos tienen tasa_cambio_aplicada no nula; tasa_cambio_aplicada y fecha_tasa_aplicada existen',
    (select count(*)::text from ops_con_costos) || ' operación(es) con costos, '
      || (select count(*)::text
            from ops_con_costos oc
            join public.app_dat_operacion_recepcion o on o.id_operacion = oc.id_operacion
           where o.tasa_cambio_aplicada is null) || ' con tasa NULL, '
      || (select count(*)::text from information_schema.columns
           where table_schema = 'public' and table_name = 'app_dat_operacion_recepcion'
             and column_name in ('tasa_cambio_aplicada','fecha_tasa_aplicada')) || ' de 2 columnas',
    (select count(*) = 0
       from ops_con_costos oc
       join public.app_dat_operacion_recepcion o on o.id_operacion = oc.id_operacion
      where o.tasa_cambio_aplicada is null)
    and
    (select count(*) = 2 from information_schema.columns
      where table_schema = 'public' and table_name = 'app_dat_operacion_recepcion'
        and column_name in ('tasa_cambio_aplicada','fecha_tasa_aplicada'))

  union all
  -- 16) INVARIANTE (D10): el costo sabe a qué vínculo pertenece
  select 16, 'columna_vinculo_en_costo',
    'id_compra_recepcion: bigint NULL, FK a fdi_dat_compra_recepcion e índice idx_recepcion_producto_costo_vinculo',
    (select count(*)::text from information_schema.columns
      where table_schema = 'public' and table_name = 'app_dat_recepcion_producto_costo'
        and column_name = 'id_compra_recepcion'
        and data_type = 'bigint' and is_nullable = 'YES') || ' columna, '
      || (select count(*)::text
            from pg_constraint c
            join pg_class t on t.oid = c.conrelid
            join pg_class f on f.oid = c.confrelid
            join pg_attribute a on a.attrelid = t.oid and a.attnum = any (c.conkey)
           where c.contype = 'f'
             and t.relname = 'app_dat_recepcion_producto_costo'
             and f.relname = 'fdi_dat_compra_recepcion'
             and a.attname = 'id_compra_recepcion') || ' FK, '
      || (select count(*)::text from pg_indexes
           where schemaname = 'public' and tablename = 'app_dat_recepcion_producto_costo'
             and indexname = 'idx_recepcion_producto_costo_vinculo') || ' índice',
    (select count(*) = 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'app_dat_recepcion_producto_costo'
        and column_name = 'id_compra_recepcion'
        and data_type = 'bigint' and is_nullable = 'YES')
    and
    (select count(*) = 1
       from pg_constraint c
       join pg_class t on t.oid = c.conrelid
       join pg_class f on f.oid = c.confrelid
       join pg_attribute a on a.attrelid = t.oid and a.attnum = any (c.conkey)
      where c.contype = 'f'
        and t.relname = 'app_dat_recepcion_producto_costo'
        and f.relname = 'fdi_dat_compra_recepcion'
        and a.attname = 'id_compra_recepcion')
    and
    (select count(*) = 1 from pg_indexes
      where schemaname = 'public' and tablename = 'app_dat_recepcion_producto_costo'
        and indexname = 'idx_recepcion_producto_costo_vinculo')

  union all
  -- 17) INVARIANTE (D10): la atribución no cruza operaciones
  select 17, 'costos_del_vinculo_no_invaden',
    'ninguna fila de costo atribuida a un vínculo cuya operación difiera de la de su línea de recepción',
    (select count(*)::text from costos_por_vinculo x
      where x.id_compra_recepcion is not null
        and x.id_op_vinculo is distinct from x.id_op_linea) || ' fila(s) mal atribuida(s) de '
      || (select count(*)::text from costos_por_vinculo x
           where x.id_compra_recepcion is not null) || ' atribuidas',
    (select count(*) = 0 from costos_por_vinculo x
      where x.id_compra_recepcion is not null
        and x.id_op_vinculo is distinct from x.id_op_linea)

  union all
  -- 18) INVARIANTE (D9): moneda del vínculo = moneda de la operación
  select 18, 'moneda_vinculo_igual_operacion',
    'cuando el vínculo informa moneda, es la misma que app_dat_operacion_recepcion.moneda_factura',
    (select count(*)::text from vinculos
      where moneda <> '' and moneda_op <> '' and moneda <> moneda_op) || ' discrepancia(s) de '
      || (select count(*)::text from vinculos where moneda <> '') || ' vínculo(s) con moneda informada',
    (select count(*) = 0 from vinculos
      where moneda <> '' and moneda_op <> '' and moneda <> moneda_op)

  union all
  -- 19) Los cuerpos desplegados son los de esta versión
  --     Se comprueba con marcas que NO están en la firma (un `position` sobre
  --     el nombre del parámetro daría falso positivo): `prolang` en bases
  --     (pasó de `sql` a `plpgsql`) y mensajes propios de D8/D9 en los cuerpos
  --     de plpgsql. Si alguien reaplica un cuerpo viejo, esto lo caza.
  select 19, 'cuerpos_06b_desplegados',
    'bases compilada en plpgsql; el reparto aborta por moneda (D9) y borra por vínculo (D10); el wrapper exige tasa no-USD (D8)',
    (select count(*)::text from pg_proc p
      where p.oid = to_regprocedure('public.fn_fdi_compra_recepcion_bases(bigint)')
        and p.prolang = (select l.oid from pg_language l where l.lanname = 'plpgsql')
        and position('v_vinculos' in p.prosrc) > 0) || ' de 1 bases, '
      || (select count(*)::text from pg_proc p
           where p.oid = to_regprocedure('public.fn_fdi_compra_repartir_aterrizaje(bigint,numeric)')
             and position('no coincide con la de la operación' in p.prosrc) > 0
             and position('id_compra_recepcion = p_id_compra_recepcion' in p.prosrc) > 0) || ' de 1 reparto, '
      || (select count(*)::text from pg_proc p
           where p.oid = to_regprocedure('public.fn_fdi_recepcion_con_costos(jsonb,jsonb,jsonb,uuid)')
             and position('no se recibió la tasa' in p.prosrc) > 0) || ' de 1 wrapper',
    (select count(*) = 1 from pg_proc p
      where p.oid = to_regprocedure('public.fn_fdi_compra_recepcion_bases(bigint)')
        and p.prolang = (select l.oid from pg_language l where l.lanname = 'plpgsql')
        and position('v_vinculos' in p.prosrc) > 0)
    and
    (select count(*) = 1 from pg_proc p
      where p.oid = to_regprocedure('public.fn_fdi_compra_repartir_aterrizaje(bigint,numeric)')
        and position('no coincide con la de la operación' in p.prosrc) > 0
        and position('id_compra_recepcion = p_id_compra_recepcion' in p.prosrc) > 0)
    and
    (select count(*) = 1 from pg_proc p
      where p.oid = to_regprocedure('public.fn_fdi_recepcion_con_costos(jsonb,jsonb,jsonb,uuid)')
        and position('no se recibió la tasa' in p.prosrc) > 0)

  union all
  -- 20) INVARIANTE (D10): con un solo vínculo, todo lo de Importadora queda atribuido
  select 20, 'aterrizaje_siempre_atribuido',
    'en una operación con un solo vínculo, ninguna fila del tipo Importadora queda con id_compra_recepcion NULL',
    (select count(*)::text from huerfanos_vinculo) || ' fila(s) sin atribuir en operaciones de un solo vínculo',
    (select count(*) = 0 from huerfanos_vinculo)
)

-- 99) Resumen: cuenta las filas con ok = false (las informativas siempre ok).
select * from base
union all
select 99 as n, 'RESUMEN' as chequeo,
       '0 fallos' as esperado,
       (select count(*)::text from base where not ok) || ' fallo(s) de '
         || (select count(*)::text from base) || ' comprobaciones' as actual,
       (select count(*) = 0 from base where not ok) as ok
  from (select 1) z
order by n;