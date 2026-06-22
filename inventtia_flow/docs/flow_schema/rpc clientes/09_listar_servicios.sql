-- ============================================================================
-- RPC CLIENTES: listar el catalogo de servicios
-- Tabla: flow.app_dat_servicios (+ entidad)
-- Filtro opcional: p_id_entidad (null = todos)
-- Devuelve: jsonb (array de servicios del catalogo)
-- ============================================================================

create or replace function flow.cliente_listar_servicios(
  p_id_entidad integer default null
)
returns jsonb
language sql
stable
security invoker
set search_path = flow, public
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',          s.id,
        'nombre',      s.nombre,
        'descripcion', s.descripcion,
        'foto',        s.foto,
        'created_at',  s.created_at,
        'updated_at',  s.updated_at,
        'entidad', case when en.id is null then null else jsonb_build_object(
          'id',           en.id,
          'denominacion', en.denominacion
        ) end
      )
      order by s.nombre
    ),
    '[]'::jsonb
  )
  from flow.app_dat_servicios s
  left join flow.entidad en on en.id = s.id_entidad
  where (p_id_entidad is null or s.id_entidad = p_id_entidad);
$$;

grant execute on function flow.cliente_listar_servicios(integer) to authenticated, anon;

-- Uso:
--   select flow.cliente_listar_servicios();      -- todo el catalogo
--   select flow.cliente_listar_servicios(2);     -- de una entidad
