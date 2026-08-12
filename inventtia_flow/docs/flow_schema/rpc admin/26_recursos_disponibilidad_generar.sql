-- ============================================================================
-- RECURSOS - Fase 2 (parte A): disponibilidad por turno + generacion plan_tramo
--
-- Reemplaza (extiende) dos RPCs para que sean "recurso-aware" sin romper el
-- camino legacy (servicios SIN recursos siguen usando plan_servicios):
--   1) cliente_obtener_disponibilidad -> si el LS tiene recursos activos,
--      cada dia incluye 'turnos' con su disponibilidad (min sobre tramos).
--   2) admin_generar_plan_mensual     -> si el LS tiene recursos activos,
--      genera flow.plan_tramo por (tramo, dia) en vez de plan_servicios.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Helper: ¿el local_servicio tiene al menos un recurso activo?
-- ----------------------------------------------------------------------------
create or replace function flow._ls_tiene_recursos(p_id_local_servicio integer)
returns boolean
language sql stable set search_path = flow, public as $$
  select exists (
    select 1 from flow.recurso r
    where r.id_local_servicio = p_id_local_servicio and r.activo
  );
$$;

-- ============================================================================
-- 1) DISPONIBILIDAD (cliente). Compatible con DisponibilidadDia.fromJson:
--    mantiene { fecha, cantidad, agendados, disponibles } y AÑADE, cuando hay
--    recursos, 'turnos': [{ id_recurso, recurso, id_turno, turno, disponibles }].
--    Un turno esta disponible un dia solo si TODOS sus tramos tienen plan_tramo
--    ese dia; su disponibilidad = min(cantidad - agendados) sobre esos tramos.
-- ============================================================================
create or replace function flow.cliente_obtener_disponibilidad(
  p_id_local_servicio integer,
  p_desde date default null,
  p_hasta date default null
)
returns jsonb
language plpgsql stable set search_path = flow, public
as $$
declare
  v_desde date;
  v_hasta date;
  v_data  jsonb;
begin
  v_desde := coalesce(p_desde, (current_timestamp at time zone 'America/Havana')::date);
  v_hasta := coalesce(p_hasta, (current_timestamp at time zone 'America/Havana')::date + 90);

  if not flow._ls_tiene_recursos(p_id_local_servicio) then
    -- ── Camino legacy: cupo por dia desde plan_servicios (formato original) ──
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
             'disponibles', pd.cantidad - pd.agendados
           ) order by pd.dia), '[]'::jsonb)
      into v_data
    from por_dia pd
    where pd.cantidad - pd.agendados > 0;

    return v_data;
  end if;

  -- ── Camino recursos: disponibilidad por turno y por dia ──
  with turnos_dia as (
    select
      (pt.fecha at time zone 'America/Havana')::date as dia,
      r.id     as id_recurso,
      r.nombre as recurso,
      r.orden  as r_orden,
      t.id     as id_turno,
      t.nombre as turno,
      t.orden  as t_orden,
      min(pt.cantidad - pt.agendados)                    as disp,
      count(*)                                           as n_plan,
      (select count(*) from flow.turno_tramo tt2
         where tt2.id_turno = t.id)                      as n_turno
    from flow.turno t
    join flow.recurso r      on r.id = t.id_recurso and r.activo
    join flow.turno_tramo tt on tt.id_turno = t.id
    join flow.tramo tr       on tr.id = tt.id_tramo and tr.activo
    join flow.plan_tramo pt  on pt.id_tramo = tr.id
    where r.id_local_servicio = p_id_local_servicio
      and t.activo
      and (pt.fecha at time zone 'America/Havana')::date between v_desde and v_hasta
    group by dia, r.id, r.nombre, r.orden, t.id, t.nombre, t.orden
  ),
  turnos_ok as (
    -- El turno solo cuenta si TODOS sus tramos tienen cupo ese dia y disp > 0.
    select * from turnos_dia
    where n_plan = n_turno and disp > 0
  ),
  por_dia as (
    select
      dia,
      sum(disp) as disponibles,
      jsonb_agg(jsonb_build_object(
        'id_recurso',  id_recurso,
        'recurso',     recurso,
        'id_turno',    id_turno,
        'turno',       turno,
        'disponibles', disp
      ) order by r_orden, id_recurso, t_orden, id_turno) as turnos
    from turnos_ok
    group by dia
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'fecha',       to_char(pd.dia, 'YYYY-MM-DD'),
           'cantidad',    pd.disponibles,   -- agregado (no hay un unico "total")
           'agendados',   0,
           'disponibles', pd.disponibles,
           'turnos',      pd.turnos
         ) order by pd.dia), '[]'::jsonb)
    into v_data
  from por_dia pd
  where pd.disponibles > 0;

  return v_data;
end;
$$;

grant execute on function flow.cliente_obtener_disponibilidad(integer, date, date) to authenticated, anon;

