-- ============================================================================
-- APLICAR EN RELEASE (vsieeihstajlrdvpuooh) - MIGRACIONES 60 A 67, EN ESTE ORDEN
--
-- Pegar TODO este archivo de una vez en el SQL Editor de release y ejecutar.
-- Es idempotente: se puede volver a ejecutar sin duplicar nada.
-- ============================================================================

-- #################### INICIO: 60_tasa_cambio_y_precio_config.sql ####################

-- ============================================================================
-- MIGRACION 60: cache diaria de la tasa de cambio ("el toque") + config de
--               precios automaticos por entidad
--
-- QUE RESUELVE
--   El admin escribe UN precio (p. ej. en USD) y la app calcula el resto de
--   monedas del servicio con la tasa del dia. La tasa NO se pide desde la app:
--   vive en Supabase (Edge Function `flow-tasas`) y se cachea aqui, un registro
--   por dia y fuente. Durante el dia se lee esta tabla; si el ultimo registro no
--   es de hoy, la Edge Function consulta la URL, recalcula y guarda.
--
-- TABLAS NUEVAS (schema `flow`)
--   * `flow.tasa_cambio`  â€” cache (una fila por dia y fuente).
--       tasas        jsonb: el JSON crudo del proveedor
--                            {"USD":{"CUP":840,"MLC":1.2,"USD":null}, ...}
--       conversiones jsonb: matriz normalizada y cruzada de las monedas de la
--                            app {"USD":{"CUP":840,"EUR":0.908,"MLC":1.204}, ...}
--                            Se calcula en la Edge Function: usa la tasa directa
--                            si existe y, si no, cruza por CUP
--                            (MLC->EUR = MLC->CUP / EUR->CUP).
--   * `flow.precio_config` â€” por entidad: si el calculo automatico esta activo,
--       la moneda de origen preferida y los decimales de redondeo.
--
-- FUNCIONES NUEVAS
--   * flow.tasas_actuales()                       -- lectura para la app
--   * flow.tasa_factor(p_origen, p_destino)       -- factor de conversion
--   * flow.admin_precio_config_get(p_id_entidad)
--   * flow.admin_precio_config_set(...)
--   * flow._puede_ver_entidad(p_id_entidad)       -- helper de permisos
--
-- LO QUE NO CAMBIA
--   * Ninguna columna ni funcion existente se toca.
--   * Sin Edge Function desplegada, `tasa_cambio` queda vacia y la app cae al
--     comportamiento actual (precios escritos a mano). No rompe nada.
--
-- REVERSION
--   drop table if exists flow.tasa_cambio;
--   drop table if exists flow.precio_config;
--   drop function if exists flow.tasas_actuales();
--   drop function if exists flow.tasa_factor(text, text);
--   drop function if exists flow.admin_precio_config_get(integer);
--   drop function if exists flow.admin_precio_config_set(integer, boolean, text, integer, integer);
--   drop function if exists flow._puede_ver_entidad(integer);
--
-- IDEMPOTENTE: si / not exists / create or replace / drop policy if exists.
-- ============================================================================

-- â•â• 1. TABLAS â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

create table if not exists flow.tasa_cambio (
  id           bigint generated always as identity primary key,
  fecha        date        not null,
  fuente       text        not null default 'directoriocubano',
  -- Texto tal cual lo publica el proveedor ("7:00 AM").
  hora         text,
  -- Momento en que se guardo la fila (y momento que publica el proveedor).
  actualizado  timestamptz not null default now(),
  tasas        jsonb       not null default '{}'::jsonb,
  conversiones jsonb       not null default '{}'::jsonb,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint tasa_cambio_fecha_fuente_uk unique (fecha, fuente),
  constraint tasa_cambio_tasas_obj_chk       check (jsonb_typeof(tasas) = 'object'),
  constraint tasa_cambio_conversiones_obj_chk check (jsonb_typeof(conversiones) = 'object')
);

comment on table flow.tasa_cambio is
  'Cache diaria de la tasa de cambio (el "toque"). Una fila por (fecha, fuente). La escribe la Edge Function flow-tasas; la app solo lee.';
comment on column flow.tasa_cambio.tasas is
  'JSON crudo del proveedor: {"USD":{"CUP":840,"MLC":1.2,"USD":null}, ...}';
comment on column flow.tasa_cambio.conversiones is
  'Matriz normalizada de las monedas de la app: {"USD":{"CUP":840,"EUR":0.9083,"MLC":1.2041,...}, ...}. Calculada cruzando por CUP cuando no hay tasa directa.';

create index if not exists idx_tasa_cambio_fecha_desc
  on flow.tasa_cambio (fecha desc, id desc);

create table if not exists flow.precio_config (
  id_entidad      integer primary key
                  references flow.entidad (id) on delete cascade,
  auto_activo     boolean  not null default true,
  moneda_origen   text     not null default 'USD',
  redondeo_cup    smallint not null default 0,
  redondeo_divisa smallint not null default 2,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  updated_by      uuid,
  constraint precio_config_moneda_chk
    check (moneda_origen in ('USD', 'EUR', 'CUP', 'MLC')),
  constraint precio_config_redondeo_cup_chk
    check (redondeo_cup between 0 and 2),
  constraint precio_config_redondeo_divisa_chk
    check (redondeo_divisa between 0 and 2)
);

comment on table flow.precio_config is
  'Configuracion por entidad del calculo automatico de precios por tasa de cambio: si esta activo, la moneda de origen preferida y los decimales de redondeo por tipo de moneda.';

drop trigger if exists trg_precio_config_updated_at on flow.precio_config;
create trigger trg_precio_config_updated_at
  before update on flow.precio_config
  for each row execute function flow.update_updated_at_column();

-- â•â• 2. HELPERS â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

-- Permiso de lectura/administracion de una entidad: dueÃ±o, `entidad_admin` o
-- superadmin. Se reutiliza en las migraciones 61-63.
create or replace function flow._puede_ver_entidad(p_id_entidad integer)
returns boolean
language sql
stable
security definer
set search_path = flow, public
as $function$
  select
    p_id_entidad is not null
    and (
      public.fn_is_superadmin_full_access()
      or exists (
        select 1 from flow.entidad e
        where e.id = p_id_entidad and e.owner_uuid = auth.uid()
      )
      or exists (
        select 1 from flow.entidad_admin ea
        where ea.id_entidad = p_id_entidad and ea.uuid_usuario = auth.uid()
      )
    );
$function$;

comment on function flow._puede_ver_entidad(integer) is
  'true si el llamador es dueÃ±o, entidad_admin o superadmin de la entidad.';

-- Ultima tasa cacheada, con el mismo formato que devuelve la Edge Function.
create or replace function flow.tasas_actuales()
returns jsonb
language plpgsql
stable
security definer
set search_path = flow, public
as $function$
declare
  v_row flow.tasa_cambio%rowtype;
  v_hoy date := (timezone('America/Havana', now()))::date;
begin
  select * into v_row
  from flow.tasa_cambio
  order by fecha desc, id desc
  limit 1;

  if v_row.id is null then
    return jsonb_build_object('ok', false, 'error', 'sin tasas en cache');
  end if;

  return jsonb_build_object(
    'ok',           true,
    'fecha',        v_row.fecha,
    'hora',         v_row.hora,
    'fuente',       v_row.fuente,
    'actualizado',  v_row.actualizado,
    'vigente',      v_row.fecha = v_hoy,
    'tasas',        v_row.tasas,
    'conversiones', v_row.conversiones
  );
end;
$function$;

comment on function flow.tasas_actuales() is
  'Devuelve la ultima tasa cacheada. `vigente` = false significa que la Edge Function debe refrescarla.';

-- Factor de conversion origen -> destino (1 unidad de origen = N de destino).
create or replace function flow.tasa_factor(p_origen text, p_destino text)
returns numeric
language plpgsql
stable
security definer
set search_path = flow, public
as $function$
declare
  v_conv jsonb;
  v_o    text := upper(btrim(coalesce(p_origen,  '')));
  v_d    text := upper(btrim(coalesce(p_destino, '')));
  v_val  numeric;
begin
  if v_o = '' or v_d = '' then
    return null;
  end if;
  if v_o = v_d then
    return 1;
  end if;

  select conversiones into v_conv
  from flow.tasa_cambio
  order by fecha desc, id desc
  limit 1;

  if v_conv is null then
    return null;
  end if;

  v_val := nullif(v_conv -> v_o ->> v_d, '')::numeric;

  -- Cruce por CUP: 1 origen = (origen->CUP) / (destino->CUP) destinos.
  if v_val is null then
    declare
      v_o_cup numeric := nullif(v_conv -> v_o ->> 'CUP', '')::numeric;
      v_d_cup numeric := nullif(v_conv -> v_d ->> 'CUP', '')::numeric;
    begin
      if v_o_cup is not null and v_d_cup is not null and v_d_cup <> 0 then
        v_val := v_o_cup / v_d_cup;
      end if;
    end;
  end if;

  return v_val;
end;
$function$;

comment on function flow.tasa_factor(text, text) is
  'Factor de conversion entre dos monedas usando la cache. Usa la tasa directa y, si no existe, cruza por CUP.';

-- â•â• 3. RPC DE CONFIGURACION DE PRECIOS â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

create or replace function flow.admin_precio_config_get(p_id_entidad integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = flow, public
as $function$
declare
  v_row flow.precio_config%rowtype;
begin
  if not flow._puede_ver_entidad(p_id_entidad) then
    return jsonb_build_object('ok', false, 'error', 'No tiene permisos sobre esta entidad');
  end if;

  select * into v_row from flow.precio_config where id_entidad = p_id_entidad;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id_entidad',      p_id_entidad,
      'auto_activo',     coalesce(v_row.auto_activo, true),
      'moneda_origen',   coalesce(v_row.moneda_origen, 'USD'),
      'redondeo_cup',    coalesce(v_row.redondeo_cup, 0),
      'redondeo_divisa', coalesce(v_row.redondeo_divisa, 2),
      'tiene_fila',      v_row.id_entidad is not null
    )
  );
end;
$function$;

create or replace function flow.admin_precio_config_set(
  p_id_entidad      integer,
  p_auto_activo     boolean default true,
  p_moneda_origen   text    default 'USD',
  p_redondeo_cup    integer default 0,
  p_redondeo_divisa integer default 2
)
returns jsonb
language plpgsql
security definer
set search_path = flow, public
as $function$
declare
  v_moneda text := upper(btrim(coalesce(p_moneda_origen, 'USD')));
begin
  if not flow._puede_ver_entidad(p_id_entidad) then
    return jsonb_build_object('ok', false, 'error', 'No tiene permisos sobre esta entidad');
  end if;

  if v_moneda not in ('USD', 'EUR', 'CUP', 'MLC') then
    return jsonb_build_object('ok', false, 'error', 'Moneda de origen no soportada');
  end if;

  if coalesce(p_redondeo_cup, 0) not between 0 and 2
     or coalesce(p_redondeo_divisa, 2) not between 0 and 2 then
    return jsonb_build_object('ok', false, 'error', 'El redondeo debe estar entre 0 y 2 decimales');
  end if;

  insert into flow.precio_config
    (id_entidad, auto_activo, moneda_origen, redondeo_cup, redondeo_divisa, updated_by)
  values
    (p_id_entidad, coalesce(p_auto_activo, true), v_moneda,
     coalesce(p_redondeo_cup, 0), coalesce(p_redondeo_divisa, 2), auth.uid())
  on conflict (id_entidad) do update
    set auto_activo     = excluded.auto_activo,
        moneda_origen   = excluded.moneda_origen,
        redondeo_cup    = excluded.redondeo_cup,
        redondeo_divisa = excluded.redondeo_divisa,
        updated_by      = excluded.updated_by,
        updated_at      = now();

  return flow.admin_precio_config_get(p_id_entidad);
