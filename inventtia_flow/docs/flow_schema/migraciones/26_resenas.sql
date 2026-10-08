-- ============================================================================
-- MIGRACION: resenas de servicio (verificadas contra reserva completada)
--
-- POR QUE
--   El Home pintaba estrellas, "142 resenas" y una "Resena del dia" con autor
--   inventado. No habia tabla ni forma de que un cliente opinara. Esta migracion
--   crea el modelo real: una resena por reserva COMPLETADA.
--
-- EL ANCLA ES LA RESERVA, NO EL SERVICIO
--   La resena cuelga de `agenda` (la reserva concreta), no directamente del
--   servicio:
--     * `id_agenda` UNIQUE  -> una resena por reserva: no se puede inflar el
--       rating resenando 10 veces el mismo turno.
--     * `id_local_servicio` -> para listar todas las resenas de un servicio sin
--       pasar por la agenda.
--     * La reserva debe estar en estado 'Completado' (id 3 de
--       `nom_estado_agenda`). No basta con que exista: reservar y cancelar no
--       da derecho a opinar.
--   Hoy hay 73 reservas en estado Completado, asi que la seccion tendra datos
--   reales desde el primer dia.
--
-- INVOKER vs DEFINER (el detalle que hace que esto funcione)
--   * `publicar_resena` / `eliminar_mi_resena` -> SECURITY INVOKER. Toda la
--     autorizacion la hacen las politicas RLS: el INSERT exige que la reserva
--     sea tuya y este completada.
--   * `resenas_de_servicio` / `resenas_recientes` -> SECURITY DEFINER. NO es
--     por comodidad: RLS de `flow.perfil` es `perfil_select_own` y la de
--     `flow.agenda` solo deja ver lo propio, asi que un invoker no podria
--     resolver el nombre de OTROS autores (todos saldrian "Cliente") ni saber
--     si la resena es tuya. Como definer saltan RLS, y por eso cada funcion
--     **comprueba el rol con `auth.role()`** y filtra por `auth.uid()`
--     explicitamente en SQL en vez de confiar en las politicas.
--   * `resenas_por_servicio` -> INVOKER: es un agregado sobre `flow.resena`,
--     que ya es legible por cualquier autenticado. No toca `perfil`.
--
-- PRIVACIDAD DEL AUTOR
--   Se expone el nombre y la INICIAL del apellido ("Ana R."), nunca el apellido
--   completo ni el CI ni el telefono. Se resuelve en el RPC, no en el cliente,
--   para que un cambio de criterio no obligue a tocar la app.
--
-- QUE CREA
--   - Tabla flow.resena + RLS + indices.
--   - publicar_resena        (el cliente publica/edita la suya)
--   - eliminar_mi_resena     (el cliente borra la suya)
--   - resenas_de_servicio    (resumen + lista + "puedo resenar" para el detalle)
--   - resenas_recientes      (feed corto para el Home)
--   - resenas_por_servicio   (agregado que alimenta las estrellas del feed)
--
-- REVERSION
--   drop function if exists flow.publicar_resena(uuid, integer, smallint, text);
--   drop function if exists flow.eliminar_mi_resena(uuid, bigint);
--   drop function if exists flow.resenas_de_servicio(integer, integer, integer);
--   drop function if exists flow.resenas_recientes(integer);
--   drop function if exists flow.resenas_por_servicio();
--   drop table if exists flow.resena;
--   (Es una creacion nueva: no toca ninguna tabla existente.)
--
-- DEPENDE DE: nada. Se puede aplicar sola.
-- ============================================================================

create table if not exists flow.resena (
  id                 bigint generated always as identity primary key,
  id_agenda          integer not null unique
                     references flow.agenda(id) on delete cascade,
  id_local_servicio  integer not null
                     references flow.local_servicio(id) on delete cascade,
  uuid_usuario       uuid not null
                     references auth.users(id) on delete cascade,
  puntuacion         smallint not null check (puntuacion between 1 and 5),
  comentario         text,
  created_at         timestamp not null default current_timestamp,
  updated_at         timestamp not null default current_timestamp,
  constraint resena_comentario_no_vacio
    check (comentario is null or length(btrim(comentario)) > 0),
  constraint resena_comentario_longitud
    check (comentario is null or length(comentario) <= 1000)
);

comment on table flow.resena is
  'Resenas de clientes, una por reserva COMPLETADA. El autor solo se expone como nombre + inicial.';

