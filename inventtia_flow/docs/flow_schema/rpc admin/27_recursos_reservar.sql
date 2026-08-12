-- ============================================================================
-- RECURSOS - Fase 2 (parte B): reserva directa turno-aware + cancelaciones.
--
-- Se AÑADE el parametro p_id_turno (nullable) a las RPCs de reserva directa.
--   - p_id_turno NULL  -> comportamiento legacy (descuenta plan_servicios).
--   - p_id_turno != NULL -> valida que el turno pertenezca al LS, verifica cupo
--     en TODOS sus tramos (plan_tramo del dia), inserta agenda con id_turno e
--     incrementa agendados en cada plan_tramo. La reserva ocupa 1 plaza de cada
--     tramo del turno (multiplicado por la cantidad reservada).
--
-- Helper flow._reservar_tramos: bajo el advisory lock ya tomado por el caller,
-- bloquea (FOR UPDATE) los plan_tramo del turno del dia, valida cupo y descuenta.
-- Devuelve el minimo disponible ANTES de descontar (para mensajes) o -1 si algun
-- tramo no tiene plan ese dia. Lanza si no alcanza el cupo.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Helper interno: descuenta v_cant plazas de cada tramo del turno en la fecha.
-- Debe llamarse dentro de la transaccion con el advisory lock del LS tomado.
-- Retorna jsonb { ok, disponibles } o { ok:false, error }.
-- ----------------------------------------------------------------------------
create or replace function flow._descontar_tramos_turno(
  p_id_turno integer,
  p_fecha    date,
  p_cant     integer
)
returns jsonb
language plpgsql volatile set search_path = flow, public
as $$
declare
  v_n_tramos   integer;
  v_n_plan     integer;
  v_min_disp   integer;
begin
  -- Cuantos tramos consume el turno.
  select count(*) into v_n_tramos
  from flow.turno_tramo tt where tt.id_turno = p_id_turno;

  if coalesce(v_n_tramos, 0) = 0 then
    return jsonb_build_object('ok', false, 'error', 'El turno no tiene tramos configurados');
  end if;

  -- Bloquea los plan_tramo del turno para ese dia (FIFO-safe contra el bot).
  create temporary table if not exists _tmp_pt (id bigint, disp integer) on commit drop;
  delete from _tmp_pt;

  insert into _tmp_pt (id, disp)
  select pt.id, (pt.cantidad - pt.agendados)
  from flow.turno_tramo tt
  join flow.tramo tr      on tr.id = tt.id_tramo and tr.activo
  join flow.plan_tramo pt on pt.id_tramo = tr.id
  where tt.id_turno = p_id_turno
    and (pt.fecha at time zone 'America/Havana')::date = p_fecha
  for update of pt;

  select count(*), min(disp) into v_n_plan, v_min_disp from _tmp_pt;

  -- Todos los tramos del turno deben tener plan ese dia.
  if coalesce(v_n_plan, 0) < v_n_tramos then
    return jsonb_build_object('ok', false, 'error', 'El turno no esta disponible esa fecha');
  end if;

  if v_min_disp < p_cant then
    return jsonb_build_object('ok', false,
      'error', 'No hay cupo suficiente (quedan ' || greatest(v_min_disp, 0) || ')');
  end if;

  -- Descontar en todos los tramos del turno.
  update flow.plan_tramo pt
     set agendados = pt.agendados + p_cant
  from _tmp_pt tmp
  where pt.id = tmp.id;

  return jsonb_build_object('ok', true, 'disponibles', v_min_disp);
end;
$$;

-- ============================================================================
-- 1) CLIENTE: reservar directo (con p_id_turno opcional).
-- ============================================================================
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
  p_t_telefono        text    default null,
  p_moneda            text    default null,
  p_id_turno          integer default null
)
returns jsonb
language plpgsql security definer set search_path = flow, public
as $$
declare
  v_permite          boolean;
  v_cantidad_default integer;
  v_cantidad_max     integer;
  v_plan_id          bigint;
  v_disponibles      integer;
  v_estado           integer;
  v_id_agenda        integer;
  v_fecha_ts         timestamp without time zone;
  v_titular          uuid;
  v_nombre_servicio  text;
  v_nombre_local     text;
  v_saludo           text;
  v_cant             integer;
  v_id_servicio      integer;
  v_precio_total     numeric;
  v_moneda           varchar;
  v_desc             jsonb;
