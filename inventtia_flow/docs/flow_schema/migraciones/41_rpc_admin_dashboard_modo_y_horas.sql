-- ============================================================================
-- 41_rpc_admin_dashboard_modo_y_horas.sql
-- ============================================================================
-- QUE HACE
--   1. `flow.admin_dashboard_entidad(...)`  → totales + serie de reservas para
--      el dashboard de la vista de Gestión (punto 1 del plan).
--   2. `flow.admin_config_modo_gestion(...)` → activa/desactiva los modos
--      "Solo configurar turnos" y "No uso tramos" (punto 6).
--   3. `flow.admin_guardar_turno_auto(...)`  → crea/edita un turno en modo
--      simplificado: recurso oculto + tramo oculto + turno, en UNA transacción.
--   4. `flow.admin_guardar_turno(...)`       → recreate: + hora_inicio/hora_fin.
--   5. `flow.admin_listar_recursos(...)`     → recreate: expone hora_inicio/fin.
--
-- POR QUE `admin_guardar_turno` SE RECREA EN VEZ DE REEMPLAZARSE
--   Cambia la aridad (2 parámetros nuevos), y `create or replace` con otra
--   aridad deja DOS sobrecargas. PostgREST no resuelve funciones homónimas y el
--   fallo aparecería en toda la app (misma lección que la migración 18). Se hace
--   `drop function` + `create`. Sólo la llama `inventtia_flow`.
--
-- POR QUE `admin_guardar_turno_auto` EN UNA SOLA RPC
--   El modo simplificado necesita 3 escrituras coherentes (recurso oculto,
--   tramo oculto, turno + turno_tramo). Hechas desde el cliente serían 3 viajes
--   y un estado intermedio roto si falla el segundo. En una función plpgsql es
--   una transacción: o queda todo, o no queda nada.
--
-- POR QUE `solo_turnos` RECHAZA >1 RECURSO
--   Mover los turnos de varios recursos a uno solo dejaría filas de
--   `turno_tramo` apuntando a tramos de OTRO recurso (la validación de
--   pertenencia sólo vive en `admin_guardar_turno`). En vez de corromper datos,
--   se devuelve un error claro: con varios recursos, el modo correcto es
--   "No uso tramos".
--
-- REVERSIBILIDAD
--   drop function if exists flow.admin_dashboard_entidad(uuid, integer);
--   drop function if exists flow.admin_config_modo_gestion(uuid, integer, boolean, boolean);
--   drop function if exists flow.admin_guardar_turno_auto(uuid, integer, text, integer, boolean, jsonb, time, time, integer);
--   drop function if exists flow.admin_guardar_turno(uuid, integer, text, jsonb, integer, boolean, integer, jsonb, time, time);
--   (y recrear las versiones sin horas si se revierte la migración 40)
--
-- ORDEN: después de 40. No depende de 42.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Dashboard de la entidad
-- ---------------------------------------------------------------------------
-- Una sola petición: los 4 KPIs, la serie de 30 días (con los días sin reservas
-- en 0, para que el gráfico no mienta juntando barras) y el top 5 de servicios.
--
-- Permiso con el MISMO helper que el resto de RPC admin
-- (`admin_entidades_de_usuario` = propietario ∪ `entidad_admin`).
--
-- El rango se construye con generate_series y se une a la agregación de agenda:
-- así devuelve exactamente `dias` filas, siempre 30, haya o no reservas.
create or replace function flow.admin_dashboard_entidad(
  p_uuid_usuario uuid,
  p_id_entidad integer,
  p_dias integer default 30
)
returns jsonb
language plpgsql
stable
set search_path to 'flow', 'public'
as $function$
declare
  v_dias       integer := least(greatest(coalesce(p_dias, 30), 1), 180);
  v_desde      date;
  v_locales_t  integer; v_locales_a  integer;
  v_serv_t     integer; v_serv_a     integer;
  v_ls_t       integer; v_ls_a       integer;
  v_res_t      integer; v_res_res    integer; v_res_com integer; v_res_can integer;
  v_por_dia    jsonb;
  v_top        jsonb;
