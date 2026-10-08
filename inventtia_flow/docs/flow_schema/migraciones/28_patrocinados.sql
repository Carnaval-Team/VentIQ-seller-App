-- ============================================================================
-- MIGRACION: campanas patrocinadas del Home (las cura el SUPERADMIN)
--
-- QUE ES ESTO
--   El "espacio patrocinado" del Home del cliente. A diferencia de las
--   promociones (paso 5), que las crea el **admin de la entidad** para sus
--   servicios, las campanas patrocinadas son contenido de PLATAFORMA: las
--   configura el superadmin desde `ventiq_superadmin`, y sirven para destacar
--   locales/servicios de cualquier entidad en el Home.
--
-- QUIEN ESCRIBE Y QUIEN LEE
--   Escritura  -> solo superadmin con acceso total (`public.fn_is_superadmin_full_access()`).
--   Lectura    -> cualquier autenticado (el Home del cliente necesita pintarlas).
--   La app del cliente NUNCA escribe campanas: solo las consume.
--
-- POR QUE SE REUTILIZA `fn_is_superadmin_full_access`
--   Ya existe en `public` y es la que usan las politicas de
--   `app_dat_superadmin`. Inventar otra comprobacion habria creado dos
--   definiciones de "es superadmin", que es justo el error que se corrigio en
--   la migracion 24 (autorizar por parametro en vez de por `auth.uid()`).
--   El helper no recibe argumentos: resuelve el usuario por `auth.uid()`.
--
-- DIFERENCIA CON `flow.promocion`
--   * `promocion` = descuento de precio. Afecta a lo que se COBRA.
--   * `campana`   = destacado/publicidad. NO afecta al precio jamas.
--   Se mantienen separadas a proposito: si el patrocinio pudiera alterar el
--   importe, se volveria a mezclar "lo que se muestra" con "lo que se cobra".
--
-- VIGENCIA
--   activo and (desde is null or now >= desde) and (hasta is null or now < hasta)
--   `hasta` es EXCLUSIVO, igual que en `promocion`. `prioridad` ordena la
--   rotacion: mayor primero.
--
-- QUE CREA
--   - flow.campana (+ RLS + indices)
--   - flow.campanas_activas()            (lectura para el Home)
--   - flow.admin_listar_campanas()       (listado del superadmin)
--   - flow.admin_guardar_campana()       (alta/edicion)
--   - flow.admin_eliminar_campana()
--   - flow.admin_alternar_campana()
--
-- REVERSION
--   drop function if exists flow.admin_alternar_campana(uuid, integer, boolean);
--   drop function if exists flow.admin_eliminar_campana(uuid, integer);
--   drop function if exists flow.admin_guardar_campana(uuid, integer, text, integer, text, text, timestamptz, timestamptz, integer, boolean, text, text);
--   drop function if exists flow.admin_listar_campanas(uuid);
--   drop function if exists flow.campanas_activas();
--   drop table if exists flow.campana;
--   (Es una creacion nueva: no toca nada existente.)
--
-- DEPENDE DE: nada. Se puede aplicar sola.
-- ============================================================================

create table if not exists flow.campana (
  id                integer generated always as identity primary key,
  titulo            varchar(120) not null,
  subtitulo         varchar(160),
  descripcion       text,

  -- A quien destaca. Una campana puede apuntar a un local-servicio concreto o
  -- a toda una entidad (todos sus servicios).
  id_local_servicio integer references flow.local_servicio(id) on delete cascade,
  id_entidad        integer references flow.entidad(id) on delete cascade,

  -- Aspecto: color e imagen son opcionales; si no hay imagen, el Home pinta un
  -- degradado con estos colores.
  color_inicio      varchar(9),
  color_fin         varchar(9),
  icono             varchar(48),
  image_url         text,

  desde             timestamptz,
  hasta             timestamptz,

  -- Mayor = se muestra antes en la rotacion.
  prioridad         integer not null default 0,

  activo            boolean not null default true,

  -- Auditoria: quien la creo. Se guarda el uuid del superadmin.
  created_by        uuid,
  created_at        timestamp not null default current_timestamp,
  updated_at        timestamp not null default current_timestamp,

  constraint campana_alcance_check
    check (id_local_servicio is not null or id_entidad is not null),
  constraint campana_vigencia_check
    check (desde is null or hasta is null or desde < hasta)
);