end;
$function$;

-- â•â• 4. RLS â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- Criterio (el mismo de la 43): LECTURA por politica, ESCRITURA por RPC
-- `security definer` o service_role. La RLS es la red de seguridad.

alter table flow.tasa_cambio enable row level security;

-- Las tasas no son secretas: cualquier usuario con sesion las necesita para
-- ver precios. La escritura la hace la Edge Function con service_role (que
-- salta la RLS), por eso no hay politica de INSERT/UPDATE para authenticated.
drop policy if exists tasa_cambio_select_autenticados on flow.tasa_cambio;
create policy tasa_cambio_select_autenticados on flow.tasa_cambio
  for select to authenticated using (true);

alter table flow.precio_config enable row level security;

drop policy if exists precio_config_select_entidad on flow.precio_config;
create policy precio_config_select_entidad on flow.precio_config
  for select to authenticated
  using (flow._puede_ver_entidad(id_entidad) or public.fn_is_superadmin_full_access());

drop policy if exists precio_config_write_superadmin on flow.precio_config;
create policy precio_config_write_superadmin on flow.precio_config
  for all to authenticated
  using (public.fn_is_superadmin_full_access())
  with check (public.fn_is_superadmin_full_access());

-- â•â• 5. GRANTS â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

revoke all on flow.tasa_cambio, flow.precio_config from anon;

grant select on flow.tasa_cambio, flow.precio_config to authenticated;
grant all    on flow.tasa_cambio, flow.precio_config to service_role;

-- [FIX] El permiso sobre las TABLAS no basta: sin USAGE en el schema, cualquier
-- lectura de `flow.*` con el rol service_role falla con
-- Â«permission denied for schema flowÂ». Lo necesita la Edge Function `flow-tasas`,
-- que corre con service_role (en release `flow` solo se lo habia concedido a
-- anon y authenticated).
grant usage on schema flow to service_role;

-- La RLS necesita poder evaluar el helper.
grant execute on function flow._puede_ver_entidad(integer) to authenticated;

revoke all on function flow.tasas_actuales() from public, anon;
revoke all on function flow.tasa_factor(text, text) from public, anon;
revoke all on function flow.admin_precio_config_get(integer) from public, anon;
revoke all on function flow.admin_precio_config_set(integer, boolean, text, integer, integer) from public, anon;

grant execute on function flow.tasas_actuales() to authenticated;
grant execute on function flow.tasa_factor(text, text) to authenticated;
grant execute on function flow.admin_precio_config_get(integer) to authenticated;
grant execute on function flow.admin_precio_config_set(integer, boolean, text, integer, integer) to authenticated;

-- â•â• 6. VERIFICACION (ejecutar a mano despues de aplicar) â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--
-- 6.a Las dos tablas existen y estan vacias.
-- select
--   (select count(*) from flow.tasa_cambio)   as tasas,     -- 0
--   (select count(*) from flow.precio_config) as configs;   -- 0
--
-- 6.b Inserta una tasa de prueba y comprueba el cruce por CUP.
-- insert into flow.tasa_cambio (fecha, hora, conversiones) values (
--   (timezone('America/Havana', now()))::date, 'prueba',
--   '{"USD":{"CUP":840,"EUR":0.908,"MLC":1.2041},"EUR":{"CUP":925,"USD":1.1012,"MLC":1.3262},"MLC":{"CUP":697.62,"USD":0.8307,"EUR":0.7542},"CUP":{"USD":0.001190,"EUR":0.001081,"MLC":0.001434}}'::jsonb
-- );
-- select flow.tasa_factor('USD','CUP')  as usd_cup,   -- 840
--        flow.tasa_factor('MLC','EUR')  as mlc_eur,   -- 0.7542 (directa)
--        flow.tasa_factor('EUR','USD')  as eur_usd;   -- 1.1012
-- delete from flow.tasa_cambio where hora = 'prueba';
--
-- 6.c El RPC de config responde con permisos y con error sin ellos.
-- select flow.admin_precio_config_get(1);   -- {ok:true,...} siendo admin de la entidad 1
--
-- 6.d RLS activa y sin escritura abierta.
-- select tablename, policyname, cmd, roles from pg_policies
--  where schemaname = 'flow' and tablename in ('tasa_cambio','precio_config')
--  order by tablename, policyname;

-- #################### FIN: 60_tasa_cambio_y_precio_config.sql ####################

-- #################### INICIO: 61_cancelacion_motivo_y_notificacion.sql ####################

-- ============================================================================
-- MIGRACION 61: motivo de cancelacion + notificacion en rojo al cliente
--
-- QUE RESUELVE
--   1. El admin (y el vendedor) cancelaban una reserva SIN decir por que y, en el
--      caso de `admin_cancelar_agenda`, SIN avisar al cliente: la reserva
--      desaparecia de su lista sin una sola notificacion.
--   2. El cliente que cancelaba tampoco podia explicar nada.
--   3. Todas las notificaciones de cancelacion viajaban con `tipo = 'reserva'`,
--      el mismo que una reserva creada, asi que en la campana salian en verde.
--
-- QUE CAMBIA
--   * `flow.agenda` gana 4 columnas de auditoria de la cancelacion:
--       motivo_cancelacion  text  â€” lo que escribio quien cancelo
--       cancelado_por       uuid  â€” quien la cancelo
--       cancelado_por_rol   text  â€” 'cliente' | 'admin' | 'staff' | 'sistema'
--       cancelado_at        timestamptz
--   * Las 4 funciones de cancelacion aceptan `p_motivo text default null`
--     (se DROP-ean las versiones viejas: dejar dos sobrecargas rompe a PostgREST,
--     que no elige candidata entre aridades distintas).
--   * La notificacion al titular pasa a `tipo = 'cancelacion'` (rojo en la app)
--     y lleva el motivo en `mensaje` y en `data.motivo`.
--   * `admin_cancelar_agenda` AHORA SI notifica al titular. Antes no lo hacia.
--
-- LO QUE NO CAMBIA
--   * La liberacion de capacidad (tramos/`plan_servicios`) y la validacion de
--     estados: identicas.
--   * Reactivar y completar siguen notificando con `tipo = 'reserva'`.
--   * Las firmas VIEJAS dejan de existir (drop + create). Ninguna otra app del
--     repo llama a estas funciones.
--
-- REVERSION
--   `alter table flow.agenda drop column if exists motivo_cancelacion, ...` y
--   volver a aplicar los cuerpos de `24_staff_marcar_estado_agenda.sql`,
--   `58_reactivar_reserva_cancelada.sql`, `12_cliente_cancelar_reserva.sql`.
--
-- IDEMPOTENTE: `if not exists` + `drop function if exists` + `create or replace`.
-- ============================================================================

-- â•â• 1. COLUMNAS DE CANCELACION â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

alter table flow.agenda add column if not exists motivo_cancelacion text;
alter table flow.agenda add column if not exists cancelado_por       uuid;
alter table flow.agenda add column if not exists cancelado_por_rol   text;
alter table flow.agenda add column if not exists cancelado_at        timestamptz;

alter table flow.agenda drop constraint if exists agenda_cancelado_rol_chk;
alter table flow.agenda add  constraint agenda_cancelado_rol_chk
  check (cancelado_por_rol is null
         or cancelado_por_rol in ('cliente', 'admin', 'staff', 'sistema'));

comment on column flow.agenda.motivo_cancelacion is
  'Motivo que escribio quien cancelo la reserva. Se muestra al cliente en la notificacion y en el detalle de la reserva.';
comment on column flow.agenda.cancelado_por is 'Usuario que cancelo la reserva.';
comment on column flow.agenda.cancelado_por_rol is
  'Rol desde el que se cancelo: cliente, admin, staff o sistema (expiracion de pago).';
comment on column flow.agenda.cancelado_at is 'Momento de la cancelacion.';

create index if not exists idx_agenda_canceladas
  on flow.agenda (cancelado_at desc)
  where motivo_cancelacion is not null;

-- â•â• 2. HELPER: texto de la notificacion de cancelacion â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- Una sola funcion arma el mensaje para las 4 vias de cancelacion: asi el
-- cliente lee siempre lo mismo, con o sin motivo.

create or replace function flow._mensaje_cancelacion(
  p_servicio text,
  p_local    text,
  p_fecha    timestamptz,
  p_rol      text,
  p_motivo   text
)
returns text
language sql
immutable
set search_path = flow, public
as $function$
  select
    case
      when coalesce(btrim(p_motivo), '') <> '' then
        'Se ha cancelado tu reserva para "' || coalesce(p_servicio, 'el servicio')
        || '" en "' || coalesce(p_local, 'el local') || '" del '
        || to_char(p_fecha, 'DD/MM/YYYY') || '. Motivo: ' || btrim(p_motivo)
      else
        'Se ha cancelado tu reserva para "' || coalesce(p_servicio, 'el servicio')
        || '" en "' || coalesce(p_local, 'el local') || '" del '
        || to_char(p_fecha, 'DD/MM/YYYY')
        || case when p_rol = 'cliente' then '.' else ' por la administracion.' end
    end;
$function$;

comment on function flow._mensaje_cancelacion(text, text, timestamptz, text, text) is
  'Mensaje unico de la notificacion de cancelacion, con el motivo al final cuando existe.';

-- â•â• 3. staff_marcar_estado_agenda (+ p_motivo) â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

drop function if exists flow.staff_marcar_estado_agenda(integer, integer);

