-- ============================================================================
-- PENDIENTE EN RELEASE SI YA APLICASTE 60-64: 65 (permiso), 66 (bot al cancelar) y 67 (cobro por servicio)
--
-- Pegar TODO este archivo de una vez en el SQL Editor de release y ejecutar.
-- Es idempotente: se puede volver a ejecutar sin duplicar nada.
-- ============================================================================

-- #################### INICIO: 65_grants_service_role_schema_flow.sql ####################

-- ============================================================================
-- MIGRACION 65: permisos de `service_role` sobre el schema `flow`
--
-- QUE ARREGLA
--   La Edge Function `flow-tasas` corre con `service_role` y lee
--   `flow.tasa_cambio` con `client.schema('flow')`. En release, el schema `flow`
--   solo tenia USAGE para `anon` y `authenticated`:
--
--       flow_acl = {postgres=UC/postgres, anon=U/postgres, authenticated=U/postgres}
--
--   Con el permiso sobre la TABLA pero sin USAGE en el SCHEMA, PostgREST
--   responde Â«permission denied for schema flowÂ» y la funcion devuelve
--   `{ok:false,"error":"No se pudo leer la cache: permission denied for schema flow"}`.
--
-- QUE HACE
--   1. `grant usage on schema flow to service_role`.
--   2. Refuerza el SELECT de `service_role` sobre las tablas que leen las
--      funciones de servidor (idempotente: solo concede lo que falta).
--
-- QUIEN LO NECESITA
--   * release (`vsieeihstajlrdvpuooh`): SI, es el que estaba incompleto.
--   * debug (`qhprswhhfasrikhawjoz`): ya tenia USAGE; la migracion es un no-op.
--
-- REVERSION
--   revoke usage on schema flow from service_role;
--
-- IDEMPOTENTE.
-- ============================================================================

grant usage on schema flow to service_role;

-- El service_role es el rol de servidor: puede saltarse la RLS, pero necesita
-- los privilegios de tabla. Se repiten los de las migraciones 60-64 por si
-- alguna se aplico por separado.
grant select on flow.tasa_cambio,
                flow.tasa_cambio_sondeo,
                flow.precio_config,
                flow.cobro_config,
                flow.reserva_pago
  to service_role;

grant insert, update, delete on flow.tasa_cambio,
                                flow.tasa_cambio_sondeo,
                                flow.precio_config,
                                flow.cobro_config,
                                flow.reserva_pago
  to service_role;

notify pgrst, 'reload schema';

-- â•â• VERIFICACION â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--
-- select has_schema_privilege('service_role', 'flow', 'USAGE');          -- true
-- select has_table_privilege('service_role', 'flow.tasa_cambio', 'SELECT'); -- true
-- select nspacl::text from pg_namespace where nspname = 'flow';
--   -- debe incluir service_role=U/postgres
--
-- Prueba real de la funcion (desde el cliente o el dashboard):
--   POST /functions/v1/flow-tasas   ->  {"ok":true, ...}
--   Antes devolvia 500 con "permission denied for schema flow".
-- #################### FIN: 65_grants_service_role_schema_flow.sql ####################

-- #################### INICIO: 66_bot_al_cancelar_reserva.sql ####################

