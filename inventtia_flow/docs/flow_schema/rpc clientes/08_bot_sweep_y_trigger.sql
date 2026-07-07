-- ============================================================================
-- BACKGROUND: sweep (recorre todos los planes con cupo) + trigger (reactivo)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) SWEEP: procesa todos los planes que aun tienen cupo.
--    Pensado para pg_cron:  select cron.schedule('bot-sweep', '* * * * *',
--                             $$ select flow.bot_sweep(); $$);
--    Usa el indice parcial idx_plan_servicios_con_cupo -> solo lee planes con cupo.
-- ----------------------------------------------------------------------------
create or replace function flow.bot_sweep()
returns jsonb
language plpgsql
volatile
security definer
set search_path = flow, public
as $$
declare
  r           record;
  v_total     integer := 0;
  v_planes    integer := 0;
begin
  for r in
    select ps.id
    from flow.plan_servicios ps
    where ps.cantidad is not null
      and ps.agendados < ps.cantidad
      and ps.id_local_servicio is not null
    order by ps.fecha
  loop
    v_planes := v_planes + 1;
    v_total  := v_total + coalesce(
      (flow.bot_procesar_plan(r.id) ->> 'movidos')::int, 0
    );
  end loop;

  return jsonb_build_object('ok', true, 'planes_revisados', v_planes, 'agendas_creadas', v_total);
end;
$$;

revoke all on function flow.bot_sweep() from public;
grant execute on function flow.bot_sweep() to service_role;


-- ----------------------------------------------------------------------------
-- 2) TRIGGER: cuando el admin crea/edita un plan, procesarlo al instante.
--    Solo dispara si hay cupo real, para no trabajar de mas.
-- ----------------------------------------------------------------------------
create or replace function flow.trg_plan_servicio_procesar()
returns trigger
language plpgsql
security definer
set search_path = flow, public
as $$
begin
  if new.id_local_servicio is not null
     and new.cantidad is not null
     and new.agendados < new.cantidad
  then
    perform flow.bot_procesar_plan(new.id);
  end if;
  return null;  -- AFTER trigger: el valor no se usa
end;
$$;

drop trigger if exists trg_plan_servicio_aiu on flow.plan_servicios;

-- AFTER INSERT/UPDATE: tras crear o editar (cantidad/fecha/servicio) el plan.
-- WHEN evita re-disparar cuando solo cambia 'agendados' (lo escribe el propio bot).
create trigger trg_plan_servicio_aiu
after insert or update of cantidad, fecha, id_local_servicio
on flow.plan_servicios
for each row
execute function flow.trg_plan_servicio_procesar();
