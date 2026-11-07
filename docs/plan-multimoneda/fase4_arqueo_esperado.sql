-- ============================================================================
-- FASE 4 — ESPERADO POR DIVISA EN EL ARQUEO (parte 1c)
--
-- PROBLEMA (medido en producción el 2026-11-05):
--   `app_dat_caja_turno.efectivo_esperado` es **0 en todos los turnos**: ninguna
--   RPC lo calcula (lo calcula la app en local). El trigger `trg_sync_turno_moneda`
--   heredaba ese 0, así que el arqueo quedaba:
--       turno 3415 → esperado CUP 0 · real 58.480 · diferencia 58.480
--   `diferencia` es una columna generada (`real - esperado`), así que con
--   `esperado = 0` la diferencia es simplemente el real: **no significa nada**.
--
-- SOLUCIÓN:
--   1. El trigger **calcula** el esperado de cada divisa:
--        esperado = efectivo_inicial de esa divisa
--                 + pagos EN EFECTIVO de esa divisa dentro de la ventana del turno
--      (mismo criterio que `fn_cerrar_turno_tpv_monedas` y `_v2`). La ventana se
--      cierra en `fecha_cierre` cuando existe, para no arrastrar ventas posteriores.
--   2. Recálculo set-based de las filas ya existentes.
--
-- Idempotente. Nota: `fn_cerrar_turno_tpv_monedas` recalcula por su cuenta con la
-- misma fórmula y su upsert corre después del UPDATE legacy, así que manda él.
-- ============================================================================

create or replace function public.fn_sync_turno_moneda()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_esperado record;
begin
  if tg_op = 'INSERT' then
    insert into public.app_dat_caja_turno_moneda (id_turno, moneda, efectivo_inicial)
    values (new.id, 'CUP', coalesce(new.efectivo_inicial, 0))
    on conflict (id_turno, moneda) do nothing;

    if coalesce(new.efectivo_inicial_usd, 0) <> 0 then
      insert into public.app_dat_caja_turno_moneda (id_turno, moneda, efectivo_inicial)
      values (new.id, 'USD', coalesce(new.efectivo_inicial_usd, 0))
      on conflict (id_turno, moneda) do nothing;
    end if;
    return new;
  end if;

  if new.estado               is distinct from old.estado
     or new.efectivo_real     is distinct from old.efectivo_real
     or new.efectivo_real_usd is distinct from old.efectivo_real_usd
     or new.efectivo_inicial  is distinct from old.efectivo_inicial
     or new.efectivo_inicial_usd is distinct from old.efectivo_inicial_usd
     or new.fecha_cierre      is distinct from old.fecha_cierre then

    for v_esperado in
      select moneda, esperado from public.fn_esperado_turno_por_moneda(new.id)
    loop
      insert into public.app_dat_caja_turno_moneda
        (id_turno, moneda, efectivo_inicial, efectivo_esperado, efectivo_real)
      values (new.id, v_esperado.moneda,
              case when v_esperado.moneda = 'USD'
                   then coalesce(new.efectivo_inicial_usd, 0)
                   else coalesce(new.efectivo_inicial, 0) end,
              v_esperado.esperado,
              case when v_esperado.moneda = 'USD'
                   then new.efectivo_real_usd
                   else new.efectivo_real end)
      on conflict (id_turno, moneda) do update
        set efectivo_esperado = excluded.efectivo_esperado,
            efectivo_real     = coalesce(excluded.efectivo_real,
                                         public.app_dat_caja_turno_moneda.efectivo_real),
            updated_at        = now();
    end loop;
  end if;

  return new;
end $$;

