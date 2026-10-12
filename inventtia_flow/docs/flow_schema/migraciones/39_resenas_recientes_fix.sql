-- ============================================================================
-- 39 - Arreglo: `resenas_recientes` no encontraba el local (`ls.local`)
-- ============================================================================
-- QUE HACE
--   1) Re-despliega `flow.resenas_recientes` uniendo el local por la columna que
--      existe de verdad: `flow.local_servicio.id_local` (antes decia `ls.local`).
--   2) Comprueba antes de tocar nada que las tablas y columnas de las que
--      depende estan donde toca, para no dejar el esquema a medias.
--
-- POR QUE
--   `flow.local_servicio` tiene `id_local`, no `local`. El RPC iba con
--   `join flow.app_dat_locales l on l.id = ls.local`, asi que **cualquier**
--   llamada moria con:
--       {"code":"42703","message":"column ls.local does not exist"}
--   y el Home se quedaba sin el feed de resenas (el cliente lo captura y pinta la
--   seccion vacia, por eso no habia mas sintoma que "no salen resenas").
--
--   Nadie lo detecto al crear la migracion 26 porque en PostgreSQL el cuerpo de
--   una funcion `plpgsql` **no se valida al crearla**: se compila la primera vez
--   que se ejecuta. Un `create or replace` "correcto" puede dejar una funcion
--   rota esperando a su primera llamada.
--
--   Auditado el resto del esquema con
--     select proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--      where n.nspname in ('flow','public') and p.prosrc ~ '\mls\.local\M';
--   y era la UNICA funcion con ese error: el resto usa `ls.id_local`.
--
-- ALCANCE
--   Una sola funcion de `flow`. No se toca ninguna tabla, ni RLS, ni indices, ni
--   la forma de la respuesta (`to_jsonb(t)` sigue devolviendo las mismas claves:
--   id, puntuacion, comentario, created_at, id_local_servicio, servicio, local,
--   autor), asi que el cliente (`ResenaService.getRecientes`) no cambia.
--   `create or replace` conserva la ACL y la firma `(p_limit integer)`: PostgREST
--   no ve overloading nuevo.
--
-- ROLLBACK
--   Volver a desplegar la definicion anterior (esta en el historial de
--   `pg_get_functiondef`), que es la misma con `ls.local`. No hace falta: el
--   error era total (la funcion no devolvia nada nunca), asi que no hay
--   comportamiento bueno que recuperar.
--
-- IDEMPOTENTE
--   `create or replace function` con la misma firma y los mismos `grant`: se
--   puede reejecutar las veces que haga falta.
--
-- REQUISITO PREVIO
--   Tablas `flow.resena`, `flow.local_servicio`, `flow.app_dat_servicios`,
--   `flow.app_dat_locales` y `flow.perfil` (migraciones 26 y anteriores). Este
--   archivo no crea nada de eso.
--
--   Aplicar en LOS DOS proyectos Supabase (debug `qhprswhhfasrikhawjoz` y
--   release `vsieeihstajlrdvpuooh`); si no, el feed de resenas saldra en uno y
--   no en el otro.
--
--   OJO: la migracion 26 ya viene corregida en el repo, pero en una base donde
--   se aplico antes hay que ejecutar ESTE archivo (26 no se puede "re-aplicar"
--   sin volver a crear todas sus funciones; es inofensivo, pero innecesario).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- COMPROBACION PREVIA
-- ---------------------------------------------------------------------------
do $check$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'flow'
       and table_name = 'local_servicio'
       and column_name = 'id_local'
  ) then
    raise exception 'Falta flow.local_servicio.id_local: revisa el esquema antes de aplicar 39';
  end if;

  if not exists (
    select 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'flow'
       and p.proname = 'resenas_recientes'
  ) then
    raise exception 'Falta flow.resenas_recientes: aplica antes 26_resenas.sql';
  end if;

  -- OJO: nada de `group by true`; en GROUP BY un booleano constante es un error
  -- (42601: non-integer constant in GROUP BY). Se cuenta y se compara.
  if (
    select count(*) from information_schema.tables
     where table_schema = 'flow'
       and table_name in ('resena', 'app_dat_servicios', 'app_dat_locales', 'perfil')
  ) <> 4 then
    raise exception 'Faltan tablas de las que depende resenas_recientes (26_resenas.sql)';
  end if;
end
$check$;

-- ---------------------------------------------------------------------------
-- 1. resenas_recientes  (el unico cambio: `ls.local` -> `ls.id_local`)
-- ---------------------------------------------------------------------------
create or replace function flow.resenas_recientes(p_limit integer default 5)
returns jsonb
language plpgsql
stable
security definer
set search_path = flow, public
as $function$
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
    join flow.app_dat_locales l on l.id = ls.id_local
    left join flow.perfil p on p.uuid_usuario = r.uuid_usuario
    where r.comentario is not null
    order by r.created_at desc
    limit greatest(1, least(coalesce(p_limit, 5), 20))
  ) t;

  return jsonb_build_object('ok', true, 'data', v_result);
end;
$function$;

-- La ACL no deberia cambiar (`create or replace` la conserva), pero se repite
-- para que en una base donde la funcion se creara de cero quede igual.
revoke all on function flow.resenas_recientes(integer) from public, anon;
grant execute on function flow.resenas_recientes(integer)
  to authenticated, service_role;

-- ============================================================================
-- VERIFICACION (ejecutar a mano despues de aplicar)
-- ============================================================================
-- V.1 Ya no queda ninguna funcion con el typo. Esperado: 0 filas. La regex es
--     ancha a proposito (`ls . "local"` tambien cuenta), no solo `ls.local`.
-- select n.nspname, p.proname
--   from pg_proc p
--   join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname in ('flow','public') and p.prosrc ~ 'ls\s*\.\s*"?local"?';
--
-- V.2 La funcion conserva firma unica `(p_limit integer)`. Esperado: 1 fila.
-- select p.proname, pg_get_function_identity_arguments(p.oid) as args
--   from pg_proc p
--   join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'flow' and p.proname = 'resenas_recientes';
--
-- V.3 La consulta interna devuelve filas (esta es la que fallaba). Esperado: las
--     resenas con comentario, con `servicio` y `local` rellenos.
-- select r.id, r.puntuacion, r.comentario, s.nombre as servicio, l.nombre as local
--   from flow.resena r
--   join flow.local_servicio ls on ls.id = r.id_local_servicio
--   join flow.app_dat_servicios s on s.id = ls.id_servicio
--   join flow.app_dat_locales l on l.id = ls.id_local
--  where r.comentario is not null
--  order by r.created_at desc
--  limit 6;
--
-- V.4 El RPC responde con datos. En el SQL Editor no hay JWT, asi que hay que
--     fingir el rol dentro de una transaccion (y deshacerla: no escribe nada).
-- begin;
--   select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
--   select jsonb_pretty(flow.resenas_recientes(6));
-- rollback;
--     Esperado: {"ok": true, "data": [ {... "servicio": "...", "local": "...",
--     "autor": "..."} ]} y NO un 42703. Sin el `set_config` sale
--     {"ok": false, "error": "Sesion no valida"}, que es lo correcto: la funcion
--     solo la puede llamar un usuario con sesion.
--
--     Desde la app no hace falta nada mas: el Home ya llama a este RPC en
--     `ResenaService.getRecientes`.
