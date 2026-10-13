-- ════════════════════════════════════════════════════════════════════════════
-- 30 — Colecciones temáticas (Paso 7)
-- ════════════════════════════════════════════════════════════════════════════
--
-- QUÉ HACE
--   Crea `flow.coleccion` + `flow.coleccion_servicio` (lista curada y ordenada
--   de servicios) y las RPC que las usan:
--     · colecciones_activas()                 -> cliente (Home), array JSON
--     · admin_listar_colecciones(uuid)        -> panel superadmin
--     · admin_guardar_coleccion(...)          -> alta/edición + set de servicios
--     · admin_alternar_coleccion(uuid,id,act) -> encender/apagar
--     · admin_eliminar_coleccion(uuid,id)     -> baja
--
-- POR QUÉ ES CONTENIDO DE PLATAFORMA
--   Igual que `flow.campana` (patrocinados), las cura el **superadmin** desde
--   `ventiq_superadmin`, no el admin de cada entidad: una colección cruza
--   entidades ("Pack Novia" puede mezclar servicios de 3 negocios). Por eso no
--   hay `id_entidad` ni aislamiento por entidad aquí.
--
-- DEPENDE DE
--   · `flow.local_servicio` (esquema base)
--   · `public.fn_is_superadmin_full_access()` (migración 28_patrocinados.sql)
--   La comprobación previa aborta con un mensaje claro si falta alguna.
--
-- IDEMPOTENTE
--   `create table if not exists`, `drop policy if exists` antes de cada
--   `create policy`, y `create or replace function`. Re-ejecutarla deja el
--   mismo estado.
--
-- REVERSIBLE (SQL de vuelta atrás)
--   drop function if exists flow.admin_eliminar_coleccion(uuid, integer);
--   drop function if exists flow.admin_alternar_coleccion(uuid, integer, boolean);
--   drop function if exists flow.admin_guardar_coleccion(uuid, text, text, text, text, text, integer, boolean, timestamptz, timestamptz, jsonb, integer);
--   drop function if exists flow.admin_listar_colecciones(uuid);
--   drop function if exists flow.colecciones_activas();
--   drop table if exists flow.coleccion_servicio;
--   drop table if exists flow.coleccion;
--
-- ⚠ SE APLICA EN LOS DOS PROYECTOS: `qhprswhhfasrikhawjoz` (debug) y
--   `vsieeihstajlrdvpuooh` (release).
-- ════════════════════════════════════════════════════════════════════════════


-- ── 1. Comprobación previa ─────────────────────────────────────────────────
do $pre$
begin
  if to_regclass('flow.local_servicio') is null then
    raise exception 'Falta el esquema base: flow.local_servicio no existe';
  end if;
  if to_regprocedure('public.fn_is_superadmin_full_access()') is null then
    raise exception
      'Falta 28_patrocinados.sql: public.fn_is_superadmin_full_access() no existe';
  end if;
end
$pre$;


-- ── 2. Tablas ──────────────────────────────────────────────────────────────
create table if not exists flow.coleccion (
  id           serial primary key,
  titulo       varchar(120) not null,
  subtitulo    text,
  icono        text,
  color_inicio text,
  color_fin    text,
  orden        integer     not null default 0,
  activo       boolean     not null default true,
  desde        timestamptz,
  hasta        timestamptz,
  created_by   uuid,
  created_at   timestamptz not null default current_timestamp,
  updated_at   timestamptz not null default current_timestamp
);

-- `orden` es la posición dentro de la colección (el orden en que se eligieron
-- los servicios), no un campo de la fila de servicio.
create table if not exists flow.coleccion_servicio (
  id_coleccion      integer not null references flow.coleccion(id)      on delete cascade,
  id_local_servicio integer not null references flow.local_servicio(id) on delete cascade,
  orden             integer not null default 0,
  primary key (id_coleccion, id_local_servicio)
);

create index if not exists idx_coleccion_servicio_ls
  on flow.coleccion_servicio (id_local_servicio);

create index if not exists idx_coleccion_activa
  on flow.coleccion (activo, orden, id);