create or replace function flow.staff_marcar_estado_agenda(
  p_id_agenda integer,
  p_id_estado integer,
  p_motivo    text default null
)
returns json
language plpgsql
security definer
set search_path = flow, public
as $function$
declare
  v_agenda        record;
  v_id_reservado  int;
  v_id_cancelado  int;
  v_plan_id       bigint;
  v_result        json;
  v_nombre_serv   text;
  v_nombre_local  text;
  v_fecha_dia     date;
  v_hoy           date;
  v_motivo        text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  -- [58] Estados destino validos: Reservado (1, solo al reactivar), Cancelado (2)
  -- o Completado (3).
  if p_id_estado not in (1, 2, 3) then
    raise exception 'Estado destino no permitido (use Reservado, Cancelado o Completado)';
  end if;

  -- [61] El motivo es obligatorio al cancelar desde el panel: el cliente tiene
  -- que saber por que le quitaron la reserva.
  if p_id_estado = 2 and v_motivo is null then
    raise exception 'Debes indicar el motivo de la cancelacion';
  end if;

  -- Autorizacion: owner / admin / vendedor de la entidad de la reserva.
  if not exists (
    select 1
    from flow.agenda a
    join flow.local_servicio ls on ls.id = a.id_local_servicio
    join flow.app_dat_locales l on l.id = ls.id_local
    where a.id = p_id_agenda
      and (
        l.id_entidad in (select id from flow.entidad where owner_uuid = auth.uid())
        or exists (
          select 1 from flow.entidad_admin ea
          where ea.id_entidad = l.id_entidad and ea.uuid_usuario = auth.uid()
        )
        or exists (
          select 1 from flow.entidad_vendedor ev
          where ev.id_entidad = l.id_entidad and ev.uuid_usuario = auth.uid()
        )
      )
  ) then
    raise exception 'No tiene permisos sobre esta reserva';
  end if;

  -- Cargar la reserva (incluye id_turno para re-consumir la capacidad correcta).
  select a.id, a.uuid_usuario, a.id_local_servicio, a.id_estado,
         a.fecha_hora_reserva, a.cantidad, a.id_turno
    into v_agenda
    from flow.agenda a
   where a.id = p_id_agenda;

  select id into v_id_reservado from flow.nom_estado_agenda where nombre = 'Reservado';
  select id into v_id_cancelado from flow.nom_estado_agenda where nombre = 'Cancelado';

  v_fecha_dia := (v_agenda.fecha_hora_reserva at time zone 'America/Havana')::date;
  v_hoy       := (current_timestamp at time zone 'America/Havana')::date;

  -- Reglas por transicion.
  if p_id_estado = 2 then
    -- Cancelar: solo desde activa (Reservado).
    if v_agenda.id_estado is distinct from v_id_reservado then
      raise exception 'Solo se pueden cancelar reservas activas';
    end if;
  elsif p_id_estado = 1 then
    -- [58] Reactivar: solo desde cancelada y solo si no ha pasado.
    if v_agenda.id_estado is distinct from v_id_cancelado then
      raise exception 'Solo se pueden reactivar reservas canceladas';
    end if;
    if v_fecha_dia < v_hoy then
      raise exception 'Solo se pueden reactivar reservas de hoy o fechas futuras';
    end if;
  else
    -- Completar: desde activa, o desde cancelada si la fecha es hoy o anterior.
    if v_agenda.id_estado = v_id_reservado then
      null;  -- ok
    elsif v_agenda.id_estado = v_id_cancelado then
      if v_fecha_dia > v_hoy then
        raise exception 'Solo se pueden completar reservas canceladas de hoy o fechas anteriores';
      end if;
    else
      raise exception 'Esta reserva no se puede completar en su estado actual';
    end if;
  end if;

  -- Capacidad:
  --   cancelar           -> liberar (baja agendados)
  --   reactivar          -> re-consumir lo que libero la cancelacion
  --   completar desde
  --     cancelada        -> re-consumir (sube agendados, acotado a la capacidad)
  --     reservado        -> no toca (ya estaba consumida al reservar)
  if p_id_estado = 2 then
    if v_agenda.id_turno is not null then
      update flow.plan_tramo pt
         set agendados = greatest(0, pt.agendados - v_agenda.cantidad)
      from flow.turno_tramo tt
      join flow.tramo tr on tr.id = tt.id_tramo
      where tt.id_turno = v_agenda.id_turno
        and pt.id_tramo = tr.id
        and (pt.fecha at time zone 'America/Havana')::date = v_fecha_dia;
    else
      select ps.id into v_plan_id
        from flow.plan_servicios ps
       where ps.id_local_servicio = v_agenda.id_local_servicio
         and (ps.fecha at time zone 'America/Havana')::date = v_fecha_dia
       limit 1;
      if v_plan_id is not null then
        update flow.plan_servicios
           set agendados = greatest(0, agendados - v_agenda.cantidad)
         where id = v_plan_id;
      end if;
    end if;
  elsif p_id_estado in (1, 3) and v_agenda.id_estado = v_id_cancelado then
    -- [58] Re-consumir capacidad liberada por la cancelacion (acotado a la
    -- capacidad total). Vale para reactivar (1) y para completar (3).
    if v_agenda.id_turno is not null then
      update flow.plan_tramo pt
         set agendados = least(pt.cantidad, pt.agendados + v_agenda.cantidad)
      from flow.turno_tramo tt
      join flow.tramo tr on tr.id = tt.id_tramo
      where tt.id_turno = v_agenda.id_turno
        and pt.id_tramo = tr.id
        and (pt.fecha at time zone 'America/Havana')::date = v_fecha_dia;
    else
      select ps.id into v_plan_id
        from flow.plan_servicios ps
       where ps.id_local_servicio = v_agenda.id_local_servicio
         and (ps.fecha at time zone 'America/Havana')::date = v_fecha_dia
       limit 1;
      if v_plan_id is not null then
        update flow.plan_servicios
           set agendados = least(cantidad, agendados + v_agenda.cantidad)
         where id = v_plan_id;
      end if;
    end if;
  end if;

  -- Actualizar el estado. Al completar se sella la atencion; al reactivar se
  -- limpia (vuelve a estar pendiente de atencion).
  -- [61] Al cancelar se guarda el motivo y quien cancelo. Al reactivar se borra
  -- la huella de la cancelacion anterior (la reserva vuelve a estar viva).
  update flow.agenda
     set id_estado = p_id_estado,
         fecha_hora_atencion = case
                                 when p_id_estado = 3 then current_timestamp
                                 when p_id_estado = 1 then null
                                 else fecha_hora_atencion
                               end,
         motivo_cancelacion = case when p_id_estado = 2 then v_motivo
                                   when p_id_estado = 1 then null
                                   else motivo_cancelacion end,
         cancelado_por      = case when p_id_estado = 2 then auth.uid()
                                   when p_id_estado = 1 then null
                                   else cancelado_por end,
         cancelado_por_rol  = case when p_id_estado = 2 then 'staff'
                                   when p_id_estado = 1 then null
                                   else cancelado_por_rol end,
         cancelado_at       = case when p_id_estado = 2 then current_timestamp
                                   when p_id_estado = 1 then null
                                   else cancelado_at end,
         updated_at = current_timestamp
   where id = p_id_agenda;

  -- Notificar al titular: al cancelar, y tambien cuando la reserva SALE de
  -- cancelada (reactivada a pendiente, o completada desde cancelada).
  if p_id_estado in (1, 2, 3) and v_agenda.uuid_usuario is not null then
    select s.nombre, l.nombre into v_nombre_serv, v_nombre_local
      from flow.local_servicio ls
      join flow.app_dat_servicios s on s.id = ls.id_servicio
      join flow.app_dat_locales   l on l.id = ls.id_local
     where ls.id = v_agenda.id_local_servicio;

    if p_id_estado = 2 then
      -- [61] tipo 'cancelacion' => se pinta en ROJO en la campana del cliente.
      insert into flow.notificaciones
        (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
      values (
        v_agenda.uuid_usuario, 'cancelacion', 'Reserva cancelada',
        flow._mensaje_cancelacion(v_nombre_serv, v_nombre_local,
                                  v_agenda.fecha_hora_reserva, 'staff', v_motivo),
        v_agenda.id_local_servicio, p_id_agenda,
        jsonb_build_object(
          'fecha',    v_agenda.fecha_hora_reserva,
          'motivo',   v_motivo,
          'cancelada_por', 'administracion'
        )
      );
    elsif v_agenda.id_estado = v_id_cancelado then
      insert into flow.notificaciones
        (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
      values (
        v_agenda.uuid_usuario, 'reserva',
        case when p_id_estado = 1 then 'Reserva reactivada'
             else 'Reserva completada' end,
        case when p_id_estado = 1
             then 'Su reserva para "' || coalesce(v_nombre_serv, 'el servicio')
                  || '" en "' || coalesce(v_nombre_local, 'el local')
                  || '" del ' || to_char(v_agenda.fecha_hora_reserva, 'DD/MM/YYYY')
                  || ' vuelve a estar activa.'
             else 'Su reserva para "' || coalesce(v_nombre_serv, 'el servicio')
                  || '" en "' || coalesce(v_nombre_local, 'el local')
                  || '" del ' || to_char(v_agenda.fecha_hora_reserva, 'DD/MM/YYYY')
                  || ' se ha marcado como completada.'
        end,
        v_agenda.id_local_servicio, p_id_agenda,
        jsonb_build_object('fecha', v_agenda.fecha_hora_reserva, 'estado', p_id_estado)
      );
    end if;
  end if;

  -- Devolver la agenda actualizada (formato Agenda.fromJson) + los campos nuevos.
  select json_build_object(
    'id', a.id,
    'uuid_usuario', a.uuid_usuario,
    'id_local_servicio', a.id_local_servicio,
    'id_estado', a.id_estado,
    'fecha_hora_reserva', a.fecha_hora_reserva,
    'fecha_hora_atencion', a.fecha_hora_atencion,
    'created_at', a.created_at,
    'updated_at', a.updated_at,
    'cantidad', a.cantidad,
    'datos_adicionales', a.datos_adicionales,
    'reservado_por', a.reservado_por,
    'id_turno', a.id_turno,
    'motivo_cancelacion', a.motivo_cancelacion,
    'cancelado_por', a.cancelado_por,
    'cancelado_por_rol', a.cancelado_por_rol,
    'cancelado_at', a.cancelado_at,
    'nom_estado_agenda', json_build_object(
      'id', nea.id, 'nombre', nea.nombre, 'descripcion', nea.descripcion
    )
  ) into v_result
  from flow.agenda a
  join flow.nom_estado_agenda nea on nea.id = a.id_estado
  where a.id = p_id_agenda;

  return v_result;
end;
$function$;

-- â•â• 4. staff_cancelar_reserva (+ p_motivo) â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

drop function if exists flow.staff_cancelar_reserva(integer);

create or replace function flow.staff_cancelar_reserva(
  p_id_agenda integer,
  p_motivo    text default null
)
returns json
language plpgsql
security definer
set search_path = flow, public
as $function$
DECLARE
  v_agenda    RECORD;
  v_regreso   RECORD;
  v_result    JSON;
  v_id_reservado INTEGER;
  v_motivo    TEXT := nullif(btrim(coalesce(p_motivo, '')), '');
BEGIN
  IF v_motivo IS NULL THEN
    RAISE EXCEPTION 'Debes indicar el motivo de la cancelacion';
  END IF;

  SELECT a.id, a.id_viaje, a.tipo_trayecto
  INTO v_agenda
  FROM flow.agenda a
  WHERE a.id = p_id_agenda
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Reserva no encontrada';
  END IF;

  SELECT id
  INTO v_id_reservado
  FROM flow.nom_estado_agenda
  WHERE nombre = 'Reservado';

  v_result := flow.staff_marcar_estado_agenda(p_id_agenda, 2, v_motivo);

  IF v_agenda.tipo_trayecto = 'ida' AND v_agenda.id_viaje IS NOT NULL THEN
    FOR v_regreso IN
      SELECT a.id
      FROM flow.agenda a
      WHERE a.id_viaje = v_agenda.id_viaje
        AND a.tipo_trayecto = 'vuelta'
        AND a.id_estado = v_id_reservado
      ORDER BY a.id
      FOR UPDATE
    LOOP
      PERFORM flow.staff_marcar_estado_agenda(v_regreso.id, 2, v_motivo);
    END LOOP;
  END IF;

  RETURN v_result;
END;
$function$;

-- â•â• 5. admin_cancelar_agenda (+ p_motivo, + notificacion) â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

drop function if exists flow.admin_cancelar_agenda(integer);

create or replace function flow.admin_cancelar_agenda(
  p_id_agenda integer,
  p_motivo    text default null
)
returns json
language plpgsql
security definer
set search_path = flow
as $function$
declare
  v_id_estado int;
  v_id_estado_reservado int;
  v_result json;
  v_agenda record;
  v_plan_id bigint;
  v_nombre_serv text;
  v_nombre_local text;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_rol text;
  v_resultado jsonb;
begin
  if v_motivo is null then
    raise exception 'Debes indicar el motivo de la cancelacion';
  end if;

  if not exists (
    select 1
    from flow.agenda a
    join flow.local_servicio ls on ls.id = a.id_local_servicio
    join flow.app_dat_locales l on l.id = ls.id_local
    where a.id = p_id_agenda
      and (
        auth.uid() = a.uuid_usuario
        or l.id_entidad in (select id from flow.entidad where owner_uuid = auth.uid())
        or exists (
          select 1 from flow.entidad_admin ea
          where ea.id_entidad = l.id_entidad and ea.uuid_usuario = auth.uid()
        )
      )
  ) then
    raise exception 'No tiene permisos para cancelar esta reserva';
  end if;

  select a.id, a.uuid_usuario, a.id_local_servicio, a.id_estado,
         a.fecha_hora_reserva, a.cantidad, a.id_turno
    into v_agenda
    from flow.agenda a
   where a.id = p_id_agenda;

  select id into v_id_estado_reservado from flow.nom_estado_agenda where nombre = 'Reservado';

  if v_agenda.id_estado is distinct from v_id_estado_reservado then
    raise exception 'Solo se pueden cancelar reservas activas';
  end if;

  select id into v_id_estado from flow.nom_estado_agenda where nombre = 'Cancelado';
  if v_id_estado is null then
    raise exception 'Estado cancelado no encontrado';
  end if;

  -- [61] Quien cancela: el propio titular o la administracion.
  v_rol := case when auth.uid() = v_agenda.uuid_usuario then 'cliente' else 'admin' end;

  update flow.agenda
     set id_estado = v_id_estado,
         motivo_cancelacion = v_motivo,
         cancelado_por = auth.uid(),
         cancelado_por_rol = v_rol,
         cancelado_at = current_timestamp,
         updated_at = current_timestamp
   where id = p_id_agenda;

  -- Liberar capacidad: plan_tramo si la reserva tiene turno, si no plan_servicios.
  if v_agenda.id_turno is not null then
    perform flow._liberar_tramos_turno(
      v_agenda.id_turno,
      (v_agenda.fecha_hora_reserva at time zone 'America/Havana')::date,
      v_agenda.cantidad);
  else
    select ps.id into v_plan_id
      from flow.plan_servicios ps
     where ps.id_local_servicio = v_agenda.id_local_servicio
       and (ps.fecha at time zone 'America/Havana')::date =
           (v_agenda.fecha_hora_reserva at time zone 'America/Havana')::date
     limit 1;
    if v_plan_id is not null then
      update flow.plan_servicios
         set agendados = greatest(0, agendados - v_agenda.cantidad)
       where id = v_plan_id;
    end if;
  end if;

  -- [61] Notificar al TITULAR (antes esta funcion no avisaba a nadie). Si el que
  -- cancela es el propio titular â€”caso raro por esta viaâ€” no se auto-notifica.
  if v_agenda.uuid_usuario is not null and v_agenda.uuid_usuario <> auth.uid() then
    select s.nombre, l.nombre into v_nombre_serv, v_nombre_local
      from flow.local_servicio ls
      join flow.app_dat_servicios s on s.id = ls.id_servicio
      join flow.app_dat_locales   l on l.id = ls.id_local
     where ls.id = v_agenda.id_local_servicio;

    insert into flow.notificaciones
      (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
    values (
      v_agenda.uuid_usuario,
      'cancelacion',
      'Reserva cancelada',
      flow._mensaje_cancelacion(v_nombre_serv, v_nombre_local,
                                v_agenda.fecha_hora_reserva, v_rol, v_motivo),
      v_agenda.id_local_servicio,
      v_agenda.id,
      jsonb_build_object(
        'fecha',         v_agenda.fecha_hora_reserva,
        'motivo',        v_motivo,
        'cancelada_por', v_rol
      )
    );
  end if;

  select json_build_object(
    'id', a.id,
    'uuid_usuario', a.uuid_usuario,
    'id_local_servicio', a.id_local_servicio,
    'id_estado', a.id_estado,
    'fecha_hora_reserva', a.fecha_hora_reserva,
    'fecha_hora_atencion', a.fecha_hora_atencion,
    'created_at', a.created_at,
    'updated_at', a.updated_at,
    'cantidad', a.cantidad,
    'datos_adicionales', a.datos_adicionales,
    'reservado_por', a.reservado_por,
    'id_turno', a.id_turno,
    'motivo_cancelacion', a.motivo_cancelacion,
    'cancelado_por', a.cancelado_por,
    'cancelado_por_rol', a.cancelado_por_rol,
    'cancelado_at', a.cancelado_at,
    'nom_estado_agenda', json_build_object(
      'id', nea.id, 'nombre', nea.nombre, 'descripcion', nea.descripcion
    ),
    'local_servicio', json_build_object(
      'id', ls.id,
      'id_local', ls.id_local,
      'id_servicio', ls.id_servicio,
      'permite_reserva_directa', ls.permite_reserva_directa,
      'app_dat_locales', (select row_to_json(x) from (
        select ll.id, ll.nombre, ll.direccion from flow.app_dat_locales ll where ll.id = ls.id_local) x),
      'app_dat_servicios', (select row_to_json(y) from (
        select ss.id, ss.nombre from flow.app_dat_servicios ss where ss.id = ls.id_servicio) y)
    )
  ) into v_result
  from flow.agenda a
  join flow.nom_estado_agenda nea on nea.id = a.id_estado
  join flow.local_servicio ls on ls.id = a.id_local_servicio
  where a.id = p_id_agenda;

  return v_result;
end;
$function$;

-- â•â• 6. cliente_cancelar_reserva (+ p_motivo opcional) â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

drop function if exists flow.cliente_cancelar_reserva(uuid, integer);

create or replace function flow.cliente_cancelar_reserva(
  p_uuid_usuario uuid,
  p_id_agenda    integer,
  p_motivo       text default null
)
returns jsonb
language plpgsql
security definer
set search_path = flow, public
as $function$
declare
  v_agenda              flow.agenda%rowtype;
  v_estado_reservado    integer;
  v_estado_cancelado    integer;
  v_horas_anticipacion  integer;
  v_limite              timestamp without time zone;
  v_plan_id             bigint;
  v_nombre_servicio     text;
  v_nombre_local        text;
  v_motivo              text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  if p_uuid_usuario is null or p_id_agenda is null then
    return jsonb_build_object('ok', false, 'error', 'parametros obligatorios faltantes');
  end if;

  -- Estados
  select id into v_estado_reservado from flow.nom_estado_agenda where nombre = 'Reservado' limit 1;
  select id into v_estado_cancelado from flow.nom_estado_agenda where nombre = 'Cancelado' limit 1;
  if v_estado_reservado is null or v_estado_cancelado is null then
    return jsonb_build_object('ok', false, 'error', 'faltan estados de agenda');
  end if;

  -- Cargar la reserva y validar propiedad
  select a.* into v_agenda
  from flow.agenda a
  where a.id = p_id_agenda;

  if v_agenda.id is null then
    return jsonb_build_object('ok', false, 'error', 'Reserva no encontrada');
  end if;

  if v_agenda.uuid_usuario != p_uuid_usuario and v_agenda.reservado_por != p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'No tienes permiso para cancelar esta reserva');
  end if;

  if v_agenda.id_estado != v_estado_reservado then
    return jsonb_build_object('ok', false, 'error', 'Solo se pueden cancelar reservas activas');
  end if;

  -- Configuracion de cancelacion de la entidad
  select e.horas_anticipacion_cancelacion
    into v_horas_anticipacion
  from flow.local_servicio ls
  join flow.app_dat_locales l on l.id = ls.id_local
  join flow.entidad         e on e.id = l.id_entidad
  where ls.id = v_agenda.id_local_servicio;

  -- Solo validar ventana si la entidad configuro horas de anticipacion (>0).
  -- Si no hay configuracion (0 o null), el cliente puede cancelar en cualquier momento.
  if coalesce(v_horas_anticipacion, 0) > 0 then
    v_limite := v_agenda.fecha_hora_reserva - (v_horas_anticipacion || ' hours')::interval;
    if current_timestamp > v_limite then
      return jsonb_build_object('ok', false, 'error',
        'Solo puedes cancelar hasta ' || v_horas_anticipacion || ' horas antes de la reserva');
    end if;
  end if;

  -- Aplicar cancelacion en una transaccion implicita
  update flow.agenda
     set id_estado = v_estado_cancelado,
         motivo_cancelacion = v_motivo,
         cancelado_por = p_uuid_usuario,
         cancelado_por_rol = 'cliente',
         cancelado_at = current_timestamp,
         updated_at = current_timestamp
   where id = p_id_agenda;

  if v_agenda.id_turno is not null then
    update flow.plan_tramo pt
       set agendados = greatest(0, pt.agendados - v_agenda.cantidad)
      from flow.turno_tramo tt
     where tt.id_turno = v_agenda.id_turno
       and pt.id_tramo = tt.id_tramo
       and (pt.fecha at time zone 'America/Havana')::date =
           (v_agenda.fecha_hora_reserva at time zone 'America/Havana')::date;
  else
    -- Buscar plan del dia para restar agendados (sin forzar: puede no existir si el plan fue borrado)
    select ps.id
      into v_plan_id
    from flow.plan_servicios ps
    where ps.id_local_servicio = v_agenda.id_local_servicio
      and (ps.fecha at time zone 'America/Havana')::date =
          (v_agenda.fecha_hora_reserva at time zone 'America/Havana')::date
    limit 1;

    if v_plan_id is not null then
      update flow.plan_servicios
         set agendados = greatest(0, agendados - v_agenda.cantidad)
       where id = v_plan_id;
    end if;
  end if;

  -- Notificacion al cliente que cancelo (tipo 'cancelacion' = ROJO en la app)
  select s.nombre, l.nombre
    into v_nombre_servicio, v_nombre_local
  from flow.local_servicio ls
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  join flow.app_dat_locales   l on l.id = ls.id_local
  where ls.id = v_agenda.id_local_servicio;

  insert into flow.notificaciones
    (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
  values
    (p_uuid_usuario,
     'cancelacion',
     'Reserva cancelada',
     flow._mensaje_cancelacion(v_nombre_servicio, v_nombre_local,
                               v_agenda.fecha_hora_reserva, 'cliente', v_motivo),
     v_agenda.id_local_servicio,
     v_agenda.id,
     jsonb_build_object(
       'fecha',         v_agenda.fecha_hora_reserva,
       'servicio',      v_nombre_servicio,
       'local',         v_nombre_local,
       'cantidad',      v_agenda.cantidad,
       'motivo',        v_motivo,
       'cancelada_por', 'cliente'
     ));

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id_agenda', p_id_agenda,
      'fecha',     to_char(v_agenda.fecha_hora_reserva, 'YYYY-MM-DD')
    )
  );

exception
  when others then
    return jsonb_build_object('ok', false, 'error', sqlerrm, 'sqlstate', sqlstate);
end;
$function$;

-- â•â• 7. GRANTS â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

revoke all on function flow._mensaje_cancelacion(text, text, timestamptz, text, text) from public, anon;

revoke all on function flow.staff_marcar_estado_agenda(integer, integer, text) from public, anon;
revoke all on function flow.staff_cancelar_reserva(integer, text) from public, anon;
revoke all on function flow.admin_cancelar_agenda(integer, text) from public, anon;
revoke all on function flow.cliente_cancelar_reserva(uuid, integer, text) from public, anon;

grant execute on function flow.staff_marcar_estado_agenda(integer, integer, text) to authenticated;
grant execute on function flow.staff_cancelar_reserva(integer, text) to authenticated;
grant execute on function flow.admin_cancelar_agenda(integer, text) to authenticated;
grant execute on function flow.cliente_cancelar_reserva(uuid, integer, text) to authenticated;

-- â•â• 8. VERIFICACION (ejecutar a mano despues de aplicar) â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--
-- 8.a Las columnas nuevas existen.
-- select column_name, data_type from information_schema.columns
--  where table_schema='flow' and table_name='agenda'
--    and column_name in ('motivo_cancelacion','cancelado_por','cancelado_por_rol','cancelado_at');
--
-- 8.b Solo queda UNA version de cada funcion (sin sobrecargas).
-- select p.proname, count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--  where n.nspname='flow' and p.proname in ('staff_marcar_estado_agenda','staff_cancelar_reserva',
--        'admin_cancelar_agenda','cliente_cancelar_reserva')
--  group by p.proname;   -- cada una: 1
--
-- 8.c Cancelar sin motivo debe fallar (con una sesion de admin real).
-- select flow.admin_cancelar_agenda(1);            -- ERROR: Debes indicar el motivo...
-- select flow.staff_cancelar_reserva(1);           -- ERROR: Debes indicar el motivo...
--
-- 8.d Cancelar con motivo deja la huella y la notificacion en rojo.
-- select flow.admin_cancelar_agenda(1, 'Cambio de horario del local');
-- select id, id_estado, motivo_cancelacion, cancelado_por_rol, cancelado_at
--   from flow.agenda where id = 1;
-- select tipo, titulo, mensaje, data from flow.notificaciones
--  where id_referencia = 1 order by id desc limit 1;   -- tipo = 'cancelacion'

-- #################### FIN: 61_cancelacion_motivo_y_notificacion.sql ####################

-- #################### INICIO: 62_pago_adelantado_servicio.sql ####################

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
--   * flow.cobro_config  â€” por entidad: numeros, plantillas, moneda y plazo.
--   * flow.reserva_pago  â€” un intento por reserva (auditable e idempotente).
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

-- â•â• 1. TABLAS â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

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

-- â•â• 2. COLUMNAS DE PAGO EN LA AGENDA â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

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

-- â•â• 3. HELPER: importe del cobro â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
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

-- â•â• 4. CONFIG DEL COBRO (ADMIN) â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

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

-- â•â• 5. LADO CLIENTE â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

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

-- â•â• 6. LADO ADMIN: BANDEJA Y VERIFICACION â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

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

-- â•â• 7. EXPIRACION â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

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

-- â•â• 8. RLS â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

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

-- â•â• 9. GRANTS â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

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

-- â•â• 10. VERIFICACION (ejecutar a mano despues de aplicar) â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
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

-- #################### FIN: 62_pago_adelantado_servicio.sql ####################

-- #################### INICIO: 63_listados_motivo_pago_y_calendario.sql ####################

-- ============================================================================
-- MIGRACION 63: listados con motivo de cancelacion y estado de pago +
--               resumen calendario de reservas para el admin
--
-- QUE RESUELVE
--   1. El motivo de la cancelacion (migracion 61) y el estado del pago por
--      adelantado (migracion 62) tienen que LLEGAR a la app. Se devuelven en los
--      4 listados existentes. NO se meten en `datos_adicionales` a proposito:
--      `reservas_screen` autodescubre las claves de ese jsonb y las pinta como
--      filas y como COLUMNAS del PDF/Excel, asi que un motivo ahi se filtraria
--      a las exportaciones y a reservas que no se cancelaron.
--   2. El admin necesita un resumen-calendario de TODAS las reservas de su
--      entidad, desde hoy hasta el ultimo mes que tenga reservas, con vista de
--      calendario y vista de lista (estilo to-do).
--
-- FUNCIONES RECREADAS (misma firma: CREATE OR REPLACE, sin sobrecargas)
--   * flow.admin_listar_agendas             (+6 campos)
--   * flow.admin_listar_agendas_por_estado  (+6 campos)
--   * flow.vendedor_listar_agendas          (+6 campos)
--   * flow.cliente_obtener_agendas          (+6 campos)
--   Campos nuevos en cada item:
--     motivo_cancelacion, cancelado_por, cancelado_por_rol, cancelado_at,
--     pago_estado, pago_monto, pago_moneda
--
-- FUNCION NUEVA
--   * flow.admin_calendario_reservas(p_uuid_usuario, p_id_entidad, p_desde, p_hasta)
--     - rango por defecto: de HOY al ULTIMO mes con reservas de la entidad.
--     - devuelve un dia por fecha (incluidos los dias sin reservas, con total 0)
--       y, dentro de cada dia, los items ya listos para pintar.
--
-- LO QUE NO CAMBIA
--   * Los filtros y el orden de los listados: identicos (fecha_hora_reserva desc).
--   * `cliente_obtener_agendas` sigue devolviendo las reservas propias Y las que
--     el usuario hizo para terceros.
--
-- REVERSION
--   Volver a aplicar los cuerpos de `sync_flow_newa_desde_main.sql` (listados) y
--   `drop function if exists flow.admin_calendario_reservas(uuid, integer, date, date);`
--
-- IDEMPOTENTE: create or replace en todo.
-- ============================================================================

-- â•â• 1. admin_listar_agendas â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

create or replace function flow.admin_listar_agendas(
  p_uuid_usuario uuid,
  p_id_entidad integer default null,
  p_id_local integer default null,
  p_id_local_servicio integer default null,
  p_id_estado integer default null,
  p_desde timestamp without time zone default null,
  p_hasta timestamp without time zone default null
)
returns jsonb
language sql
stable
security definer
set search_path = flow, public
as $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',                  a.id,
        'uuid_usuario',        a.uuid_usuario,
        'id_estado',           a.id_estado,
        'fecha_hora_reserva',  a.fecha_hora_reserva,
        'fecha_hora_atencion', a.fecha_hora_atencion,
        'created_at',          a.created_at,
        'updated_at',          a.updated_at,
        'cantidad',            a.cantidad,
        'datos_adicionales',   a.datos_adicionales,
        'reservado_por',       a.reservado_por,
        'precio_total',        a.precio_total,
        'moneda',              a.moneda,
        'id_turno',            a.id_turno,
        'id_viaje',            a.id_viaje,
        'tipo_trayecto',       a.tipo_trayecto,
        -- [63] Cancelacion y pago
        'motivo_cancelacion',  a.motivo_cancelacion,
        'cancelado_por',       a.cancelado_por,
        'cancelado_por_rol',   a.cancelado_por_rol,
        'cancelado_at',        a.cancelado_at,
        'pago_estado',         a.pago_estado,
        'pago_monto',          a.pago_monto,
        'pago_moneda',         a.pago_moneda,
        'turno', case when t.id is null then null else jsonb_build_object(
          'id',     t.id,
          'nombre', t.nombre,
          'recurso', jsonb_build_object('id', r.id, 'nombre', r.nombre)
        ) end,
        'estado', jsonb_build_object(
          'id',          es.id,
          'nombre',      es.nombre,
          'descripcion', es.descripcion
        ),
        'id_local_servicio', ls.id,
        'servicio', jsonb_build_object(
          'id',                 s.id,
          'nombre',             s.nombre,
          'descripcion',        s.descripcion,
          'foto',               s.foto,
          'campos_adicionales', s.campos_adicionales,
          'config_precio',      s.config_precio
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
        ),
        'entidad', jsonb_build_object(
          'id',           en.id,
          'denominacion', en.denominacion,
          'direccion',    en.direccion,
          'telefono',     en.telefono
        ),
        'cliente', case when p.id is null then null else jsonb_build_object(
          'id',           p.id,
          'uuid_usuario', p.uuid_usuario,
          'nombre',       p.nombre,
          'apellidos',    p.apellidos,
          'ci',           p.ci,
          'telefono',     p.telefono,
          'created_at',   p.created_at,
          'updated_at',   p.updated_at
        ) end
      )
      order by a.fecha_hora_reserva desc
    ),
    '[]'::jsonb
  )
  from flow.agenda a
  join flow.local_servicio    ls on ls.id = a.id_local_servicio
  join flow.app_dat_locales   l  on l.id  = ls.id_local
  join flow.app_dat_servicios s  on s.id  = ls.id_servicio
  join flow.entidad           en on en.id = l.id_entidad
  join flow.nom_estado_agenda es on es.id = a.id_estado
  left join flow.perfil       p  on p.uuid_usuario = a.uuid_usuario
  left join flow.turno        t  on t.id = a.id_turno
  left join flow.recurso      r  on r.id = t.id_recurso
  join flow.admin_entidades_de_usuario(auth.uid()) mine on mine.id_entidad = l.id_entidad
  where (p_id_entidad        is null or l.id_entidad         = p_id_entidad)
    and (p_id_local          is null or ls.id_local          = p_id_local)
    and (p_id_local_servicio is null or a.id_local_servicio  = p_id_local_servicio)
    and (p_id_estado         is null or a.id_estado          = p_id_estado)
    and (p_desde             is null or a.fecha_hora_reserva::date >= p_desde::date)
    and (p_hasta             is null or a.fecha_hora_reserva::date <= p_hasta::date);
