-- ============================================================================
-- Admin: reservar pasaje ómnibus (misma lógica de precio/cupo que el cliente).
-- No exige permite_reserva_directa. Guarda datos del pasajero en datos_adicionales
-- y deja uuid_usuario/reservado_por = admin (como admin_crear_reserva_directa).
-- ============================================================================

create or replace function flow.admin_reservar_pasaje_omnibus(
  p_uuid_admin uuid,
  p_id_local_servicio integer,
  p_tipo_viaje varchar,
  p_fecha_ida date default null,
  p_id_turno_ida integer default null,
  p_fecha_vuelta date default null,
  p_id_turno_vuelta integer default null,
  p_cantidad integer default 1,
  p_datos_adicionales jsonb default '{}'::jsonb,
  p_moneda text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = flow, public
as $$
declare
  v_uuid_admin uuid;
  v_es_admin boolean;
  v_estado integer;
  v_id_viaje uuid;
  v_desc jsonb;
  v_precio_total numeric := 0;
  v_moneda varchar;
  v_precio_ida numeric := 0;
  v_precio_vuelta numeric := 0;
  v_id_agenda_ida integer;
  v_id_agenda_vuelta integer;
  v_id_servicio integer;
  v_es_transporte boolean;
  v_fecha_ts timestamp without time zone;
  v_misma_fecha boolean;
  v_usar_precio_combinado boolean;
  v_aplica_todos boolean;
  v_id_turno_precio integer;
  v_datos jsonb;
begin
  v_uuid_admin := coalesce(p_uuid_admin, auth.uid());
  if v_uuid_admin is null then
    return jsonb_build_object('ok', false, 'error', 'Usuario no autenticado');
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
        or exists (
          select 1 from flow.entidad_vendedor ev
          where ev.id_entidad = e.id and ev.uuid_usuario = v_uuid_admin
        )
      )
  ) into v_es_admin;

  if not coalesce(v_es_admin, false) then
    return jsonb_build_object('ok', false, 'error', 'No tienes permisos sobre este servicio');
  end if;

  if p_tipo_viaje not in ('ida', 'vuelta', 'ida_vuelta') then
    return jsonb_build_object('ok', false, 'error', 'Tipo de viaje inválido');
  end if;
  if coalesce(p_cantidad, 0) < 1 then
    return jsonb_build_object('ok', false, 'error', 'La cantidad debe ser al menos 1');
  end if;
  if (p_tipo_viaje in ('ida', 'ida_vuelta') and (p_fecha_ida is null or p_id_turno_ida is null))
     or (p_tipo_viaje in ('vuelta', 'ida_vuelta') and (p_fecha_vuelta is null or p_id_turno_vuelta is null)) then
    return jsonb_build_object('ok', false, 'error', 'Faltan fecha o vehículo para uno de los trayectos');
  end if;

  select ls.id_servicio,
         ta.codigo = 'transporte_omnibus',
         coalesce((s.config_precio->>'aplica_precio_ida_vuelta_todos')::boolean, false)
    into v_id_servicio, v_es_transporte, v_aplica_todos
  from flow.local_servicio ls
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  join flow.nom_tipo_actividad_servicio ta on ta.id = s.id_tipo_actividad
  where ls.id = p_id_local_servicio;

  if coalesce(v_es_transporte, false) is not true then
    return jsonb_build_object('ok', false, 'error', 'El servicio no admite reserva de pasajes');
  end if;

  perform pg_advisory_xact_lock(hashtext('flow.sala_espera'), p_id_local_servicio);

  select id into v_estado
  from flow.nom_estado_agenda
  where lower(nombre) = 'reservado'
  limit 1;
  if v_estado is null then
    return jsonb_build_object('ok', false, 'error', 'No existe el estado Reservado');
  end if;

  v_datos := coalesce(p_datos_adicionales, '{}'::jsonb) || jsonb_build_object('tipo_viaje', p_tipo_viaje);
  v_id_viaje := case when p_tipo_viaje = 'ida_vuelta' then gen_random_uuid() else null end;

  if p_tipo_viaje in ('ida', 'ida_vuelta') and not exists (
    select 1
    from flow.turno t
    join flow.recurso r on r.id = t.id_recurso and r.activo
    join flow.turno_tramo tt on tt.id_turno = t.id
    join flow.tramo tr on tr.id = tt.id_tramo and tr.activo
    where t.id = p_id_turno_ida and t.activo
      and r.id_local_servicio = p_id_local_servicio
      and tr.tipo_trayecto = 'ida'
    group by t.id
    having count(*) = 1
  ) then
    return jsonb_build_object('ok', false, 'error', 'El vehículo de ida no es válido');
  end if;

  if p_tipo_viaje in ('vuelta', 'ida_vuelta') and not exists (
    select 1
    from flow.turno t
    join flow.recurso r on r.id = t.id_recurso and r.activo
    join flow.turno_tramo tt on tt.id_turno = t.id
    join flow.tramo tr on tr.id = tt.id_tramo and tr.activo
    where t.id = p_id_turno_vuelta and t.activo
      and r.id_local_servicio = p_id_local_servicio
      and tr.tipo_trayecto = 'vuelta'
    group by t.id
    having count(*) = 1
  ) then
    return jsonb_build_object('ok', false, 'error', 'El vehículo de vuelta no es válido');
  end if;

  v_misma_fecha := p_tipo_viaje = 'ida_vuelta'
    and p_fecha_ida is not null
    and p_fecha_vuelta is not null
    and p_fecha_ida = p_fecha_vuelta;
  v_usar_precio_combinado := p_tipo_viaje = 'ida_vuelta'
    and (v_misma_fecha or v_aplica_todos);

  if p_tipo_viaje = 'ida' then
    select precio_total, moneda into v_precio_total, v_moneda
    from flow.calcular_precio_turno(
      v_id_servicio, p_id_turno_ida,
      v_datos || jsonb_build_object('tipo_viaje', 'ida'),
      p_moneda, p_cantidad
    );
    v_precio_ida := v_precio_total;
  elsif p_tipo_viaje = 'vuelta' then
    select precio_total, moneda into v_precio_total, v_moneda
    from flow.calcular_precio_turno(
      v_id_servicio, p_id_turno_vuelta,
      v_datos || jsonb_build_object('tipo_viaje', 'vuelta'),
      p_moneda, p_cantidad
    );
    v_precio_vuelta := v_precio_total;
  elsif v_usar_precio_combinado then
    if p_id_turno_ida is not distinct from p_id_turno_vuelta then
      v_id_turno_precio := p_id_turno_ida;
    else
      select t.id into v_id_turno_precio
      from flow.turno t
      join flow.recurso r on r.id = t.id_recurso and r.activo
      where r.id_local_servicio = p_id_local_servicio
        and t.activo
        and exists (
          select 1 from flow.turno_tramo tt
          join flow.tramo tr on tr.id = tt.id_tramo and tr.activo
          where tt.id_turno = t.id and tr.tipo_trayecto = 'ida'
        )
        and exists (
          select 1 from flow.turno_tramo tt
          join flow.tramo tr on tr.id = tt.id_tramo and tr.activo
          where tt.id_turno = t.id and tr.tipo_trayecto = 'vuelta'
        )
      order by case when coalesce(t.precios, '{}'::jsonb) <> '{}'::jsonb then 0 else 1 end, t.id
      limit 1;
      v_id_turno_precio := coalesce(v_id_turno_precio, p_id_turno_ida);
    end if;

    select precio_total, moneda into v_precio_total, v_moneda
    from flow.calcular_precio_turno(
      v_id_servicio, v_id_turno_precio,
      v_datos || jsonb_build_object('tipo_viaje', 'ida_vuelta'),
      p_moneda, p_cantidad
    );
    v_precio_ida := v_precio_total;
    v_precio_vuelta := 0;
  else
    select precio_total, moneda into v_precio_ida, v_moneda
    from flow.calcular_precio_turno(
      v_id_servicio, p_id_turno_ida,
      v_datos || jsonb_build_object('tipo_viaje', 'ida'),
      p_moneda, p_cantidad
    );
    select precio_total, moneda into v_precio_vuelta, v_moneda
    from flow.calcular_precio_turno(
      v_id_servicio, p_id_turno_vuelta,
      v_datos || jsonb_build_object('tipo_viaje', 'vuelta'),
      p_moneda, p_cantidad
    );
    v_precio_total := coalesce(v_precio_ida, 0) + coalesce(v_precio_vuelta, 0);
  end if;

  if p_tipo_viaje in ('ida', 'ida_vuelta') then
    if not (v_misma_fecha and p_id_turno_ida is not distinct from p_id_turno_vuelta) then
      v_desc := flow._descontar_tramos_turno(p_id_turno_ida, p_fecha_ida, p_cantidad);
      if coalesce((v_desc ->> 'ok')::boolean, false) is not true then
        return jsonb_build_object('ok', false, 'error', v_desc ->> 'error');
      end if;
    end if;
    v_fecha_ts := make_timestamp(
      extract(year from p_fecha_ida)::int,
      extract(month from p_fecha_ida)::int,
      extract(day from p_fecha_ida)::int, 12, 0, 0);
    insert into flow.agenda (
      uuid_usuario, id_local_servicio, id_estado, fecha_hora_reserva, cantidad,
      datos_adicionales, reservado_por, precio_total, moneda, id_turno, id_viaje, tipo_trayecto
    ) values (
      v_uuid_admin, p_id_local_servicio, v_estado, v_fecha_ts, p_cantidad,
      v_datos, v_uuid_admin, v_precio_ida, v_moneda, p_id_turno_ida, v_id_viaje, 'ida'
    ) returning id into v_id_agenda_ida;
  end if;

  if p_tipo_viaje in ('vuelta', 'ida_vuelta') then
    v_desc := flow._descontar_tramos_turno(p_id_turno_vuelta, p_fecha_vuelta, p_cantidad);
    if coalesce((v_desc ->> 'ok')::boolean, false) is not true then
      raise exception '%', coalesce(v_desc ->> 'error', 'No hay capacidad para la vuelta');
    end if;
    v_fecha_ts := make_timestamp(
      extract(year from p_fecha_vuelta)::int,
      extract(month from p_fecha_vuelta)::int,
      extract(day from p_fecha_vuelta)::int, 12, 0, 0);
    insert into flow.agenda (
      uuid_usuario, id_local_servicio, id_estado, fecha_hora_reserva, cantidad,
      datos_adicionales, reservado_por, precio_total, moneda, id_turno, id_viaje, tipo_trayecto
    ) values (
      v_uuid_admin, p_id_local_servicio, v_estado, v_fecha_ts, p_cantidad,
      v_datos, v_uuid_admin, v_precio_vuelta, v_moneda, p_id_turno_vuelta, v_id_viaje, 'vuelta'
    ) returning id into v_id_agenda_vuelta;
  end if;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'id_viaje', v_id_viaje,
    'id_agenda_ida', v_id_agenda_ida,
    'id_agenda_vuelta', v_id_agenda_vuelta,
    'precio_total', v_precio_total,
    'moneda', v_moneda
  ));
exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm, 'sqlstate', sqlstate);
end;
$$;

grant execute on function flow.admin_reservar_pasaje_omnibus(
  uuid, integer, varchar, date, integer, date, integer, integer, jsonb, text
) to authenticated;