begin
  if p_uuid_usuario is null or p_id_local_servicio is null or p_fecha is null then
    return jsonb_build_object('ok', false, 'error', 'parametros obligatorios faltantes');
  end if;

  perform pg_advisory_xact_lock(hashtext('flow.sala_espera'), p_id_local_servicio);

  select ls.permite_reserva_directa, ls.cantidad_default,
         ls.cantidad_max_capacidad, ls.id_servicio
    into v_permite, v_cantidad_default, v_cantidad_max, v_id_servicio
  from flow.local_servicio ls
  where ls.id = p_id_local_servicio;

  if v_permite is null then
    return jsonb_build_object('ok', false, 'error', 'El servicio no existe');
  end if;
  if v_permite is not true then
    return jsonb_build_object('ok', false, 'error', 'Reserva directa no habilitada para este servicio');
  end if;

  -- Si se pide turno, validar que pertenezca a un recurso activo de este LS.
  if p_id_turno is not null then
    if not exists (
      select 1 from flow.turno t
      join flow.recurso r on r.id = t.id_recurso and r.activo
      where t.id = p_id_turno and t.activo and r.id_local_servicio = p_id_local_servicio
    ) then
      return jsonb_build_object('ok', false, 'error', 'Turno invalido para este servicio');
    end if;
  end if;

  -- Titular: uno mismo o un tercero.
  if coalesce(p_para_tercero, false) then
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

  v_cant := coalesce(p_cantidad, v_cantidad_default, 1);
  if v_cant < 1 then
    return jsonb_build_object('ok', false, 'error', 'La cantidad debe ser al menos 1');
  end if;
  if v_cant > v_cantidad_max then
    return jsonb_build_object('ok', false, 'error',
      'La cantidad maxima por reserva es ' || v_cantidad_max);
  end if;

  select id into v_estado from flow.nom_estado_agenda where nombre = 'Reservado' limit 1;
  if v_estado is null then
    return jsonb_build_object('ok', false, 'error', 'falta el estado Reservado (correr migracion 03)');
  end if;

  -- Idempotencia: el titular ya tiene reserva activa ese dia/servicio.
  -- Con turnos, la idempotencia es por (dia, turno) para permitir ida y vuelta
  -- distintos; sin turno, por dia como antes.
  if exists (
    select 1 from flow.agenda a
    where a.uuid_usuario = v_titular
      and a.id_local_servicio = p_id_local_servicio
      and a.id_estado = v_estado
      and (a.fecha_hora_reserva at time zone 'America/Havana')::date = p_fecha
      and a.id_turno is not distinct from p_id_turno
  ) then
    return jsonb_build_object('ok', false, 'error',
      case when v_titular = p_uuid_usuario
           then 'Ya tienes una reserva ese dia'
           else 'Esa persona ya tiene una reserva ese dia' end);
  end if;

  v_fecha_ts := (make_timestamp(extract(year from p_fecha)::int,
                                extract(month from p_fecha)::int,
                                extract(day from p_fecha)::int, 12, 0, 0));

  if p_id_turno is not null then
    -- ── Camino recursos: descontar de los tramos del turno ──
    v_desc := flow._descontar_tramos_turno(p_id_turno, p_fecha, v_cant);
    if (v_desc ->> 'ok') <> 'true' then
      return jsonb_build_object('ok', false, 'error', v_desc ->> 'error');
    end if;
  else
    -- ── Camino legacy: plan_servicios ──
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
    if v_cant > v_disponibles then
      return jsonb_build_object('ok', false,
        'error', 'No hay suficientes turnos (quedan ' || v_disponibles || ')');
    end if;
  end if;

  select cp.precio_total, cp.moneda
    into v_precio_total, v_moneda
  from flow.calcular_precio_reserva(
    v_id_servicio, coalesce(p_datos_adicionales, '{}'::jsonb), p_moneda, v_cant
  ) cp;

  insert into flow.agenda
    (uuid_usuario, id_local_servicio, id_estado, fecha_hora_reserva,
     cantidad, datos_adicionales, reservado_por, precio_total, moneda, id_turno)
  values
    (v_titular, p_id_local_servicio, v_estado, v_fecha_ts,
     v_cant, p_datos_adicionales, p_uuid_usuario, v_precio_total, v_moneda, p_id_turno)
  returning id into v_id_agenda;

  if p_id_turno is null then
    update flow.plan_servicios set agendados = agendados + v_cant where id = v_plan_id;
  end if;

  -- Notificacion "reservacion confirmada".
  select s.nombre, l.nombre into v_nombre_servicio, v_nombre_local
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
    p_uuid_usuario, 'reserva', 'Reservacion confirmada',
    v_saludo || ', '
      || coalesce(nullif(trim(p.nombre || ' ' || p.apellidos), ''), 'estimado cliente')
      || ', se ha realizado satisfactoriamente '
      || case when v_cant > 1 then v_cant || ' reservaciones' else 'su reservacion' end
      || case when coalesce(p_para_tercero, false)
              then ' a nombre de ' || coalesce(nullif(trim(coalesce(p_t_nombre,'') || ' ' || coalesce(p_t_apellidos,'')), ''), 'un tercero')
              else '' end
      || ' para el local "' || coalesce(v_nombre_local, 'local')
      || '" el servicio "' || coalesce(v_nombre_servicio, 'servicio')
      || '" para la fecha ' || to_char(v_fecha_ts, 'DD/MM/YYYY') || '.',
    p_id_local_servicio, v_id_agenda,
    jsonb_build_object('fecha', v_fecha_ts, 'servicio', v_nombre_servicio,
                       'local', v_nombre_local, 'cantidad', v_cant, 'id_turno', p_id_turno)
  from (select 1) x
  left join flow.perfil p on p.uuid_usuario = p_uuid_usuario;

  return jsonb_build_object('ok', true,
    'data', jsonb_build_object(
      'id_agenda', v_id_agenda,
      'fecha',     to_char(v_fecha_ts, 'YYYY-MM-DD'),
      'cantidad',  v_cant,
      'id_turno',  p_id_turno
    ));
