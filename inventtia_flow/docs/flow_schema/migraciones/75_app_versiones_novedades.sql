-- ════════════════════════════════════════════════════════════════════════════
-- MIGRACION 75: CHANGELOG E HISTORIAL DE VERSIONES EN `public.app_versiones`
-- ════════════════════════════════════════════════════════════════════════════
--
-- QUE HACE
--   1. Tres columnas nuevas en `public.app_versiones` (idempotentes):
--        · titulo        text          -> titular corto ("🚌 PDF de reservas…").
--        · novedades     jsonb not null default '[]' -> array de cambios:
--            [{"type":"feature|improvement|fix","title":"...","description":"..."}]
--        · url_descarga  text          -> APK directo de ESA versión; NULL =
--                                         cada app usa su enlace por defecto.
--      Las filas existentes nacen con titulo/url_descarga NULL y novedades '[]':
--      NO se inventan changelogs retroactivos (ver el UPDATE de ejemplo comentado).
--
--   2. Helper `public.fn_version_menor(p_a text, p_b text)`: compara versiones
--      por partes numéricas separadas por punto, tolerante a vacíos y sufijos
--      ("1.4.9" < "1.4.10", "1.4" = "1.4.0", "1.4.7-beta" = "1.4.7"). immutable.
--
--   3. `public.fn_check_update(p_app_name varchar, p_version_actual varchar,
--      p_build_actual integer)` — MISMA FIRMA y TODAS las claves actuales
--      (`hay_actualizacion`, `version_disponible`, `obligatoria`,
--      `version_minima`, `fecha_lanzamiento`) con el mismo significado, más:
--      `id_version`, `build_disponible`, `titulo`, `novedades`, `url_descarga`.
--      MEJORA: `obligatoria = actualizacion_obligatoria OR
--      fn_version_menor(p_version_actual, version_minima)`, así subir
--      `version_minima` fuerza la actualización aunque el build ya sea el último.
--
--   4. `public.fn_app_versiones(p_app_name varchar, p_limit integer default 30)`:
--      historial para la app, `{ok:true, data:[…]}` ordenado por build desc,
--      solo filas `activa = true`, límite acotado a 1..100.
--
--   5. `public.fn_app_version_guardar(...)` y `public.fn_app_version_eliminar(id)`:
--      gestión del superadmin para el panel, con guard interno
--      `public.fn_is_superadmin_full_access()`.
--
-- POR QUÉ `security definer` EN TODO
--   `app_versiones` tiene RLS activa y la app llama a `fn_check_update` /
--   `fn_app_versiones` con `anon` (antes de iniciar sesión). Sin definer, la RLS
--   dejaría al anon sin filas (o reventaría, ver abajo). Además la escritura debe
--   saltarse la RLS: la hacen solo los RPC con guard de superadmin.
--
-- BUG LATENTE QUE SE ARREGLA (documentado, no es una clave del contrato)
--   La versión original de `fn_check_update` declaraba `v_latest RECORD` y hacía
--   `COALESCE(v_latest.version_actual,'')`. Si no hay ninguna fila activa para
--   esa app, un RECORD sin asignar revienta al leer un campo («record is not
--   assigned yet») en vez de responder "no hay actualización". La 75 usa
--   `public.app_versiones%rowtype` + `found`, así que sin filas devuelve el
--   shape seguro: hay_actualizacion=false y las claves nuevas en null/'[]'.
--   (Mismo criterio que documenta la migración 33 para `%rowtype`.)
--
-- SEGURIDAD: RLS de `app_versiones` (endurecimiento incluido aquí)
--   Estado ANTES (verificado con MCP el 2026-10-30):
--     · RLS activa, una sola política `app_versiones_authenticated_all`
--       (ALL, authenticated, using(true) with check(true));
--     · `anon` y `authenticated` con TODOS los privilegios de tabla
--       (SELECT/INSERT/UPDATE/DELETE/TRUNCATE…).
--     Resultado: cualquier usuario autenticado de CUALQUIERA de las 5 apps podía
--     insertar/editar/borrar versiones por PostgREST (y ahora, con
--     `url_descarga`, publicar un APK falso en un aviso de actualización).
--   DESPUÉS:
--     · se elimina la política de escritura y se deja solo lectura para
--       `authenticated`;
--     · se revocan INSERT/UPDATE/DELETE/TRUNCATE de `anon` y `authenticated`.
--       `service_role`/`postgres` conservan todo, y los RPC definer (superadmin)
--       siguen escribiendo. Ninguna app del repo escribe la tabla directamente
--       (solo se consulta por `fn_check_update`), así que no se rompe nada.
--
-- OJO CON LOS DEFAULT EN `fn_app_version_guardar` (trampa heredada del contrato)
--   La firma pedida trae `p_obligatoria boolean default false` y
--   `p_activa boolean default true`. Como los defaults NO son null, una llamada
--   de UPDATE que omita esos dos campos los aplicará (false/true) en vez de
--   conservarlos. Para conservar el valor actual hay que enviar `null` explícito:
--   `{"p_id": 168, "p_titulo": "…", "p_obligatoria": null, "p_activa": null}`.
--   El resto de campos nuevos sí conservan con NULL (patrón del repo).
--
-- DEPENDE DE: `public.app_versiones` y `public.fn_check_update(varchar,varchar,int)`
--             (migración base de versiones) y `public.fn_is_superadmin_full_access()`.
--             El bloque previo lo comprueba y falla claro si falta algo.
-- NO APLICAR AUTOMATICAMENTE: este archivo lo pega el usuario en el editor SQL.
--
-- REVERSIBILIDAD: ver el bloque comentado al final. Incluye la definición
-- ORIGINAL de `fn_check_update` leída de la base (OJO: esa función NO está en
-- `ventiq_app/supabase/` del repo; solo vive en la base de datos).
-- ════════════════════════════════════════════════════════════════════════════