-- ---------------------------------------------------------------------------
-- Cálculo del esperado por divisa de un turno (reutilizable por el recálculo)
-- ---------------------------------------------------------------------------
create or replace function public.fn_esperado_turno_por_moneda(p_id_turno bigint)
returns table(moneda text, esperado numeric)
language sql
security definer
set search_path to 'public'
as $$
  with turno as (
    select id, id_tpv, creado_por, fecha_apertura,
           coalesce(fecha_cierre, now()) as fecha_fin,
           coalesce(efectivo_inicial, 0) as inicial_cup,
           coalesce(efectivo_inicial_usd, 0) as inicial_usd
    from public.app_dat_caja_turno
    where id = p_id_turno
  ),
  arqueo as (
    select m.moneda, m.efectivo_inicial
    from public.app_dat_caja_turno_moneda m
    where m.id_turno = p_id_turno
  ),  pagos as (
    select upper(trim(pv.moneda)) as moneda, sum(pv.monto) as efectivo_nativo
    from turno t
    join public.app_dat_operaciones o
      on o.uuid = t.creado_por
     and o.created_at >= t.fecha_apertura
     and o.created_at <= t.fecha_fin
    join public.app_dat_operacion_venta ov
      on ov.id_operacion = o.id and ov.id_tpv = t.id_tpv
    join public.app_dat_pago_venta pv on pv.id_operacion_venta = ov.id_operacion
    join public.app_nom_medio_pago mp on mp.id = pv.id_medio_pago
    where mp.es_efectivo and mp.es_activo
      and exists (select 1 from public.app_dat_estado_operacion eo
                  where eo.id_operacion = o.id and eo.estado = 2
                    and eo.id = (select max(eo2.id) from public.app_dat_estado_operacion eo2
                                 where eo2.id_operacion = o.id))
    group by 1
  ),
  base as (
    select 'CUP'::text as moneda,
           coalesce((select a.efectivo_inicial from arqueo a where a.moneda = 'CUP'),
                    (select t.inicial_cup from turno t), 0) as inicial
    union all
    select 'USD',
           coalesce((select a.efectivo_inicial from arqueo a where a.moneda = 'USD'),
                    (select t.inicial_usd from turno t), 0)
    where coalesce((select a.efectivo_inicial from arqueo a where a.moneda = 'USD'),
                   (select t.inicial_usd from turno t), 0) <> 0
    union all
    select a.moneda, coalesce(a.efectivo_inicial, 0)
    from arqueo a
    where a.moneda not in ('CUP','USD')
  )
  select b.moneda,
         b.inicial + coalesce(p.efectivo_nativo, 0)
  from base b
  left join pagos p on p.moneda = b.moneda
  union all
  select p.moneda, coalesce(p.efectivo_nativo, 0)
  from pagos p
  where not exists (select 1 from base b where b.moneda = p.moneda);
$$;

-- ---------------------------------------------------------------------------
-- Recálculo set-based de lo ya escrito (3.396 turnos en producción)
-- ---------------------------------------------------------------------------
update public.app_dat_caja_turno_moneda m
set efectivo_esperado = c.esperado,
    updated_at        = now()
from (
  select t.id as id_turno, e.moneda, e.esperado
  from public.app_dat_caja_turno t
  cross join lateral public.fn_esperado_turno_por_moneda(t.id) e
) c
where c.id_turno = m.id_turno and c.moneda = m.moneda;

-- ---------------------------------------------------------------------------
-- Verificación: antes/después de una muestra de turnos cerrados
-- ---------------------------------------------------------------------------
select t.id, m.moneda, m.efectivo_inicial, m.efectivo_esperado, m.efectivo_real,
       m.diferencia,
       (m.efectivo_real = m.diferencia) as diferencia_igual_al_real_sospechoso
from public.app_dat_caja_turno t
join public.app_dat_caja_turno_moneda m on m.id_turno = t.id
where t.estado = 2
order by t.id desc
limit 8;

select count(*) filter (where efecto_sospechoso) as filas_con_diferencia_igual_al_real,
       count(*) as filas_totales
from (
  select coalesce(efectivo_real = diferencia, false) as efecto_sospechoso
  from public.app_dat_caja_turno_moneda
  where efectivo_real is not null
) x;

-- ---------------------------------------------------------------------------
-- NOTA DE EJECUCIÓN EN PRODUCCIÓN
--
-- El recálculo recorre los 3.396 turnos y, por cada uno, agrega sus pagos en
-- efectivo. Con los índices actuales debería resolverse en segundos o pocos
-- minutos; si se alarga, ejecuta primero la versión reducida a los turnos
-- cerrados (que son los que tienen `diferencia` calculada y visible):
--
--   update public.app_dat_caja_turno_moneda m
--   set efectivo_esperado = c.esperado, updated_at = now()
--   from (
--     select t.id as id_turno, e.moneda, e.esperado
--     from public.app_dat_caja_turno t
--     cross join lateral public.fn_esperado_turno_por_moneda(t.id) e
--     where t.estado = 2
--   ) c
--   where c.id_turno = m.id_turno and c.moneda = m.moneda;
--
-- Esperado tras aplicar (medido el 2026-11-05): las filas cuyo
-- `diferencia` era igual al `efectivo_real` (porque el esperado era 0) deben
-- dejar de serlo salvo en los turnos donde de verdad no hubo ventas en efectivo.