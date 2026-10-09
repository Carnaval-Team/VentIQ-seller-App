-- ════════════════════════════════════════════════════════════════════════════
-- MIGRACION 34: EL BENEFICIO DE BIENVENIDA DESCUENTA DE VERDAD
-- ════════════════════════════════════════════════════════════════════════════
--
-- QUE HACE
--   Aplica el beneficio de bienvenida al PRECIO REAL, en los dos unicos caminos
--   donde hay un cliente identificado:
--     - `flow.cotizar_reserva`            -> la cotizacion que ve el cliente
--     - `flow.cliente_reservar_directo`   -> la reserva que se cobra
--
--   Hasta ahora el Home no podia anunciarlo (`HomeFeatures.beneficioBienvenida`
--   estaba en false) porque no existia nada que lo cobrara: habria sido el mismo
--   "20 % de descuento" inventado del Paso 5 otra vez.
--
-- ORDEN DE LOS DESCUENTOS (acordado en la 31)
--     1. precio de lista
--     2. menos la promocion
--     3. menos el beneficio de bienvenida SOBRE LO QUE QUEDA
--     4. total = greatest(lista - promo - bienvenida, 0)
--
--   El beneficio va SOBRE EL RESTO y no sobre la lista, para que los dos
--   descuentos no se solapen: con 35 de lista, 20 % de promo y 5 de bienvenida,
--   el total es 35 - 7 - 5 = 23, no 35 - 7 - 7 = 21.
--
--   El `monto_minimo` del beneficio se compara con el subtotal **despues de la
--   promocion**, que es lo que de verdad se va a pagar por el servicio. Es la
--   lectura conservadora: un minimo mas dificil de alcanzar es un minimo que no
--   se regala por accidente.
--
-- QUIEN recibe el descuento
--   `p_uuid_usuario`: **quien paga**. En una reserva para tercero, el titular de
--   la agenda es el tercero (`v_titular`), pero el regalo es de quien gasta. El
--   canje se anota a nombre del que paga, no del tercero.
--
-- QUIEN no lo recibe (y por que)
--   - `admin_crear_reserva_directa` (reserva presencial): ahi `auth.uid()` es el
--     ADMIN. Aplicarlo gastaria el beneficio DEL ADMIN por una venta de mostrador,
--     y una reserva presencial no tiene identidad de cliente a quien cobrarle.
--   - El camino del bot (sala de espera): cuando mueve a alguien a la agenda
--     nadie eligio una oferta, y el principio ya establecido es que ahi se cobra
--     precio de lista. Ademas el bot no debe gastar el unico regalo del cliente
--     sin que este lo sepa.
--
-- EL INTERRUPTOR GLOBAL
--   `_beneficio_bienvenida_aplicable` comprueba `flow.fidelidad_config.activa`.
--   Con el programa apagado (migracion 33) no hay descuento ni aunque el
--   beneficio siga activo: apagar la fidelidad apaga la seccion entera.
--
-- ── NOTA DE SEGURIDAD (heredada, no introducida aqui) ───────────────────────
--   `cliente_reservar_directo` NO comprueba `auth.uid() = p_uuid_usuario` (es
--   uno de los 3 RPC del IDOR conocida en plan.md 5.c, y se decidio posponerlo).
--   El beneficio hereda esa misma confianza: quien llame con el uuid de otro
--   podria gastarle el beneficio. No es un agujero nuevo y no amplia la
--   superficie -el atacante ya podia reservar y notificar a nombre de la
--   victima-, pero es una razon mas para aplicar el arreglo de una linea:
--       if auth.uid() is distinct from p_uuid_usuario then
--         return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
--       end if;
--   El dia que se aplique, el beneficio queda protegido sin tocar nada de aqui.
--
-- DEPENDE DE: 31 (tablas y helpers), 33 (`flow.fidelidad_config`).
--
-- REVERSIBILIDAD
--   drop function if exists flow._beneficio_bienvenida_aplicable(uuid, integer, varchar, numeric);
--   -- y volver a pegar `cotizar_reserva` y `cliente_reservar_directo` desde la
--   -- migracion 27 para quitarles el bloque del beneficio.
--   -- Los `beneficio_canje` ya anotados NO se borran: si se revierte, quedan
--   -- como historia (y correctamente impiden volver a gastar el beneficio).
-- ════════════════════════════════════════════════════════════════════════════