-- ── 0. Comprobación previa ──────────────────────────────────────────────────
do $pre$
begin
  if to_regclass('public.app_versiones') is null then
    raise exception 'Falta public.app_versiones: aplica primero la migración base de versiones.';
  end if;

  if (select count(*)
        from information_schema.columns
       where table_schema = 'public' and table_name = 'app_versiones'
         and column_name in ('app_name','version_actual','version_minima',
                             'build_number','actualizacion_obligatoria',
                             'fecha_lanzamiento','activa')) <> 7 then
    raise exception 'public.app_versiones no tiene la forma esperada: faltan columnas base.';
  end if;

  if to_regprocedure('public.fn_check_update(character varying,character varying,integer)') is null then
    raise exception 'Falta public.fn_check_update(character varying,character varying,integer): aplica la migración base antes de la 75.';
  end if;

  if to_regprocedure('public.fn_is_superadmin_full_access()') is null then
    raise exception 'Falta public.fn_is_superadmin_full_access(): lo usan fn_app_version_guardar y fn_app_version_eliminar.';
  end if;
end
$pre$;

-- ══ 1. COLUMNAS NUEVAS ══════════════════════════════════════════════════════
--
-- Idempotentes. Las filas existentes quedan con titulo/url_descarga NULL y
-- novedades '[]': no se inventan changelogs retroactivos.

alter table public.app_versiones add column if not exists titulo text;
alter table public.app_versiones add column if not exists novedades jsonb not null default '[]'::jsonb;
alter table public.app_versiones add column if not exists url_descarga text;

comment on column public.app_versiones.titulo is
  'Titular corto de la version para la tarjeta de novedades ("🚌 PDF de reservas y listado mas claro"). NULL = sin titular.';
comment on column public.app_versiones.novedades is
  'Array jsonb de cambios: [{"type":"feature|improvement|fix","title":"...","description":"..."}]. Nunca null: sin changelog es [].';
comment on column public.app_versiones.url_descarga is
  'Enlace directo al APK de ESTA version (http/https). NULL = cada app usa su enlace por defecto.';

-- ════════════════════════════════════════════════════════════════════════════
-- EJEMPLO DE RELLENO (COMENTADO): la última versión de `inventtia_flow`.
-- Descomentar y ajustar a gusto. El historial ya publicado NO se toca.
-- ════════════════════════════════════════════════════════════════════════════
--
-- update public.app_versiones
--    set titulo = '🚌 PDF de reservas y listado más claro',
--        novedades = '[
--          {"type":"feature","title":"PDF de reservas","description":"Descarga e imprime el comprobante de cualquier reserva."},
--          {"type":"improvement","title":"Listado más claro","description":"Filtros y totales visibles sin abrir el detalle."},
--          {"type":"fix","title":"Corrección de zona horaria","description":"Las horas ya no se desplazan al cambiar de día."}
--        ]'::jsonb
--  where id = (select v.id
--                from public.app_versiones v
--               where v.app_name = 'inventtia_flow'
--               order by v.build_number desc, v.id desc
--               limit 1);

