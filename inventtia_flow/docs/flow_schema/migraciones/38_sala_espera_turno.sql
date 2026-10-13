-- ============================================================================
-- 38 - Lista de espera: el turno donde el cliente se anota
-- ============================================================================
-- QUE HACE
--   1) `flow.cliente_obtener_salas_espera` devuelve `id_turno` y el nombre del
--      turno (`turno`), para que "Mis Listas" y la tarjeta de la cola puedan
--      decir en que turno se anoto el cliente.
--   2) `flow.admin_listar_salas_espera` devuelve lo mismo, para que el negocio
--      vea el turno que pidio cada persona en la cola.
--   3) `flow.cliente_entrar_sala_espera_reserva` pasa a comprobar el duplicado
--      por (servicio, titular) en vez de por (servicio, titular, turno).
--
-- POR QUE (3) ES UN ARREGLO Y NO UN CAMBIO DE CRITERIO
--   La restriccion real de la tabla es el indice unico
--   `unique_usuario_servicio_activo (uuid_usuario, id_local_servicio)`: una sola
--   entrada por persona y servicio-local. El pre-chequeo del RPC, en cambio,
--   comparaba tambien `id_turno`, asi que una segunda entrada al MISMO servicio
--   con OTRO turno pasaba el pre-chequeo, llegaba al INSERT y reventaba con un
--   `23505 unique_violation` que la funcion NO captura: el cliente recibia un
--   error crudo de PostgREST en vez de `{ok:false, error:'...'}`. Ahora el
--   pre-chequeo dice exactamente lo que dice el indice.
--
-- POR QUE NO SE TOCA EL INDICE UNICO
--   La tentacion es ampliarlo a `(uuid_usuario, id_local_servicio, id_turno)`
--   para permitir varias colas por turno. NO se hace: la numeracion de la cola
--   es global por servicio-local (`max(numero_cola)` en este RPC),
--   `cliente_salir_sala_espera` recompacta por servicio-local y borra por
--   (servicio, usuario) sin mirar el turno, y `bot_procesar_recurso_dia`
--   recompacta tambien por servicio-local. Permitir dos entradas de la misma
--   persona romperia esas tres cosas a la vez. El turno es, por tanto, la
--   **preferencia** de la persona dentro de la unica cola del servicio, que es
--   justo lo que el bot ya sabe usar (`se.id_turno = p_id_turno`, con respaldo
--   para las entradas viejas con `id_turno is null`).
--
--   El cliente respeta ese modelo: mientras hay una entrada activa, la pantalla
--   muestra "Salir de la lista" y no ofrece volver a anotarse.
--
-- ALCANCE
--   Tres funciones del esquema `flow`. No se toca ninguna tabla, ni RLS, ni
--   indices, ni grants (`create or replace` conserva la ACL y la firma, asi que
--   PostgREST no ve overloading nuevo).
--
-- ROLLBACK
--   Volver a desplegar las dos definiciones anteriores (estan en el historial
--   de `pg_get_functiondef`): la de `cliente_entrar_sala_espera_reserva` con el
--   pre-chequeo por `id_turno` y las de `cliente_obtener_salas_espera` /
--   `admin_listar_salas_espera` sin las claves `id_turno`/`turno`. El cliente
--   tolera el rollback: `SalaEspera.fromJson` lee `id_turno` y `turno` como
--   opcionales (quedan en "turno no indicado").
--
-- IDEMPOTENTE
--   `create or replace function` con la misma firma: se puede reejecutar.
--
-- REQUISITO PREVIO
--   La columna `flow.sala_espera.id_turno` y su FK ya existen (migracion 16),
--   igual que `flow.cliente_entrar_sala_espera_reserva`, que es la unica que
--   acepta `p_id_turno`. Este archivo no crea nada de eso: si falta, aborta
--   abajo con un mensaje claro en vez de dejar el esquema a medias.
--
--   Aplicar en LOS DOS proyectos Supabase (debug `qhprswhhfasrikhawjoz` y
--   release `vsieeihstajlrdvpuooh`); si no, el turno se vera en uno y no en el
--   otro.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- COMPROBACION PREVIA
-- ---------------------------------------------------------------------------
do $check$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'flow'
       and table_name = 'sala_espera'
       and column_name = 'id_turno'
  ) then
    raise exception 'Falta flow.sala_espera.id_turno: aplica antes 16_recursos_tramos_turnos.sql';
  end if;

  if not exists (
    select 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'flow'
       and p.proname = 'cliente_entrar_sala_espera_reserva'
       and pg_get_function_identity_arguments(p.oid) like '%p_id_turno integer%'
  ) then
    raise exception 'Falta flow.cliente_entrar_sala_espera_reserva con p_id_turno: aplica antes las RPC de sala de espera (rpc clientes/05)';
  end if;

  if (
    select count(distinct p.proname)
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'flow'
       and p.proname in ('cliente_obtener_salas_espera', 'admin_listar_salas_espera')
  ) < 2 then
    raise exception 'Faltan flow.cliente_obtener_salas_espera o flow.admin_listar_salas_espera: aplica antes las RPC de sala de espera (rpc clientes/03 y rpc admin/06)';
  end if;