comment on table flow.campana is
  'Campanas patrocinadas del Home, curadas por el superadmin. NO afectan al precio: solo al destacado.';

create index if not exists idx_campana_vigente
  on flow.campana (activo, prioridad desc);

create index if not exists idx_campana_local
  on flow.campana (id_local_servicio)
  where id_local_servicio is not null;

create index if not exists idx_campana_entidad
  on flow.campana (id_entidad)
  where id_entidad is not null;

-- ============================================================================
-- RLS
--   SELECT -> autenticados (el Home del cliente las lee).
--   INSERT/UPDATE/DELETE -> solo superadmin con acceso total, via
--     `public.fn_is_superadmin_full_access()`.
--
--   Las politicas de escritura son IMPRESCINDIBLES, no decorativas: los RPC de
--   abajo son `security invoker`, asi que sin ellas el superadmin no podria
--   guardar (RLS le bloquearia el INSERT). Con ellas, la autorizacion vive en un
--   solo sitio (RLS) y el RPC solo valida los datos.
-- ============================================================================
alter table flow.campana enable row level security;

drop policy if exists "campana_select_autenticados" on flow.campana;
drop policy if exists "campana_insert_superadmin" on flow.campana;
drop policy if exists "campana_update_superadmin" on flow.campana;
drop policy if exists "campana_delete_superadmin" on flow.campana;

create policy "campana_select_autenticados"
on flow.campana
for select
to authenticated
using (true);

create policy "campana_insert_superadmin"
on flow.campana
for insert
to authenticated
with check (public.fn_is_superadmin_full_access());

create policy "campana_update_superadmin"
on flow.campana
for update
to authenticated
using (public.fn_is_superadmin_full_access())
with check (public.fn_is_superadmin_full_access());

create policy "campana_delete_superadmin"
on flow.campana
for delete
to authenticated
using (public.fn_is_superadmin_full_access());

revoke all on flow.campana from anon;
grant select on flow.campana to authenticated;
grant all on flow.campana to service_role;

-- ============================================================================
-- LECTURA PARA EL HOME
--
--   Devuelve las campanas vigentes resueltas: con el nombre del local y del
--   servicio ya incluidos, para que el Home no tenga que cruzar nada.
-- ============================================================================
create or replace function flow.campanas_activas()
returns jsonb
language sql
stable
security invoker
set search_path = flow, public
as $$
  select coalesce(
    jsonb_agg(to_jsonb(t) order by t.prioridad desc, t.id asc),
    '[]'::jsonb
  )
  from (
    select
      c.id,
      c.titulo,
      c.subtitulo,
      c.descripcion,
      c.id_local_servicio,
      c.id_entidad,
      c.color_inicio,
      c.color_fin,
      c.icono,
      c.image_url,
      c.prioridad,
      c.hasta,
      -- Nombres resueltos para pintar el badge sin otra consulta.
      l.nombre      as local,
      ls.id         as id_local_servicio_real,
      s.nombre      as servicio,
      en.denominacion as entidad
    from flow.campana c
    left join flow.local_servicio   ls on ls.id = c.id_local_servicio
    left join flow.app_dat_locales  l  on l.id  = ls.id_local
    left join flow.app_dat_servicios s on s.id  = ls.id_servicio
    left join flow.entidad          en on en.id = coalesce(l.id_entidad, c.id_entidad)
    where c.activo
      and (c.desde is null or (now() at time zone 'America/Havana') >= c.desde)
      and (c.hasta is null or (now() at time zone 'America/Havana') <  c.hasta)
  ) t;
$$;

