-- ============================================================================
-- RPC ADMIN: generar los plan_servicios de un MES a partir de flow.plan_config.
--
-- Lee la config recurrente del local_servicio y, para cada dia del mes:
--   - capacidad = por_dia[isodow] si existe, si no -> default.
--   - capacidad 0 (o sin default)  -> dia OMITIDO (local cerrado ese dia).
--   - si NO existe plan ese dia      -> INSERT (cantidad, agendados=0).
--   - si YA existe plan ese dia       -> UPDATE cantidad = greatest(nueva, agendados)
--                                        (decision "sobrescribir", respetando el
--                                         minimo ya reservado para no perder cupos).
--
-- Comparacion de dia por hora local (America/Havana), igual que bot_procesar_plan,
-- para que el limite de dia no se desplace segun la tz de la conexion. La fecha
-- guardada es el mediodia local del dia (evita cruces de medianoche/DST).
--
-- El trigger trg_plan_servicio_aiu se dispara por cada insert/update y reparte
-- la cola pendiente automaticamente; no hace falta llamar al bot aqui.
--
-- security invoker -> respeta RLS de plan_servicios (insert/update solo de
-- entidades del usuario). Ademas validamos pertenencia explicitamente.
-- Devuelve: { ok, creados, actualizados, omitidos, dias_sin_cupo }.
-- ============================================================================

create or replace function flow.admin_generar_plan_mensual(
  p_uuid_usuario      uuid,
  p_id_local_servicio integer,
  p_anio              integer,
  p_mes               integer
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = flow, public
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
begin
  if p_uuid_usuario is null or p_id_local_servicio is null
     or p_anio is null or p_mes is null then
    return jsonb_build_object('ok', false, 'error', 'parametros obligatorios faltantes');
  end if;
  if p_mes < 1 or p_mes > 12 then
    return jsonb_build_object('ok', false, 'error', 'mes invalido');
  end if;

  -- Validar pertenencia
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

  -- Cargar config recurrente
  select pc.config into v_config
  from flow.plan_config pc
  where pc.id_local_servicio = p_id_local_servicio
    and pc.activo = true;

  if v_config is null then
    return jsonb_build_object('ok', false, 'error', 'no hay configuracion activa para este servicio');
  end if;

  v_default := coalesce((v_config ->> 'default')::int, 0);
  v_por_dia := coalesce(v_config -> 'por_dia', '{}'::jsonb);

  v_primer_dia := make_date(p_anio, p_mes, 1);
  v_ultimo_dia := (v_primer_dia + interval '1 month - 1 day')::date;

  v_dia := v_primer_dia;
  while v_dia <= v_ultimo_dia loop
    v_isodow := extract(isodow from v_dia)::int;   -- 1=lunes .. 7=domingo

    -- capacidad del dia: override por_dia[isodow] si existe, si no el default
    if v_por_dia ? v_isodow::text then
      v_cap := coalesce((v_por_dia ->> v_isodow::text)::int, 0);
    else
      v_cap := v_default;
    end if;

    if v_cap is null or v_cap <= 0 then
      -- dia cerrado: no se planifica
      v_sin_cupo := v_sin_cupo + 1;
    else
      -- mediodia local del dia (estable frente a medianoche/DST)
      v_fecha_ts := (make_timestamp(p_anio, p_mes, extract(day from v_dia)::int, 12, 0, 0)
                       at time zone 'America/Havana');

      -- ¿ya existe un plan ese dia (por dia local)?
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
    'ok',            true,
    'id_local_servicio', p_id_local_servicio,
    'anio',          p_anio,
    'mes',           p_mes,
    'creados',       v_creados,
    'actualizados',  v_actualizados,
    'omitidos',      v_omitidos,
    'dias_sin_cupo', v_sin_cupo
  );
end;
$$;

grant execute on function flow.admin_generar_plan_mensual(uuid, integer, integer, integer) to authenticated;

-- Uso:
--   select flow.admin_generar_plan_mensual('00000000-...', 7, 2026, 7);  -- julio 2026
