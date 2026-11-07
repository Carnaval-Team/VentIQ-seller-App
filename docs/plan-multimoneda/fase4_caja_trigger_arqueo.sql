-- ============================================================================
-- FASE 4 — CIERRE DEL HUECO DE ARQUEO (parte 1b)
--
-- PROBLEMA (medido en producción el 2026-11-05):
--   `app_dat_caja_turno_moneda` tenía 3.388 filas para 3.396 turnos: **9 turnos
--   sin ninguna fila**. Todos creados DESPUÉS del backfill.
--   Causa: la app desplegada abre turnos con `registrar_apertura_turno_usd`
--   (RPC legacy), que **no escribe** el arqueo por divisa. Solo lo escribe
--   `registrar_apertura_turno_monedas`, que la app aún no usa.
--   Consecuencia: el arqueo por divisa se queda vacío para todo turno nuevo y
--   el cierre tampoco lo rellena.
--
-- SOLUCIÓN: un trigger en `app_dat_caja_turno` (mismo patrón que
--   `trg_seed_tienda_monedas` de la Fase 2) que
--     · en INSERT  → siembra la fila de CUP (y la de USD si hay inicial USD);
--     · en UPDATE  → refleja el cierre que dejó la RPC vigente
--                    (`efectivo_real`, `efectivo_esperado`, `efectivo_real_usd`).
--   Así el arqueo por divisa queda correcto **incluso con la app vieja**, y
--   `fn_cerrar_turno_tpv_monedas` sigue mandando: su upsert por divisa corre
--   después del UPDATE legacy y sobreescribe con el cálculo correcto.
--
-- Idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Función de sincronización
-- ---------------------------------------------------------------------------
create or replace function public.fn_sync_turno_moneda()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
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

  -- UPDATE: solo si cambió algo del arqueo (evita ruido en updates ajenos).
  if new.estado              is distinct from old.estado
     or new.efectivo_real     is distinct from old.efectivo_real
     or new.efectivo_esperado is distinct from old.efectivo_esperado
     or new.efectivo_real_usd is distinct from old.efectivo_real_usd
     or new.efectivo_inicial_usd is distinct from old.efectivo_inicial_usd then

    insert into public.app_dat_caja_turno_moneda
      (id_turno, moneda, efectivo_inicial, efectivo_esperado, efectivo_real)
    values (new.id, 'CUP', coalesce(new.efectivo_inicial, 0),
            new.efectivo_esperado, new.efectivo_real)
    on conflict (id_turno, moneda) do update
      set efectivo_esperado = coalesce(excluded.efectivo_esperado,
                                       public.app_dat_caja_turno_moneda.efectivo_esperado),
          efectivo_real     = coalesce(excluded.efectivo_real,
                                       public.app_dat_caja_turno_moneda.efectivo_real),
          updated_at        = now();

    -- El turno NO guarda el efectivo esperado en USD (solo el real y la diferencia),
    -- así que hay que calcularlo aquí o la diferencia saldría falsa (real - 0).
    -- Mismo criterio que `fn_cerrar_turno_tpv_monedas`: inicial USD + pagos EN
    -- EFECTIVO en USD dentro de la ventana del turno.
    if coalesce(new.efectivo_inicial_usd, 0) <> 0 or new.efectivo_real_usd is not null then
      insert into public.app_dat_caja_turno_moneda
        (id_turno, moneda, efectivo_inicial, efectivo_esperado, efectivo_real)
      select new.id, 'USD', coalesce(new.efectivo_inicial_usd, 0),
             coalesce(new.efectivo_inicial_usd, 0) + coalesce((
               select sum(pv.monto)
               from public.app_dat_operaciones o
               join public.app_dat_operacion_venta ov on ov.id_operacion = o.id
               join public.app_dat_pago_venta pv on pv.id_operacion_venta = ov.id_operacion
               join public.app_nom_medio_pago mp on mp.id = pv.id_medio_pago
               where ov.id_tpv = new.id_tpv
                 and o.uuid = new.creado_por
                 and o.created_at >= new.fecha_apertura
                 and upper(trim(pv.moneda)) = 'USD'
                 and mp.es_efectivo and mp.es_activo
                 and exists (select 1 from public.app_dat_estado_operacion eo
                             where eo.id_operacion = o.id and eo.estado = 2
                               and eo.id = (select max(eo2.id) from public.app_dat_estado_operacion eo2
                                            where eo2.id_operacion = o.id))
             ), 0),
             new.efectivo_real_usd
      on conflict (id_turno, moneda) do update
        set efectivo_esperado = excluded.efectivo_esperado,
            efectivo_real = coalesce(excluded.efectivo_real,
                                     public.app_dat_caja_turno_moneda.efectivo_real),
            updated_at    = now();
    end if;
  end if;

  return new;
