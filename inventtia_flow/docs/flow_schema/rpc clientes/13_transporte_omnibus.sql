create or replace function flow.cliente_obtener_disponibilidad_transporte(
  p_id_local_servicio integer,
  p_fecha date,
  p_tipo_trayecto varchar default null
)
returns jsonb
language sql
stable
security invoker
set search_path = flow, public
as $$
  with actividad as (
    select 1
    from flow.local_servicio ls
    join flow.app_dat_servicios s on s.id = ls.id_servicio
    join flow.nom_tipo_actividad_servicio ta on ta.id = s.id_tipo_actividad
    where ls.id = p_id_local_servicio
      and ta.codigo = 'transporte_omnibus'
  ), por_turno as (
    select
      t.id as id_turno,
      r.id as id_recurso,
      r.nombre as recurso,
      t.nombre as turno,
      t.precios,
      tr.tipo_trayecto,
      min(pt.cantidad) as cantidad,
      min(pt.agendados) as agendados,
      min(pt.cantidad - pt.agendados) as disponibles,
      (
        select count(*)::int
        from flow.turno_tramo tt_c
        join flow.tramo tr_c on tr_c.id = tt_c.id_tramo and tr_c.activo
        where tt_c.id_turno = t.id
      ) as num_tramos,
      exists (
        select 1
        from flow.turno_tramo tt_i
        join flow.tramo tr_i on tr_i.id = tt_i.id_tramo and tr_i.activo
        where tt_i.id_turno = t.id and tr_i.tipo_trayecto = 'ida'
      ) and exists (
        select 1
        from flow.turno_tramo tt_v
        join flow.tramo tr_v on tr_v.id = tt_v.id_tramo and tr_v.activo
        where tt_v.id_turno = t.id and tr_v.tipo_trayecto = 'vuelta'
      ) as es_combinado
    from flow.turno t
    join flow.recurso r on r.id = t.id_recurso and r.activo
    join flow.turno_tramo tt on tt.id_turno = t.id
    join flow.tramo tr on tr.id = tt.id_tramo and tr.activo
    join flow.plan_tramo pt on pt.id_tramo = tr.id
    where r.id_local_servicio = p_id_local_servicio
      and t.activo
      and (pt.fecha at time zone 'America/Havana')::date = p_fecha
      and (p_tipo_trayecto is null or tr.tipo_trayecto = p_tipo_trayecto)
    group by t.id, r.id, r.nombre, t.nombre, t.precios, tr.tipo_trayecto
    having count(*) = 1
  )
  select jsonb_build_object(
    'ok', exists(select 1 from actividad),
    'fecha', to_char(p_fecha, 'YYYY-MM-DD'),
    'turnos', coalesce(jsonb_agg(jsonb_build_object(
      'id_turno', id_turno,
      'id_recurso', id_recurso,
      'recurso', recurso,
      'turno', turno,
      'precios', precios,
      'tipo_trayecto', tipo_trayecto,
      'cantidad', cantidad,
      'agendados', agendados,
      'disponibles', disponibles,
      'num_tramos', num_tramos,
      'es_combinado', es_combinado or num_tramos > 1
    ) order by recurso, turno), '[]'::jsonb)
  )
  from por_turno;
$$;

grant execute on function flow.cliente_obtener_disponibilidad_transporte(integer, date, varchar) to authenticated, anon;

create or replace function flow.cliente_obtener_fechas_disponibles_transporte(
  p_id_local_servicio integer,
  p_tipo_trayecto varchar
)
returns jsonb
language sql
stable
security invoker
set search_path = flow, public
as $$
  select coalesce(jsonb_agg(fecha order by fecha), '[]'::jsonb)
  from (
    select distinct (pt.fecha at time zone 'America/Havana')::date as fecha
    from flow.plan_tramo pt
    join flow.tramo tr on tr.id = pt.id_tramo and tr.activo
    join flow.recurso r on r.id = tr.id_recurso and r.activo
    join flow.turno_tramo tt on tt.id_tramo = tr.id
    join flow.turno t on t.id = tt.id_turno and t.activo
    where r.id_local_servicio = p_id_local_servicio
      and tr.tipo_trayecto = p_tipo_trayecto
      and pt.cantidad > pt.agendados
      and (pt.fecha at time zone 'America/Havana')::date >= current_date
  ) fechas;
