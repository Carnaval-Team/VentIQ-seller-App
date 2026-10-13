-- ════════════════════════════════════════════════════════════════════════════
-- MIGRACION 44: SUSCRIPCIONES — PREDICADO DE ENTIDAD ACTIVA, TRIAL Y ESTADO
-- ════════════════════════════════════════════════════════════════════════════
--
-- QUE HACE
--   1. `flow.entidad_activa(id_entidad)` — el UNICO predicado de "esta entidad
--      esta al dia".
--   2. Recomponer `flow._ls_disponible(id_local_servicio)` para que incluya ese
--      predicado. Con eso, una entidad impagada desaparece del catalogo del
--      cliente y no admite reservas, SIN tocar ninguna bandera `activo`.
--   3. Trial automatico al crear una entidad (trigger), con anti-abuso.
--   4. RPC de lectura para la app: estado de la entidad y planes activos.
--
-- POR QUE UN PREDICADO Y NO PONER `activo = false` EN LAS FILAS
--   Decision del usuario. La alternativa destructiva obliga a recorrer locales,
--   servicios y pares, a guardar un snapshot para restaurar y a decidir que hacer
--   si el admin habia apagado algo por su cuenta: al reactivar se le pisaria su
--   configuracion. Con el predicado:
--     · reactivar el pago reactiva todo AL INSTANTE y sin efectos secundarios;
--     · no hay ventana en la que la base quede a medias (mitad apagado, mitad no);
--     · `app_dat_locales.activo` sigue significando lo unico que debe significar:
--       "el admin decidio publicar o no esto".
--
-- POR QUE ES SEGURO COMPONERLO EN `_ls_disponible`
--   La migracion 40 lo dejo escrito: `_ls_disponible` es la UNICA definicion de
--   "este local-servicio es visible y reservable para el cliente", y TODOS los
--   RPC de cliente y el trigger `trg_agenda_ls_disponible` la usan. Tocar una
--   funcion en vez de N consultas es justo lo que evita que el feed diga
--   "visible" donde la reserva dice "no disponible".
--
-- POR QUE EL CORTE NO DEPENDE DEL CRON
--   `entidad_activa` compara FECHAS, no estados. Aunque el cron de expiracion no
--   corra (o se retrase), una entidad cuya gracia ya paso esta inactiva igual.
--   El cron solo (a) ordena el estado visible en el panel y (b) manda los avisos.
--   La correccion no se delega a un job.
--
-- POR QUE "SIN FILA = ACTIVA" (grandfathering)
--   Al aplicar esta migracion NINGUNA entidad existente tiene suscripcion. Si
--   "sin fila" fuera inactiva, la migracion apagaria TODAS las entidades en vivo
--   de golpe. Con grandfathering nada cambia de visibilidad hasta que haya una
--   fila, y el superadmin decide cuando inicializar el historico (RPC
--   `flow.admin_suscripcion_inicializar` en la migracion 46). Es la misma regla
--   que la migracion 40 con `default true`.
--
-- DEPENDE DE: migracion 43 (tablas, config, helper) y 40 (`_ls_disponible`).
--
-- REVERSIBILIDAD
--   -- volver a la version de `_ls_disponible` de la migracion 40:
--   create or replace function flow._ls_disponible(p_id_local_servicio integer)
--   returns boolean language sql stable
--   set search_path to 'flow','public' as $function$
--     select coalesce(l.activo,false) and coalesce(s.activo,false)
--        and coalesce(ls.activo,false)
--     from flow.local_servicio ls
--     join flow.app_dat_locales l on l.id = ls.id_local
--     join flow.app_dat_servicios s on s.id = ls.id_servicio
--     where ls.id = p_id_local_servicio;
--   $function$;
--   drop trigger if exists trg_entidad_suscripcion_trial on flow.entidad;
--   drop function if exists flow._suscripcion_trial_entidad();
--   drop function if exists flow.entidad_activa(integer);
--   drop function if exists flow.cliente_estado_suscripcion(integer);
--   drop function if exists flow.cliente_planes_suscripcion();
--
-- ORDEN: 44 va despues de 43 y antes de 45.
-- ════════════════════════════════════════════════════════════════════════════

