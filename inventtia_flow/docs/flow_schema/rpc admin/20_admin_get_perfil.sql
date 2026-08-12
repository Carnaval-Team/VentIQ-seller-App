-- ============================================================================
-- RPC: flow.admin_get_perfil
-- Descripción: Obtiene el perfil de un usuario por UUID
-- Autor: Sistema
-- Fecha: 2025-07-07
-- ============================================================================

-- security definer: ejecuta con permisos del propietario de la función
-- Concedida solo a authenticated.
-- Devuelve: JSON con perfil o error.
-- ============================================================================

create or replace function flow.admin_get_perfil(
  p_uuid_usuario uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = flow, public
as $$
declare
  v_uuid_solicitante  uuid;
  v_result            jsonb;
begin
  -- Obtener UUID del solicitante
  v_uuid_solicitante := auth.uid();
  
  if v_uuid_solicitante is null or p_uuid_usuario is null then
    return jsonb_build_object('ok', false, 'error', 'Parámetros obligatorios faltantes');
  end if;

  -- Solo el propio usuario puede ver su perfil
  if v_uuid_solicitante != p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'No tienes permisos para ver este perfil');
  end if;

  -- Obtener el perfil
  select jsonb_build_object(
    'id', p.id,
    'uuid_usuario', p.uuid_usuario,
    'nombre', p.nombre,
    'apellidos', p.apellidos,
    'ci', p.ci,
    'telefono', p.telefono,
    'created_at', p.created_at,
    'updated_at', p.updated_at
  ) into v_result
  from flow.perfil p
  where p.uuid_usuario = p_uuid_usuario;

  if v_result is null then
    return jsonb_build_object('ok', true, 'data', null);
  end if;

  return jsonb_build_object(
    'ok', true,
    'data', v_result
  );

exception
  when others then
    return jsonb_build_object('ok', false, 'error', sqlerrm, 'sqlstate', sqlstate);
end;
$$;

-- Permisos
revoke all on function flow.admin_get_perfil(uuid) from public;
grant execute on function flow.admin_get_perfil(uuid) to authenticated;
