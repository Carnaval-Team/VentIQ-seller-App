-- ============================================================================
-- MIGRACION: cerrar el IDOR de los RPC de listado
--
-- HALLAZGO (ajeno al Home; encontrado al auditar el esquema `flow`)
--
--   Estas funciones son SECURITY DEFINER, es decir saltan RLS, y varias
--   autorizan con un parametro que envia el cliente (`p_uuid_usuario`) en vez de
--   con `auth.uid()`, que lo pone el motor. Quien llama puede pasar el uuid de
--   OTRO administrador y leer sus reservas:
--
--     select * from flow.admin_listar_agendas(
--       p_uuid_usuario := '<uuid de otro admin>'
--     );
--
--   Y lo peor: `admin_listar_agendas` tiene EXECUTE concedido a `anon`, ademas
--   del GRANT a PUBLIC que Postgres pone por defecto en toda funcion nueva. Es
--   decir, se puede explotar SIN INICIAR SESION con la publishable key.
--
--   El JSON que devuelve `admin_listar_agendas` incluye el bloque 'cliente' con
--   perfil.ci, nombre, apellidos y telefono: datos personales de terceros.
--
--   `admin_listar_admins` y `admin_listar_vendedores` no comprueban NADA: con
--   cualquier p_id_entidad devuelven los uuid y los emails (auth.users) de los
--   administradores y vendedores de esa entidad.
--
-- QUE CAMBIA
--   1. Las 4 funciones de agendas pasan a autorizar con `auth.uid()`.
--   2. `admin_listar_admins` y `admin_listar_vendedores` empiezan a comprobar
--      que quien llama administra esa entidad.
--   3. La familia admin_*/vendedor_*/staff_* deja de ser ejecutable por `anon`.
--
-- LA FIRMA NO CAMBIA en ningun caso: el Dart ya manda su propio uuid en
-- `p_uuid_usuario`, asi que la app no necesita tocarse. El parametro se sigue
-- aceptando pero deja de decidir el acceso.
--
-- COMO SE APLICAN LOS CAMBIOS 1
--   Las 4 funciones de agendas devuelven un jsonb grande (~200 lineas) que vive
--   en la base de datos. Reescribirlas a mano invita a un typo que romperia el
--   panel admin. En vez de eso, el bloque lee la definicion VIVA con
--   `pg_get_functiondef`, sustituye solo la expresion de autorizacion y la
--   vuelve a crear. Si el patron no aparece, ABORTA en vez de continuar en
--   silencio. Es idempotente: si ya esta aplicado, informa y no hace nada.
--
-- REVERSION
--   No se pierde nada de datos: son CREATE OR REPLACE. Para volver al estado
--   anterior habria que redefinir las funciones autorizando por parametro (no
--   recomendado: reabre el agujero).
-- ============================================================================


-- ============================================================================
-- 1. Las 4 funciones de agendas: autorizar por auth.uid()
-- ============================================================================
do $$
declare
  r        record;
  v_def    text;
  v_nuevo  text;
  v_cambios integer;