-- ── Comprobacion previa ─────────────────────────────────────────────────────
do $pre$
begin
  if to_regclass('flow.suscripcion') is null
     or to_regclass('flow.suscripcion_config') is null then
    raise exception 'Falta la migracion 43 (tablas de suscripcion). Aplicala antes que la 44.';
  end if;

  if to_regprocedure('flow._ls_disponible(integer)') is null then
    raise exception 'Falta flow._ls_disponible(integer) (migracion 40).';
  end if;
end
$pre$;

-- ══ 1. EL PREDICADO UNICO: "esta entidad esta al dia" ══════════════════════

create or replace function flow.entidad_activa(p_id_entidad integer)
returns boolean
language sql
stable
security definer
set search_path to 'flow', 'public'
as $function$
  select coalesce((
    select case
             -- Estados que significan "no hay derecho": inactiva sin mirar fechas.
             when s.estado in ('vencida','sin_plan','suspendida','cancelada')
               then false
             -- Estados vivos: manda la fecha. `fecha_gracia_fin` es el corte real.
             else coalesce(s.fecha_gracia_fin, s.fecha_vencimiento) > now()
           end
    from flow.suscripcion s
    where s.id_entidad = p_id_entidad
    order by
      -- Primero las filas vivas (si hay una, es la que gobierna); despues la
      -- mas reciente. El indice unico parcial de la 43 garantiza que haya a lo
      -- sumo UNA viva.
      (s.estado in ('trial','activa','en_gracia','sin_plan','suspendida')) desc,
      s.updated_at desc,
      s.id desc
    limit 1
  ), true);   -- SIN FILA = ACTIVA (grandfathering: ver cabecera)
$function$;

comment on function flow.entidad_activa(integer) is
  'UNICA definicion de "esta entidad tiene suscripcion vigente". La componen _ls_disponible y los RPC de suscripcion. Sin fila de suscripcion devuelve TRUE (grandfathering: la migracion no apaga nada).';

-- `anon` incluido a proposito: `_ls_disponible` es `security invoker` y el catalogo
-- de Flow se puede navegar antes de iniciar sesion. Si `anon` no pudiera ejecutar
-- `entidad_activa`, `_ls_disponible` fallaria con "permission denied" y el
-- catalogo entero dejaria de responder. Lo unico que se filtra es un booleano.
-- Se revoca de `public` para no dejar el EXECUTE implicito que Postgres concede
-- a toda funcion nueva.
revoke all on function flow.entidad_activa(integer) from public;
grant execute on function flow.entidad_activa(integer) to anon, authenticated, service_role;

-- ══ 2. `_ls_disponible` v2: ahora tambien mira la suscripcion de la entidad ═

create or replace function flow._ls_disponible(p_id_local_servicio integer)
returns boolean
language sql
stable
set search_path to 'flow', 'public'
as $function$
  select coalesce(l.activo, false)
     and coalesce(s.activo, false)
     and coalesce(ls.activo, false)
     -- Lo nuevo: la entidad dueña del local debe estar al dia. `entidad_activa`
     -- es `security definer` a proposito: un cliente no puede leer
     -- `flow.suscripcion` por RLS, y sin definer veria "sin fila" en todas.
     and flow.entidad_activa(l.id_entidad)
  from flow.local_servicio ls
  join flow.app_dat_locales   l on l.id = ls.id_local
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  where ls.id = p_id_local_servicio;
$function$;

comment on function flow._ls_disponible(integer) is
  'UNICA definicion de "este local-servicio es visible y reservable para el cliente". Incluye la suscripcion de la entidad (migracion 44).';

-- ══ 3. TRIAL AUTOMATICO AL CREAR LA ENTIDAD ════════════════════════════════
--
-- Reglas (decisiones del usuario):
--   · `trial_auto = true`  -> la entidad nueva recibe `trial_meses_default` meses.
--   · `trial_por_usuario`  -> un owner solo recibe UN trial. Las entidades
--     siguientes nacen en `sin_plan`: activas en el sistema pero sin derecho,
--     es decir bloqueadas hasta pagar. El superadmin puede acreditarlas a mano.
--   · `trial_auto = false` -> no se crea fila (la entidad queda como hoy: activa)
--     y el superadmin acredita cuando quiera. No se bloquea a nadie por apagar
--     el otorgamiento automatico.
--
-- El trigger es `security definer`: corre en el INSERT de `flow.entidad` y debe
-- poder escribir suscripcion y movimiento aunque el que inserta sea el propio
-- usuario recien registrado (que no tiene permisos sobre esas tablas).