-- ══ 2. RLS Y PERMISOS DE TABLA (endurecimiento) ═════════════════════════════
--
-- Antes: política ALL para authenticated con using(true) + privilegios totales
-- para anon/authenticated => cualquier usuario logueado podía escribir versiones.
-- Ahora: lectura para authenticated; la escritura solo por RPC definer
-- (superadmin), service_role o postgres.

alter table public.app_versiones enable row level security;

drop policy if exists app_versiones_authenticated_all on public.app_versiones;
drop policy if exists app_versiones_select_authenticated on public.app_versiones;
create policy app_versiones_select_authenticated on public.app_versiones
  for select to authenticated
  using (true);

revoke insert, update, delete, truncate on public.app_versiones from anon, authenticated;

-- ══ 3. HELPER: COMPARAR VERSIONES ═══════════════════════════════════════════
--
-- Partes numéricas separadas por punto; cada parte usa su primer bloque de
-- dígitos (sufijos tipo "-beta" o prefijos tipo "v" no estorban). Vacío/NULL
-- equivale a 0. Igual longitud lógica: "1.4" = "1.4.0".
create or replace function public.fn_version_menor(p_a text, p_b text)
returns boolean
language plpgsql
immutable
set search_path to 'public'
as $function$
declare
  v_a      text[]  := string_to_array(btrim(coalesce(p_a, '')), '.');
  v_b      text[]  := string_to_array(btrim(coalesce(p_b, '')), '.');
  v_partes integer;
  v_na     integer;
  v_nb     integer;
begin
  -- Sin versión se trata como '0': cualquier versión real es mayor y un
  -- `version_minima` vacío nunca fuerza una actualización.
  if btrim(coalesce(p_a, '')) = '' then v_a := array['0']; end if;
  if btrim(coalesce(p_b, '')) = '' then v_b := array['0']; end if;

  v_partes := greatest(coalesce(array_length(v_a, 1), 0),
                       coalesce(array_length(v_b, 1), 0));
  if v_partes = 0 then
    return false;
  end if;

  for i in 1..v_partes loop
    v_na := coalesce((substring(coalesce(v_a[i], '') from '([0-9]+)'))::integer, 0);
    v_nb := coalesce((substring(coalesce(v_b[i], '') from '([0-9]+)'))::integer, 0);

    if v_na < v_nb then
      return true;
    end if;
    if v_na > v_nb then
      return false;
    end if;
  end loop;

  return false;   -- iguales ("1.4" = "1.4.0")
end;
$function$;

comment on function public.fn_version_menor(text, text) is
  'TRUE si p_a es una version menor que p_b (partes numericas por punto, tolerante a vacios y sufijos). Inmutable.';

-- ══ 4. fn_check_update (MISMA FIRMA, CLAVES NUEVAS) ═════════════════════════
--
-- Conserva las 5 claves originales con su significado exacto y añade las nuevas.
-- `obligatoria` incorpora la comparación con `version_minima`.
create or replace function public.fn_check_update(
  p_app_name      character varying,
  p_version_actual character varying,
  p_build_actual  integer
)
returns json
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_latest       public.app_versiones%rowtype;
  v_hay          boolean := false;
  v_build_actual integer := coalesce(p_build_actual, 0);
begin
  -- Última versión activa de la app. `id` como desempate: si dos filas
  -- comparten build, gana la insertada después.
  select v.* into v_latest
  from public.app_versiones v
  where v.app_name = p_app_name
    and v.activa = true
  order by v.build_number desc, v.id desc
  limit 1;

  if found and coalesce(v_latest.build_number, 0) > v_build_actual then
    v_hay := true;
  end if;

  return json_build_object(
    -- ── claves originales (mismo significado) ──
    'hay_actualizacion',  v_hay,
    'version_disponible', coalesce(v_latest.version_actual, ''),
    'obligatoria',        coalesce(v_latest.actualizacion_obligatoria, false)
                          or public.fn_version_menor(p_version_actual, v_latest.version_minima),
    'version_minima',     coalesce(v_latest.version_minima, ''),
    'fecha_lanzamiento',  coalesce(v_latest.fecha_lanzamiento, now()),
    -- ── claves nuevas (72/75: null o [] cuando no hay actualización) ──
    'id_version',         case when v_hay then v_latest.id else null end,
    'build_disponible',   case when v_hay then v_latest.build_number else null end,
    'titulo',             case when v_hay then v_latest.titulo else null end,
    'novedades',          case
                            when v_hay and jsonb_typeof(v_latest.novedades) = 'array'
                              then v_latest.novedades
                            else '[]'::jsonb
                          end,
    'url_descarga',       case when v_hay then v_latest.url_descarga else null end
  );
