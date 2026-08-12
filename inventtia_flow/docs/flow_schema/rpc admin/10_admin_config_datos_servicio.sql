-- ============================================================================
-- RPC ADMIN: guardar datos adicionales, terceros y configuración de precio.
-- ============================================================================

drop function if exists flow.admin_guardar_datos_servicio(uuid, integer, jsonb, boolean);

create or replace function flow.admin_guardar_datos_servicio(
  p_uuid_usuario    uuid,
  p_id_servicio     integer,
  p_campos          jsonb,
  p_permite_tercero boolean,
  p_config_precio   jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = flow, public
as $$
declare
  v_campos jsonb;
  v_tercero boolean;
  v_precio jsonb;
begin
  if p_uuid_usuario is null or p_id_servicio is null then
    return jsonb_build_object('ok', false, 'error', 'parametros obligatorios faltantes');
  end if;

  update flow.app_dat_servicios s
     set campos_adicionales = coalesce(p_campos, '[]'::jsonb),
         permite_tercero    = coalesce(p_permite_tercero, false),
         config_precio      = coalesce(p_config_precio, '{}'::jsonb),
         updated_at         = current_timestamp
   where s.id = p_id_servicio
     and s.id_entidad in (
       select id_entidad from flow.admin_entidades_de_usuario(p_uuid_usuario)
     )
  returning s.campos_adicionales, s.permite_tercero, s.config_precio
    into v_campos, v_tercero, v_precio;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'servicio inexistente o sin permiso');
  end if;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id_servicio',        p_id_servicio,
      'campos_adicionales', v_campos,
      'permite_tercero',    v_tercero,
      'config_precio',      v_precio
    )
  );
end;
$$;

grant execute on function flow.admin_guardar_datos_servicio(uuid, integer, jsonb, boolean, jsonb) to authenticated;