$function$;

-- â•â• 2. admin_listar_agendas_por_estado â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

create or replace function flow.admin_listar_agendas_por_estado(
  p_uuid_usuario uuid,
  p_id_entidad integer default null,
  p_id_local integer default null,
  p_id_local_servicio integer default null,
  p_id_estado integer default null
)
returns jsonb
language sql
stable
security definer
set search_path = flow, public
as $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',                  a.id,
        'uuid_usuario',        a.uuid_usuario,
        'id_estado',           a.id_estado,
        'fecha_hora_reserva',  a.fecha_hora_reserva,
        'fecha_hora_atencion', a.fecha_hora_atencion,
        'created_at',          a.created_at,
        'updated_at',          a.updated_at,
        'cantidad',            a.cantidad,
        'datos_adicionales',   a.datos_adicionales,
        'reservado_por',       a.reservado_por,
        'precio_total',        a.precio_total,
        'moneda',              a.moneda,
        'id_turno',            a.id_turno,
        'id_viaje',            a.id_viaje,
        'tipo_trayecto',       a.tipo_trayecto,
        'motivo_cancelacion',  a.motivo_cancelacion,
        'cancelado_por',       a.cancelado_por,
        'cancelado_por_rol',   a.cancelado_por_rol,
        'cancelado_at',        a.cancelado_at,
        'pago_estado',         a.pago_estado,
        'pago_monto',          a.pago_monto,
        'pago_moneda',         a.pago_moneda,
        'turno', case when t.id is null then null else jsonb_build_object(
          'id',     t.id,
          'nombre', t.nombre,
          'recurso', jsonb_build_object('id', r.id, 'nombre', r.nombre)
        ) end,
        'estado', jsonb_build_object(
          'id',          es.id,
          'nombre',      es.nombre,
          'descripcion', es.descripcion
        ),
        'id_local_servicio', ls.id,
        'servicio', jsonb_build_object(
          'id',                 s.id,
          'nombre',             s.nombre,
          'descripcion',        s.descripcion,
          'foto',               s.foto,
          'campos_adicionales', s.campos_adicionales,
          'config_precio',      s.config_precio
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
        ),
        'entidad', jsonb_build_object(
          'id',           en.id,
          'denominacion', en.denominacion,
          'direccion',    en.direccion,
          'telefono',     en.telefono
        ),
        'cliente', case when p.id is null then null else jsonb_build_object(
          'id',           p.id,
          'uuid_usuario', p.uuid_usuario,
          'nombre',       p.nombre,
          'apellidos',    p.apellidos,
          'ci',           p.ci,
          'telefono',     p.telefono,
          'created_at',   p.created_at,
          'updated_at',   p.updated_at
        ) end
      )
      order by a.fecha_hora_reserva desc
    ),
    '[]'::jsonb
  )
  from flow.agenda a
  join flow.local_servicio    ls on ls.id = a.id_local_servicio
  join flow.app_dat_locales   l  on l.id  = ls.id_local
  join flow.app_dat_servicios s  on s.id  = ls.id_servicio
  join flow.entidad           en on en.id = l.id_entidad
  join flow.nom_estado_agenda es on es.id = a.id_estado
  left join flow.perfil       p  on p.uuid_usuario = a.uuid_usuario
  left join flow.turno        t  on t.id = a.id_turno
  left join flow.recurso      r  on r.id = t.id_recurso
  join flow.admin_entidades_de_usuario(auth.uid()) mine
    on mine.id_entidad = l.id_entidad
  where (p_id_entidad        is null or l.id_entidad         = p_id_entidad)
    and (p_id_local          is null or ls.id_local          = p_id_local)
    and (p_id_local_servicio is null or a.id_local_servicio  = p_id_local_servicio)
    and (p_id_estado         is null or a.id_estado          = p_id_estado)
    and a.fecha_hora_reserva::date >= (timezone('America/Havana', now()))::date;
