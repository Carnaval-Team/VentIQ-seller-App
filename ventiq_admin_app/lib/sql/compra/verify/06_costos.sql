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
--         DEFAULT 1
--   n=6   Σ monto_usd del tipo Importadora por recepción = cargo convertido
--         (sólo verificable en vínculos con moneda USD: ver nota)
--   n=7   ninguna fila con id_tipo_costo inexistente en el catálogo
--   n=8   monto_promedio_anterior >= 0 en todas las filas
--   n=9   sin duplicados por (id_recepcion_producto, id_tipo_costo)
--   n=10  monto_usd finito y no negativo
--   n=11  (informativa) vínculos que no son USD: la tasa aplicada no se
--         persiste, así que su reparto no se puede re-derivar
--   n=12  (informativa) vínculos en USD sin aterrizaje (fondo, cargo 0 o
--         anteriores a 06b)
--   n=13  (informativa) volumen de la fase 6
--   n=99  resumen
--
-- NOTA sobre n=6 — POR QUÉ NO SE COMPRUEBA TODO:
--   `fn_fdi_compra_repartir_aterrizaje` convierte con `p_tasa_usd`, y **esa
--   tasa no se guarda en ninguna columna**: `fdi_dat_compra_recepcion` sólo
--   tiene `moneda` y `tasa_a_base`, y esta última la escribe
--   `fn_fdi_compra_vincular_recepcion` siempre como 1 (no es una tasa a USD).
--   Por eso:
--     · moneda USD  → tasa 1 (la función la fuerza) y el invariante es
--                     Σ monto_usd = monto_importadora. Se comprueba.
--     · moneda ≠ USD → el cargo en USD no se puede recalcular. Se informa en
--                     n=11 y NO se marca como fallo: fallar aquí sería culpar
--                     al dato de una carencia del esquema.
--   Si el lead quiere auditoría completa, hace falta
--   `fdi_dat_compra_recepcion.tasa_usd_aplicada numeric`. 06b NO la añade.
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

-- Costos por recepción, separando el tipo Importadora del resto.
por_recepcion as (
    select rp.id_operacion,
           coalesce(sum(c.monto_usd) filter (where c.id_tipo_costo = (select id from tipo_imp)), 0) as suma_imp,
           count(c.id)          filter (where c.id_tipo_costo = (select id from tipo_imp))          as filas_imp,
           count(c.id)                                                                              as filas_todas
      from public.app_dat_recepcion_productos rp
      left join public.app_dat_recepcion_producto_costo c on c.id_recepcion_producto = rp.id
     group by rp.id_operacion
),

vinculos as (
    select r.id,
           r.id_operacion,
           r.monto_importadora,
           r.origen_pago,
           upper(btrim(coalesce(r.moneda, ''))) as moneda,
           coalesce(pr.suma_imp, 0)             as suma_imp,
           coalesce(pr.filas_imp, 0)            as filas_imp
      from public.fdi_dat_compra_recepcion r
      left join por_recepcion pr on pr.id_operacion = r.id_operacion
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
    'las 2 RPC devuelven jsonb y son SECURITY DEFINER; p_tasa_usd con DEFAULT 1',
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
        and pg_get_expr(p.proargdefaults, 0) = '1')

  union all
  -- 6) INVARIANTE: Σ monto_usd del aterrizaje = el cargo (sólo USD)
  select 6, 'suma_costos_igual_cargo_usd',
    'en vínculos con moneda USD: Σ monto_usd del tipo Importadora = monto_importadora',
    (select count(*)::text from vinculos where moneda = 'USD') || ' vínculos USD, '
      || (select count(*)::text from vinculos where moneda = 'USD' and filas_imp > 0) || ' con aterrizaje, '
      || (select count(*)::text from vinculos
           where moneda = 'USD' and filas_imp > 0
             and abs(suma_imp - monto_importadora) >= 0.005) || ' descuadrados',
    (select count(*) = 0 from vinculos
      where moneda = 'USD' and filas_imp > 0
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
  -- 11) (informativa) vínculos no-USD: no re-derivables
  select 11, 'vinculos_no_usd_sin_tasa_persistida',
    'informativa: la tasa aplicada no se guarda, así que el reparto no-USD no se puede re-calcular',
    (select count(*)::text from vinculos where moneda <> 'USD') || ' vínculo(s) con moneda distinta de USD ('
      || coalesce((select string_agg(distinct coalesce(nullif(moneda, ''), 'NULL'), ', ')
                     from vinculos where moneda <> 'USD'), 'ninguna') || ')',
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