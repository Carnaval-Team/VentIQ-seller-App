-- ============================================================================
-- MIGRACION 62: pago por adelantado del servicio (pago en linea)
--
-- QUE RESUELVE
--   El cliente, si el admin lo tiene activado, puede pagar su reserva POR
--   ADELANTADO con el mismo circuito que ya usa la suscripcion (deep link de
--   Transfermovil -> "Ya he pagado" -> verificacion manual del admin), pero con
--   LOS DATOS DEL ADMIN: su numero de proveedor y su WhatsApp de verificacion.
--   La config es POR ENTIDAD (una sola para todos sus locales).
--
-- FLUJO (completo)
--   1. El cliente reserva normal (la reserva nace `Reservado`).
--   2. Si el local-servicio tiene cobro activo, la app le ofrece
--      "Pagar por adelantado". `cliente_crear_pago_reserva` crea el intento,
--      devuelve el link de Transfermovil y deja `agenda.pago_estado='pendiente'`.
--      La reserva SIGUE OCUPANDO su turno mientras el admin revisa.
--   3. El cliente abre Transfermovil, paga y pulsa "Ya he pagado"
--      (`cliente_reportar_pago_reserva`): `pago_estado='reportado'` y aviso al
--      admin (in-app) con el WhatsApp del cliente a mano.
--   4. El admin verifica (`admin_verificar_pago_reserva` -> 'verificado' +
--      notificacion al cliente) o rechaza (`admin_rechazar_pago_reserva` ->
--      'rechazado' + motivo + notificacion).
--   5. `reserva_pago_expirar()` cierra los intentos vencidos: los marca
--      'expirado' y cancela la reserva con motivo, liberando la capacidad.
--      Se puede llamar a mano y desde un cron.
--
-- TABLAS NUEVAS (schema `flow`)
--   * flow.cobro_config  — por entidad: numeros, plantillas, moneda y plazo.
--   * flow.reserva_pago  — un intento por reserva (auditable e idempotente).
--
-- COLUMNAS NUEVAS EN flow.agenda
--   pago_estado text, pago_id bigint, pago_monto numeric, pago_moneda text
--
-- LO QUE NO CAMBIA
--   * Reservar, cancelar y completar siguen igual. El pago es un paso OPCIONAL
--     posterior: si el admin no lo activa, nada de esto aparece.
--   * `agenda.id_estado` no cambia: una reserva pendiente de pago es una reserva
--     `Reservado` como cualquier otra (por eso el turno queda bloqueado).
--
-- REVERSION
--   alter table flow.agenda drop column if exists pago_estado, drop column if exists pago_id,
--     drop column if exists pago_monto, drop column if exists pago_moneda;
--   drop table if exists flow.reserva_pago;
--   drop table if exists flow.cobro_config;
--   + drop de las 8 funciones de esta migracion.
--
-- IDEMPOTENTE: if not exists / create or replace / drop policy if exists.
-- ============================================================================

-- ══ 1. TABLAS ══════════════════════════════════════════════════════════════

create table if not exists flow.cobro_config (
  id_entidad integer primary key
               references flow.entidad (id) on delete cascade,
  activo boolean not null default false,
  -- Numero de proveedor de Transfermovil del ADMIN (el que cobra).
  transfermovil_numero_proveedor text not null default '',
  transfermovil_titulo           text not null default '',
  transfermovil_intent_template  text not null default
    'transfermovil://tm_compra_en_linea/action?id_transaccion=$id_transaccion&importe=$importe&moneda=$moneda&numero_proveedor=$numero_proveedor&version=1.0.0&titulo=$titulo&set_title=$titulo',
  transfermovil_url_template     text not null default
    'https://transfermovil.app/action?id_transaccion=$id_transaccion&importe=$importe&moneda=$moneda&numero_proveedor=$numero_proveedor&version=5&titulo=$titulo&set_title=$titulo',
  -- WhatsApp del admin donde el cliente manda el comprobante.
  whatsapp_verificacion text,
  soporte_whatsapp      text,
  instrucciones         text,
  moneda                text not null default 'CUP',
  intent_horas_vigencia integer not null default 24,
  cancelar_si_expira    boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid,
  constraint cobro_config_moneda_chk check (moneda in ('CUP', 'USD', 'EUR', 'MLC')),
  constraint cobro_config_horas_chk  check (intent_horas_vigencia between 1 and 720),
  constraint cobro_config_prov_chk   check (not activo or btrim(transfermovil_numero_proveedor) <> '')
);

comment on table flow.cobro_config is
  'Configuracion por entidad del pago por adelantado del servicio: numero de proveedor de Transfermovil del admin, WhatsApp de verificacion, moneda de cobro y plazo del intento.';

create table if not exists flow.reserva_pago (
  id          bigint generated always as identity primary key,
  id_agenda   integer not null references flow.agenda (id) on delete cascade,
  id_entidad  integer not null references flow.entidad (id) on delete cascade,
  uuid_usuario uuid   not null,
  monto       numeric(12,2) not null,
  moneda      text    not null default 'CUP',
  id_transaccion   text not null,
  numero_proveedor text not null,
  url_intent  text not null,
  url_http    text not null,
  estado      text not null default 'creado',
  codigo_confirmacion text,
  comprobante_url     text,
  motivo_rechazo      text,
  reportado_at   timestamptz,
  verificado_por uuid,
  verificado_at  timestamptz,
  expira_at   timestamptz not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint reserva_pago_monto_chk  check (monto > 0),
  constraint reserva_pago_moneda_chk check (moneda in ('CUP', 'USD', 'EUR', 'MLC')),
  constraint reserva_pago_estado_chk check (
    estado in ('creado', 'reportado', 'verificado', 'rechazado', 'expirado', 'anulado')
  )
);

