-- ============================================================================
-- RPC ADMIN: listar las entidades que administra el usuario (admin u owner).
-- Indica el rol con que las administra.
-- Devuelve: jsonb (array de entidades)
-- ============================================================================

create or replace function flow.admin_listar_entidades(
  p_uuid_usuario uuid
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
        'id',           en.id,
        'denominacion', en.denominacion,
        'direccion',    en.direccion,
        'telefono',     en.telefono,
        'created_at',   en.created_at,
        'updated_at',   en.updated_at,
        'es_owner',     (en.owner_uuid = p_uuid_usuario)
      )
      order by en.denominacion
    ),
    '[]'::jsonb
  )
  from flow.entidad en
  join flow.admin_entidades_de_usuario(p_uuid_usuario) mine on mine.id_entidad = en.id;
$$;

grant execute on function flow.admin_listar_entidades(uuid) to authenticated;

-- Uso:  select flow.admin_listar_entidades('00000000-...');
