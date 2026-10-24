-- ============================================================================
-- MIGRACION 57: listado de CATEGORIAS y de ESTABLECIMIENTOS del cliente
--
-- QUE RESUELVE
--   El Home del cliente pasa a tener una rejilla de acceso rapido
--   («Categorias», «Servicios», «Establecimientos», «Mas populares») y detras
--   tres vistas nuevas. Dos de ellas necesitan agregados que hoy NO existen en
--   ninguna RPC:
--     1. cuantos establecimientos y servicios tiene cada categoria y cada
--        subcategoria;
--     2. el listado de establecimientos con foto, valoracion promedio real y
--        numero de servicios.
--   `metadata.categorias` de `cliente_home_feed` no trae conteos, y
--   `cliente_obtener_locales` no trae contadores ni rating y ademas NO aplica
--   la regla de visibilidad del cliente (devolveria locales sin servicios
--   reservables).
--
-- REGLA DE VISIBILIDAD (identica a `cliente_home_feed`)
--   `flow._ls_disponible(ls.id)`  -> local activo + servicio activo + par
--   activo + entidad al dia.
--   Y la exclusion de `flow.entidad_categoria_oculta`: una entidad puede ocultar
--   una categoria para si misma; se excluye la hoja Y su padre, igual que en el
--   feed (migracion 56).
--
-- POR QUE EL PRECIO NO SE CALCULA AQUI
--   `precio_desde` necesita la regla de precio del servicio (`precios_base` +
--   moneda por defecto), que vive en Dart (`precioBaseDe`) y en SQL
--   (`flow.calcular_precio_con_reglas`). Repetirla aqui seria una tercera
--   implementacion de lo mismo. La RPC devuelve el `config_precio` de cada
--   servicio visible del local y el cliente aplica su regla de siempre.
--
-- DEPENDE DE: 35/36 (feed y ranking), 40/42 (activo y horarios), 47 (jerarquia
--   categoria/subcategoria), 55/56 (categorias ocultas por entidad).
--
-- REVERSION
--   drop function if exists flow.cliente_locales_publicos(integer, integer, text);
--   drop function if exists flow.cliente_categorias_resumen();
--   (Ninguna de las dos la llama todavia nada mas: el cliente degrada a estado
--   vacio con mensaje si no existen.)
-- ============================================================================


-- ============================================================================
-- 1. `cliente_categorias_resumen()`: el nomenclador CON CONTADORES
--
--    Devuelve:
--      {
--        "categorias": [
--          { "id", "codigo", "nombre", "servicios", "establecimientos",
--            "subcategorias": [ { "id", "codigo", "nombre",
--                                 "servicios", "establecimientos" } ] }
--        ],
--        "total_servicios",        -- pares visibles, sin duplicar
--        "total_establecimientos", -- locales distintos con algo visible
--        "otros_servicios",        -- visibles SIN taxonomia asignada
--        "otros_establecimientos"
--      }
--
--    Se incluyen TODAS las raices activas, aunque tengan 0 (la pantalla las
--    pinta con «Todavia sin establecimientos»): el cliente pidio ver «todos los
--    rubros», no solo los que tienen datos. El chip «N ACTIVAS» del Home cuenta
--    las raices activas, que es lo que significa «activa» en el nomenclador.
--
--    Un servicio cuya hoja es raiz (sin padre) cuenta para esa raiz; uno cuya
--    hoja es subcategoria cuenta para la subcategoria Y para su raiz. Es la
--    misma regla que el filtro del feed (migracion 48).
-- ============================================================================
drop function if exists flow.cliente_categorias_resumen();