create or replace function flow._suscripcion_trial_entidad()
returns trigger
language plpgsql
security definer
set search_path to 'flow', 'public'
as $function$
declare
  -- `%rowtype` y no `record`: con `record` anonimo, un SELECT INTO sin filas
  -- deja la variable SIN ASIGNAR y cualquier lectura revienta con "record is not
  -- assigned yet". Con `%rowtype` los campos quedan NULL y `not found` es fiable.
  v_cfg        flow.suscripcion_config%rowtype;
  v_ya_trial   boolean := false;
  v_dias       integer;
  v_venc       timestamptz;
  v_gracia     timestamptz;
  v_susc_id    bigint;
begin
  select c.* into v_cfg
  from flow.suscripcion_config c
  where c.id = 1;

  -- Sin configuracion no se inventa nada: la entidad queda sin fila (activa por
  -- grandfathering) y el superadmin decide.
  if not found then
    return new;
  end if;

  -- El otorgamiento automatico esta apagado: no se bloquea a nadie.
  if not coalesce(v_cfg.trial_auto, false)
     or coalesce(v_cfg.trial_meses_default, 0) <= 0 then
    return new;
  end if;

  if coalesce(v_cfg.trial_por_usuario, false) then
    select exists (
      select 1
      from flow.suscripcion s
      join flow.entidad e on e.id = s.id_entidad
      where e.owner_uuid = new.owner_uuid
        and s.origen = 'trial'
    ) into v_ya_trial;
  end if;

  if v_ya_trial then
    -- Anti-abuso: esta entidad no recibe meses gratis. Nace bloqueada hasta que
    -- pague; el superadmin puede acreditarla a mano si el caso lo justifica.
    insert into flow.suscripcion
      (id_entidad, id_plan, estado, fecha_inicio, fecha_vencimiento,
       fecha_gracia_fin, origen, notas)
    values
      (new.id, null, 'sin_plan', now(), now(), now(), 'trial',
       'Sin trial: el owner ya recibio meses gratis en otra entidad')
    returning id into v_susc_id;

    insert into flow.suscripcion_movimiento
      (id_entidad, id_suscripcion, tipo, dias, fecha_desde, fecha_hasta, motivo)
    values
      (new.id, v_susc_id, 'ajuste', 0, now(), now(),
       'Entidad creada sin trial por anti-abuso (1 trial por usuario)');

    return new;
  end if;

  v_dias   := v_cfg.trial_meses_default * 30;
  v_venc   := now() + make_interval(days => v_dias);
  v_gracia := v_venc + make_interval(days => coalesce(v_cfg.dias_gracia, 7));

  insert into flow.suscripcion
    (id_entidad, id_plan, estado, fecha_inicio, fecha_vencimiento,
     fecha_gracia_fin, origen, notas)
  values
    (new.id, null, 'trial', now(), v_venc, v_gracia, 'trial',
     'Trial automatico: ' || v_dias || ' dias')
  returning id into v_susc_id;

  insert into flow.suscripcion_movimiento
    (id_entidad, id_suscripcion, tipo, dias, fecha_desde, fecha_hasta, motivo)
  values
    (new.id, v_susc_id, 'trial', v_dias, now(), v_venc,
     'Trial automatico al crear la entidad');

  return new;
end;
$function$;

comment on function flow._suscripcion_trial_entidad() is
  'Trigger AFTER INSERT en flow.entidad: otorga el trial configurado, o deja la entidad en sin_plan si el owner ya consumio su trial.';

drop trigger if exists trg_entidad_suscripcion_trial on flow.entidad;
create trigger trg_entidad_suscripcion_trial
  after insert on flow.entidad
  for each row execute function flow._suscripcion_trial_entidad();

-- ══ 4. LECTURA PARA LA APP ═════════════════════════════════════════════════

