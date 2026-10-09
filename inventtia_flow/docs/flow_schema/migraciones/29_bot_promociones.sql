-- ============================================================================
-- 29. BOTS DE COLA + PROMOCIONES
--
-- ORIGEN DE ESTAS DEFINICIONES (LEER ANTES DE TOCAR)
--   Las dos funciones de abajo NO se han escrito a mano desde los archivos del
--   repo: se han extraido de la BASE DE DATOS VIVA con `pg_get_functiondef()` y
--   se les ha sustituido SOLO el bloque de precios.
--
--   Motivo: `docs/flow_schema/rpc admin/28_recursos_cola_bot.sql` esta
--   DESACTUALIZADO. La `bot_procesar_recurso_dia` viva tiene una logica de
--   candidatos que NO existe en el archivo: ademas de los candidatos con
--   `se.id_turno = p_id_turno`, reclama los que tienen `id_turno is null`
--   cuando ningun turno ANTERIOR (por `turno.orden`) puede atenderlos, con
--   verificacion de cupo por tramo. Aplicar la version del archivo habria
--   BORRADO esa logica.
--
--   `bot_procesar_plan` vivo coincide funcionalmente con el archivo: solo
--   cambiaban el delimitador (`$function$`) y los saltos de linea (CRLF).
--
--   Los cuerpos se han verificado contra la base por md5 (ver VERIFICACION).
--
-- OBJETIVO
--   Que los bots de cola apliquen la promocion VIGENTE al confirmar la reserva,
--   consumiendo cupo, igual que `cliente_reservar_directo`.
--
-- POR QUE HACE FALTA
--   `flow.sala_espera` NO tiene columna de precio: el importe se fija al crear
--   la fila de `flow.agenda`, y quien la crea es el bot. Lo hacia con
--   `calcular_precio_reserva` a secas, asi que quien veia "-20%" en el detalle
--   acababa pagando precio de lista. Con 4 de los 7 servicios en
--   `permite_reserva_directa = false`, afectaba a la mayoria de las reservas.
--
--   Decision de producto: el bot aplica la promo vigente al confirmar.
--   Consecuencia asumida: si la promo vence mientras el cliente espera en la
--   cola, el importe cobrado puede diferir del que se mostro al anotarse.
--
-- QUE CAMBIA (SOLO el bloque de precios de cada funcion)
--
--   1) flow.bot_procesar_plan(bigint)            [camino legacy plan_servicios]
--        Precio de lista: `calcular_precio_reserva` (SIN cambio).
--        Ahora pasa por `_aplicar_promocion(..., true)`.
--
--   2) flow.bot_procesar_recurso_dia(integer, date)      [camino recursos/turnos]
--        a) aplica la promo con `_aplicar_promocion(..., true)`;
--        b) el precio de lista pasa de `calcular_precio_reserva` a
--           `calcular_precio_turno`.
--
--   (b) corrige un descuadre que YA existia y es INDEPENDIENTE de las promos.
--   Medido en la base con los turnos reales:
--        turno 4,5,6 -> LS 7  : calcular_precio_reserva 60 | turno 60
--        turno 17    -> LS 11 : calcular_precio_reserva 40 | turno 70
--        turno 18    -> LS 11 : calcular_precio_reserva 40 | turno 60
--        turno 19    -> LS 11 : calcular_precio_reserva 40 | turno 20
--        turno 20,21 -> LS 12 : calcular_precio_reserva 50 | turno 35
--   `cotizar_reserva` y `cliente_reservar_directo` usan `calcular_precio_turno`
--   cuando hay turno; el bot usaba el generico del servicio. Habia 123 agendas
--   creadas por ese camino. Se alinea el cobro con lo que la app muestra.
--
-- COMO CONSUME CUPO
--   Cada reserva consume 1 de cupo de la promo aplicada. `_aplicar_promocion`
--   hace el UPDATE condicionado a `cupo_usado < cupo_total` y comprueba
--   row_count: si el cupo se agoto entre la cotizacion y la confirmacion
--   devuelve ok=false. En ese caso el bot cae al PRECIO DE LISTA, nunca deja
--   `precio_total` en NULL ni cobra 0.
--
--   Nota (limitacion asumida): dentro de una misma sentencia las CTE comparten
--   snapshot, asi que si hay 2 promos solapadas y la mejor se agota a mitad del
--   reparto, las filas siguientes caen a precio de lista en vez de pasar a la
--   segunda promo. Erra siempre hacia cobrar de mas, nunca de menos.
--
-- PRECIO NULL
--   Un servicio con `config_precio = '{}'` devuelve precio de lista NULL (la app
--   muestra "Consultar"). Se conserva NULL: `_aplicar_promocion` devolveria 0 y
--   convertiria "Consultar" en "gratis".
--
-- NO INCLUIDO A PROPOSITO (pendiente de decision)
--   `bot_procesar_plan` NO filtra por `id_turno`, asi que puede capturar
--   candidatos que esperan un turno y crearles una agenda SIN `id_turno`, al
--   precio generico del servicio y sin descontar `plan_tramo`. `bot_sweep`
--   recorre los planes legacy ANTES que los turnos, asi que gana el legacy.
--   Afecta a los servicios 7, 19 y 21, que hoy tienen planes legacy con cupo y
--   turnos activos a la vez.
--   No se incluye aqui porque la precedencia correcta entre el camino legacy y
--   el camino de turnos es una decision de producto, y la logica viva del bot
--   de turnos (que reclama TAMBIEN los `id_turno is null`) sugiere que el camino
--   de turnos deberia tener prioridad. Va en una migracion aparte si se decide.
--
-- PRE-CHECK
--   Requiere la migracion 27 aplicada (usa `flow._aplicar_promocion`).
--
-- REVERSION
--   Guardar ANTES de aplicar, para poder volver atras:
--     select p.proname, pg_get_functiondef(p.oid)
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--     where n.nspname = 'flow'
--       and p.proname in ('bot_procesar_plan', 'bot_procesar_recurso_dia');
--   Restaurar esas dos definiciones. NO sirve volver a aplicar los archivos del
--   repo: estan desactualizados (ver arriba).
--
-- IDEMPOTENTE: solo `create or replace`, se puede reaplicar.
-- ============================================================================