create or replace function flow.cliente_categorias_resumen()
returns jsonb
language sql
stable
security invoker
set search_path = flow, public
as $function$
with visibles as (
  select
    ls.id                as id_ls,
    l.id                 as id_local,
    s.id_tipo_actividad  as id_hoja,
    ta.id_padre          as id_padre
  from flow.local_servicio ls
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  join flow.app_dat_locales   l on l.id = ls.id_local
  left join flow.nom_tipo_actividad_servicio ta on ta.id = s.id_tipo_actividad
  where flow._ls_disponible(ls.id)
    and not exists (
      select 1
      from flow.entidad_categoria_oculta o
      where o.id_entidad = l.id_entidad
        -- `in` con un NULL nunca casa: sirve para la hoja y para su padre.
        and o.id_tipo_actividad in (s.id_tipo_actividad, ta.id_padre)
    )
),
-- Conteo por RAIZ: la hoja si es raiz, o el padre si es subcategoria.
por_raiz as (
  select
    coalesce(id_padre, id_hoja)         as id_raiz,
    count(*)::integer                   as servicios,
    count(distinct id_local)::integer   as establecimientos
  from visibles
  where id_hoja is not null
  group by 1
),
-- Conteo por HOJA (subcategoria).
por_hoja as (
  select
    id_hoja,
    count(*)::integer                   as servicios,
    count(distinct id_local)::integer   as establecimientos
  from visibles
  where id_hoja is not null
  group by 1
),
armado as (
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id',     ta.id,
             'codigo', ta.codigo,
             'nombre', ta.nombre,
             'servicios',         coalesce(r.servicios, 0),
             'establecimientos',  coalesce(r.establecimientos, 0),
             -- Mismo patron que el nomenclador del feed (migracion 48): solo
             -- subcategorias activas y con nombre, en el orden del superadmin.
             'subcategorias', coalesce((
               select jsonb_agg(
                        jsonb_build_object(
                          'id',     h.id,
                          'codigo', h.codigo,
                          'nombre', h.nombre,
                          'servicios',        coalesce(hh.servicios, 0),
                          'establecimientos', coalesce(hh.establecimientos, 0)
                        )
                        order by h.orden, lower(h.nombre)
                      )
               from flow.nom_tipo_actividad_servicio h
               left join por_hoja hh on hh.id_hoja = h.id
               where h.id_padre = ta.id
                 and h.activo
                 and btrim(h.nombre) <> ''
             ), '[]'::jsonb)
           )
           order by ta.orden, lower(ta.nombre)
         ), '[]'::jsonb) as lista,
         (select count(*)::integer from visibles) as total_servicios,
         (select count(distinct id_local)::integer from visibles)
           as total_establecimientos,
         (select count(*)::integer from visibles where id_hoja is null)
           as otros_servicios,
         (select count(distinct id_local)::integer from visibles where id_hoja is null)
           as otros_establecimientos
  from flow.nom_tipo_actividad_servicio ta
  left join por_raiz r on r.id_raiz = ta.id
  where ta.activo
    and ta.id_padre is null
    and btrim(ta.nombre) <> ''
)
select jsonb_build_object(
  'categorias',             a.lista,
  'total_servicios',        a.total_servicios,
  'total_establecimientos', a.total_establecimientos,
  'otros_servicios',        a.otros_servicios,
  'otros_establecimientos', a.otros_establecimientos
)
from armado a;
$function$;

revoke all on function flow.cliente_categorias_resumen() from public, anon;
grant execute on function flow.cliente_categorias_resumen()
  to authenticated, service_role;


-- ============================================================================
-- 2. `cliente_locales_publicos(...)`: el listado de ESTABLECIMIENTOS
--
--    Devuelve un array (jsonb) con UN objeto por local que tenga al menos un
--    servicio visible bajo el filtro pedido:
--      id, nombre, descripcion, direccion, pais, provincia, foto,
--      horario_atencion, horario_detalle, coordenadas,
--      total_servicios, tiene_reserva_directa, precios[] (config_precio crudo),
--      total_resenas, rating (promedio REAL por local), entidad{...}
--
--    Filtros (los tres opcionales, misma semantica que el feed):
--      * `p_id_categoria`: incluye los servicios de sus subcategorias.
--      * `p_id_subcategoria`: manda sobre la categoria (se aplican los dos).
--      * `p_provincia`: comparacion exacta sin distinguir mayusculas, como el
--        resto del cliente.
--
--    `rating` se agrega sobre `flow.resena` por LOCAL (suma de puntuaciones /
--    numero de resenas), que es el dato exacto, y NO la media de medias por
--    servicio que habria que hacer en el cliente. Si no hay resenas va NULL: la
--    tarjeta no pinta estrellas en vez de inventar un promedio.
--
--    El ORDEN no se decide aqui: la pantalla tiene selector de orden (mejor
--    valorados, mas servicios, A-Z) y reordena en memoria. Se devuelve por
--    nombre para que sin ordenar la lista sea estable.
-- ============================================================================
drop function if exists flow.cliente_locales_publicos(integer, integer, text);