exception
  when others then
    return jsonb_build_object('ok', false, 'error', sqlerrm, 'sqlstate', sqlstate);
end;
$$;

grant execute on function flow.cliente_reservar_directo(uuid, integer, date, integer, jsonb, boolean, text, text, text, text, text, integer) to authenticated;

-- ============================================================================
-- 2) ADMIN: crear reserva directa (con p_id_turno opcional).
-- ============================================================================
create or replace function flow.admin_crear_reserva_directa(
  p_id_local_servicio integer,
  p_fecha             date,
  p_cantidad          integer default null,
  p_datos_adicionales jsonb   default null,
  p_uuid_admin        uuid    default null,
  p_id_turno          integer default null
)
returns jsonb
language plpgsql security definer set search_path = flow, public
as $$
declare
  v_cantidad_default integer;
  v_cantidad_max     integer;
  v_plan_id          bigint;
  v_disponibles      integer;
  v_estado           integer;
  v_id_agenda        integer;
  v_fecha_ts         timestamp without time zone;
  v_cant             integer;
  v_uuid_admin       uuid;
  v_es_admin         boolean;
  v_id_servicio      integer;
  v_precio_total     numeric;
  v_moneda           varchar;
  v_desc             jsonb;
begin
  v_uuid_admin := coalesce(p_uuid_admin, auth.uid());

  if v_uuid_admin is null or p_id_local_servicio is null or p_fecha is null then
    return jsonb_build_object('ok', false, 'error', 'parametros obligatorios faltantes');
  end if;

  select exists (
    select 1
    from flow.local_servicio ls
    join flow.app_dat_locales l on l.id = ls.id_local
    join flow.entidad e on e.id = l.id_entidad
    where ls.id = p_id_local_servicio
      and (
        e.owner_uuid = v_uuid_admin
        or exists (
          select 1 from flow.entidad_admin ea
          where ea.id_entidad = e.id and ea.uuid_usuario = v_uuid_admin
        )
      )
  ) into v_es_admin;

  if not v_es_admin then
    return jsonb_build_object('ok', false, 'error', 'No tienes permisos de administrador sobre este servicio');
  end if;

  perform pg_advisory_xact_lock(hashtext('flow.sala_espera'), p_id_local_servicio);

  select ls.cantidad_default, ls.cantidad_max_capacidad, ls.id_servicio
    into v_cantidad_default, v_cantidad_max, v_id_servicio
  from flow.local_servicio ls
  where ls.id = p_id_local_servicio;

  if v_cantidad_default is null then
    return jsonb_build_object('ok', false, 'error', 'El servicio no existe');
  end if;

  if p_id_turno is not null then
    if not exists (
      select 1 from flow.turno t
      join flow.recurso r on r.id = t.id_recurso and r.activo
      where t.id = p_id_turno and t.activo and r.id_local_servicio = p_id_local_servicio
    ) then
      return jsonb_build_object('ok', false, 'error', 'Turno invalido para este servicio');
    end if;
  end if;

  v_cant := coalesce(p_cantidad, v_cantidad_default, 1);
  if v_cant < 1 then
    return jsonb_build_object('ok', false, 'error', 'La cantidad debe ser al menos 1');
  end if;
  if v_cant > v_cantidad_max then
    return jsonb_build_object('ok', false, 'error',
      'La cantidad maxima por reserva es ' || v_cantidad_max);
  end if;

  select id into v_estado from flow.nom_estado_agenda where nombre = 'Reservado' limit 1;
  if v_estado is null then
    return jsonb_build_object('ok', false, 'error', 'falta el estado Reservado (correr migracion 03)');
  end if;

  v_fecha_ts := (make_timestamp(extract(year from p_fecha)::int,
                                extract(month from p_fecha)::int,
                                extract(day from p_fecha)::int, 12, 0, 0));

  if p_id_turno is not null then
    v_desc := flow._descontar_tramos_turno(p_id_turno, p_fecha, v_cant);
    if (v_desc ->> 'ok') <> 'true' then
      return jsonb_build_object('ok', false, 'error', v_desc ->> 'error');
    end if;
  else
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
  end if;

  select cp.precio_total, cp.moneda
    into v_precio_total, v_moneda
  from flow.calcular_precio_reserva(
    v_id_servicio, coalesce(p_datos_adicionales, '{}'::jsonb), null, v_cant
  ) cp;

  insert into flow.agenda
    (uuid_usuario, id_local_servicio, id_estado, fecha_hora_reserva,
     cantidad, datos_adicionales, reservado_por, precio_total, moneda, id_turno)
  values
    (v_uuid_admin, p_id_local_servicio, v_estado, v_fecha_ts,
     v_cant, p_datos_adicionales, v_uuid_admin, v_precio_total, v_moneda, p_id_turno)
  returning id into v_id_agenda;

  if p_id_turno is null then
    update flow.plan_servicios set agendados = agendados + v_cant where id = v_plan_id;
  end if;

  return jsonb_build_object('ok', true,
    'data', jsonb_build_object(
      'id_agenda', v_id_agenda,
      'fecha',     to_char(v_fecha_ts, 'YYYY-MM-DD'),
      'cantidad',  v_cant,
      'id_turno',  p_id_turno
    ));
