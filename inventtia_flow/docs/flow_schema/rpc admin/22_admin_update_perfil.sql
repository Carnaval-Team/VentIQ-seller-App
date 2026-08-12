-- ============================================================================
-- RPC: flow.admin_update_perfil
-- Descripción: Actualiza un perfil de usuario existente
-- Autor: Sistema
-- Fecha: 2025-07-07
-- ============================================================================

-- security definer: ejecuta con permisos del propietario de la función
-- Concedida solo a authenticated.
-- Devuelve: JSON con perfil actualizado o error.
-- ============================================================================

create or replace function flow.admin_update_perfil(
  p_uuid_usuario uuid,
  p_nombre        text,
  p_apellidos     text,
  p_ci            text,
  p_telefono      text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = flow, public
as $$
declare
  v_uuid_solicitante  uuid;
  v_result            jsonb;
  v_existe_ci         boolean;
  v_ci_actual         text;
begin
  -- Obtener UUID del solicitante
  v_uuid_solicitante := auth.uid();
  
  if v_uuid_solicitante is null or p_uuid_usuario is null or p_nombre is null or p_apellidos is null or p_ci is null then
    return jsonb_build_object('ok', false, 'error', 'Parámetros obligatorios faltantes');
  end if;

  -- Solo el propio usuario puede actualizar su perfil
  if v_uuid_solicitante != p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'No tienes permisos para actualizar este perfil');
  end if;

  -- Verificar que exista el perfil
  select ci into v_ci_actual from flow.perfil where uuid_usuario = p_uuid_usuario;
  if v_ci_actual is null then
    return jsonb_build_object('ok', false, 'error', 'Perfil no encontrado');
  end if;

  -- Si el CI cambia, verificar que no esté duplicado
  if v_ci_actual != p_ci then
    select exists (select 1 from flow.perfil where ci = p_ci and uuid_usuario != p_uuid_usuario) into v_existe_ci;
    if v_existe_ci then
      return jsonb_build_object('ok', false, 'error', 'El carnet de identidad ya está registrado por otro usuario');
    end if;
  end if;

  -- Actualizar el perfil
  update flow.perfil
  set 
    nombre = trim(p_nombre),
    apellidos = trim(p_apellidos),
    ci = trim(p_ci),
    telefono = p_telefono,
    updated_at = now()
  where uuid_usuario = p_uuid_usuario;

  -- Obtener el perfil actualizado
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
revoke all on function flow.admin_update_perfil(uuid, text, text, text, text) from public;
grant execute on function flow.admin_update_perfil(uuid, text, text, text, text) to authenticated;
