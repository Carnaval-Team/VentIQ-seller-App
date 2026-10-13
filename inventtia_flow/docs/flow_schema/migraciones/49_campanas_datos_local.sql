-- ============================================================================
-- MIGRACION 49: la campana patrocinada trae los datos del LOCAL
--
-- POR QUE
--   El Home necesita pintar la tarjeta de "Espacio patrocinado" con la imagen
--   del local de fondo, y al tocarla abrir una vista de marketing del
--   establecimiento (imagen grande, descripcion, direccion, horario). Hasta
--   ahora `flow.campanas_activas()` solo resolvia el NOMBRE del local y del
--   servicio, asi que el cliente tenia que adivinar el resto.
--
--   Se resuelve en el mismo RPC (una peticion, no tres) y se mantiene la MISMA
--   FIRMA sin argumentos, asi que `create or replace` no rompe a nadie.
--
-- QUE NO HACE
--   No cambia la vigencia ni el orden (prioridad desc, id asc) ni la relacion
--   con `flow.promocion`. Una campana sigue sin tocar el precio jamas.
--
-- DEPENDE DE: 28_patrocinados.sql (crea la tabla y el RPC).
--
-- REVERSION
--   Volver a ejecutar `28_patrocinados.sql`: recrea `campanas_activas()` sin
--   los campos nuevos. La app los trata como opcionales.
-- ============================================================================

create or replace function flow.campanas_activas()
returns jsonb
language sql
stable
security invoker
set search_path = flow, public
as $$
  select coalesce(
    jsonb_agg(to_jsonb(t) order by t.prioridad desc, t.id asc),
    '[]'::jsonb
  )
  from (
    select
      c.id,
      c.titulo,
      c.subtitulo,
      c.descripcion,
      c.id_local_servicio,
      c.id_entidad,
      c.color_inicio,
      c.color_fin,
      c.icono,
      c.image_url,
      c.prioridad,
      c.hasta,
      -- Nombres resueltos para pintar el badge sin otra consulta.
      l.nombre      as local,
      ls.id         as id_local_servicio_real,
      s.nombre      as servicio,
      en.denominacion as entidad,
      -- [49] Datos del establecimiento para la tarjeta y la vista de marketing.
      l.id              as id_local,
      l.foto            as local_foto,
      l.descripcion     as local_descripcion,
      l.direccion       as local_direccion,
      l.provincia       as local_provincia,
      l.pais            as local_pais,
      l.horario_atencion as local_horario_atencion,
      l.horario_detalle  as local_horario_detalle,
      l.coordenadas      as local_coordenadas,
      l.activo           as local_activo,
      -- La campana puede ser de entidad: entonces no hay local.
      coalesce(l.id_entidad, c.id_entidad) as id_entidad_real,
      en.telefono       as entidad_telefono,
      en.direccion      as entidad_direccion
    from flow.campana c
    left join flow.local_servicio   ls on ls.id = c.id_local_servicio
    left join flow.app_dat_locales  l  on l.id  = ls.id_local
    left join flow.app_dat_servicios s on s.id  = ls.id_servicio
    left join flow.entidad          en on en.id = coalesce(l.id_entidad, c.id_entidad)
    where c.activo
      and (c.desde is null or (now() at time zone 'America/Havana') >= c.desde)
      and (c.hasta is null or (now() at time zone 'America/Havana') <  c.hasta)
  ) t;
$$;

revoke all on function flow.campanas_activas() from public, anon;
grant execute on function flow.campanas_activas() to authenticated, service_role;

notify pgrst, 'reload schema';

-- ============================================================================
-- VERIFICACION
-- ============================================================================
select jsonb_array_length(flow.campanas_activas()) as campanas_vigentes;

select c ->> 'titulo'      as titulo,
       c ->> 'local'       as local,
       c ->> 'local_foto'  as local_foto,
       (c ->> 'id_local')::integer as id_local
from jsonb_array_elements(flow.campanas_activas()) c;
