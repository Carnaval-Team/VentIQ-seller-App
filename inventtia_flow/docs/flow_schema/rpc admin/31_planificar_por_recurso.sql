-- ============================================================================
-- PLANIFICACION POR RECURSO
--
-- Cambio de modelo: la CAPACIDAD ya no se declara en la configuracion de
-- recursos/tramos (esos solo definen la ESTRUCTURA: nombres y que tramos
-- consume cada turno). La capacidad se fija al PLANIFICAR, por RECURSO y por
-- dia. Todos los tramos activos de un recurso reciben la misma capacidad ese
-- dia (plan_tramo.cantidad).
--
-- Config recurrente (flow.plan_config.config) para servicios CON recursos:
--   { "por_recurso": {
--       "<id_recurso>": { "default": 15, "por_dia": { "1": 20, "7": 0 } },
--       ...
--   } }
--   (dia ISO 1=lun..7=dom; valor 0 o ausente-y-default-0 = ese dia sin cupo)
-- Servicios SIN recursos siguen usando { "default": N, "por_dia": {...} }.
--
-- Piezas:
--   1) _upsert_plan_tramos_recurso : escribe plan_tramo de un recurso/dia.
--   2) admin_planificar_dia        : planifica UN dia (day-click del calendario).
--   3) admin_generar_plan_mensual  : reescrito para leer por_recurso.
--   4) admin_get_plan_dias         : resumen por dia para el calendario admin.
--
-- Aplicar manualmente (la conexion MCP es read-only).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Helper: upsert de plan_tramo para todos los tramos activos de un recurso
--    en una fecha, con capacidad p_cap. p_cap <= 0 -> "dia cerrado": borra los
--    plan_tramo del dia sin reservas y deja cantidad = agendados en los que ya
--    tienen reservas (no se puede bajar por debajo de lo agendado).
-- ----------------------------------------------------------------------------
create or replace function flow._upsert_plan_tramos_recurso(
  p_id_recurso integer,
  p_fecha      date,
  p_cap        integer
)
returns integer   -- nº de tramos afectados
language plpgsql
volatile
set search_path = flow, public
as $$
declare
  v_fecha_ts timestamptz;
  v_n        integer := 0;
begin
  v_fecha_ts := make_timestamp(
    extract(year  from p_fecha)::int,
    extract(month from p_fecha)::int,
    extract(day   from p_fecha)::int, 12, 0, 0
  ) at time zone 'America/Havana';

  if coalesce(p_cap, 0) <= 0 then
    update flow.plan_tramo pt
       set cantidad = pt.agendados
    from flow.tramo tr
    where tr.id_recurso = p_id_recurso and tr.activo
      and pt.id_tramo = tr.id
      and (pt.fecha at time zone 'America/Havana')::date = p_fecha
      and pt.agendados > 0;

    delete from flow.plan_tramo pt
    using flow.tramo tr
    where tr.id_recurso = p_id_recurso and tr.activo
      and pt.id_tramo = tr.id
      and (pt.fecha at time zone 'America/Havana')::date = p_fecha
      and pt.agendados = 0;
    return 0;
  end if;

  with tramos as (
    select tr.id as id_tramo
    from flow.tramo tr
    where tr.id_recurso = p_id_recurso and tr.activo
  ),
  ins as (
    insert into flow.plan_tramo (id_tramo, fecha, cantidad, agendados)
    select t.id_tramo, v_fecha_ts, p_cap, 0
    from tramos t
    on conflict (id_tramo, fecha) do update
      set cantidad = greatest(excluded.cantidad, flow.plan_tramo.agendados)
    returning 1
  )
  select count(*) into v_n from ins;

  return v_n;
end;
$$;

grant execute on function flow._upsert_plan_tramos_recurso(integer, date, integer) to authenticated;

