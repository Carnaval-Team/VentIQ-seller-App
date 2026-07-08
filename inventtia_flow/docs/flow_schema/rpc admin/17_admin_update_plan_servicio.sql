-- ============================================================================
-- RPC: flow.admin_update_plan_servicio
-- Descripción: Actualiza un plan de servicio existente
-- Autor: Sistema
-- Fecha: 2025-07-07
-- ============================================================================

-- security definer: ejecuta con permisos del propietario de la función
-- Concedida solo a authenticated.
-- Devuelve: JSON con el plan actualizado o error.
-- ============================================================================

create or replace function flow.admin_update_plan_servicio(
  p_id        integer,
  p_fecha     date,
  p_cantidad  integer
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
  v_agendados_actuales integer;
begin
  -- Obtener UUID del admin
  v_uuid_admin := auth.uid();
  
  if v_uuid_admin is null or p_id is null or p_cantidad is null then
    return jsonb_build_object('ok', false, 'error', 'Parámetros obligatorios faltantes');
  end if;

  if p_cantidad <= 0 then
    return jsonb_build_object('ok', false, 'error', 'La cantidad debe ser mayor a cero');
  end if;

  -- Verificar que el plan existe y obtener los agendados actuales
  select ps.agendados into v_agendados_actuales
  from flow.plan_servicios ps
  where ps.id = p_id;

  if v_agendados_actuales is null then
    return jsonb_build_object('ok', false, 'error', 'Plan de servicio no encontrado');
  end if;

  if p_cantidad < v_agendados_actuales then
    return jsonb_build_object('ok', false, 'error', 'No se puede reducir la cantidad por debajo de los agendados actuales (' || v_agendados_actuales || ')');
  end if;

  -- Verificar que el usuario es admin o owner de la entidad dueña del servicio
  select exists (
    select 1
    from flow.plan_servicios ps
    join flow.local_servicio ls on ls.id = ps.id_local_servicio
    join flow.app_dat_locales l on l.id = ls.id_local
    join flow.entidad e on e.id = l.id_entidad
    where ps.id = p_id
    and (
      e.owner_uuid = v_uuid_admin
      or exists (
        select 1 from flow.entidad_admin a
        where a.id_entidad = e.id and a.uuid_usuario = v_uuid_admin
      )
    )
  ) into v_es_admin;

  if not v_es_admin then
    return jsonb_build_object('ok', false, 'error', 'No tienes permisos para actualizar este plan');
  end if;

  -- Verificar que no exista otro plan para la misma fecha (excluyendo este)
  if exists (
    select 1 from flow.plan_servicios 
    where id_local_servicio = (select id_local_servicio from flow.plan_servicios where id = p_id)
    and date(fecha) = p_fecha
    and id != p_id
  ) then
    return jsonb_build_object('ok', false, 'error', 'Ya existe otro plan para esta fecha');
  end if;

  -- Actualizar el plan de servicio
  update flow.plan_servicios
  set 
    fecha = p_fecha,
    cantidad = p_cantidad
  where id = p_id;

  -- Obtener el plan actualizado
  select jsonb_build_object(
    'id', ps.id,
    'id_local_servicio', ps.id_local_servicio,
    'fecha', ps.fecha,
    'cantidad', ps.cantidad,
    'agendados', ps.agendados,
    'created_at', ps.created_at
  ) into v_result
  from flow.plan_servicios ps
  where ps.id = p_id;

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
revoke all on function flow.admin_update_plan_servicio(integer, date, integer) from public;
grant execute on function flow.admin_update_plan_servicio(integer, date, integer) to authenticated;
