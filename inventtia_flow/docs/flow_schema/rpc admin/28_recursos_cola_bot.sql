-- ============================================================================
-- RECURSOS - Fase 3: cola de espera + bot turno-aware.
--
-- Extiende la sala de espera y el bot para servicios CON recursos, sin tocar el
-- camino legacy (servicios sin recursos siguen con plan_servicios + bot_procesar_plan).
--
--   1) cliente_entrar_sala_espera: nuevo parametro p_id_turno (NULL = legacy).
--      La numeracion (numero_cola) sigue siendo GLOBAL por local_servicio; el
--      turno solo determina a que reparto pertenece el candidato. El antiduplicado
--      pasa a ser por (LS, titular, turno) para permitir esperar ida y vuelta.
--   2) bot_procesar_recurso_dia(p_id_turno, p_fecha): reparte cupo de UN turno en
--      UN dia. Cupo = min(cantidad-agendados) sobre los plan_tramo del turno ese
--      dia. Toma N candidatos FIFO (N=cupo), crea agenda con id_turno, los saca de
--      la cola, descuenta N en cada tramo del turno y notifica.
--   3) trigger en plan_tramo: al crear/subir cupo de un tramo, procesa los turnos
--      que lo usan para esa fecha (analogo a trg_plan_servicio_procesar).
--   4) bot_sweep: ahora recorre AMBOS caminos (planes legacy + turnos con cupo).
-- ============================================================================

-- ============================================================================
-- 1) ENTRAR A LA COLA con turno opcional.
-- ============================================================================
create or replace function flow.cliente_entrar_sala_espera(
  p_uuid_usuario      uuid,
  p_id_local_servicio integer,
  p_fecha_regla       timestamp without time zone default null,
  p_datos_adicionales jsonb   default null,
  p_para_tercero      boolean default false,
  p_t_nombre          text    default null,
  p_t_apellidos       text    default null,
  p_t_ci              text    default null,
  p_t_telefono        text    default null,
  p_id_turno          integer default null
)
returns jsonb
language plpgsql set search_path to 'flow', 'public'
as $function$
declare
  v_numero  integer;
  v_id      integer;
  v_fecha   timestamp without time zone;
  v_created timestamp without time zone;
  v_recientes integer;
  v_nombre_servicio text;
  v_nombre_local    text;
  v_titular uuid;
  c_flood_ventana constant interval := interval '1 minute';
  c_flood_max     constant integer  := 5;
