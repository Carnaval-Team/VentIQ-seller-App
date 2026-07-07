-- ============================================================================
-- RPC CLIENTE: cancelar una reserva propia (o hecha para un tercero)
--
-- Valida:
--   1. La reserva existe y pertenece al usuario (uuid_usuario o reservado_por).
--   2. La reserva está en estado 'Reservado'.
--   3. Si la entidad configuró horas_anticipacion_cancelacion (>0), aún debe quedar
--      ese plazo antes de la fecha_hora_reserva.
--   4. Si no hay configuración (0 o null), el cliente puede cancelar en cualquier momento.
--
-- Acciones:
--   - Cambia el estado a 'Cancelado'.
--   - Resta la cantidad reservada de plan_servicios.agendados (si aplica).
--   - Devuelve { ok, data } o { ok:false, error }.
-- ============================================================================

create or replace function flow.cliente_cancelar_reserva(
  p_uuid_usuario uuid,
  p_id_agenda    integer
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = flow, public
as $$
declare
  v_agenda              flow.agenda%rowtype;
  v_estado_reservado    integer;
  v_estado_cancelado    integer;
  v_horas_anticipacion  integer;
  v_limite              timestamp without time zone;
  v_plan_id             bigint;
  v_nombre_servicio     text;
  v_nombre_local        text;
begin
  if p_uuid_usuario is null or p_id_agenda is null then
    return jsonb_build_object('ok', false, 'error', 'parametros obligatorios faltantes');
  end if;

  -- Estados
  select id into v_estado_reservado from flow.nom_estado_agenda where nombre = 'Reservado' limit 1;
  select id into v_estado_cancelado from flow.nom_estado_agenda where nombre = 'Cancelado' limit 1;
  if v_estado_reservado is null or v_estado_cancelado is null then
    return jsonb_build_object('ok', false, 'error', 'faltan estados de agenda');
  end if;

  -- Cargar la reserva y validar propiedad
  select a.* into v_agenda
  from flow.agenda a
  where a.id = p_id_agenda;

  if v_agenda.id is null then
    return jsonb_build_object('ok', false, 'error', 'Reserva no encontrada');
  end if;

  if v_agenda.uuid_usuario != p_uuid_usuario and v_agenda.reservado_por != p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'No tienes permiso para cancelar esta reserva');
  end if;

  if v_agenda.id_estado != v_estado_reservado then
    return jsonb_build_object('ok', false, 'error', 'Solo se pueden cancelar reservas activas');
  end if;

  -- Configuración de cancelación de la entidad
  select e.horas_anticipacion_cancelacion
    into v_horas_anticipacion
  from flow.local_servicio ls
  join flow.app_dat_locales l on l.id = ls.id_local
  join flow.entidad         e on e.id = l.id_entidad
  where ls.id = v_agenda.id_local_servicio;

  -- Solo validar ventana si la entidad configuró horas de anticipación (>0).
  -- Si no hay configuración (0 o null), el cliente puede cancelar en cualquier momento.
  if coalesce(v_horas_anticipacion, 0) > 0 then
    v_limite := v_agenda.fecha_hora_reserva - (v_horas_anticipacion || ' hours')::interval;
    if current_timestamp > v_limite then
      return jsonb_build_object('ok', false, 'error',
        'Solo puedes cancelar hasta ' || v_horas_anticipacion || ' horas antes de la reserva');
    end if;
  end if;

  -- Buscar plan del día para restar agendados (sin forzar: puede no existir si el plan fue borrado)
  select ps.id
    into v_plan_id
  from flow.plan_servicios ps
  where ps.id_local_servicio = v_agenda.id_local_servicio
    and (ps.fecha at time zone 'America/Havana')::date = (v_agenda.fecha_hora_reserva at time zone 'America/Havana')::date
  limit 1;

  -- Aplicar cancelación en una transacción implícita
  update flow.agenda
     set id_estado = v_estado_cancelado,
         updated_at = current_timestamp
   where id = p_id_agenda;

  if v_plan_id is not null then
    update flow.plan_servicios
       set agendados = greatest(0, agendados - v_agenda.cantidad)
     where id = v_plan_id;
  end if;

  -- Notificación al cliente que canceló
  select s.nombre, l.nombre
    into v_nombre_servicio, v_nombre_local
  from flow.local_servicio ls
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  join flow.app_dat_locales   l on l.id = ls.id_local
  where ls.id = v_agenda.id_local_servicio;

  insert into flow.notificaciones
    (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
  values
    (p_uuid_usuario,
     'reserva',
     'Reserva cancelada',
     'Se ha cancelado tu reserva para el servicio "' || coalesce(v_nombre_servicio, 'servicio')
       || '" en "' || coalesce(v_nombre_local, 'local') || '" para el '
       || to_char(v_agenda.fecha_hora_reserva, 'DD/MM/YYYY') || '.',
     v_agenda.id_local_servicio,
     v_agenda.id,
     jsonb_build_object(
       'fecha',    v_agenda.fecha_hora_reserva,
       'servicio', v_nombre_servicio,
       'local',    v_nombre_local,
       'cantidad', v_agenda.cantidad
     ));

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id_agenda', p_id_agenda,
      'fecha',     to_char(v_agenda.fecha_hora_reserva, 'YYYY-MM-DD')
    )
  );

exception
  when others then
    return jsonb_build_object('ok', false, 'error', sqlerrm, 'sqlstate', sqlstate);
end;
$$;

revoke all on function flow.cliente_cancelar_reserva(uuid, integer) from public;
grant execute on function flow.cliente_cancelar_reserva(uuid, integer) to authenticated;

-- Uso:
--   select flow.cliente_cancelar_reserva('00000000-...', 42);
