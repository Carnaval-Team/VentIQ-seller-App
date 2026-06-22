-- ============================================================================
-- RPC CLIENTES: obtener todos los locales
-- Join: flow.app_dat_locales + flow.entidad (la entidad duena del local)
-- Filtro opcional: p_id_entidad (null = todos)
-- Devuelve: jsonb (array de locales)
-- ============================================================================

create or replace function flow.cliente_obtener_locales(
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
        'id',                  l.id,
        'nombre',              l.nombre,
        'descripcion',         l.descripcion,
        'horario_atencion',    l.horario_atencion,
        'terminos_condiciones',l.terminos_condiciones,
        'coordenadas',         l.coordenadas,
        'direccion',           l.direccion,
        'pais',                l.pais,
        'provincia',           l.provincia,
        'foto',                l.foto,
        'created_at',          l.created_at,
        'updated_at',          l.updated_at,
        'entidad', case when en.id is null then null else jsonb_build_object(
          'id',           en.id,
          'denominacion', en.denominacion,
          'direccion',    en.direccion,
          'telefono',     en.telefono
        ) end
      )
      order by l.nombre
    ),
    '[]'::jsonb
  )
  from flow.app_dat_locales l
  left join flow.entidad en on en.id = l.id_entidad
  where (p_id_entidad is null or l.id_entidad = p_id_entidad);
$$;

-- Se reemplaza la firma anterior (sin parametros) por seguridad
drop function if exists flow.cliente_obtener_locales();
grant execute on function flow.cliente_obtener_locales(integer) to authenticated, anon;

-- Uso:
--   select flow.cliente_obtener_locales();        -- todos
--   select flow.cliente_obtener_locales(2);       -- de una entidad
