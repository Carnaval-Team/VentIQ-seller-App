-- ============================================================================
-- 36 - Ranking semanal del Home ("Servicios populares de la semana")
-- ============================================================================
-- QUE HACE
--   Anade `flow.cliente_ranking_semanal(p_limite)`: los servicios con mas
--   demanda REAL en la semana natural en curso (lunes 00:00, hora de La Habana)
--   ya en la misma forma de item que el feed del Home.
--
-- POR QUE ASI
--   * La metrica es "lugares reservados", no "numero de reservas". En los datos
--     reales hay un servicio con 3 reservas que suman 11 lugares y otro con 3
--     reservas que suman 3: ordenar por numero de reservas los dejaria empatados
--     y el desempate seria invisible. Asi, el numero que se pinta
--     ("11 lugares reservados") es EXACTAMENTE el que ordena la lista.
--   * Solo cuentan `Reservado` (1) y `Completado` (3). Una `Cancelado` (2) no es
--     demanda: contarla inflaria el ranking con intenciones que no se
--     sostuvieron.
--   * La ventana es la semana natural (`date_trunc('week', now())`), que es lo
--     que promete el titulo del bloque ("de la semana"), y no "los ultimos 7
--     dias", que es otra cosa.
--   * **No define la forma del item**: reusa la que ya construye
--     `flow.cliente_home_feed()` y solo le inyecta `lugares_semana`. Repetir
--     aqui las 60 lineas de proyeccion anidada seria volver a tener dos
--     definiciones del mismo objeto, que es como aparecen los descuadres.
--   * Un servicio sin reservas esta semana **no aparece**. El bloque no pinta
--     nada en vez de rellenar con el orden del catalogo, que es lo que hacia
--     `_buildWeeklyPopular` con `_items.take(3)`: posiciones 1-2-3 que no
--     significaban nada.
--
-- ALCANCE
--   `p_limite` acota cuantos servicios devuelve (por defecto 5).
--
-- ROLLBACK
--   drop function if exists flow.cliente_ranking_semanal(integer);
--   Ademas: poner `rankingSemanal = false` en lib/config/home_features.dart y
--   revertir el commit del cliente.
--
-- ANTES DE APLICAR
--   Requiere 35_home_feed.sql aplicada: esta funcion compone
--   `flow.cliente_home_feed()`.
-- ============================================================================

do $pre$
begin
  if to_regprocedure('flow.cliente_home_feed(text,integer,text,integer,boolean)') is null then
    raise exception 'Falta 35_home_feed.sql: aplica antes la migracion del feed del Home.';
  end if;
end
$pre$;

create or replace function flow.cliente_ranking_semanal(
  p_limite integer default 5
)
returns jsonb
language sql
stable
security invoker
set search_path to 'flow','public'
as $function$
  with ventana as (
    select
      a.id_local_servicio,
      -- `greatest(..., 1)`: una reserva con cantidad 0 o nula sigue siendo una
      -- reserva; contarla como 0 la haria desaparecer del ranking.
      sum(greatest(coalesce(a.cantidad, 1), 1))::integer as lugares,
      count(*)::integer                                   as reservas
    from flow.agenda a
    where a.id_estado in (1, 3)
      and a.created_at is not null
      and a.created_at >= date_trunc('week', now())
    group by a.id_local_servicio
  ),
  puntaje as (
    select
      v.id_local_servicio,
      v.lugares,
      v.reservas,
      row_number() over (
        order by v.lugares desc, v.reservas desc, v.id_local_servicio asc
      ) as rn
    from ventana v
  ),
  con_item as (
    select
      jsonb_set(it.value, '{lugares_semana}', to_jsonb(p.lugares)) as item,
      p.rn
    from puntaje p
      join jsonb_array_elements(flow.cliente_home_feed() -> 'items') as it(value)
        on (it.value ->> 'id_local_servicio')::integer = p.id_local_servicio
  )
  select coalesce(jsonb_agg(c.item order by c.rn), '[]'::jsonb)
  from con_item c
  where c.rn <= greatest(p_limite, 1);
