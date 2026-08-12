-- ============================================================================
-- RPC: flow.admin_create_perfil
-- Descripción: Crea un nuevo perfil de usuario
-- Autor: Sistema
-- Fecha: 2025-07-07
-- ============================================================================

-- security definer: ejecuta con permisos del propietario de la función
-- Concedida solo a authenticated.
-- Devuelve: JSON con perfil creado o error.
-- ============================================================================

create or replace function flow.admin_create_perfil(
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
begin
  -- Obtener UUID del solicitante
  v_uuid_solicitante := auth.uid();
  
  if v_uuid_solicitante is null or p_uuid_usuario is null or p_nombre is null or p_apellidos is null or p_ci is null then
    return jsonb_build_object('ok', false, 'error', 'Parámetros obligatorios faltantes');
  end if;

  -- Solo el propio usuario puede crear su perfil
  if v_uuid_solicitante != p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'No tienes permisos para crear este perfil');
  end if;

  -- Verificar que no exista ya un perfil para este usuario
  if exists (select 1 from flow.perfil where uuid_usuario = p_uuid_usuario) then
    return jsonb_build_object('ok', false, 'error', 'Ya existe un perfil para este usuario');
  end if;

  -- Verificar que el CI no esté duplicado
  select exists (select 1 from flow.perfil where ci = p_ci) into v_existe_ci;
  if v_existe_ci then
    return jsonb_build_object('ok', false, 'error', 'El carnet de identidad ya está registrado');
  end if;

  -- Insertar el nuevo perfil
  insert into flow.perfil (
    uuid_usuario,
    nombre,
    apellidos,
    ci,
    telefono,
    created_at,
    updated_at
  ) values (
    p_uuid_usuario,
    trim(p_nombre),
    trim(p_apellidos),
    trim(p_ci),
    p_telefono,
    now(),
    now()
  ) returning id into v_result;

  -- Obtener el perfil creado
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
revoke all on function flow.admin_create_perfil(uuid, text, text, text, text) from public;
grant execute on function flow.admin_create_perfil(uuid, text, text, text, text) to authenticated;
