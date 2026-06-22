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

  -- Mover en un solo paso: toma hasta v_cupo candidatos FIFO, los borra de
  -- sala_espera e inserta sus agendas. skip locked por robustez ante concurrencia.
  with candidatos as (
    select se.id
    from flow.sala_espera se
    where se.id_local_servicio = v_ls
      and se.fecha_regla <= v_fecha          -- plan.fecha >= fecha_regla
    order by se.numero_cola
    limit v_cupo
    for update skip locked
  ),
  borrados as (
    delete from flow.sala_espera se
    using candidatos c
    where se.id = c.id
    returning se.uuid_usuario
  ),
  insertados as (
    insert into flow.agenda (uuid_usuario, id_local_servicio, id_estado, fecha_hora_reserva)
    select b.uuid_usuario, v_ls, v_estado, v_fecha
    from borrados b
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
