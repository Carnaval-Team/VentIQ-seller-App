-- ============================================================================
-- RPC ADMIN: CREAR RESERVA DIRECTA desde la administración.
--
-- Igual que cliente_reservar_directo pero:
--   1. No valida permite_reserva_directa (el admin puede reservar siempre).
--   2. Valida que p_uuid_usuario_admin sea admin/owner de la entidad del servicio.
--   3. El campo reservado_por queda con el uuid del admin.
--   4. El titular (uuid_usuario) es el admin mismo (reserva a nombre propio
--      con los datos_adicionales del cliente físico).
--
-- security definer: escribe en agenda / plan_servicios.
-- Concedida solo a authenticated.
-- Devuelve: { ok, data:{ id_agenda, fecha } } | { ok:false, error }.
-- ============================================================================

create or replace function flow.admin_crear_reserva_directa(
  p_uuid_admin        uuid,
  p_id_local_servicio integer,
  p_fecha             date,
  p_cantidad          integer default null,
  p_datos_adicionales jsonb   default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = flow, public
as $$
declare
  v_cantidad_default  integer;
  v_cantidad_max      integer;
  v_plan_id           bigint;
  v_disponibles       integer;
  v_estado            integer;
  v_id_agenda         integer;
  v_fecha_ts          timestamp without time zone;
  v_nombre_servicio   text;
  v_nombre_local      text;
  v_cant              integer;
  v_es_admin          boolean;
begin
  if p_uuid_admin is null or p_id_local_servicio is null or p_fecha is null then
    return jsonb_build_object('ok', false, 'error', 'parametros obligatorios faltantes');
  end if;

  -- Verificar que el usuario es admin o owner de la entidad dueña del servicio.
  select exists (
    select 1
    from flow.local_servicio ls
    join flow.app_dat_locales l on l.id = ls.id_local
    join flow.entidad e on e.id = l.id_entidad
    where ls.id = p_id_local_servicio
      and (
        e.owner_uuid = p_uuid_admin
        or exists (
          select 1 from flow.entidad_admin ea
          where ea.id_entidad = e.id and ea.uuid_usuario = p_uuid_admin
        )
      )
  ) into v_es_admin;

  if not v_es_admin then
    return jsonb_build_object('ok', false, 'error', 'No tienes permisos de administrador sobre este servicio');
  end if;

  -- Serializa con la cola y el bot del MISMO servicio.
  perform pg_advisory_xact_lock(hashtext('flow.sala_espera'), p_id_local_servicio);

  -- Capacidad configurada del servicio
  select ls.cantidad_default, ls.cantidad_max_capacidad
    into v_cantidad_default, v_cantidad_max
  from flow.local_servicio ls
  where ls.id = p_id_local_servicio;

  if v_cantidad_default is null then
    return jsonb_build_object('ok', false, 'error', 'El servicio no existe');
  end if;

  -- Resolver y validar cantidad
  v_cant := coalesce(p_cantidad, v_cantidad_default, 1);
  if v_cant < 1 then
    return jsonb_build_object('ok', false, 'error', 'La cantidad debe ser al menos 1');
  end if;
  if v_cant > v_cantidad_max then
    return jsonb_build_object('ok', false, 'error',
      'La cantidad maxima por reserva es ' || v_cantidad_max);
  end if;

  -- Estado destino
  select id into v_estado from flow.nom_estado_agenda where nombre = 'Reservado' limit 1;
  if v_estado is null then
    return jsonb_build_object('ok', false, 'error', 'falta el estado Reservado (correr migracion 03)');
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
    return jsonb_build_object('ok', false, 'error', 'No hay turnos disponibles para esa fecha');
  end if;

  if v_cant > v_disponibles then
    return jsonb_build_object('ok', false,
      'error', 'No hay suficientes turnos (quedan ' || v_disponibles || ')');
  end if;

  -- La agenda se guarda al mediodia local del dia
  v_fecha_ts := (make_timestamp(extract(year from p_fecha)::int,
                                extract(month from p_fecha)::int,
                                extract(day from p_fecha)::int, 12, 0, 0));

  insert into flow.agenda
    (uuid_usuario, id_local_servicio, id_estado, fecha_hora_reserva,
     cantidad, datos_adicionales, reservado_por)
  values
    (p_uuid_admin, p_id_local_servicio, v_estado, v_fecha_ts,
     v_cant, p_datos_adicionales, p_uuid_admin)
  returning id into v_id_agenda;

  update flow.plan_servicios
     set agendados = agendados + v_cant
   where id = v_plan_id;

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

revoke all on function flow.admin_crear_reserva_directa(uuid, integer, date, integer, jsonb) from public;
grant execute on function flow.admin_crear_reserva_directa(uuid, integer, date, integer, jsonb) to authenticated;