-- ============================================================================
-- MIGRACION 66: al cancelar una reserva, disparar el BOT de la cola
--
-- QUE RESUELVE
--   Al cancelar (o al expirar un pago y cancelarse sola) se libera cupo, pero
--   NADIE avisaba al bot: no habia cron del bot ni trigger en `flow.agenda`, asi
--   que el hueco quedaba vacio hasta que alguien ejecutara `flow.bot_sweep()` a
--   mano. El siguiente de la cola (`flow.sala_espera`) no recibia su turno.
--
-- COMO
--   Un trigger **deferido** en `flow.agenda`: cuando una reserva pasa de
--   `Reservado` a `Cancelado`, al hacer COMMIT se procesa el turno/dia liberado:
--
--     * reserva con turno  -> flow.bot_procesar_recurso_dia(id_turno, dia)
--     * reserva por plan   -> flow.bot_procesar_plan(id_plan del dia)
--
--   Deferido (`initially deferred`) es la clave: las funciones de cancelacion
--   hacen el `update` del estado ANTES de devolver el cupo a `plan_tramo` /
--   `plan_servicios`. Si el bot corriera en ese instante veria el cupo todavia
--   ocupado. Al ejecutarse en el COMMIT, la capacidad ya esta liberada.
--
--   Ademas cubre TODAS las vias de cancelacion sin tocarlas una por una:
--   admin (staff_cancelar_reserva / admin_cancelar_agenda), staff
--   (staff_marcar_estado_agenda), cliente (cliente_cancelar_reserva) y la
--   expiracion automatica de un pago (reserva_pago_expirar).
--
-- LO QUE NO CAMBIA
--   * Nada del bot: se llaman sus funciones tal cual, con su propio manejo de
--     errores y su registro en `flow.bot_log`.
--   * Si no hay nadie en la cola, `bot_procesar_*` no hace nada (movidos = 0).
--   * El bot NUNCA puede tumbar la cancelacion: el trigger captura cualquier
--     error y lo deja en `bot_log`.
--   * Reactivar y completar no disparan nada (reactivar consume cupo, completar
--     no lo libera).
--
-- REVERSION
--   drop trigger if exists trg_agenda_bot_al_cancelar on flow.agenda;
--   drop function if exists flow.trg_agenda_bot_al_cancelar();
--
-- IDEMPOTENTE.
-- ============================================================================

create or replace function flow.trg_agenda_bot_al_cancelar()
returns trigger
language plpgsql
security definer
set search_path = flow, public
as $function$
declare
  v_cancelado integer;
  v_reservado integer;
  v_dia       date;
  v_plan      bigint;
  v_res       jsonb;
begin
  select id into v_cancelado from flow.nom_estado_agenda where nombre = 'Cancelado' limit 1;
  select id into v_reservado from flow.nom_estado_agenda where nombre = 'Reservado' limit 1;

  -- Solo interesa la transicion que LIBERA cupo: activa -> cancelada.
  if v_cancelado is null
     or new.id_estado is distinct from v_cancelado
     or old.id_estado is distinct from v_reservado then
    return new;
  end if;

  v_dia := (new.fecha_hora_reserva at time zone 'America/Havana')::date;

  begin
    if new.id_turno is not null then
      -- Camino recursos/turnos: reparte el cupo liberado entre la cola de ESE
      -- turno (y de turnos posteriores sin cola propia).
      v_res := flow.bot_procesar_recurso_dia(new.id_turno, v_dia);
    else
      -- Camino legacy: cupo del dia en `plan_servicios`.
      select ps.id into v_plan
        from flow.plan_servicios ps
       where ps.id_local_servicio = new.id_local_servicio
         and (ps.fecha at time zone 'America/Havana')::date = v_dia
       limit 1;

      if v_plan is not null then
        v_res := flow.bot_procesar_plan(v_plan);
      end if;
    end if;
  exception
    when others then
      -- El bot jamÃ¡s puede abortar la cancelaciÃ³n del usuario.
      insert into flow.bot_log (id_plan, id_local_servicio, resultado, movidos, mensaje, detalle)
      values (v_plan, new.id_local_servicio, 'error', 0,
              'trigger cancelacion: ' || sqlerrm,
              jsonb_build_object(
                'id_agenda', new.id,
                'id_turno', new.id_turno,
                'fecha', v_dia,
                'sqlstate', sqlstate
              ));
  end;

  return new;
end;
$function$;

comment on function flow.trg_agenda_bot_al_cancelar() is
  'Cuando una reserva pasa de Reservado a Cancelado, manda correr el bot de la cola para el turno/dia liberado. Deferido al COMMIT para que el cupo ya este devuelto.';

drop trigger if exists trg_agenda_bot_al_cancelar on flow.agenda;

create constraint trigger trg_agenda_bot_al_cancelar
  after update on flow.agenda
  deferrable initially deferred
  for each row
  execute function flow.trg_agenda_bot_al_cancelar();