begin
  if p_uuid_usuario is null or p_id_local_servicio is null then
    return jsonb_build_object('ok', false,
      'error', 'uuid_usuario e id_local_servicio son obligatorios');
  end if;

  perform pg_advisory_xact_lock(hashtext('flow.sala_espera'), p_id_local_servicio);

  if not exists (select 1 from flow.local_servicio ls where ls.id = p_id_local_servicio) then
    insert into flow.sala_espera_fraude (uuid_usuario, id_local_servicio, motivo, detalle)
    values (p_uuid_usuario, p_id_local_servicio, 'local_servicio_inexistente', null);
    return jsonb_build_object('ok', false, 'error', 'El id_local_servicio no existe');
  end if;

  -- Validar turno si se pide.
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

  -- ANTIFRAUDE 1: el titular no entra dos veces a la MISMA cola (LS + turno).
  if exists (
    select 1 from flow.sala_espera se
    where se.id_local_servicio = p_id_local_servicio
      and se.uuid_usuario = v_titular
      and se.id_turno is not distinct from p_id_turno
  ) then
    insert into flow.sala_espera_fraude (uuid_usuario, id_local_servicio, motivo, detalle)
    values (p_uuid_usuario, p_id_local_servicio, 'duplicado', null);
    return jsonb_build_object('ok', false, 'error',
      case when v_titular = p_uuid_usuario
           then 'El usuario ya esta en esta cola'
           else 'Esa persona ya esta en esta cola' end);
  end if;

  -- ANTIFRAUDE 2: flood / bots.
  select count(*) into v_recientes
  from flow.sala_espera_fraude f
  where f.uuid_usuario = p_uuid_usuario
    and f.created_at >= current_timestamp - c_flood_ventana;

  if v_recientes >= c_flood_max then
    insert into flow.sala_espera_fraude (uuid_usuario, id_local_servicio, motivo, detalle)
    values (p_uuid_usuario, p_id_local_servicio, 'flood',
            jsonb_build_object('intentos_ventana', v_recientes, 'ventana', c_flood_ventana::text));
    return jsonb_build_object('ok', false, 'error', 'Demasiados intentos, espera un momento');
  end if;

  -- Numeracion global por LS (independiente del turno).
  select coalesce(max(se.numero_cola), 0) into v_numero
  from flow.sala_espera se
  where se.id_local_servicio = p_id_local_servicio;

  v_numero := v_numero + 1;
  v_fecha  := coalesce(p_fecha_regla, current_timestamp);

  insert into flow.sala_espera
    (uuid_usuario, id_local_servicio, fecha_regla, numero_cola,
     datos_adicionales, reservado_por, id_turno)
  values
    (v_titular, p_id_local_servicio, v_fecha, v_numero,
     p_datos_adicionales, p_uuid_usuario, p_id_turno)
  returning id, created_at into v_id, v_created;

  insert into flow.ultimo_numero (id_local_servicio, ultimo_otorgado, ultimo_en_anotarse, updated_at)
  values (p_id_local_servicio, 0, v_numero, current_timestamp)
  on conflict (id_local_servicio) do update
    set ultimo_en_anotarse = v_numero, updated_at = current_timestamp;

  select s.nombre, l.nombre into v_nombre_servicio, v_nombre_local
  from flow.local_servicio ls
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  join flow.app_dat_locales   l on l.id = ls.id_local
  where ls.id = p_id_local_servicio;

  insert into flow.notificaciones
    (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
  values (
    p_uuid_usuario, 'sala_espera', 'Entraste en la cola',
    'Has entrado satisfactoriamente en la cola para el servicio "'
      || coalesce(v_nombre_servicio, 'servicio')
      || '" en el local "' || coalesce(v_nombre_local, 'local')
      || '" para reserva a partir del '
      || to_char(v_fecha, 'DD/MM/YYYY') || '.',
    p_id_local_servicio, v_id,
    jsonb_build_object('numero_cola', v_numero, 'fecha_regla', v_fecha,
      'servicio', v_nombre_servicio, 'local', v_nombre_local, 'id_turno', p_id_turno)
  );

  return jsonb_build_object('ok', true,
    'data', jsonb_build_object(
      'id', v_id, 'uuid_usuario', p_uuid_usuario,
      'id_local_servicio', p_id_local_servicio, 'fecha_regla', v_fecha,
      'numero_cola', v_numero, 'ultimo_en_anotarse', v_numero,
      'created_at', v_created, 'id_turno', p_id_turno));
end;
$function$;

grant execute on function flow.cliente_entrar_sala_espera(uuid, integer, timestamp without time zone, jsonb, boolean, text, text, text, text, integer) to authenticated, anon;

-- ============================================================================
-- 2) BOT: repartir cupo de un turno en un dia.
-- ============================================================================
create or replace function flow.bot_procesar_recurso_dia(
  p_id_turno integer,
  p_fecha    date
)
returns jsonb
language plpgsql security definer set search_path to 'flow', 'public'
as $function$
declare
  v_ls              integer;
  v_id_servicio     integer;
  v_estado          integer;
  v_cupo            integer;
  v_n_tramos        integer;
  v_n_plan          integer;
  v_movidos         integer := 0;
  v_fecha_ts        timestamp without time zone;
  v_nombre_servicio text;
  v_nombre_local    text;
  v_saludo          text;
