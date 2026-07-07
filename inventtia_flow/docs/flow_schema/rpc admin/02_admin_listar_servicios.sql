-- ============================================================================
-- RPC ADMIN: listar servicios (catalogo) de las entidades del usuario.
-- Filtro opcional p_id_entidad.
-- Devuelve: jsonb (array de servicios con su entidad)
-- ============================================================================

create or replace function flow.admin_listar_servicios(
  p_uuid_usuario uuid,
  p_id_entidad   integer default null
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
        'id',          s.id,
        'nombre',      s.nombre,
        'descripcion', s.descripcion,
        'foto',        s.foto,
        'created_at',  s.created_at,
        'updated_at',  s.updated_at,
        'entidad', jsonb_build_object(
          'id',           en.id,
          'denominacion', en.denominacion
        )
      )
      order by en.denominacion, s.nombre
    ),
    '[]'::jsonb
  )
  from flow.app_dat_servicios s
  join flow.entidad en on en.id = s.id_entidad
  join flow.admin_entidades_de_usuario(p_uuid_usuario) mine on mine.id_entidad = s.id_entidad
  where (p_id_entidad is null or s.id_entidad = p_id_entidad);
$$;

grant execute on function flow.admin_listar_servicios(uuid, integer) to authenticated;

-- Uso:
--   select flow.admin_listar_servicios('00000000-...');
--   select flow.admin_listar_servicios('00000000-...', 2);
