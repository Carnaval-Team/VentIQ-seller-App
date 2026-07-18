-- ============================================================================
-- RPC ADMIN: configuracion de RECURSOS / TRAMOS / TURNOS de un local_servicio.
--
-- Modelo (ver migracion 16_recursos_tramos_turnos.sql):
--   recurso  (Carro 1)  -> tramos (Ida, Vuelta) -> turnos (Ida y vuelta, Solo ida)
--   turno_tramo: que tramos consume cada turno.
--
-- Todas validan pertenencia con flow.admin_entidades_de_usuario y son
-- security invoker (respetan RLS). Devuelven { ok, ... } / { ok:false, error }.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Helper interno: ¿el usuario administra la entidad dueña del local_servicio?
-- ----------------------------------------------------------------------------
create or replace function flow._admin_puede_local_servicio(
  p_uuid_usuario uuid, p_id_local_servicio integer
) returns boolean
language sql stable security invoker set search_path = flow, public as $$
  select exists (
    select 1 from flow.local_servicio ls
    join flow.app_dat_locales l on l.id = ls.id_local
    where ls.id = p_id_local_servicio
      and l.id_entidad in (
        select id_entidad from flow.admin_entidades_de_usuario(p_uuid_usuario)
      )
  );
$$;

create or replace function flow._admin_puede_recurso(
  p_uuid_usuario uuid, p_id_recurso integer
) returns boolean
language sql stable security invoker set search_path = flow, public as $$
  select exists (
    select 1 from flow.recurso r
    join flow.local_servicio ls on ls.id = r.id_local_servicio
    join flow.app_dat_locales l on l.id = ls.id_local
    where r.id = p_id_recurso
      and l.id_entidad in (
        select id_entidad from flow.admin_entidades_de_usuario(p_uuid_usuario)
      )
  );
$$;

-- ============================================================================
-- 1) LISTAR: recursos del local_servicio con sus tramos y turnos (anidado).
-- ============================================================================
create or replace function flow.admin_listar_recursos(
  p_uuid_usuario      uuid,
  p_id_local_servicio integer
)
returns jsonb
language plpgsql stable security invoker set search_path = flow, public
as $$
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
$$;

grant execute on function flow.admin_listar_recursos(uuid, integer) to authenticated;

-- ============================================================================
-- 2) RECURSO: guardar (insert si p_id null, update si no) / eliminar.
-- ============================================================================
create or replace function flow.admin_guardar_recurso(
  p_uuid_usuario      uuid,
  p_id_local_servicio integer,
  p_nombre            text,
  p_capacidad         integer default 1,
  p_orden             integer default 0,
  p_activo            boolean default true,
  p_id                integer default null
)
returns jsonb
language plpgsql volatile security invoker set search_path = flow, public
as $$
declare
  v_id integer;
begin
  if p_id is null then
    if not flow._admin_puede_local_servicio(p_uuid_usuario, p_id_local_servicio) then
      return jsonb_build_object('ok', false, 'error', 'local_servicio inexistente o sin permiso');
    end if;
    insert into flow.recurso (id_local_servicio, nombre, capacidad, orden, activo)
    values (p_id_local_servicio, p_nombre, coalesce(p_capacidad,1), coalesce(p_orden,0), coalesce(p_activo,true))
    returning id into v_id;
  else
    if not flow._admin_puede_recurso(p_uuid_usuario, p_id) then
      return jsonb_build_object('ok', false, 'error', 'recurso inexistente o sin permiso');
    end if;
    update flow.recurso
       set nombre     = p_nombre,
           capacidad  = coalesce(p_capacidad, capacidad),
           orden      = coalesce(p_orden, orden),
           activo     = coalesce(p_activo, activo),
           updated_at = now()
     where id = p_id
    returning id into v_id;
  end if;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

grant execute on function flow.admin_guardar_recurso(uuid, integer, text, integer, integer, boolean, integer) to authenticated;

create or replace function flow.admin_eliminar_recurso(
  p_uuid_usuario uuid, p_id integer
)
returns jsonb
language plpgsql volatile security invoker set search_path = flow, public
as $$
begin
  if not flow._admin_puede_recurso(p_uuid_usuario, p_id) then
    return jsonb_build_object('ok', false, 'error', 'recurso inexistente o sin permiso');
  end if;
  delete from flow.recurso where id = p_id;   -- cascada borra tramos/turnos/plan_tramo
  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function flow.admin_eliminar_recurso(uuid, integer) to authenticated;

-- ============================================================================
-- 3) TRAMO: guardar / eliminar.
-- ============================================================================
create or replace function flow.admin_guardar_tramo(
  p_uuid_usuario uuid,
  p_id_recurso   integer,
  p_nombre       text,
  p_capacidad    integer default null,   -- NULL = hereda recurso.capacidad
  p_orden        integer default 0,
  p_activo       boolean default true,
  p_id           integer default null
)
returns jsonb
language plpgsql volatile security invoker set search_path = flow, public
as $$
declare
  v_id integer;