end;
$function$;

comment on function public.fn_check_update(character varying,character varying,integer) is
  'Ultima version activa de la app: conserva hay_actualizacion/version_disponible/obligatoria/version_minima/fecha_lanzamiento y añade id_version, build_disponible, titulo, novedades y url_descarga. obligatoria tambien es true si la version instalada es menor que version_minima.';

-- ══ 5. HISTORIAL PARA LA APP ════════════════════════════════════════════════
create or replace function public.fn_app_versiones(
  p_app_name varchar,
  p_limit    integer default 30
)
returns json
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_limit integer;
begin
  if p_app_name is null or btrim(p_app_name) = '' then
    return json_build_object('ok', false, 'error', 'Falta el nombre de la app');
  end if;

  -- Límite acotado: ni 0 filas ni un barrido de toda la tabla.
  v_limit := least(greatest(coalesce(p_limit, 30), 1), 100);

  return json_build_object('ok', true, 'data', coalesce((
    select json_agg(x.fila order by x.build_number desc, x.id desc)
    from (
      select
        v.build_number,
        v.id,
        json_build_object(
          'id',                v.id,
          'version_actual',    v.version_actual,
          'build_number',      v.build_number,
          'titulo',            v.titulo,
          'novedades',         case
                                 when jsonb_typeof(v.novedades) = 'array'
                                   then v.novedades
                                 else '[]'::jsonb
                               end,
          'fecha_lanzamiento', v.fecha_lanzamiento,
          'obligatoria',       coalesce(v.actualizacion_obligatoria, false),
          'version_minima',    v.version_minima
        ) as fila
      from public.app_versiones v
      where v.app_name = p_app_name
        and v.activa = true
      order by v.build_number desc, v.id desc
      limit v_limit
    ) x
  ), '[]'::json));
end;
$function$;

comment on function public.fn_app_versiones(varchar, integer) is
  'Historial de versiones activas de una app (changelog incluido), de la mas nueva a la mas vieja, con limite 1..100.';

-- ══ 6. SUPERADMIN: GUARDAR VERSION ══════════════════════════════════════════
--
-- AVISO: al INSERTAR con `activa = true` se dispara el trigger existente
-- `trigger_notificar_nueva_version`, que notifica a los usuarios de la app. Es
-- el comportamiento actual de la tabla; no se toca.
create or replace function public.fn_app_version_guardar(
  p_id             integer default null,
  p_app_name       varchar default null,
  p_version_actual varchar default null,
  p_build_number   integer default null,
  p_version_minima varchar default null,
  p_obligatoria    boolean default false,
  p_titulo         text    default null,
  p_novedades      jsonb   default null,
  p_url_descarga   text    default null,
  p_activa         boolean default true
)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_id        integer := p_id;
  v_row       public.app_versiones%rowtype;
  v_titulo    text;
  v_url       text;
  v_novedades jsonb;
