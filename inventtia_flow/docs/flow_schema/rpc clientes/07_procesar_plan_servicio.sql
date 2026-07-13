-- ============================================================================
-- BACKGROUND (nucleo): procesar UN plan_servicios
--
-- Mueve candidatos de sala_espera -> agenda mientras haya cupo:
--   - mismo id_local_servicio
--   - plan.fecha >= sala_espera.fecha_regla  (respeta la regla pedida)
--   - orden FIFO por numero_cola
--   - se detiene cuando agendados == cantidad o no quedan candidatos
--
-- Todo en UNA operacion set-based (CTE): delete + insert + recount.
-- Tras repartir, hace UPSERT en flow.ultimo_numero (acumula ultimo_otorgado)
-- para guardar "por donde se quedo repartiendo" en este id_local_servicio.
-- Registra CADA corrida en flow.bot_log (ok / sin_movimiento / sin_cupo / error)
-- incluyendo fallos inesperados via bloque EXCEPTION.
-- Devuelve: jsonb con cuantos se agendaron.
-- security definer: escribe en agenda/sala_espera/plan/ultimo_numero/bot_log.
-- ============================================================================

create or replace function flow.bot_procesar_plan(
  p_id_plan bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = flow, public
as $$
declare
  v_ls       integer;
  v_fecha    timestamp with time zone;
  v_cupo     integer;
  v_estado   integer;
  v_movidos  integer := 0;
  v_nombre_servicio text;
  v_nombre_local    text;
  v_saludo          text;
  v_id_servicio     integer;
begin
  -- Lee el plan y BLOQUEA esa fila (evita doble procesamiento del mismo plan)
  select ps.id_local_servicio, ps.fecha, (ps.cantidad - ps.agendados)
    into v_ls, v_fecha, v_cupo
  from flow.plan_servicios ps
  where ps.id = p_id_plan
  for update;

  if not found then
    insert into flow.bot_log (id_plan, resultado, movidos, mensaje)
    values (p_id_plan, 'error', 0, 'plan no encontrado');
    return jsonb_build_object('ok', false, 'error', 'plan no encontrado');
  end if;

  -- Sin cupo o sin servicio asignado -> nada que hacer
  if v_ls is null or v_cupo is null or v_cupo <= 0 then
    insert into flow.bot_log (id_plan, id_local_servicio, resultado, movidos, mensaje, detalle)
    values (p_id_plan, v_ls, 'sin_cupo', 0, 'sin cupo',
            jsonb_build_object('cupo', v_cupo));
    return jsonb_build_object('ok', true, 'movidos', 0, 'motivo', 'sin cupo');
  end if;

  -- Serializa con entrar/salir de ESTE servicio (mismo advisory lock)
  perform pg_advisory_xact_lock(hashtext('flow.sala_espera'), v_ls);

  -- Estado destino para las agendas creadas
  select id into v_estado from flow.nom_estado_agenda where nombre = 'Reservado' limit 1;
  if v_estado is null then
    insert into flow.bot_log (id_plan, id_local_servicio, resultado, movidos, mensaje)
    values (p_id_plan, v_ls, 'error', 0, 'falta el estado Reservado (correr migracion 03)');
    return jsonb_build_object('ok', false, 'error', 'falta el estado Reservado (correr migracion 03)');
  end if;

  -- Datos para las notificaciones de "reservacion confirmada":
  -- nombres legibles del servicio/local y saludo segun la hora del servidor.
  select s.nombre, l.nombre, ls.id_servicio
    into v_nombre_servicio, v_nombre_local, v_id_servicio
  from flow.local_servicio ls
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  join flow.app_dat_locales   l on l.id = ls.id_local
  where ls.id = v_ls;

  v_saludo := case
    when extract(hour from current_timestamp) between 5 and 11 then 'Buenos días'
    when extract(hour from current_timestamp) between 12 and 18 then 'Buenas tardes'
    else 'Buenas noches'
  end;

  -- Reparto en un solo paso (set-based). ORDEN IMPORTANTE para no sacar a nadie
  -- de la cola sin darle reserva:
  --   1) candidatos: hasta v_cupo elegibles, FIFO, bloqueados (skip locked).
  --   2) insertados: se CREA la agenda primero (una por candidato).
  --   3) borrados:   se elimina de sala_espera SOLO a quienes quedaron en
  --                  'insertados' (los que de verdad recibieron agenda).
  -- Como 'borrados' depende del RETURNING de 'insertados', Postgres garantiza
  -- que nunca se borra a un candidato que no haya sido reservado. Si en el
  -- futuro la insercion se vuelve condicional, los no reservados permanecen en
  -- la cola y podran recibir reserva en una corrida posterior.
  -- El CTE 'notificados' crea una notificacion por cada reserva confirmada;
  -- como es data-modifying, Postgres lo ejecuta siempre aunque no se lea.
  with candidatos as (
    select se.id, se.uuid_usuario, se.datos_adicionales, se.reservado_por
    from flow.sala_espera se
    where se.id_local_servicio = v_ls
      -- Compara por DIA en hora local (America/Havana). Antes era
      -- 'se.fecha_regla <= v_fecha', que casteaba el timestamp naive de
      -- fecha_regla usando la tz de la conexion (cron/service_role suele ser
      -- UTC, sesion interactiva America/Havana): el limite de dia se desplazaba
      -- y se barrian candidatos del dia equivocado, borrandolos de la cola.
      -- Solo califican los cuya fecha pedida (dia) sea <= al dia del plan.
      and se.fecha_regla::date <= (v_fecha at time zone 'America/Havana')::date
    order by se.numero_cola
    limit v_cupo
    for update skip locked
  ),
  insertados as (
    insert into flow.agenda
      (uuid_usuario, id_local_servicio, id_estado, fecha_hora_reserva,
       cantidad, datos_adicionales, reservado_por, precio_total, moneda)
    select c.uuid_usuario, v_ls, v_estado, v_fecha,
           1, c.datos_adicionales, c.reservado_por,
           cp.precio_total, cp.moneda
    from candidatos c
    cross join lateral flow.calcular_precio_reserva(
      v_id_servicio,
      coalesce(c.datos_adicionales, '{}'::jsonb),
      null,
      1
    ) cp
    returning uuid_usuario, id, fecha_hora_reserva
  ),
  borrados as (
    delete from flow.sala_espera se
    using candidatos c
    where se.id = c.id
      and se.uuid_usuario in (select uuid_usuario from insertados)
    returning se.id
  ),
  notificados as (
    insert into flow.notificaciones
      (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
    select
      i.uuid_usuario,
      'reserva',
      'Reservación confirmada',
      v_saludo || ', '
        || coalesce(nullif(trim(p.nombre || ' ' || p.apellidos), ''), 'estimado cliente')
        || ', se ha realizado satisfactoriamente su reservación para el local "'
        || coalesce(v_nombre_local, 'local') || '" el servicio "'
        || coalesce(v_nombre_servicio, 'servicio') || '" para la fecha '
        || to_char(i.fecha_hora_reserva, 'DD/MM/YYYY') || '.',
      v_ls,
      i.id,
      jsonb_build_object(
        'fecha',    i.fecha_hora_reserva,
        'servicio', v_nombre_servicio,
        'local',    v_nombre_local
      )
    from insertados i
    left join flow.perfil p on p.uuid_usuario = i.uuid_usuario
    returning 1
  )
  select count(*) into v_movidos from insertados;

  if v_movidos > 0 then
    -- Actualiza el contador del plan
    update flow.plan_servicios
       set agendados = agendados + v_movidos
     where id = p_id_plan;

    -- Registra "por donde se quedo repartiendo" en flow.ultimo_numero.
    -- Como la cola es compacta (se renumera 1..N tras agendar), ultimo_otorgado
    -- se lleva como contador ACUMULADO del total repartido en este servicio:
    -- crece de forma monotonica corrida tras corrida.
    -- UPSERT por id_local_servicio (columna UNIQUE): suma si ya existe, inserta si no.
    insert into flow.ultimo_numero (id_local_servicio, ultimo_otorgado, updated_at)
    values (v_ls, v_movidos, current_timestamp)
    on conflict (id_local_servicio) do update
      set ultimo_otorgado = flow.ultimo_numero.ultimo_otorgado + excluded.ultimo_otorgado,
          updated_at      = current_timestamp;

    -- Recompacta la cola del servicio: renumera 1..N por orden de llegada,
    -- asi no quedan huecos tras sacar a los del frente.
    with reord as (
      select se.id, row_number() over (order by se.numero_cola) as rn
      from flow.sala_espera se
      where se.id_local_servicio = v_ls
    )
    update flow.sala_espera se
       set numero_cola = r.rn
      from reord r
     where se.id = r.id
       and se.numero_cola <> r.rn;   -- solo toca filas que realmente cambian

    -- Si la cola quedo VACIA tras despachar a todos, reinicia los contadores
    -- de flow.ultimo_numero: es una cola "nueva" porque ya no queda nadie
    -- esperando. ultimo_otorgado y ultimo_en_anotarse vuelven a 0 para que
    -- la proxima persona que se anote empiece a numerar desde cero otra vez.
    if not exists (
      select 1 from flow.sala_espera se where se.id_local_servicio = v_ls
    ) then
      update flow.ultimo_numero
         set ultimo_otorgado    = 0,
             ultimo_en_anotarse = 0,
             updated_at         = current_timestamp
       where id_local_servicio = v_ls;
    end if;
  end if;

  -- Log de la corrida: 'ok' si repartio, 'sin_movimiento' si no habia candidatos.
  insert into flow.bot_log (id_plan, id_local_servicio, resultado, movidos, mensaje, detalle)
  values (
    p_id_plan, v_ls,
    case when v_movidos > 0 then 'ok' else 'sin_movimiento' end,
    v_movidos,
    case when v_movidos > 0
         then 'repartio ' || v_movidos || ' agenda(s)'
         else 'sin candidatos en cola' end,
    jsonb_build_object('cupo', v_cupo, 'fecha_plan', v_fecha)
  );

  return jsonb_build_object(
    'ok', true,
    'id_plan', p_id_plan,
    'id_local_servicio', v_ls,
    'movidos', v_movidos
  );

exception
  when others then
    -- Cualquier fallo inesperado: el rollback al savepoint implicito de este
    -- bloque revierte el reparto, pero este INSERT (posterior) si persiste.
    insert into flow.bot_log (id_plan, id_local_servicio, resultado, movidos, mensaje, detalle)
    values (p_id_plan, v_ls, 'error', 0, sqlerrm,
            jsonb_build_object('sqlstate', sqlstate));
    return jsonb_build_object(
      'ok', false,
      'id_plan', p_id_plan,
      'error', sqlerrm,
      'sqlstate', sqlstate
    );
end;
$$;

revoke all on function flow.bot_procesar_plan(bigint) from public;
-- Solo roles de servidor lo ejecutan (cron / edge function con service_role)
grant execute on function flow.bot_procesar_plan(bigint) to service_role;