-- ----------------------------------------------------------------------------
-- 2) admin_planificar_dia: planifica UN dia concreto.
--    CON recursos : p_caps = { "<id_recurso>": cantidad, ... }.
--    SIN recursos : usa p_cantidad (upsert de plan_servicios del dia).
-- ----------------------------------------------------------------------------
create or replace function flow.admin_planificar_dia(
  p_uuid_usuario      uuid,
  p_id_local_servicio integer,
  p_fecha             date,
  p_caps              jsonb   default null,
  p_cantidad          integer default null
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = flow, public
as $$
declare
  v_tiene_rec  boolean;
  v_fecha_ts   timestamptz;
  v_existe_id  bigint;
  v_id_rec     integer;
  v_cap        integer;
  v_afectados  integer := 0;
begin
  if p_uuid_usuario is null or p_id_local_servicio is null or p_fecha is null then
    return jsonb_build_object('ok', false, 'error', 'parametros obligatorios faltantes');
  end if;

  if not flow._admin_puede_local_servicio(p_uuid_usuario, p_id_local_servicio) then
    return jsonb_build_object('ok', false, 'error', 'local_servicio inexistente o sin permiso');
  end if;

  v_tiene_rec := flow._ls_tiene_recursos(p_id_local_servicio);

  if v_tiene_rec then
    if p_caps is null or jsonb_typeof(p_caps) <> 'object' then
      return jsonb_build_object('ok', false, 'error', 'faltan las capacidades por recurso');
    end if;

    for v_id_rec, v_cap in
      select key::int, coalesce(value::text::int, 0)
      from jsonb_each(p_caps)
    loop
      if not exists (
        select 1 from flow.recurso r
        where r.id = v_id_rec and r.id_local_servicio = p_id_local_servicio and r.activo
      ) then
        continue;
      end if;
      v_afectados := v_afectados + flow._upsert_plan_tramos_recurso(v_id_rec, p_fecha, v_cap);
    end loop;

    return jsonb_build_object('ok', true, 'con_recursos', true, 'tramos', v_afectados);
  end if;

  -- ── Sin recursos: plan_servicios (upsert por dia) ──
  if coalesce(p_cantidad, 0) <= 0 then
    return jsonb_build_object('ok', false, 'error', 'la cantidad debe ser mayor a 0');
  end if;

  v_fecha_ts := make_timestamp(
    extract(year  from p_fecha)::int,
    extract(month from p_fecha)::int,
    extract(day   from p_fecha)::int, 12, 0, 0
  ) at time zone 'America/Havana';

  select ps.id into v_existe_id
  from flow.plan_servicios ps
  where ps.id_local_servicio = p_id_local_servicio
    and (ps.fecha at time zone 'America/Havana')::date = p_fecha
  order by ps.id
  limit 1;

  if v_existe_id is null then
    insert into flow.plan_servicios (id_local_servicio, fecha, cantidad, agendados)
    values (p_id_local_servicio, v_fecha_ts, p_cantidad, 0);
  else
    update flow.plan_servicios ps
       set cantidad = greatest(p_cantidad, ps.agendados)
     where ps.id = v_existe_id;
  end if;

  return jsonb_build_object('ok', true, 'con_recursos', false, 'cantidad', p_cantidad);
exception
  when others then
    return jsonb_build_object('ok', false, 'error', sqlerrm, 'sqlstate', sqlstate);
end;
$$;

grant execute on function flow.admin_planificar_dia(uuid, integer, date, jsonb, integer) to authenticated;

-- ----------------------------------------------------------------------------
-- 3) admin_generar_plan_mensual: reescrito. Camino recursos lee por_recurso.
-- ----------------------------------------------------------------------------
create or replace function flow.admin_generar_plan_mensual(
  p_uuid_usuario      uuid,
  p_id_local_servicio integer,
  p_anio              integer,
  p_mes               integer
)
returns jsonb
language plpgsql
set search_path = flow, public
as $$
declare
  v_config        jsonb;
  v_por_recurso   jsonb;
  v_default       integer;
  v_por_dia       jsonb;
  v_dia           date;
  v_primer_dia    date;
  v_ultimo_dia    date;
  v_isodow        integer;
  v_cap           integer;
  v_fecha_ts      timestamptz;
  v_existe_id     bigint;
  v_creados       integer := 0;
  v_actualizados  integer := 0;
  v_sin_cupo      integer := 0;
  v_tiene_rec     boolean;
  v_rec           record;
  v_rcfg          jsonb;
  v_rdef          integer;
  v_rpordia       jsonb;