comment on table flow.reserva_pago is
  'Intento de pago por adelantado de una reserva. La crea el cliente via RPC; el admin la verifica o la rechaza; `reserva_pago_expirar` cierra las vencidas.';
comment on column flow.reserva_pago.id_transaccion is
  'Referencia interna unica del intento. NO viaja en el link: la app de Transfermovil trata id_transaccion como estatico ("ESTATICO"), asi que el link lo lleva literal y esta columna sirve para auditar y para que soporte ubique el pago.';

create index if not exists idx_reserva_pago_agenda on flow.reserva_pago (id_agenda);
create index if not exists idx_reserva_pago_pendientes
  on flow.reserva_pago (estado, expira_at)
  where estado in ('creado', 'reportado');

drop trigger if exists trg_cobro_config_updated_at on flow.cobro_config;
create trigger trg_cobro_config_updated_at
  before update on flow.cobro_config
  for each row execute function flow.update_updated_at_column();

drop trigger if exists trg_reserva_pago_updated_at on flow.reserva_pago;
create trigger trg_reserva_pago_updated_at
  before update on flow.reserva_pago
  for each row execute function flow.update_updated_at_column();

-- ══ 2. COLUMNAS DE PAGO EN LA AGENDA ═══════════════════════════════════════

alter table flow.agenda add column if not exists pago_estado text;
alter table flow.agenda add column if not exists pago_id     bigint;
alter table flow.agenda add column if not exists pago_monto  numeric(12,2);
alter table flow.agenda add column if not exists pago_moneda text;

alter table flow.agenda drop constraint if exists agenda_pago_estado_chk;
alter table flow.agenda add  constraint agenda_pago_estado_chk
  check (pago_estado is null
         or pago_estado in ('pendiente', 'reportado', 'verificado', 'rechazado', 'expirado'));

comment on column flow.agenda.pago_estado is
  'Estado del pago por adelantado de la reserva. NULL = no pide pago por adelantado.';
comment on column flow.agenda.pago_id is 'Ultimo intento de pago asociado a la reserva.';
comment on column flow.agenda.pago_monto is 'Importe que se cobra por adelantado (en `pago_moneda`).';
comment on column flow.agenda.pago_moneda is 'Moneda del cobro por adelantado.';

-- ══ 3. HELPER: importe del cobro ═══════════════════════════════════════════
-- El cobro es el TOTAL de la reserva, convertido a la moneda de cobro con la
-- tasa cacheada cuando no coinciden (misma fuente que los precios automaticos).

create or replace function flow._monto_cobro_reserva(
  p_id_agenda integer,
  p_moneda_cobro text
)
returns numeric
language plpgsql
stable
security definer
set search_path = flow, public
as $function$
declare
  v_total  numeric;
  v_moneda text;
  v_factor numeric;
  v_out    numeric;
begin
  select a.precio_total, coalesce(nullif(btrim(a.moneda), ''), p_moneda_cobro)
    into v_total, v_moneda
  from flow.agenda a
  where a.id = p_id_agenda;

  if v_total is null or v_total <= 0 then
    return null;
  end if;

  if upper(v_moneda) = upper(p_moneda_cobro) then
    return round(v_total, 2);
  end if;

  v_factor := flow.tasa_factor(v_moneda, p_moneda_cobro);
  if v_factor is null or v_factor <= 0 then
    return null;
  end if;

  v_out := v_total * v_factor;
  -- CUP sin centavos: Transfermovil cobra pesos enteros.
  if upper(p_moneda_cobro) = 'CUP' then
    return round(v_out);
  end if;
  return round(v_out, 2);
end;
$function$;

comment on function flow._monto_cobro_reserva(integer, text) is
  'Total de la reserva convertido a la moneda de cobro. NULL cuando la reserva no tiene precio o no hay tasa para convertir.';

-- ══ 4. CONFIG DEL COBRO (ADMIN) ════════════════════════════════════════════