-- ============================================================================
-- CRUD DEL SUPERADMIN
--
--   Todas comprueban `public.fn_is_superadmin_full_access()`, que resuelve el
--   usuario por `auth.uid()` (no por el parametro) y exige `nivel_acceso = 1`.
--
--   Son **SECURITY INVOKER**, no definer: la autorizacion ya la hace el helper,
--   que es definer por dentro, y la tabla tiene RLS de lectura publica. Hacerlas
--   definer ampliaria la superficie sin aportar nada.
--
--   El uuid que llega por parametro NO decide: se compara con el de la sesion.
-- ============================================================================
create or replace function flow.admin_listar_campanas(
  p_uuid_usuario uuid
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = flow, public
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error', 'Solo el superadmin puede gestionar campanas');
  end if;

  select coalesce(jsonb_agg(to_jsonb(t) order by t.prioridad desc, t.id desc), '[]'::jsonb)
    into v_result
  from (
    select
      c.*,
      l.nombre as local,
      s.nombre as servicio,
      en.denominacion as entidad
    from flow.campana c
    left join flow.local_servicio   ls on ls.id = c.id_local_servicio
    left join flow.app_dat_locales  l  on l.id  = ls.id_local
    left join flow.app_dat_servicios s on s.id  = ls.id_servicio
    left join flow.entidad          en on en.id = coalesce(l.id_entidad, c.id_entidad)
  ) t;

  return jsonb_build_object('ok', true, 'data', v_result);
end;
$$;

create or replace function flow.admin_guardar_campana(
  p_uuid_usuario uuid,
  p_titulo text,
  p_id_local_servicio integer default null,
  p_id_entidad integer default null,
  p_subtitulo text default null,
  p_descripcion text default null,
  p_color_inicio text default null,
  p_color_fin text default null,
  p_icono text default null,
  p_image_url text default null,
  p_desde timestamptz default null,
  p_hasta timestamptz default null,
  p_prioridad integer default 0,
  p_activo boolean default true,
  p_id integer default null
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = flow, public
as $$
declare
  v_id integer;
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error', 'Solo el superadmin puede gestionar campanas');
  end if;

  if btrim(coalesce(p_titulo, '')) = '' then
    return jsonb_build_object('ok', false, 'error', 'El titulo es obligatorio');
  end if;
  if p_id_local_servicio is null and p_id_entidad is null then
    return jsonb_build_object('ok', false, 'error', 'Elige un servicio o una entidad');
  end if;
  if p_id_local_servicio is not null and p_id_entidad is not null then
    return jsonb_build_object('ok', false, 'error', 'Elige servicio O entidad, no ambos');
  end if;
  if p_desde is not null and p_hasta is not null and p_desde >= p_hasta then
    return jsonb_build_object('ok', false, 'error', 'La fecha de fin debe ser posterior al inicio');
  end if;

  if p_id_local_servicio is not null
     and not exists (select 1 from flow.local_servicio where id = p_id_local_servicio) then
    return jsonb_build_object('ok', false, 'error', 'El servicio no existe');
  end if;
  if p_id_entidad is not null
     and not exists (select 1 from flow.entidad where id = p_id_entidad) then
    return jsonb_build_object('ok', false, 'error', 'La entidad no existe');
  end if;

  if p_id is null then
    insert into flow.campana (
      titulo, subtitulo, descripcion,
      id_local_servicio, id_entidad,
      color_inicio, color_fin, icono, image_url,
      desde, hasta, prioridad, activo, created_by
    )
    values (
      btrim(p_titulo),
      nullif(btrim(coalesce(p_subtitulo, '')), ''),
      nullif(btrim(coalesce(p_descripcion, '')), ''),
      p_id_local_servicio, p_id_entidad,
      nullif(btrim(coalesce(p_color_inicio, '')), ''),
      nullif(btrim(coalesce(p_color_fin, '')), ''),
      nullif(btrim(coalesce(p_icono, '')), ''),
      nullif(btrim(coalesce(p_image_url, '')), ''),
      p_desde, p_hasta, coalesce(p_prioridad, 0), coalesce(p_activo, true),
      auth.uid()
    )
    returning id into v_id;
  else
    update flow.campana
       set titulo = btrim(p_titulo),
           subtitulo = nullif(btrim(coalesce(p_subtitulo, '')), ''),
           descripcion = nullif(btrim(coalesce(p_descripcion, '')), ''),
           id_local_servicio = p_id_local_servicio,
           id_entidad = p_id_entidad,
           color_inicio = nullif(btrim(coalesce(p_color_inicio, '')), ''),
           color_fin = nullif(btrim(coalesce(p_color_fin, '')), ''),
           icono = nullif(btrim(coalesce(p_icono, '')), ''),
           image_url = nullif(btrim(coalesce(p_image_url, '')), ''),
           desde = p_desde,
           hasta = p_hasta,
           prioridad = coalesce(p_prioridad, 0),
           activo = coalesce(p_activo, true),
           updated_at = current_timestamp
     where id = p_id
     returning id into v_id;

    if v_id is null then
      return jsonb_build_object('ok', false, 'error', 'Campana inexistente');
    end if;
  end if;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));