-- Estado completo de la suscripcion de una entidad, listo para pintar.
create or replace function flow.cliente_estado_suscripcion(p_id_entidad integer)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'flow', 'public'
as $function$
declare
  -- Escalares y no un `record`: con un record anonimo, un SELECT INTO sin filas
  -- deja la variable sin asignar y leerla revienta con "record is not assigned
  -- yet". Con escalares, "no hay fila" es NULL y se comprueba sin drama.
  v_id         bigint;
  v_estado_g   text;
  v_inicio     timestamptz;
  v_venc       timestamptz;
  v_gracia_fin timestamptz;
  v_origen     text;
  v_plan_cod   text;
  v_plan_nom   text;
  v_dur_dias   integer;
  v_precio     numeric;
  v_moneda     text;
  v_activa     boolean;
  v_gracia     timestamptz;
  v_dias_rest  integer;
  v_dias_grac  integer;
  v_estado     text;
  v_mensaje    text;
begin
  if not (flow._susc_caller_ve_entidad(p_id_entidad)
          or public.fn_is_superadmin_full_access()) then
    return jsonb_build_object('ok', false, 'error', 'No tiene acceso a esta entidad');
  end if;

  v_activa := flow.entidad_activa(p_id_entidad);

  select s.id, s.estado, s.fecha_inicio, s.fecha_vencimiento, s.fecha_gracia_fin,
         s.origen,
         p.codigo, p.nombre, p.duracion_dias, p.precio, p.moneda
    into v_id, v_estado_g, v_inicio, v_venc, v_gracia_fin,
         v_origen,
         v_plan_cod, v_plan_nom, v_dur_dias, v_precio, v_moneda
  from flow.suscripcion s
  left join flow.suscripcion_plan p on p.id = s.id_plan
  where s.id_entidad = p_id_entidad
  order by
    (s.estado in ('trial','activa','en_gracia','sin_plan','suspendida')) desc,
    s.updated_at desc,
    s.id desc
  limit 1;

  -- Sin fila: grandfathering. Se reporta activa y sin vencimiento conocido.
  if v_id is null then
    return jsonb_build_object(
      'ok', true,
      'data', jsonb_build_object(
        'id_entidad',        p_id_entidad,
        'estado',            'sin_suscripcion',
        'activa',            true,
        'es_trial',          false,
        'en_gracia',         false,
        'plan_codigo',       null,
        'plan_nombre',       null,
        'duracion_dias',     null,
        'precio',            null,
        'moneda',            null,
        'fecha_inicio',      null,
        'fecha_vencimiento', null,
        'fecha_gracia_fin',  null,
        'dias_restantes',    null,
        'dias_gracia',       null,
        'mensaje',           'Esta entidad todavia no tiene suscripcion registrada.'
      )
    );
  end if;

  v_estado    := v_estado_g;
  v_gracia    := coalesce(v_gracia_fin, v_venc);
  v_dias_rest := case when v_venc is null then null
                      else ceil(extract(epoch from (v_venc - now())) / 86400.0)::integer
                 end;
  v_dias_grac := case when v_gracia is null then null
                      else ceil(extract(epoch from (v_gracia - now())) / 86400.0)::integer
                 end;

  -- El estado que pinta la UI se deriva de las fechas, no del texto guardado:
  -- el cron puede ir con retraso y el aviso tiene que ser exacto igual.
  if not v_activa then
    v_estado := case
                  when v_estado_g = 'suspendida' then 'suspendida'
                  when v_estado_g = 'sin_plan'   then 'sin_plan'
                  else 'vencida'
                end;
    v_mensaje := case
                   when v_estado_g = 'suspendida'
                     then 'La suscripcion de esta entidad esta suspendida por el administrador.'
                   when v_estado_g = 'sin_plan'
                     then 'Esta entidad no tiene un plan activo. Compra un plan para publicarla.'
                   else 'La suscripcion vencio y se agoto el margen de gracia. Esta entidad no se muestra ni admite reservas.'
                 end;
  elsif v_gracia is not null and v_gracia > now() and v_venc <= now() then
    v_estado  := 'en_gracia';
    v_mensaje := 'La suscripcion vencio. Tiene ' || coalesce(v_dias_grac, 0)
              || ' dia(s) de margen antes de que la entidad se desactive.';
  elsif v_estado_g = 'trial' then
    v_mensaje := 'Periodo de prueba: quedan ' || coalesce(v_dias_rest, 0) || ' dia(s).';
  else
    v_mensaje := 'Suscripcion activa: quedan ' || coalesce(v_dias_rest, 0) || ' dia(s).';
  end if;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id_entidad',        p_id_entidad,
      'estado',            v_estado,
      'estado_guardado',   v_estado_g,
      'activa',            v_activa,
      'es_trial',          v_estado_g = 'trial',
      'en_gracia',         v_estado = 'en_gracia',
      'plan_codigo',       v_plan_cod,
      'plan_nombre',       v_plan_nom,
      'duracion_dias',     v_dur_dias,
      'precio',            v_precio,
      'moneda',            v_moneda,
      'fecha_inicio',      v_inicio,
      'fecha_vencimiento', v_venc,
      'fecha_gracia_fin',  v_gracia_fin,
      'dias_restantes',    v_dias_rest,
      'dias_gracia',       v_dias_grac,
      'mensaje',           v_mensaje
    )
  );