begin
  if not public.fn_is_superadmin_full_access() then
    return json_build_object('ok', false, 'error', 'Solo el superadmin puede gestionar versiones');
  end if;

  -- ── Validaciones comunes ──
  if p_novedades is not null and jsonb_typeof(p_novedades) <> 'array' then
    return json_build_object('ok', false,
      'error', 'Las novedades deben ser un array jsonb: [{"type":"feature","title":"...","description":"..."}]');
  end if;

  if p_url_descarga is not null and btrim(p_url_descarga) <> ''
     and btrim(p_url_descarga) !~* '^https?://' then
    return json_build_object('ok', false,
      'error', 'La url de descarga debe empezar por http:// o https://');
  end if;

  if p_build_number is not null and p_build_number <= 0 then
    return json_build_object('ok', false, 'error', 'El build debe ser mayor que 0');
  end if;

  -- ── CREAR ──
  if v_id is null then
    if p_app_name is null or btrim(p_app_name) = '' then
      return json_build_object('ok', false, 'error', 'Falta el nombre de la app');
    end if;
    if p_version_actual is null or btrim(p_version_actual) = '' then
      return json_build_object('ok', false, 'error', 'Falta la version');
    end if;
    if p_build_number is null then
      return json_build_object('ok', false, 'error', 'Falta el build');
    end if;
    -- La columna es NOT NULL: mejor un error claro que un 23502 críptico.
    if p_version_minima is null or btrim(p_version_minima) = '' then
      return json_build_object('ok', false, 'error', 'Falta la version minima (version_minima)');
    end if;

    insert into public.app_versiones
      (app_name, version_actual, version_minima, build_number,
       actualizacion_obligatoria, titulo, novedades, url_descarga, activa)
    values
      (btrim(p_app_name), btrim(p_version_actual), btrim(p_version_minima),
       p_build_number,
       coalesce(p_obligatoria, false),
       nullif(btrim(coalesce(p_titulo, '')), ''),
       coalesce(p_novedades, '[]'::jsonb),
       nullif(btrim(coalesce(p_url_descarga, '')), ''),
       coalesce(p_activa, true))
    returning id into v_id;

    return json_build_object('ok', true, 'data',
      json_build_object('id', v_id, 'creado', true));
  end if;

  -- ── ACTUALIZAR ──
  select v.* into v_row
  from public.app_versiones v
  where v.id = v_id;

  if not found then
    return json_build_object('ok', false, 'error', 'La version no existe');
  end if;

  -- NULL conserva; cadena vacía limpia (titulo y url_descarga).
  v_titulo := case
                when p_titulo is null then v_row.titulo
                when btrim(p_titulo) = '' then null
                else btrim(p_titulo)
              end;

  v_url := case
             when p_url_descarga is null then v_row.url_descarga
             when btrim(p_url_descarga) = '' then null
             else btrim(p_url_descarga)
           end;

  v_novedades := coalesce(p_novedades, v_row.novedades);

  update public.app_versiones v
     set app_name                  = coalesce(nullif(btrim(coalesce(p_app_name, '')), ''), v.app_name),
         version_actual            = coalesce(nullif(btrim(coalesce(p_version_actual, '')), ''), v.version_actual),
         version_minima            = coalesce(nullif(btrim(coalesce(p_version_minima, '')), ''), v.version_minima),
         build_number              = coalesce(p_build_number, v.build_number),
         actualizacion_obligatoria = coalesce(p_obligatoria, v.actualizacion_obligatoria),
         titulo                    = v_titulo,
         novedades                 = v_novedades,
         url_descarga              = v_url,
         activa                    = coalesce(p_activa, v.activa)
   where v.id = v_id;

  return json_build_object('ok', true, 'data',
    json_build_object('id', v_id, 'creado', false));
end;
$function$;

comment on function public.fn_app_version_guardar(integer,varchar,varchar,integer,varchar,boolean,text,jsonb,text,boolean) is
  'Superadmin: crea o actualiza una version de app (titulo, novedades, url_descarga). En UPDATE los null conservan, salvo p_obligatoria/p_activa cuyos defaults false/true se aplican si se omiten.';

-- ══ 7. SUPERADMIN: ELIMINAR VERSION ═════════════════════════════════════════
create or replace function public.fn_app_version_eliminar(p_id integer)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_row    public.app_versiones%rowtype;
  v_ultima boolean := false;
  v_data   jsonb;
begin
  if not public.fn_is_superadmin_full_access() then
    return json_build_object('ok', false, 'error', 'Solo el superadmin puede gestionar versiones');
  end if;

  if p_id is null then
    return json_build_object('ok', false, 'error', 'Falta el id de la version');
  end if;

  select v.* into v_row
  from public.app_versiones v
  where v.id = p_id;

  if not found then
    return json_build_object('ok', false, 'error', 'La version no existe');
  end if;

  delete from public.app_versiones where id = p_id;

  -- Solo avisa si la borrada estaba activa y era la última activa de esa app.
  if coalesce(v_row.activa, false) then
    select not exists (
      select 1 from public.app_versiones v
      where v.app_name = v_row.app_name
        and v.activa = true
    ) into v_ultima;
  end if;

  v_data := jsonb_build_object('eliminado', true);

  if v_ultima then
    v_data := v_data || jsonb_build_object('aviso',
      'Era la ultima version activa de ' || v_row.app_name ||
      ': esa app dejara de avisar de actualizaciones hasta que publiques otra.');
  end if;

  return json_build_object('ok', true, 'data', v_data);
