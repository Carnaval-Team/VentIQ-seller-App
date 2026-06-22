-- ============================================================================
-- RPC CLIENTES: entrar en la sala de espera de un servicio
--
-- Logica:
--   1. Se serializan SOLO las entradas del mismo id_local_servicio con un
--      advisory lock transaccional (no bloquea la tabla, RAM despreciable).
--   2. Se busca el ultimo numero_cola dado en ese servicio.
--   3. Se inserta con numero_cola = ultimo + 1.
--
-- Parametros obligatorios: p_uuid_usuario, p_id_local_servicio
-- p_fecha_regla es opcional (default = ahora).
-- Devuelve: jsonb con el registro creado o un error controlado.
-- ============================================================================

create or replace function flow.cliente_entrar_sala_espera(
  p_uuid_usuario      uuid,
  p_id_local_servicio integer,
  p_fecha_regla       timestamp without time zone default null
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = flow, public
as $$
declare
  v_numero  integer;
  v_id      integer;
  v_fecha   timestamp without time zone;
  v_created timestamp without time zone;
  v_recientes integer;
  -- Antifraude: no mas de N entradas (a cualquier cola) por ventana de tiempo
  c_flood_ventana constant interval := interval '1 minute';
  c_flood_max     constant integer  := 5;
begin
  -- Validacion de obligatorios
  if p_uuid_usuario is null or p_id_local_servicio is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'uuid_usuario e id_local_servicio son obligatorios'
    );
  end if;

  -- Serializa solo las operaciones de ESTE servicio (se libera al commit/rollback)
  perform pg_advisory_xact_lock(hashtext('flow.sala_espera'), p_id_local_servicio);

  -- Validar que el local_servicio existe (evita error feo de FK)
  if not exists (select 1 from flow.local_servicio ls where ls.id = p_id_local_servicio) then
    insert into flow.sala_espera_fraude (uuid_usuario, id_local_servicio, motivo, detalle)
    values (p_uuid_usuario, p_id_local_servicio, 'local_servicio_inexistente', null);
    return jsonb_build_object('ok', false, 'error', 'El id_local_servicio no existe');
  end if;

  -- ANTIFRAUDE 1: mismo usuario no entra dos veces a la misma cola
  if exists (
    select 1 from flow.sala_espera se
    where se.id_local_servicio = p_id_local_servicio
      and se.uuid_usuario = p_uuid_usuario
  ) then
    insert into flow.sala_espera_fraude (uuid_usuario, id_local_servicio, motivo, detalle)
    values (p_uuid_usuario, p_id_local_servicio, 'duplicado', null);
    return jsonb_build_object('ok', false, 'error', 'El usuario ya esta en esta cola');
  end if;

  -- ANTIFRAUDE 2: flood / bots. Demasiadas entradas en poco tiempo.
  -- Cuenta los intentos recientes registrados como entradas exitosas + fraudes.
  select count(*) into v_recientes
  from flow.sala_espera_fraude f
  where f.uuid_usuario = p_uuid_usuario
    and f.created_at >= current_timestamp - c_flood_ventana;

  if v_recientes >= c_flood_max then
    insert into flow.sala_espera_fraude (uuid_usuario, id_local_servicio, motivo, detalle)
    values (p_uuid_usuario, p_id_local_servicio, 'flood',
            jsonb_build_object('intentos_ventana', v_recientes, 'ventana', c_flood_ventana::text));
    return jsonb_build_object('ok', false, 'error', 'Demasiados intentos, espera un momento');
  end if;

  -- Ultimo numero otorgado en este servicio (0 si la cola esta vacia)
  select coalesce(max(se.numero_cola), 0)
    into v_numero
  from flow.sala_espera se
  where se.id_local_servicio = p_id_local_servicio;

  v_numero := v_numero + 1;
  v_fecha  := coalesce(p_fecha_regla, current_timestamp);

  insert into flow.sala_espera (uuid_usuario, id_local_servicio, fecha_regla, numero_cola)
  values (p_uuid_usuario, p_id_local_servicio, v_fecha, v_numero)
  returning id, created_at into v_id, v_created;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id',                v_id,
      'uuid_usuario',      p_uuid_usuario,
      'id_local_servicio', p_id_local_servicio,
      'fecha_regla',       v_fecha,
      'numero_cola',       v_numero,
      'created_at',        v_created
    )
  );
end;
$$;

grant execute on function flow.cliente_entrar_sala_espera(uuid, integer, timestamp without time zone) to authenticated;

-- Uso:
--   select flow.cliente_entrar_sala_espera('00000000-0000-0000-0000-000000000000', 5);
--   select flow.cliente_entrar_sala_espera('00000000-...', 5, '2026-06-22 10:00:00');