end;
$function$;

comment on function flow.cliente_estado_suscripcion(integer) is
  'Estado de suscripcion de una entidad para el panel del owner/admin. Deriva el estado de las FECHAS: el aviso es exacto aunque el cron vaya con retraso.';

-- Planes disponibles para comprar. Solo los activos.
create or replace function flow.cliente_planes_suscripcion()
returns jsonb
language sql
stable
security definer
set search_path to 'flow', 'public'
as $function$
  select jsonb_build_object(
    'ok', true,
    'data', coalesce(
      (select jsonb_agg(
                jsonb_build_object(
                  'id',            p.id,
                  'codigo',        p.codigo,
                  'nombre',        p.nombre,
                  'descripcion',   p.descripcion,
                  'duracion_dias', p.duracion_dias,
                  'precio',        p.precio,
                  'moneda',        p.moneda,
                  'limites',       p.limites,
                  'orden',         p.orden
                ) order by p.orden, p.precio, p.id)
         from flow.suscripcion_plan p
        where p.activo),
      '[]'::jsonb
    )
  );
$function$;

comment on function flow.cliente_planes_suscripcion() is
  'Planes de suscripcion activos, ordenados, para la pantalla "Mi suscripcion".';

revoke all on function flow.cliente_estado_suscripcion(integer) from public;
revoke all on function flow.cliente_planes_suscripcion() from public;
grant execute on function flow.cliente_estado_suscripcion(integer) to anon, authenticated, service_role;
grant execute on function flow.cliente_planes_suscripcion() to anon, authenticated, service_role;

-- ══ 5. VERIFICACION (ejecutar a mano despues de aplicar) ═══════════════════
--
-- 5.a El predicado responde y NO apago nada: todas las entidades existentes
--     deben salir activas (grandfathering), porque ninguna tiene fila todavia.
-- select count(*) filter (where flow.entidad_activa(id)) as activas,
--        count(*)                                  as total
--   from flow.entidad;                          -- esperado: activas = total
--
-- 5.b El catalogo no cambio de tamano (mismo resultado que antes de la 44).
-- select count(*) from flow.local_servicio ls
--  where flow._ls_disponible(ls.id);            -- mismo que antes de migrar
--
-- 5.c Los planes salen vacios pero la forma es correcta.
-- select flow.cliente_planes_suscripcion();    -- {"ok": true, "data": []}
--
-- 5.d El trigger de trial esta instalado.
-- select tgname from pg_trigger
--  where tgrelid = 'flow.entidad'::regclass
--    and tgname = 'trg_entidad_suscripcion_trial';   -- 1 fila
--
-- 5.e Prueba de humo del trial (deja rastro; hacerla en el proyecto debug):
-- insert into flow.entidad (denominacion, owner_uuid)
--   values ('PRUEBA SUSCRIPCION', auth.uid()) returning id;
-- select estado, fecha_vencimiento, fecha_gracia_fin
--   from flow.suscripcion where id_entidad = <id_devuelto>;  -- estado 'trial'
-- delete from flow.entidad where id = <id_devuelto>;         -- limpia (cascade)
-- ════════════════════════════════════════════════════════════════════════════
