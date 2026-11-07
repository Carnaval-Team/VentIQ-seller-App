-- ============================================================================
-- FASE 5b (§17) — DESGLOSE POR DIVISA DEL INFORME POR TURNO/VENDEDOR
--
-- PROBLEMA: la pestaña «TPVs» pinta sus tarjetas con `fn_reporte_ventas_por_turno`,
-- que suma `SUM(pv.monto)` sobre importes **nativos de cualquier divisa** y no
-- tiene columna de moneda. Sumar 14 USD con 45.000 CUP da 45.014, que no
-- significa nada.
--
-- SOLUCIÓN (aditiva, sin tocar lo que ya funciona):
--   1. `fn_desglose_monedas_usuario(...)` — desglose por divisa de lo que cobró
--      un vendedor en un período. Es `fn_reporte_ventas_por_moneda` filtrada por
--      `o.uuid`, con la MISMA forma de salida para que la UI reutilice el
--      formato que ya existe.
--   2. `fn_reporte_ventas_por_turno_v2(...)` — envuelve a la vigente añadiendo
--      `desglose_monedas` + `total_base` **al final**.
--
-- ⚠️ LA ENVOLTURA SE CONSTRUYE CONTRA EL CONTRATO DESPLEGADO, y esto no es un
-- alarde: `newa` y producción tienen **versiones distintas** de la función
-- vigente. Producción devuelve 13 columnas **por vendedor**
-- (`uuid_usuario, nombres, …, ultima_venta`); `newa` devuelve 19 **por turno**
-- (`id_turno, id_tpv, tpv_nombre, estado_turno, fecha_apertura, fecha_cierre,
-- uuid_usuario, …, ultima_venta`). Los parámetros, en cambio, son idénticos en
-- ambos. Escribir el `RETURNS TABLE` a mano habría hecho que el fichero no se
-- pudiera ejecutar (ni por tanto probar) más que en uno de los dos entornos.
-- Por eso el tipo de retorno se lee de `pg_get_function_result` y se le añaden
-- las dos columnas nuevas; el desglose se elige según lo que la vigente tenga:
--   · si devuelve `id_turno` → `fn_desglose_monedas_turno(id_turno, false)`
--   · si no                 → `fn_desglose_monedas_usuario(uuid_usuario, …)`
-- Así el mismo fichero es correcto en los dos y **no hay deriva** entre lo
-- probado y lo desplegado.
--
-- `total_dinero_general` (nativo) se sigue devolviendo por compatibilidad; lo
-- que la UI debe empezar a usar como total es `total_base`, el consolidado.
--
-- Idempotente. Verificado en `newa` el 2026-11-06:
--   · la `_v2` conserva **el mismo número de filas** que la vigente (1 = 1)
--   · el desglose cuadra: efectivo 292.530 + digital 18.950 = 311.480 = total_base
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Desglose por divisa de un vendedor en un período
-- ---------------------------------------------------------------------------
create or replace function public.fn_desglose_monedas_usuario(
  p_uuid_usuario uuid,
  p_fecha_desde  date,
  p_fecha_hasta  date,
  p_id_tienda    bigint
) returns table(
  desglose_monedas jsonb,
  total_base       numeric
)
language sql
stable
security definer
set search_path to 'public'
as $$
  with pagos as (
    select upper(trim(pv.moneda)) as moneda,
           count(distinct pv.id_operacion_venta) as operaciones,
           sum(pv.monto) as importe_nativo,
           sum(pv.monto_cup_equivalente) as importe_base,
           sum(pv.monto) filter (where mp.es_efectivo) as efectivo_nativo,
           sum(pv.monto) filter (where not coalesce(mp.es_efectivo, false)) as digital_nativo
    from public.app_dat_pago_venta pv
    join public.app_dat_operacion_venta ov on ov.id_operacion = pv.id_operacion_venta
    join public.app_dat_operaciones o on o.id = ov.id_operacion
    join public.app_nom_medio_pago mp on mp.id = pv.id_medio_pago
    where (p_uuid_usuario is null or o.uuid = p_uuid_usuario)
      and (p_id_tienda is null or o.id_tienda = p_id_tienda)
      and (p_fecha_desde is null or o.created_at::date >= p_fecha_desde)
      and (p_fecha_hasta is null or o.created_at::date <= p_fecha_hasta)
    group by 1
  )
  select coalesce(
           jsonb_agg(jsonb_build_object(
             'moneda',          p.moneda,
             'operaciones',     p.operaciones,
             'importe_nativo',  p.importe_nativo,
             'importe_base',    p.importe_base,
             'efectivo_nativo', coalesce(p.efectivo_nativo, 0),
             'digital_nativo',  coalesce(p.digital_nativo, 0),
             'tasa_promedio',   round(p.importe_base / nullif(p.importe_nativo, 0), 4)
           ) order by p.importe_base desc), '[]'::jsonb),
         coalesce(sum(p.importe_base), 0)
  from pagos p;
