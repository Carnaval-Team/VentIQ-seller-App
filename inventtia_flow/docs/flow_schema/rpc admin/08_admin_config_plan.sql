-- ============================================================================
-- RPC ADMIN: guardar / obtener la configuracion RECURRENTE de un local_servicio
-- (capacidades por dia de la semana). Persiste en flow.plan_config.
--
-- Formato esperado de p_config (jsonb):
--   { "default": 30, "por_dia": { "1": 50, "4": 60 } }   -- dia ISO 1=lunes..7=domingo
--
-- Ambas validan pertenencia con flow.admin_entidades_de_usuario.
-- security invoker -> respeta RLS de plan_config.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) GUARDAR (upsert por id_local_servicio)
-- ----------------------------------------------------------------------------
create or replace function flow.admin_guardar_config_plan(
  p_uuid_usuario      uuid,
  p_id_local_servicio integer,
  p_config            jsonb,
  p_activo            boolean default true
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = flow, public
as $$
declare
  v_ok boolean;
  v_row flow.plan_config;
begin
  if p_uuid_usuario is null or p_id_local_servicio is null or p_config is null then
    return jsonb_build_object('ok', false, 'error', 'parametros obligatorios faltantes');
  end if;

  -- Validar pertenencia (la RLS tambien protege, pero damos un error claro)
  select exists (
    select 1
    from flow.local_servicio  ls
    join flow.app_dat_locales l on l.id = ls.id_local
    where ls.id = p_id_local_servicio
      and l.id_entidad in (
        select id_entidad from flow.admin_entidades_de_usuario(p_uuid_usuario)
      )
  ) into v_ok;

  if not v_ok then
    return jsonb_build_object('ok', false, 'error', 'local_servicio inexistente o sin permiso');
  end if;

  insert into flow.plan_config (id_local_servicio, config, activo, updated_at)
  values (p_id_local_servicio, p_config, coalesce(p_activo, true), now())
  on conflict (id_local_servicio) do update
    set config     = excluded.config,
        activo     = excluded.activo,
        updated_at = now()
  returning * into v_row;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id',                v_row.id,
      'id_local_servicio', v_row.id_local_servicio,
      'config',            v_row.config,
      'activo',            v_row.activo,
      'updated_at',        v_row.updated_at
    )
  );
end;
$$;

grant execute on function flow.admin_guardar_config_plan(uuid, integer, jsonb, boolean) to authenticated;


-- ----------------------------------------------------------------------------
-- 2) OBTENER (la config guardada, o null si no hay)
-- ----------------------------------------------------------------------------
create or replace function flow.admin_obtener_config_plan(
  p_uuid_usuario      uuid,
  p_id_local_servicio integer
)
returns jsonb
language sql
stable
security invoker
set search_path = flow, public
as $$
  select case when pc.id is null then null else jsonb_build_object(
           'id',                pc.id,
           'id_local_servicio', pc.id_local_servicio,
           'config',            pc.config,
           'activo',            pc.activo,
           'updated_at',        pc.updated_at
         ) end
  from flow.plan_config pc
  join flow.local_servicio  ls on ls.id = pc.id_local_servicio
  join flow.app_dat_locales l  on l.id  = ls.id_local
  where pc.id_local_servicio = p_id_local_servicio
    and l.id_entidad in (
      select id_entidad from flow.admin_entidades_de_usuario(p_uuid_usuario)
    );
$$;

grant execute on function flow.admin_obtener_config_plan(uuid, integer) to authenticated;

-- Uso:
--   select flow.admin_guardar_config_plan('00000000-...', 7,
--            '{"default":30,"por_dia":{"1":50,"4":60}}'::jsonb);
--   select flow.admin_obtener_config_plan('00000000-...', 7);