$function$;

-- â•â• 3. vendedor_listar_agendas â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

create or replace function flow.vendedor_listar_agendas(
  p_uuid_usuario uuid,
  p_id_entidad integer default null,
  p_id_local integer default null,
  p_id_local_servicio integer default null,
  p_id_estado integer default null,
  p_desde timestamp without time zone default null,
  p_hasta timestamp without time zone default null
)
returns jsonb
language sql
stable
security definer
set search_path = flow, public
as $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',                  a.id,
        'fecha_hora_reserva',  a.fecha_hora_reserva,
        'fecha_hora_atencion', a.fecha_hora_atencion,
        'created_at',          a.created_at,
        'updated_at',          a.updated_at,
        'cantidad',            a.cantidad,
        'datos_adicionales',   a.datos_adicionales,
        'reservado_por',       a.reservado_por,
        'precio_total',        a.precio_total,
        'moneda',              a.moneda,
        'id_estado',           a.id_estado,
        'id_turno',            a.id_turno,
        'id_viaje',            a.id_viaje,
        'tipo_trayecto',       a.tipo_trayecto,
        'motivo_cancelacion',  a.motivo_cancelacion,
        'cancelado_por',       a.cancelado_por,
        'cancelado_por_rol',   a.cancelado_por_rol,
        'cancelado_at',        a.cancelado_at,
        'pago_estado',         a.pago_estado,
        'pago_monto',          a.pago_monto,
        'pago_moneda',         a.pago_moneda,
        'turno', case when t.id is null then null else jsonb_build_object(
          'id',     t.id,
          'nombre', t.nombre,
          'recurso', jsonb_build_object('id', r.id, 'nombre', r.nombre)
        ) end,
        'estado', jsonb_build_object(
          'id',          es.id,
          'nombre',      es.nombre,
          'descripcion', es.descripcion
        ),
        'id_local_servicio', ls.id,
        'servicio', jsonb_build_object(
          'id',                 s.id,
          'nombre',             s.nombre,
          'descripcion',        s.descripcion,
          'foto',               s.foto,
          'campos_adicionales', s.campos_adicionales
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
        ),
        'entidad', jsonb_build_object(
          'id',           en.id,
          'denominacion', en.denominacion,
          'direccion',    en.direccion,
          'telefono',     en.telefono
        ),
        'cliente', case when p.id is null then null else jsonb_build_object(
          'id',           p.id,
          'uuid_usuario', p.uuid_usuario,
          'nombre',       p.nombre,
          'apellidos',    p.apellidos,
          'ci',           p.ci,
          'telefono',     p.telefono,
          'created_at',   p.created_at,
          'updated_at',   p.updated_at
        ) end
      )
      order by a.fecha_hora_reserva desc
    ),
    '[]'::jsonb
  )
  from flow.agenda a
  join flow.local_servicio    ls on ls.id = a.id_local_servicio
  join flow.app_dat_locales   l  on l.id  = ls.id_local
  join flow.app_dat_servicios s  on s.id  = ls.id_servicio
  join flow.entidad           en on en.id = l.id_entidad
  join flow.nom_estado_agenda es on es.id = a.id_estado
  left join flow.perfil       p  on p.uuid_usuario = a.uuid_usuario
  left join flow.turno        t  on t.id = a.id_turno
  left join flow.recurso      r  on r.id = t.id_recurso
  join flow.entidad_vendedor  ev on ev.id_entidad  = l.id_entidad
                                and ev.uuid_usuario = auth.uid()
  where (p_id_entidad        is null or l.id_entidad         = p_id_entidad)
    and (p_id_local          is null or ls.id_local          = p_id_local)
    and (p_id_local_servicio is null or a.id_local_servicio  = p_id_local_servicio)
    and (p_id_estado         is null or a.id_estado          = p_id_estado)
    and (p_desde             is null or a.fecha_hora_reserva >= p_desde)
    and (p_hasta             is null or a.fecha_hora_reserva <= p_hasta);
