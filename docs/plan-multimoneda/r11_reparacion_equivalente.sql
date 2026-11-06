-- ============================================================================
-- R11 — `monto_cup_equivalente` CORRUPTO: PREVENCIÓN + REPARACIÓN
--
-- DIAGNÓSTICO (medido en producción el 2026-11-05):
--   CUP: 129.680 filas · 675 con equivalente NULL · 372 descuadradas
--        (equivalente ≠ monto × tasa) · 301 sin `tasa_cambio`
--        → 131.461.881 CUP sin equivalente contable
--   USD:  11 filas · 0 NULL · 0 descuadradas
--   Sin trigger en la tabla.
--
-- POR QUÉ UNA SOLA CAPA NO BASTA:
--   Hay **12 funciones** que insertan en `app_dat_pago_venta`
--   (fn_registrar_pago_venta / _v2 / _v3, fn_registrar_venta / _v2 / _v3,
--    fn_registrar_venta_offline / _v2, fn_agregar_producto_orden_pendiente / _v2,
--    fn_cxc_registrar_liquidacion, fn_eliminar_order_detail_con_devolucion_v2).
--   Auditar y corregir 12 caminos a mano se vuelve a romper en cuanto alguien
--   añada el 13.º. El invariante tiene que estar **en la tabla**.
--
-- DOS CAPAS:
--   A. PREVENCIÓN — trigger BEFORE INSERT OR UPDATE que calcula el equivalente
--      siempre, venga de donde venga la escritura. Ningún escritor puede dejarlo
--      NULL ni descuadrado.
--   B. REPARACIÓN — medir, respaldar, recalcular fila por fila y verificar.
--      Determinista: no depende de lo que hubiera antes (no es un backfill de
--      NULLs, que en las filas con el total de la operación duplicaría la suma).
--
-- REGLA: `monto_cup_equivalente = monto × tasa`, **sin redondear**, que es
--   exactamente lo que hace `fn_registrar_pago_venta_v3`. No se redondea porque
--   `es_pagada` se decide comparando esa suma contra `importe_total`, y redondear
--   a 2 decimales puede dejar la suma unas milésimas por debajo. La tasa es
--   `tasa_cambio`, con `tasa_usd` como alias legacy y 1 para la moneda base.
--
-- Orden de ejecución: A (trigger) → B (reparación). Ejecutar B sin A deja la
-- puerta abierta a que se vuelva a corromper mientras se repara.
-- Idempotente.
-- ============================================================================

-- ============================================================================
-- A. PREVENCIÓN
-- ============================================================================
create or replace function public.fn_pago_venta_equivalente()
returns trigger
language plpgsql
set search_path to 'public'
as $$
declare
  v_moneda text;
  v_tasa   numeric;
begin
  v_moneda := upper(trim(coalesce(new.moneda, 'CUP')));

  v_tasa := case
              when v_moneda = 'CUP' then 1
              else coalesce(new.tasa_cambio, new.tasa_usd)
            end;

  -- Divisa distinta de la base sin tasa: no se inventa nada. Las RPC ya
  -- rechazan ese pago; si llegara por otra vía, el equivalente queda NULL y
  -- el reporte de verificación lo delata en vez de mentir.
  if v_tasa is null or v_tasa <= 0 then
    return new;
  end if;

  new.monto_cup_equivalente := new.monto * v_tasa;

  -- Coherencia de las columnas de tasa: la genérica siempre, y la legacy
  -- cuando la divisa es USD (la app vieja la sigue leyendo).
  if new.tasa_cambio is null then
    new.tasa_cambio := v_tasa;
  end if;
  if v_moneda = 'USD' and new.tasa_usd is null then
    new.tasa_usd := v_tasa;
  end if;

  return new;
end $$;

drop trigger if exists trg_pago_venta_equivalente on public.app_dat_pago_venta;
create trigger trg_pago_venta_equivalente
before insert or update of monto, moneda, tasa_cambio, tasa_usd
on public.app_dat_pago_venta
for each row execute function public.fn_pago_venta_equivalente();

-- ============================================================================
-- B. REPARACIÓN
-- ============================================================================

-- B.0 — Medición previa (guárdala: es la línea base para comparar después)
with calc as (
  select pv.id,
         pv.moneda,
         pv.monto,
         pv.monto_cup_equivalente as actual,
         pv.monto * coalesce(pv.tasa_cambio, pv.tasa_usd,
                             case when upper(trim(pv.moneda)) = 'CUP' then 1 end) as correcto
  from public.app_dat_pago_venta pv
)
select count(*)                                                       as filas,
       count(*) filter (where actual is null)                         as nulos,
       count(*) filter (where actual is not null and actual is distinct from correcto)
                                                                      as descuadradas,
       sum(monto) filter (where actual is null)                       as monto_en_nulos,
       sum(correcto - coalesce(actual, 0))                            as correccion_total_cup
from calc;

-- B.1 — Respaldo de lo que se va a tocar (reversible)
create table if not exists public.app_dat_pago_venta_bkp_equiv as
select pv.id, pv.moneda, pv.monto, pv.tasa_cambio, pv.tasa_usd,
       pv.monto_cup_equivalente, now() as respaldado_en
from public.app_dat_pago_venta pv
where pv.monto_cup_equivalente is distinct from
        pv.monto * coalesce(pv.tasa_cambio, pv.tasa_usd,
                            case when upper(trim(pv.moneda)) = 'CUP' then 1 end)
   or pv.tasa_cambio is null;

-- B.2 — Rellenar `tasa_cambio` (la base es 1; el resto, su tasa legacy).
--       Este UPDATE dispara el trigger y ya deja el equivalente bien.
update public.app_dat_pago_venta
set tasa_cambio = coalesce(tasa_cambio, tasa_usd, 1)
where tasa_cambio is null;

-- B.3 — Recalcular el equivalente descuadrado (determinista, no incremental).
update public.app_dat_pago_venta pv
set monto_cup_equivalente = pv.monto * coalesce(pv.tasa_cambio, pv.tasa_usd, 1)
where pv.monto_cup_equivalente is distinct from
        pv.monto * coalesce(pv.tasa_cambio, pv.tasa_usd, 1);

-- B.4 — Verificación: debe dar 0 en las tres columnas de problema.
with calc as (
  select pv.id,
         pv.monto_cup_equivalente as actual,
         pv.monto * coalesce(pv.tasa_cambio, pv.tasa_usd, 1) as correcto,
         pv.moneda
  from public.app_dat_pago_venta pv
)
select count(*) filter (where actual is null and upper(trim(moneda)) = 'CUP') as cup_sin_equivalente,
       count(*) filter (where actual is null)                                  as con_null,
       count(*) filter (where actual is distinct from correcto)                as descuadradas
from calc;

-- ============================================================================
-- C. LISTA DE REVISIÓN (no se repara: es desajuste de negocio, no de moneda)
--
-- Operaciones donde el dinero registrado NO cuadra con el total de la venta.
-- Ya existían antes (descuentos, pagos parciales, ediciones de orden). Se
-- entregan para revisión; corregirlas a ciegas sería inventar contabilidad.
-- ============================================================================
with por_op as (
  select pv.id_operacion_venta,
         ov.importe_total,
         sum(pv.monto_cup_equivalente) as cobrado
  from public.app_dat_pago_venta pv
  join public.app_dat_operacion_venta ov on ov.id_operacion = pv.id_operacion_venta
  group by 1, 2
)
select count(*)                                        as operaciones_descuadradas,
       sum(abs(cobrado - importe_total))               as desviacion_total_cup
from por_op
where cobrado is distinct from importe_total;