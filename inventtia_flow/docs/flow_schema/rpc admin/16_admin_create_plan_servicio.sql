-- ============================================================================
-- RPC: flow.admin_create_plan_servicio
-- Descripción: Crea un nuevo plan de servicio
-- Autor: Sistema
-- Fecha: 2025-07-07
-- ============================================================================

-- security definer: ejecuta con permisos del propietario de la función
-- Concedida solo a authenticated.
-- Devuelve: JSON con el plan creado o error.
-- ============================================================================

create or replace function flow.admin_create_plan_servicio(
  p_id_local_servicio integer,
  p_fecha             date,
  p_cantidad          integer
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
  v_id_plan           integer;
  v_result            jsonb;
begin
  -- Obtener UUID del admin
  v_uuid_admin := auth.uid();
  
  if v_uuid_admin is null or p_id_local_servicio is null or p_cantidad is null then
    return jsonb_build_object('ok', false, 'error', 'Parámetros obligatorios faltantes');
  end if;

  if p_cantidad <= 0 then
    return jsonb_build_object('ok', false, 'error', 'La cantidad debe ser mayor a cero');
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
    return jsonb_build_object('ok', false, 'error', 'No tienes permisos para crear planes para este servicio');
  end if;

  -- Verificar que no exista un plan para la misma fecha
  if exists (
    select 1 from flow.plan_servicios 
    where id_local_servicio = p_id_local_servicio 
    and date(fecha) = p_fecha
  ) then
    return jsonb_build_object('ok', false, 'error', 'Ya existe un plan para esta fecha');
  end if;

  -- Insertar el nuevo plan de servicio
  insert into flow.plan_servicios (
    id_local_servicio,
    fecha,
    cantidad,
    agendados
  ) values (
    p_id_local_servicio,
    p_fecha,
    p_cantidad,
    0
  ) returning id into v_id_plan;

  -- Obtener el plan creado
  select jsonb_build_object(
    'id', ps.id,
    'id_local_servicio', ps.id_local_servicio,
    'fecha', ps.fecha,
    'cantidad', ps.cantidad,
    'agendados', ps.agendados,
    'created_at', ps.created_at
  ) into v_result
  from flow.plan_servicios ps
  where ps.id = v_id_plan;

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
revoke all on function flow.admin_create_plan_servicio(integer, date, integer) from public;
grant execute on function flow.admin_create_plan_servicio(integer, date, integer) to authenticated;