end;
$function$;

comment on function public.fn_app_version_eliminar(integer) is
  'Superadmin: borra una version. Si era la ultima activa de su app, avisa de que esa app dejara de anunciar actualizaciones.';

-- ══ 8. PERMISOS ═════════════════════════════════════════════════════════════
--
-- La app consulta antes de loguear: fn_check_update y fn_app_versiones van a
-- anon/authenticated/service_role. Guardar/eliminar llevan guard interno de
-- superadmin. El helper de comparación no se expone a la app.

revoke all on function public.fn_version_menor(text, text) from public, anon, authenticated;
grant execute on function public.fn_version_menor(text, text) to service_role;

revoke all on function public.fn_check_update(character varying,character varying,integer)
  from public, anon, authenticated, service_role;
grant execute on function public.fn_check_update(character varying,character varying,integer)
  to anon, authenticated, service_role;

revoke all on function public.fn_app_versiones(varchar, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.fn_app_versiones(varchar, integer)
  to anon, authenticated, service_role;

revoke all on function public.fn_app_version_guardar(
  integer,varchar,varchar,integer,varchar,boolean,text,jsonb,text,boolean) from public, anon;
grant execute on function public.fn_app_version_guardar(
  integer,varchar,varchar,integer,varchar,boolean,text,jsonb,text,boolean) to authenticated, service_role;

revoke all on function public.fn_app_version_eliminar(integer) from public, anon;
grant execute on function public.fn_app_version_eliminar(integer) to authenticated, service_role;

notify pgrst, 'reload schema';

-- ════════════════════════════════════════════════════════════════════════════
-- 9. VERIFICACIÓN (comentada: ejecutar a mano DESPUÉS de aplicar)
-- ════════════════════════════════════════════════════════════════════════════
--
-- 9.1 Columnas nuevas (esperado: 3 filas; novedades jsonb not null default []).
-- select column_name, data_type, is_nullable, column_default
--   from information_schema.columns
--  where table_schema = 'public' and table_name = 'app_versiones'
--    and column_name in ('titulo','novedades','url_descarga')
--  order by column_name;
--
-- 9.2 El helper compara como se espera.
-- select public.fn_version_menor('1.4.9','1.4.10')   as menor,        -- true
--        public.fn_version_menor('1.4.10','1.4.9')   as mayor,        -- false
--        public.fn_version_menor('1.4','1.4.0')      as iguales,      -- false
--        public.fn_version_menor('1.4.7-beta','1.4.7') as con_sufijo, -- false
--        public.fn_version_menor('','1.0.0')         as vacio_menor,  -- true
--        public.fn_version_menor('1.0.0','')         as contra_vacio; -- false
--
-- 9.3 La consulta pedida: con inventtia_flow (build 14, version 1.4.6) hay
--     actualización a la build 15 (1.4.7) y llega el changelog.
-- select public.fn_check_update('inventtia_flow','1.4.6',14);
--   -- esperado: {"hay_actualizacion":true,"version_disponible":"1.4.7",
--   --            "obligatoria":true,"version_minima":"1.4.7",
--   --            "fecha_lanzamiento":"2026-08-03T16:36:37.300517-04:00",
--   --            "id_version":168,"build_disponible":15,"titulo":null,
--   --            "novedades":[],"url_descarga":null}
--
-- 9.4 Ya al día: hay_actualizacion=false y las claves nuevas en null/'[]'
--     (las 5 originales se conservan).
-- select public.fn_check_update('inventtia_flow','1.4.7',15);
--
-- 9.5 Historial.
-- select public.fn_app_versiones('inventtia_flow');       -- ok true, 11 filas
-- select jsonb_array_length((public.fn_app_versiones('inventtia_flow')::jsonb) -> 'data');  -- 11
-- select public.fn_app_versiones('inventtia_flow', 5);    -- 5 filas
-- select public.fn_app_versiones('inventtia_flow', 999);  -- 11 (acotado a 100)
-- select public.fn_app_versiones('no_existe');            -- ok true, data []
--
-- 9.6 La mejora de `obligatoria` con `version_minima` (dato real:
--     ventiq_marketplace última = 1.6.0 / version_minima 1.0.0 /
--     actualizacion_obligatoria = false).
-- select public.fn_check_update('ventiq_marketplace','0.9.0',13);
--   -- ANTES: obligatoria=false.  DESPUÉS: obligatoria=true (0.9.0 < 1.0.0).
--
-- 9.7 RLS: ya no hay política de escritura para authenticated.
-- select policyname, cmd, roles, qual, with_check
--   from pg_policies
--  where schemaname = 'public' and tablename = 'app_versiones';
--   -- esperado: solo app_versiones_select_authenticated (SELECT, {authenticated})
--
-- 9.8 Sin sesión sigue funcionando (clave: definer).
-- select public.fn_check_update('inventtia_flow','1.4.6',14);
-- select public.fn_app_versiones('inventtia_flow', 3);
--
-- 9.9 Guardar/eliminar exigen superadmin (sin sesión de superadmin => ok false).
-- select public.fn_app_version_guardar(p_app_name := 'inventtia_flow');
-- select public.fn_app_version_eliminar(999999);
--
-- 9.10 Reejecutar la migración es no-op: mismas firmas, sin sobrecargas.
-- select p.proname, pg_get_function_identity_arguments(p.oid) as args
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'public'
--    and p.proname in ('fn_version_menor','fn_check_update','fn_app_versiones',
--                      'fn_app_version_guardar','fn_app_version_eliminar')
--  order by p.proname;
--
-- ════════════════════════════════════════════════════════════════════════════
-- 10. REVERSIÓN (comentada: NO ejecutar salvo que haya que deshacer)
-- ════════════════════════════════════════════════════════════════════════════
--
-- -- 10.1 Restaurar la versión ORIGINAL de fn_check_update. OJO: esta función NO
-- --      está en el repo (`ventiq_app/supabase/` no la contiene); esta es la
-- --      definición leída de la base con pg_get_functiondef el 2026-10-30.
-- create or replace function public.fn_check_update(
--   p_app_name character varying,
--   p_version_actual character varying,
--   p_build_actual integer
-- )
-- returns json
-- language plpgsql
-- as $function$
-- DECLARE
--     v_latest RECORD;
--     v_hay_update BOOLEAN := FALSE;
-- BEGIN
--     -- Obtener última versión activa
--     SELECT * INTO v_latest
--     FROM app_versiones
--     WHERE app_name = p_app_name AND activa = TRUE
--     ORDER BY build_number DESC
--     LIMIT 1;
--
--     -- Verificar si hay actualización
--     IF FOUND AND v_latest.build_number > p_build_actual THEN
--         v_hay_update := TRUE;
--     END IF;
--
--     RETURN json_build_object(
--         'hay_actualizacion', v_hay_update,
--         'version_disponible', COALESCE(v_latest.version_actual, ''),
--         'obligatoria', COALESCE(v_latest.actualizacion_obligatoria, false),
--         'version_minima', COALESCE(v_latest.version_minima, ''),
--         'fecha_lanzamiento', COALESCE(v_latest.fecha_lanzamiento, NOW())
--     );
-- END;
-- $function$;
--
-- revoke all on function public.fn_check_update(character varying,character varying,integer)
--   from public, anon, authenticated, service_role;
-- grant execute on function public.fn_check_update(character varying,character varying,integer)
--   to anon, authenticated, service_role;
--
-- -- 10.2 Borrar los RPC nuevos y el helper.
-- drop function if exists public.fn_app_version_eliminar(integer);
-- drop function if exists public.fn_app_version_guardar(
--   integer,varchar,varchar,integer,varchar,boolean,text,jsonb,text,boolean);
-- drop function if exists public.fn_app_versiones(varchar, integer);
-- drop function if exists public.fn_version_menor(text, text);
--
-- -- 10.3 Restaurar la RLS anterior (política ALL para authenticated).
-- drop policy if exists app_versiones_select_authenticated on public.app_versiones;
-- create policy app_versiones_authenticated_all on public.app_versiones
--   for all to authenticated using (true) with check (true);
-- grant insert, update, delete, truncate on public.app_versiones to anon, authenticated;
--
-- -- 10.4 Borrar las columnas nuevas (¡se pierden titulo/novedades/url_descarga!).
-- alter table public.app_versiones drop column if exists url_descarga;
-- alter table public.app_versiones drop column if exists novedades;
-- alter table public.app_versiones drop column if exists titulo;
--
-- notify pgrst, 'reload schema';
-- ════════════════════════════════════════════════════════════════════════════