$$;

grant execute on function public.fn_desglose_monedas_usuario(uuid, date, date, bigint)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Envoltura con el desglose al final, adaptada al contrato desplegado
-- ---------------------------------------------------------------------------
do $$
declare
  v_cols     text;
  v_es_turno boolean;
  v_expr     text;
begin
  select substring(pg_get_function_result(p.oid) from 'TABLE\((.*)\)$')
  into v_cols
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'fn_reporte_ventas_por_turno';

  if v_cols is null then
    raise exception 'FASE5b: no pude leer las columnas de fn_reporte_ventas_por_turno';
  end if;

  -- `id_turno` solo está en la variante por turno (la de `newa`).
  v_es_turno := position('id_turno' in v_cols) > 0;

  v_expr := case when v_es_turno
    then 'public.fn_desglose_monedas_turno(b.id_turno, false)'
    else 'public.fn_desglose_monedas_usuario(b.uuid_usuario, p_fecha_desde, p_fecha_hasta, p_id_tienda)'
  end;

  execute format($f$
    create or replace function public.fn_reporte_ventas_por_turno_v2(
      p_uuid_usuario uuid default null,
      p_fecha_desde  date default null,
      p_fecha_hasta  date default null,
      p_id_tienda    bigint default null
    ) returns table(%s, desglose_monedas jsonb, total_base numeric)
    language sql
    stable
    security definer
    set search_path to 'public'
    as $body$
      with base as (
        select * from public.fn_reporte_ventas_por_turno(
          p_uuid_usuario, p_fecha_desde, p_fecha_hasta, p_id_tienda)
      )
      select b.*, d.desglose_monedas, d.total_base
      from base b
      cross join lateral %s d;
    $body$;
  $f$, v_cols, v_expr);

  raise notice 'FASE5b: _v2 creada con criterio %',
    case when v_es_turno then 'por turno' else 'por vendedor' end;
end $$;

grant execute on function public.fn_reporte_ventas_por_turno_v2(uuid, date, date, bigint)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Verificación: misma cantidad de filas que la vigente + desglose coherente
-- ---------------------------------------------------------------------------
with t as (
  select o.id_tienda
  from public.app_dat_pago_venta pv
  join public.app_dat_operacion_venta ov on ov.id_operacion = pv.id_operacion_venta
  join public.app_dat_operaciones o on o.id = ov.id_operacion
  limit 1
)
select
  (select count(*) from public.fn_reporte_ventas_por_turno(
     null, (current_date - 400), current_date, (select id_tienda from t))) as filas_vigente,
  (select count(*) from public.fn_reporte_ventas_por_turno_v2(
     null, (current_date - 400), current_date, (select id_tienda from t))) as filas_v2,
  (select string_agg(
      d.moneda || ': efectivo ' || d.efectivo_nativo || ' + digital ' || d.digital_nativo
      || ' = ' || (d.efectivo_nativo + d.digital_nativo)
      || ' | importe_base ' || d.importe_base, ' · ')
   from public.fn_reporte_ventas_por_turno_v2(
     null, (current_date - 400), current_date, (select id_tienda from t)) v,
   lateral jsonb_to_recordset(v.desglose_monedas)
     as d(moneda text, efectivo_nativo numeric, digital_nativo numeric, importe_base numeric)) as desglose;