end $$;

drop trigger if exists trg_sync_turno_moneda on public.app_dat_caja_turno;
create trigger trg_sync_turno_moneda
after insert or update on public.app_dat_caja_turno
for each row execute function public.fn_sync_turno_moneda();

-- ---------------------------------------------------------------------------
-- 2. Backfill de los turnos que quedaron sin fila
-- ---------------------------------------------------------------------------
insert into public.app_dat_caja_turno_moneda (id_turno, moneda, efectivo_inicial, efectivo_real)
select ct.id, 'CUP', coalesce(ct.efectivo_inicial, 0), ct.efectivo_real
from public.app_dat_caja_turno ct
on conflict (id_turno, moneda) do nothing;

insert into public.app_dat_caja_turno_moneda (id_turno, moneda, efectivo_inicial, efectivo_real)
select ct.id, 'USD', coalesce(ct.efectivo_inicial_usd, 0), ct.efectivo_real_usd
from public.app_dat_caja_turno ct
where coalesce(ct.efectivo_inicial_usd, 0) <> 0 or ct.efectivo_real_usd is not null
on conflict (id_turno, moneda) do nothing;

-- ---------------------------------------------------------------------------
-- 3. Verificación
-- ---------------------------------------------------------------------------
select (select count(*) from public.app_dat_caja_turno) as turnos,
       (select count(distinct id_turno) from public.app_dat_caja_turno_moneda) as turnos_con_arqueo,
       (select count(*) from public.app_dat_caja_turno t
         where not exists (select 1 from public.app_dat_caja_turno_moneda m where m.id_turno = t.id))
         as turnos_sin_arqueo,
       (select count(*) from public.app_dat_caja_turno_moneda) as filas;

select tgname, pg_get_triggerdef(oid) as def
from pg_trigger
where not tgisinternal and tgrelid = 'public.app_dat_caja_turno'::regclass;

-- ---------------------------------------------------------------------------
-- 4. RUNBOOK DEL PASE A PRODUCCIÓN
--
-- Estado medido en producción el 2026-11-05 ANTES de aplicar este fichero:
--   turnos = 3.396 · filas de arqueo = 3.388 (CUP 3.387 / USD 1)
--   turnos con arqueo = 3.387 · turnos SIN arqueo = 9 (ids 3413-3421)
--   Los 9 huecos tienen efectivo_inicial_usd = 0, así que el backfill solo
--   añadirá filas CUP.
--
-- Resultado esperado DESPUÉS:
--   turnos = 3.396 · filas de arqueo = 3.397 (CUP 3.396 / USD 1)
--   turnos con arqueo = 3.396 · turnos SIN arqueo = 0
--   trigger `trg_sync_turno_moneda` presente en `app_dat_caja_turno`
--
-- Reversión (no toca datos, solo deja de sembrar el arqueo):
--   drop trigger if exists trg_sync_turno_moneda on public.app_dat_caja_turno;
--   drop function if exists public.fn_sync_turno_moneda();
--
-- Comprobación después de abrir un turno desde la app:
--   select * from public.app_dat_caja_turno_moneda order by id_turno desc limit 4;
--   → debe aparecer una fila CUP con el efectivo_inicial declarado.