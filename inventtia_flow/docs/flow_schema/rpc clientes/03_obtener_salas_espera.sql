-- ============================================================================
-- RPC CLIENTES: obtener las salas de espera de un usuario
-- Join: flow.sala_espera + flow.local_servicio + flow.app_dat_locales
--       + flow.app_dat_servicios + flow.ultimo_numero
-- Permite saber el numero del usuario en la cola y el ultimo numero otorgado
-- Devuelve: jsonb (array de salas de espera del usuario)
-- ============================================================================

create or replace function flow.cliente_obtener_salas_espera(
  p_uuid_usuario uuid
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
        'id',                se.id,
        'fecha_regla',       se.fecha_regla,
        'created_at',        se.created_at,
        'numero_cola',       se.numero_cola,           -- numero del usuario
        'ultimo_otorgado',   coalesce(un.ultimo_otorgado, 0), -- ultimo numero en el servicio
        -- cuantos numeros faltan para llegar al del usuario (0 = ya es su turno o paso)
        'personas_delante',  greatest(se.numero_cola - coalesce(un.ultimo_otorgado, 0), 0),
        'es_su_turno',       (coalesce(un.ultimo_otorgado, 0) >= se.numero_cola),
        'id_local_servicio', ls.id,
        'servicio', jsonb_build_object(
          'id',          s.id,
          'nombre',      s.nombre,
          'descripcion', s.descripcion,
          'foto',        s.foto
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
        )
      )
      order by se.fecha_regla
    ),
    '[]'::jsonb
  )
  from flow.sala_espera se
  join flow.local_servicio    ls on ls.id = se.id_local_servicio
  join flow.app_dat_locales   l  on l.id  = ls.id_local
  join flow.app_dat_servicios s  on s.id  = ls.id_servicio
  left join flow.ultimo_numero un on un.id_local_servicio = ls.id
  where se.uuid_usuario = p_uuid_usuario;
$$;

grant execute on function flow.cliente_obtener_salas_espera(uuid) to authenticated;

-- Uso:  select flow.cliente_obtener_salas_espera('00000000-0000-0000-0000-000000000000');