-- â•â• VERIFICACION (ejecutar a mano despues de aplicar) â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--
-- V.1 El trigger existe y es deferido.
-- select tgname, tgdeferrable, tginitdeferred, tgconstraint <> 0 as es_constraint
--   from pg_trigger
--  where tgrelid = 'flow.agenda'::regclass and tgname = 'trg_agenda_bot_al_cancelar';
--   -- 1 fila: deferrable = true, initdeferred = true
--
-- V.2 Al cancelar con cola, el siguiente de la cola recibe la reserva.
--   (necesita un turno con plan_tramo lleno y una fila en flow.sala_espera)
-- select flow.staff_cancelar_reserva(<id_agenda>, 'Prueba bot');
-- select * from flow.sala_espera where id_local_servicio = <ls>;  -- debe quedar vacia
-- select * from flow.agenda where id_local_servicio = <ls> order by id desc limit 3;
--   -- debe aparecer una agenda nueva con fecha = dia liberado
-- select * from flow.bot_log order by id desc limit 3;
--   -- resultado 'ok', movidos >= 1
--
-- V.3 Sin nadie en la cola no pasa nada (no crea reservas).
-- select flow.bot_procesar_recurso_dia(<id_turno>, current_date);  -- movidos: 0
-- #################### FIN: 66_bot_al_cancelar_reserva.sql ####################

-- #################### INICIO: 67_cobro_por_servicio.sql ####################

-- ============================================================================
-- MIGRACION 67: activar el pago por adelantado POR SERVICIO
--
-- QUE RESUELVE
--   El cobro por adelantado quedÃ³ configurado por ENTIDAD (una sola vez: nÃºmero
--   de proveedor, WhatsApp de verificaciÃ³n, moneda y plazo), que es lo correcto
--   porque el admin cobra con una sola cuenta. Pero no todos sus servicios se
--   pagan por adelantado, y no habÃ­a forma de decirlo: al activarlo en la
--   entidad, TODOS los servicios ofrecÃ­an el pago al cliente.
--
-- QUE CAMBIA
--   1. `flow.app_dat_servicios.cobro_adelantado boolean not null default false`
--      â€” nace en `false` a propÃ³sito: activar el cobro en la entidad deja de
--      encenderlo en todos los servicios. El admin marca los que sÃ­.
--   2. `flow.cliente_cobro_info` exige **las dos** condiciones: la entidad tiene
--      el cobro activo Y el servicio lo acepta. Si el servicio no lo acepta,
--      devuelve `disponible: false` y la app no ofrece nada.
--   3. Guarda extra en `flow.reserva_pago` (trigger BEFORE INSERT): crear un
--      intento de pago para un servicio que no lo acepta falla con un mensaje
--      claro. Cubre clientes viejos o llamadas directas a la RPC.
--
-- LO QUE NO CAMBIA
--   * `flow.cobro_config` sigue siendo el interruptor maestro por entidad.
--   * La RPC de creaciÃ³n de intentos y todo el circuito de verificaciÃ³n.
--   * Las reservas ya existentes: el flag solo afecta a OFRECER el pago.
--
-- REVERSION
--   drop trigger if exists trg_reserva_pago_servicio_cobra on flow.reserva_pago;
--   drop function if exists flow.trg_reserva_pago_servicio_cobra();
--   alter table flow.app_dat_servicios drop column if exists cobro_adelantado;
--   + volver a aplicar `cliente_cobro_info` de la migracion 62.
--
-- IDEMPOTENTE.
-- ============================================================================

-- â•â• 1. COLUMNA â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

alter table flow.app_dat_servicios
  add column if not exists cobro_adelantado boolean not null default false;

comment on column flow.app_dat_servicios.cobro_adelantado is
  'Si true, este servicio se puede pagar por adelantado en linea. Ademas, la entidad tiene que tener el cobro activo en flow.cobro_config (interruptor maestro).';

-- â•â• 2. DISPONIBILIDAD PARA EL CLIENTE â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