begin
  for r in
    select p.oid, p.proname
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'flow'
      and p.proname in (
        'admin_listar_agendas',
        'admin_listar_agendas_por_estado',
        'vendedor_listar_agendas',
        'vendedor_listar_agendas_por_estado'
      )
    order by p.proname
  loop
    v_def    := pg_get_functiondef(r.oid);
    v_nuevo  := v_def;
    v_cambios := 0;

    -- Helper de entidades: el parametro pasa a ser auth.uid()
    v_nuevo := regexp_replace(
      v_nuevo,
      'admin_entidades_de_usuario\s*\(\s*p_uuid_usuario\s*\)',
      'admin_entidades_de_usuario(auth.uid())',
      'g');

    -- Idem para el helper de vendedores (por si alguna lo usara)
    v_nuevo := regexp_replace(
      v_nuevo,
      'vendedor_entidades_de_usuario\s*\(\s*p_uuid_usuario\s*\)',
      'vendedor_entidades_de_usuario(auth.uid())',
      'g');

    -- JOIN directo contra entidad_vendedor
    v_nuevo := regexp_replace(
      v_nuevo,
      'ev\.uuid_usuario\s*=\s*p_uuid_usuario',
      'ev.uuid_usuario = auth.uid()',
      'g');

    if v_nuevo <> v_def then
      v_cambios := 1;
    end if;

    if v_cambios = 0 then
      -- Puede ser que ya este aplicado (tiene auth.uid() y no el parametro).
      if v_def ilike '%auth.uid()%' then
        raise notice 'flow.% ya autoriza con auth.uid(); no se toca', r.proname;
      else
        raise exception
          'No se encontro el patron de autorizacion por parametro en flow.%. '
          'Revisar a mano: la definicion puede haber cambiado.',
          r.proname;
      end if;
    else
      -- El parametro sigue en la FIRMA (no se puede cambiar sin romper el Dart),
      -- asi que lo que hay que comprobar es que ya no aparezca en el CUERPO.
      if position('p_uuid_usuario' in split_part(v_nuevo, 'AS $function$', 2)) > 0 then
        raise exception
          'flow.% sigue usando p_uuid_usuario dentro del cuerpo. Abortado.',
          r.proname;
      end if;
      if position('auth.uid()' in v_nuevo) = 0 then
        raise exception
          'La reescritura de flow.% no introdujo auth.uid(). Abortado.',
          r.proname;
      end if;
      execute v_nuevo;
      raise notice 'flow.% pasa a autorizar con auth.uid()', r.proname;
    end if;
  end loop;
end $$;


-- ============================================================================
-- 2. admin_listar_admins / admin_listar_vendedores
--
--    Solo reciben p_id_entidad y no validaban nada. Ahora exigen que quien
--    llama administre esa entidad. Misma firma, mismas columnas y mismo orden:
--    EntidadService.getAdmins / getVendedores no cambian.
-- ============================================================================
create or replace function flow.admin_listar_admins(p_id_entidad integer)
returns table (
  id integer,
  id_entidad integer,
  uuid_usuario uuid,
  asignado_por uuid,
  created_at timestamp without time zone,
  email text
)
language sql
stable
security definer
set search_path = flow, auth
as $$
  select ea.id, ea.id_entidad, ea.uuid_usuario, ea.asignado_por,
         ea.created_at, u.email::text
  from flow.entidad_admin ea
  join auth.users u on u.id = ea.uuid_usuario
  where ea.id_entidad = p_id_entidad
    -- Sin esta comprobacion, cualquier autenticado (o anonimo, por el grant a
    -- PUBLIC) podia listar los uuid y emails de los admins de cualquier entidad.
    and exists (
      select 1 from flow.admin_entidades_de_usuario(auth.uid()) mine
      where mine.id_entidad = p_id_entidad
    )
  order by ea.created_at;
$$;

create or replace function flow.admin_listar_vendedores(p_id_entidad integer)
returns table (
  id integer,
  id_entidad integer,
  uuid_usuario uuid,
  asignado_por uuid,
  created_at timestamp without time zone,
  email text
)
language sql
stable
security definer
set search_path = flow, auth
as $$
  select ev.id, ev.id_entidad, ev.uuid_usuario, ev.asignado_por,
         ev.created_at, u.email::text
  from flow.entidad_vendedor ev
  join auth.users u on u.id = ev.uuid_usuario
  where ev.id_entidad = p_id_entidad
    and exists (
      select 1 from flow.admin_entidades_de_usuario(auth.uid()) mine
      where mine.id_entidad = p_id_entidad
    )
  order by ev.created_at;
$$;


