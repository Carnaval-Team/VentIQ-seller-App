-- ============================================================================
-- MEJORAS DE REPORTE Y ESTADO DE RESERVAS
--
-- 1) admin_listar_agendas / vendedor_listar_agendas: exponen el turno y su
--    recurso (aditivo). Permite totalizar por recurso-turno en el panel.
--      'id_turno' : id del turno reservado (null = reserva sin turno)
--      'turno'    : { id, nombre, recurso: { id, nombre } }  (null si sin turno)
--
-- 2) staff_marcar_estado_agenda: ahora permite COMPLETAR (estado 3) una reserva
--    que estaba CANCELADA siempre que su fecha sea de hoy o anterior (tz Havana).
--    Al re-completar una cancelada se RE-CONSUME la capacidad que la cancelacion
--    habia liberado (plan_servicios, o plan_tramo si la reserva tiene turno),
--    acotado para no pasar de la capacidad total. Cancelar (estado 2) sigue
--    exigiendo que la reserva este activa (Reservado).
--
-- Todo es idempotente (create or replace). Aplicar manualmente.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1a) admin_listar_agendas
-- ----------------------------------------------------------------------------
create or replace function flow.admin_listar_agendas(
  p_uuid_usuario uuid,
  p_id_entidad integer default null,
  p_id_local integer default null,
  p_id_local_servicio integer default null,
  p_id_estado integer default null,
  p_desde timestamp without time zone default null,
  p_hasta timestamp without time zone default null
)
returns jsonb
language sql
stable security definer
set search_path to 'flow', 'public'
as $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',                  a.id,
        'uuid_usuario',        a.uuid_usuario,
        'id_estado',           a.id_estado,
        'fecha_hora_reserva',  a.fecha_hora_reserva,
        'fecha_hora_atencion', a.fecha_hora_atencion,
        'created_at',          a.created_at,
        'updated_at',          a.updated_at,
        'cantidad',            a.cantidad,
        'datos_adicionales',   a.datos_adicionales,
        'reservado_por',       a.reservado_por,
        'precio_total',        a.precio_total,
        'moneda',              a.moneda,
        'id_turno',            a.id_turno,
        'id_viaje',            a.id_viaje,
        'tipo_trayecto',       a.tipo_trayecto,
        'turno', case when t.id is null then null else jsonb_build_object(
          'id',     t.id,
          'nombre', t.nombre,
          'recurso', jsonb_build_object('id', r.id, 'nombre', r.nombre)
        ) end,
        'estado', jsonb_build_object(
          'id',          es.id,
          'nombre',      es.nombre,
          'descripcion', es.descripcion
        ),
        'id_local_servicio', ls.id,
        'servicio', jsonb_build_object(
          'id',                 s.id,
          'nombre',             s.nombre,
          'descripcion',        s.descripcion,
          'foto',               s.foto,
          'campos_adicionales', s.campos_adicionales
        ),
        'local', jsonb_build_object(
          'id',               l.id,
          'nombre',           l.nombre,
          'direccion',        l.direccion,
          'pais',             l.pais,
          'provincia',        l.provincia,
          'horario_atencion', l.horario_atencion,
          'coordenadas',      l.coordenadas,
          'foto',             l.foto
        ),
        'entidad', jsonb_build_object(
          'id',           en.id,
          'denominacion', en.denominacion,
          'direccion',    en.direccion,
          'telefono',     en.telefono
        ),
        'cliente', case when p.id is null then null else jsonb_build_object(
          'id',           p.id,
          'uuid_usuario', p.uuid_usuario,
          'nombre',       p.nombre,
          'apellidos',    p.apellidos,
          'ci',           p.ci,
          'telefono',     p.telefono,
          'created_at',   p.created_at,
          'updated_at',   p.updated_at
        ) end
      )
      order by a.fecha_hora_reserva desc
    ),
    '[]'::jsonb
  )
  from flow.agenda a
  join flow.local_servicio    ls on ls.id = a.id_local_servicio
  join flow.app_dat_locales   l  on l.id  = ls.id_local
  join flow.app_dat_servicios s  on s.id  = ls.id_servicio
  join flow.entidad           en on en.id = l.id_entidad
  join flow.nom_estado_agenda es on es.id = a.id_estado
  left join flow.perfil       p  on p.uuid_usuario = a.uuid_usuario
  left join flow.turno        t  on t.id = a.id_turno
  left join flow.recurso      r  on r.id = t.id_recurso
  join flow.admin_entidades_de_usuario(p_uuid_usuario) mine on mine.id_entidad = l.id_entidad
  where (p_id_entidad        is null or l.id_entidad         = p_id_entidad)
    and (p_id_local          is null or ls.id_local          = p_id_local)
    and (p_id_local_servicio is null or a.id_local_servicio  = p_id_local_servicio)
    and (p_id_estado         is null or a.id_estado          = p_id_estado)
    and (p_desde             is null or a.fecha_hora_reserva::date >= p_desde::date)
    and (p_hasta             is null or a.fecha_hora_reserva::date <= p_hasta::date);