-- La clave foranea va contra `auth.users`, igual que `flow.favorito`. Con 5261
-- usuarios en auth y solo 19 filas en `flow.perfil`, apuntar a `perfil` dejaria
-- a la mayoria sin poder resenar.

-- Sobre `on delete cascade` en id_agenda: ninguna funcion del esquema borra
-- filas de `agenda` (los bot solo hacen UPDATE de `agendados`), asi que la
-- cascada no deberia dispararse en operacion normal. Si alguien borra una
-- reserva a mano, su resena deja de estar verificada y lo coherente es que
-- desaparezca.

create index if not exists idx_resena_servicio_fecha
  on flow.resena (id_local_servicio, created_at desc);

create index if not exists idx_resena_usuario
  on flow.resena (uuid_usuario, created_at desc);

-- ============================================================================
-- RLS
--   SELECT -> autenticados: una resena es contenido que su autor publica a
--     proposito para que lo lean otros clientes. No se abre a `anon`.
--   INSERT -> solo el autor, y solo si la reserva es suya y esta completada.
--   UPDATE/DELETE -> solo el autor.
-- ============================================================================
alter table flow.resena enable row level security;

drop policy if exists "resena_select_autenticados" on flow.resena;
drop policy if exists "resena_insert_propia" on flow.resena;
drop policy if exists "resena_update_propia" on flow.resena;
drop policy if exists "resena_delete_propia" on flow.resena;

create policy "resena_select_autenticados"
on flow.resena
for select
to authenticated
using (true);

create policy "resena_insert_propia"
on flow.resena
for insert
to authenticated
with check (
  uuid_usuario = auth.uid()
  and exists (
    select 1
    from flow.agenda a
    join flow.nom_estado_agenda e on e.id = a.id_estado
    where a.id = id_agenda
      and a.id_local_servicio = id_local_servicio
      and e.nombre = 'Completado'
      and (a.uuid_usuario = auth.uid() or a.reservado_por = auth.uid())
  )
);

create policy "resena_update_propia"
on flow.resena
for update
to authenticated
using (uuid_usuario = auth.uid())
with check (uuid_usuario = auth.uid());

create policy "resena_delete_propia"
on flow.resena
for delete
to authenticated
using (uuid_usuario = auth.uid());

revoke all on flow.resena from anon;
grant select, insert, update, delete on flow.resena to authenticated;
grant all on flow.resena to service_role;

-- ============================================================================
-- 1. publicar_resena  (INVOKER: autoriza RLS)
--    Crea o actualiza la resena del usuario para una reserva completada suya.
-- ============================================================================
create or replace function flow.publicar_resena(
  p_uuid_usuario uuid,
  p_id_agenda integer,
  p_puntuacion smallint,
  p_comentario text default null
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = flow, public
as $$
declare
  v_agenda      record;
  v_comentario  text;
  v_id          bigint;
begin
  if p_uuid_usuario is null or p_id_agenda is null then
    return jsonb_build_object('ok', false, 'error', 'Faltan parametros');
  end if;

  -- El uuid debe ser el de la sesion: recibirlo por parametro es suplantable.
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;

  if p_puntuacion is null or p_puntuacion < 1 or p_puntuacion > 5 then
    return jsonb_build_object('ok', false, 'error', 'La puntuacion debe ser de 1 a 5');
  end if;

  v_comentario := nullif(btrim(coalesce(p_comentario, '')), '');
  if v_comentario is not null and length(v_comentario) > 1000 then
    return jsonb_build_object('ok', false, 'error', 'El comentario es demasiado largo (max 1000)');
  end if;

  -- `agenda` bajo RLS solo deja ver las propias, asi que este SELECT ya filtra.
  select a.id, a.id_local_servicio, a.uuid_usuario, a.reservado_por, e.nombre as estado
    into v_agenda
  from flow.agenda a
  join flow.nom_estado_agenda e on e.id = a.id_estado
  where a.id = p_id_agenda;

  if v_agenda.id is null then
    return jsonb_build_object('ok', false, 'error', 'La reserva no existe o no es tuya');
  end if;

  if v_agenda.estado <> 'Completado' then
    return jsonb_build_object(
      'ok', false,
      'error', 'Solo puedes resenar un servicio que ya te atendieron'
    );
  end if;

  insert into flow.resena (
    id_agenda, id_local_servicio, uuid_usuario, puntuacion, comentario
  )
  values (
    p_id_agenda, v_agenda.id_local_servicio, p_uuid_usuario, p_puntuacion, v_comentario
  )
  on conflict (id_agenda) do update
    set puntuacion = excluded.puntuacion,
        comentario = excluded.comentario,
        updated_at = current_timestamp
  returning id into v_id;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id', v_id,
      'id_agenda', p_id_agenda,
      'id_local_servicio', v_agenda.id_local_servicio
    )
  );
