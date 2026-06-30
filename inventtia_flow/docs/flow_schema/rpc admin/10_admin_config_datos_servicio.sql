-- ============================================================================
-- RPC ADMIN: guardar los datos adicionales + flag de terceros de un servicio.
--
-- Configura, a nivel de servicio (app_dat_servicios, catalogo de la entidad):
--   - campos_adicionales (jsonb array): que datos extra pedir al reservar.
--   - permite_tercero (bool): si se puede reservar a nombre de otra persona.
--
-- security invoker -> respeta la politica servicios_update_admin existente
-- (flow.is_entidad_admin sobre id_entidad). Ademas validamos pertenencia con el
-- helper para devolver un error claro si no corresponde.
-- Devuelve: { ok, data } | { ok:false, error }.
-- ============================================================================

create or replace function flow.admin_guardar_datos_servicio(
  p_uuid_usuario    uuid,
  p_id_servicio     integer,
  p_campos          jsonb,
  p_permite_tercero boolean
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
begin
  if p_uuid_usuario is null or p_id_servicio is null then
    return jsonb_build_object('ok', false, 'error', 'parametros obligatorios faltantes');
  end if;

  update flow.app_dat_servicios s
     set campos_adicionales = coalesce(p_campos, '[]'::jsonb),
         permite_tercero    = coalesce(p_permite_tercero, false),
         updated_at         = current_timestamp
   where s.id = p_id_servicio
     and s.id_entidad in (
       select id_entidad from flow.admin_entidades_de_usuario(p_uuid_usuario)
     )
  returning s.campos_adicionales, s.permite_tercero into v_campos, v_tercero;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'servicio inexistente o sin permiso');
  end if;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id_servicio',        p_id_servicio,
      'campos_adicionales', v_campos,
      'permite_tercero',    v_tercero
    )
  );
end;
$$;

grant execute on function flow.admin_guardar_datos_servicio(uuid, integer, jsonb, boolean) to authenticated;

-- Uso:
--   select flow.admin_guardar_datos_servicio('00000000-...', 2,
--     '[{"clave":"codigo_pais","etiqueta":"Código de país","tipo":"numero","requerido":true,"min":2,"max":2},
--       {"clave":"estado_civil","etiqueta":"Estado civil","tipo":"select","requerido":true,"opciones":["Casado","Viudo","Soltero"]}]'::jsonb,
--     true);
