-- ============================================================================
-- RPC CLIENTES: salir de la sala de espera de un servicio
--
-- Logica (cola compacta, sin huecos):
--   1. Advisory lock por id_local_servicio (igual que al entrar).
--   2. Se elimina al usuario y se obtiene su numero_cola.
--   3. A todos los que estaban DETRAS (numero_cola mayor) se les resta 1,
--      asi la cola queda numerada 1..N sin huecos.
--
-- Parametros obligatorios: p_uuid_usuario, p_id_local_servicio
-- Devuelve: jsonb con resultado.
-- ============================================================================

create or replace function flow.cliente_salir_sala_espera(
  p_uuid_usuario      uuid,
  p_id_local_servicio integer
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = flow, public
as $$
declare
  v_numero    integer;
  v_afectados integer;
begin
  if p_uuid_usuario is null or p_id_local_servicio is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'uuid_usuario e id_local_servicio son obligatorios'
    );
  end if;

  -- Mismo lock que entrar: serializa las operaciones de este servicio
  perform pg_advisory_xact_lock(hashtext('flow.sala_espera'), p_id_local_servicio);

  -- Elimina al usuario y captura su numero (un solo paso)
  delete from flow.sala_espera se
  where se.id_local_servicio = p_id_local_servicio
    and se.uuid_usuario = p_uuid_usuario
  returning se.numero_cola into v_numero;

  if v_numero is null then
    return jsonb_build_object('ok', false, 'error', 'El usuario no estaba en esta cola');
  end if;

  -- Compacta la cola: todos los de atras suben un puesto.
  -- Usa el indice (id_local_servicio, numero_cola) -> index scan, no seq scan.
  update flow.sala_espera se
     set numero_cola = se.numero_cola - 1
   where se.id_local_servicio = p_id_local_servicio
     and se.numero_cola > v_numero;

  get diagnostics v_afectados = row_count;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id_local_servicio',    p_id_local_servicio,
      'numero_liberado',      v_numero,
      'reordenados',          v_afectados   -- cuantos subieron un puesto
    )
  );
end;
$$;

grant execute on function flow.cliente_salir_sala_espera(uuid, integer) to authenticated;

-- Uso:
--   select flow.cliente_salir_sala_espera('00000000-0000-0000-0000-000000000000', 5);