-- ── Comprobacion previa ─────────────────────────────────────────────────────
do $pre$
begin
  if to_regclass('flow.fidelidad_config') is null then
    raise exception 'Falta la migracion 33. Aplicala antes que la 34.';
  end if;

  if to_regclass('flow.beneficio_canje') is null
     or to_regclass('flow.beneficio_bienvenida') is null then
    raise exception 'Falta la migracion 31 (fidelidad). Aplicala antes que la 34.';
  end if;

  if to_regprocedure('flow._resolver_beneficio_bienvenida(uuid,integer,varchar)') is null then
    raise exception 'Falta flow._resolver_beneficio_bienvenida de la migracion 31.';
  end if;

  if to_regprocedure('flow.cliente_reservar_directo(uuid,integer,date,integer,jsonb,boolean,text,text,text,text,text,integer)') is null then
    raise exception 'Falta flow.cliente_reservar_directo. Sin ella no hay nada que modificar.';
  end if;
end
$pre$;

-- ══ 1. QUE BENEFICIO TOCA, Y CUANTO DESCUENTA ══════════════════════════════
--
-- Devuelve 0 o 1 fila. No consume nada: es de solo lectura, asi que
-- `cotizar_reserva` puede usarla sin gastar el beneficio del cliente.
--
-- El redondeo del porcentaje es HACIA ABAJO (`floor`) y luego a 2 decimales:
-- nunca se descuenta de mas. El descuento por monto se limita al subtotal, para
-- que no pueda dejar el total en negativo.

create or replace function flow._beneficio_bienvenida_aplicable(
  p_uuid_usuario uuid,
  p_id_entidad   integer,
  p_moneda       varchar,
  p_subtotal     numeric
)
returns table (
  id_beneficio integer,
  titulo       varchar,
  tipo         varchar,
  valor        numeric,
  descuento    numeric
)
language sql
stable
set search_path to 'flow','public'
as $function$
  with cfg as (
    select coalesce(
      (select c.activa from flow.fidelidad_config c where c.id = 1), true
    ) as activa
  ),
  b as (
    select * from flow._resolver_beneficio_bienvenida(
      p_uuid_usuario, p_id_entidad, p_moneda
    )
  )
  select b.id_beneficio, b.titulo, b.tipo, b.valor,
         round(
           case
             when b.tipo = 'porcentaje'
               then floor(coalesce(p_subtotal, 0) * b.valor / 100)
             else least(b.valor, coalesce(p_subtotal, 0))
           end,
           2
         ) as descuento
  from b, cfg
  where cfg.activa
    and p_uuid_usuario is not null
    and b.id_beneficio is not null
    and coalesce(p_subtotal, 0) > 0
    and (b.monto_minimo is null or coalesce(p_subtotal, 0) >= b.monto_minimo);
$function$;

-- ══ 2. LA COTIZACION QUE VE EL CLIENTE ═════════════════════════════════════
--
-- OJO: `cotizar_reserva` es STABLE (comprobado en `pg_proc.provolatile`). Se
-- recrea CON ese modificador; omitirlo la volveria volatil y cambiaria como la
-- planifica el planner. Se conserva tambien su `search_path`.
--
-- Se le anade `id_entidad` (para resolver beneficios por entidad) y el bloque
-- del beneficio. NO lo consume: solo informa de lo que se pagaria ahora mismo.
-- Se anaden tres campos nuevos al JSON (`descuento_beneficio`, `id_beneficio`,
-- `beneficio_titulo`); `precio_lista`, `descuento`, `id_promocion` y
-- `promo_titulo` siguen significando lo mismo, asi que la app vieja no se rompe.