create or replace function flow.admin_cobro_config_get(p_id_entidad integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = flow, public
as $function$
declare
  v_row flow.cobro_config%rowtype;
begin
  if not flow._puede_ver_entidad(p_id_entidad) then
    return jsonb_build_object('ok', false, 'error', 'No tiene permisos sobre esta entidad');
  end if;

  select * into v_row from flow.cobro_config where id_entidad = p_id_entidad;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id_entidad',          p_id_entidad,
      'activo',              coalesce(v_row.activo, false),
      'tiene_fila',          v_row.id_entidad is not null,
      'transfermovil_numero_proveedor', coalesce(v_row.transfermovil_numero_proveedor, ''),
      'transfermovil_titulo',           coalesce(v_row.transfermovil_titulo, ''),
      'transfermovil_intent_template',
        coalesce(v_row.transfermovil_intent_template,
          'transfermovil://tm_compra_en_linea/action?id_transaccion=$id_transaccion&importe=$importe&moneda=$moneda&numero_proveedor=$numero_proveedor&version=1.0.0&titulo=$titulo&set_title=$titulo'),
      'transfermovil_url_template',
        coalesce(v_row.transfermovil_url_template,
          'https://transfermovil.app/action?id_transaccion=$id_transaccion&importe=$importe&moneda=$moneda&numero_proveedor=$numero_proveedor&version=5&titulo=$titulo&set_title=$titulo'),
      'whatsapp_verificacion', coalesce(v_row.whatsapp_verificacion, ''),
      'soporte_whatsapp',      coalesce(v_row.soporte_whatsapp, ''),
      'instrucciones',         coalesce(v_row.instrucciones, ''),
      'moneda',                coalesce(v_row.moneda, 'CUP'),
      'intent_horas_vigencia', coalesce(v_row.intent_horas_vigencia, 24),
      'cancelar_si_expira',    coalesce(v_row.cancelar_si_expira, true)
    )
  );
end;
$function$;