-- ============================================================================
-- 0. PRE-CHECK (debe devolver todo_en_orden = true)
-- ============================================================================
select
  to_regprocedure('flow._aplicar_promocion(integer, integer, numeric, varchar, numeric, boolean)') is not null
  and to_regprocedure('flow.calcular_precio_turno(integer, integer, jsonb, text, integer)') is not null
  and to_regprocedure('flow.bot_procesar_plan(bigint)') is not null
  and to_regprocedure('flow.bot_procesar_recurso_dia(integer, date)') is not null
  as todo_en_orden;


-- ============================================================================
-- 1. bot_procesar_plan  (camino legacy: plan_servicios)
--    Copia de la definicion VIVA + bloque de precios parcheado.
-- ============================================================================
CREATE OR REPLACE FUNCTION flow.bot_procesar_plan(p_id_plan bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
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
           case when cp.precio_total is null then null
                when (pr ->> 'ok') = 'true' then (pr ->> 'precio_total')::numeric
                else cp.precio_total end,
           case when cp.precio_total is null then cp.moneda
                when (pr ->> 'ok') = 'true' then (pr ->> 'moneda')::varchar
                else cp.moneda end
    from candidatos c
    cross join lateral flow.calcular_precio_reserva(
      v_id_servicio,
      coalesce(c.datos_adicionales, '{}'::jsonb),
      null,
      1
    ) cp
    cross join lateral flow._aplicar_promocion(
      v_ls, v_id_servicio, cp.precio_total, cp.moneda, cp.precio_unit, true
    ) pr
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
$function$;


-- ============================================================================
-- 2. bot_procesar_recurso_dia  (camino recursos/turnos)
--    Copia de la definicion VIVA + bloque de precios parcheado.
--    CONSERVA la logica viva de candidatos (id_turno is null / turno.orden).
-- ============================================================================
CREATE OR REPLACE FUNCTION flow.bot_procesar_recurso_dia(p_id_turno integer, p_fecha date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_ls              integer;
  v_id_servicio     integer;
  v_estado          integer;
  v_cupo            integer;
  v_n_tramos        integer;
  v_n_plan          integer;
  v_movidos         integer := 0;
  v_fecha_ts        timestamp without time zone;
  v_nombre_servicio text;
  v_nombre_local    text;
  v_saludo          text;
begin
  -- Recurso/LS del turno.
  select r.id_local_servicio into v_ls
  from flow.turno t
  join flow.recurso r on r.id = t.id_recurso and r.activo
  where t.id = p_id_turno and t.activo;

  if v_ls is null then
    return jsonb_build_object('ok', true, 'movidos', 0, 'motivo', 'turno inactivo');
  end if;

  perform pg_advisory_xact_lock(hashtext('flow.sala_espera'), v_ls);

  select id into v_estado from flow.nom_estado_agenda where nombre = 'Reservado' limit 1;
  if v_estado is null then
    return jsonb_build_object('ok', false, 'error', 'falta el estado Reservado');
  end if;

  -- Cuantos tramos consume el turno.
  select count(*) into v_n_tramos from flow.turno_tramo tt where tt.id_turno = p_id_turno;
  if coalesce(v_n_tramos, 0) = 0 then
    return jsonb_build_object('ok', true, 'movidos', 0, 'motivo', 'turno sin tramos');
  end if;

  -- Cupo del turno ese dia = min(disponible) sobre sus tramos; bloquea plan_tramo.
  create temporary table if not exists _tmp_bot_pt (id bigint) on commit drop;
  delete from _tmp_bot_pt where id is not null;

  insert into _tmp_bot_pt (id)
  select pt.id
  from flow.turno_tramo tt
  join flow.tramo tr      on tr.id = tt.id_tramo and tr.activo
  join flow.plan_tramo pt on pt.id_tramo = tr.id
  where tt.id_turno = p_id_turno
    and (pt.fecha at time zone 'America/Havana')::date = p_fecha
  for update of pt;

  select count(*), coalesce(min(pt.cantidad - pt.agendados), 0)
    into v_n_plan, v_cupo
  from flow.plan_tramo pt
  join _tmp_bot_pt tmp on tmp.id = pt.id;

  -- Todos los tramos del turno deben tener plan ese dia y quedar cupo.
  if coalesce(v_n_plan, 0) < v_n_tramos or v_cupo <= 0 then
    return jsonb_build_object('ok', true, 'movidos', 0, 'motivo', 'sin cupo');
  end if;

  v_fecha_ts := (make_timestamp(extract(year from p_fecha)::int,
                                extract(month from p_fecha)::int,
                                extract(day from p_fecha)::int, 12, 0, 0));

  select s.nombre, l.nombre, ls.id_servicio
    into v_nombre_servicio, v_nombre_local, v_id_servicio
  from flow.local_servicio ls
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  join flow.app_dat_locales   l on l.id = ls.id_local
  where ls.id = v_ls;

  v_saludo := case
    when extract(hour from current_timestamp) between 5 and 11 then 'Buenos dias'
    when extract(hour from current_timestamp) between 12 and 18 then 'Buenas tardes'
    else 'Buenas noches'
  end;

  -- Reparto set-based: N candidatos FIFO de la cola de ESTE turno (N=cupo).
  -- Cada turno consume 1 plaza de cada tramo, por eso caben exactamente v_cupo.
  with candidatos as (
    select se.id, se.uuid_usuario, se.datos_adicionales, se.reservado_por
    from flow.sala_espera se
    where se.id_local_servicio = v_ls
      and (
        se.id_turno = p_id_turno
        or (
          se.id_turno is null
          and not exists (
            select 1
            from flow.turno t0
            join flow.recurso r0 on r0.id = t0.id_recurso and r0.activo
            join flow.turno_tramo tt0 on tt0.id_turno = t0.id
            join flow.tramo tr0 on tr0.id = tt0.id_tramo and tr0.activo
            join flow.plan_tramo pt0 on pt0.id_tramo = tr0.id
            where t0.activo
              and r0.id_local_servicio = v_ls
              and (t0.orden, t0.id) < (
                select t1.orden, t1.id
                from flow.turno t1
                where t1.id = p_id_turno
              )
              and (pt0.fecha at time zone 'America/Havana')::date = p_fecha
            group by t0.id
            having count(pt0.id) = (
              select count(*)
              from flow.turno_tramo tt2
              where tt2.id_turno = t0.id
            )
              and min(pt0.cantidad - pt0.agendados) > 0
          )
        )
      )
      and se.fecha_regla::date <= p_fecha
    order by se.numero_cola
    limit v_cupo
    for update skip locked
  ),
  insertados as (
    insert into flow.agenda
      (uuid_usuario, id_local_servicio, id_estado, fecha_hora_reserva,
       cantidad, datos_adicionales, reservado_por, precio_total, moneda, id_turno)
    select c.uuid_usuario, v_ls, v_estado, v_fecha_ts,
           1, c.datos_adicionales, c.reservado_por,
           case when cp.precio_total is null then null
                when (pr ->> 'ok') = 'true' then (pr ->> 'precio_total')::numeric
                else cp.precio_total end,
           case when cp.precio_total is null then cp.moneda
                when (pr ->> 'ok') = 'true' then (pr ->> 'moneda')::varchar
                else cp.moneda end,
           p_id_turno
    from candidatos c
    cross join lateral flow.calcular_precio_turno(
      v_id_servicio, p_id_turno, coalesce(c.datos_adicionales, '{}'::jsonb), null, 1) cp
    cross join lateral flow._aplicar_promocion(
      v_ls, v_id_servicio, cp.precio_total, cp.moneda, cp.precio_unit, true) pr
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
      i.uuid_usuario, 'reserva', 'Reservacion confirmada',
      v_saludo || ', '
        || coalesce(nullif(trim(p.nombre || ' ' || p.apellidos), ''), 'estimado cliente')
        || ', se ha realizado satisfactoriamente su reservacion para el local "'
        || coalesce(v_nombre_local, 'local') || '" el servicio "'
        || coalesce(v_nombre_servicio, 'servicio') || '" para la fecha '
        || to_char(i.fecha_hora_reserva, 'DD/MM/YYYY') || '.',
      v_ls, i.id,
      jsonb_build_object('fecha', i.fecha_hora_reserva, 'servicio', v_nombre_servicio,
        'local', v_nombre_local, 'id_turno', p_id_turno)
    from insertados i
    left join flow.perfil p on p.uuid_usuario = i.uuid_usuario
    returning 1
  )
  select count(*) into v_movidos from insertados;

  if v_movidos > 0 then
    -- Descontar el cupo en cada tramo del turno.
    update flow.plan_tramo pt
       set agendados = pt.agendados + v_movidos
    from _tmp_bot_pt tmp
    where pt.id = tmp.id;

    -- Recompactar la cola del LS (numeracion global 1..N por orden de llegada).
    with reord as (
      select se.id, row_number() over (order by se.numero_cola) as rn
      from flow.sala_espera se
      where se.id_local_servicio = v_ls
    )
    update flow.sala_espera se
       set numero_cola = r.rn
      from reord r
     where se.id = r.id and se.numero_cola <> r.rn;
  end if;

  insert into flow.bot_log (id_plan, id_local_servicio, resultado, movidos, mensaje, detalle)
  values (null, v_ls,
    case when v_movidos > 0 then 'ok' else 'sin_movimiento' end,
    v_movidos,
    case when v_movidos > 0 then 'repartio ' || v_movidos || ' agenda(s) turno'
         else 'sin candidatos en cola de turno' end,
    jsonb_build_object('id_turno', p_id_turno, 'fecha', p_fecha, 'cupo', v_cupo));

  return jsonb_build_object('ok', true, 'id_turno', p_id_turno,
    'id_local_servicio', v_ls, 'movidos', v_movidos);
exception
  when others then
    insert into flow.bot_log (id_plan, id_local_servicio, resultado, movidos, mensaje, detalle)
    values (null, v_ls, 'error', 0, sqlerrm,
            jsonb_build_object('id_turno', p_id_turno, 'sqlstate', sqlstate));
    return jsonb_build_object('ok', false, 'id_turno', p_id_turno,
      'error', sqlerrm, 'sqlstate', sqlstate);
end;
$function$;


-- ============================================================================
-- 3. PERMISOS
--   `create or replace` conserva los ACL previos; se reafirman.
-- ============================================================================
revoke all on function flow.bot_procesar_plan(bigint) from public, anon, authenticated;
grant execute on function flow.bot_procesar_plan(bigint) to service_role;

revoke all on function flow.bot_procesar_recurso_dia(integer, date) from public, anon;
grant execute on function flow.bot_procesar_recurso_dia(integer, date) to authenticated, service_role;

notify pgrst, 'reload schema';


-- ============================================================================
-- 4. VERIFICACION
-- ============================================================================
-- 4.a) Comprobacion EXACTA contra las definiciones que se generaron en la base.
--      `coincide` debe ser true en las DOS filas. El md5 se calcula sobre el
--      texto normalizado a LF, igual que se genero.
select p.proname,
       length(replace(pg_get_functiondef(p.oid), E'\r\n', E'\n')) as largo,
       md5(replace(pg_get_functiondef(p.oid), E'\r\n', E'\n'))    as md5_actual,
       case p.proname
         when 'bot_procesar_plan'        then 'caef740b02331681764c1478ac8587a5'
         when 'bot_procesar_recurso_dia' then '6b7e5661ff5b95dd2db9e82333f91477'
       end as md5_esperado,
       md5(replace(pg_get_functiondef(p.oid), E'\r\n', E'\n')) = case p.proname
         when 'bot_procesar_plan'        then 'caef740b02331681764c1478ac8587a5'
         when 'bot_procesar_recurso_dia' then '6b7e5661ff5b95dd2db9e82333f91477'
       end as coincide
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'flow'
  and p.proname in ('bot_procesar_plan', 'bot_procesar_recurso_dia')
order by p.proname;

-- 4.b) Comprobacion semantica. Valores esperados:
--        bot_procesar_plan        : usa_promociones=t, usa_precio_turno=f,
--                                   usa_precio_servicio=t, definer=t
--        bot_procesar_recurso_dia : usa_promociones=t, usa_precio_turno=t,
--                                   usa_precio_servicio=f, definer=t
--
--      OJO con el patron: se busca `flow.<nombre>(` (con prefijo y parentesis),
--      no solo el nombre. `pg_get_functiondef` devuelve el cuerpo CON sus
--      comentarios, y ahi los nombres aparecen mencionados en prosa, asi que
--      buscar solo el nombre daria un falso positivo.
select p.proname,
       (pg_get_functiondef(p.oid) ilike '%flow._aplicar_promocion(%')      as usa_promociones,
       (pg_get_functiondef(p.oid) ilike '%flow.calcular_precio_turno(%')   as usa_precio_turno,
       (pg_get_functiondef(p.oid) ilike '%flow.calcular_precio_reserva(%') as usa_precio_servicio,
       p.prosecdef                                                          as es_definer
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'flow'
  and p.proname in ('bot_procesar_plan', 'bot_procesar_recurso_dia')
order by p.proname;

-- 4.c) `anon` no debe poder ejecutar ninguna de las dos.
select p.proname,
       has_function_privilege('anon', p.oid, 'EXECUTE') as anon_puede
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'flow'
  and p.proname in ('bot_procesar_plan', 'bot_procesar_recurso_dia')
order by p.proname;

-- 4.d) PRUEBA FUNCIONAL (manual, tras aplicar):
--   a) crear una promo activa con cupo para un servicio de cola
--      (`permite_reserva_directa = false`);
--   b) anotarse en la sala de espera de ese servicio;
--   c) disparar el bot:  select flow.bot_sweep();
--   d) comprobar que la agenda nueva lleva el precio CON descuento y que
--      `flow.promocion.cupo_usado` subio en 1.