$function$;

-- â•â• 4. cliente_obtener_agendas â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

create or replace function flow.cliente_obtener_agendas(
  p_uuid_usuario uuid,
  p_id_estado integer default null
)
returns jsonb
language sql
stable
set search_path = flow, public
as $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',                   a.id,
        'fecha_hora_reserva',   a.fecha_hora_reserva,
        'fecha_hora_atencion',  a.fecha_hora_atencion,
        'created_at',           a.created_at,
        'updated_at',           a.updated_at,
        'cantidad',             a.cantidad,
        'datos_adicionales',    a.datos_adicionales,
        'reservado_por',        a.reservado_por,
        'precio_total',         a.precio_total,
        'moneda',               a.moneda,
        'uuid_usuario',         a.uuid_usuario,
        'motivo_cancelacion',   a.motivo_cancelacion,
        'cancelado_por',        a.cancelado_por,
        'cancelado_por_rol',    a.cancelado_por_rol,
        'cancelado_at',         a.cancelado_at,
        'pago_estado',          a.pago_estado,
        'pago_monto',           a.pago_monto,
        'pago_moneda',          a.pago_moneda,
        'estado', jsonb_build_object(
          'id',          e.id,
          'nombre',      e.nombre,
          'descripcion', e.descripcion
        ),
        'id_local_servicio', ls.id,
        'local_servicio', jsonb_build_object(
          'id',                     ls.id,
          'permite_reserva_directa', ls.permite_reserva_directa,
          'cantidad_default',       ls.cantidad_default,
          'cantidad_max_capacidad', ls.cantidad_max_capacidad
        ),
        'servicio', jsonb_build_object(
          'id',                 s.id,
          'nombre',             s.nombre,
          'descripcion',        s.descripcion,
          'foto',               s.foto,
          'campos_adicionales', s.campos_adicionales
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
        ),
        'entidad', jsonb_build_object(
          'id',                             en.id,
          'denominacion',                   en.denominacion,
          'horas_anticipacion_cancelacion', en.horas_anticipacion_cancelacion
        ),
        -- Titular de la reserva (para mostrar "Para: <nombre>" si es un tercero)
        'cliente', case when p.id is null then null else jsonb_build_object(
          'id',           p.id,
          'uuid_usuario', p.uuid_usuario,
          'nombre',       p.nombre,
          'apellidos',    p.apellidos,
          'ci',           p.ci,
          'telefono',     p.telefono
        ) end
      )
      order by a.fecha_hora_reserva desc
    ),
    '[]'::jsonb
  )
  from flow.agenda a
  join flow.local_servicio    ls on ls.id = a.id_local_servicio
  join flow.app_dat_locales   l  on l.id  = ls.id_local
  join flow.app_dat_servicios s  on s.id  = ls.id_servicio
  join flow.nom_estado_agenda e  on e.id  = a.id_estado
  join flow.entidad          en on en.id = l.id_entidad
  left join flow.perfil       p  on p.uuid_usuario = a.uuid_usuario
  -- El usuario ve sus propias reservas Y las que hizo para terceros.
  where (a.uuid_usuario = p_uuid_usuario or a.reservado_por = p_uuid_usuario)
    and (p_id_estado is null or a.id_estado = p_id_estado);
$function$;

-- â•â• 5. admin_calendario_reservas â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- Resumen-calendario: un dia por fecha desde HOY hasta el ULTIMO mes con
-- reservas de la entidad (o hasta `p_hasta` si el admin lo pide). Cada dia trae
-- sus items ya listos para la vista de lista (to-do) y los contadores para la
-- vista de calendario. Los dias sin reservas vienen con total 0: el calendario
-- necesita la serie completa para pintar el mes.

create or replace function flow.admin_calendario_reservas(
  p_uuid_usuario  uuid,
  p_id_entidad    integer,
  p_desde         date default null,
  p_hasta         date default null,
  p_incluir_items boolean default true
)
returns jsonb
language plpgsql
stable
security definer
set search_path = flow, public
as $function$
declare
  v_hoy        date := (timezone('America/Havana', now()))::date;
  v_desde      date;
  v_hasta      date;
  v_ultimo     date;
  v_truncado   boolean := false;
  v_tope       date;
  v_dias       jsonb;
  v_resumen    jsonb;
  v_permitido  boolean;