end
$check$;

-- ---------------------------------------------------------------------------
-- 1) Mis colas: decir en que turno esta anotado el cliente
-- ---------------------------------------------------------------------------
create or replace function flow.cliente_obtener_salas_espera(p_uuid_usuario uuid)
returns jsonb
language sql
stable
set search_path to 'flow', 'public'
as $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',                se.id,
        'fecha_regla',       se.fecha_regla,
        'created_at',        se.created_at,
        'numero_cola',       se.numero_cola,           -- numero del usuario
        'ultimo_otorgado',   coalesce(un.ultimo_otorgado, 0), -- ultimo numero en el servicio
        -- cuantos numeros faltan para llegar al del usuario (0 = ya es su turno o paso)
        'personas_delante',  greatest(se.numero_cola - coalesce(un.ultimo_otorgado, 0), 0),
        'es_su_turno',       (coalesce(un.ultimo_otorgado, 0) >= se.numero_cola),
        'id_local_servicio', ls.id,
        -- Turno elegido al anotarse (null en las entradas anteriores a esta
        -- migracion y en los servicios que no trabajan por turnos).
        'id_turno',          se.id_turno,
        'turno',             t.nombre,
        'servicio', jsonb_build_object(
          'id',          s.id,
          'nombre',      s.nombre,
          'descripcion', s.descripcion,
          'foto',        s.foto
        ),
        'local', jsonb_build_object(
          'id',               l.id,
          'nombre',           l.nombre,
          'direccion',        l.direccion,
          'pais',             l.pais,
          'provincia',        l.provincia,
          'horario_atencion', l.horario_atencion,
          'coordenadas',      l.coordenadas,
          'foto',             l.foto
        )
      )
      order by se.fecha_regla
    ),
    '[]'::jsonb
  )
  from flow.sala_espera se
  join flow.local_servicio    ls on ls.id = se.id_local_servicio
  join flow.app_dat_locales   l  on l.id  = ls.id_local
  join flow.app_dat_servicios s  on s.id  = ls.id_servicio
  left join flow.turno        t  on t.id  = se.id_turno
  left join flow.ultimo_numero un on un.id_local_servicio = ls.id
  where se.uuid_usuario = p_uuid_usuario;
$function$;

-- ---------------------------------------------------------------------------
-- 2) Panel del negocio: el turno que pidio cada persona en la cola
-- ---------------------------------------------------------------------------
create or replace function flow.admin_listar_salas_espera(
  p_uuid_usuario uuid,
  p_id_entidad integer default null,
  p_id_local integer default null,
  p_id_local_servicio integer default null
)
returns jsonb
language sql
stable
set search_path to 'flow', 'public'
as $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',          se.id,
        'numero_cola', se.numero_cola,
        'fecha_regla', se.fecha_regla,
        'created_at',  se.created_at,
        'id_local_servicio', ls.id,
        'id_turno',    se.id_turno,
        'turno',       t.nombre,
        'servicio', jsonb_build_object('id', s.id, 'nombre', s.nombre),
        'local',    jsonb_build_object('id', l.id, 'nombre', l.nombre),
        'entidad',  jsonb_build_object('id', en.id, 'denominacion', en.denominacion),
        'cliente', case when p.id is null then null else jsonb_build_object(
          'uuid_usuario', p.uuid_usuario,
          'nombre',       p.nombre,
          'apellidos',    p.apellidos,
          'ci',           p.ci,
          'telefono',     p.telefono
        ) end
      )
      order by l.nombre, s.nombre, se.numero_cola
    ),
    '[]'::jsonb
  )
  from flow.sala_espera se
  join flow.local_servicio    ls on ls.id = se.id_local_servicio
  join flow.app_dat_locales   l  on l.id  = ls.id_local
  join flow.app_dat_servicios s  on s.id  = ls.id_servicio
  join flow.entidad           en on en.id = l.id_entidad
  left join flow.turno        t  on t.id  = se.id_turno
  left join flow.perfil       p  on p.uuid_usuario = se.uuid_usuario
  join flow.admin_entidades_de_usuario(p_uuid_usuario) mine on mine.id_entidad = l.id_entidad
  where (p_id_entidad        is null or l.id_entidad        = p_id_entidad)
    and (p_id_local          is null or ls.id_local         = p_id_local)
    and (p_id_local_servicio is null or se.id_local_servicio = p_id_local_servicio);