exception
  when others then
    return jsonb_build_object('ok', false, 'error', sqlerrm, 'sqlstate', sqlstate);
end;
$$;

grant execute on function flow.admin_crear_reserva_directa(integer, date, integer, jsonb, uuid, integer) to authenticated;

-- ============================================================================
-- 3) CANCELACIONES turno-aware: al cancelar una agenda con id_turno, liberar la
--    capacidad en plan_tramo (no en plan_servicios). Se sobrescriben ambas RPCs
--    de cancelacion conservando su logica; solo cambia el paso de "liberar cupo".
--
-- Helper: libera v_cant plazas en todos los tramos del turno para la fecha.
-- ============================================================================
create or replace function flow._liberar_tramos_turno(
  p_id_turno integer,
  p_fecha    date,
  p_cant     integer
)
returns void
language sql volatile set search_path = flow, public
as $$
  update flow.plan_tramo pt
     set agendados = greatest(0, pt.agendados - p_cant)
  from flow.turno_tramo tt
  join flow.tramo tr on tr.id = tt.id_tramo
  where tt.id_turno = p_id_turno
    and pt.id_tramo = tr.id
    and (pt.fecha at time zone 'America/Havana')::date = p_fecha;
$$;

-- ── 3a) admin_cancelar_agenda (SECURITY DEFINER, valida owner/admin/dueño) ──
create or replace function flow.admin_cancelar_agenda(p_id_agenda integer)
returns json
language plpgsql security definer set search_path = flow
as $$
declare
  v_id_estado int;
  v_id_estado_reservado int;
  v_result json;
  v_agenda record;
  v_plan_id bigint;