end;
$$;

-- ============================================================================
-- 2. eliminar_mi_resena  (INVOKER)
-- ============================================================================
create or replace function flow.eliminar_mi_resena(
  p_uuid_usuario uuid,
  p_id_resena bigint
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

  delete from flow.resena
   where id = p_id_resena and uuid_usuario = p_uuid_usuario;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Resena inexistente o no es tuya');
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

-- ============================================================================
-- 3. resenas_de_servicio  (DEFINER, con guarda de rol y filtro explicito)
--
--    Todo lo que necesita la seccion de resenas del detalle: resumen con
--    distribucion por estrellas, lista paginada, la resena propia si existe, y
--    la reserva completada que el usuario todavia puede resenar (para no
--    ofrecer un formulario que fallaria al guardar).
-- ============================================================================
create or replace function flow.resenas_de_servicio(
  p_id_local_servicio integer,
  p_limit integer default 20,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = flow, public
as $$
declare
  v_result jsonb;
begin
  -- Definir salta RLS: la autorizacion se hace aqui.
  if coalesce(auth.role(), 'anon') <> 'authenticated' then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;

  with mias as (
    select r.id, r.id_agenda, r.puntuacion, r.comentario, r.created_at
    from flow.resena r
    where r.id_local_servicio = p_id_local_servicio
      and r.uuid_usuario = auth.uid()
    limit 1
  ),
  resenable as (
    select
      a.id as id_agenda,
      coalesce(a.fecha_hora_atencion, a.fecha_hora_reserva) as atendido
    from flow.agenda a
    join flow.nom_estado_agenda e on e.id = a.id_estado
    where a.id_local_servicio = p_id_local_servicio
      and e.nombre = 'Completado'
      -- Filtro explicito en SQL: como definer se ven TODAS las agendas, asi que
      -- la restriccion a las propias tiene que estar aqui, no en RLS.
      and (a.uuid_usuario = auth.uid() or a.reservado_por = auth.uid())
      and not exists (select 1 from flow.resena r where r.id_agenda = a.id)
    order by coalesce(a.fecha_hora_atencion, a.fecha_hora_reserva) desc
    limit 1
  ),
  listado as (
    select
      r.id,
      r.puntuacion,
      r.comentario,
      r.created_at,
      case
        when p.nombre is null then 'Cliente'
        when p.apellidos is null or btrim(p.apellidos) = '' then btrim(p.nombre)
        else btrim(p.nombre) || ' ' || upper(left(btrim(p.apellidos), 1)) || '.'
      end as autor,
      (r.uuid_usuario = auth.uid()) as es_mia
    from flow.resena r
    left join flow.perfil p on p.uuid_usuario = r.uuid_usuario
    where r.id_local_servicio = p_id_local_servicio
    order by r.created_at desc
    limit greatest(1, least(coalesce(p_limit, 20), 50))
    offset greatest(0, coalesce(p_offset, 0))
  )
  select jsonb_build_object(
    'ok', true,
    'resumen', (
      select jsonb_build_object(
        'total',     count(*),
        'promedio',  coalesce(round(avg(puntuacion)::numeric, 1), 0),
        'estrellas', jsonb_build_object(
          '5', count(*) filter (where puntuacion = 5),
          '4', count(*) filter (where puntuacion = 4),
          '3', count(*) filter (where puntuacion = 3),
          '2', count(*) filter (where puntuacion = 2),
          '1', count(*) filter (where puntuacion = 1)
        )
      )
      from flow.resena
      where id_local_servicio = p_id_local_servicio
    ),
    'items', coalesce(
      (select jsonb_agg(to_jsonb(l) order by l.created_at desc) from listado l),
      '[]'::jsonb
    ),
    'mi_resena', (select to_jsonb(m) from mias m),
    'agenda_resenable', (select to_jsonb(x) from resenable x)
  ) into v_result;

  return v_result;
end;
$$;

-- ============================================================================
-- 4. resenas_recientes  (DEFINER por el join a `perfil`)
--    Feed corto para el Home. Se priorizan las que traen comentario: una lista
--    de "5 estrellas" sin texto no aporta nada en una seccion de resenas.
-- ============================================================================
create or replace function flow.resenas_recientes(p_limit integer default 5)
returns jsonb
language plpgsql
stable
security definer
set search_path = flow, public
as $$
declare
  v_result jsonb;
begin
  if coalesce(auth.role(), 'anon') <> 'authenticated' then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;

  select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc), '[]'::jsonb)
    into v_result
  from (
    select
      r.id,
      r.puntuacion,
      r.comentario,
      r.created_at,
      r.id_local_servicio,
      s.nombre as servicio,
      l.nombre as local,
      case
        when p.nombre is null then 'Cliente'
        when p.apellidos is null or btrim(p.apellidos) = '' then btrim(p.nombre)
        else btrim(p.nombre) || ' ' || upper(left(btrim(p.apellidos), 1)) || '.'
      end as autor
    from flow.resena r
    join flow.local_servicio ls on ls.id = r.id_local_servicio
    join flow.app_dat_servicios s on s.id = ls.id_servicio
    join flow.app_dat_locales l on l.id = ls.local
    left join flow.perfil p on p.uuid_usuario = r.uuid_usuario
    where r.comentario is not null
    order by r.created_at desc
    limit greatest(1, least(coalesce(p_limit, 5), 20))
  ) t;

  return jsonb_build_object('ok', true, 'data', v_result);
