-- ============================================================================
-- RPC ADMIN: habilitar/deshabilitar la RESERVA DIRECTA de un local_servicio.
--
-- Solo el admin/owner de la entidad dueña del local puede cambiarlo. La
-- pertenencia se valida con flow.admin_entidades_de_usuario (mismo patron que
-- el resto de RPC admin: no hay fuga entre entidades aunque manden otro id).
-- Devuelve: jsonb accion { ok, data | error }.
-- ============================================================================

create or replace function flow.admin_set_reserva_directa(
  p_uuid_usuario      uuid,
  p_id_local_servicio integer,
  p_permite           boolean
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = flow, public
as $$
declare
  v_permite boolean;
begin
  if p_uuid_usuario is null or p_id_local_servicio is null or p_permite is null then
    return jsonb_build_object('ok', false, 'error', 'parametros obligatorios faltantes');
  end if;

  update flow.local_servicio ls
     set permite_reserva_directa = p_permite
    from flow.app_dat_locales l
   where ls.id = p_id_local_servicio
     and l.id = ls.id_local
     and l.id_entidad in (
       select id_entidad from flow.admin_entidades_de_usuario(p_uuid_usuario)
     )
  returning ls.permite_reserva_directa into v_permite;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'local_servicio inexistente o sin permiso'
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id_local_servicio',       p_id_local_servicio,
      'permite_reserva_directa', v_permite
    )
  );
end;
$$;

grant execute on function flow.admin_set_reserva_directa(uuid, integer, boolean) to authenticated;

-- Uso:
--   select flow.admin_set_reserva_directa('00000000-...', 7, true);
--   select flow.admin_set_reserva_directa('00000000-...', 7, false);