-- ── 3. RLS ─────────────────────────────────────────────────────────────────
-- El cliente NO lee las tablas directamente: usa `colecciones_activas()`
-- (SECURITY INVOKER), que respeta estas políticas. Las de escritura solo dejan
-- pasar al superadmin.
alter table flow.coleccion          enable row level security;
alter table flow.coleccion_servicio enable row level security;

-- El cliente solo ve colecciones ACTIVAS. Un borrador no se filtra.
drop policy if exists coleccion_select_activas on flow.coleccion;
create policy coleccion_select_activas on flow.coleccion
  for select to authenticated
  using (activo);

-- El superadmin necesita ver también las apagadas (para encenderlas).
-- Ambas son permisivas: se suman con OR.
drop policy if exists coleccion_select_superadmin on flow.coleccion;
create policy coleccion_select_superadmin on flow.coleccion
  for select to authenticated
  using (public.fn_is_superadmin_full_access());

drop policy if exists coleccion_insert_superadmin on flow.coleccion;
create policy coleccion_insert_superadmin on flow.coleccion
  for insert to authenticated
  with check (public.fn_is_superadmin_full_access());

drop policy if exists coleccion_update_superadmin on flow.coleccion;
create policy coleccion_update_superadmin on flow.coleccion
  for update to authenticated
  using (public.fn_is_superadmin_full_access())
  with check (public.fn_is_superadmin_full_access());

drop policy if exists coleccion_delete_superadmin on flow.coleccion;
create policy coleccion_delete_superadmin on flow.coleccion
  for delete to authenticated
  using (public.fn_is_superadmin_full_access());

-- Los enlaces solo exponen ids de servicios que ya son visibles en el catálogo;
-- se dejan legibles para que el RPC invoker del cliente pueda resolver el
-- conjunto de servicios de cada colección.
drop policy if exists coleccion_servicio_select_autenticados on flow.coleccion_servicio;
create policy coleccion_servicio_select_autenticados on flow.coleccion_servicio
  for select to authenticated
  using (true);

drop policy if exists coleccion_servicio_insert_superadmin on flow.coleccion_servicio;
create policy coleccion_servicio_insert_superadmin on flow.coleccion_servicio
  for insert to authenticated
  with check (public.fn_is_superadmin_full_access());

drop policy if exists coleccion_servicio_update_superadmin on flow.coleccion_servicio;
create policy coleccion_servicio_update_superadmin on flow.coleccion_servicio
  for update to authenticated
  using (public.fn_is_superadmin_full_access())
  with check (public.fn_is_superadmin_full_access());

drop policy if exists coleccion_servicio_delete_superadmin on flow.coleccion_servicio;
create policy coleccion_servicio_delete_superadmin on flow.coleccion_servicio
  for delete to authenticated
  using (public.fn_is_superadmin_full_access());


-- ── 4. RPC del cliente ─────────────────────────────────────────────────────

-- Colecciones vigentes con su conjunto de servicios.
--
-- Una colección **sin servicios no se devuelve**: pintaría una tarjeta vacía en
-- el Home. Tampoco se devuelven las apagadas ni las fuera de vigencia.
--
-- Se devuelve `servicios` como array de `id_local_servicio` porque el Home
-- filtra y pagina **en memoria** sobre el catálogo ya cacheado (igual que hace
-- con las categorías), así que no necesita una segunda petición por colección.
create or replace function flow.colecciones_activas()
returns jsonb
language sql
stable
set search_path to 'flow', 'public'
as $function$
  select coalesce(
    jsonb_agg(to_jsonb(t) order by t.orden asc, t.id asc),
    '[]'::jsonb
  )
  from (
    select
      c.id,
      c.titulo,
      c.subtitulo,
      c.icono,
      c.color_inicio,
      c.color_fin,
      c.orden,
      c.hasta,
      (select count(*)
         from flow.coleccion_servicio cs
        where cs.id_coleccion = c.id) as total_servicios,
      (select coalesce(
                jsonb_agg(cs.id_local_servicio
                          order by cs.orden asc, cs.id_local_servicio asc),
                '[]'::jsonb)
         from flow.coleccion_servicio cs
        where cs.id_coleccion = c.id) as servicios
    from flow.coleccion c
    where c.activo
      and (c.desde is null or (now() at time zone 'America/Havana') >= c.desde)
      and (c.hasta is null or (now() at time zone 'America/Havana') <  c.hasta)
      and exists (select 1 from flow.coleccion_servicio cs where cs.id_coleccion = c.id)
  ) t;
