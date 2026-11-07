-- ============================================================================
-- MONEDA DE CONSOLIDACIÓN DEL ADMIN (Ventas)  ·  paquete completo
--
-- QUÉ RESUELVE: en Ventas, el consolidado salía siempre en CUP. Una tienda que
-- vende **solo** en USD obligaba a convertir mentalmente. Ahora la moneda de
-- consolidación es la que la tienda fuerza en el admin (`forzar_moneda_venta` +
-- `moneda_venta_forzada`), y **CUP cuando no fuerza nada** (así las 2.336
-- tiendas actuales no cambian).
--
-- CÓMO SE CONSOLIDA CADA FILA — la parte que importa:
--   · fila de la propia moneda de consolidación → `importe_nativo`, **exacto**
--     (si la tienda vende solo en USD, el consolidado ES lo cobrado en USD)
--   · fila de otra divisa → `importe_base × tasa(CUP→X)`, **aproximación** explícita
-- Por qué no se convierte CUP→X y ya está: las tasas han cambiado (en producción
-- hay USD cobrado a 550, 800 y 900), así que reconvertir el equivalente en CUP de
-- un pago que YA estaba en USD metería un error gratuito. De ahí `importe_consolidado`
-- por fila: la UI suma esa columna y no sabe de tasas.
--
-- FAIL-SAFE: si no hay tasa para CUP→X, `fn_moneda_consolidacion` devuelve
-- ('CUP', 1, true). El admin nunca muestra importes en una divisa que no puede
-- convertir.
--
-- CONTENIDO:
--   1. `fn_moneda_consolidacion(p_id_tienda)`
--   2. `fn_reporte_ventas_por_moneda` + `moneda_consolidacion` + `importe_consolidado`
--   3. `fn_desglose_monedas_usuario` (informe por vendedor) con las dos claves
--   4. `fn_desglose_monedas_turno` (detalle de caja) con las dos claves
--
-- Idempotente. Verificado en `newa` el 2026-11-06:
--   · sin forzar → CUP/1/true; forzando USD → USD/0,001183
--   · 5.330.900 CUP × 0,001183 = 5.794,69 USD
--   · ambos helpers emiten `moneda_consolidacion` e `importe_consolidado`
--   · `fn_resumen_turno_por_id_v2` sigue devolviendo su fila
--
-- CORRECCIÓN (2026-11-06, tras revisar una tarjeta de TPVs): tanto el reporte
-- como el desglose por vendedor **cuentan solo ventas completadas**
-- (`último estado = 2`). Sin ese filtro contaban pagos de operaciones aún
-- abiertas y NO cuadraban con los totales del propio informe: en la tienda 223
-- el desglose sumaba 17.187,34 CUP y 3,47 USD mientras la tarjeta mostraba
-- 4.187,34 y 1,47. Las dos operaciones de diferencia (13.000 CUP y 2 USD)
-- estaban en estado 1. Con el filtro, los dos lados coinciden exactamente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. ¿En qué moneda consolida esta tienda?
-- ---------------------------------------------------------------------------
create or replace function public.fn_moneda_consolidacion(p_id_tienda bigint)
returns table(
  moneda  text,
  tasa_cup numeric,   -- multiplicador CUP -> moneda (1 si consolida en CUP)
  es_base boolean
)
language sql
stable
security definer
set search_path to 'public'
as $$
  with candidata as (
    select c.moneda_venta_forzada as moneda
    from public.app_dat_configuracion_tienda c
    where c.id_tienda = p_id_tienda
      and c.forzar_moneda_venta
      and c.moneda_venta_forzada is not null
      and exists (
        select 1 from public.app_dat_tienda_moneda m
        where m.id_tienda = c.id_tienda
          and m.moneda = c.moneda_venta_forzada
          and m.activo)
    limit 1
  ),
  resuelta as (
    select cd.moneda,
           -- La dirección directa manda (es la que da de alta el sistema). Solo
           -- si no existe se invierte la contraria.
           coalesce(
             public.fn_tasa_cambio('CUP', cd.moneda, p_id_tienda, now()),
             1::numeric / nullif(
               public.fn_tasa_cambio(cd.moneda, 'CUP', p_id_tienda, now()), 0)
           ) as tasa
    from candidata cd
  )
  -- Solo se cambia de moneda si la tasa se pudo resolver.
  select coalesce(r.moneda, 'CUP')::text,
         coalesce(r.tasa, 1)::numeric,
         (r.moneda is null)::boolean
  from (select moneda, tasa from resuelta where tasa is not null) r
  right join (select 1) uno on true;