begin
  select exists (
    select 1 from flow.admin_entidades_de_usuario(p_uuid_usuario) m
    where m.id_entidad = p_id_entidad
  ) or public.fn_is_superadmin_full_access()
    into v_permitido;

  if not v_permitido then
    return jsonb_build_object('ok', false, 'error', 'No tiene permisos sobre esta entidad');
  end if;

  v_desde := coalesce(p_desde, v_hoy);

  -- Ultimo dia con reserva de la entidad (de hoy en adelante).
  select max((a.fecha_hora_reserva at time zone 'America/Havana')::date)
    into v_ultimo
  from flow.agenda a
  join flow.local_servicio  ls on ls.id = a.id_local_servicio
  join flow.app_dat_locales l  on l.id  = ls.id_local
  where l.id_entidad = p_id_entidad
    and (a.fecha_hora_reserva at time zone 'America/Havana')::date >= v_desde;

  -- Por defecto se llega al ultimo dia del ultimo mes con reservas.
  v_hasta := coalesce(
    p_hasta,
    case when v_ultimo is null then v_desde
         else (date_trunc('month', v_ultimo::timestamp) + interval '1 month - 1 day')::date
    end
  );

  if v_hasta < v_desde then
    v_hasta := v_desde;
  end if;

  -- Tope de seguridad: 24 meses. Un rango absurdo no puede tumbar la pantalla.
  v_tope := (v_desde + interval '24 months')::date;
  if v_hasta > v_tope then
    v_hasta := v_tope;
    v_truncado := true;
  end if;

  with base as (
    select
      a.id,
      a.fecha_hora_reserva,
      a.fecha_hora_atencion,
      a.cantidad,
      a.precio_total,
      a.moneda,
      a.id_estado,
      a.motivo_cancelacion,
      a.cancelado_por_rol,
      a.pago_estado,
      a.pago_monto,
      a.pago_moneda,
      (a.fecha_hora_reserva at time zone 'America/Havana')::date as dia,
      es.nombre  as estado_nombre,
      s.nombre   as servicio_nombre,
      l.nombre   as local_nombre,
      ls.id      as id_local_servicio,
      coalesce(nullif(btrim(coalesce(p.nombre, '') || ' ' || coalesce(p.apellidos, '')), ''),
               'Cliente') as cliente_nombre,
      p.telefono as cliente_telefono,
      t.nombre   as turno_nombre
    from flow.agenda a
    join flow.local_servicio    ls on ls.id = a.id_local_servicio
    join flow.app_dat_locales   l  on l.id  = ls.id_local
    join flow.app_dat_servicios s  on s.id  = ls.id_servicio
    join flow.nom_estado_agenda es on es.id = a.id_estado
    left join flow.perfil       p  on p.uuid_usuario = a.uuid_usuario
    left join flow.turno        t  on t.id = a.id_turno
    where l.id_entidad = p_id_entidad
      and (a.fecha_hora_reserva at time zone 'America/Havana')::date
          between v_desde and v_hasta
  ),
  por_dia as (
    select
      dia,
      count(*)::int                                                   as total,
      count(*) filter (where id_estado = 1)::int                      as reservadas,
      count(*) filter (where id_estado = 2)::int                      as canceladas,
      count(*) filter (where id_estado = 3)::int                      as completadas,
      coalesce(sum(cantidad), 0)::int                                 as personas,
      count(*) filter (where pago_estado is not null
                         and pago_estado <> 'verificado')::int        as pagos_pendientes
    from base
    group by dia
  ),
  items as (
    select
      dia,
      jsonb_agg(
        jsonb_build_object(
          'id',                  id,
          'fecha_hora_reserva',  fecha_hora_reserva,
          'fecha_hora_atencion', fecha_hora_atencion,
          'cantidad',            cantidad,
          'precio_total',        precio_total,
          'moneda',              moneda,
          'id_estado',           id_estado,
          'estado',              estado_nombre,
          'servicio',            servicio_nombre,
          'local',               local_nombre,
          'id_local_servicio',   id_local_servicio,
          'turno',               turno_nombre,
          'cliente',             cliente_nombre,
          'cliente_telefono',    cliente_telefono,
          'motivo_cancelacion',  motivo_cancelacion,
          'cancelado_por_rol',   cancelado_por_rol,
          'pago_estado',         pago_estado,
          'pago_monto',          pago_monto,
          'pago_moneda',         pago_moneda
        )
        order by fecha_hora_reserva, id
      ) as lista
    from base
    group by dia
  ),
  serie as (
    select (generate_series(v_desde::timestamp, v_hasta::timestamp, interval '1 day'))::date as dia
  )
  select
    coalesce(jsonb_agg(
      jsonb_build_object(
        'fecha',       s.dia,
        'total',       coalesce(d.total, 0),
        'reservadas',  coalesce(d.reservadas, 0),
        'canceladas',  coalesce(d.canceladas, 0),
        'completadas', coalesce(d.completadas, 0),
        'personas',    coalesce(d.personas, 0),
        'pagos_pendientes', coalesce(d.pagos_pendientes, 0),
        -- `p_incluir_items = false` devuelve solo los contadores: es lo que pinta
        -- los marcadores del calendario, sin arrastrar la lista completa.
        'items',       case when p_incluir_items
                            then coalesce(i.lista, '[]'::jsonb)
                            else '[]'::jsonb end
      )
      order by s.dia
    ), '[]'::jsonb)
  into v_dias
  from serie s
  left join por_dia d on d.dia = s.dia
  left join items   i on i.dia = s.dia;

  -- Resumen del rango: totales por estado y por servicio.
  with base as (
    select a.id_estado, es.nombre as estado_nombre, s.nombre as servicio_nombre,
           a.cantidad, a.precio_total
    from flow.agenda a
    join flow.local_servicio    ls on ls.id = a.id_local_servicio
    join flow.app_dat_locales   l  on l.id  = ls.id_local
    join flow.app_dat_servicios s  on s.id  = ls.id_servicio
    join flow.nom_estado_agenda es on es.id = a.id_estado
    where l.id_entidad = p_id_entidad
      and (a.fecha_hora_reserva at time zone 'America/Havana')::date
          between v_desde and v_hasta
  )
  select jsonb_build_object(
    'total',      (select count(*)::int from base),
    'reservadas', (select count(*)::int from base where id_estado = 1),
    'canceladas', (select count(*)::int from base where id_estado = 2),
    'completadas',(select count(*)::int from base where id_estado = 3),
    'por_servicio', coalesce((
      select jsonb_agg(jsonb_build_object('servicio', servicio_nombre, 'total', t) order by t desc)
      from (
        select servicio_nombre, count(*)::int as t
        from base group by servicio_nombre order by count(*) desc limit 15
      ) x
    ), '[]'::jsonb)
  ) into v_resumen;

  return jsonb_build_object(
    'ok', true,
    'rango', jsonb_build_object(
      'hoy',                    v_hoy,
      'desde',                  v_desde,
      'hasta',                  v_hasta,
      'ultimo_dia_con_reserva', v_ultimo,
      'truncado',               v_truncado
    ),
    'resumen', v_resumen,
    'dias',    v_dias
  );
end;
$function$;

comment on function flow.admin_calendario_reservas(uuid, integer, date, date, boolean) is
  'Resumen-calendario de las reservas de una entidad: de hoy al ultimo mes con reservas (o al rango pedido). Un elemento por dia, con contadores e items.';

-- â•â• 6. GRANTS â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

revoke all on function flow.admin_listar_agendas(uuid, integer, integer, integer, integer, timestamp without time zone, timestamp without time zone) from public, anon;
revoke all on function flow.admin_listar_agendas_por_estado(uuid, integer, integer, integer, integer) from public, anon;
revoke all on function flow.vendedor_listar_agendas(uuid, integer, integer, integer, integer, timestamp without time zone, timestamp without time zone) from public, anon;
revoke all on function flow.cliente_obtener_agendas(uuid, integer) from public, anon;
revoke all on function flow.admin_calendario_reservas(uuid, integer, date, date, boolean) from public, anon;

grant execute on function flow.admin_listar_agendas(uuid, integer, integer, integer, integer, timestamp without time zone, timestamp without time zone) to authenticated;
grant execute on function flow.admin_listar_agendas_por_estado(uuid, integer, integer, integer, integer) to authenticated;
grant execute on function flow.vendedor_listar_agendas(uuid, integer, integer, integer, integer, timestamp without time zone, timestamp without time zone) to authenticated;
grant execute on function flow.cliente_obtener_agendas(uuid, integer) to authenticated;
grant execute on function flow.admin_calendario_reservas(uuid, integer, date, date, boolean) to authenticated;

notify pgrst, 'reload schema';

-- â•â• 7. VERIFICACION (ejecutar a mano despues de aplicar) â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--
-- 7.a Los listados devuelven los campos nuevos (con una sesion de admin real).
-- select jsonb_pretty(flow.admin_listar_agendas(auth.uid(), 1, null, null, null,
--          now()::date - 1, now()::date + 400) -> 0);
--   -- el primer item debe traer motivo_cancelacion, pago_estado, pago_monto,
--   -- pago_moneda, cancelado_por, cancelado_por_rol, cancelado_at
--
-- 7.b El cliente ve el motivo de su reserva cancelada.
-- select jsonb_pretty(flow.cliente_obtener_agendas(auth.uid()) -> 0);
--
-- 7.c El calendario arranca hoy y llega al ultimo mes con reservas.
-- select flow.admin_calendario_reservas(auth.uid(), 1) -> 'rango';
--   -- desde = hoy; hasta = ultimo dia del mes de la ultima reserva;
--   -- ultimo_dia_con_reserva = null si no hay ninguna reserva futura
-- select jsonb_array_length(flow.admin_calendario_reservas(auth.uid(), 1) -> 'dias');
-- select flow.admin_calendario_reservas(auth.uid(), 1) -> 'resumen';
-- -- Solo contadores (lo que pinta el calendario): los items vienen vacios.
-- select flow.admin_calendario_reservas(auth.uid(), 1, null, null, false) -> 'dias' -> 0 -> 'items';
--
-- 7.d Un rango absurdo se recorta a 24 meses y lo dice.
-- select flow.admin_calendario_reservas(auth.uid(), 1, now()::date, now()::date + 3000) -> 'rango';
--
-- 7.e Sin permisos devuelve error, no datos.
-- select flow.admin_calendario_reservas(gen_random_uuid(), 1);   -- {ok:false, error:...}

-- #################### FIN: 63_listados_motivo_pago_y_calendario.sql ####################

-- #################### INICIO: 64_tasas_refresco_pg_net.sql ####################

-- ============================================================================
-- MIGRACION 64: refresco de la tasa de cambio SIN depender de una Edge Function
--
-- POR QUE EXISTE
--   La Edge Function `flow-tasas` (docs/flow_schema/edge_functions/flow-tasas)
--   es el camino limpio: se despliega una vez y devuelve la tasa lista. Pero
--   desplegarla exige un token con permiso `edge_functions_write`, que no
--   siempre hay. Con `pg_net` (ya instalado en el proyecto) el refresco se puede
--   hacer ENTERAMENTE desde Postgres: la base pide la URL, y una segunda llamada
--   ingiere la respuesta y la cachea. Asi la funcion automatica de precios
--   funciona aunque no haya ninguna Edge Function desplegada.
--
-- COMO SE USA (la app hace esto, en este orden)
--   1. `flow.tasas_actuales()`                    -- lectura barata de la cache
--   2. si `vigente = false`:
--        `flow.tasas_refrescar()`                 -- pide la URL (async)
--        -> {estado:'vigente'}     : ya habia tasa de hoy, nada que hacer
--        -> {estado:'solicitado', request_id:N}
--   3. en bucle (cada ~250 ms, max ~1.5 s):
--        `flow.tasas_ingest(N)`                   -- mira si ya llego
--        -> {estado:'pendiente'} | {estado:'ingerido', ...tasas}
--   4. `flow.tasas_actuales()` otra vez para leer el resultado.
--
--   `pg_net` es ASINCRONO: por eso son dos llamadas. No se puede esperar la
--   respuesta dentro de la misma transaccion.
--
-- TABLA NUEVA
--   * flow.tasa_cambio_sondeo â€” un registro por peticion HTTP lanzada. Sirve de
--     pestillo anti-spam (no se lanza otra igual en 2 minutos) y de bandeja de
--     "pendiente de ingerir".
--
-- FUNCIONES NUEVAS
--   * flow._tasas_conversiones(p_tasas jsonb)  -- matriz cruzada por CUP
--   * flow.tasas_refrescar(p_forzar boolean)   -- pide la URL si la cache no es de hoy
--   * flow.tasas_ingest(p_request_id bigint)   -- lee la respuesta y cachea
--
-- LO QUE NO CAMBIA
--   * `flow.tasa_cambio` es la MISMA tabla de la migracion 60: la Edge Function
--     y esta via escriben exactamente la misma forma. Conviven sin conflicto.
--   * `flow.tasas_actuales()` y `flow.tasa_factor()` no se tocan.
--
-- REVERSION
--   drop function if exists flow.tasas_ingest(bigint);
--   drop function if exists flow.tasas_refrescar(boolean);
--   drop function if exists flow._tasas_conversiones(jsonb);
--   drop table if exists flow.tasa_cambio_sondeo;
--
-- IDEMPOTENTE: if not exists / create or replace / drop policy if exists.
-- ============================================================================

-- â•â• 1. BANDEJA DE SONDEO â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

create table if not exists flow.tasa_cambio_sondeo (
  request_id bigint primary key,
  creado_at  timestamptz not null default now(),
  ingerido   boolean     not null default false,
  ingerido_at timestamptz,
  error      text
);

comment on table flow.tasa_cambio_sondeo is
  'Una fila por peticion HTTP lanzada con pg_net para leer la tasa. Evita lanzar peticiones repetidas y sirve de bandeja de respuestas pendientes de ingerir.';

