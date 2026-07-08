-- ============================================================================
-- RPC: flow.admin_get_plan_servicios
-- Descripción: Obtiene los planes de servicio para un local_servicio específico
-- Autor: Sistema
-- Fecha: 2025-07-07
-- ============================================================================

-- security definer: ejecuta con permisos del propietario de la función
-- Concedida solo a authenticated.
-- Devuelve: JSON con array de planes o error.
-- ============================================================================

create or replace function flow.admin_get_plan_servicios(
  p_id_local_servicio integer
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
  v_result            jsonb;
begin
  -- Obtener UUID del admin
  v_uuid_admin := auth.uid();
  
  if v_uuid_admin is null or p_id_local_servicio is null then
    return jsonb_build_object('ok', false, 'error', 'Parámetros obligatorios faltantes');
  end if;

  -- Verificar que el usuario es admin o owner de la entidad dueña del servicio
  select exists (
    select 1
    from flow.local_servicio ls
    join flow.app_dat_locales l on l.id = ls.id_local
    join flow.entidad e on e.id = l.id_entidad
    where ls.id = p_id_local_servicio
    and (
      e.owner_uuid = v_uuid_admin
      or exists (
        select 1 from flow.entidad_admin a
        where a.id_entidad = e.id and a.uuid_usuario = v_uuid_admin
      )
    )
  ) into v_es_admin;

  if not v_es_admin then
    return jsonb_build_object('ok', false, 'error', 'No tienes permisos para ver los planes de este servicio');
  end if;

  -- Obtener los planes de servicio
  select jsonb_agg(
    jsonb_build_object(
      'id', ps.id,
      'id_local_servicio', ps.id_local_servicio,
      'fecha', ps.fecha,
      'cantidad', ps.cantidad,
      'agendados', ps.agendados,
      'created_at', ps.created_at
    ) order by ps.fecha
  ) into v_result
  from flow.plan_servicios ps
  where ps.id_local_servicio = p_id_local_servicio;

  if v_result is null then
    v_result := '[]'::jsonb;
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
revoke all on function flow.admin_get_plan_servicios(integer) from public;
grant execute on function flow.admin_get_plan_servicios(integer) to authenticated;