begin
  if p_uuid_usuario is null or p_id_local_servicio is null
     or p_anio is null or p_mes is null then
    return jsonb_build_object('ok', false, 'error', 'parametros obligatorios faltantes');
  end if;
  if p_mes < 1 or p_mes > 12 then
    return jsonb_build_object('ok', false, 'error', 'mes invalido');
  end if;

  if not flow._admin_puede_local_servicio(p_uuid_usuario, p_id_local_servicio) then
    return jsonb_build_object('ok', false, 'error', 'local_servicio inexistente o sin permiso');
  end if;

  select pc.config into v_config
  from flow.plan_config pc
  where pc.id_local_servicio = p_id_local_servicio
    and pc.activo = true;

  if v_config is null then
    return jsonb_build_object('ok', false, 'error', 'no hay configuracion activa para este servicio');
  end if;

  v_tiene_rec   := flow._ls_tiene_recursos(p_id_local_servicio);
  v_primer_dia  := make_date(p_anio, p_mes, 1);
  v_ultimo_dia  := (v_primer_dia + interval '1 month - 1 day')::date;

  if v_tiene_rec then
    -- ── Camino recursos: config { por_recurso: { <id>: {default, por_dia} } } ──
    v_por_recurso := coalesce(v_config -> 'por_recurso', '{}'::jsonb);

    for v_rec in
      select r.id from flow.recurso r
      where r.id_local_servicio = p_id_local_servicio and r.activo
    loop
      v_rcfg    := coalesce(v_por_recurso -> v_rec.id::text, '{}'::jsonb);
      v_rdef    := coalesce((v_rcfg ->> 'default')::int, 0);
      v_rpordia := coalesce(v_rcfg -> 'por_dia', '{}'::jsonb);

      v_dia := v_primer_dia;
      while v_dia <= v_ultimo_dia loop
        v_isodow := extract(isodow from v_dia)::int;
        if v_rpordia ? v_isodow::text then
          v_cap := coalesce((v_rpordia ->> v_isodow::text)::int, 0);
        else
          v_cap := v_rdef;
        end if;

        if coalesce(v_cap, 0) <= 0 then
          v_sin_cupo := v_sin_cupo + 1;
        else
          v_creados := v_creados + flow._upsert_plan_tramos_recurso(v_rec.id, v_dia, v_cap);
        end if;

        v_dia := v_dia + 1;
      end loop;
    end loop;

    return jsonb_build_object(
      'ok', true, 'id_local_servicio', p_id_local_servicio,
      'anio', p_anio, 'mes', p_mes, 'con_recursos', true,
      'creados', v_creados, 'actualizados', 0, 'omitidos', 0,
      'dias_sin_cupo', v_sin_cupo
    );
  end if;

  -- ── Camino legacy: plan_servicios { default, por_dia } ──
  v_default := coalesce((v_config ->> 'default')::int, 0);
  v_por_dia := coalesce(v_config -> 'por_dia', '{}'::jsonb);

  v_dia := v_primer_dia;
  while v_dia <= v_ultimo_dia loop
    v_isodow := extract(isodow from v_dia)::int;
    if v_por_dia ? v_isodow::text then
      v_cap := coalesce((v_por_dia ->> v_isodow::text)::int, 0);
    else
      v_cap := v_default;
    end if;

    if coalesce(v_cap, 0) <= 0 then
      v_sin_cupo := v_sin_cupo + 1;
    else
      v_fecha_ts := make_timestamp(p_anio, p_mes, extract(day from v_dia)::int, 12, 0, 0)
                      at time zone 'America/Havana';

      select ps.id into v_existe_id
      from flow.plan_servicios ps
      where ps.id_local_servicio = p_id_local_servicio
        and (ps.fecha at time zone 'America/Havana')::date = v_dia
      order by ps.id
      limit 1;

      if v_existe_id is null then
        insert into flow.plan_servicios (id_local_servicio, fecha, cantidad, agendados)
        values (p_id_local_servicio, v_fecha_ts, v_cap, 0);
        v_creados := v_creados + 1;
      else
        update flow.plan_servicios ps
           set cantidad = greatest(v_cap, ps.agendados)
         where ps.id = v_existe_id
           and ps.cantidad <> greatest(v_cap, ps.agendados);
        v_actualizados := v_actualizados + 1;
      end if;
    end if;

    v_dia := v_dia + 1;
  end loop;

  return jsonb_build_object(
    'ok', true, 'id_local_servicio', p_id_local_servicio,
    'anio', p_anio, 'mes', p_mes, 'con_recursos', false,
    'creados', v_creados, 'actualizados', v_actualizados, 'omitidos', 0,
    'dias_sin_cupo', v_sin_cupo
  );
end;
$$;

grant execute on function flow.admin_generar_plan_mensual(uuid, integer, integer, integer) to authenticated;