create or replace function flow.admin_cobro_config_set(
  p_id_entidad            integer,
  p_activo                boolean default false,
  p_numero_proveedor      text    default '',
  p_titulo                text    default '',
  p_whatsapp_verificacion text    default '',
  p_soporte_whatsapp      text    default '',
  p_instrucciones         text    default '',
  p_moneda                text    default 'CUP',
  p_horas_vigencia        integer default 24,
  p_cancelar_si_expira    boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = flow, public
as $function$
declare
  v_moneda text := upper(btrim(coalesce(p_moneda, 'CUP')));
  v_prov   text := btrim(coalesce(p_numero_proveedor, ''));
begin
  if not flow._puede_ver_entidad(p_id_entidad) then
    return jsonb_build_object('ok', false, 'error', 'No tiene permisos sobre esta entidad');
  end if;

  if v_moneda not in ('CUP', 'USD', 'EUR', 'MLC') then
    return jsonb_build_object('ok', false, 'error', 'Moneda de cobro no soportada');
  end if;

  if coalesce(p_horas_vigencia, 24) not between 1 and 720 then
    return jsonb_build_object('ok', false, 'error', 'El plazo debe estar entre 1 y 720 horas');
  end if;

  if coalesce(p_activo, false) and v_prov = '' then
    return jsonb_build_object('ok', false,
      'error', 'Para activar el pago por adelantado hace falta el numero de proveedor');
  end if;

  insert into flow.cobro_config (
    id_entidad, activo, transfermovil_numero_proveedor, transfermovil_titulo,
    whatsapp_verificacion, soporte_whatsapp, instrucciones, moneda,
    intent_horas_vigencia, cancelar_si_expira, updated_by
  ) values (
    p_id_entidad, coalesce(p_activo, false), v_prov,
    coalesce(nullif(btrim(p_titulo), ''), (select e.denominacion from flow.entidad e where e.id = p_id_entidad), ''),
    nullif(btrim(coalesce(p_whatsapp_verificacion, '')), ''),
    nullif(btrim(coalesce(p_soporte_whatsapp, '')), ''),
    nullif(btrim(coalesce(p_instrucciones, '')), ''),
    v_moneda, coalesce(p_horas_vigencia, 24), coalesce(p_cancelar_si_expira, true), auth.uid()
  )
  on conflict (id_entidad) do update
    set activo = excluded.activo,
        transfermovil_numero_proveedor = excluded.transfermovil_numero_proveedor,
        transfermovil_titulo = excluded.transfermovil_titulo,
        whatsapp_verificacion = excluded.whatsapp_verificacion,
        soporte_whatsapp = excluded.soporte_whatsapp,
        instrucciones = excluded.instrucciones,
        moneda = excluded.moneda,
        intent_horas_vigencia = excluded.intent_horas_vigencia,
        cancelar_si_expira = excluded.cancelar_si_expira,
        updated_by = excluded.updated_by,
        updated_at = now();

  return flow.admin_cobro_config_get(p_id_entidad);
end;
$function$;

-- ══ 5. LADO CLIENTE ════════════════════════════════════════════════════════

-- Lo que la app necesita saber ANTES de ofrecer "pagar por adelantado".
create or replace function flow.cliente_cobro_info(p_id_local_servicio integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = flow, public
as $function$
declare
  v_id_entidad integer;
  v_row        flow.cobro_config%rowtype;
begin
  select l.id_entidad into v_id_entidad
  from flow.local_servicio ls
  join flow.app_dat_locales l on l.id = ls.id_local
  where ls.id = p_id_local_servicio;

  if v_id_entidad is null then
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

-- Crea el intento de pago de UNA reserva ya creada.
create or replace function flow.cliente_crear_pago_reserva(p_id_agenda integer)
returns jsonb
language plpgsql
security definer
set search_path = flow, public
as $function$
declare
  v_uid        uuid := auth.uid();
  v_agenda     flow.agenda%rowtype;
  v_estado_res integer;
  v_id_entidad integer;
  v_cfg        flow.cobro_config%rowtype;
  v_monto      numeric(12,2);
  v_importe    text;
  v_id_trx     text;
  v_url_intent text;
  v_url_http   text;
  v_expira     timestamptz;
  v_id         bigint;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Sesion requerida');
  end if;

  select a.* into v_agenda from flow.agenda a where a.id = p_id_agenda;
  if v_agenda.id is null then
    return jsonb_build_object('ok', false, 'error', 'Reserva no encontrada');
  end if;

  if v_agenda.uuid_usuario <> v_uid and coalesce(v_agenda.reservado_por, v_uid) <> v_uid then
    return jsonb_build_object('ok', false, 'error', 'No tienes permiso sobre esta reserva');
  end if;

  select id into v_estado_res from flow.nom_estado_agenda where nombre = 'Reservado' limit 1;
  if v_agenda.id_estado is distinct from v_estado_res then
    return jsonb_build_object('ok', false, 'error', 'Solo se puede pagar una reserva activa');
  end if;

  -- Un solo intento vivo por reserva.
  if exists (
    select 1 from flow.reserva_pago rp
    where rp.id_agenda = p_id_agenda
      and rp.estado in ('creado', 'reportado')
      and rp.expira_at > now()
  ) then
    return jsonb_build_object('ok', false, 'error',
      'Ya tienes un pago en curso para esta reserva. Revisa su estado antes de crear otro.');
  end if;

  select l.id_entidad into v_id_entidad
  from flow.local_servicio ls
  join flow.app_dat_locales l on l.id = ls.id_local
  where ls.id = v_agenda.id_local_servicio;

  if v_id_entidad is null then
    return jsonb_build_object('ok', false, 'error', 'No se pudo resolver la entidad de la reserva');
  end if;

  select * into v_cfg from flow.cobro_config where id_entidad = v_id_entidad;
  if v_cfg.id_entidad is null or not v_cfg.activo then
    return jsonb_build_object('ok', false, 'error',
      'Este servicio no tiene activado el pago por adelantado');
  end if;

  v_monto := flow._monto_cobro_reserva(p_id_agenda, v_cfg.moneda);
  if v_monto is null or v_monto <= 0 then
    if v_agenda.precio_total is not null and v_agenda.precio_total > 0 then
      return jsonb_build_object('ok', false, 'error',
        'No hay tasa de cambio para cobrar en ' || v_cfg.moneda || '. Intentalo mas tarde.');
    end if;
    return jsonb_build_object('ok', false, 'error',
      'Esta reserva no tiene precio configurado: no se puede pagar por adelantado');
  end if;

  v_importe := case when v_monto = trunc(v_monto)
                    then trunc(v_monto)::bigint::text
                    else to_char(v_monto, 'FM9999999990.00') end;

  v_id_trx := 'FLW-PAGO-' || p_id_agenda || '-' || to_char(now(), 'YYYYMMDDHH24MISS') || '-'
              || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));

  v_expira := now() + make_interval(hours => coalesce(v_cfg.intent_horas_vigencia, 24));

  v_url_intent := replace(replace(replace(replace(replace(
                    v_cfg.transfermovil_intent_template,
                    '$id_transaccion',   'ESTATICO'),
                    '$importe',          v_importe),
                    '$moneda',           v_cfg.moneda),
                    '$numero_proveedor', v_cfg.transfermovil_numero_proveedor),
                    '$titulo',           v_cfg.transfermovil_titulo);

  v_url_http := replace(replace(replace(replace(replace(
                    v_cfg.transfermovil_url_template,
                    '$id_transaccion',   'ESTATICO'),
                    '$importe',          v_importe),
                    '$moneda',           v_cfg.moneda),
                    '$numero_proveedor', v_cfg.transfermovil_numero_proveedor),
                    '$titulo',           v_cfg.transfermovil_titulo);

  insert into flow.reserva_pago (
    id_agenda, id_entidad, uuid_usuario, monto, moneda, id_transaccion,
    numero_proveedor, url_intent, url_http, estado, expira_at
  ) values (
    p_id_agenda, v_id_entidad, v_uid, v_monto, v_cfg.moneda, v_id_trx,
    v_cfg.transfermovil_numero_proveedor, v_url_intent, v_url_http, 'creado', v_expira
  ) returning id into v_id;

  update flow.agenda
     set pago_estado = 'pendiente',
         pago_id     = v_id,
         pago_monto  = v_monto,
         pago_moneda = v_cfg.moneda,
         updated_at  = current_timestamp
   where id = p_id_agenda;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id',               v_id,
      'id_agenda',        p_id_agenda,
      'monto',            v_monto,
      'moneda',           v_cfg.moneda,
      'importe',          v_importe,
      'id_transaccion',   v_id_trx,
      'numero_proveedor', v_cfg.transfermovil_numero_proveedor,
      'titulo',           v_cfg.transfermovil_titulo,
      'url_intent',       v_url_intent,
      'url_http',         v_url_http,
      'expira_at',        v_expira,
      'whatsapp_verificacion', v_cfg.whatsapp_verificacion,
      'soporte_whatsapp',      v_cfg.soporte_whatsapp,
      'instrucciones',         v_cfg.instrucciones
    )
  );
end;
$function$;

