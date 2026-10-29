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
--   * `flow.tasa_cambio`  — cache (una fila por dia y fuente).
--       tasas        jsonb: el JSON crudo del proveedor
--                            {"USD":{"CUP":840,"MLC":1.2,"USD":null}, ...}
--       conversiones jsonb: matriz normalizada y cruzada de las monedas de la
--                            app {"USD":{"CUP":840,"EUR":0.908,"MLC":1.204}, ...}
--                            Se calcula en la Edge Function: usa la tasa directa
--                            si existe y, si no, cruza por CUP
--                            (MLC->EUR = MLC->CUP / EUR->CUP).
--   * `flow.precio_config` — por entidad: si el calculo automatico esta activo,
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

-- ══ 1. TABLAS ══════════════════════════════════════════════════════════════

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

-- ══ 2. HELPERS ═════════════════════════════════════════════════════════════

-- Permiso de lectura/administracion de una entidad: dueño, `entidad_admin` o
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
  'true si el llamador es dueño, entidad_admin o superadmin de la entidad.';

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

-- ══ 3. RPC DE CONFIGURACION DE PRECIOS ═════════════════════════════════════

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

-- ══ 4. RLS ═════════════════════════════════════════════════════════════════
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

-- ══ 5. GRANTS ══════════════════════════════════════════════════════════════

revoke all on flow.tasa_cambio, flow.precio_config from anon;

grant select on flow.tasa_cambio, flow.precio_config to authenticated;
grant all    on flow.tasa_cambio, flow.precio_config to service_role;

-- [FIX] El permiso sobre las TABLAS no basta: sin USAGE en el schema, cualquier
-- lectura de `flow.*` con el rol service_role falla con
-- «permission denied for schema flow». Lo necesita la Edge Function `flow-tasas`,
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

-- ══ 6. VERIFICACION (ejecutar a mano despues de aplicar) ══════════════════
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
