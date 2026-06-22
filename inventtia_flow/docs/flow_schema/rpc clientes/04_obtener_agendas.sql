-- ============================================================================
-- RPC CLIENTES: obtener las agendas (reservas) de un usuario
-- Join: flow.agenda + flow.local_servicio + flow.app_dat_locales
--       + flow.app_dat_servicios + flow.nom_estado_agenda
-- Filtros opcionales: p_id_estado (null = todos los estados)
-- Devuelve: jsonb (array de reservas del usuario con su estado)
-- ============================================================================

create or replace function flow.cliente_obtener_agendas(
  p_uuid_usuario uuid,
  p_id_estado    integer default null
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
        'id',                   a.id,
        'fecha_hora_reserva',   a.fecha_hora_reserva,
        'fecha_hora_atencion',  a.fecha_hora_atencion,
        'created_at',           a.created_at,
        'updated_at',           a.updated_at,
        'estado', jsonb_build_object(
          'id',          e.id,
          'nombre',      e.nombre,
          'descripcion', e.descripcion
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
        )
      )
      order by a.fecha_hora_reserva desc
    ),
    '[]'::jsonb
  )
  from flow.agenda a
  join flow.local_servicio    ls on ls.id = a.id_local_servicio
  join flow.app_dat_locales   l  on l.id  = ls.id_local
  join flow.app_dat_servicios s  on s.id  = ls.id_servicio
  join flow.nom_estado_agenda e  on e.id  = a.id_estado
  where a.uuid_usuario = p_uuid_usuario
    and (p_id_estado is null or a.id_estado = p_id_estado);
$$;

grant execute on function flow.cliente_obtener_agendas(uuid, integer) to authenticated;

-- Uso:
--   select flow.cliente_obtener_agendas('00000000-0000-0000-0000-000000000000');       -- todas
--   select flow.cliente_obtener_agendas('00000000-0000-0000-0000-000000000000', 2);    -- por estado