$$;

grant execute on function public.fn_moneda_consolidacion(bigint) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. El reporte añade la consolidación (columnas NUEVAS al final)
-- ---------------------------------------------------------------------------
drop function if exists public.fn_reporte_ventas_por_moneda(bigint, date, date, bigint);

create function public.fn_reporte_ventas_por_moneda(
  p_id_tienda bigint,
  p_desde     date,
  p_hasta     date,
  p_id_tpv    bigint default null
) returns table(
  moneda               text,
  operaciones          bigint,
  importe_nativo       numeric,
  importe_base         numeric,
  efectivo_nativo      numeric,
  digital_nativo       numeric,
  tasa_promedio        numeric,
  moneda_consolidacion text,
  importe_consolidado  numeric
)
language sql
stable
security definer
set search_path to 'public'
as $$
  with cons as (select * from public.fn_moneda_consolidacion(p_id_tienda)),
  agg as (
    select upper(trim(pv.moneda)) as moneda,
           count(distinct pv.id_operacion_venta) as operaciones,
           sum(pv.monto) as importe_nativo,
           sum(pv.monto_cup_equivalente) as importe_base,
           sum(pv.monto) filter (where mp.es_efectivo) as efectivo_nativo,
           sum(pv.monto) filter (where not coalesce(mp.es_efectivo, false)) as digital_nativo,
           round(sum(pv.monto_cup_equivalente) / nullif(sum(pv.monto), 0), 4) as tasa_promedio
    from public.app_dat_pago_venta pv
    join public.app_dat_operacion_venta ov on ov.id_operacion = pv.id_operacion_venta
    join public.app_dat_operaciones o on o.id = ov.id_operacion
    join public.app_nom_medio_pago mp on mp.id = pv.id_medio_pago
    where o.id_tienda = p_id_tienda
      and o.created_at::date between p_desde and p_hasta
      and (p_id_tpv is null or ov.id_tpv = p_id_tpv)
      -- Solo ventas COMPLETADAS. Sin esto el reporte cuenta pagos de
      -- operaciones abiertas (último estado <> 2) y deja de cuadrar con los
      -- totales del resto de informes, que sí filtran así.
      and exists (select 1 from public.app_dat_estado_operacion eo
                  where eo.id_operacion = o.id and eo.estado = 2
                    and eo.id = (select max(eo2.id) from public.app_dat_estado_operacion eo2
                                 where eo2.id_operacion = o.id))
    group by 1
  )
  select a.moneda,
         a.operaciones,
         a.importe_nativo,
         a.importe_base,
         a.efectivo_nativo,
         a.digital_nativo,
         a.tasa_promedio,
         c.moneda::text,
         case when a.moneda = c.moneda
              then a.importe_nativo            -- exacto: es la divisa que se cobró
              else a.importe_base * c.tasa_cup -- aproximado: cambio de hoy
         end::numeric
  from agg a cross join cons c
  order by a.importe_base desc;
$$;

comment on function public.fn_reporte_ventas_por_moneda(bigint, date, date, bigint) is
  'Contabilización por moneda. `importe_base` va siempre en CUP (equivalente contable); `importe_consolidado` va en `moneda_consolidacion` (la divisa forzada de la tienda o CUP). La UI debe TOTALIZAR `importe_consolidado`, no `importe_base`.';

grant execute on function public.fn_reporte_ventas_por_moneda(bigint, date, date, bigint)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Desglose por vendedor: las dos claves nuevas en cada divisa
-- ---------------------------------------------------------------------------
create or replace function public.fn_desglose_monedas_usuario(
  p_uuid_usuario uuid, p_fecha_desde date, p_fecha_hasta date, p_id_tienda bigint
) returns table(desglose_monedas jsonb, total_base numeric)
language sql stable security definer set search_path to 'public' as $$
  with cons as (select * from public.fn_moneda_consolidacion(p_id_tienda)),
  pagos as (
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
      -- Mismo criterio que el informe al que acompaña: solo ventas completadas.
      and exists (select 1 from public.app_dat_estado_operacion eo
                  where eo.id_operacion = o.id and eo.estado = 2
                    and eo.id = (select max(eo2.id) from public.app_dat_estado_operacion eo2
                                 where eo2.id_operacion = o.id))
    group by 1
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'moneda', p.moneda,
           'operaciones', p.operaciones,
           'importe_nativo', p.importe_nativo,
           'importe_base', p.importe_base,
           'efectivo_nativo', coalesce(p.efectivo_nativo, 0),
           'digital_nativo', coalesce(p.digital_nativo, 0),
           'tasa_promedio', round(p.importe_base / nullif(p.importe_nativo, 0), 4),
           'moneda_consolidacion', c.moneda,
           'importe_consolidado', case when p.moneda = c.moneda
                                       then p.importe_nativo
                                       else p.importe_base * c.tasa_cup end
         ) order by p.importe_base desc), '[]'::jsonb),
         coalesce(sum(p.importe_base), 0)
  from pagos p cross join cons c;