begin
  if not exists (
    select 1
    from flow.agenda a
    join flow.local_servicio ls on ls.id = a.id_local_servicio
    join flow.app_dat_locales l on l.id = ls.id_local
    where a.id = p_id_agenda
      and (
        auth.uid() = a.uuid_usuario
        or l.id_entidad in (select id from flow.entidad where owner_uuid = auth.uid())
        or exists (
          select 1 from flow.entidad_admin ea
          where ea.id_entidad = l.id_entidad and ea.uuid_usuario = auth.uid()
        )
      )
  ) then
    raise exception 'No tiene permisos para cancelar esta reserva';
  end if;

  select a.id, a.uuid_usuario, a.id_local_servicio, a.id_estado,
         a.fecha_hora_reserva, a.cantidad, a.id_turno
    into v_agenda
    from flow.agenda a
   where a.id = p_id_agenda;

  select id into v_id_estado_reservado from flow.nom_estado_agenda where nombre = 'Reservado';

  if v_agenda.id_estado is distinct from v_id_estado_reservado then
    raise exception 'Solo se pueden cancelar reservas activas';
  end if;

  select id into v_id_estado from flow.nom_estado_agenda where nombre = 'Cancelado';
  if v_id_estado is null then
    raise exception 'Estado cancelado no encontrado';
  end if;

  update flow.agenda
     set id_estado = v_id_estado, updated_at = current_timestamp
   where id = p_id_agenda;

  -- Liberar capacidad: plan_tramo si la reserva tiene turno, si no plan_servicios.
  if v_agenda.id_turno is not null then
    perform flow._liberar_tramos_turno(
      v_agenda.id_turno,
      (v_agenda.fecha_hora_reserva at time zone 'America/Havana')::date,
      v_agenda.cantidad);
  else
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
    'id_turno', a.id_turno,
    'nom_estado_agenda', json_build_object(
      'id', nea.id, 'nombre', nea.nombre, 'descripcion', nea.descripcion
    ),
    'local_servicio', json_build_object(
      'id', ls.id,
      'id_local', ls.id_local,
      'id_servicio', ls.id_servicio,
      'permite_reserva_directa', ls.permite_reserva_directa,
      'app_dat_locales', (select row_to_json(x) from (
        select ll.id, ll.nombre, ll.direccion from flow.app_dat_locales ll where ll.id = ls.id_local) x),
      'app_dat_servicios', (select row_to_json(y) from (
        select ss.id, ss.nombre from flow.app_dat_servicios ss where ss.id = ls.id_servicio) y)
    )
  ) into v_result
  from flow.agenda a
  join flow.nom_estado_agenda nea on nea.id = a.id_estado
  join flow.local_servicio ls on ls.id = a.id_local_servicio
  where a.id = p_id_agenda;

  return v_result;
end;
$$;