$function$;

-- ---------------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------------
-- `create or replace function` conserva el ACL si la funcion ya existia, pero
-- una funcion NUEVA recibe EXECUTE para `authenticated` por los privilegios por
-- defecto de Supabase (por eso no basta con revocar de `public`). Se cierra y se
-- abre solo a quien debe poder llamarla. El Home solo es alcanzable con sesion,
-- asi que `anon` no la necesita; y como es INVOKER y compone el feed (que es
-- authenticated-only), darsela a `anon` no funcionaria igualmente.
revoke all on function flow.cliente_ranking_semanal(integer) from public, anon;
grant execute on function flow.cliente_ranking_semanal(integer) to authenticated, service_role;

notify pgrst, 'reload schema';

-- ============================================================================
-- VERIFICACION (ejecutar a mano despues de aplicar)
-- ============================================================================
-- 4.a Existe, es INVOKER y STABLE.
--     Esperado: 1 fila, INVOKER, s.
-- select p.proname,
--        case when p.prosecdef then 'DEFINER' else 'INVOKER' end as seguridad,
--        p.provolatile as volatilidad
--   from pg_proc p
--   join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'flow' and p.proname = 'cliente_ranking_semanal';
--
-- 4.b ACL real: anon fuera, authenticated dentro.
--     Esperado: anon = false, authenticated = true, service_role = true.
-- select r.rolname,
--        has_function_privilege(r.rolname,
--          'flow.cliente_ranking_semanal(integer)', 'execute') as puede
--   from pg_roles r
--  where r.rolname in ('anon', 'authenticated', 'service_role')
--  order by r.rolname;
--
-- 4.c Devuelve un array y ningun item viene sin `lugares_semana`.
--     Esperado: tipo = array, sin_lugares = 0.
-- select jsonb_typeof(flow.cliente_ranking_semanal()) as tipo,
--        count(*) filter (
--          where coalesce((it ->> 'lugares_semana')::integer, 0) <= 0
--        ) as sin_lugares,
--        count(*) as items
--   from jsonb_array_elements(flow.cliente_ranking_semanal()) as t(it);
--
-- 4.d El orden es decreciente por `lugares_semana`.
--     Esperado: 0 (ninguna fila rompe el orden).
-- select count(*) as desordenados
--   from (
--     select (it ->> 'lugares_semana')::integer as lugares,
--            lag((it ->> 'lugares_semana')::integer) over (order by ordinality) as previo
--       from jsonb_array_elements(flow.cliente_ranking_semanal())
--            with ordinality as t(it, ordinality)
--   ) x
--  where x.previo is not null and x.lugares > x.previo;
--
-- 4.e Ningun intruso: todo lo que devuelve tiene reservas en la ventana.
--     Esperado: 0.
-- select count(*) as intrusos
--   from jsonb_array_elements(flow.cliente_ranking_semanal()) as t(it)
--  where (it ->> 'id_local_servicio')::integer not in (
--          select a.id_local_servicio
--            from flow.agenda a
--           where a.id_estado in (1, 3)
--             and a.created_at is not null
--             and a.created_at >= date_trunc('week', now())
--        );
--
-- 4.f Contenido real a fecha 2026-10-09 (semana del 2026-10-05; cambiara con la
--     semana). Los items traen la forma anidada completa del feed mas
--     `lugares_semana`:
--       LS 21 "Lifting De Cejas"    (Salon 1 Cejas) -> 11 lugares, 3 reservas
--       LS 19 "Depilacion De Cejas" (Salon 1 Cejas) ->  3 lugares, 3 reservas
-- select it ->> 'id_local_servicio' as id_local_servicio,
--        it ->> 'lugares_semana'    as lugares_semana,
--        it -> 'servicio' ->> 'nombre' as servicio
--   from jsonb_array_elements(flow.cliente_ranking_semanal()) as t(it);