begin
  if not exists (
    select 1 from flow.admin_entidades_de_usuario(p_uuid_usuario) e
    where e.id_entidad = p_id_entidad
  ) then
    return jsonb_build_object('ok', false, 'error', 'entidad inexistente o sin permiso');
  end if;

  v_desde := current_date - (v_dias - 1);

  select count(*), count(*) filter (where coalesce(l.activo, false))
    into v_locales_t, v_locales_a
  from flow.app_dat_locales l
  where l.id_entidad = p_id_entidad;

  select count(*), count(*) filter (where coalesce(s.activo, false))
    into v_serv_t, v_serv_a
  from flow.app_dat_servicios s
  where s.id_entidad = p_id_entidad;

  select count(*), count(*) filter (where flow._ls_disponible(ls.id))
    into v_ls_t, v_ls_a
  from flow.local_servicio ls
  join flow.app_dat_locales l on l.id = ls.id_local
  where l.id_entidad = p_id_entidad;

  select count(*),
         count(*) filter (where a.id_estado = 1),
         count(*) filter (where a.id_estado = 3),
         count(*) filter (where a.id_estado = 2)
    into v_res_t, v_res_res, v_res_com, v_res_can
  from flow.agenda a
  join flow.local_servicio ls on ls.id = a.id_local_servicio
  join flow.app_dat_locales l  on l.id = ls.id_local
  where l.id_entidad = p_id_entidad;

  select coalesce(jsonb_agg(jsonb_build_object(
           'fecha',      to_char(d.dia, 'YYYY-MM-DD'),
           'total',      coalesce(c.total, 0),
           'reservadas', coalesce(c.reservadas, 0),
           'completadas', coalesce(c.completadas, 0),
           'canceladas', coalesce(c.canceladas, 0)
         ) order by d.dia), '[]'::jsonb)
    into v_por_dia
  from generate_series(v_desde, current_date, interval '1 day') as d(dia)
  left join (
    select (a.fecha_hora_reserva at time zone 'America/Havana')::date as dia,
           count(*)::integer                                         as total,
           count(*) filter (where a.id_estado = 1)::integer           as reservadas,
           count(*) filter (where a.id_estado = 3)::integer           as completadas,
           count(*) filter (where a.id_estado = 2)::integer           as canceladas
    from flow.agenda a
    join flow.local_servicio ls on ls.id = a.id_local_servicio
    join flow.app_dat_locales l  on l.id = ls.id_local
    where l.id_entidad = p_id_entidad
      and (a.fecha_hora_reserva at time zone 'America/Havana')::date between v_desde and current_date
    group by 1
  ) c on c.dia = d.dia;

  select coalesce(jsonb_agg(q.t order by q.orden), '[]'::jsonb)
    into v_top
  from (
    select
      jsonb_build_object(
        'id_local_servicio', a.id_local_servicio,
        'servicio',          s.nombre,
        'local',             l.nombre,
        'total',             count(*)::integer,
        'reservadas',        count(*) filter (where a.id_estado = 1)::integer,
        'canceladas',        count(*) filter (where a.id_estado = 2)::integer
      ) as t,
      row_number() over (order by count(*) desc, s.nombre, l.nombre) as orden
    from flow.agenda a
    join flow.local_servicio ls   on ls.id = a.id_local_servicio
    join flow.app_dat_locales l   on l.id = ls.id_local
    join flow.app_dat_servicios s on s.id = ls.id_servicio
    where l.id_entidad = p_id_entidad
    group by a.id_local_servicio, s.nombre, l.nombre
    order by count(*) desc, s.nombre, l.nombre
    limit 5
  ) q;

  return jsonb_build_object(
    'ok', true,
    'dias', v_dias,
    'locales', jsonb_build_object(
      'total', v_locales_t, 'activos', v_locales_a,
      'inactivos', v_locales_t - v_locales_a
    ),
    'servicios', jsonb_build_object(
      'total', v_serv_t, 'activos', v_serv_a,
      'inactivos', v_serv_t - v_serv_a
    ),
    'local_servicios', jsonb_build_object(
      'total', v_ls_t, 'activos', v_ls_a,
      'inactivos', v_ls_t - v_ls_a
    ),
    'reservas', jsonb_build_object(
      'total', v_res_t, 'reservado', v_res_res,
      'completado', v_res_com, 'cancelado', v_res_can
    ),
    'reservas_por_dia', v_por_dia,
    'top_servicios', v_top
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 2. Modo de gestión (punto 6 del plan)
-- ---------------------------------------------------------------------------
create or replace function flow.admin_config_modo_gestion(
  p_uuid_usuario uuid,
  p_id_local_servicio integer,
  p_solo_turnos boolean,
  p_sin_tramos boolean
)
returns jsonb
language plpgsql
set search_path to 'flow', 'public'
as $function$
declare
  v_solo          boolean := coalesce(p_solo_turnos, false);
  -- `solo_turnos` implica `sin_tramos` (el CHECK de la 40 lo exige igualmente).
  v_sin           boolean := coalesce(p_sin_tramos, false) or coalesce(p_solo_turnos, false);
  v_recursos      integer;
  v_recurso       integer;
  v_tramo         integer;
  v_creados_tramo integer := 0;
  v_creado_rec    boolean := false;
  v_turno         record;
begin
  if not flow._admin_puede_local_servicio(p_uuid_usuario, p_id_local_servicio) then
    return jsonb_build_object('ok', false, 'error', 'local_servicio inexistente o sin permiso');
  end if;

  select count(*) into v_recursos
  from flow.recurso r
  where r.id_local_servicio = p_id_local_servicio;

  -- Con varios recursos no se puede simplificar a "solo turnos" sin romper
  -- `turno_tramo`. El modo correcto para ese caso es "No uso tramos".
  if v_solo and v_recursos > 1 then
    return jsonb_build_object(
      'ok', false,
      'error', 'Este servicio tiene ' || v_recursos || ' recursos. '
               'Mantén "No uso tramos" o deja un único recurso para usar '
               '"Solo configurar turnos".'
    );
  end if;

  update flow.local_servicio
     set solo_turnos = v_solo,
         sin_tramos  = v_sin
   where id = p_id_local_servicio;

  -- En "solo turnos" siempre tiene que existir UN recurso que agrupe los turnos.
  if v_solo and v_recursos = 0 then
    insert into flow.recurso (id_local_servicio, nombre, capacidad, orden, activo)
    select p_id_local_servicio,
           'Cupo',
           greatest(coalesce(ls.cantidad_max_capacidad, 1), 1),
           0,
           true
    from flow.local_servicio ls
    where ls.id = p_id_local_servicio
    returning id into v_recurso;
    v_creado_rec := true;
  end if;

  -- Un tramo oculto por cada turno sin tramo (todo el local_servicio).
  -- Es idempotente: la segunda pasada no encuentra turnos sin tramo.
  if v_sin then
    for v_turno in
      select t.id, t.nombre, t.orden, t.id_recurso
      from flow.turno t
      join flow.recurso r on r.id = t.id_recurso
      where r.id_local_servicio = p_id_local_servicio
        and not exists (
          select 1 from flow.turno_tramo tt where tt.id_turno = t.id
        )
      order by t.orden, t.id
    loop
      insert into flow.tramo (id_recurso, nombre, capacidad, orden, activo)
      values (
        v_turno.id_recurso,
        coalesce(nullif(btrim(v_turno.nombre), ''), 'Cupo'),
        null,               -- null = hereda la capacidad del recurso
        coalesce(v_turno.orden, 0),
        true
      )
      returning id into v_tramo;

      insert into flow.turno_tramo (id_turno, id_tramo)
      values (v_turno.id, v_tramo)
      on conflict do nothing;

      v_creados_tramo := v_creados_tramo + 1;
    end loop;
  end if;

  return jsonb_build_object(
    'ok', true,
    'solo_turnos', v_solo,
    'sin_tramos', v_sin,
    'recurso_creado', v_creado_rec,
    'tramos_creados', v_creados_tramo
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 3. Guardar turno en modo simplificado (1 sola transacción)
-- ---------------------------------------------------------------------------
-- Garantiza: recurso (el único del local_servicio, o uno oculto nuevo) + un
-- tramo propio del turno + turno + enlace. Nunca exige al admin elegir tramos.
create or replace function flow.admin_guardar_turno_auto(
  p_uuid_usuario uuid,
  p_id_local_servicio integer,
  p_nombre text,
  p_orden integer default 0,
  p_activo boolean default true,
  p_precios jsonb default '{}'::jsonb,
  p_hora_inicio time default null,
  p_hora_fin time default null,
  p_id integer default null
)
returns jsonb
language plpgsql
set search_path to 'flow', 'public'
as $function$
declare
  v_recurso integer;
  v_turno   integer;
  v_tramo   integer;
begin
  if not flow._admin_puede_local_servicio(p_uuid_usuario, p_id_local_servicio) then
    return jsonb_build_object('ok', false, 'error', 'local_servicio inexistente o sin permiso');
  end if;

  if coalesce(btrim(p_nombre), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'el nombre del turno es obligatorio');
  end if;

  if p_id is null then
    -- Recurso destino: el único del local_servicio; si no hay, uno oculto.
    select r.id into v_recurso
    from flow.recurso r
    where r.id_local_servicio = p_id_local_servicio
    order by r.orden, r.id
    limit 1;

    if v_recurso is null then
      insert into flow.recurso (id_local_servicio, nombre, capacidad, orden, activo)
      select p_id_local_servicio,
             'Cupo',
             greatest(coalesce(ls.cantidad_max_capacidad, 1), 1),
             0,
             true
      from flow.local_servicio ls
      where ls.id = p_id_local_servicio
      returning id into v_recurso;
    end if;

    insert into flow.turno (id_recurso, nombre, orden, activo, precios, hora_inicio, hora_fin)
    values (
      v_recurso, btrim(p_nombre), coalesce(p_orden, 0), coalesce(p_activo, true),
      coalesce(p_precios, '{}'::jsonb), p_hora_inicio, p_hora_fin
    )
    returning id into v_turno;
  else
    select t.id_recurso into v_recurso
    from flow.turno t
    where t.id = p_id
      and flow._admin_puede_recurso(p_uuid_usuario, t.id_recurso);

    if v_recurso is null then
      return jsonb_build_object('ok', false, 'error', 'turno inexistente o sin permiso');
    end if;

    update flow.turno
       set nombre      = btrim(p_nombre),
           orden       = coalesce(p_orden, orden),
           activo      = coalesce(p_activo, activo),
           precios     = coalesce(p_precios, '{}'::jsonb),
           hora_inicio = p_hora_inicio,
           hora_fin    = p_hora_fin,
           updated_at  = now()
     where id = p_id
    returning id into v_turno;
  end if;

  -- Tramo propio del turno, sólo si aún no tiene ninguno.
  insert into flow.tramo (id_recurso, nombre, capacidad, orden, activo)
  select v_recurso, btrim(p_nombre), null, coalesce(p_orden, 0), true
  where not exists (
    select 1 from flow.turno_tramo tt where tt.id_turno = v_turno
  )
  returning id into v_tramo;

  if v_tramo is not null then
    insert into flow.turno_tramo (id_turno, id_tramo)
    values (v_turno, v_tramo)
    on conflict do nothing;
  end if;

  -- En modo simplificado los tramos son invisibles: se renombran con el turno
  -- para que la BD se lea sola si alguien la inspecciona a mano.
  if exists (
    select 1
    from flow.local_servicio ls
    join flow.recurso r      on r.id_local_servicio = ls.id
    join flow.turno_tramo tt on tt.id_turno = v_turno
    join flow.tramo tr       on tr.id = tt.id_tramo
    where ls.id = p_id_local_servicio and ls.sin_tramos
  ) then
    update flow.tramo tr
       set nombre = btrim(p_nombre), updated_at = now()
     where tr.id in (
       select tt.id_tramo from flow.turno_tramo tt where tt.id_turno = v_turno
     );
  end if;

  return jsonb_build_object(
    'ok', true,
    'id', v_turno,
    'id_recurso', v_recurso,
    'id_tramo', v_tramo
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 4. `admin_guardar_turno` con horas (recreate: cambia la aridad)
-- ---------------------------------------------------------------------------
drop function if exists flow.admin_guardar_turno(
  uuid, integer, text, jsonb, integer, boolean, integer, jsonb
);

create or replace function flow.admin_guardar_turno(
  p_uuid_usuario uuid,
  p_id_recurso integer,
  p_nombre text,
  p_tramos jsonb default '[]'::jsonb,
  p_orden integer default 0,
  p_activo boolean default true,
  p_id integer default null,
  p_precios jsonb default '{}'::jsonb,
  p_hora_inicio time default null,
  p_hora_fin time default null
)
returns jsonb
language plpgsql
set search_path to 'flow', 'public'
as $function$
declare
  v_id       integer;
  v_recurso  integer;
  v_bad      integer;
begin
  if coalesce(btrim(p_nombre), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'el nombre del turno es obligatorio');
  end if;

  if p_id is null then
    if not flow._admin_puede_recurso(p_uuid_usuario, p_id_recurso) then
      return jsonb_build_object('ok', false, 'error', 'recurso inexistente o sin permiso');
    end if;
    v_recurso := p_id_recurso;
    insert into flow.turno (id_recurso, nombre, orden, activo, precios, hora_inicio, hora_fin)
    values (p_id_recurso, btrim(p_nombre), coalesce(p_orden,0), coalesce(p_activo,true),
            coalesce(p_precios, '{}'::jsonb), p_hora_inicio, p_hora_fin)
    returning id into v_id;
  else
    select t.id_recurso into v_recurso
    from flow.turno t
    where t.id = p_id and flow._admin_puede_recurso(p_uuid_usuario, t.id_recurso);
    if v_recurso is null then
      return jsonb_build_object('ok', false, 'error', 'turno inexistente o sin permiso');
    end if;
    update flow.turno
       set nombre      = btrim(p_nombre),
           orden       = coalesce(p_orden, orden),
           activo      = coalesce(p_activo, activo),
           precios     = coalesce(p_precios, '{}'::jsonb),
           hora_inicio = p_hora_inicio,
           hora_fin    = p_hora_fin,
           updated_at  = now()
     where id = p_id
    returning id into v_id;
  end if;

  -- Validar que todos los tramos pedidos pertenezcan al recurso del turno.
  if p_tramos is not null and jsonb_array_length(p_tramos) > 0 then
    select count(*) into v_bad
    from jsonb_array_elements_text(p_tramos) e(tid)
    left join flow.tramo tr on tr.id = e.tid::int
    where tr.id is null or tr.id_recurso <> v_recurso;
    if v_bad > 0 then
      return jsonb_build_object('ok', false, 'error', 'algun tramo no pertenece al recurso del turno');
    end if;
  end if;

  -- Reemplazar el set de tramos del turno.
  delete from flow.turno_tramo where id_turno = v_id;
  if p_tramos is not null and jsonb_array_length(p_tramos) > 0 then
    insert into flow.turno_tramo (id_turno, id_tramo)
    select v_id, e.tid::int
    from jsonb_array_elements_text(p_tramos) e(tid)
    on conflict do nothing;
  end if;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$function$;

-- ---------------------------------------------------------------------------
-- 5. `admin_listar_recursos` exponiendo las horas del turno
-- ---------------------------------------------------------------------------
create or replace function flow.admin_listar_recursos(
  p_uuid_usuario uuid,
  p_id_local_servicio integer
)
returns jsonb
language plpgsql
stable
set search_path to 'flow', 'public'
as $function$
declare
  v_data jsonb;
begin
  if not flow._admin_puede_local_servicio(p_uuid_usuario, p_id_local_servicio) then
    return jsonb_build_object('ok', false, 'error', 'local_servicio inexistente o sin permiso');
  end if;

  select coalesce(jsonb_agg(rec order by rec_orden, rec_id), '[]'::jsonb)
    into v_data
  from (
    select
      r.orden as rec_orden,
      r.id    as rec_id,
      jsonb_build_object(
        'id',        r.id,
        'nombre',    r.nombre,
        'capacidad', r.capacidad,
        'orden',     r.orden,
        'activo',    r.activo,
        'tramos', (
          select coalesce(jsonb_agg(jsonb_build_object(
                    'id',        tr.id,
                    'nombre',    tr.nombre,
                    'capacidad', tr.capacidad,
                    'tipo_trayecto', tr.tipo_trayecto,
                    'orden',     tr.orden,
                    'activo',    tr.activo
                  ) order by tr.orden, tr.id), '[]'::jsonb)
          from flow.tramo tr where tr.id_recurso = r.id
        ),
        'turnos', (
          select coalesce(jsonb_agg(jsonb_build_object(
                    'id',      t.id,
                    'nombre',  t.nombre,
                    'orden',   t.orden,
                    'activo',  t.activo,
                    'precios', t.precios,
                    -- Horas opcionales del turno (punto 7). `to_char` con
                    -- 'HH24:MI' para que viajen como "09:00" y no como
                    -- "09:00:00", que es lo que espera el selector de hora.
                    'hora_inicio', case when t.hora_inicio is null then null
                                        else to_char(t.hora_inicio, 'HH24:MI') end,
                    'hora_fin',    case when t.hora_fin is null then null
                                        else to_char(t.hora_fin, 'HH24:MI') end,
                    'tramos', (
                      select coalesce(jsonb_agg(tt.id_tramo order by tt.id_tramo), '[]'::jsonb)
                      from flow.turno_tramo tt where tt.id_turno = t.id
                    )
                  ) order by t.orden, t.id), '[]'::jsonb)
          from flow.turno t where t.id_recurso = r.id
        )
      ) as rec
    from flow.recurso r
    where r.id_local_servicio = p_id_local_servicio
  ) s;

  return jsonb_build_object('ok', true, 'data', v_data);
end;
$function$;

-- ---------------------------------------------------------------------------
-- 6. Verificación posterior (ejecutar a mano)
-- ---------------------------------------------------------------------------
-- 6.a El dashboard responde y trae 30 días.
-- select flow.admin_dashboard_entidad('<uuid-admin>', <id_entidad>) -> 'reservas';
-- select jsonb_array_length(
--          flow.admin_dashboard_entidad('<uuid-admin>', <id_entidad>) -> 'reservas_por_dia'
--        );   -- esperado: 30
--
-- 6.b Las horas viajan como HH:MM.
-- select flow.admin_listar_recursos('<uuid-admin>', <id_local_servicio>) -> 'data' -> 0 -> 'turnos';
--
-- 6.c No quedan sobrecargas de admin_guardar_turno: esperado 1 fila.
-- select pg_get_function_identity_arguments(p.oid)
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'flow' and p.proname = 'admin_guardar_turno';
-- ============================================================================