begin
  -- Recurso/LS del turno.
  select r.id_local_servicio into v_ls
  from flow.turno t
  join flow.recurso r on r.id = t.id_recurso and r.activo
  where t.id = p_id_turno and t.activo;

  if v_ls is null then
    return jsonb_build_object('ok', true, 'movidos', 0, 'motivo', 'turno inactivo');
  end if;

  perform pg_advisory_xact_lock(hashtext('flow.sala_espera'), v_ls);

  select id into v_estado from flow.nom_estado_agenda where nombre = 'Reservado' limit 1;
  if v_estado is null then
    return jsonb_build_object('ok', false, 'error', 'falta el estado Reservado');
  end if;

  -- Cuantos tramos consume el turno.
  select count(*) into v_n_tramos from flow.turno_tramo tt where tt.id_turno = p_id_turno;
  if coalesce(v_n_tramos, 0) = 0 then
    return jsonb_build_object('ok', true, 'movidos', 0, 'motivo', 'turno sin tramos');
  end if;

  -- Cupo del turno ese dia = min(disponible) sobre sus tramos; bloquea plan_tramo.
  create temporary table if not exists _tmp_bot_pt (id bigint) on commit drop;
  delete from _tmp_bot_pt;

  insert into _tmp_bot_pt (id)
  select pt.id
  from flow.turno_tramo tt
  join flow.tramo tr      on tr.id = tt.id_tramo and tr.activo
  join flow.plan_tramo pt on pt.id_tramo = tr.id
  where tt.id_turno = p_id_turno
    and (pt.fecha at time zone 'America/Havana')::date = p_fecha
  for update of pt;

  select count(*), coalesce(min(pt.cantidad - pt.agendados), 0)
    into v_n_plan, v_cupo
  from flow.plan_tramo pt
  join _tmp_bot_pt tmp on tmp.id = pt.id;

  -- Todos los tramos del turno deben tener plan ese dia y quedar cupo.
  if coalesce(v_n_plan, 0) < v_n_tramos or v_cupo <= 0 then
    return jsonb_build_object('ok', true, 'movidos', 0, 'motivo', 'sin cupo');
  end if;

  v_fecha_ts := (make_timestamp(extract(year from p_fecha)::int,
                                extract(month from p_fecha)::int,
                                extract(day from p_fecha)::int, 12, 0, 0));

  select s.nombre, l.nombre, ls.id_servicio
    into v_nombre_servicio, v_nombre_local, v_id_servicio
  from flow.local_servicio ls
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  join flow.app_dat_locales   l on l.id = ls.id_local
  where ls.id = v_ls;

  v_saludo := case
    when extract(hour from current_timestamp) between 5 and 11 then 'Buenos dias'
    when extract(hour from current_timestamp) between 12 and 18 then 'Buenas tardes'
    else 'Buenas noches'
  end;

  -- Reparto set-based: N candidatos FIFO de la cola de ESTE turno (N=cupo).
  -- Cada turno consume 1 plaza de cada tramo, por eso caben exactamente v_cupo.
  with candidatos as (
    select se.id, se.uuid_usuario, se.datos_adicionales, se.reservado_por
    from flow.sala_espera se
    where se.id_local_servicio = v_ls
      and se.id_turno = p_id_turno
      and se.fecha_regla::date <= p_fecha
    order by se.numero_cola
    limit v_cupo
    for update skip locked
  ),
  insertados as (
    insert into flow.agenda
      (uuid_usuario, id_local_servicio, id_estado, fecha_hora_reserva,
       cantidad, datos_adicionales, reservado_por, precio_total, moneda, id_turno)
    select c.uuid_usuario, v_ls, v_estado, v_fecha_ts,
           1, c.datos_adicionales, c.reservado_por,
           cp.precio_total, cp.moneda, p_id_turno
    from candidatos c
    cross join lateral flow.calcular_precio_reserva(
      v_id_servicio, coalesce(c.datos_adicionales, '{}'::jsonb), null, 1) cp
    returning uuid_usuario, id, fecha_hora_reserva
  ),
  borrados as (
    delete from flow.sala_espera se
    using candidatos c
    where se.id = c.id
      and se.uuid_usuario in (select uuid_usuario from insertados)
    returning se.id
  ),
  notificados as (
    insert into flow.notificaciones
      (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
    select
      i.uuid_usuario, 'reserva', 'Reservacion confirmada',
      v_saludo || ', '
        || coalesce(nullif(trim(p.nombre || ' ' || p.apellidos), ''), 'estimado cliente')
        || ', se ha realizado satisfactoriamente su reservacion para el local "'
        || coalesce(v_nombre_local, 'local') || '" el servicio "'
        || coalesce(v_nombre_servicio, 'servicio') || '" para la fecha '
        || to_char(i.fecha_hora_reserva, 'DD/MM/YYYY') || '.',
      v_ls, i.id,
      jsonb_build_object('fecha', i.fecha_hora_reserva, 'servicio', v_nombre_servicio,
        'local', v_nombre_local, 'id_turno', p_id_turno)
    from insertados i
    left join flow.perfil p on p.uuid_usuario = i.uuid_usuario
    returning 1
  )
  select count(*) into v_movidos from insertados;

  if v_movidos > 0 then
    -- Descontar el cupo en cada tramo del turno.
    update flow.plan_tramo pt
       set agendados = pt.agendados + v_movidos
    from _tmp_bot_pt tmp
    where pt.id = tmp.id;

    -- Recompactar la cola del LS (numeracion global 1..N por orden de llegada).
    with reord as (
      select se.id, row_number() over (order by se.numero_cola) as rn
      from flow.sala_espera se
      where se.id_local_servicio = v_ls
    )
    update flow.sala_espera se
       set numero_cola = r.rn
      from reord r
     where se.id = r.id and se.numero_cola <> r.rn;
  end if;

  insert into flow.bot_log (id_plan, id_local_servicio, resultado, movidos, mensaje, detalle)
  values (null, v_ls,
    case when v_movidos > 0 then 'ok' else 'sin_movimiento' end,
    v_movidos,
    case when v_movidos > 0 then 'repartio ' || v_movidos || ' agenda(s) turno'
         else 'sin candidatos en cola de turno' end,
    jsonb_build_object('id_turno', p_id_turno, 'fecha', p_fecha, 'cupo', v_cupo));

  return jsonb_build_object('ok', true, 'id_turno', p_id_turno,
    'id_local_servicio', v_ls, 'movidos', v_movidos);
exception
  when others then
    insert into flow.bot_log (id_plan, id_local_servicio, resultado, movidos, mensaje, detalle)
    values (null, v_ls, 'error', 0, sqlerrm,
            jsonb_build_object('id_turno', p_id_turno, 'sqlstate', sqlstate));
    return jsonb_build_object('ok', false, 'id_turno', p_id_turno,
      'error', sqlerrm, 'sqlstate', sqlstate);
end;
$function$;

-- ============================================================================
-- 3) TRIGGER en plan_tramo: al crear/subir cupo, procesa los turnos del tramo.
-- ============================================================================
create or replace function flow.trg_plan_tramo_procesar()
returns trigger
language plpgsql security definer set search_path to 'flow', 'public'
as $function$
declare
  v_turno record;
  v_fecha date;