-- ── 3b) cliente_cancelar_reserva (valida ventana de anticipacion) ──
create or replace function flow.cliente_cancelar_reserva(
  p_uuid_usuario uuid,
  p_id_agenda    integer
)
returns jsonb
language plpgsql security definer set search_path = flow, public
as $$
declare
  v_agenda            record;
  v_estado_reservado  integer;
  v_estado_cancelado  integer;
  v_horas_anticipacion integer;
  v_limite            timestamptz;
  v_plan_id           bigint;
  v_nombre_servicio   text;
  v_nombre_local      text;
begin
  select id into v_estado_reservado from flow.nom_estado_agenda where nombre = 'Reservado';
  select id into v_estado_cancelado from flow.nom_estado_agenda where nombre = 'Cancelado';

  select a.id, a.uuid_usuario, a.id_local_servicio, a.id_estado,
         a.fecha_hora_reserva, a.cantidad, a.reservado_por, a.id_turno
    into v_agenda
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

  select e.horas_anticipacion_cancelacion into v_horas_anticipacion
  from flow.local_servicio ls
  join flow.app_dat_locales l on l.id = ls.id_local
  join flow.entidad         e on e.id = l.id_entidad
  where ls.id = v_agenda.id_local_servicio;

  if coalesce(v_horas_anticipacion, 0) = 0 then
    return jsonb_build_object('ok', false, 'error', 'La entidad no permite cancelaciones por el cliente');
  end if;

  v_limite := v_agenda.fecha_hora_reserva - (v_horas_anticipacion || ' hours')::interval;
  if current_timestamp > v_limite then
    return jsonb_build_object('ok', false, 'error',
      'Solo puedes cancelar hasta ' || v_horas_anticipacion || ' horas antes de la reserva');
  end if;

  update flow.agenda
     set id_estado = v_estado_cancelado, updated_at = current_timestamp
   where id = p_id_agenda;

  -- Liberar capacidad segun tenga turno o no.
  if v_agenda.id_turno is not null then
    perform flow._liberar_tramos_turno(
      v_agenda.id_turno,
      (v_agenda.fecha_hora_reserva at time zone 'America/Havana')::date,
      v_agenda.cantidad);
  else
    select ps.id into v_plan_id
    from flow.plan_servicios ps
    where ps.id_local_servicio = v_agenda.id_local_servicio
      and (ps.fecha at time zone 'America/Havana')::date = (v_agenda.fecha_hora_reserva at time zone 'America/Havana')::date
    limit 1;
    if v_plan_id is not null then
      update flow.plan_servicios
         set agendados = greatest(0, agendados - v_agenda.cantidad)
       where id = v_plan_id;
    end if;
  end if;

  select s.nombre, l.nombre into v_nombre_servicio, v_nombre_local
  from flow.local_servicio ls
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  join flow.app_dat_locales   l on l.id = ls.id_local
  where ls.id = v_agenda.id_local_servicio;

  insert into flow.notificaciones
    (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
  values
    (p_uuid_usuario, 'reserva', 'Reserva cancelada',
     'Se ha cancelado tu reserva para el servicio "' || coalesce(v_nombre_servicio, 'servicio')
       || '" en "' || coalesce(v_nombre_local, 'local') || '" para el '
       || to_char(v_agenda.fecha_hora_reserva, 'DD/MM/YYYY') || '.',
     v_agenda.id_local_servicio, v_agenda.id,
     jsonb_build_object('fecha', v_agenda.fecha_hora_reserva, 'servicio', v_nombre_servicio,
                        'local', v_nombre_local, 'cantidad', v_agenda.cantidad));

  return jsonb_build_object('ok', true,
    'data', jsonb_build_object(
      'id_agenda', p_id_agenda,
      'fecha',     to_char(v_agenda.fecha_hora_reserva, 'YYYY-MM-DD')
    ));
exception
  when others then
    return jsonb_build_object('ok', false, 'error', sqlerrm, 'sqlstate', sqlstate);
end;
$$;

grant execute on function flow.cliente_cancelar_reserva(uuid, integer) to authenticated;