$$;

-- ---------------------------------------------------------------------------
-- 4. Desglose por turno: idem (lo usa el detalle de caja del admin)
--    La tienda se resuelve desde las propias operaciones: `min(o.id_tienda)`
--    es seguro porque un turno pertenece a un único TPV de una única tienda.
-- ---------------------------------------------------------------------------
create or replace function public.fn_desglose_monedas_turno(
  p_id_turno bigint,
  p_criterio_resumen boolean
) returns table(desglose_monedas jsonb, total_base numeric)
language sql security definer set search_path to 'public' as $$
  with turno as (
    select id, id_tpv, id_vendedor, creado_por, fecha_apertura,
           coalesce(fecha_cierre, now()) as fecha_fin
    from public.app_dat_caja_turno where id = p_id_turno
  ),
  venta_tipo as (
    select id from public.app_nom_tipo_operacion where lower(denominacion) = 'venta' limit 1
  ),
  pagos as (
    select upper(trim(pv.moneda)) as moneda,
           count(distinct pv.id_operacion_venta) as operaciones,
           sum(pv.monto) as importe_nativo,
           sum(pv.monto * coalesce(pv.tasa_cambio, pv.tasa_usd, 1)) as importe_base,
           sum(pv.monto) filter (where mp.es_efectivo) as efectivo_nativo,
           sum(pv.monto) filter (where not mp.es_efectivo) as digital_nativo,
           min(o.id_tienda) as id_tienda
    from turno t
    join public.app_dat_operaciones o
      on o.created_at >= t.fecha_apertura
     and (p_criterio_resumen or o.created_at <= t.fecha_fin)
     and o.uuid = case when p_criterio_resumen
                       then (select v.uuid from public.app_dat_vendedor v where v.id = t.id_vendedor)
                       else t.creado_por end
     and (not p_criterio_resumen or o.id_tipo_operacion = (select id from venta_tipo))
    join public.app_dat_operacion_venta ov on ov.id_operacion = o.id and ov.id_tpv = t.id_tpv
    join public.app_dat_pago_venta pv on pv.id_operacion_venta = ov.id_operacion
    join public.app_nom_medio_pago mp on mp.id = pv.id_medio_pago and mp.es_activo
    where exists (select 1 from public.app_dat_estado_operacion eo
                  where eo.id_operacion = o.id and eo.estado = 2
                    and eo.id = (select max(eo2.id) from public.app_dat_estado_operacion eo2
                                 where eo2.id_operacion = o.id))
    group by 1
  ),
  cons as (
    select * from public.fn_moneda_consolidacion((select min(id_tienda) from pagos))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'moneda', p.moneda,
           'operaciones', p.operaciones,
           'importe_nativo', p.importe_nativo,
           'importe_base', p.importe_base,
           'efectivo_nativo', coalesce(p.efectivo_nativo, 0),
           'digital_nativo', coalesce(p.digital_nativo, 0),
           'moneda_consolidacion', c.moneda,
           'importe_consolidado', case when p.moneda = c.moneda
                                       then p.importe_nativo
                                       else p.importe_base * c.tasa_cup end
         ) order by p.importe_base desc), '[]'::jsonb),
         coalesce(sum(p.importe_base), 0)
  from pagos p cross join cons c;
$$;

-- ---------------------------------------------------------------------------
-- 5. Verificación
-- ---------------------------------------------------------------------------
select 'sin forzar (tienda 223)' as caso, c.moneda, c.tasa_cup, c.es_base
from public.fn_moneda_consolidacion(223) c
union all
select 'sin configuracion', c.moneda, c.tasa_cup, c.es_base
from public.fn_moneda_consolidacion(-1) c;

select m.moneda, m.operaciones, m.importe_nativo, m.importe_base,
       m.moneda_consolidacion, m.importe_consolidado
from public.fn_reporte_ventas_por_moneda(223, '2026-01-01', '2026-12-31') m;