end;
$$;

-- ============================================================================
-- 5. resenas_por_servicio  (INVOKER: agregado sobre `resena`, sin `perfil`)
--
--    Alimenta las estrellas de las tarjetas del feed. Solo devuelve los
--    servicios que tienen al menos una resena; quien no aparece **no tiene
--    valoracion**, y la UI no debe inventarsela.
-- ============================================================================
create or replace function flow.resenas_por_servicio()
returns table (
  id_local_servicio integer,
  total bigint,
  promedio numeric
)
language sql
stable
security invoker
set search_path = flow, public
as $$
  select r.id_local_servicio, count(*)::bigint,
         round(avg(r.puntuacion)::numeric, 1)
  from flow.resena r
  group by r.id_local_servicio
  order by r.id_local_servicio;
$$;

revoke all on function flow.publicar_resena(uuid, integer, smallint, text)
  from public, anon;
revoke all on function flow.eliminar_mi_resena(uuid, bigint)
  from public, anon;
revoke all on function flow.resenas_de_servicio(integer, integer, integer)
  from public, anon;
revoke all on function flow.resenas_recientes(integer)
  from public, anon;
revoke all on function flow.resenas_por_servicio()
  from public, anon;

grant execute on function flow.publicar_resena(uuid, integer, smallint, text)
  to authenticated, service_role;
grant execute on function flow.eliminar_mi_resena(uuid, bigint)
  to authenticated, service_role;
grant execute on function flow.resenas_de_servicio(integer, integer, integer)
  to authenticated, service_role;
grant execute on function flow.resenas_recientes(integer)
  to authenticated, service_role;
grant execute on function flow.resenas_por_servicio()
  to authenticated, service_role;

notify pgrst, 'reload schema';

-- ============================================================================
-- Verificacion
-- ============================================================================
select 'tabla' as objeto, c.relname as nombre,
       c.relrowsecurity as rls_activo,
       coalesce(array_to_string(c.relacl::text[], ' | '), 'default') as acl
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'flow' and c.relname = 'resena'
union all
select 'policy', policyname, true, cmd::text || ' → ' || roles::text
from pg_policies where schemaname = 'flow' and tablename = 'resena'
union all
select 'funcion', p.proname, p.prosecdef,
       coalesce(array_to_string(p.proacl::text[], ' | '), 'default')
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'flow' and p.proname in (
  'publicar_resena', 'eliminar_mi_resena', 'resenas_de_servicio',
  'resenas_recientes', 'resenas_por_servicio'
)
order by objeto, nombre;

-- Reservas que HOY podrian resenarse (para saber si la seccion tendra datos).
select count(*) as reservas_resenables
from flow.agenda a
join flow.nom_estado_agenda e on e.id = a.id_estado
where e.nombre = 'Completado';