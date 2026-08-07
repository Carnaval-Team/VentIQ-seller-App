-- ============================================================================
-- RPC ADMIN: listar agendas (reservas) de las entidades del usuario admin.
-- ESTADO ACTUAL (revisar este archivo como fuente de verdad del RPC).
--
-- Join completo: agenda -> local_servicio -> local -> servicio -> entidad
--                agenda -> nom_estado_agenda
--                agenda.uuid_usuario -> perfil (cliente)
--                agenda.id_turno -> turno -> recurso  (denominaciones)
-- SECURITY DEFINER: necesario para leer agenda de terceros cuando hay RLS.
-- La seguridad la garantiza el JOIN con admin_entidades_de_usuario.
--
-- Campos de turno/viaje:
--   id_turno, id_viaje, tipo_trayecto
--   turno: { id, nombre, recurso: { id, nombre } }  (null si sin turno)
--
-- Filtros opcionales: p_id_entidad, p_id_local, p_id_local_servicio,
--                     p_id_estado, p_desde, p_hasta (rango de fecha_hora_reserva)
-- Devuelve: jsonb (array de reservas)
-- ============================================================================

create or replace function flow.admin_listar_agendas(
  p_uuid_usuario        uuid,
  p_id_entidad          integer default null,
  p_id_local            integer default null,
  p_id_local_servicio   integer default null,
  p_id_estado           integer default null,
  p_desde               timestamp without time zone default null,
  p_hasta               timestamp without time zone default null
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
        'uuid_usuario',        a.uuid_usuario,
        'id_estado',           a.id_estado,
        'fecha_hora_reserva',  a.fecha_hora_reserva,
        'fecha_hora_atencion', a.fecha_hora_atencion,
        'created_at',          a.created_at,
        'updated_at',          a.updated_at,
        'cantidad',            a.cantidad,
        'datos_adicionales',   a.datos_adicionales,
        'reservado_por',       a.reservado_por,
        'precio_total',        a.precio_total,
        'moneda',              a.moneda,
        'id_turno',            a.id_turno,
        'id_viaje',            a.id_viaje,
        'tipo_trayecto',       a.tipo_trayecto,
        'turno', case when t.id is null then null else jsonb_build_object(
          'id',     t.id,
          'nombre', t.nombre,
          'recurso', jsonb_build_object('id', r.id, 'nombre', r.nombre)
        ) end,
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
          'campos_adicionales', s.campos_adicionales,
          'config_precio',      s.config_precio
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
  left join flow.turno        t  on t.id = a.id_turno
  left join flow.recurso      r  on r.id = t.id_recurso
  join flow.admin_entidades_de_usuario(p_uuid_usuario) mine on mine.id_entidad = l.id_entidad
  where (p_id_entidad        is null or l.id_entidad         = p_id_entidad)
    and (p_id_local          is null or ls.id_local          = p_id_local)
    and (p_id_local_servicio is null or a.id_local_servicio  = p_id_local_servicio)
    and (p_id_estado         is null or a.id_estado          = p_id_estado)
    and (p_desde             is null or a.fecha_hora_reserva::date >= p_desde::date)
    and (p_hasta             is null or a.fecha_hora_reserva::date <= p_hasta::date);
$$;

grant execute on function flow.admin_listar_agendas(
  uuid, integer, integer, integer, integer,
  timestamp without time zone, timestamp without time zone
) to authenticated;

-- Uso:
--   select flow.admin_listar_agendas('00000000-...');
--   select flow.admin_listar_agendas('00000000-...', 2);
--   select flow.admin_listar_agendas('00000000-...', null, null, 7);
--   select flow.admin_listar_agendas('00000000-...', null, null, null, 1,
--            '2026-08-03', '2026-08-03');
