-- ============================================================================
-- RPC CLIENTES: entrar en la sala de espera de un servicio
--
-- Logica:
--   1. Se serializan SOLO las entradas del mismo id_local_servicio con un
--      advisory lock transaccional (no bloquea la tabla, RAM despreciable).
--   2. Se busca el ultimo numero_cola dado en ese servicio.
--   3. Se inserta con numero_cola = ultimo + 1.
--   4. Se hace upsert en ultimo_numero actualizando ultimo_en_anotarse.
--
-- Parametros obligatorios: p_uuid_usuario, p_id_local_servicio
-- p_fecha_regla es opcional (default = ahora).
-- Devuelve: jsonb con el registro creado o un error controlado.
-- ============================================================================

-- Añadir columna si no existe (ejecutar una sola vez en migracion):
-- ALTER TABLE flow.ultimo_numero ADD COLUMN IF NOT EXISTS ultimo_en_anotarse integer NOT NULL DEFAULT 0;

-- Firma anterior (3 params) reemplazada por la nueva (con datos/tercero).
drop function if exists flow.cliente_entrar_sala_espera(uuid, integer, timestamp without time zone);

create or replace function flow.cliente_entrar_sala_espera(
  p_uuid_usuario      uuid,
  p_id_local_servicio integer,
  p_fecha_regla       timestamp without time zone default null,
  p_datos_adicionales jsonb   default null,
  p_para_tercero      boolean default false,
  p_t_nombre          text    default null,
  p_t_apellidos       text    default null,
  p_t_ci              text    default null,
  p_t_telefono        text    default null
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
  v_nombre_servicio text;
  v_nombre_local    text;
  v_titular uuid;   -- a nombre de quien queda la entrada en cola
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

  -- Resolver el titular de la entrada: uno mismo o un tercero.
  if coalesce(p_para_tercero, false) then
    if not exists (
      select 1 from flow.local_servicio ls
      join flow.app_dat_servicios s on s.id = ls.id_servicio
      where ls.id = p_id_local_servicio and s.permite_tercero = true
    ) then
      return jsonb_build_object('ok', false, 'error', 'Este servicio no permite reservar para terceros');
    end if;
    v_titular := flow._resolver_perfil_tercero(p_t_nombre, p_t_apellidos, p_t_ci, p_t_telefono);
  else
    v_titular := p_uuid_usuario;
  end if;

  -- ANTIFRAUDE 1: el titular no entra dos veces a la misma cola
  if exists (
    select 1 from flow.sala_espera se
    where se.id_local_servicio = p_id_local_servicio
      and se.uuid_usuario = v_titular
  ) then
    insert into flow.sala_espera_fraude (uuid_usuario, id_local_servicio, motivo, detalle)
    values (p_uuid_usuario, p_id_local_servicio, 'duplicado', null);
    return jsonb_build_object('ok', false, 'error',
      case when v_titular = p_uuid_usuario
           then 'El usuario ya esta en esta cola'
           else 'Esa persona ya esta en esta cola' end);
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

  insert into flow.sala_espera
    (uuid_usuario, id_local_servicio, fecha_regla, numero_cola,
     datos_adicionales, reservado_por)
  values
    (v_titular, p_id_local_servicio, v_fecha, v_numero,
     p_datos_adicionales, p_uuid_usuario)
  returning id, created_at into v_id, v_created;

  -- Actualizar ultimo_en_anotarse en ultimo_numero (upsert atomico bajo el mismo advisory lock)
  insert into flow.ultimo_numero (id_local_servicio, ultimo_otorgado, ultimo_en_anotarse, updated_at)
  values (p_id_local_servicio, 0, v_numero, current_timestamp)
  on conflict (id_local_servicio) do update
    set ultimo_en_anotarse = v_numero,
        updated_at         = current_timestamp;

  -- Notificacion al usuario: "entro satisfactoriamente en la cola".
  -- Nombres del servicio y del local para un mensaje legible.
  select s.nombre, l.nombre
    into v_nombre_servicio, v_nombre_local
  from flow.local_servicio ls
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  join flow.app_dat_locales   l on l.id = ls.id_local
  where ls.id = p_id_local_servicio;

  insert into flow.notificaciones
    (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
  values (
    p_uuid_usuario,
    'sala_espera',
    'Entraste en la cola',
    'Has entrado satisfactoriamente en la cola para el servicio "'
      || coalesce(v_nombre_servicio, 'servicio')
      || '" en el local "' || coalesce(v_nombre_local, 'local')
      || '" para reserva a partir del '
      || to_char(v_fecha, 'DD/MM/YYYY') || '.',
    p_id_local_servicio,
    v_id,
    jsonb_build_object(
      'numero_cola', v_numero,
      'fecha_regla', v_fecha,
      'servicio',    v_nombre_servicio,
      'local',       v_nombre_local
    )
  );

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id',                  v_id,
      'uuid_usuario',        p_uuid_usuario,
      'id_local_servicio',   p_id_local_servicio,
      'fecha_regla',         v_fecha,
      'numero_cola',         v_numero,
      'ultimo_en_anotarse',  v_numero,
      'created_at',          v_created
    )
  );
end;
$$;

grant execute on function flow.cliente_entrar_sala_espera(
  uuid, integer, timestamp without time zone, jsonb, boolean, text, text, text, text
) to authenticated;

-- Migracion requerida (ejecutar una sola vez en Supabase):
--   ALTER TABLE flow.ultimo_numero ADD COLUMN IF NOT EXISTS ultimo_en_anotarse integer NOT NULL DEFAULT 0;
--   (datos_adicionales/reservado_por -> migracion 11; permite_tercero -> migracion 10)
--
-- Uso:
--   select flow.cliente_entrar_sala_espera('00000000-...', 5);
--   select flow.cliente_entrar_sala_espera('00000000-...', 5, '2026-06-22 10:00:00');
--   select flow.cliente_entrar_sala_espera('00000000-...', 5, null,
--            '{"codigo_pais":"53"}'::jsonb);                                  -- con datos
--   select flow.cliente_entrar_sala_espera('00000000-...', 5, null, null,
--            true, 'Ana', 'Paz', '85010112345', '55512345');                 -- para tercero
