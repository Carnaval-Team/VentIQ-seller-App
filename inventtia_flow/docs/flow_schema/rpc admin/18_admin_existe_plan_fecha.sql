-- ============================================================================
-- RPC: flow.admin_existe_plan_fecha
-- Descripción: Verifica si existe un plan para un local-servicio en una fecha específica
-- Autor: Sistema
-- Fecha: 2025-07-07
-- ============================================================================

-- security definer: ejecuta con permisos del propietario de la función
-- Concedida solo a authenticated.
-- Devuelve: JSON con booleano indicando si existe el plan o error.
-- ============================================================================

create or replace function flow.admin_existe_plan_fecha(
  p_id_local_servicio integer,
  p_fecha             date,
  p_exclude_id        integer default null
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
  v_existe            boolean;
begin
  -- Obtener UUID del admin
  v_uuid_admin := auth.uid();
  
  if v_uuid_admin is null or p_id_local_servicio is null or p_fecha is null then
    return jsonb_build_object('ok', false, 'error', 'Parámetros obligatorios faltantes');
  end if;

  -- Verificar que el usuario es admin o owner de la entidad dueña del servicio
  select exists (
    select 1
    from flow.local_servicio ls
    join flow.app_dat_locales l on l.id = ls.id_local
    join flow.app_dat_entidades e on e.id = l.id_entidad
    where ls.id = p_id_local_servicio
    and (
      e.id_owner = v_uuid_admin
      or exists (
        select 1 from flow.app_dat_entidades_admins a
        where a.id_entidad = e.id and a.uuid_admin = v_uuid_admin
      )
    )
  ) into v_es_admin;

  if not v_es_admin then
    return jsonb_build_object('ok', false, 'error', 'No tienes permisos para verificar planes de este servicio');
  end if;

  -- Verificar si existe un plan para la fecha
  if p_exclude_id is not null then
    select exists (
      select 1 from flow.plan_servicios 
      where id_local_servicio = p_id_local_servicio 
      and date(fecha) = p_fecha
      and id != p_exclude_id
    ) into v_existe;
  else
    select exists (
      select 1 from flow.plan_servicios 
      where id_local_servicio = p_id_local_servicio 
      and date(fecha) = p_fecha
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
revoke all on function flow.admin_existe_plan_fecha(integer, date, integer) from public;
grant execute on function flow.admin_existe_plan_fecha(integer, date, integer) to authenticated;
