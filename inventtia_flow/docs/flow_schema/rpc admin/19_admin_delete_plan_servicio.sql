-- ============================================================================
-- RPC: flow.admin_delete_plan_servicio
-- Descripción: Elimina un plan de servicio existente
-- Autor: Sistema
-- Fecha: 2025-07-07
-- ============================================================================

-- security definer: ejecuta con permisos del propietario de la función
-- Concedida solo a authenticated.
-- Devuelve: JSON con éxito o error.
-- ============================================================================

create or replace function flow.admin_delete_plan_servicio(
  p_id integer
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = flow, public
as $$
declare
  v_uuid_admin        uuid;
  v_es_admin          boolean;
  v_agendados_actuales integer;
begin
  -- Obtener UUID del admin
  v_uuid_admin := auth.uid();
  
  if v_uuid_admin is null or p_id is null then
    return jsonb_build_object('ok', false, 'error', 'Parámetros obligatorios faltantes');
  end if;

  -- Verificar que el plan existe y obtener los agendados actuales
  select ps.agendados into v_agendados_actuales
  from flow.plan_servicios ps
  where ps.id = p_id;

  if v_agendados_actuales is null then
    return jsonb_build_object('ok', false, 'error', 'Plan de servicio no encontrado');
  end if;

  if v_agendados_actuales > 0 then
    return jsonb_build_object('ok', false, 'error', 'No se puede eliminar un plan con agendados activos (' || v_agendados_actuales || ')');
  end if;

  -- Verificar que el usuario es admin o owner de la entidad dueña del servicio
  select exists (
    select 1
    from flow.plan_servicios ps
    join flow.local_servicio ls on ls.id = ps.id_local_servicio
    join flow.app_dat_locales l on l.id = ls.id_local
    join flow.app_dat_entidades e on e.id = l.id_entidad
    where ps.id = p_id
    and (
      e.id_owner = v_uuid_admin
      or exists (
        select 1 from flow.app_dat_entidades_admins a
        where a.id_entidad = e.id and a.uuid_admin = v_uuid_admin
      )
    )
  ) into v_es_admin;

  if not v_es_admin then
    return jsonb_build_object('ok', false, 'error', 'No tienes permisos para eliminar este plan');
  end if;

  -- Eliminar el plan de servicio
  delete from flow.plan_servicios where id = p_id;

  return jsonb_build_object(
    'ok', true,
    'message', 'Plan eliminado exitosamente'
  );

exception
  when others then
    return jsonb_build_object('ok', false, 'error', sqlerrm, 'sqlstate', sqlstate);
end;
$$;

-- Permisos
revoke all on function flow.admin_delete_plan_servicio(integer) from public;
grant execute on function flow.admin_delete_plan_servicio(integer) to authenticated;