create or replace function flow.cotizar_reserva(
  p_uuid_usuario uuid,
  p_id_local_servicio integer,
  p_datos jsonb default null,
  p_moneda text default null,
  p_cantidad integer default 1,
  p_id_turno integer default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'flow','public'
as $function$
declare
  v_id_servicio   integer;
  v_id_entidad    integer;
  v_lista         numeric;
  v_moneda        varchar;
  v_unit          numeric;
  v_descuento     numeric := 0;
  v_subtotal      numeric;
  v_promo_id      integer;
  v_promo_titulo  varchar;
  v_id_beneficio  integer;
  v_ben_titulo    varchar;
  v_ben_descuento numeric := 0;
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;

  -- `left join`: si un local no tuviera fila en app_dat_locales, esto no debe
  -- cambiar el mensaje 'El servicio no existe'. Simplemente no habria entidad y
  -- solo aplicarian los beneficios globales.
  select ls.id_servicio, l.id_entidad
    into v_id_servicio, v_id_entidad
  from flow.local_servicio ls
  left join flow.app_dat_locales l on l.id = ls.id_local
  where ls.id = p_id_local_servicio;

  if v_id_servicio is null then
    return jsonb_build_object('ok', false, 'error', 'El servicio no existe');
  end if;

  -- Con turno el precio puede venir del turno (transporte); sin turno, del
  -- servicio. Se obtiene el precio de LISTA por el camino que corresponda.
  if p_id_turno is not null then
    select cp.precio_total, cp.moneda, cp.precio_unit
      into v_lista, v_moneda, v_unit
    from flow.calcular_precio_turno(
      v_id_servicio, p_id_turno, coalesce(p_datos, '{}'::jsonb),
      p_moneda, p_cantidad
    ) cp;
  else
    select cp.precio_total, cp.moneda, cp.precio_unit
      into v_lista, v_moneda, v_unit
    from flow.calcular_precio_reserva(
      v_id_servicio, coalesce(p_datos, '{}'::jsonb), p_moneda, p_cantidad
    ) cp;
  end if;

  v_lista := coalesce(v_lista, 0);

  -- UNA sola resolucion de promocion, igual que al cobrar. Esta funcion no
  -- consume cupo: solo informa de lo que se pagaria ahora mismo.
  --
  -- Se leen escalares y no un `record`: si no hay promo aplicable la consulta
  -- no devuelve filas, y acceder a un campo de un record sin asignar lanza
  -- "record is not assigned yet".
  if v_lista > 0 then
    select pr.id_promocion, pr.descuento, pr.titulo
      into v_promo_id, v_descuento, v_promo_titulo
    from flow._resolver_promocion(p_id_local_servicio, v_id_servicio, v_lista) pr;
    v_descuento := coalesce(v_descuento, 0);
  end if;

  v_subtotal := greatest(v_lista - v_descuento, 0);

  -- Beneficio de bienvenida SOBRE LO QUE QUEDA tras la promocion.
  if v_subtotal > 0 then
    select b.id_beneficio, b.titulo, b.descuento
      into v_id_beneficio, v_ben_titulo, v_ben_descuento
    from flow._beneficio_bienvenida_aplicable(
      p_uuid_usuario, v_id_entidad, v_moneda, v_subtotal
    ) b;
    v_ben_descuento := coalesce(v_ben_descuento, 0);
  end if;

  return jsonb_build_object(
    'ok', true,
    'precio_lista', v_lista,
    'precio_total', greatest(v_subtotal - v_ben_descuento, 0),
    'descuento',    v_descuento,
    'moneda',       coalesce(v_moneda, 'USD'),
    'precio_unit',  coalesce(v_unit, 0),
    'id_promocion', v_promo_id,
    'promo_titulo', v_promo_titulo,
    'descuento_beneficio', v_ben_descuento,
    'id_beneficio',        v_id_beneficio,
    'beneficio_titulo',    v_ben_titulo
  );
end;
$function$;

-- ══ 3. LA RESERVA QUE SE COBRA ═════════════════════════════════════════════
--
-- Copiada del cuerpo VIVO (no de los archivos: pueden estar desviados) y con
-- tres cambios, todos marcados con `BENEFICIO`:
--   1. `id_entidad` en el primer select, via `left join`.
--   2. El bloque de reclamo + descuento, DESPUES de las dos ramas de precio, para
--      que cubra turno y legacy de una sola vez sin tocar `_aplicar_promocion`
--      ni `_precio_con_promocion`.
--   3. El enlace del canje con el `id_agenda` y los campos nuevos del return.
--
-- El reclamo del beneficio usa `insert ... on conflict (uuid_usuario) do nothing`
-- + `row_count`, ANTES de descontar. Si dos reservas compiten, solo la primera
-- gana el descuento y la segunda cobra sin el, sin fallar: se prefiere cobrar de
-- mas y no bloquear una reserva por un regalo. Es el mismo patron que el cupo de
-- las promociones.
--
-- Si algo revienta despues, el `exception when others` de la funcion revierte
-- todo el bloque (PL/pgSQL envuelve el begin/end en un savepoint), asi que el
-- canje no queda anotado sin su reserva.

create or replace function flow.cliente_reservar_directo(
  p_uuid_usuario uuid,
  p_id_local_servicio integer,
  p_fecha date,
  p_cantidad integer default null,
  p_datos_adicionales jsonb default null,
  p_para_tercero boolean default false,
  p_t_nombre text default null,
  p_t_apellidos text default null,
  p_t_ci text default null,
  p_t_telefono text default null,
  p_moneda text default null,
  p_id_turno integer default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'flow','public'
as $function$
declare
  v_permite          boolean;
  v_cantidad_default integer;
  v_cantidad_max     integer;
  v_plan_id          bigint;
  v_disponibles      integer;
  v_estado           integer;
  v_id_agenda        integer;
  v_fecha_ts         timestamp without time zone;
  v_titular          uuid;
  v_nombre_servicio  text;
  v_nombre_local     text;
  v_saludo           text;
  v_cant             integer;
  v_id_servicio      integer;
  v_id_entidad       integer;
  v_precio_total     numeric;
  v_moneda           varchar;
  v_desc             jsonb;
  v_cotizacion       jsonb;
  -- BENEFICIO
  v_id_beneficio     integer;
  v_ben_titulo       varchar;
  v_ben_descuento    numeric;
  v_canje_filas      integer;
begin
  if p_uuid_usuario is null or p_id_local_servicio is null or p_fecha is null then
    return jsonb_build_object('ok', false, 'error', 'parametros obligatorios faltantes');
  end if;

  perform pg_advisory_xact_lock(hashtext('flow.sala_espera'), p_id_local_servicio);

  -- BENEFICIO: se anade `l.id_entidad` con left join.
  select ls.permite_reserva_directa, ls.cantidad_default,
         ls.cantidad_max_capacidad, ls.id_servicio, l.id_entidad
    into v_permite, v_cantidad_default, v_cantidad_max, v_id_servicio, v_id_entidad
  from flow.local_servicio ls
  left join flow.app_dat_locales l on l.id = ls.id_local
  where ls.id = p_id_local_servicio;

  if v_permite is null then
    return jsonb_build_object('ok', false, 'error', 'El servicio no existe');
  end if;
  if v_permite is not true then
    return jsonb_build_object('ok', false, 'error', 'Reserva directa no habilitada para este servicio');
  end if;

  if p_id_turno is not null then
    if not exists (
      select 1 from flow.turno t
      join flow.recurso r on r.id = t.id_recurso and r.activo
      where t.id = p_id_turno and t.activo and r.id_local_servicio = p_id_local_servicio
    ) then
      return jsonb_build_object('ok', false, 'error', 'Turno invalido para este servicio');
    end if;
  end if;

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

  v_cant := coalesce(p_cantidad, v_cantidad_default, 1);
  if v_cant < 1 then
    return jsonb_build_object('ok', false, 'error', 'La cantidad debe ser al menos 1');
  end if;
  if v_cant > v_cantidad_max then
    return jsonb_build_object('ok', false, 'error',
      'La cantidad maxima por reserva es ' || v_cantidad_max);
  end if;

  select id into v_estado from flow.nom_estado_agenda where nombre = 'Reservado' limit 1;
  if v_estado is null then
    return jsonb_build_object('ok', false, 'error', 'falta el estado Reservado (correr migracion 03)');
  end if;

  if exists (
    select 1 from flow.agenda a
    where a.uuid_usuario = v_titular
      and a.id_local_servicio = p_id_local_servicio
      and a.id_estado = v_estado
      and (a.fecha_hora_reserva at time zone 'America/Havana')::date = p_fecha
      and a.id_turno is not distinct from p_id_turno
  ) then
    return jsonb_build_object('ok', false, 'error',
      case when v_titular = p_uuid_usuario
           then 'Ya tienes una reserva ese dia'
           else 'Esa persona ya tiene una reserva ese dia' end);
  end if;

  v_fecha_ts := (make_timestamp(extract(year from p_fecha)::int,
                                extract(month from p_fecha)::int,
                                extract(day from p_fecha)::int, 12, 0, 0));

  if p_id_turno is not null then
    v_desc := flow._descontar_tramos_turno(p_id_turno, p_fecha, v_cant);
    if (v_desc ->> 'ok') <> 'true' then
      return jsonb_build_object('ok', false, 'error', v_desc ->> 'error');
    end if;
    -- Transporte: el precio puede venir del turno. Se calcula el precio de
    -- lista por turno y se pasa al MISMO envoltorio que el camino normal, para
    -- que tambien CONSUMA CUPO. Si aqui solo se restara el descuento, el
    -- transporte aplicaria la promo sin gastar cupo y se agotaria infinitas
    -- veces.
    select flow._aplicar_promocion(
             p_id_local_servicio, v_id_servicio,
             cp.precio_total, cp.moneda, cp.precio_unit, true
           )
      into v_cotizacion
    from flow.calcular_precio_turno(
      v_id_servicio, p_id_turno, coalesce(p_datos_adicionales, '{}'::jsonb), p_moneda, v_cant
    ) cp;
  else
    -- ── Camino legacy: plan_servicios ──
    select ps.id, (ps.cantidad - ps.agendados) into v_plan_id, v_disponibles
    from flow.plan_servicios ps
    where ps.id_local_servicio = p_id_local_servicio
      and ps.cantidad is not null
      and ps.agendados < ps.cantidad
      and (ps.fecha at time zone 'America/Havana')::date = p_fecha
    order by ps.id
    limit 1
    for update;

    if v_plan_id is null then
      return jsonb_build_object('ok', false, 'error', 'No hay turnos disponibles');
    end if;
    if v_cant > v_disponibles then
      return jsonb_build_object('ok', false,
        'error', 'No hay suficientes turnos (quedan ' || v_disponibles || ')');
    end if;

    v_cotizacion := flow._precio_con_promocion(
      v_id_servicio, p_id_local_servicio, p_datos_adicionales, p_moneda, v_cant, true
    );
  end if;

  if (v_cotizacion ->> 'ok') = 'false' then
    return jsonb_build_object('ok', false,
      'error', v_cotizacion ->> 'error',
      'codigo', v_cotizacion ->> 'codigo');
  end if;

  v_precio_total := (v_cotizacion ->> 'precio_total')::numeric;
  v_moneda       := (v_cotizacion ->> 'moneda')::varchar;

  -- ── BENEFICIO: reclamo + descuento ──────────────────────────────────────
  -- Despues de las dos ramas, asi que cubre turno y legacy a la vez.
  select b.id_beneficio, b.titulo, b.descuento
    into v_id_beneficio, v_ben_titulo, v_ben_descuento
  from flow._beneficio_bienvenida_aplicable(
    p_uuid_usuario, v_id_entidad, v_moneda, v_precio_total
  ) b;

  if coalesce(v_ben_descuento, 0) > 0 then
    insert into flow.beneficio_canje
      (uuid_usuario, id_beneficio, id_entidad, moneda, monto_descontado)
    values
      (p_uuid_usuario, v_id_beneficio, v_id_entidad, v_moneda, v_ben_descuento)
    on conflict (uuid_usuario) do nothing;

    get diagnostics v_canje_filas = row_count;

    if v_canje_filas = 1 then
      v_precio_total := greatest(v_precio_total - v_ben_descuento, 0);
    else
      -- Otra reserva simultanea se llevo el beneficio: se cobra sin el.
      v_id_beneficio  := null;
      v_ben_titulo    := null;
      v_ben_descuento := 0;
    end if;
  end if;

  insert into flow.agenda
    (uuid_usuario, id_local_servicio, id_estado, fecha_hora_reserva,
     cantidad, datos_adicionales, reservado_por, precio_total, moneda, id_turno)
  values
    (v_titular, p_id_local_servicio, v_estado, v_fecha_ts,
     v_cant, p_datos_adicionales, p_uuid_usuario, v_precio_total, v_moneda, p_id_turno)
  returning id into v_id_agenda;

  -- BENEFICIO: enlazar el canje con la reserva. El insert de arriba no podia
  -- saber el id de la agenda todavia.
  if v_id_beneficio is not null then
    update flow.beneficio_canje
       set id_agenda = v_id_agenda
     where uuid_usuario = p_uuid_usuario
       and id_agenda is null;
  end if;

  if p_id_turno is null then
    update flow.plan_servicios set agendados = agendados + v_cant where id = v_plan_id;
  end if;

  select s.nombre, l.nombre into v_nombre_servicio, v_nombre_local
  from flow.local_servicio ls
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  join flow.app_dat_locales   l on l.id = ls.id_local
  where ls.id = p_id_local_servicio;

  v_saludo := case
    when extract(hour from current_timestamp) between 5 and 11 then 'Buenos dias'
    when extract(hour from current_timestamp) between 12 and 18 then 'Buenas tardes'
    else 'Buenas noches'
  end;

  insert into flow.notificaciones
    (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
  select
    p_uuid_usuario, 'reserva', 'Reservacion confirmada',
    v_saludo || ', '
      || coalesce(nullif(trim(p.nombre || ' ' || p.apellidos), ''), 'estimado cliente')
      || ', se ha realizado satisfactoriamente '
      || case when v_cant > 1 then v_cant || ' reservaciones' else 'su reservacion' end
      || case when coalesce(p_para_tercero, false)
              then ' a nombre de ' || coalesce(nullif(trim(coalesce(p_t_nombre,'') || ' ' || coalesce(p_t_apellidos,'')), ''), 'un tercero')
              else '' end
      || ' para el local "' || coalesce(v_nombre_local, 'local')
      || '" el servicio "' || coalesce(v_nombre_servicio, 'servicio')
      || '" para la fecha ' || to_char(v_fecha_ts, 'DD/MM/YYYY') || '.',
    p_id_local_servicio, v_id_agenda,
    jsonb_build_object('fecha', v_fecha_ts, 'servicio', v_nombre_servicio,
                       'local', v_nombre_local, 'cantidad', v_cant, 'id_turno', p_id_turno)
  from (select 1) x
  left join flow.perfil p on p.uuid_usuario = p_uuid_usuario;

  return jsonb_build_object('ok', true,
    'data', jsonb_build_object(
      'id_agenda', v_id_agenda,
      'fecha',     to_char(v_fecha_ts, 'YYYY-MM-DD'),
      'cantidad',  v_cant,
      'id_turno',  p_id_turno,
      'precio_total', v_precio_total,
      'moneda',       v_moneda,
      -- BENEFICIO: campos nuevos, informativos para la app.
      'descuento_beneficio', coalesce(v_ben_descuento, 0),
      'id_beneficio',        v_id_beneficio,
      'beneficio_titulo',    v_ben_titulo
    ));
exception
  when others then
    return jsonb_build_object('ok', false, 'error', sqlerrm, 'sqlstate', sqlstate);
end;
$function$;

-- ══ 4. PERMISOS DE EJECUCION ════════════════════════════════════════════════
-- Idioma de la migracion 27. `create or replace` CONSERVA el ACL existente, asi
-- que estas lineas son sobre todo defensivas; el helper interno si es nuevo y
-- hay que cerrarlo (Supabase le habra concedido EXECUTE a `authenticated` por
-- privilegios por defecto en el CREATE).

revoke all on function flow._beneficio_bienvenida_aplicable(uuid, integer, varchar, numeric)
  from public, anon, authenticated;
grant execute on function flow._beneficio_bienvenida_aplicable(uuid, integer, varchar, numeric)
  to service_role;

revoke all on function flow.cotizar_reserva(uuid, integer, jsonb, text, integer, integer)
  from public, anon;
grant execute on function flow.cotizar_reserva(uuid, integer, jsonb, text, integer, integer)
  to authenticated, service_role;

revoke all on function flow.cliente_reservar_directo(uuid, integer, date, integer, jsonb, boolean, text, text, text, text, text, integer)
  from public, anon;
grant execute on function flow.cliente_reservar_directo(uuid, integer, date, integer, jsonb, boolean, text, text, text, text, text, integer)
  to authenticated, service_role;

notify pgrst, 'reload schema';

-- ══ 5. VERIFICACION ═════════════════════════════════════════════════════════

-- 5.a Las tres funciones tienen el modificador correcto. `cotizar_reserva` DEBE
--     seguir siendo STABLE (`s`) y las otras dos volatiles (`v`).
select p.proname, p.prosecdef as definer,
       p.provolatile as volatilidad,   -- cotizar_reserva: 's'; las otras: 'v'
       coalesce(array_to_string(p.proconfig, ' | '), '(sin config)') as config
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'flow'
  and p.proname in ('_beneficio_bienvenida_aplicable','cotizar_reserva',
                    'cliente_reservar_directo')
order by p.proname;

-- 5.b El helper interno NO queda al alcance del cliente.
select p.proname,
       has_function_privilege('authenticated', p.oid, 'execute') as authenticated_puede,
       p.proacl
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'flow'
  and p.proname = '_beneficio_bienvenida_aplicable';
-- Esperado: authenticated_puede = FALSE y proacl sin `authenticated`.

-- 5.c Las firmas no cambiaron (misma identidad para la app).
select p.proname, pg_get_function_arguments(p.oid) as args
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'flow'
  and p.proname in ('cotizar_reserva','cliente_reservar_directo');
-- Esperado: los mismos 6 y 12 argumentos con sus DEFAULT, igual que antes.

-- 5.d El interruptor global apaga el beneficio aunque el beneficio este activo.
--     (Se prueba sin escribir nada: solo lectura.)
select
  (select count(*) from flow.beneficio_bienvenida where activo) as beneficios_activos,
  (select count(*) from flow._beneficio_bienvenida_aplicable(
     '047a7f26-67bb-444b-848b-22c5267ba9e8'::uuid, 4, 'USD', 35)) as con_fidelidad_encendida;
-- Con la fidelidad apagada (admin_guardar_fidelidad_config con false) la segunda
-- columna debe dar 0 aunque la primera no lo sea. Volver a encenderla al terminar.

-- ══ 6. PRUEBA DE ROLLBACK (manual; no deja nada) ════════════════════════════
-- Pega este bloque aparte. Al final hace ROLLBACK: no queda ni el beneficio ni
-- la reserva ni el canje. `fallan` debe ser 0.
--
-- Nota: `cotizar_reserva` NO se puede probar desde el SQL Editor porque exige
-- sesion (`auth.uid()`), y aqui es NULL: devolveria 'Sesion no valida'. Se prueba
-- el helper, que es donde vive la aritmetica, y `cliente_reservar_directo`, que
-- no comprueba sesion (el IDOR conocido).
--
-- begin;
--
-- create temp table _r (n int, caso text, esperado text, obtenido text, ok boolean) on commit drop;
--
-- insert into flow.beneficio_bienvenida (titulo, descripcion, tipo, valor, moneda, activo)
-- values ('Prueba 20%', 'test', 'porcentaje', 20, 'USD', true);
--
-- -- 1. 20 % sobre 35 = 7 (floor)
-- insert into _r
-- select 1, '20% de 35 = 7',
--        '7',
--        (select b.descuento::text from flow._beneficio_bienvenida_aplicable(
--           '047a7f26-67bb-444b-848b-22c5267ba9e8'::uuid, 4, 'USD', 35) b),
--        (select b.descuento = 7 from flow._beneficio_bienvenida_aplicable(
--           '047a7f26-67bb-444b-848b-22c5267ba9e8'::uuid, 4, 'USD', 35) b);
--
-- -- 2. El redondeo es hacia abajo: 20 % de 33 = 6.6, no 7
-- insert into _r
-- select 2, '20% de 33 = 6.6 (hacia abajo)',
--        '6.6',
--        (select b.descuento::text from flow._beneficio_bienvenida_aplicable(
--           '047a7f26-67bb-444b-848b-22c5267ba9e8'::uuid, 4, 'USD', 33) b),
--        (select b.descuento = 6.6 from flow._beneficio_bienvenida_aplicable(
--           '047a7f26-67bb-444b-848b-22c5267ba9e8'::uuid, 4, 'USD', 33) b);
--
-- -- 3. Reserva con turno: LS 12, turno 20, 35.00 de lista, sin promo -> 28.
-- --    El CTE es OBLIGATORIO: sin el, las dos referencias llamarian a la funcion
-- --    DOS veces y la segunda reserva fallaria con "Ya tienes una reserva ese dia".
-- insert into _r
-- with llamada as (
--   select flow.cliente_reservar_directo(
--            '047a7f26-67bb-444b-848b-22c5267ba9e8'::uuid, 12, date '2026-10-14',
--            1, '{}'::jsonb, false, null, null, null, null, 'USD', 20
--          ) as j
-- )
-- select 3, 'reserva 35 - 7 = 28', '28',
--        (select j #>> '{data,precio_total}' from llamada),
--        (select (j #>> '{data,precio_total}')::numeric = 28 from llamada);
--
-- -- 4. El canje quedo anotado y enlazado con la agenda
-- insert into _r
-- select 4, 'canje anotado con id_agenda',
--        'true',
--        (select (c.id_agenda is not null)::text from flow.beneficio_canje c
--          where c.uuid_usuario = '047a7f26-67bb-444b-848b-22c5267ba9e8'),
--        (select c.id_agenda is not null from flow.beneficio_canje c
--          where c.uuid_usuario = '047a7f26-67bb-444b-848b-22c5267ba9e8');
--
-- -- 5. Segunda reserva (otro dia): ya NO hay beneficio -> precio de lista 35
-- insert into _r
-- with llamada as (
--   select flow.cliente_reservar_directo(
--            '047a7f26-67bb-444b-848b-22c5267ba9e8'::uuid, 12, date '2026-10-21',
--            1, '{}'::jsonb, false, null, null, null, null, 'USD', 21
--          ) as j
-- )
-- select 5, 'segunda reserva sin descuento (35)', '35',
--        (select j #>> '{data,precio_total}' from llamada),
--        (select (j #>> '{data,precio_total}')::numeric = 35 from llamada);
--
-- -- 6. Control negativo: otro usuario no ve el beneficio del primero
-- insert into _r
-- select 6, 'otro usuario no hereda el beneficio',
--        '0',
--        (select count(*)::text from flow._beneficio_bienvenida_aplicable(
--           '1a78a129-c517-4f8f-915c-12c15f8a04ec'::uuid, 4, 'USD', 35)),
--        ((select count(*) from flow._beneficio_bienvenida_aplicable(
--           '1a78a129-c517-4f8f-915c-12c15f8a04ec'::uuid, 4, 'USD', 35)) = 0);
--
-- select n as "#", caso, esperado, obtenido, ok from _r order by n;
-- select count(*) filter (where not ok) as fallan from _r;
--
-- rollback;
-- ════════════════════════════════════════════════════════════════════════════