$$;

grant execute on function flow.cliente_obtener_fechas_disponibles_transporte(integer, varchar) to authenticated, anon;

drop function if exists flow.cliente_reservar_pasaje_omnibus(uuid, integer, varchar, date, integer, date, integer, integer, jsonb, text);

create or replace function flow.cliente_reservar_pasaje_omnibus(
  p_uuid_usuario uuid,
  p_id_local_servicio integer,
  p_tipo_viaje varchar,
  p_fecha_ida date default null,
  p_id_turno_ida integer default null,
  p_fecha_vuelta date default null,
  p_id_turno_vuelta integer default null,
  p_cantidad integer default 1,
  p_datos_adicionales jsonb default '{}'::jsonb,
  p_moneda text default null,
  p_para_tercero boolean default false,
  p_t_nombre text default null,
  p_t_apellidos text default null,
  p_t_ci text default null,
  p_t_telefono text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = flow, public
as $$
declare
  v_estado integer;
  v_id_viaje uuid;
  v_titular uuid;
  v_desc jsonb;
  v_precio_total numeric := 0;
  v_moneda varchar;
  v_precio_ida numeric := 0;
  v_precio_vuelta numeric := 0;
  v_id_agenda_ida integer;
  v_id_agenda_vuelta integer;
  v_id_servicio integer;
  v_es_transporte boolean;
  v_opcion_precio text;
  v_fecha_ts timestamp without time zone;
  v_misma_fecha boolean;
  v_usar_precio_combinado boolean;
  v_aplica_todos boolean;
  v_id_turno_precio integer;
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Usuario no autorizado');
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
  where ls.id = p_id_local_servicio
    and ls.permite_reserva_directa;

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

  if coalesce(p_para_tercero, false) then
    if not exists (
      select 1
      from flow.local_servicio ls
      join flow.app_dat_servicios s on s.id = ls.id_servicio
      where ls.id = p_id_local_servicio and s.permite_tercero
    ) then
      return jsonb_build_object('ok', false, 'error', 'Este servicio no permite reservar para terceros');
    end if;
    v_titular := flow._resolver_perfil_tercero(
      p_t_nombre, p_t_apellidos, p_t_ci, p_t_telefono
    );
  else
    v_titular := p_uuid_usuario;
  end if;
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

  -- Precio:
  --  * ida / vuelta: precio del turno simple.
  --  * ida_vuelta mismo día (o flag "todos"): precio del turno combinado una vez.
  --  * ida_vuelta fechas distintas sin flag: suma ida + vuelta.
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
      coalesce(p_datos_adicionales, '{}'::jsonb) || jsonb_build_object('tipo_viaje', 'ida'),
      p_moneda, p_cantidad
    );
    v_precio_ida := v_precio_total;
  elsif p_tipo_viaje = 'vuelta' then
    select precio_total, moneda into v_precio_total, v_moneda
    from flow.calcular_precio_turno(
      v_id_servicio, p_id_turno_vuelta,
      coalesce(p_datos_adicionales, '{}'::jsonb) || jsonb_build_object('tipo_viaje', 'vuelta'),
      p_moneda, p_cantidad
    );
    v_precio_vuelta := v_precio_total;
  elsif v_usar_precio_combinado then
    -- Preferir turno combinado si ida y vuelta son el mismo; si no, buscar
    -- un turno del local que cubra ida+vuelta para tomar su precio.
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
      coalesce(p_datos_adicionales, '{}'::jsonb) || jsonb_build_object('tipo_viaje', 'ida_vuelta'),
      p_moneda, p_cantidad
    );
    v_precio_ida := v_precio_total;
    v_precio_vuelta := 0;
  else
    select precio_total, moneda into v_precio_ida, v_moneda
    from flow.calcular_precio_turno(
      v_id_servicio, p_id_turno_ida,
      coalesce(p_datos_adicionales, '{}'::jsonb) || jsonb_build_object('tipo_viaje', 'ida'),
      p_moneda, p_cantidad
    );
    select precio_total, moneda into v_precio_vuelta, v_moneda
    from flow.calcular_precio_turno(
      v_id_servicio, p_id_turno_vuelta,
      coalesce(p_datos_adicionales, '{}'::jsonb) || jsonb_build_object('tipo_viaje', 'vuelta'),
      p_moneda, p_cantidad
    );
    v_precio_total := coalesce(v_precio_ida, 0) + coalesce(v_precio_vuelta, 0);
  end if;

  -- Descuento de plazas:
  --  * Mismo día + mismo turno combinado → una sola pasada (descuenta ida y vuelta).
  --  * En cualquier otro caso → descuenta cada tramo/fecha por separado.
  if p_tipo_viaje in ('ida', 'ida_vuelta') then
    if not (v_misma_fecha and p_id_turno_ida is not distinct from p_id_turno_vuelta) then
      v_desc := flow._descontar_tramos_turno(p_id_turno_ida, p_fecha_ida, p_cantidad);
      if coalesce((v_desc ->> 'ok')::boolean, false) is not true then
        return jsonb_build_object('ok', false, 'error', v_desc ->> 'error');
      end if;
    end if;
    v_fecha_ts := make_timestamp(extract(year from p_fecha_ida)::int, extract(month from p_fecha_ida)::int, extract(day from p_fecha_ida)::int, 12, 0, 0);
    insert into flow.agenda (uuid_usuario, id_local_servicio, id_estado, fecha_hora_reserva, cantidad, datos_adicionales, reservado_por, precio_total, moneda, id_turno, id_viaje, tipo_trayecto)
    values (v_titular, p_id_local_servicio, v_estado, v_fecha_ts, p_cantidad,
      coalesce(p_datos_adicionales, '{}'::jsonb) || jsonb_build_object('tipo_viaje', p_tipo_viaje),
      p_uuid_usuario, v_precio_ida, v_moneda, p_id_turno_ida, v_id_viaje, 'ida')
    returning id into v_id_agenda_ida;
  end if;

  if p_tipo_viaje in ('vuelta', 'ida_vuelta') then
    -- Si es paquete mismo día (mismo turno), aquí se descuentan ambos tramos.
    -- Si son turnos/fechas distintos, solo descuenta el tramo de vuelta.
    v_desc := flow._descontar_tramos_turno(p_id_turno_vuelta, p_fecha_vuelta, p_cantidad);
    if coalesce((v_desc ->> 'ok')::boolean, false) is not true then
      raise exception '%', coalesce(v_desc ->> 'error', 'No hay capacidad para la vuelta');
    end if;
    v_fecha_ts := make_timestamp(extract(year from p_fecha_vuelta)::int, extract(month from p_fecha_vuelta)::int, extract(day from p_fecha_vuelta)::int, 12, 0, 0);
    insert into flow.agenda (uuid_usuario, id_local_servicio, id_estado, fecha_hora_reserva, cantidad, datos_adicionales, reservado_por, precio_total, moneda, id_turno, id_viaje, tipo_trayecto)
    values (v_titular, p_id_local_servicio, v_estado, v_fecha_ts, p_cantidad,
      coalesce(p_datos_adicionales, '{}'::jsonb) || jsonb_build_object('tipo_viaje', p_tipo_viaje),
      p_uuid_usuario, v_precio_vuelta, v_moneda, p_id_turno_vuelta, v_id_viaje, 'vuelta')
    returning id into v_id_agenda_vuelta;
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

grant execute on function flow.cliente_reservar_pasaje_omnibus(uuid, integer, varchar, date, integer, date, integer, integer, jsonb, text, boolean, text, text, text, text) to authenticated;