end;
$$;

create or replace function flow.admin_eliminar_campana(
  p_uuid_usuario uuid,
  p_id integer
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = flow, public
as $$
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error', 'Solo el superadmin puede gestionar campanas');
  end if;

  delete from flow.campana where id = p_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Campana inexistente');
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

create or replace function flow.admin_alternar_campana(
  p_uuid_usuario uuid,
  p_id integer,
  p_activo boolean
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = flow, public
as $$
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error', 'Solo el superadmin puede gestionar campanas');
  end if;

  update flow.campana
     set activo = coalesce(p_activo, true),
         updated_at = current_timestamp
   where id = p_id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Campana inexistente');
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

-- ============================================================================
-- PERMISOS
--   `anon` fuera de todo. `authenticated` puede leer las activas (Home) y
--   ejecutar los admin_* (que ya comprueban superadmin por dentro).
-- ============================================================================
revoke all on function flow.campanas_activas() from public, anon;
revoke all on function flow.admin_listar_campanas(uuid) from public, anon;
revoke all on function flow.admin_guardar_campana(uuid, text, integer, integer, text, text, text, text, text, text, timestamptz, timestamptz, integer, boolean, integer) from public, anon;
revoke all on function flow.admin_eliminar_campana(uuid, integer) from public, anon;
revoke all on function flow.admin_alternar_campana(uuid, integer, boolean) from public, anon;

grant execute on function flow.campanas_activas() to authenticated, service_role;
grant execute on function flow.admin_listar_campanas(uuid) to authenticated, service_role;
grant execute on function flow.admin_guardar_campana(uuid, text, integer, integer, text, text, text, text, text, text, timestamptz, timestamptz, integer, boolean, integer) to authenticated, service_role;
grant execute on function flow.admin_eliminar_campana(uuid, integer) to authenticated, service_role;
grant execute on function flow.admin_alternar_campana(uuid, integer, boolean) to authenticated, service_role;

notify pgrst, 'reload schema';

-- ============================================================================
-- VERIFICACION
-- ============================================================================
select 'tabla' as objeto, c.relname as nombre, c.relrowsecurity as rls,
       coalesce(array_to_string(c.relacl::text[], ' | '), 'default') as acl
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'flow' and c.relname = 'campana'
union all
select 'policy', policyname, true, cmd::text || ' → ' || roles::text
from pg_policies where schemaname = 'flow' and tablename = 'campana'
union all
select 'funcion', p.proname, p.prosecdef,
       coalesce(array_to_string(p.proacl::text[], ' | '), 'default(PUBLIC)')
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'flow' and p.proname in (
  'campanas_activas', 'admin_listar_campanas', 'admin_guardar_campana',
  'admin_eliminar_campana', 'admin_alternar_campana'
)
order by objeto, nombre;

-- El helper del superadmin debe existir: si falta, los RPC fallaran en runtime.
select public.fn_is_superadmin_full_access() as helper_disponible;