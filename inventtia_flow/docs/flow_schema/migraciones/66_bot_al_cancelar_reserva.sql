-- ============================================================================
-- MIGRACION 66: al cancelar una reserva, disparar el BOT de la cola
--
-- QUE RESUELVE
--   Al cancelar (o al expirar un pago y cancelarse sola) se libera cupo, pero
--   NADIE avisaba al bot: no habia cron del bot ni trigger en `flow.agenda`, asi
--   que el hueco quedaba vacio hasta que alguien ejecutara `flow.bot_sweep()` a
--   mano. El siguiente de la cola (`flow.sala_espera`) no recibia su turno.
--
-- COMO
--   Un trigger **deferido** en `flow.agenda`: cuando una reserva pasa de
--   `Reservado` a `Cancelado`, al hacer COMMIT se procesa el turno/dia liberado:
--
--     * reserva con turno  -> flow.bot_procesar_recurso_dia(id_turno, dia)
--     * reserva por plan   -> flow.bot_procesar_plan(id_plan del dia)
--
--   Deferido (`initially deferred`) es la clave: las funciones de cancelacion
--   hacen el `update` del estado ANTES de devolver el cupo a `plan_tramo` /
--   `plan_servicios`. Si el bot corriera en ese instante veria el cupo todavia
--   ocupado. Al ejecutarse en el COMMIT, la capacidad ya esta liberada.
--
--   Ademas cubre TODAS las vias de cancelacion sin tocarlas una por una:
--   admin (staff_cancelar_reserva / admin_cancelar_agenda), staff
--   (staff_marcar_estado_agenda), cliente (cliente_cancelar_reserva) y la
--   expiracion automatica de un pago (reserva_pago_expirar).
--
-- LO QUE NO CAMBIA
--   * Nada del bot: se llaman sus funciones tal cual, con su propio manejo de
--     errores y su registro en `flow.bot_log`.
--   * Si no hay nadie en la cola, `bot_procesar_*` no hace nada (movidos = 0).
--   * El bot NUNCA puede tumbar la cancelacion: el trigger captura cualquier
--     error y lo deja en `bot_log`.
--   * Reactivar y completar no disparan nada (reactivar consume cupo, completar
--     no lo libera).
--
-- REVERSION
--   drop trigger if exists trg_agenda_bot_al_cancelar on flow.agenda;
--   drop function if exists flow.trg_agenda_bot_al_cancelar();
--
-- IDEMPOTENTE.
-- ============================================================================

create or replace function flow.trg_agenda_bot_al_cancelar()
returns trigger
language plpgsql
security definer
set search_path = flow, public
as $function$
declare
  v_cancelado integer;
  v_reservado integer;
  v_dia       date;
  v_plan      bigint;
  v_res       jsonb;
begin
  select id into v_cancelado from flow.nom_estado_agenda where nombre = 'Cancelado' limit 1;
  select id into v_reservado from flow.nom_estado_agenda where nombre = 'Reservado' limit 1;

  -- Solo interesa la transicion que LIBERA cupo: activa -> cancelada.
  if v_cancelado is null
     or new.id_estado is distinct from v_cancelado
     or old.id_estado is distinct from v_reservado then
    return new;
  end if;

  v_dia := (new.fecha_hora_reserva at time zone 'America/Havana')::date;

  begin
    if new.id_turno is not null then
      -- Camino recursos/turnos: reparte el cupo liberado entre la cola de ESE
      -- turno (y de turnos posteriores sin cola propia).
      v_res := flow.bot_procesar_recurso_dia(new.id_turno, v_dia);
    else
      -- Camino legacy: cupo del dia en `plan_servicios`.
      select ps.id into v_plan
        from flow.plan_servicios ps
       where ps.id_local_servicio = new.id_local_servicio
         and (ps.fecha at time zone 'America/Havana')::date = v_dia
       limit 1;

      if v_plan is not null then
        v_res := flow.bot_procesar_plan(v_plan);
      end if;
    end if;
  exception
    when others then
      -- El bot jamás puede abortar la cancelación del usuario.
      insert into flow.bot_log (id_plan, id_local_servicio, resultado, movidos, mensaje, detalle)
      values (v_plan, new.id_local_servicio, 'error', 0,
              'trigger cancelacion: ' || sqlerrm,
              jsonb_build_object(
                'id_agenda', new.id,
                'id_turno', new.id_turno,
                'fecha', v_dia,
                'sqlstate', sqlstate
              ));
  end;

  return new;
end;
$function$;

comment on function flow.trg_agenda_bot_al_cancelar() is
  'Cuando una reserva pasa de Reservado a Cancelado, manda correr el bot de la cola para el turno/dia liberado. Deferido al COMMIT para que el cupo ya este devuelto.';

drop trigger if exists trg_agenda_bot_al_cancelar on flow.agenda;

create constraint trigger trg_agenda_bot_al_cancelar
  after update on flow.agenda
  deferrable initially deferred
  for each row
  execute function flow.trg_agenda_bot_al_cancelar();

-- ══ VERIFICACION (ejecutar a mano despues de aplicar) ══════════════════════
--
-- V.1 El trigger existe y es deferido.
-- select tgname, tgdeferrable, tginitdeferred, tgconstraint <> 0 as es_constraint
--   from pg_trigger
--  where tgrelid = 'flow.agenda'::regclass and tgname = 'trg_agenda_bot_al_cancelar';
--   -- 1 fila: deferrable = true, initdeferred = true
--
-- V.2 Al cancelar con cola, el siguiente de la cola recibe la reserva.
--   (necesita un turno con plan_tramo lleno y una fila en flow.sala_espera)
-- select flow.staff_cancelar_reserva(<id_agenda>, 'Prueba bot');
-- select * from flow.sala_espera where id_local_servicio = <ls>;  -- debe quedar vacia
-- select * from flow.agenda where id_local_servicio = <ls> order by id desc limit 3;
--   -- debe aparecer una agenda nueva con fecha = dia liberado
-- select * from flow.bot_log order by id desc limit 3;
--   -- resultado 'ok', movidos >= 1
--
-- V.3 Sin nadie en la cola no pasa nada (no crea reservas).
-- select flow.bot_procesar_recurso_dia(<id_turno>, current_date);  -- movidos: 0