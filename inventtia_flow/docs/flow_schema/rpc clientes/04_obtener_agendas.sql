-- ============================================================================
-- RPC CLIENTES: obtener las agendas (reservas) de un usuario
-- Join: flow.agenda + flow.local_servicio + flow.app_dat_locales
--       + flow.app_dat_servicios + flow.nom_estado_agenda
-- Filtros opcionales: p_id_estado (null = todos los estados)
-- Devuelve: jsonb (array de reservas del usuario con su estado)
-- ============================================================================

create or replace function flow.cliente_obtener_agendas(
  p_uuid_usuario uuid,
  p_id_estado    integer default null
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
        'id',                   a.id,
        'fecha_hora_reserva',   a.fecha_hora_reserva,
        'fecha_hora_atencion',  a.fecha_hora_atencion,
        'created_at',           a.created_at,
        'updated_at',           a.updated_at,
        'cantidad',             a.cantidad,
        'datos_adicionales',    a.datos_adicionales,
        'reservado_por',        a.reservado_por,
        'precio_total',         a.precio_total,
        'moneda',               a.moneda,
        'uuid_usuario',         a.uuid_usuario,
        'estado', jsonb_build_object(
          'id',          e.id,
          'nombre',      e.nombre,
          'descripcion', e.descripcion
        ),
        'id_local_servicio', ls.id,
        'local_servicio', jsonb_build_object(
          'id',                     ls.id,
          'permite_reserva_directa', ls.permite_reserva_directa,
          'cantidad_default',       ls.cantidad_default,
          'cantidad_max_capacidad', ls.cantidad_max_capacidad
        ),
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
          'id',                             en.id,
          'denominacion',                   en.denominacion,
          'horas_anticipacion_cancelacion', en.horas_anticipacion_cancelacion
        ),
        -- Titular de la reserva (para mostrar "Para: <nombre>" si es un tercero)
        'cliente', case when p.id is null then null else jsonb_build_object(
          'id',           p.id,
          'uuid_usuario', p.uuid_usuario,
          'nombre',       p.nombre,
          'apellidos',    p.apellidos,
          'ci',           p.ci,
          'telefono',     p.telefono
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
  join flow.nom_estado_agenda e  on e.id  = a.id_estado
  join flow.entidad          en on en.id = l.id_entidad
  left join flow.perfil       p  on p.uuid_usuario = a.uuid_usuario
  -- El usuario ve sus propias reservas Y las que hizo para terceros.
  where (a.uuid_usuario = p_uuid_usuario or a.reservado_por = p_uuid_usuario)
    and (p_id_estado is null or a.id_estado = p_id_estado);
$$;

grant execute on function flow.cliente_obtener_agendas(uuid, integer) to authenticated;

-- Uso:
--   select flow.cliente_obtener_agendas('00000000-0000-0000-0000-000000000000');       -- todas
--   select flow.cliente_obtener_agendas('00000000-0000-0000-0000-000000000000', 2);    -- por estado
