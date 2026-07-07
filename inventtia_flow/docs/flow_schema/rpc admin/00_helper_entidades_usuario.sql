-- ============================================================================
-- HELPER ADMIN: entidades a las que pertenece un usuario.
-- Un usuario "administra" una entidad si:
--   - es admin asignado en flow.entidad_admin, O
--   - es el owner_uuid de la entidad.
-- Devuelve una tabla de id_entidad (para usar con IN / JOIN).
-- ============================================================================

create or replace function flow.admin_entidades_de_usuario(
  p_uuid_usuario uuid
)
returns table (id_entidad integer)
language sql
stable
security invoker
set search_path = flow, public
as $$
  select ea.id_entidad
  from flow.entidad_admin ea
  where ea.uuid_usuario = p_uuid_usuario
  union
  select e.id
  from flow.entidad e
  where e.owner_uuid = p_uuid_usuario;
$$;

grant execute on function flow.admin_entidades_de_usuario(uuid) to authenticated;