begin
  if p_id is null then
    if not flow._admin_puede_recurso(p_uuid_usuario, p_id_recurso) then
      return jsonb_build_object('ok', false, 'error', 'recurso inexistente o sin permiso');
    end if;
    insert into flow.tramo (id_recurso, nombre, capacidad, orden, activo)
    values (p_id_recurso, p_nombre, p_capacidad, coalesce(p_orden,0), coalesce(p_activo,true))
    returning id into v_id;
  else
    -- validar via recurso del tramo existente
    if not exists (
      select 1 from flow.tramo tr
      where tr.id = p_id and flow._admin_puede_recurso(p_uuid_usuario, tr.id_recurso)
    ) then
      return jsonb_build_object('ok', false, 'error', 'tramo inexistente o sin permiso');
    end if;
    update flow.tramo
       set nombre     = p_nombre,
           capacidad  = p_capacidad,     -- se permite volver a NULL (hereda)
           orden      = coalesce(p_orden, orden),
           activo     = coalesce(p_activo, activo),
           updated_at = now()
     where id = p_id
    returning id into v_id;
  end if;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

grant execute on function flow.admin_guardar_tramo(uuid, integer, text, integer, integer, boolean, integer) to authenticated;

create or replace function flow.admin_eliminar_tramo(
  p_uuid_usuario uuid, p_id integer
)
returns jsonb
language plpgsql volatile security invoker set search_path = flow, public
as $$
begin
  if not exists (
    select 1 from flow.tramo tr
    where tr.id = p_id and flow._admin_puede_recurso(p_uuid_usuario, tr.id_recurso)
  ) then
    return jsonb_build_object('ok', false, 'error', 'tramo inexistente o sin permiso');
  end if;
  delete from flow.tramo where id = p_id;   -- cascada quita turno_tramo y plan_tramo
  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function flow.admin_eliminar_tramo(uuid, integer) to authenticated;

-- ============================================================================
-- 4) TURNO: guardar (con su set de tramos) / eliminar.
--    p_tramos: array jsonb de ids de tramo, ej '[3,4]'. Reemplaza el set actual.
--    Todos los tramos deben pertenecer al MISMO recurso del turno.
-- ============================================================================
create or replace function flow.admin_guardar_turno(
  p_uuid_usuario uuid,
  p_id_recurso   integer,
  p_nombre       text,
  p_tramos       jsonb   default '[]'::jsonb,
  p_orden        integer default 0,
  p_activo       boolean default true,
  p_id           integer default null
)
returns jsonb
language plpgsql volatile security invoker set search_path = flow, public
as $$
declare
  v_id       integer;
  v_recurso  integer;
  v_bad      integer;
begin
  if p_id is null then
    if not flow._admin_puede_recurso(p_uuid_usuario, p_id_recurso) then
      return jsonb_build_object('ok', false, 'error', 'recurso inexistente o sin permiso');
    end if;
    v_recurso := p_id_recurso;
    insert into flow.turno (id_recurso, nombre, orden, activo)
    values (p_id_recurso, p_nombre, coalesce(p_orden,0), coalesce(p_activo,true))
    returning id into v_id;
  else
    select t.id_recurso into v_recurso
    from flow.turno t
    where t.id = p_id and flow._admin_puede_recurso(p_uuid_usuario, t.id_recurso);
    if v_recurso is null then
      return jsonb_build_object('ok', false, 'error', 'turno inexistente o sin permiso');
    end if;
    update flow.turno
       set nombre = p_nombre,
           orden  = coalesce(p_orden, orden),
           activo = coalesce(p_activo, activo),
           updated_at = now()
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
$$;

grant execute on function flow.admin_guardar_turno(uuid, integer, text, jsonb, integer, boolean, integer) to authenticated;

create or replace function flow.admin_eliminar_turno(
  p_uuid_usuario uuid, p_id integer
)
returns jsonb
language plpgsql volatile security invoker set search_path = flow, public
as $$
begin
  if not exists (
    select 1 from flow.turno t
    where t.id = p_id and flow._admin_puede_recurso(p_uuid_usuario, t.id_recurso)
  ) then
    return jsonb_build_object('ok', false, 'error', 'turno inexistente o sin permiso');
  end if;
  delete from flow.turno where id = p_id;   -- cascada quita turno_tramo
  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function flow.admin_eliminar_turno(uuid, integer) to authenticated;

-- Uso:
--   select flow.admin_listar_recursos('uuid', 5);
--   select flow.admin_guardar_recurso('uuid', 5, 'Carro 1', 15);
--   select flow.admin_guardar_tramo('uuid', 1, 'Ida', 15);
--   select flow.admin_guardar_turno('uuid', 1, 'Ida y vuelta', '[1,2]'::jsonb);
