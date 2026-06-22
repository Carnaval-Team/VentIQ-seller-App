-- ============================================================================
-- RPC ADMIN: listar agendas (reservas) de las entidades del usuario admin.
-- Join completo: agenda -> local_servicio -> local -> servicio -> entidad
--                agenda -> nom_estado_agenda
--                agenda.uuid_usuario -> perfil (TODOS los datos del cliente)
-- Filtros opcionales: p_id_entidad, p_id_local, p_id_local_servicio,
--                     p_id_estado, p_desde, p_hasta (rango de fecha_hora_reserva)
-- Devuelve: jsonb (array de reservas)
-- ============================================================================

create or replace function flow.admin_listar_agendas(
  p_uuid_usuario        uuid,
  p_id_entidad          integer default null,
  p_id_local            integer default null,
  p_id_local_servicio   integer default null,
  p_id_estado           integer default null,
  p_desde               timestamp without time zone default null,
  p_hasta               timestamp without time zone default null
)
returns jsonb
language sql
stable
security invoker
set search_path = flow, public
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',                  a.id,
        'fecha_hora_reserva',  a.fecha_hora_reserva,
        'fecha_hora_atencion', a.fecha_hora_atencion,
        'created_at',          a.created_at,
        'updated_at',          a.updated_at,
        'estado', jsonb_build_object(
          'id',          es.id,
          'nombre',      es.nombre,
          'descripcion', es.descripcion
        ),
        'id_local_servicio', ls.id,
        'servicio', jsonb_build_object(
          'id',          s.id,
          'nombre',      s.nombre,
          'descripcion', s.descripcion,
          'foto',        s.foto
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
        -- Perfil completo del cliente que reservo
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
  -- Seguridad: solo agendas de locales de entidades que administra el usuario
  join flow.admin_entidades_de_usuario(p_uuid_usuario) mine on mine.id_entidad = l.id_entidad
  where (p_id_entidad        is null or l.id_entidad         = p_id_entidad)
    and (p_id_local          is null or ls.id_local          = p_id_local)
    and (p_id_local_servicio is null or a.id_local_servicio  = p_id_local_servicio)
    and (p_id_estado         is null or a.id_estado          = p_id_estado)
    and (p_desde             is null or a.fecha_hora_reserva >= p_desde)
    and (p_hasta             is null or a.fecha_hora_reserva <= p_hasta);
$$;

grant execute on function flow.admin_listar_agendas(uuid, integer, integer, integer, integer, timestamp without time zone, timestamp without time zone) to authenticated;

-- Uso:
--   select flow.admin_listar_agendas('00000000-...');                    -- todas sus agendas
--   select flow.admin_listar_agendas('00000000-...', 2);                 -- por entidad
--   select flow.admin_listar_agendas('00000000-...', null, null, 7);     -- por local_servicio
--   select flow.admin_listar_agendas('00000000-...', null, null, null, 1,
--            '2026-06-01', '2026-06-30');                                 -- estado + rango fechas