begin
  if new.cantidad is null or new.agendados >= new.cantidad then
    return null;
  end if;

  v_fecha := (new.fecha at time zone 'America/Havana')::date;

  -- Cada turno activo que USA este tramo puede tener candidatos esperando.
  for v_turno in
    select distinct t.id
    from flow.turno_tramo tt
    join flow.turno t on t.id = tt.id_turno and t.activo
    where tt.id_tramo = new.id_tramo
  loop
    perform flow.bot_procesar_recurso_dia(v_turno.id, v_fecha);
  end loop;

  return null;
end;
$function$;

-- Dispara solo al crear el plan o al SUBIR la capacidad (cantidad), NO sobre
-- 'agendados': el propio bot decrementa cupo actualizando agendados y no debe
-- re-dispararse (mismo criterio que trg_plan_servicio_procesar en el legacy).
-- Una sola pasada del bot reparte todo el cupo disponible (set-based).
drop trigger if exists trg_plan_tramo_aiu on flow.plan_tramo;
create trigger trg_plan_tramo_aiu
  after insert or update of cantidad on flow.plan_tramo
  for each row execute function flow.trg_plan_tramo_procesar();

-- ============================================================================
-- 4) BOT_SWEEP: recorre planes legacy Y turnos con cupo pendiente.
-- ============================================================================
create or replace function flow.bot_sweep()
returns jsonb
language plpgsql security definer set search_path to 'flow', 'public'
as $function$
declare
  r        record;
  v_total  integer := 0;
  v_planes integer := 0;
  v_turnos integer := 0;
begin
  -- (a) Camino legacy: plan_servicios con cupo.
  for r in
    select ps.id
    from flow.plan_servicios ps
    where ps.cantidad is not null
      and ps.agendados < ps.cantidad
      and ps.id_local_servicio is not null
    order by ps.fecha
  loop
    v_planes := v_planes + 1;
    v_total  := v_total + coalesce((flow.bot_procesar_plan(r.id) ->> 'movidos')::int, 0);
  end loop;

  -- (b) Camino recursos: (turno, dia) con cupo pendiente en TODOS sus tramos.
  --     Solo procesa turnos cuyos tramos tienen plan_tramo con disponible > 0.
  for r in
    select tt.id_turno,
           (pt.fecha at time zone 'America/Havana')::date as dia
    from flow.turno t
    join flow.recurso r2      on r2.id = t.id_recurso and r2.activo
    join flow.turno_tramo tt  on tt.id_turno = t.id
    join flow.tramo tr        on tr.id = tt.id_tramo and tr.activo
    join flow.plan_tramo pt   on pt.id_tramo = tr.id
    where t.activo
      and pt.agendados < pt.cantidad
    group by tt.id_turno, (pt.fecha at time zone 'America/Havana')::date
    order by (pt.fecha at time zone 'America/Havana')::date
  loop
    v_turnos := v_turnos + 1;
    v_total  := v_total + coalesce(
      (flow.bot_procesar_recurso_dia(r.id_turno, r.dia) ->> 'movidos')::int, 0);
  end loop;

  return jsonb_build_object('ok', true,
    'planes_revisados', v_planes, 'turnos_revisados', v_turnos, 'agendas_creadas', v_total);
end;
$function$;

grant execute on function flow.bot_procesar_recurso_dia(integer, date) to authenticated;
grant execute on function flow.bot_sweep() to authenticated;
