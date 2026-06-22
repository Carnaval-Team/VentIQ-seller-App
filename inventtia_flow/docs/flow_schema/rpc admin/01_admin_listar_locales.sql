-- ============================================================================
-- RPC ADMIN: listar locales de las entidades que administra el usuario.
-- Filtro opcional p_id_entidad: si se pasa, debe estar dentro de sus entidades.
-- Devuelve: jsonb (array de locales con su entidad)
-- ============================================================================

create or replace function flow.admin_listar_locales(
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
        'id',                  l.id,
        'nombre',              l.nombre,
        'descripcion',         l.descripcion,
        'horario_atencion',    l.horario_atencion,
        'terminos_condiciones',l.terminos_condiciones,
        'coordenadas',         l.coordenadas,
        'direccion',           l.direccion,
        'pais',                l.pais,
        'provincia',           l.provincia,
        'foto',                l.foto,
        'created_at',          l.created_at,
        'updated_at',          l.updated_at,
        'entidad', jsonb_build_object(
          'id',           en.id,
          'denominacion', en.denominacion,
          'direccion',    en.direccion,
          'telefono',     en.telefono
        )
      )
      order by en.denominacion, l.nombre
    ),
    '[]'::jsonb
  )
  from flow.app_dat_locales l
  join flow.entidad en on en.id = l.id_entidad
  -- Solo entidades del usuario
  join flow.admin_entidades_de_usuario(p_uuid_usuario) mine on mine.id_entidad = l.id_entidad
  where (p_id_entidad is null or l.id_entidad = p_id_entidad);
$$;

grant execute on function flow.admin_listar_locales(uuid, integer) to authenticated;

-- Uso:
--   select flow.admin_listar_locales('00000000-...');       -- todos los de sus entidades
--   select flow.admin_listar_locales('00000000-...', 2);    -- de una entidad suya