-- ----------------------------------------------------------------------------
-- 4) admin_get_plan_dias: resumen por dia para pintar el calendario del admin,
--    unificado para servicios con y sin recursos.
--      Sin recursos -> suma de plan_servicios por dia.
--      Con recursos -> suma de plan_tramo por dia + detalle por recurso.
--    Devuelve { ok, con_recursos, dias: [{ fecha, cantidad, agendados,
--               disponibles, recursos:[{id_recurso,recurso,cantidad,agendados}] }] }
-- ----------------------------------------------------------------------------
create or replace function flow.admin_get_plan_dias(
  p_uuid_usuario      uuid,
  p_id_local_servicio integer,
  p_desde             date default null,
  p_hasta             date default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = flow, public
as $$
declare
  v_tiene_rec boolean;
  v_desde     date;
  v_hasta     date;
  v_data      jsonb;
begin
  if not flow._admin_puede_local_servicio(p_uuid_usuario, p_id_local_servicio) then
    return jsonb_build_object('ok', false, 'error', 'local_servicio inexistente o sin permiso');
  end if;

  v_desde := coalesce(p_desde, (current_timestamp at time zone 'America/Havana')::date - 31);
  v_hasta := coalesce(p_hasta, (current_timestamp at time zone 'America/Havana')::date + 120);
  v_tiene_rec := flow._ls_tiene_recursos(p_id_local_servicio);

  if not v_tiene_rec then
    with por_dia as (
      select (ps.fecha at time zone 'America/Havana')::date as dia,
             sum(ps.cantidad)  as cantidad,
             sum(ps.agendados) as agendados
      from flow.plan_servicios ps
      where ps.id_local_servicio = p_id_local_servicio
        and ps.cantidad is not null
        and (ps.fecha at time zone 'America/Havana')::date between v_desde and v_hasta
      group by (ps.fecha at time zone 'America/Havana')::date
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'fecha',       to_char(pd.dia, 'YYYY-MM-DD'),
             'cantidad',    pd.cantidad,
             'agendados',   pd.agendados,
             'disponibles', pd.cantidad - pd.agendados,
             'recursos',    '[]'::jsonb
           ) order by pd.dia), '[]'::jsonb)
      into v_data
    from por_dia pd;

    return jsonb_build_object('ok', true, 'con_recursos', false, 'dias', v_data);
  end if;

  -- Con recursos: la "capacidad del recurso ese dia" es el MIN de sus tramos
  -- (todos deberian ser iguales, pero min es lo correcto para disponibilidad);
  -- agendados del recurso = MAX de agendados de sus tramos.
  with por_recurso_dia as (
    select
      (pt.fecha at time zone 'America/Havana')::date as dia,
      r.id     as id_recurso,
      r.nombre as recurso,
      r.orden  as r_orden,
      min(pt.cantidad)  as cantidad,
      max(pt.agendados) as agendados
    from flow.recurso r
    join flow.tramo tr      on tr.id_recurso = r.id and tr.activo
    join flow.plan_tramo pt on pt.id_tramo = tr.id
    where r.id_local_servicio = p_id_local_servicio and r.activo
      and (pt.fecha at time zone 'America/Havana')::date between v_desde and v_hasta
    group by dia, r.id, r.nombre, r.orden
  ),
  por_dia as (
    select
      dia,
      sum(cantidad)  as cantidad,
      sum(agendados) as agendados,
      jsonb_agg(jsonb_build_object(
        'id_recurso', id_recurso,
        'recurso',    recurso,
        'cantidad',   cantidad,
        'agendados',  agendados
      ) order by r_orden, id_recurso) as recursos
    from por_recurso_dia
    group by dia
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'fecha',       to_char(pd.dia, 'YYYY-MM-DD'),
           'cantidad',    pd.cantidad,
           'agendados',   pd.agendados,
           'disponibles', pd.cantidad - pd.agendados,
           'recursos',    pd.recursos
         ) order by pd.dia), '[]'::jsonb)
    into v_data
  from por_dia pd;

  return jsonb_build_object('ok', true, 'con_recursos', true, 'dias', v_data);
end;
$$;

grant execute on function flow.admin_get_plan_dias(uuid, integer, date, date) to authenticated;

-- Uso:
--   select flow.admin_planificar_dia('uuid', 5, '2026-08-01', '{"1":15,"2":10}'::jsonb);
--   select flow.admin_planificar_dia('uuid', 3, '2026-08-01', null, 20);  -- sin recursos
--   select flow.admin_generar_plan_mensual('uuid', 5, 2026, 8);
--   select flow.admin_get_plan_dias('uuid', 5, '2026-08-01', '2026-08-31');