create or replace function flow.cliente_cobro_info(p_id_local_servicio integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = flow, public
as $function$
declare
  v_id_entidad integer;
  v_cobra_servicio boolean;
  v_row        flow.cobro_config%rowtype;
begin
  -- [67] Hacen falta las DOS cosas: que el servicio lo acepte y que la entidad
  -- lo tenga activo. La entidad sola ya no basta.
  select l.id_entidad, s.cobro_adelantado
    into v_id_entidad, v_cobra_servicio
  from flow.local_servicio ls
  join flow.app_dat_locales   l on l.id = ls.id_local
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  where ls.id = p_id_local_servicio;

  if v_id_entidad is null or not coalesce(v_cobra_servicio, false) then
    return jsonb_build_object('ok', true, 'data', jsonb_build_object('disponible', false));
  end if;

  select * into v_row from flow.cobro_config where id_entidad = v_id_entidad;

  if v_row.id_entidad is null or not v_row.activo then
    return jsonb_build_object('ok', true, 'data', jsonb_build_object('disponible', false));
  end if;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'disponible', true,
      'id_entidad', v_id_entidad,
      'moneda',     v_row.moneda,
      'horas_vigencia', v_row.intent_horas_vigencia,
      'whatsapp_verificacion', v_row.whatsapp_verificacion,
      'soporte_whatsapp',      v_row.soporte_whatsapp,
      'instrucciones',         v_row.instrucciones,
      'titulo',                v_row.transfermovil_titulo,
      'numero_proveedor',      v_row.transfermovil_numero_proveedor
    )
  );
end;
$function$;

comment on function flow.cliente_cobro_info(integer) is
  'Si este local-servicio puede pagarse por adelantado: exige cobro_adelantado del servicio Y cobro_config.activo de la entidad.';

-- â•â• 3. GUARDA AL CREAR EL INTENTO â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

create or replace function flow.trg_reserva_pago_servicio_cobra()
returns trigger
language plpgsql
security definer
set search_path = flow, public
as $function$
begin
  if not exists (
    select 1
    from flow.agenda a
    join flow.local_servicio    ls on ls.id = a.id_local_servicio
    join flow.app_dat_servicios s  on s.id  = ls.id_servicio
    where a.id = new.id_agenda
      and coalesce(s.cobro_adelantado, false)
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'Este servicio no tiene activado el pago por adelantado',
      hint    = 'Activalo en el servicio (Catalogo -> editar servicio) o desactiva el cobro de la reserva.';
  end if;

  return new;
end;
$function$;

comment on function flow.trg_reserva_pago_servicio_cobra() is
  'Impide crear un intento de pago por adelantado en un servicio que no lo acepta.';

drop trigger if exists trg_reserva_pago_servicio_cobra on flow.reserva_pago;

create trigger trg_reserva_pago_servicio_cobra
  before insert on flow.reserva_pago
  for each row
  execute function flow.trg_reserva_pago_servicio_cobra();

notify pgrst, 'reload schema';

-- â•â• VERIFICACION (ejecutar a mano despues de aplicar) â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--
-- V.1 La columna existe y nace apagada.
-- select column_name, data_type, column_default from information_schema.columns
--  where table_schema='flow' and table_name='app_dat_servicios'
--    and column_name='cobro_adelantado';   -- false
--
-- V.2 Con el servicio apagado, la app no ofrece el pago aunque la entidad lo tenga activo.
-- update flow.app_dat_servicios set cobro_adelantado = false where id = <id_servicio>;
-- select flow.cliente_cobro_info(<id_local_servicio>) -> 'data' ->> 'disponible';  -- false
-- update flow.app_dat_servicios set cobro_adelantado = true  where id = <id_servicio>;
-- select flow.cliente_cobro_info(<id_local_servicio>) -> 'data' ->> 'disponible';  -- true (si la entidad lo tiene activo)
--
-- V.3 El trigger corta el intento en un servicio que no lo acepta.
-- select flow.cliente_crear_pago_reserva(<id_agenda_de_un_servicio_apagado>);
--   -- ERROR: Este servicio no tiene activado el pago por adelantado
-- #################### FIN: 67_cobro_por_servicio.sql ####################

