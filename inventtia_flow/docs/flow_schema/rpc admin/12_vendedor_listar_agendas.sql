-- ============================================================================
-- RPC VENDEDOR: listar agendas de las entidades asignadas al vendedor.
-- Misma firma y output que admin_listar_agendas pero filtra por
-- flow.entidad_vendedor en lugar de admin/owner.
-- SECURITY DEFINER: necesario para acceder a tablas con RLS desde el JOIN.
-- Filtros opcionales: p_id_entidad, p_id_local, p_id_local_servicio,
--                     p_id_estado, p_desde, p_hasta
-- Devuelve: jsonb (array de reservas)
-- ============================================================================

create or replace function flow.vendedor_listar_agendas(
  p_uuid_usuario        uuid,
  p_id_entidad          integer                      default null,
  p_id_local            integer                      default null,
  p_id_local_servicio   integer                      default null,
  p_id_estado           integer                      default null,
  p_desde               timestamp without time zone  default null,
  p_hasta               timestamp without time zone  default null
)
returns jsonb
language sql
stable
security definer
set search_path = flow, public
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',                  a.id,
        'fecha_hora_reserva',  a.fecha_hora_reserva,
        'fecha_hora_atencion', a.fecha_hora_atencion,
        'created_at',          a.created_at,
        'updated_at',          a.updated_at,
        'cantidad',            a.cantidad,
        'datos_adicionales',   a.datos_adicionales,
        'reservado_por',       a.reservado_por,
        'estado', jsonb_build_object(
          'id',          es.id,
          'nombre',      es.nombre,
          'descripcion', es.descripcion
        ),
        'id_local_servicio', ls.id,
        'servicio', jsonb_build_object(
          'id',                 s.id,
          'nombre',             s.nombre,
          'descripcion',        s.descripcion,
          'foto',               s.foto,
          'campos_adicionales', s.campos_adicionales
        ),
        'local', jsonb_build_object(
          'id',               l.id,
          'nombre',           l.nombre,
          'direccion',        l.direccion,
          'pais',             l.pais,
          'provincia',        l.provincia,
          'horario_atencion', l.horario_atencion,
          'coordenadas',      l.coordenadas,
          'foto',             l.foto
        ),
        'entidad', jsonb_build_object(
          'id',           en.id,
          'denominacion', en.denominacion,
          'direccion',    en.direccion,
          'telefono',     en.telefono
        ),
        'cliente', case when p.id is null then null else jsonb_build_object(
          'id',           p.id,
          'uuid_usuario', p.uuid_usuario,
          'nombre',       p.nombre,
          'apellidos',    p.apellidos,
          'ci',           p.ci,
          'telefono',     p.telefono,
          'created_at',   p.created_at,
          'updated_at',   p.updated_at
        ) end
      )
      order by a.fecha_hora_reserva desc
    ),
    '[]'::jsonb
  )
  from flow.agenda a
  join flow.local_servicio    ls on ls.id = a.id_local_servicio
  join flow.app_dat_locales   l  on l.id  = ls.id_local
  join flow.app_dat_servicios s  on s.id  = ls.id_servicio
  join flow.entidad           en on en.id = l.id_entidad
  join flow.nom_estado_agenda es on es.id = a.id_estado
  left join flow.perfil       p  on p.uuid_usuario = a.uuid_usuario
  -- Seguridad: el p_uuid_usuario debe ser vendedor de esa entidad
  join flow.entidad_vendedor  ev on ev.id_entidad  = l.id_entidad
                                and ev.uuid_usuario = p_uuid_usuario
  where (p_id_entidad        is null or l.id_entidad         = p_id_entidad)
    and (p_id_local          is null or ls.id_local          = p_id_local)
    and (p_id_local_servicio is null or a.id_local_servicio  = p_id_local_servicio)
    and (p_id_estado         is null or a.id_estado          = p_id_estado)
    and (p_desde             is null or a.fecha_hora_reserva >= p_desde)
    and (p_hasta             is null or a.fecha_hora_reserva <= p_hasta);
$$;

grant execute on function flow.vendedor_listar_agendas(
  uuid, integer, integer, integer, integer,
  timestamp without time zone, timestamp without time zone
) to authenticated;

-- ── Verificación ──────────────────────────────────────────────────────────────
-- Sustituir con el uuid real del vendedor:
--
--   select flow.vendedor_listar_agendas(
--     (select id from auth.users where email = 'vendedor@correo.com'),
--     null, null, null, null, null, null
--   );
--
--   -- Por entidad específica:
--   select flow.vendedor_listar_agendas(
--     (select id from auth.users where email = 'vendedor@correo.com'),
--     2
--   );
