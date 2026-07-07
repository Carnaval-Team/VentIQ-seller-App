-- ============================================================================
-- RPC ADMIN: listar los local_servicio (asignaciones servicio<->local)
-- de las entidades que administra el usuario.
-- Filtros opcionales: p_id_entidad, p_id_local.
-- Devuelve: jsonb (array con local, servicio y entidad)
-- ============================================================================

create or replace function flow.admin_listar_locales_servicios(
  p_uuid_usuario uuid,
  p_id_entidad   integer default null,
  p_id_local     integer default null
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
        'id_local_servicio', ls.id,
        'created_at',        ls.created_at,
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
          'denominacion', en.denominacion
        )
      )
      order by en.denominacion, l.nombre, s.nombre
    ),
    '[]'::jsonb
  )
  from flow.local_servicio ls
  join flow.app_dat_locales   l  on l.id  = ls.id_local
  join flow.app_dat_servicios s  on s.id  = ls.id_servicio
  join flow.entidad           en on en.id = l.id_entidad
  join flow.admin_entidades_de_usuario(p_uuid_usuario) mine on mine.id_entidad = l.id_entidad
  where (p_id_entidad is null or l.id_entidad = p_id_entidad)
    and (p_id_local   is null or ls.id_local  = p_id_local);
$$;

grant execute on function flow.admin_listar_locales_servicios(uuid, integer, integer) to authenticated;

-- Uso:
--   select flow.admin_listar_locales_servicios('00000000-...');
--   select flow.admin_listar_locales_servicios('00000000-...', 2);      -- por entidad
--   select flow.admin_listar_locales_servicios('00000000-...', null, 5);-- por local
