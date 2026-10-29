-- ============================================================================
-- MIGRACION 67: activar el pago por adelantado POR SERVICIO
--
-- QUE RESUELVE
--   El cobro por adelantado quedó configurado por ENTIDAD (una sola vez: número
--   de proveedor, WhatsApp de verificación, moneda y plazo), que es lo correcto
--   porque el admin cobra con una sola cuenta. Pero no todos sus servicios se
--   pagan por adelantado, y no había forma de decirlo: al activarlo en la
--   entidad, TODOS los servicios ofrecían el pago al cliente.
--
-- QUE CAMBIA
--   1. `flow.app_dat_servicios.cobro_adelantado boolean not null default false`
--      — nace en `false` a propósito: activar el cobro en la entidad deja de
--      encenderlo en todos los servicios. El admin marca los que sí.
--   2. `flow.cliente_cobro_info` exige **las dos** condiciones: la entidad tiene
--      el cobro activo Y el servicio lo acepta. Si el servicio no lo acepta,
--      devuelve `disponible: false` y la app no ofrece nada.
--   3. Guarda extra en `flow.reserva_pago` (trigger BEFORE INSERT): crear un
--      intento de pago para un servicio que no lo acepta falla con un mensaje
--      claro. Cubre clientes viejos o llamadas directas a la RPC.
--
-- LO QUE NO CAMBIA
--   * `flow.cobro_config` sigue siendo el interruptor maestro por entidad.
--   * La RPC de creación de intentos y todo el circuito de verificación.
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

-- ══ 1. COLUMNA ═════════════════════════════════════════════════════════════

alter table flow.app_dat_servicios
  add column if not exists cobro_adelantado boolean not null default false;

comment on column flow.app_dat_servicios.cobro_adelantado is
  'Si true, este servicio se puede pagar por adelantado en linea. Ademas, la entidad tiene que tener el cobro activo en flow.cobro_config (interruptor maestro).';

-- ══ 2. DISPONIBILIDAD PARA EL CLIENTE ══════════════════════════════════════

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

-- ══ 3. GUARDA AL CREAR EL INTENTO ══════════════════════════════════════════

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

-- ══ VERIFICACION (ejecutar a mano despues de aplicar) ══════════════════════
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