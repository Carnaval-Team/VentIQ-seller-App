-- ============================================================================
-- RPC ADMIN: ver las colas (sala_espera) de los servicios de sus entidades.
-- Util para que el admin vea quien esta esperando y con que numero.
-- Incluye el perfil del cliente. Filtros opcionales: entidad, local, local_servicio.
-- Devuelve: jsonb (array de personas en cola)
-- ============================================================================

create or replace function flow.admin_listar_salas_espera(
  p_uuid_usuario        uuid,
  p_id_entidad          integer default null,
  p_id_local            integer default null,
  p_id_local_servicio   integer default null
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
        'id',          se.id,
        'numero_cola', se.numero_cola,
        'fecha_regla', se.fecha_regla,
        'created_at',  se.created_at,
        'id_local_servicio', ls.id,
        'servicio', jsonb_build_object('id', s.id, 'nombre', s.nombre),
        'local',    jsonb_build_object('id', l.id, 'nombre', l.nombre, 'pais', l.pais, 'provincia', l.provincia),
        'entidad',  jsonb_build_object('id', en.id, 'denominacion', en.denominacion),
        'cliente', case when p.id is null then null else jsonb_build_object(
          'uuid_usuario', p.uuid_usuario,
          'nombre',       p.nombre,
          'apellidos',    p.apellidos,
          'ci',           p.ci,
          'telefono',     p.telefono
        ) end
      )
      order by l.nombre, s.nombre, se.numero_cola
    ),
    '[]'::jsonb
  )
  from flow.sala_espera se
  join flow.local_servicio    ls on ls.id = se.id_local_servicio
  join flow.app_dat_locales   l  on l.id  = ls.id_local
  join flow.app_dat_servicios s  on s.id  = ls.id_servicio
  join flow.entidad           en on en.id = l.id_entidad
  left join flow.perfil       p  on p.uuid_usuario = se.uuid_usuario
  join flow.admin_entidades_de_usuario(p_uuid_usuario) mine on mine.id_entidad = l.id_entidad
  where (p_id_entidad        is null or l.id_entidad        = p_id_entidad)
    and (p_id_local          is null or ls.id_local         = p_id_local)
    and (p_id_local_servicio is null or se.id_local_servicio = p_id_local_servicio);
$$;

grant execute on function flow.admin_listar_salas_espera(uuid, integer, integer, integer) to authenticated;

-- Uso:
--   select flow.admin_listar_salas_espera('00000000-...');
--   select flow.admin_listar_salas_espera('00000000-...', 2);   -- por entidad