create index if not exists idx_tasa_cambio_sondeo_pendientes
  on flow.tasa_cambio_sondeo (creado_at desc)
  where not ingerido;

-- â•â• 2. MATRIZ DE CONVERSIONES (espejo SQL de la Edge Function) â•â•â•â•â•â•â•â•â•â•â•â•

create or replace function flow._tasas_conversiones(p_tasas jsonb)
returns jsonb
language plpgsql
immutable
set search_path = flow, public
as $function$
declare
  v_monedas text[] := array['USD', 'EUR', 'CUP', 'MLC'];
  v_salida  jsonb := '{}'::jsonb;
  v_fila    jsonb;
  v_o       text;
  v_d       text;
  v_val     numeric;
  v_a       numeric;
  v_b       numeric;
begin
  if p_tasas is null or jsonb_typeof(p_tasas) <> 'object' then
    return '{}'::jsonb;
  end if;

  foreach v_o in array v_monedas loop
    -- OJO: `jsonb_set` NO crea objetos intermedios, solo la ultima clave. Por eso
    -- se arma la fila de la moneda origen aparte y se cuelga entera de la salida
    -- (`jsonb_set('{}', '{USD,EUR}', ...)` no hacia NADA y devolvia `{}`).
    v_fila := '{}'::jsonb;

    foreach v_d in array v_monedas loop
      if v_o = v_d then
        v_val := 1;
      elsif v_o = 'CUP' then
        -- El proveedor no publica una fila CUP: se invierte X -> CUP.
        v_val := nullif(p_tasas -> v_d ->> 'CUP', '')::numeric;
        v_val := case when v_val is not null and v_val > 0
                      then 1 / v_val else null end;
      elsif v_d = 'CUP' then
        v_val := nullif(p_tasas -> v_o ->> 'CUP', '')::numeric;
      else
        v_val := nullif(p_tasas -> v_o ->> v_d, '')::numeric;
        if v_val is null then
          -- Cruce por CUP: (origen -> CUP) / (destino -> CUP).
          v_a := nullif(p_tasas -> v_o ->> 'CUP', '')::numeric;
          v_b := nullif(p_tasas -> v_d ->> 'CUP', '')::numeric;
          if v_a is not null and v_b is not null and v_b > 0 then
            v_val := v_a / v_b;
          end if;
        end if;
      end if;

      if v_val is not null and v_val > 0 then
        v_fila := jsonb_set(v_fila, array[v_d], to_jsonb(round(v_val, 6)), true);
      end if;
    end loop;

    v_salida := jsonb_set(v_salida, array[v_o], v_fila, true);
  end loop;

  return v_salida;
end;
$function$;

comment on function flow._tasas_conversiones(jsonb) is
  'Matriz de conversion entre USD/EUR/CUP/MLC a partir del JSON crudo del proveedor, cruzando por CUP cuando no hay tasa directa.';

-- â•â• 3. PEDIR LA TASA â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

create or replace function flow.tasas_refrescar(p_forzar boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = flow, public
as $function$
declare
  v_hoy     date := (timezone('America/Havana', now()))::date;
  v_row     flow.tasa_cambio%rowtype;
  v_pend    flow.tasa_cambio_sondeo%rowtype;
  v_req     bigint;
begin
  -- Fast path: ya hay tasa de hoy y no se fuerza.
  if not coalesce(p_forzar, false) then
    select * into v_row
    from flow.tasa_cambio
    order by fecha desc, id desc
    limit 1;

    if v_row.id is not null and v_row.fecha = v_hoy then
      return jsonb_build_object(
        'ok', true, 'estado', 'vigente',
        'fecha', v_row.fecha, 'hora', v_row.hora, 'actualizado', v_row.actualizado,
        'tasas', v_row.tasas, 'conversiones', v_row.conversiones
      );
    end if;
  end if;

  -- Pestillo: si hay una peticion de hace menos de 2 minutos sin ingerir, se
  -- devuelve ESA en vez de lanzar otra. Evita que pulsar "reintentar" en la app
  -- dispare una peticion HTTP por toque.
  select * into v_pend
  from flow.tasa_cambio_sondeo
  where not ingerido
    and creado_at > now() - interval '2 minutes'
  order by creado_at desc
  limit 1;

  if v_pend.request_id is not null then
    return jsonb_build_object(
      'ok', true, 'estado', 'solicitado', 'request_id', v_pend.request_id
    );
  end if;

  v_req := net.http_get(
    'https://widgets.directoriocubano.info/api/tasas',
    headers := jsonb_build_object(
      'Accept', 'application/json',
      'User-Agent', 'Mozilla/5.0 (compatible; GoReserva-flow-tasas/1.0)'
    ),
    timeout_milliseconds := 12000
  );

  insert into flow.tasa_cambio_sondeo (request_id)
  values (v_req)
  on conflict (request_id) do nothing;

  return jsonb_build_object(
    'ok', true, 'estado', 'solicitado', 'request_id', v_req
  );
exception
  when others then
    return jsonb_build_object('ok', false, 'estado', 'error', 'error', sqlerrm);
end;
$function$;

comment on function flow.tasas_refrescar(boolean) is
  'Pide la tasa del dia al proveedor via pg_net (asincrono). Devuelve la tasa vigente si ya la tiene, o el request_id a ingerir.';

-- â•â• 4. INGERIR LA RESPUESTA â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

create or replace function flow.tasas_ingest(p_request_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = flow, public
as $function$
declare
  v_resp    record;
  v_json    jsonb;
  v_tasas   jsonb;
  v_conv    jsonb;
  v_hoy     date := (timezone('America/Havana', now()))::date;
  v_act     text;
  v_fecha   date;
  v_hora    text;
  v_sondeo  flow.tasa_cambio_sondeo%rowtype;
begin
  select * into v_sondeo
  from flow.tasa_cambio_sondeo
  where request_id = p_request_id;

  if v_sondeo.request_id is not null and v_sondeo.ingerido then
    -- Ya se proceso: se devuelve la cache (idempotente).
    return flow.tasas_actuales();
  end if;

  select * into v_resp from net._http_response where id = p_request_id;

  if v_resp.id is null or v_resp.status_code is null then
    return jsonb_build_object('ok', true, 'estado', 'pendiente',
                              'request_id', p_request_id);
  end if;

  if v_resp.status_code <> 200 then
    update flow.tasa_cambio_sondeo
       set ingerido = true, ingerido_at = now(),
           error = 'HTTP ' || v_resp.status_code
     where request_id = p_request_id;
    return jsonb_build_object('ok', false, 'estado', 'error',
                              'error', 'HTTP ' || v_resp.status_code);
  end if;

  begin
    v_json := coalesce(v_resp.content, '{}')::jsonb;
  exception
    when others then
      update flow.tasa_cambio_sondeo
         set ingerido = true, ingerido_at = now(), error = 'respuesta no JSON'
       where request_id = p_request_id;
      return jsonb_build_object('ok', false, 'estado', 'error',
                                'error', 'El proveedor no devolvio JSON');
  end;

  if coalesce(v_json -> 'ok', 'false'::jsonb) <> 'true'::jsonb
     or jsonb_typeof(v_json -> 'tasas') <> 'object' then
    update flow.tasa_cambio_sondeo
       set ingerido = true, ingerido_at = now(), error = 'respuesta sin tasas'
     where request_id = p_request_id;
    return jsonb_build_object('ok', false, 'estado', 'error',
                              'error', 'El proveedor devolvio una respuesta sin tasas');
  end if;

  v_tasas := v_json -> 'tasas';
  v_conv  := flow._tasas_conversiones(v_tasas);
  v_act   := nullif(btrim(coalesce(v_json ->> 'actualizado', '')), '');
  v_hora  := nullif(btrim(coalesce(v_json ->> 'hora', '')), '');

  -- La cache se indexa por el dia del proveedor. Se valida el formato; si no
  -- es una fecha, se usa hoy (hora de La Habana).
  begin
    v_fecha := (left(v_act, 10))::date;
  exception
    when others then
      v_fecha := v_hoy;
  end;
  if v_fecha is null then
    v_fecha := v_hoy;
  end if;

  insert into flow.tasa_cambio (fecha, fuente, hora, actualizado, tasas, conversiones, updated_at)
  values (
    v_fecha,
    'directoriocubano',
    v_hora,
    case when v_act is null then null else v_act::timestamptz end,
    v_tasas,
    v_conv,
    now()
  )
  on conflict (fecha, fuente) do update
    set hora         = excluded.hora,
        actualizado  = excluded.actualizado,
        tasas        = excluded.tasas,
        conversiones = excluded.conversiones,
        updated_at   = now();

  update flow.tasa_cambio_sondeo
     set ingerido = true, ingerido_at = now(), error = null
   where request_id = p_request_id;

  -- Limpieza: las respuestas de pg_net no se borran solas.
  delete from net._http_response where created < now() - interval '2 days';
  delete from flow.tasa_cambio_sondeo where ingerido and creado_at < now() - interval '7 days';

  return jsonb_build_object(
    'ok', true, 'estado', 'ingerido',
    'fecha', v_fecha, 'hora', v_hora, 'actualizado', v_act,
    'tasas', v_tasas, 'conversiones', v_conv
  );
exception
  when others then
    return jsonb_build_object('ok', false, 'estado', 'error', 'error', sqlerrm);
end;
$function$;

comment on function flow.tasas_ingest(bigint) is
  'Lee la respuesta de pg_net de un request_id, calcula las conversiones y cachea la tasa. Idempotente: llamarla dos veces no duplica nada.';

-- â•â• 5. RLS Y GRANTS â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

alter table flow.tasa_cambio_sondeo enable row level security;

revoke all on flow.tasa_cambio_sondeo from anon;
grant select on flow.tasa_cambio_sondeo to authenticated;
grant all    on flow.tasa_cambio_sondeo to service_role;

revoke all on function flow._tasas_conversiones(jsonb) from public, anon;
revoke all on function flow.tasas_refrescar(boolean) from public, anon;
revoke all on function flow.tasas_ingest(bigint) from public, anon;

grant execute on function flow.tasas_refrescar(boolean) to authenticated;
grant execute on function flow.tasas_ingest(bigint) to authenticated;

notify pgrst, 'reload schema';

-- â•â• 6. VERIFICACION (ejecutar a mano despues de aplicar) â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--
-- 6.a La conversion cruzada da lo mismo que la Edge Function.
-- select flow._tasas_conversiones(
--   '{"USD":{"CUP":840,"MLC":1.2,"USD":null},"EUR":{"CUP":925,"MLC":1.33,"USD":1.1},"MLC":{"CUP":697.62,"MLC":null,"USD":0.83}}'::jsonb
-- ) -> 'MLC' ->> 'EUR';   -- 0.754184 (697.62 / 925)
--
-- 6.b Pedir + ingerir (tarda ~1 s: la respuesta es asincrona).
-- select flow.tasas_refrescar();
--   -- {ok:true, estado:'solicitado', request_id:N}
-- select pg_sleep(2);
-- select flow.tasas_ingest(N);         -- {ok:true, estado:'ingerido', ...}
-- select flow.tasas_actuales();        -- {ok:true, vigente:true, ...}
--
-- 6.c El pestillo: dos peticiones seguidas devuelven el MISMO request_id.
-- select flow.tasas_refrescar(true);   -- mismo request_id
--
-- 6.d Una vez cacheada la tasa de hoy, sin forzar no se pide nada.
-- select flow.tasas_refrescar();       -- {ok:true, estado:'vigente'}
-- #################### FIN: 64_tasas_refresco_pg_net.sql ####################

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