-- ============================================================================
-- 3. Quitar EXECUTE a anon / PUBLIC en la familia de panel
--
--    `grants_flow.sql` hace `grant execute on all functions ... to anon`, y
--    Postgres ademas concede EXECUTE a PUBLIC por defecto en toda funcion nueva.
--    Estos RPC son de panel: solo `authenticated` (y `service_role`).
--
--    OJO: se concede ADEMAS a `service_role` de forma explicita. Los permisos de
--    funcion son ACL normales y `bypassrls` NO otorga EXECUTE, asi que un
--    `revoke from public` a secas dejaria fuera al bot y a las tareas que usan
--    la service_role key. El owner (`postgres`) no se ve afectado: revoke no
--    toca al owner.
-- ============================================================================
do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as firma
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'flow'
      and (
        left(p.proname, 6) = 'admin_'
        or left(p.proname, 9) = 'vendedor_'
        or left(p.proname, 6) = 'staff_'
      )
  loop
    execute format('revoke all on function %s from public, anon', f.firma);
    execute format(
      'grant execute on function %s to authenticated, service_role', f.firma);
  end loop;
end $$;

-- Para que los RPC nuevos nazcan ya cerrados, sin depender de que cada
-- migracion recuerde el revoke. Ojo: a partir de aqui, un RPC `cliente_*` nuevo
-- que deba ser invocable por `anon` necesita su `grant execute ... to anon`
-- explicito (los existentes ya lo tienen).
alter default privileges in schema flow revoke execute on functions from public;
alter default privileges in schema flow revoke execute on functions from anon;
alter default privileges in schema flow
  grant execute on functions to authenticated, service_role;


-- ============================================================================
-- 4. Verificacion
--
--    Esperado en las 4 primeras: autoriza_con_auth_uid = true y sin `anon` ni
--    `=X/postgres` (PUBLIC) en el ACL.
-- ============================================================================
select p.proname,
       coalesce(array_to_string(p.proacl::text[], ' | '), 'default(PUBLIC)') as acl,
       (pg_get_functiondef(p.oid) ilike '%auth.uid()%') as autoriza_con_auth_uid,
       -- Ojo: `p_uuid_usuario` sigue en la FIRMA a proposito (el Dart lo manda).
       -- Lo que debe ser 0 es su uso dentro del CUERPO.
       (select count(*) from regexp_matches(
          split_part(pg_get_functiondef(p.oid), 'AS $function$', 2),
          'p_uuid_usuario', 'g')) as usos_en_cuerpo
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'flow'
  and p.proname in (
    'admin_listar_agendas', 'admin_listar_agendas_por_estado',
    'vendedor_listar_agendas', 'vendedor_listar_agendas_por_estado',
    'admin_listar_admins', 'admin_listar_vendedores'
  )
order by p.proname;


-- ============================================================================
-- 5. PROBAR DESPUES DE APLICAR (no automatizable desde aqui)
--
--   Con la app, como administrador de una entidad:
--     [ ] Admin → Reservas carga y lista las reservas de TU entidad.
--     [ ] Admin → Planificación y el calendario siguen mostrando ocupación.
--     [ ] Admin → Configurar entidad: la lista de Admins y Vendedores aparece.
--     [ ] Reservas → exportar PDF/Excel sigue funcionando.
--     [ ] Como vendedor: "Reservas" lista las de sus entidades.
--
--   Negativo (debe FALLAR o devolver vacio):
--     [ ] Volver a ejecutar la migracion: informa "ya autoriza con auth.uid()"
--         y no duplica nada.
--     [ ] Desde el cliente con la publishable key y SIN sesion:
--           POST /rest/v1/rpc/admin_listar_agendas   → debe dar 401/403.
--
--   Si algo del panel admin dejara de listar, el sospechoso es el paso 3
--   (permisos). Se recupera concediendo de nuevo:
--     grant execute on function flow.<firma> to authenticated;
--   Los datos no se tocan en ningun caso: solo cambian cuerpos de funcion y ACLs.
-- ============================================================================