$function$;


-- ── 5. RPC del superadmin ──────────────────────────────────────────────────

create or replace function flow.admin_listar_colecciones(p_uuid_usuario uuid)
returns jsonb
language plpgsql
stable
set search_path to 'flow', 'public'
as $function$
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error',
      'Solo el superadmin puede gestionar colecciones');
  end if;

  return jsonb_build_object('ok', true, 'data', (
    select coalesce(
      jsonb_agg(to_jsonb(t) order by t.orden asc, t.id asc),
      '[]'::jsonb
    )
    from (
      select
        c.id, c.titulo, c.subtitulo, c.icono,
        c.color_inicio, c.color_fin, c.orden, c.activo,
        c.desde, c.hasta, c.created_at, c.updated_at,
        (select count(*)
           from flow.coleccion_servicio cs
          where cs.id_coleccion = c.id) as total_servicios,
        (select coalesce(
                  jsonb_agg(cs.id_local_servicio
                            order by cs.orden asc, cs.id_local_servicio asc),
                  '[]'::jsonb)
           from flow.coleccion_servicio cs
          where cs.id_coleccion = c.id) as servicios
      from flow.coleccion c
    ) t
  ));
end;
$function$;


-- Alta (p_id null) o edición. `p_servicios` REEMPLAZA el conjunto completo:
-- es un array JSON de `id_local_servicio` y el orden del array manda.
create or replace function flow.admin_guardar_coleccion(
  p_uuid_usuario uuid,
  p_titulo       text,
  p_subtitulo    text      default null,
  p_icono        text      default null,
  p_color_inicio text      default null,
  p_color_fin    text      default null,
  p_orden        integer   default 0,
  p_activo       boolean   default true,
  p_desde        timestamptz default null,
  p_hasta        timestamptz default null,
  p_servicios    jsonb     default '[]'::jsonb,
  p_id           integer   default null
)
returns jsonb
language plpgsql
set search_path to 'flow', 'public'
as $function$
declare
  v_id    integer;
  v_idls  integer;
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error',
      'Solo el superadmin puede gestionar colecciones');
  end if;

  if btrim(coalesce(p_titulo, '')) = '' then
    return jsonb_build_object('ok', false, 'error', 'El titulo es obligatorio');
  end if;
  if p_desde is not null and p_hasta is not null and p_desde >= p_hasta then
    return jsonb_build_object('ok', false, 'error',
      'La fecha de fin debe ser posterior al inicio');
  end if;
  if jsonb_typeof(coalesce(p_servicios, '[]'::jsonb)) <> 'array' then
    return jsonb_build_object('ok', false, 'error',
      'p_servicios debe ser un array de id_local_servicio');
  end if;

  -- Validar TODOS los servicios antes de escribir nada.
  for v_idls in
    select (e.v)::int
      from jsonb_array_elements_text(coalesce(p_servicios, '[]'::jsonb)) as e(v)
  loop
    if not exists (select 1 from flow.local_servicio where id = v_idls) then
      return jsonb_build_object('ok', false, 'error',
        'El servicio ' || v_idls || ' no existe');
    end if;
  end loop;

  if p_id is null then
    insert into flow.coleccion
      (titulo, subtitulo, icono, color_inicio, color_fin,
       orden, activo, desde, hasta, created_by)
    values
      (btrim(p_titulo),
       nullif(btrim(coalesce(p_subtitulo, '')), ''),
       nullif(btrim(coalesce(p_icono, '')), ''),
       nullif(btrim(coalesce(p_color_inicio, '')), ''),
       nullif(btrim(coalesce(p_color_fin, '')), ''),
       coalesce(p_orden, 0), coalesce(p_activo, true),
       p_desde, p_hasta, auth.uid())
    returning id into v_id;
  else
    update flow.coleccion
       set titulo       = btrim(p_titulo),
           subtitulo    = nullif(btrim(coalesce(p_subtitulo, '')), ''),
           icono        = nullif(btrim(coalesce(p_icono, '')), ''),
           color_inicio = nullif(btrim(coalesce(p_color_inicio, '')), ''),
           color_fin    = nullif(btrim(coalesce(p_color_fin, '')), ''),
           orden        = coalesce(p_orden, 0),
           activo       = coalesce(p_activo, true),
           desde        = p_desde,
           hasta        = p_hasta,
           updated_at   = current_timestamp
     where id = p_id
     returning id into v_id;

    if v_id is null then
      return jsonb_build_object('ok', false, 'error', 'Coleccion inexistente');
    end if;

    delete from flow.coleccion_servicio where id_coleccion = v_id;
  end if;

  -- `distinct on` porque el mismo id repetido en el array chocaría dos veces
  -- contra la PK en un único INSERT ... ON CONFLICT ("cannot affect row a
  -- second time"). Gana la primera aparición, que es la que fija el orden.
  insert into flow.coleccion_servicio (id_coleccion, id_local_servicio, orden)
  select v_id, d.id_ls, (row_number() over (order by d.pos)) - 1
  from (
    select distinct on ((e.v)::int)
           (e.v)::int as id_ls, e.pos
      from jsonb_array_elements_text(coalesce(p_servicios, '[]'::jsonb))
           with ordinality as e(v, pos)
     order by (e.v)::int, e.pos
  ) d;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'id', v_id,
    'servicios', (select count(*)
                    from flow.coleccion_servicio
                   where id_coleccion = v_id)
  ));
