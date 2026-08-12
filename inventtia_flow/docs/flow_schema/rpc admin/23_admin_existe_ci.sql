-- ============================================================================
-- RPC: flow.admin_existe_ci
-- Descripción: Verifica si existe un carnet de identidad en la base de datos
-- Autor: Sistema
-- Fecha: 2025-07-07
-- ============================================================================

-- security definer: ejecuta con permisos del propietario de la función
-- Concedida solo a authenticated.
-- Devuelve: JSON con booleano indicando si existe el CI o error.
-- ============================================================================

create or replace function flow.admin_existe_ci(
  p_ci          text,
  p_exclude_uuid uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = flow, public
as $$
declare
  v_uuid_solicitante  uuid;
  v_existe            boolean;
begin
  -- Obtener UUID del solicitante
  v_uuid_solicitante := auth.uid();
  
  if v_uuid_solicitante is null or p_ci is null then
    return jsonb_build_object('ok', false, 'error', 'Parámetros obligatorios faltantes');
  end if;

  -- Verificar si existe el CI
  if p_exclude_uuid is not null then
    select exists (
      select 1 from flow.perfil 
      where ci = trim(p_ci)
      and uuid_usuario != p_exclude_uuid
    ) into v_existe;
  else
    select exists (
      select 1 from flow.perfil 
      where ci = trim(p_ci)
    ) into v_existe;
  end if;

  return jsonb_build_object(
    'ok', true,
    'existe', v_existe
  );

exception
  when others then
    return jsonb_build_object('ok', false, 'error', sqlerrm, 'sqlstate', sqlstate);
end;
$$;

-- Permisos
revoke all on function flow.admin_existe_ci(text, uuid) from public;
grant execute on function flow.admin_existe_ci(text, uuid) to authenticated;
