-- ============================================================================
-- RPC CLIENTE: RESERVA DIRECTA (sin pasar por la cola).
--
-- Cuando un local_servicio tiene permite_reserva_directa = true y existe un
-- plan_servicios con cupo ese dia, el cliente reserva al instante: se crea la
-- agenda en estado 'Reservado' y se suma +1 a plan_servicios.agendados.
--
-- Serializa con la cola y el bot del MISMO servicio via el advisory lock
-- compartido pg_advisory_xact_lock(hashtext('flow.sala_espera'), id_ls), de modo
-- que no se sobre-reserve si el bot esta repartiendo al mismo tiempo.
--
-- Idempotencia/antifraude: si el usuario ya tiene una agenda 'Reservado' ese dia
-- para ese servicio, no crea otra (devuelve error controlado).
--
-- security definer: escribe en agenda / plan_servicios / notificaciones.
-- Concedida solo a authenticated.
-- Devuelve: { ok, data:{ id_agenda, fecha } } | { ok:false, error }.
-- ============================================================================

-- Firma anterior (3 params) reemplazada por la nueva (con cantidad/datos/tercero).
drop function if exists flow.cliente_reservar_directo(uuid, integer, date);

create or replace function flow.cliente_reservar_directo(
  p_uuid_usuario      uuid,
  p_id_local_servicio integer,
  p_fecha             date,
  p_cantidad          integer default null,
  p_datos_adicionales jsonb   default null,
  p_para_tercero      boolean default false,
  p_t_nombre          text    default null,
  p_t_apellidos       text    default null,
  p_t_ci              text    default null,
  p_t_telefono        text    default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = flow, public
as $$
declare
  v_permite         boolean;
  v_cantidad_default integer;
  v_cantidad_max    integer;
  v_plan_id         bigint;
  v_disponibles     integer;
  v_estado          integer;
  v_id_agenda       integer;
  v_fecha_ts        timestamp without time zone;
  v_titular         uuid;    -- a nombre de quien queda la reserva
  v_nombre_servicio text;
  v_nombre_local    text;
  v_saludo          text;
  v_cant            integer;
begin
  if p_uuid_usuario is null or p_id_local_servicio is null or p_fecha is null then
    return jsonb_build_object('ok', false, 'error', 'parametros obligatorios faltantes');
  end if;

  -- Serializa con entrar/salir de la cola y con el bot de ESTE servicio.
  perform pg_advisory_xact_lock(hashtext('flow.sala_espera'), p_id_local_servicio);

  -- ¿El servicio permite reserva directa? (y, si aplica, terceros)
  select ls.permite_reserva_directa,
         ls.cantidad_default,
         ls.cantidad_max_capacidad
    into v_permite, v_cantidad_default, v_cantidad_max
  from flow.local_servicio ls
  where ls.id = p_id_local_servicio;

  if v_permite is null then
    return jsonb_build_object('ok', false, 'error', 'El servicio no existe');
  end if;
  if v_permite is not true then
    return jsonb_build_object('ok', false, 'error', 'Reserva directa no habilitada para este servicio');
  end if;

  -- Resolver el titular de la reserva: uno mismo o un tercero.
  if coalesce(p_para_tercero, false) then
    -- Validar que el servicio permita terceros
    if not exists (
      select 1 from flow.local_servicio ls
      join flow.app_dat_servicios s on s.id = ls.id_servicio
      where ls.id = p_id_local_servicio and s.permite_tercero = true
    ) then
      return jsonb_build_object('ok', false, 'error', 'Este servicio no permite reservar para terceros');
    end if;
    v_titular := flow._resolver_perfil_tercero(p_t_nombre, p_t_apellidos, p_t_ci, p_t_telefono);
  else
    v_titular := p_uuid_usuario;
  end if;

  -- Resolver y validar cantidad contra la configuración del local_servicio.
  v_cant := coalesce(p_cantidad, v_cantidad_default, 1);
  if v_cant < 1 then
    return jsonb_build_object('ok', false, 'error', 'La cantidad debe ser al menos 1');
  end if;
  if v_cant > v_cantidad_max then
    return jsonb_build_object('ok', false, 'error',
      'La cantidad maxima por reserva es ' || v_cantidad_max);
  end if;

  -- Estado destino (igual que el bot)
  select id into v_estado from flow.nom_estado_agenda where nombre = 'Reservado' limit 1;
  if v_estado is null then
    return jsonb_build_object('ok', false, 'error', 'falta el estado Reservado (correr migracion 03)');
  end if;

  -- Idempotencia: el titular ya tiene reserva activa ese dia/servicio
  if exists (
    select 1 from flow.agenda a
    where a.uuid_usuario = v_titular
      and a.id_local_servicio = p_id_local_servicio
      and a.id_estado = v_estado
      and (a.fecha_hora_reserva at time zone 'America/Havana')::date = p_fecha
  ) then
    return jsonb_build_object('ok', false, 'error',
      case when v_titular = p_uuid_usuario
           then 'Ya tienes una reserva ese dia'
           else 'Esa persona ya tiene una reserva ese dia' end);
  end if;

  -- Plan del dia con cupo, bloqueado para evitar sobre-reserva.
  select ps.id, (ps.cantidad - ps.agendados) into v_plan_id, v_disponibles
  from flow.plan_servicios ps
  where ps.id_local_servicio = p_id_local_servicio
    and ps.cantidad is not null
    and ps.agendados < ps.cantidad
    and (ps.fecha at time zone 'America/Havana')::date = p_fecha
  order by ps.id
  limit 1
  for update;

  if v_plan_id is null then
    return jsonb_build_object('ok', false, 'error', 'No hay turnos disponibles');
  end if;

  -- Validar cantidad contra lo realmente disponible.
  if v_cant > v_disponibles then
    return jsonb_build_object('ok', false,
      'error', 'No hay suficientes turnos (quedan ' || v_disponibles || ')');
  end if;

  -- La agenda se guarda al mediodia local del dia (estable frente a medianoche/DST)
  v_fecha_ts := (make_timestamp(extract(year from p_fecha)::int,
                                extract(month from p_fecha)::int,
                                extract(day from p_fecha)::int, 12, 0, 0));

  insert into flow.agenda
    (uuid_usuario, id_local_servicio, id_estado, fecha_hora_reserva,
     cantidad, datos_adicionales, reservado_por)
  values
    (v_titular, p_id_local_servicio, v_estado, v_fecha_ts,
     v_cant, p_datos_adicionales, p_uuid_usuario)
  returning id into v_id_agenda;

  update flow.plan_servicios
     set agendados = agendados + v_cant
   where id = v_plan_id;

  -- Notificacion "reservacion confirmada" al que RESERVA (p_uuid_usuario).
  select s.nombre, l.nombre
    into v_nombre_servicio, v_nombre_local
  from flow.local_servicio ls
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  join flow.app_dat_locales   l on l.id = ls.id_local
  where ls.id = p_id_local_servicio;

  v_saludo := case
    when extract(hour from current_timestamp) between 5 and 11 then 'Buenos dias'
    when extract(hour from current_timestamp) between 12 and 18 then 'Buenas tardes'
    else 'Buenas noches'
  end;

  insert into flow.notificaciones
    (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
  select
    p_uuid_usuario,
    'reserva',
    'Reservacion confirmada',
    v_saludo || ', '
      || coalesce(nullif(trim(p.nombre || ' ' || p.apellidos), ''), 'estimado cliente')
      || ', se ha realizado satisfactoriamente '
      || case when v_cant > 1 then v_cant || ' reservaciones' else 'su reservacion' end
      || case when coalesce(p_para_tercero, false)
              then ' a nombre de ' || coalesce(nullif(trim(coalesce(p_t_nombre,'') || ' ' || coalesce(p_t_apellidos,'')), ''), 'un tercero')
              else '' end
      || ' para el local "'
      || coalesce(v_nombre_local, 'local') || '" el servicio "'
      || coalesce(v_nombre_servicio, 'servicio') || '" para la fecha '
      || to_char(v_fecha_ts, 'DD/MM/YYYY') || '.',
    p_id_local_servicio,
    v_id_agenda,
    jsonb_build_object(
      'fecha',    v_fecha_ts,
      'servicio', v_nombre_servicio,
      'local',    v_nombre_local,
      'cantidad', v_cant
    )
  from (select 1) x
  left join flow.perfil p on p.uuid_usuario = p_uuid_usuario;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id_agenda', v_id_agenda,
      'fecha',     to_char(v_fecha_ts, 'YYYY-MM-DD'),
      'cantidad',  v_cant
    )
  );

exception
  when others then
    return jsonb_build_object('ok', false, 'error', sqlerrm, 'sqlstate', sqlstate);
end;
$$;

revoke all on function flow.cliente_reservar_directo(uuid, integer, date, integer, jsonb, boolean, text, text, text, text) from public;
grant execute on function flow.cliente_reservar_directo(uuid, integer, date, integer, jsonb, boolean, text, text, text, text) to authenticated;

-- Uso:
--   select flow.cliente_reservar_directo('00000000-...', 7, '2026-07-03');                       -- 1 turno, para si
--   select flow.cliente_reservar_directo('00000000-...', 7, '2026-07-03', 3,
--            '{"codigo_pais":"53","estado_civil":"Soltero"}'::jsonb);                             -- 3 turnos + datos
--   select flow.cliente_reservar_directo('00000000-...', 7, '2026-07-03', 1, null,
--            true, 'Ana', 'Paz', '85010112345', '55512345');                                      -- para tercero