exception
  when others then
    return jsonb_build_object('ok', false, 'error', sqlerrm, 'sqlstate', sqlstate);
end;
$function$;


create or replace function flow.admin_alternar_coleccion(
  p_uuid_usuario uuid,
  p_id           integer,
  p_activo       boolean
)
returns jsonb
language plpgsql
set search_path to 'flow', 'public'
as $function$
declare
  v_id integer;
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error',
      'Solo el superadmin puede gestionar colecciones');
  end if;

  update flow.coleccion
     set activo = coalesce(p_activo, true),
         updated_at = current_timestamp
   where id = p_id
   returning id into v_id;

  if v_id is null then
    return jsonb_build_object('ok', false, 'error', 'Coleccion inexistente');
  end if;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'id', v_id, 'activo', coalesce(p_activo, true)));
end;
$function$;


create or replace function flow.admin_eliminar_coleccion(
  p_uuid_usuario uuid,
  p_id           integer
)
returns jsonb
language plpgsql
set search_path to 'flow', 'public'
as $function$
declare
  v_id integer;
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error',
      'Solo el superadmin puede gestionar colecciones');
  end if;

  delete from flow.coleccion_servicio where id_coleccion = p_id;
  delete from flow.coleccion where id = p_id returning id into v_id;

  if v_id is null then
    return jsonb_build_object('ok', false, 'error', 'Coleccion inexistente');
  end if;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));
end;
$function$;


-- ── 6. Permisos ────────────────────────────────────────────────────────────
-- Al crear la tabla el ACL queda solo para el dueño: hay que conceder explícito.
grant usage on schema flow to authenticated;
grant select, insert, update, delete on flow.coleccion          to authenticated;
grant select, insert, update, delete on flow.coleccion_servicio to authenticated;
grant usage, select on sequence flow.coleccion_id_seq           to authenticated;

-- Escrituras y lecturas del panel: solo authenticated (nunca anon).
revoke all on function flow.colecciones_activas()                from public, anon;
revoke all on function flow.admin_listar_colecciones(uuid)       from public, anon;
revoke all on function flow.admin_guardar_coleccion(uuid, text, text, text, text, text, integer, boolean, timestamptz, timestamptz, jsonb, integer) from public, anon;
revoke all on function flow.admin_alternar_coleccion(uuid, integer, boolean)     from public, anon;
revoke all on function flow.admin_eliminar_coleccion(uuid, integer)              from public, anon;

