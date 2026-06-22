-- ============================================================================
-- RPC CLIENTES: obtener todos los servicios
-- Join: flow.local_servicio + flow.app_dat_servicios + flow.app_dat_locales
-- Filtros opcionales (null = sin filtrar):
--   p_id_local, p_id_servicio, p_id_entidad        -> exactos por id
--   p_nombre_local, p_nombre_servicio              -> busqueda parcial (ILIKE)
--   p_pais, p_provincia                            -> busqueda parcial (ILIKE)
-- Devuelve: jsonb (array de servicios por local)
-- ============================================================================

create or replace function flow.cliente_obtener_servicios(
  p_id_local        integer default null,
  p_id_servicio     integer default null,
  p_id_entidad      integer default null,
  p_nombre_local    text    default null,
  p_nombre_servicio text    default null,
  p_pais            text    default null,
  p_provincia       text    default null
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
        'id_local_servicio', ls.id,
        'created_at',        ls.created_at,
        'servicio', jsonb_build_object(
          'id',          s.id,
          'nombre',      s.nombre,
          'descripcion', s.descripcion,
          'foto',        s.foto
        ),
        'local', jsonb_build_object(
          'id',               l.id,
          'nombre',           l.nombre,
          'descripcion',      l.descripcion,
          'horario_atencion', l.horario_atencion,
          'coordenadas',      l.coordenadas,
          'direccion',        l.direccion,
          'pais',             l.pais,
          'provincia',        l.provincia,
          'foto',             l.foto
        ),
        'entidad', case when en.id is null then null else jsonb_build_object(
          'id',           en.id,
          'denominacion', en.denominacion,
          'direccion',    en.direccion,
          'telefono',     en.telefono
        ) end
      )
      order by l.nombre, s.nombre
    ),
    '[]'::jsonb
  )
  from flow.local_servicio ls
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  join flow.app_dat_locales   l on l.id = ls.id_local
  left join flow.entidad     en on en.id = l.id_entidad
  where (p_id_local        is null or ls.id_local    = p_id_local)
    and (p_id_servicio     is null or ls.id_servicio = p_id_servicio)
    and (p_id_entidad      is null or l.id_entidad   = p_id_entidad)
    and (p_nombre_local    is null or l.nombre    ilike '%' || p_nombre_local    || '%')
    and (p_nombre_servicio is null or s.nombre    ilike '%' || p_nombre_servicio || '%')
    and (p_pais            is null or l.pais      ilike '%' || p_pais            || '%')
    and (p_provincia       is null or l.provincia ilike '%' || p_provincia       || '%');
$$;

-- Reemplaza las firmas anteriores (3 y 4 parametros) por la nueva
drop function if exists flow.cliente_obtener_servicios(integer, integer);
drop function if exists flow.cliente_obtener_servicios(integer, integer, integer);
grant execute on function flow.cliente_obtener_servicios(integer, integer, integer, text, text, text, text) to authenticated, anon;

-- Uso (todos los parametros son opcionales; usa named params en Supabase JS):
--   select flow.cliente_obtener_servicios();                              -- todos
--   select flow.cliente_obtener_servicios(1, null, null);                 -- de un local
--   select flow.cliente_obtener_servicios(null, 3, null);                 -- de un servicio
--   select flow.cliente_obtener_servicios(null, null, 2);                 -- de una entidad
--   select flow.cliente_obtener_servicios(p_nombre_servicio => 'corte');  -- busqueda por nombre
--   select flow.cliente_obtener_servicios(p_provincia => 'Habana');       -- por provincia
--   select flow.cliente_obtener_servicios(
--            p_nombre_local => 'centro', p_pais => 'Cuba');               -- combinado