$function$;

-- ----------------------------------------------------------------------------
-- 1b) vendedor_listar_agendas
-- ----------------------------------------------------------------------------
create or replace function flow.vendedor_listar_agendas(
  p_uuid_usuario uuid,
  p_id_entidad integer default null,
  p_id_local integer default null,
  p_id_local_servicio integer default null,
  p_id_estado integer default null,
  p_desde timestamp without time zone default null,
  p_hasta timestamp without time zone default null
)
returns jsonb
language sql
stable security definer
set search_path to 'flow', 'public'
as $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',                  a.id,
        'fecha_hora_reserva',  a.fecha_hora_reserva,
        'fecha_hora_atencion', a.fecha_hora_atencion,
        'created_at',          a.created_at,
        'updated_at',          a.updated_at,
        'cantidad',            a.cantidad,
        'datos_adicionales',   a.datos_adicionales,
        'reservado_por',       a.reservado_por,
        'precio_total',        a.precio_total,
        'moneda',              a.moneda,
        'id_estado',           a.id_estado,
        'id_turno',            a.id_turno,
        'id_viaje',            a.id_viaje,
        'tipo_trayecto',       a.tipo_trayecto,
        'turno', case when t.id is null then null else jsonb_build_object(
          'id',     t.id,
          'nombre', t.nombre,
          'recurso', jsonb_build_object('id', r.id, 'nombre', r.nombre)
        ) end,
        'estado', jsonb_build_object(
          'id',          es.id,
          'nombre',      es.nombre,
          'descripcion', es.descripcion
        ),
        'id_local_servicio', ls.id,
        'servicio', jsonb_build_object(
          'id',                 s.id,
          'nombre',             s.nombre,
          'descripcion',        s.descripcion,
          'foto',               s.foto,
          'campos_adicionales', s.campos_adicionales
        ),
        'local', jsonb_build_object(
          'id',               l.id,
          'nombre',           l.nombre,
          'direccion',        l.direccion,
          'pais',             l.pais,
          'provincia',        l.provincia,
          'horario_atencion', l.horario_atencion,
          'coordenadas',      l.coordenadas,
          'foto',             l.foto
        ),
        'entidad', jsonb_build_object(
          'id',           en.id,
          'denominacion', en.denominacion,
          'direccion',    en.direccion,
          'telefono',     en.telefono
        ),
        'cliente', case when p.id is null then null else jsonb_build_object(
          'id',           p.id,
          'uuid_usuario', p.uuid_usuario,
          'nombre',       p.nombre,
          'apellidos',    p.apellidos,
          'ci',           p.ci,
          'telefono',     p.telefono,
          'created_at',   p.created_at,
          'updated_at',   p.updated_at
        ) end
      )
      order by a.fecha_hora_reserva desc
    ),
    '[]'::jsonb
  )
  from flow.agenda a
  join flow.local_servicio    ls on ls.id = a.id_local_servicio
  join flow.app_dat_locales   l  on l.id  = ls.id_local
  join flow.app_dat_servicios s  on s.id  = ls.id_servicio
  join flow.entidad           en on en.id = l.id_entidad
  join flow.nom_estado_agenda es on es.id = a.id_estado
  left join flow.perfil       p  on p.uuid_usuario = a.uuid_usuario
  left join flow.turno        t  on t.id = a.id_turno
  left join flow.recurso      r  on r.id = t.id_recurso
  join flow.entidad_vendedor  ev on ev.id_entidad  = l.id_entidad
                                and ev.uuid_usuario = p_uuid_usuario
  where (p_id_entidad        is null or l.id_entidad         = p_id_entidad)
    and (p_id_local          is null or ls.id_local          = p_id_local)
    and (p_id_local_servicio is null or a.id_local_servicio  = p_id_local_servicio)
    and (p_id_estado         is null or a.id_estado          = p_id_estado)
    and (p_desde             is null or a.fecha_hora_reserva >= p_desde)
    and (p_hasta             is null or a.fecha_hora_reserva <= p_hasta);
$function$;

