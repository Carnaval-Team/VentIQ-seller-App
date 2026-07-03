-- RPCs para listar administradores y vendedores de una entidad incluyendo
-- el correo electrónico de auth.users. Se ejecutan con SECURITY DEFINER
-- para poder leer auth.users desde el rol authenticated.

CREATE OR REPLACE FUNCTION flow.admin_listar_admins(p_id_entidad integer)
RETURNS TABLE (
  id int,
  id_entidad int,
  uuid_usuario uuid,
  asignado_por uuid,
  created_at timestamp without time zone,
  email text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = flow, auth
AS $$
  SELECT ea.id, ea.id_entidad, ea.uuid_usuario, ea.asignado_por, ea.created_at, u.email::text
  FROM flow.entidad_admin ea
  JOIN auth.users u ON u.id = ea.uuid_usuario
  WHERE ea.id_entidad = p_id_entidad
  ORDER BY ea.created_at;
$$;

CREATE OR REPLACE FUNCTION flow.admin_listar_vendedores(p_id_entidad integer)
RETURNS TABLE (
  id int,
  id_entidad int,
  uuid_usuario uuid,
  asignado_por uuid,
  created_at timestamp without time zone,
  email text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = flow, auth
AS $$
  SELECT ev.id, ev.id_entidad, ev.uuid_usuario, ev.asignado_por, ev.created_at, u.email::text
  FROM flow.entidad_vendedor ev
  JOIN auth.users u ON u.id = ev.uuid_usuario
  WHERE ev.id_entidad = p_id_entidad
  ORDER BY ev.created_at;
$$;

GRANT EXECUTE ON FUNCTION flow.admin_listar_admins(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION flow.admin_listar_vendedores(integer) TO authenticated;
