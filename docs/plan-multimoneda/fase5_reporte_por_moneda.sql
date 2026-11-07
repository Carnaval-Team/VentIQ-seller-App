-- ============================================================================
-- FASE 5 — CONTABILIZACIÓN POR MONEDA EN EL ADMIN · PARTE 1 (núcleo SQL)
--
--   `fn_reporte_ventas_por_moneda(...)` responde exactamente:
--     «¿cuántas operaciones se pagaron en cada divisa, cuánto se cobró en esa
--      divisa (importe nativo, sin convertir) y a cuánto equivale en CUP?»
--
-- DISEÑO
--   · `importe_nativo` = suma de `monto` de esa divisa. Es EXACTO y no se puede
--     comparar entre divisas (no es suma de dinero homogéneo).
--   · `importe_base` = suma de `monto_cup_equivalente`. Es el consolidable, y
--     desde R11 esa columna está reparada y la mantiene un trigger, así que ya
--     es fiable.
--   · `tasa_promedio` = base / nativo, ponderada por importe. Sirve para
--     detectar que a lo largo del periodo se usaron tasas distintas.
--   · NO se filtra por estado de la operación: este reporte tiene que cuadrar
--     contra `app_dat_pago_venta` en crudo, que es su criterio de aceptación.
--     Los reportes por estado son otra cosa y ya existen.
--
--   La moneda base (CUP) aparece como una fila más: así el que lee no tiene que
--   sumar mentalmente nada para ver el consolidado.
-- ============================================================================

create or replace function public.fn_reporte_ventas_por_moneda(
  p_id_tienda bigint,
  p_desde     date,
  p_hasta     date,
  p_id_tpv    bigint default null
) returns table(
  moneda          text,
  operaciones     bigint,
  importe_nativo  numeric,
  importe_base    numeric,
  efectivo_nativo numeric,
  digital_nativo  numeric,
  tasa_promedio   numeric
)
language sql
stable
security definer
set search_path to 'public'
as $$
  select upper(trim(pv.moneda)) as moneda,
         count(distinct pv.id_operacion_venta) as operaciones,
         sum(pv.monto) as importe_nativo,
         sum(pv.monto_cup_equivalente) as importe_base,
         sum(pv.monto) filter (where mp.es_efectivo) as efectivo_nativo,
         sum(pv.monto) filter (where not coalesce(mp.es_efectivo, false)) as digital_nativo,
         round(sum(pv.monto_cup_equivalente) / nullif(sum(pv.monto), 0), 4) as tasa_promedio
  from public.app_dat_pago_venta pv
  join public.app_dat_operacion_venta ov on ov.id_operacion = pv.id_operacion_venta
  join public.app_dat_operaciones    o  on o.id = ov.id_operacion
  join public.app_nom_medio_pago     mp on mp.id = pv.id_medio_pago
  where o.id_tienda = p_id_tienda
    and o.created_at::date between p_desde and p_hasta
    and (p_id_tpv is null or ov.id_tpv = p_id_tpv)
  group by 1
  order by sum(pv.monto_cup_equivalente) desc;
$$;

comment on function public.fn_reporte_ventas_por_moneda(bigint, date, date, bigint) is
  'Contabilización por moneda: operaciones, importe nativo (exacto), equivalente en moneda base y tasa media ponderada. Sin filtro de estado: cuadra con app_dat_pago_venta en crudo.';

grant execute on function public.fn_reporte_ventas_por_moneda(bigint, date, date, bigint)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Verificación: el reporte debe cuadrar con la tabla de pagos en crudo
-- ---------------------------------------------------------------------------
with crudo as (
  select upper(trim(pv.moneda)) as moneda,
         count(distinct pv.id_operacion_venta) as operaciones,
         sum(pv.monto) as nativo,
         sum(pv.monto_cup_equivalente) as base
  from public.app_dat_pago_venta pv
  join public.app_dat_operacion_venta ov on ov.id_operacion = pv.id_operacion_venta
  join public.app_dat_operaciones o on o.id = ov.id_operacion
  where o.id_tienda = (select id_tienda from public.app_dat_operaciones order by id limit 1)
  group by 1
),
rpc as (
  select r.moneda, r.operaciones, r.importe_nativo as nativo, r.importe_base as base
  from public.fn_reporte_ventas_por_moneda(
         (select id_tienda from public.app_dat_operaciones order by id limit 1),
         (current_date - interval '400 days')::date,
         current_date) r
)
select coalesce(c.moneda, r.moneda) as moneda,
       coalesce(c.operaciones, 0) as ops_crudo,
       coalesce(r.operaciones, 0) as ops_rpc,
       coalesce(c.nativo, 0) as nativo_crudo,
       coalesce(r.nativo, 0) as nativo_rpc,
       coalesce(c.base, 0)   as base_crudo,
       coalesce(r.base, 0)   as base_rpc,
       (coalesce(c.operaciones,0) = coalesce(r.operaciones,0)
        and coalesce(c.nativo,0) = coalesce(r.nativo,0)
        and coalesce(c.base,0)   = coalesce(r.base,0)) as cuadra
from crudo c
full join rpc r on r.moneda = c.moneda
order by 1;