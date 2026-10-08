-- ============================================================================
-- MIGRACION: reasignar los servicios existentes a las categorias reales
--
-- DEPENDE DE: 22_categorias_marketplace.sql (aplicar primero).
--
-- POR QUE
--   Tras sembrar la taxonomia, los servicios siguen apuntando a `general`, asi
--   que el riel del Home mostraria categorias sin ningun servicio dentro. Este
--   cambio solo toca `app_dat_servicios.id_tipo_actividad`: no mueve locales,
--   precios ni reservas.
--
--   La migracion comprueba al principio que las categorias destino existan; si
--   falta la 22, aborta en vez de dejar el catalogo a medias.
--
-- NO SE TOCA (a proposito)
--   1 'Gas', 3 'test', 4 'Transportacion Privada'  → se quedan en 'general'
--   6 'Transportacion', 7 'Carnaval Transportacion' → ya estan en
--     'transporte_omnibus'. NO cambiar: `LocalServicio.esTransporteOmnibus`
--     activa el flujo de pasajes ida/vuelta (recursos, tramos y turnos). Meter
--     ahi un servicio de uñas lo rompe.
--
-- LO QUE HACE
--   2  'Alquiler de asientos de camion' → transporte_privado
--   8  'Arreglo de uñas'                → unas
--   9  'Depilación De Cejas'            → cejas_pestanas
--   10 'Lifting De Pestañas'            → cejas_pestanas
--   11 'Lifting De Cejas'               → cejas_pestanas
--   12 'Arreglo uñas naturales'         → unas
--
-- REVERSION
--   Los 6 servicios estaban todos en 'general' (id 1). Para volver atras:
--     update flow.app_dat_servicios
--        set id_tipo_actividad = (select id from flow.nom_tipo_actividad_servicio
--                                  where codigo = 'general')
--      where id in (2, 8, 9, 10, 11, 12);
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. Comprobacion previa: las categorias destino deben existir
-- ---------------------------------------------------------------------------
do $$
declare
  v_faltan text;
begin
  select string_agg(c.codigo, ', ')
    into v_faltan
  from (values ('unas'), ('cejas_pestanas'), ('transporte_privado')) as c(codigo)
  where not exists (
    select 1 from flow.nom_tipo_actividad_servicio t where t.codigo = c.codigo
  );

  if v_faltan is not null then
    raise exception
      'Faltan categorias (%): aplica antes 22_categorias_marketplace.sql',
      v_faltan;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1. Reasignacion
--
--    Se resuelve el id por codigo (no por id fijo) para que funcione igual en
--    los dos proyectos Supabase, donde los ids pueden diferir.
--    Idempotente: volver a ejecutarlo deja el mismo estado.
-- ---------------------------------------------------------------------------
with destino(codigo, ids_servicio) as (
  values
    ('unas',             array[8, 12]),
    ('cejas_pestanas',   array[9, 10, 11]),
    ('transporte_privado', array[2])
)
update flow.app_dat_servicios s
   set id_tipo_actividad = t.id
  from destino d
  join flow.nom_tipo_actividad_servicio t on t.codigo = d.codigo
 where s.id = any(d.ids_servicio);

-- ---------------------------------------------------------------------------
-- 2. Verificacion: este es el resultado esperado
-- ---------------------------------------------------------------------------
select s.id as id_servicio,
       s.nombre as servicio,
       t.codigo as categoria,
       t.nombre as categoria_nombre
from flow.app_dat_servicios s
join flow.nom_tipo_actividad_servicio t on t.id = s.id_tipo_actividad
order by t.nombre, s.nombre;