-- ----------------------------------------------------------------------------
-- 2) staff_marcar_estado_agenda: completar canceladas (hoy o antes) + re-consumo
-- ----------------------------------------------------------------------------
create or replace function flow.staff_marcar_estado_agenda(
  p_id_agenda integer,
  p_id_estado integer
)
returns json
language plpgsql
security definer
set search_path to 'flow', 'public'
as $function$
declare
  v_agenda        record;
  v_id_reservado  int;
  v_id_cancelado  int;
  v_plan_id       bigint;
  v_result        json;
  v_nombre_serv   text;
  v_nombre_local  text;
  v_fecha_dia     date;
  v_hoy           date;
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

  -- Cargar la reserva (incluye id_turno para re-consumir la capacidad correcta).
  select a.id, a.uuid_usuario, a.id_local_servicio, a.id_estado,
         a.fecha_hora_reserva, a.cantidad, a.id_turno
    into v_agenda
    from flow.agenda a
   where a.id = p_id_agenda;

  select id into v_id_reservado from flow.nom_estado_agenda where nombre = 'Reservado';
  select id into v_id_cancelado from flow.nom_estado_agenda where nombre = 'Cancelado';

  v_fecha_dia := (v_agenda.fecha_hora_reserva at time zone 'America/Havana')::date;
  v_hoy       := (current_timestamp at time zone 'America/Havana')::date;

  -- Reglas por transicion.
  if p_id_estado = 2 then
    -- Cancelar: solo desde activa (Reservado).
    if v_agenda.id_estado is distinct from v_id_reservado then
      raise exception 'Solo se pueden cancelar reservas activas';
    end if;
  else
    -- Completar: desde activa, o desde cancelada si la fecha es hoy o anterior.
    if v_agenda.id_estado = v_id_reservado then
      null;  -- ok
    elsif v_agenda.id_estado = v_id_cancelado then
      if v_fecha_dia > v_hoy then
        raise exception 'Solo se pueden completar reservas canceladas de hoy o fechas anteriores';
      end if;
    else
      raise exception 'Esta reserva no se puede completar en su estado actual';
    end if;
  end if;

  -- Capacidad:
  --   cancelar        -> liberar (baja agendados)
  --   completar desde
  --     cancelada     -> re-consumir (sube agendados, acotado a la capacidad)
  --     reservado     -> no toca (ya estaba consumida al reservar)
  if p_id_estado = 2 then
    if v_agenda.id_turno is not null then
      update flow.plan_tramo pt
         set agendados = greatest(0, pt.agendados - v_agenda.cantidad)
      from flow.turno_tramo tt
      join flow.tramo tr on tr.id = tt.id_tramo
      where tt.id_turno = v_agenda.id_turno
        and pt.id_tramo = tr.id
        and (pt.fecha at time zone 'America/Havana')::date = v_fecha_dia;
    else
      select ps.id into v_plan_id
        from flow.plan_servicios ps
       where ps.id_local_servicio = v_agenda.id_local_servicio
         and (ps.fecha at time zone 'America/Havana')::date = v_fecha_dia
       limit 1;
      if v_plan_id is not null then
        update flow.plan_servicios
           set agendados = greatest(0, agendados - v_agenda.cantidad)
         where id = v_plan_id;
      end if;
    end if;
  elsif p_id_estado = 3 and v_agenda.id_estado = v_id_cancelado then
    -- Re-consumir capacidad liberada por la cancelacion (acotado a cantidad total).
    if v_agenda.id_turno is not null then
      update flow.plan_tramo pt
         set agendados = least(pt.cantidad, pt.agendados + v_agenda.cantidad)
      from flow.turno_tramo tt
      join flow.tramo tr on tr.id = tt.id_tramo
      where tt.id_turno = v_agenda.id_turno
        and pt.id_tramo = tr.id
        and (pt.fecha at time zone 'America/Havana')::date = v_fecha_dia;
    else
      select ps.id into v_plan_id
        from flow.plan_servicios ps
       where ps.id_local_servicio = v_agenda.id_local_servicio
         and (ps.fecha at time zone 'America/Havana')::date = v_fecha_dia
       limit 1;
      if v_plan_id is not null then
        update flow.plan_servicios
           set agendados = least(cantidad, agendados + v_agenda.cantidad)
         where id = v_plan_id;
      end if;
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
    'id_turno', a.id_turno,
    'nom_estado_agenda', json_build_object(
      'id', nea.id, 'nombre', nea.nombre, 'descripcion', nea.descripcion
    )
  ) into v_result
  from flow.agenda a
  join flow.nom_estado_agenda nea on nea.id = a.id_estado
  where a.id = p_id_agenda;

  return v_result;
end;
$function$;