-- "Ya he pagado": el cliente reporta el pago y avisa al admin.
create or replace function flow.cliente_reportar_pago_reserva(
  p_id_pago             bigint,
  p_codigo_confirmacion text default null,
  p_comprobante_url     text default null
)
returns jsonb
language plpgsql
security definer
set search_path = flow, public
as $function$
declare
  v_uid     uuid := auth.uid();
  v_pago    flow.reserva_pago%rowtype;
  v_admin   uuid;
  v_serv    text;
  v_local   text;
  v_cliente text;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Sesion requerida');
  end if;

  select * into v_pago from flow.reserva_pago where id = p_id_pago;
  if v_pago.id is null then
    return jsonb_build_object('ok', false, 'error', 'Pago no encontrado');
  end if;

  if v_pago.uuid_usuario <> v_uid then
    return jsonb_build_object('ok', false, 'error', 'No tienes permiso sobre este pago');
  end if;

  if v_pago.estado not in ('creado', 'reportado') then
    return jsonb_build_object('ok', false, 'error',
      'Este pago ya esta ' || v_pago.estado || ' y no se puede volver a reportar');
  end if;

  if v_pago.expira_at <= now() then
    return jsonb_build_object('ok', false, 'error',
      'El plazo de este pago vencio. Crea uno nuevo si sigues queriendo pagar por adelantado.');
  end if;

  update flow.reserva_pago
     set estado = 'reportado',
         codigo_confirmacion = coalesce(nullif(btrim(coalesce(p_codigo_confirmacion, '')), ''), codigo_confirmacion),
         comprobante_url     = coalesce(nullif(btrim(coalesce(p_comprobante_url, '')), ''), comprobante_url),
         reportado_at        = now()
   where id = p_id_pago;

  update flow.agenda
     set pago_estado = 'reportado', updated_at = current_timestamp
   where id = v_pago.id_agenda;

  -- Aviso in-app a los administradores de la entidad.
  select s.nombre, l.nombre into v_serv, v_local
    from flow.agenda a
    join flow.local_servicio ls on ls.id = a.id_local_servicio
    join flow.app_dat_servicios s on s.id = ls.id_servicio
    join flow.app_dat_locales   l on l.id = ls.id_local
   where a.id = v_pago.id_agenda;

  select coalesce(p.nombre || ' ' || coalesce(p.apellidos, ''), 'Un cliente')
    into v_cliente
  from flow.perfil p
  where p.uuid_usuario = v_uid;

  for v_admin in
    select e.owner_uuid from flow.entidad e where e.id = v_pago.id_entidad
    union
    select ea.uuid_usuario from flow.entidad_admin ea where ea.id_entidad = v_pago.id_entidad
  loop
    insert into flow.notificaciones
      (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
    select
      v_admin, 'pago', 'Pago reportado por verificar',
      btrim(v_cliente) || ' dice haber pagado ' || to_char(v_pago.monto, 'FM9999999990.00')
        || ' ' || v_pago.moneda || ' por "' || coalesce(v_serv, 'un servicio')
        || '" en "' || coalesce(v_local, 'tu local') || '". Verificalo en Reservas.',
      a.id_local_servicio, v_pago.id_agenda,
      jsonb_build_object(
        'id_pago', v_pago.id, 'monto', v_pago.monto, 'moneda', v_pago.moneda,
        'estado', 'reportado', 'id_transaccion', v_pago.id_transaccion
      )
    from flow.agenda a where a.id = v_pago.id_agenda;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id', p_id_pago, 'estado', 'reportado', 'reportado_at', now()
    )
  );
end;
$function$;

-- Estado del pago de una reserva (lo pinta la pantalla del cliente).
create or replace function flow.cliente_pago_reserva(p_id_agenda integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = flow, public
as $function$
declare
  v_uid  uuid := auth.uid();
  v_pago flow.reserva_pago%rowtype;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Sesion requerida');
  end if;

  if not exists (
    select 1 from flow.agenda a
    where a.id = p_id_agenda
      and (a.uuid_usuario = v_uid or a.reservado_por = v_uid)
  ) then
    return jsonb_build_object('ok', false, 'error', 'No tienes permiso sobre esta reserva');
  end if;

  select * into v_pago
  from flow.reserva_pago
  where id_agenda = p_id_agenda
  order by id desc
  limit 1;

  if v_pago.id is null then
    return jsonb_build_object('ok', true, 'data', null);
  end if;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id',               v_pago.id,
      'id_agenda',        v_pago.id_agenda,
      'monto',            v_pago.monto,
      'moneda',           v_pago.moneda,
      'estado',           v_pago.estado,
      'id_transaccion',   v_pago.id_transaccion,
      'numero_proveedor', v_pago.numero_proveedor,
      'url_intent',       v_pago.url_intent,
      'url_http',         v_pago.url_http,
      'codigo_confirmacion', v_pago.codigo_confirmacion,
      'comprobante_url',     v_pago.comprobante_url,
      'motivo_rechazo',      v_pago.motivo_rechazo,
      'reportado_at',        v_pago.reportado_at,
      'verificado_at',       v_pago.verificado_at,
      'expira_at',           v_pago.expira_at,
      'vencido',             v_pago.expira_at <= now()
    )
  );
end;
$function$;

-- ══ 6. LADO ADMIN: BANDEJA Y VERIFICACION ═════════════════════════════════