-- ============================================================================
-- 2) GENERAR PLAN MENSUAL. Si el LS tiene recursos activos, genera plan_tramo
--    por (tramo activo, dia abierto). "Dia abierto" = capacidad de plan_config
--    (por_dia[isodow] ?? default) > 0; la CANTIDAD del tramo viene de su propia
--    capacidad (tramo.capacidad ?? recurso.capacidad), NO de plan_config.
--    Conflicto (ya existe plan_tramo ese dia) -> greatest(nueva, agendados).
--    Si NO tiene recursos -> camino legacy (plan_servicios), identico a antes.
-- ============================================================================
create or replace function flow.admin_generar_plan_mensual(
  p_uuid_usuario      uuid,
  p_id_local_servicio integer,
  p_anio              integer,
  p_mes               integer
)
returns jsonb
language plpgsql volatile security invoker set search_path = flow, public
as $$
declare
  v_config        jsonb;
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
  v_omitidos      integer := 0;
  v_sin_cupo      integer := 0;
  v_tiene_rec     boolean;
begin
  if p_uuid_usuario is null or p_id_local_servicio is null
     or p_anio is null or p_mes is null then
    return jsonb_build_object('ok', false, 'error', 'parametros obligatorios faltantes');
  end if;
  if p_mes < 1 or p_mes > 12 then
    return jsonb_build_object('ok', false, 'error', 'mes invalido');
  end if;

  if not exists (
    select 1
    from flow.local_servicio  ls
    join flow.app_dat_locales l on l.id = ls.id_local
    where ls.id = p_id_local_servicio
      and l.id_entidad in (
        select id_entidad from flow.admin_entidades_de_usuario(p_uuid_usuario)
      )
  ) then
    return jsonb_build_object('ok', false, 'error', 'local_servicio inexistente o sin permiso');
  end if;

  select pc.config into v_config
  from flow.plan_config pc
  where pc.id_local_servicio = p_id_local_servicio
    and pc.activo = true;

  if v_config is null then
    return jsonb_build_object('ok', false, 'error', 'no hay configuracion activa para este servicio');
  end if;

  v_default := coalesce((v_config ->> 'default')::int, 0);
  v_por_dia := coalesce(v_config -> 'por_dia', '{}'::jsonb);
  v_tiene_rec := flow._ls_tiene_recursos(p_id_local_servicio);

  v_primer_dia := make_date(p_anio, p_mes, 1);
  v_ultimo_dia := (v_primer_dia + interval '1 month - 1 day')::date;

  v_dia := v_primer_dia;
  while v_dia <= v_ultimo_dia loop
    v_isodow := extract(isodow from v_dia)::int;   -- 1=lunes .. 7=domingo

    if v_por_dia ? v_isodow::text then
      v_cap := coalesce((v_por_dia ->> v_isodow::text)::int, 0);
    else
      v_cap := v_default;
    end if;

    if v_cap is null or v_cap <= 0 then
      v_sin_cupo := v_sin_cupo + 1;   -- dia cerrado: ni plan_servicios ni plan_tramo
    else
      v_fecha_ts := (make_timestamp(p_anio, p_mes, extract(day from v_dia)::int, 12, 0, 0)
                       at time zone 'America/Havana');

      if v_tiene_rec then
        -- ── Generar plan_tramo por cada tramo activo del LS ──
        -- cantidad del tramo = tramo.capacidad ?? recurso.capacidad
        with tramos as (
          select tr.id as id_tramo, coalesce(tr.capacidad, r.capacidad) as cap
          from flow.recurso r
          join flow.tramo tr on tr.id_recurso = r.id and tr.activo
          where r.id_local_servicio = p_id_local_servicio and r.activo
        ),
        ins as (
          insert into flow.plan_tramo (id_tramo, fecha, cantidad, agendados)
          select t.id_tramo, v_fecha_ts, t.cap, 0
          from tramos t
          on conflict (id_tramo, fecha) do update
            set cantidad = greatest(excluded.cantidad, flow.plan_tramo.agendados)
          returning (xmax = 0) as insertado
        )
        select
          v_creados      + count(*) filter (where insertado),
          v_actualizados + count(*) filter (where not insertado)
        into v_creados, v_actualizados
        from ins;
      else
        -- ── Camino legacy: plan_servicios ──
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
    end if;

    v_dia := v_dia + 1;
  end loop;

  return jsonb_build_object(
    'ok',            true,
    'id_local_servicio', p_id_local_servicio,
    'anio',          p_anio,
    'mes',           p_mes,
    'con_recursos',  v_tiene_rec,
    'creados',       v_creados,
    'actualizados',  v_actualizados,
    'omitidos',      v_omitidos,
    'dias_sin_cupo', v_sin_cupo
  );
end;
$$;

grant execute on function flow.admin_generar_plan_mensual(uuid, integer, integer, integer) to authenticated;