$function$;

-- ---------------------------------------------------------------------------
-- 3) Anotarse en la cola con turno: el duplicado se mide contra el indice real
-- ---------------------------------------------------------------------------
create or replace function flow.cliente_entrar_sala_espera_reserva(
  p_uuid_usuario uuid,
  p_id_local_servicio integer,
  p_fecha_regla timestamp without time zone default null,
  p_datos_adicionales jsonb default null,
  p_para_tercero boolean default false,
  p_t_nombre text default null,
  p_t_apellidos text default null,
  p_t_ci text default null,
  p_t_telefono text default null,
  p_id_turno integer default null
)
returns jsonb
language plpgsql
set search_path to 'flow', 'public'
as $function$
declare
  v_numero  integer;
  v_id      integer;
  v_fecha   timestamp without time zone;
  v_created timestamp without time zone;
  v_recientes integer;
  v_nombre_servicio text;
  v_nombre_local    text;
  v_titular uuid;
  c_flood_ventana constant interval := interval '1 minute';
  c_flood_max     constant integer  := 5;
begin
  if p_uuid_usuario is null or p_id_local_servicio is null then
    return jsonb_build_object('ok', false,
      'error', 'uuid_usuario e id_local_servicio son obligatorios');
  end if;

  perform pg_advisory_xact_lock(hashtext('flow.sala_espera'), p_id_local_servicio);

  if not exists (select 1 from flow.local_servicio ls where ls.id = p_id_local_servicio) then
    insert into flow.sala_espera_fraude (uuid_usuario, id_local_servicio, motivo, detalle)
    values (p_uuid_usuario, p_id_local_servicio, 'local_servicio_inexistente', null);
    return jsonb_build_object('ok', false, 'error', 'El id_local_servicio no existe');
  end if;

  -- Validar turno si se pide.
  if p_id_turno is not null then
    if not exists (
      select 1 from flow.turno t
      join flow.recurso r on r.id = t.id_recurso and r.activo
      where t.id = p_id_turno and t.activo and r.id_local_servicio = p_id_local_servicio
    ) then
      return jsonb_build_object('ok', false, 'error', 'Turno invalido para este servicio');
    end if;
  end if;

  -- Titular: uno mismo o un tercero.
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

  -- ANTIFRAUDE 1: el titular no entra dos veces a la cola del MISMO servicio.
  -- Es la restriccion que impone `unique_usuario_servicio_activo`, asi que el
  -- mensaje sale de aqui en vez de un 23505 sin capturar. El turno elegido no
  -- participa: la cola es una sola por servicio-local (ver nota de arriba).
  if exists (
    select 1 from flow.sala_espera se
    where se.id_local_servicio = p_id_local_servicio
      and se.uuid_usuario = v_titular
  ) then
    insert into flow.sala_espera_fraude (uuid_usuario, id_local_servicio, motivo, detalle)
    values (p_uuid_usuario, p_id_local_servicio, 'duplicado', 
            jsonb_build_object('id_turno_intentado', p_id_turno));
    return jsonb_build_object('ok', false, 'error',
      case when v_titular = p_uuid_usuario
           then 'Ya estas en la cola de este servicio: sal de ella para cambiar de turno'
           else 'Esa persona ya esta en la cola de este servicio' end);
  end if;

  -- ANTIFRAUDE 2: flood / bots.
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

  -- Numeracion global por LS (independiente del turno).
  select coalesce(max(se.numero_cola), 0) into v_numero
  from flow.sala_espera se
  where se.id_local_servicio = p_id_local_servicio;

  v_numero := v_numero + 1;
  v_fecha  := coalesce(p_fecha_regla, current_timestamp);

  insert into flow.sala_espera
    (uuid_usuario, id_local_servicio, fecha_regla, numero_cola,
     datos_adicionales, reservado_por, id_turno)
  values
    (v_titular, p_id_local_servicio, v_fecha, v_numero,
     p_datos_adicionales, p_uuid_usuario, p_id_turno)
  returning id, created_at into v_id, v_created;

  insert into flow.ultimo_numero (id_local_servicio, ultimo_otorgado, ultimo_en_anotarse, updated_at)
  values (p_id_local_servicio, 0, v_numero, current_timestamp)
  on conflict (id_local_servicio) do update
    set ultimo_en_anotarse = v_numero, updated_at = current_timestamp;

  select s.nombre, l.nombre into v_nombre_servicio, v_nombre_local
  from flow.local_servicio ls
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  join flow.app_dat_locales   l on l.id = ls.id_local
  where ls.id = p_id_local_servicio;

  insert into flow.notificaciones
    (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
  values (
    p_uuid_usuario, 'sala_espera', 'Entraste en la cola',
    'Has entrado satisfactoriamente en la cola para el servicio "'
      || coalesce(v_nombre_servicio, 'servicio')
      || '" en el local "' || coalesce(v_nombre_local, 'local')
      || '" para reserva a partir del '
      || to_char(v_fecha, 'DD/MM/YYYY')
      || case when p_id_turno is null then '.'
              else ' en el turno "' || coalesce((select t.nombre from flow.turno t where t.id = p_id_turno), 'turno') || '".'
         end,
    p_id_local_servicio, v_id,
    jsonb_build_object('numero_cola', v_numero, 'fecha_regla', v_fecha,
      'servicio', v_nombre_servicio, 'local', v_nombre_local, 'id_turno', p_id_turno)
  );

  return jsonb_build_object('ok', true,
    'data', jsonb_build_object(
      'id', v_id, 'uuid_usuario', p_uuid_usuario,
      'id_local_servicio', p_id_local_servicio, 'fecha_regla', v_fecha,
      'numero_cola', v_numero, 'ultimo_en_anotarse', v_numero,
      'created_at', v_created, 'id_turno', p_id_turno));
end;
$function$;

-- ============================================================================
-- VERIFICACION (ejecutar a mano despues de aplicar)
-- ============================================================================
-- V.1 Las tres funciones conservan su firma (no hay overloading nuevo).
--     Esperado: exactamente 3 filas, una por funcion, y `cliente_entrar_*_cola`
--     sigue teniendo 9 argumentos.
-- select p.proname,
--        pg_get_function_identity_arguments(p.oid) as args
--   from pg_proc p
--   join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'flow'
--    and p.proname in ('cliente_entrar_sala_espera_cola',
--                      'cliente_entrar_sala_espera_reserva',
--                      'cliente_obtener_salas_espera',
--                      'admin_listar_salas_espera')
--  order by p.proname;
--
-- V.2 El indice unico sigue siendo el de una entrada por (usuario, servicio).
--     Esperado: unique_usuario_servicio_activo sobre (uuid_usuario, id_local_servicio).
-- select indexname, indexdef
--   from pg_indexes
--  where schemaname = 'flow' and tablename = 'sala_espera'
--  order by indexname;
--
-- V.3 El read devuelve el turno. Con sesion de cliente (o service_role):
-- select jsonb_pretty(flow.cliente_obtener_salas_espera('<uuid-del-cliente>'::uuid));
--     Esperado: cada entrada con 'id_turno' y 'turno' (o null en las viejas).
--
-- V.4 El duplicado se rechaza con mensaje, no con excepcion. Con una entrada
--     activa del mismo usuario, repetir el RPC debe devolver
--     {ok:false, error:'Ya estas en la cola de este servicio: ...'} y NO un 23505:
-- select flow.cliente_entrar_sala_espera_reserva(
--   '<uuid-del-cliente>'::uuid, <id_local_servicio>, now() + interval '1 day');
--
-- V.5 El turno invalido (de otro servicio) sigue rechazandose:
-- select flow.cliente_entrar_sala_espera_reserva(
--   '<uuid-del-cliente>'::uuid, <id_local_servicio>, now() + interval '1 day',
--   null, false, null, null, null, null, <id_turno_de_otro_ls>);
--     Esperado: {ok:false, error:'Turno invalido para este servicio'}.
-- ============================================================================
