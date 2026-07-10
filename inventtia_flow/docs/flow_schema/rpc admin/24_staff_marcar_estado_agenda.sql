-- ============================================================================
-- RPC: staff (owner / entidad_admin / entidad_vendedor) marca una agenda como
-- Completado (id 3) o Cancelado (id 2) desde el listado de reservas del
-- administrador o del vendedor.
--
-- Reglas de negocio:
--   - Solo estados destino validos: 2 (Cancelado) o 3 (Completado).
--   - Solo se puede actuar sobre reservas activas ('Reservado').
--   - Al CANCELAR se libera la capacidad del plan del dia
--     (plan_servicios.agendados - agenda.cantidad, con piso en 0) y se notifica
--     al titular de la reserva.
--   - Al COMPLETAR se sella fecha_hora_atencion = current_timestamp.
--
-- SECURITY DEFINER: escribe en agenda / plan_servicios / notificaciones bajo RLS.
-- Autorizacion explicita: owner de la entidad, admin de la entidad, o vendedor
-- de la entidad a la que pertenece el local de la reserva.
-- Devuelve la agenda actualizada en el formato que espera Agenda.fromJson.
-- ============================================================================

create or replace function flow.staff_marcar_estado_agenda(
  p_id_agenda integer,
  p_id_estado integer
)
returns json
language plpgsql
security definer
set search_path = flow, public
as $$
declare
  v_agenda        record;
  v_id_reservado  int;
  v_plan_id       bigint;
  v_result        json;
  v_nombre_serv   text;
  v_nombre_local  text;
begin
  -- Solo estados destino validos: Cancelado (2) o Completado (3).
  if p_id_estado not in (2, 3) then
    raise exception 'Estado destino no permitido (use Cancelado o Completado)';
  end if;

  -- Autorizacion: owner / admin / vendedor de la entidad de la reserva.
  if not exists (
    select 1
    from flow.agenda a
    join flow.local_servicio ls on ls.id = a.id_local_servicio
    join flow.app_dat_locales l on l.id = ls.id_local
    where a.id = p_id_agenda
      and (
        l.id_entidad in (select id from flow.entidad where owner_uuid = auth.uid())
        or exists (
          select 1 from flow.entidad_admin ea
          where ea.id_entidad = l.id_entidad and ea.uuid_usuario = auth.uid()
        )
        or exists (
          select 1 from flow.entidad_vendedor ev
          where ev.id_entidad = l.id_entidad and ev.uuid_usuario = auth.uid()
        )
      )
  ) then
    raise exception 'No tiene permisos sobre esta reserva';
  end if;

  -- Cargar la reserva.
  select a.id, a.uuid_usuario, a.id_local_servicio, a.id_estado,
         a.fecha_hora_reserva, a.cantidad
    into v_agenda
    from flow.agenda a
   where a.id = p_id_agenda;

  select id into v_id_reservado from flow.nom_estado_agenda where nombre = 'Reservado';

  -- Solo se puede actuar sobre reservas activas.
  if v_agenda.id_estado is distinct from v_id_reservado then
    raise exception 'Solo se pueden completar o cancelar reservas activas';
  end if;

  -- Al cancelar: liberar capacidad del plan del dia.
  if p_id_estado = 2 then
    select ps.id into v_plan_id
      from flow.plan_servicios ps
     where ps.id_local_servicio = v_agenda.id_local_servicio
       and (ps.fecha at time zone 'America/Havana')::date =
           (v_agenda.fecha_hora_reserva at time zone 'America/Havana')::date
     limit 1;

    if v_plan_id is not null then
      update flow.plan_servicios
         set agendados = greatest(0, agendados - v_agenda.cantidad)
       where id = v_plan_id;
    end if;
  end if;

  -- Actualizar el estado (y sellar atencion si se completa).
  update flow.agenda
     set id_estado = p_id_estado,
         fecha_hora_atencion = case when p_id_estado = 3 then current_timestamp
                                    else fecha_hora_atencion end,
         updated_at = current_timestamp
   where id = p_id_agenda;

  -- Notificar al titular si se cancela.
  if p_id_estado = 2 and v_agenda.uuid_usuario is not null then
    select s.nombre, l.nombre into v_nombre_serv, v_nombre_local
      from flow.local_servicio ls
      join flow.app_dat_servicios s on s.id = ls.id_servicio
      join flow.app_dat_locales   l on l.id = ls.id_local
     where ls.id = v_agenda.id_local_servicio;

    insert into flow.notificaciones
      (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
    values (
      v_agenda.uuid_usuario, 'reserva', 'Reserva cancelada',
      'Su reserva para "' || coalesce(v_nombre_serv, 'el servicio')
        || '" en "' || coalesce(v_nombre_local, 'el local')
        || '" del ' || to_char(v_agenda.fecha_hora_reserva, 'DD/MM/YYYY')
        || ' ha sido cancelada por la administracion.',
      v_agenda.id_local_servicio, p_id_agenda,
      jsonb_build_object('fecha', v_agenda.fecha_hora_reserva)
    );
  end if;

  -- Devolver la agenda actualizada (formato Agenda.fromJson).
  select json_build_object(
    'id', a.id,
    'uuid_usuario', a.uuid_usuario,
    'id_local_servicio', a.id_local_servicio,
    'id_estado', a.id_estado,
    'fecha_hora_reserva', a.fecha_hora_reserva,
    'fecha_hora_atencion', a.fecha_hora_atencion,
    'created_at', a.created_at,
    'updated_at', a.updated_at,
    'cantidad', a.cantidad,
    'datos_adicionales', a.datos_adicionales,
    'reservado_por', a.reservado_por,
    'nom_estado_agenda', json_build_object(
      'id', nea.id, 'nombre', nea.nombre, 'descripcion', nea.descripcion
    )
  ) into v_result
  from flow.agenda a
  join flow.nom_estado_agenda nea on nea.id = a.id_estado
  where a.id = p_id_agenda;

  return v_result;
end;
$$;

revoke all on function flow.staff_marcar_estado_agenda(integer, integer) from public;
grant execute on function flow.staff_marcar_estado_agenda(integer, integer) to authenticated;

-- Uso:
--   select flow.staff_marcar_estado_agenda(123, 3);  -- completar
--   select flow.staff_marcar_estado_agenda(123, 2);  -- cancelar