create or replace function flow.admin_listar_pagos_reserva(
  p_id_entidad integer,
  p_estado     text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = flow, public
as $function$
declare
  v_out jsonb;
begin
  if not flow._puede_ver_entidad(p_id_entidad) then
    return jsonb_build_object('ok', false, 'error', 'No tiene permisos sobre esta entidad');
  end if;

  select coalesce(jsonb_agg(x order by x.fecha_hora_reserva desc), '[]'::jsonb)
    into v_out
  from (
    select
      rp.id, rp.id_agenda, rp.monto, rp.moneda, rp.estado, rp.id_transaccion,
      rp.numero_proveedor, rp.codigo_confirmacion, rp.comprobante_url,
      rp.motivo_rechazo, rp.reportado_at, rp.verificado_at, rp.expira_at,
      rp.created_at,
      (rp.expira_at <= now() and rp.estado in ('creado', 'reportado')) as vencido,
      a.fecha_hora_reserva, a.cantidad, a.id_estado, a.motivo_cancelacion,
      jsonb_build_object('id', es.id, 'nombre', es.nombre) as estado_reserva,
      ls.id as id_local_servicio,
      jsonb_build_object('id', s.id, 'nombre', s.nombre)   as servicio,
      jsonb_build_object('id', l.id, 'nombre', l.nombre)   as local,
      case when p.id is null then null else jsonb_build_object(
        'id', p.id, 'nombre', p.nombre, 'apellidos', p.apellidos,
        'telefono', p.telefono, 'uuid_usuario', p.uuid_usuario
      ) end as cliente
    from flow.reserva_pago rp
    join flow.agenda a             on a.id = rp.id_agenda
    join flow.local_servicio ls   on ls.id = a.id_local_servicio
    join flow.app_dat_servicios s on s.id = ls.id_servicio
    join flow.app_dat_locales l   on l.id = ls.id_local
    join flow.nom_estado_agenda es on es.id = a.id_estado
    left join flow.perfil p       on p.uuid_usuario = rp.uuid_usuario
    where rp.id_entidad = p_id_entidad
      and (p_estado is null or rp.estado = p_estado)
  ) x;

  return jsonb_build_object('ok', true, 'data', v_out);
end;
$function$;

create or replace function flow.admin_verificar_pago_reserva(
  p_id_pago       bigint,
  p_observaciones text default null
)
returns jsonb
language plpgsql
security definer
set search_path = flow, public
as $function$
declare
  v_uid   uuid := auth.uid();
  v_pago  flow.reserva_pago%rowtype;
  v_serv  text;
  v_local text;
begin
  select * into v_pago from flow.reserva_pago where id = p_id_pago;
  if v_pago.id is null then
    return jsonb_build_object('ok', false, 'error', 'Pago no encontrado');
  end if;

  if not flow._puede_ver_entidad(v_pago.id_entidad) then
    return jsonb_build_object('ok', false, 'error', 'No tiene permisos sobre esta entidad');
  end if;

  if v_pago.estado not in ('creado', 'reportado') then
    return jsonb_build_object('ok', false, 'error',
      'Este pago ya esta ' || v_pago.estado);
  end if;

  update flow.reserva_pago
     set estado = 'verificado',
         verificado_por = v_uid,
         verificado_at  = now(),
         motivo_rechazo = case when btrim(coalesce(p_observaciones, '')) = ''
                               then motivo_rechazo else btrim(p_observaciones) end
   where id = p_id_pago;

  update flow.agenda
     set pago_estado = 'verificado', updated_at = current_timestamp
   where id = v_pago.id_agenda;

  select s.nombre, l.nombre into v_serv, v_local
    from flow.agenda a
    join flow.local_servicio ls on ls.id = a.id_local_servicio
    join flow.app_dat_servicios s on s.id = ls.id_servicio
    join flow.app_dat_locales   l on l.id = ls.id_local
   where a.id = v_pago.id_agenda;

  insert into flow.notificaciones
    (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
  select
    v_pago.uuid_usuario, 'pago', 'Pago verificado',
    'Tu pago por adelantado de ' || to_char(v_pago.monto, 'FM9999999990.00') || ' '
      || v_pago.moneda || ' para "' || coalesce(v_serv, 'el servicio') || '" en "'
      || coalesce(v_local, 'el local') || '" quedo verificado. Tu reserva esta confirmada.',
    a.id_local_servicio, v_pago.id_agenda,
    jsonb_build_object('id_pago', v_pago.id, 'estado', 'verificado',
                       'monto', v_pago.monto, 'moneda', v_pago.moneda)
  from flow.agenda a where a.id = v_pago.id_agenda;

  return jsonb_build_object('ok', true,
    'data', jsonb_build_object('id', p_id_pago, 'estado', 'verificado'));
end;
$function$;

create or replace function flow.admin_rechazar_pago_reserva(
  p_id_pago bigint,
  p_motivo  text
)
returns jsonb
language plpgsql
security definer
set search_path = flow, public
as $function$
declare
  v_uid   uuid := auth.uid();
  v_pago  flow.reserva_pago%rowtype;
  v_mot   text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_serv  text;
  v_local text;
begin
  if v_mot is null then
    return jsonb_build_object('ok', false, 'error', 'Debes indicar el motivo del rechazo');
  end if;

  select * into v_pago from flow.reserva_pago where id = p_id_pago;
  if v_pago.id is null then
    return jsonb_build_object('ok', false, 'error', 'Pago no encontrado');
  end if;

  if not flow._puede_ver_entidad(v_pago.id_entidad) then
    return jsonb_build_object('ok', false, 'error', 'No tiene permisos sobre esta entidad');
  end if;

  if v_pago.estado not in ('creado', 'reportado') then
    return jsonb_build_object('ok', false, 'error', 'Este pago ya esta ' || v_pago.estado);
  end if;

  update flow.reserva_pago
     set estado = 'rechazado', motivo_rechazo = v_mot,
         verificado_por = v_uid, verificado_at = now()
   where id = p_id_pago;

  update flow.agenda
     set pago_estado = 'rechazado', updated_at = current_timestamp
   where id = v_pago.id_agenda;

  select s.nombre, l.nombre into v_serv, v_local
    from flow.agenda a
    join flow.local_servicio ls on ls.id = a.id_local_servicio
    join flow.app_dat_servicios s on s.id = ls.id_servicio
    join flow.app_dat_locales   l on l.id = ls.id_local
   where a.id = v_pago.id_agenda;

  insert into flow.notificaciones
    (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
  select
    v_pago.uuid_usuario, 'pago', 'Pago rechazado',
    'No pudimos verificar tu pago de ' || to_char(v_pago.monto, 'FM9999999990.00') || ' '
      || v_pago.moneda || ' para "' || coalesce(v_serv, 'el servicio') || '" en "'
      || coalesce(v_local, 'el local') || '". Motivo: ' || v_mot,
    a.id_local_servicio, v_pago.id_agenda,
    jsonb_build_object('id_pago', v_pago.id, 'estado', 'rechazado', 'motivo', v_mot)
  from flow.agenda a where a.id = v_pago.id_agenda;

  return jsonb_build_object('ok', true,
    'data', jsonb_build_object('id', p_id_pago, 'estado', 'rechazado'));
end;
$function$;

-- ══ 7. EXPIRACION ══════════════════════════════════════════════════════════

-- Cierra los intentos vencidos. Idempotente: se puede llamar cada hora (cron)
-- y tambien al abrir la bandeja del admin.
create or replace function flow.reserva_pago_expirar()
returns jsonb
language plpgsql
security definer
set search_path = flow, public
as $function$
declare
  v_pago     record;
  v_estado_res integer;
  v_estado_can integer;
  v_exp      int := 0;
  v_can      int := 0;
  v_serv     text;
  v_local    text;
  v_plan_id  bigint;
  v_num      bigint;
  v_turno    integer;
  v_cant     integer;
  v_fecha    timestamp;
begin
  select id into v_estado_res from flow.nom_estado_agenda where nombre = 'Reservado' limit 1;
  select id into v_estado_can from flow.nom_estado_agenda where nombre = 'Cancelado' limit 1;

  for v_pago in
    select rp.id, rp.id_agenda, rp.id_entidad, rp.uuid_usuario, rp.monto, rp.moneda,
           a.id_local_servicio, a.cantidad, a.id_turno, a.fecha_hora_reserva, a.id_estado,
           coalesce(c.cancelar_si_expira, true) as cancelar
    from flow.reserva_pago rp
    join flow.agenda a on a.id = rp.id_agenda
    left join flow.cobro_config c on c.id_entidad = rp.id_entidad
    where rp.estado in ('creado', 'reportado')
      and rp.expira_at <= now()
    for update of rp
  loop
    update flow.reserva_pago set estado = 'expirado' where id = v_pago.id;
    v_exp := v_exp + 1;

    select s.nombre, l.nombre into v_serv, v_local
      from flow.local_servicio ls
      join flow.app_dat_servicios s on s.id = ls.id_servicio
      join flow.app_dat_locales   l on l.id = ls.id_local
     where ls.id = v_pago.id_local_servicio;

    if v_pago.cancelar and v_pago.id_estado = v_estado_res then
      update flow.agenda
         set id_estado = v_estado_can,
             motivo_cancelacion = 'No se verifico el pago por adelantado en el plazo',
             cancelado_por_rol  = 'sistema',
             cancelado_at       = current_timestamp,
             pago_estado        = 'expirado',
             updated_at         = current_timestamp
       where id = v_pago.id_agenda;

      -- Liberar capacidad (misma logica que las cancelaciones del panel).
      if v_pago.id_turno is not null then
        perform flow._liberar_tramos_turno(
          v_pago.id_turno,
          (v_pago.fecha_hora_reserva at time zone 'America/Havana')::date,
          v_pago.cantidad);
      else
        select ps.id into v_plan_id
          from flow.plan_servicios ps
         where ps.id_local_servicio = v_pago.id_local_servicio
           and (ps.fecha at time zone 'America/Havana')::date =
               (v_pago.fecha_hora_reserva at time zone 'America/Havana')::date
         limit 1;
        if v_plan_id is not null then
          update flow.plan_servicios
             set agendados = greatest(0, agendados - v_pago.cantidad)
           where id = v_plan_id;
        end if;
      end if;

      insert into flow.notificaciones
        (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
      values (
        v_pago.uuid_usuario, 'cancelacion', 'Reserva cancelada por pago no verificado',
        flow._mensaje_cancelacion(v_serv, v_local, v_pago.fecha_hora_reserva, 'sistema',
          'No se verifico el pago de ' || to_char(v_pago.monto, 'FM9999999990.00') || ' '
          || v_pago.moneda || ' en el plazo'),
        v_pago.id_local_servicio, v_pago.id_agenda,
        jsonb_build_object('fecha', v_pago.fecha_hora_reserva, 'estado', 'expirado',
                           'id_pago', v_pago.id)
      );
      v_can := v_can + 1;
    else
      update flow.agenda
         set pago_estado = 'expirado', updated_at = current_timestamp
       where id = v_pago.id_agenda;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'data',
    jsonb_build_object('expirados', v_exp, 'reservas_canceladas', v_can));
end;
$function$;

-- ══ 8. RLS ═════════════════════════════════════════════════════════════════

alter table flow.cobro_config enable row level security;

drop policy if exists cobro_config_select_entidad on flow.cobro_config;
create policy cobro_config_select_entidad on flow.cobro_config
  for select to authenticated
  using (flow._puede_ver_entidad(id_entidad) or public.fn_is_superadmin_full_access());

drop policy if exists cobro_config_write_superadmin on flow.cobro_config;
create policy cobro_config_write_superadmin on flow.cobro_config
  for all to authenticated
  using (public.fn_is_superadmin_full_access())
  with check (public.fn_is_superadmin_full_access());

alter table flow.reserva_pago enable row level security;

-- El cliente ve sus intentos; el admin de la entidad ve los de su entidad.
drop policy if exists reserva_pago_select_propio on flow.reserva_pago;
create policy reserva_pago_select_propio on flow.reserva_pago
  for select to authenticated
  using (uuid_usuario = auth.uid() or flow._puede_ver_entidad(id_entidad));

drop policy if exists reserva_pago_write_superadmin on flow.reserva_pago;
create policy reserva_pago_write_superadmin on flow.reserva_pago
  for all to authenticated
  using (public.fn_is_superadmin_full_access())
  with check (public.fn_is_superadmin_full_access());

-- ══ 9. GRANTS ══════════════════════════════════════════════════════════════

revoke all on flow.cobro_config, flow.reserva_pago from anon;
grant select on flow.cobro_config, flow.reserva_pago to authenticated;
grant all    on flow.cobro_config, flow.reserva_pago to service_role;

revoke all on function flow._monto_cobro_reserva(integer, text) from public, anon;
revoke all on function flow.admin_cobro_config_get(integer) from public, anon;
revoke all on function flow.admin_cobro_config_set(integer, boolean, text, text, text, text, text, text, integer, boolean) from public, anon;
revoke all on function flow.cliente_cobro_info(integer) from public, anon;
revoke all on function flow.cliente_crear_pago_reserva(integer) from public, anon;
revoke all on function flow.cliente_reportar_pago_reserva(bigint, text, text) from public, anon;
revoke all on function flow.cliente_pago_reserva(integer) from public, anon;
revoke all on function flow.admin_listar_pagos_reserva(integer, text) from public, anon;
revoke all on function flow.admin_verificar_pago_reserva(bigint, text) from public, anon;
revoke all on function flow.admin_rechazar_pago_reserva(bigint, text) from public, anon;
revoke all on function flow.reserva_pago_expirar() from public, anon;

grant execute on function flow.admin_cobro_config_get(integer) to authenticated;
grant execute on function flow.admin_cobro_config_set(integer, boolean, text, text, text, text, text, text, integer, boolean) to authenticated;
grant execute on function flow.cliente_cobro_info(integer) to authenticated;
grant execute on function flow.cliente_crear_pago_reserva(integer) to authenticated;
grant execute on function flow.cliente_reportar_pago_reserva(bigint, text, text) to authenticated;
grant execute on function flow.cliente_pago_reserva(integer) to authenticated;
grant execute on function flow.admin_listar_pagos_reserva(integer, text) to authenticated;
grant execute on function flow.admin_verificar_pago_reserva(bigint, text) to authenticated;
grant execute on function flow.admin_rechazar_pago_reserva(bigint, text) to authenticated;
grant execute on function flow.reserva_pago_expirar() to authenticated;

notify pgrst, 'reload schema';

-- ══ 10. VERIFICACION (ejecutar a mano despues de aplicar) ══════════════════
--
-- 10.a Tablas y columnas nuevas.
-- select
--   (select count(*) from flow.cobro_config)                                as configs,      -- 0
--   (select count(*) from flow.reserva_pago)                                as pagos,        -- 0
--   (select count(*) from information_schema.columns
--     where table_schema='flow' and table_name='agenda'
--       and column_name in ('pago_estado','pago_id','pago_monto','pago_moneda')) as cols;     -- 4
--
-- 10.b El pago NO aparece si no esta activo.
-- select flow.cliente_cobro_info(1);   -- {ok:true, data:{disponible:false}}
--
-- 10.c Activar el cobro sin numero de proveedor debe fallar.
-- select flow.admin_cobro_config_set(1, true, '', 'Mi negocio');  -- error explicito
--
-- 10.d Activar bien y comprobar el importe del cobro (necesita una reserva con precio).
-- select flow.admin_cobro_config_set(1, true, '4055432', 'Mi negocio', '5355555555', null, null, 'CUP', 24, true);
-- select flow.cliente_cobro_info(1);
-- select flow._monto_cobro_reserva(<id_agenda>, 'CUP');
--
-- 10.e La expiracion es idempotente (dos veces seguidas no cancela dos veces).
-- select flow.reserva_pago_expirar();
-- select flow.reserva_pago_expirar();