grant execute on function flow.colecciones_activas()                to authenticated, service_role;
grant execute on function flow.admin_listar_colecciones(uuid)       to authenticated, service_role;
grant execute on function flow.admin_guardar_coleccion(uuid, text, text, text, text, text, integer, boolean, timestamptz, timestamptz, jsonb, integer) to authenticated, service_role;
grant execute on function flow.admin_alternar_coleccion(uuid, integer, boolean)     to authenticated, service_role;
grant execute on function flow.admin_eliminar_coleccion(uuid, integer)              to authenticated, service_role;

-- PostgREST cachea el esquema: sin esto los RPC nuevos dan 404 hasta el reload.
notify pgrst, 'reload schema';


-- ── 7. Verificación ────────────────────────────────────────────────────────

-- 7.a Tablas creadas y con RLS activo
select c.relname as tabla, c.relrowsecurity as rls
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'flow' and c.relname in ('coleccion', 'coleccion_servicio')
order by c.relname;

-- 7.b Políticas (deben salir 4 en coleccion y 4 en coleccion_servicio)
select tablename, policyname, cmd
from pg_policies
where schemaname = 'flow' and tablename in ('coleccion', 'coleccion_servicio')
order by tablename, cmd, policyname;

-- 7.c Las 5 funciones existen
select p.proname, p.prosecdef as es_definer
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'flow'
  and p.proname in ('colecciones_activas', 'admin_listar_colecciones',
                    'admin_guardar_coleccion', 'admin_alternar_coleccion',
                    'admin_eliminar_coleccion')
order by p.proname;

-- 7.d `anon` NO puede ejecutarlas (deben salir los 5 en false)
select 'colecciones_activas' as rpc,
       has_function_privilege('anon', 'flow.colecciones_activas()', 'execute') as anon_puede
union all select 'admin_listar_colecciones',
       has_function_privilege('anon', 'flow.admin_listar_colecciones(uuid)', 'execute')
union all select 'admin_guardar_coleccion',
       has_function_privilege('anon', 'flow.admin_guardar_coleccion(uuid, text, text, text, text, text, integer, boolean, timestamptz, timestamptz, jsonb, integer)', 'execute')
union all select 'admin_alternar_coleccion',
       has_function_privilege('anon', 'flow.admin_alternar_coleccion(uuid, integer, boolean)', 'execute')
union all select 'admin_eliminar_coleccion',
       has_function_privilege('anon', 'flow.admin_eliminar_coleccion(uuid, integer)', 'execute');

-- 7.e Al principio no hay ninguna colección (es normal)
select count(*) as colecciones from flow.coleccion;


-- ── 8. Prueba funcional manual (OPCIONAL, se revierte sola) ────────────────
-- Pega este bloque aparte, después del anterior. Termina en ROLLBACK.
--
-- begin;
--   -- Crea una colección con 2 servicios y comprueba que el cliente la ve.
--   -- (Ejecuta como `postgres`: las RPC admin exigen una sesión con JWT, así
--   --  que aquí se inserta directo para comprobar la parte de lectura.)
--   with nueva as (
--     insert into flow.coleccion (titulo, subtitulo, icono, color_inicio, color_fin, orden, activo)
--     values ('TEST ROLLBACK', 'Colección de prueba', '🧪', '#2C3654', '#1FA8B8', 0, true)
--     returning id
--   ), ls as (
--     select id, row_number() over (order by id) - 1 as pos
--     from flow.local_servicio order by id limit 2
--   )
--   insert into flow.coleccion_servicio (id_coleccion, id_local_servicio, orden)
--   select n.id, l.id, l.pos from nueva n cross join ls l;
--
--   -- Debe devolver 1 colección con total_servicios = 2 y 2 ids en `servicios`
--   select jsonb_pretty(flow.colecciones_activas());
--
--   -- Apagarla debe hacerla desaparecer de la vista del cliente
--   update flow.coleccion set activo = false where titulo = 'TEST ROLLBACK';
--   select flow.colecciones_activas() as tras_apagar;   -- debe ser []
-- rollback;