create or replace function flow.cliente_locales_publicos(
  p_id_categoria integer default null,
  p_id_subcategoria integer default null,
  p_provincia text default null
)
returns jsonb
language sql
stable
security invoker
set search_path = flow, public
as $function$
with visibles as (
  select
    ls.id                      as id_ls,
    ls.id_local,
    ls.id_servicio,
    ls.permite_reserva_directa,
    s.config_precio
  from flow.local_servicio ls
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  join flow.app_dat_locales   l on l.id = ls.id_local
  left join flow.nom_tipo_actividad_servicio ta on ta.id = s.id_tipo_actividad
  where flow._ls_disponible(ls.id)
    and not exists (
      select 1
      from flow.entidad_categoria_oculta o
      where o.id_entidad = l.id_entidad
        and o.id_tipo_actividad in (s.id_tipo_actividad, ta.id_padre)
    )
    -- Filtrar por categoria incluye sus subcategorias.
    and (
      p_id_categoria is null
      or s.id_tipo_actividad = p_id_categoria
      or ta.id_padre = p_id_categoria
    )
    and (p_id_subcategoria is null or s.id_tipo_actividad = p_id_subcategoria)
    and (
      p_provincia is null
      or btrim(p_provincia) = ''
      or lower(btrim(l.provincia)) = lower(btrim(p_provincia))
    )
),
rating as (
  -- Por LOCAL, no por servicio: es lo que pide la tarjeta del establecimiento.
  select
    ls.id_local,
    sum(r.puntuacion)::numeric as suma,
    count(*)::integer          as total
  from flow.resena r
  join flow.local_servicio ls on ls.id = r.id_local_servicio
  group by ls.id_local
),
agrupado as (
  select
    v.id_local,
    count(*)::integer                                    as total_servicios,
    bool_or(coalesce(v.permite_reserva_directa, false))   as tiene_reserva_directa,
    jsonb_agg(v.config_precio)                            as precios
  from visibles v
  group by v.id_local
)
select coalesce(jsonb_agg(
         jsonb_build_object(
           'id',               l.id,
           'nombre',           l.nombre,
           'descripcion',      l.descripcion,
           'direccion',        l.direccion,
           'pais',             l.pais,
           'provincia',        l.provincia,
           'foto',             l.foto,
           'horario_atencion', l.horario_atencion,
           'horario_detalle',  l.horario_detalle,
           'coordenadas',      l.coordenadas,
           'total_servicios',  a.total_servicios,
           'tiene_reserva_directa', a.tiene_reserva_directa,
           -- El cliente resuelve el precio con SU regla (`precioBaseDe`).
           'precios',          a.precios,
           'total_resenas',    coalesce(rt.total, 0),
           'rating',           case
                                 when coalesce(rt.total, 0) > 0
                                   then round(rt.suma / rt.total, 1)
                               end,
           'entidad', case when en.id is null then null else jsonb_build_object(
             'id',           en.id,
             'denominacion', en.denominacion,
             'direccion',    en.direccion,
             'telefono',     en.telefono
           ) end
         )
         order by lower(l.nombre)
       ), '[]'::jsonb)
from agrupado a
join flow.app_dat_locales l on l.id = a.id_local
left join flow.entidad en on en.id = l.id_entidad
left join rating rt on rt.id_local = a.id_local;
$function$;

revoke all on function flow.cliente_locales_publicos(integer, integer, text)
  from public, anon;
grant execute on function flow.cliente_locales_publicos(integer, integer, text)
  to authenticated, service_role;


-- PostgREST cachea el catalogo de funciones: sin esto, la app recibe PGRST202
-- («no existe la funcion») durante un rato despues de aplicar la migracion.
notify pgrst, 'reload schema';


-- ============================================================================
-- VERIFICACION (ejecutar despues de aplicar; los numeros son los reales del
-- proyecto release al 23-10-2026: 6 raices activas, 11 pares visibles)
--
--   select jsonb_array_length(flow.cliente_categorias_resumen() -> 'categorias')
--     as raices,                                    -- esperado: 6
--          (flow.cliente_categorias_resumen() ->> 'total_servicios')::int
--     as servicios_visibles,                        -- esperado: 11
--          (flow.cliente_categorias_resumen() ->> 'total_establecimientos')::int
--     as locales_visibles;                          -- esperado: <= 11
--
--   -- Belleza debe traer 5 servicios en 3 locales, y sus subcategorias sumar lo
--   -- mismo (la hoja cuenta en las dos).
--   select c ->> 'nombre', c ->> 'servicios', c ->> 'establecimientos'
--   from jsonb_array_elements(flow.cliente_categorias_resumen() -> 'categorias') c
--   where c ->> 'codigo' = 'belleza';
--
--   -- El listado de establecimientos: 8 locales con algo visible, y solo uno
--   -- con valoracion (Salon 2 Cejas, 2.5 con 2 resenas al 23-10-2026).
--   select jsonb_array_length(flow.cliente_locales_publicos()) as locales,
--          jsonb_array_length(flow.cliente_locales_publicos(11)) as del_local_11;
-- ============================================================================