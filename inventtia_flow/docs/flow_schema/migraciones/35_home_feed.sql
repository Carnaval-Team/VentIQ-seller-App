-- ============================================================================
-- 35_home_feed.sql
-- ============================================================================
-- QUE HACE
--   Anade `flow.cliente_home_feed(...)`: UNA peticion que devuelve todo lo que
--   el Home del cliente necesita pintar. Antes el Home encadenaba ~6 lecturas
--   (catalogo, nomenclador de categorias, valoraciones, promociones,
--   colecciones, patrocinados), cada una un viaje de red en un instante
--   distinto: el feed podia quedar a medio actualizar (catalogo nuevo con
--   colecciones viejas).
--
-- POR QUE COMPONE EN VEZ DE REESCRIBIR
--   La resolucion de "que promocion aplica a este servicio" ya vive en
--   `flow.promociones_por_servicio()`, y las valoraciones en
--   `flow.resenas_por_servicio()`. Este RPC las COMPONE con un join en vez de
--   copiar sus reglas: dos implementaciones de la misma regla es exactamente
--   como aparecen los descuadres (la leccion del Paso 5).
--
-- FORMA DE CADA ITEM (importante para el cliente)
--   Los `items` NO son filas planas: cada uno conserva la forma anidada que ya
--   devuelve `cliente_obtener_servicios` (`servicio` / `local` / `entidad`), y
--   se le anaden `rating`, `total_resenas`, `categoria_nombre`,
--   `categoria_codigo` y `promocion`.
--
--   Es a proposito: `HomeCatalogItem` guarda un `LocalServicio` para poder
--   abrir el detalle, y `LocalServicio.fromJson` / `Servicio.fromJson` /
--   `Local.fromJson` esperan esa forma. Devolver filas planas obligaria al
--   cliente a reconstruir el objeto y volveriamos a tener dos formas del mismo
--   dato, que es como se desincronizan.
--
-- POR QUE SECURITY INVOKER Y NO DEFINER
--   El feed lee `notificaciones` y `agenda` para los contadores. Con
--   `security definer` RLS se evaluaria como el definidor, y un error en un
--   WHERE filtraria datos de OTROS usuarios. Como INVOKER, RLS sigue siendo
--   la puerta real, y el contador de reservas coincide exactamente con el del
--   provider porque `cliente_obtener_agendas` usa el mismo WHERE y las mismas
--   politicas.
--
--   Los contadores salen de `auth.uid()`, NO de un parametro del cliente: el
--   feed no puede usarse para espiar las reservas ni los puntos de otro.
--
-- PAGINACION
--   El contrato (`has_more`, `next_cursor`) va completo pero hoy devuelve
--   `false`/`null`: el catalogo tiene 7 filas y se trae entero, que es lo que
--   ya evita una peticion por tarjeta. Anadir cursor despues es aditivo.
--
--   Con la carga completa, el filtro "Solo abiertos" puede seguir
--   evaluandose en Dart con `HorarioAtencion`. Portarlo a SQL seria una
--   SEGUNDA implementacion de un parser heuristico (formatos libres, "8-4" vs
--   "8:00am a 4:00pm", regla de 12h vs 24h) que debe coincidir exactamente con
--   la de la app: si diverge, el feed diria "abierto" donde el detalle dice
--   "Horario no disponible".
--
-- SOLO PARA `authenticated`
--   El Home solo es alcanzable con sesion (`/splash` manda a `/login` sin
--   login, y `home_shell` redirige si se pierde). Ademas el feed COMPONE
--   funciones que solo tienen EXECUTE para `authenticated`
--   (`promociones_por_servicio`, `resenas_por_servicio`, `colecciones_activas`,
--   `campanas_activas`): concederselo a `anon` haria fallar el feed entero, no
--   solo una seccion.
--
-- REVERSIBILIDAD
--   drop function if exists flow.cliente_home_feed(text, integer, text, integer, boolean);
--
-- ORDEN: despues de 34. Es ADITIVO: no toca ninguna funcion existente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Pre-chequeo: las funciones que este RPC compone deben existir.
--    (Se comprueba con to_regprocedure y no con auth.uid(), porque en el
--     editor SQL `auth.uid()` es NULL y el chequeo daria un falso negativo.)
-- ---------------------------------------------------------------------------
do $pre$
begin
  if to_regprocedure('flow.resenas_por_servicio()') is null then
    raise exception 'Falta flow.resenas_por_servicio(): aplica antes 26_resenas.sql';
  end if;
  if to_regprocedure('flow.promociones_por_servicio()') is null then
    raise exception 'Falta flow.promociones_por_servicio(): aplica antes 27_promociones.sql';
  end if;
  if to_regprocedure('flow.campanas_activas()') is null then
    raise exception 'Falta flow.campanas_activas(): aplica antes 28_patrocinados.sql';
  end if;
  if to_regprocedure('flow.colecciones_activas()') is null then
    raise exception 'Falta flow.colecciones_activas(): aplica antes 30_colecciones.sql';
  end if;
end
$pre$;

-- ---------------------------------------------------------------------------
-- 2. El feed.
-- ---------------------------------------------------------------------------
create or replace function flow.cliente_home_feed(
  p_query           text    default null,
  p_id_categoria    integer default null,
  p_provincia       text    default null,
  p_id_coleccion    integer default null,
  p_mejor_valorados boolean default false
)
returns jsonb
language sql
stable
security invoker
set search_path to 'flow','public'
as $function$
with busqueda as (
  -- El termino se normaliza UNA vez. Mismo criterio que la app: minusculas y
  -- sin acentos, en los dos lados de la comparacion.
  select nullif(btrim(unaccent(lower(coalesce(p_query, '')))), '') as q
),
base as (
  select
    ls.id                          as id_local_servicio,
    ls.created_at                  as created_at,
    ls.permite_reserva_directa,
    ls.cantidad_default,
    ls.cantidad_max_capacidad,
    s.id                           as id_servicio,
    s.nombre                       as servicio,
    s.descripcion                  as descripcion,
    s.foto                         as foto_servicio,
    s.campos_adicionales,
    s.permite_tercero,
    s.config_precio,
    s.id_tipo_actividad,
    -- `ta.nombre` viaja aqui para que el riel de categorias no necesite una
    -- segunda lectura del nomenclador (era el objetivo del Paso 9).
    ta.codigo                      as categoria_codigo,
    ta.nombre                      as categoria_nombre,
    ta.activo                      as categoria_activa,
    l.id                           as id_local,
    l.nombre                       as local,
    l.descripcion                  as local_descripcion,
    l.horario_atencion,
    l.coordenadas,
    l.direccion,
    l.pais,
    l.provincia,
    l.foto                         as foto_local,
    en.id                          as id_entidad,
    en.denominacion                as entidad,
    en.direccion                   as entidad_direccion,
    en.telefono                    as entidad_telefono,
    en.horas_anticipacion_cancelacion,
    coalesce(rv.total, 0)::integer as total_resenas,
    rv.promedio                    as rating,
    pr.id                          as id_promocion,
    pr.titulo                      as promo_titulo,
    pr.tipo                        as promo_tipo,
    pr.valor                       as promo_valor,
    pr.moneda                      as promo_moneda,
    pr.hasta                       as promo_hasta,
    pr.cupos_restantes,
    cs.orden                       as orden_coleccion
  from flow.local_servicio ls
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  join flow.app_dat_locales   l on l.id = ls.id_local
  left join flow.nom_tipo_actividad_servicio ta on ta.id = s.id_tipo_actividad
  left join flow.entidad                     en on en.id = l.id_entidad
  -- Composicion, no copia: la regla de prioridad de la promo y el promedio de
  -- resenas siguen viviendo en un unico sitio.
  left join flow.resenas_por_servicio()     rv on rv.id_local_servicio = ls.id
  left join flow.promociones_por_servicio() pr on pr.id_local_servicio = ls.id
  -- Con `p_id_coleccion` nulo la condicion no casa y `orden_coleccion` queda
  -- nulo, que es justo lo que hace que no filtre nada.
  left join flow.coleccion_servicio cs
         on cs.id_local_servicio = ls.id
        and cs.id_coleccion = p_id_coleccion
  cross join busqueda b
  where (p_id_categoria is null or s.id_tipo_actividad = p_id_categoria)
    and (p_id_coleccion is null or cs.id_coleccion is not null)
    -- Provincia: comparacion exacta sin acentos, igual que hoy en la app.
    -- No se usa unaccent aqui a proposito: la app tampoco lo hace.
    and (
      p_provincia is null
      or btrim(p_provincia) = ''
      or lower(btrim(l.provincia)) = lower(btrim(p_provincia))
    )
    -- `strpos` en vez de `like`: un `%` escrito por el usuario es un caracter
    -- literal, no un comodin. Asi el comportamiento es identico al `contains`
    -- de Dart.
    and (
      b.q is null
      or strpos(
           unaccent(lower(
             coalesce(s.nombre, '') || ' ' ||
             coalesce(l.nombre, '') || ' ' ||
             coalesce(nullif(btrim(ta.nombre), ''),
                      replace(coalesce(ta.codigo, ''), '_', ' '),
                      'General')
           )),
           b.q
         ) > 0
    )
),
ordenado as (
  select b.*,
         row_number() over (
           order by
             -- Con coleccion elegida manda el orden curado por el superadmin.
             case when p_id_coleccion is not null then b.orden_coleccion end asc nulls last,
             -- "Mejor valorados": los que no tienen valoracion van al final; no se
             -- les supone una. La condicion es EXACTAMENTE la del getter
             -- `HomeCatalogItem.tieneValoracion` del cliente
             -- (`totalResenas > 0 and rating > 0`), para que el orden del
             -- servidor y el "pinto estrellas?" del cliente no se contradigan.
             case when p_mejor_valorados
                   and not (b.total_resenas > 0 and coalesce(b.rating, 0) > 0)
                  then 1 else 0 end asc,
             case when p_mejor_valorados then b.rating end desc nulls last,
             case when p_mejor_valorados then b.total_resenas end desc,
             -- Orden por defecto: el mismo que `cliente_obtener_servicios`.
             b.local asc,
             b.servicio asc
         ) as rn
  from base b
),
pagina as (
  select
    coalesce(jsonb_agg(
      -- Cada item reusa EXACTAMENTE la forma anidada que ya devuelve
      -- `cliente_obtener_servicios` (`servicio` / `local` / `entidad`), y le
      -- anade los extras. Asi el modelo Dart (`LocalServicio.fromJson`,
      -- `Servicio.fromJson`) sigue funcionando sin cambios y la navegacion al
      -- detalle no se rompe: si el feed devolviera filas planas, el cliente
      -- tendria que adaptarlas y volveriamos a tener dos formas del mismo dato.
      jsonb_build_object(
        'id_local_servicio',       o.id_local_servicio,
        'created_at',              o.created_at,
        'permite_reserva_directa', o.permite_reserva_directa,
        'cantidad_default',        o.cantidad_default,
        'cantidad_max_capacidad',  o.cantidad_max_capacidad,

        -- Extras del feed (no venian en `cliente_obtener_servicios`).
        'rating',         o.rating,
        'total_resenas',  o.total_resenas,
        'categoria_codigo', o.categoria_codigo,
        -- Se emite la categoria SOLO si esta activa. Con la categoria apagada
        -- queda NULL y el cliente cae a su respaldo (el codigo legible), que es
        -- lo que hacia antes: el nomenclador activo no la conocia.
        'categoria_nombre', case
                              when o.categoria_activa then nullif(btrim(o.categoria_nombre), '')
                              else null
                            end,
        'promocion', case when o.id_promocion is null then null else
                       jsonb_build_object(
                         'id',              o.id_promocion,
                         'titulo',          o.promo_titulo,
                         'tipo',            o.promo_tipo,
                         'valor',           o.promo_valor,
                         'moneda',          o.promo_moneda,
                         'hasta',           o.promo_hasta,
                         'cupos_restantes', o.cupos_restantes
                       )
                     end,

        'servicio', jsonb_build_object(
          'id',                 o.id_servicio,
          'nombre',             o.servicio,
          'descripcion',        o.descripcion,
          'foto',               o.foto_servicio,
          'campos_adicionales', o.campos_adicionales,
          'permite_tercero',    o.permite_tercero,
          'config_precio',      o.config_precio,
          'id_tipo_actividad',  o.id_tipo_actividad,
          'tipo_actividad', jsonb_build_object(
            'id',     o.id_tipo_actividad,
            'codigo', o.categoria_codigo
          )
        ),

        'local', jsonb_build_object(
          'id',               o.id_local,
          'nombre',           o.local,
          'descripcion',      o.local_descripcion,
          'horario_atencion', o.horario_atencion,
          'coordenadas',      o.coordenadas,
          'direccion',        o.direccion,
          'pais',             o.pais,
          'provincia',        o.provincia,
          'foto',             o.foto_local
        ),

        'entidad', jsonb_build_object(
          'id',                             o.id_entidad,
          'denominacion',                   o.entidad,
          'direccion',                      o.entidad_direccion,
          'telefono',                       o.entidad_telefono,
          'horas_anticipacion_cancelacion', o.horas_anticipacion_cancelacion
        )
      )
      order by o.rn
    ), '[]'::jsonb) as items,
    count(*)::integer as total
  from ordenado o
),
nomenclador as (
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id',     ta.id,
             'codigo', ta.codigo,
             'nombre', ta.nombre
           )
           -- `false` va antes que `true`: "General" es el cajon de sastre, no
           -- una categoria que el cliente busque, asi que va al final.
           order by (ta.codigo = 'general'), lower(ta.nombre)
         ), '[]'::jsonb) as categorias
  from flow.nom_tipo_actividad_servicio ta
  where ta.activo
    and btrim(ta.nombre) <> ''
)
select jsonb_build_object(
  'items',       p.items,
  'total',       p.total,
  -- Contrato de paginacion completo aunque hoy no se use (ver cabecera).
  'has_more',    false,
  'next_cursor', null,
  'metadata',    jsonb_build_object('categorias', n.categorias),
  'colecciones',  flow.colecciones_activas(),
  'patrocinados', flow.campanas_activas(),
  'contadores',  jsonb_build_object(
    'notificaciones', (
      select count(*)::integer
      from flow.notificaciones no
      where no.uuid_usuario = auth.uid()
        and not no.leida
    ),
    'reservas', (
      -- Mismo WHERE que `cliente_obtener_agendas` + el filtro del provider:
      -- el OR importa, porque reservar para un tercero crea una fila que debe
      -- contar para quien la hizo.
      select count(*)::integer
      from flow.agenda a
      where (a.uuid_usuario = auth.uid() or a.reservado_por = auth.uid())
        and a.id_estado = 1
    )
  )
)
from pagina p, nomenclador n;
$function$;

-- ---------------------------------------------------------------------------
-- 3. Permisos.
--    `create or replace` de una funcion NUEVA deja el EXECUTE que Supabase
--    concede por privilegios por defecto a `authenticated` (y a veces `anon`).
--    El idioma de esta base es cerrar explicito y conceder a quien lo necesita.
-- ---------------------------------------------------------------------------
revoke all on function flow.cliente_home_feed(text, integer, text, integer, boolean)
  from public, anon;
grant execute on function flow.cliente_home_feed(text, integer, text, integer, boolean)
  to authenticated, service_role;

notify pgrst, 'reload schema';

-- ============================================================================
-- 4. Verificacion (ejecutar despues; todo debe dar lo indicado)
-- ============================================================================
-- 4.a La funcion existe, es INVOKER y STABLE.
--     Esperado: 1 fila, definer = false, volatilidad = 's'.
-- select p.proname, p.prosecdef as definer, p.provolatile as volatilidad
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'flow' and p.proname = 'cliente_home_feed';
--
-- 4.b Permisos. Esperado: anon = false, authenticated = true.
-- select has_function_privilege('anon',
--          'flow.cliente_home_feed(text, integer, text, integer, boolean)', 'execute') as anon_puede,
--        has_function_privilege('authenticated',
--          'flow.cliente_home_feed(text, integer, text, integer, boolean)', 'execute') as auth_puede;
--
-- 4.c El feed responde y trae las claves esperadas.
--     Esperado: items = 7, total = 7, categorias = 14 (las 14 activas;
--     "Todas" lo anade la app, aqui no van 15), has_more = false.
-- select jsonb_array_length(flow.cliente_home_feed() -> 'items')       as items,
--        (flow.cliente_home_feed() ->> 'total')::int                  as total,
--        jsonb_array_length(flow.cliente_home_feed() -> 'metadata' -> 'categorias') as categorias,
--        flow.cliente_home_feed() -> 'has_more'                       as has_more;
--
-- 4.d Los filtros, con los valores que HOY tiene la base.
--     Esperado: 3, 3, 7, 0, 0.
--     Nota: el nomenclador guarda la provincia como "Villa Clara Province", no
--     "Villa Clara"; la comparacion es exacta (igual que en la app), asi que
--     pasar 'Villa Clara' a secas devuelve 0. Es correcto, no un fallo.
-- select jsonb_array_length(flow.cliente_home_feed(p_query => 'pestanas') -> 'items') as por_texto,
--        jsonb_array_length(flow.cliente_home_feed(p_query => 'PESTANAS') -> 'items') as por_texto_sin_acentos,
--        jsonb_array_length(flow.cliente_home_feed(p_id_categoria => 8)   -> 'items') as por_categoria,
--        jsonb_array_length(flow.cliente_home_feed(p_provincia => 'Villa Clara Province') -> 'items') as por_provincia,
--        jsonb_array_length(flow.cliente_home_feed(p_query => 'barber')   -> 'items') as inexistente;
--
--     Y que un comodin escrito por el usuario sea literal:
--     Esperado: 0 y 0 (con `like` habrian devuelto 7 y 7).
-- select jsonb_array_length(flow.cliente_home_feed(p_query => '%') -> 'items') as comodin_pct,
--        jsonb_array_length(flow.cliente_home_feed(p_query => '_') -> 'items') as comodin_guion;
--
-- 4.e `ta.nombre` viaja en cada item (era la segunda lectura que se elimina).
--     Esperado: 0 filas (ningun item sin nombre de categoria).
-- select count(*) as items_sin_categoria
--   from jsonb_array_elements(flow.cliente_home_feed() -> 'items') it
--  where coalesce(btrim(it ->> 'categoria_nombre'), '') = '';
--
-- 4.f Cada item trae la forma anidada que el cliente ya sabe leer.
--     Esperado: 0 y 0 (ningun item sin nombre de servicio ni de local).
-- select count(*) as sin_nombre_servicio
--   from jsonb_array_elements(flow.cliente_home_feed() -> 'items') it
--  where coalesce(btrim(it -> 'servicio' ->> 'nombre'), '') = '';
-- select count(*) as sin_nombre_local
--   from jsonb_array_elements(flow.cliente_home_feed() -> 'items') it
--  where coalesce(btrim(it -> 'local' ->> 'nombre'), '') = '';
--
--     Y que `tipo_actividad` viaje como objeto (es lo que lee Servicio.fromJson):
--     Esperado: 0 filas.
-- select count(*) as sin_codigo_tipo
--   from jsonb_array_elements(flow.cliente_home_feed() -> 'items') it
--  where it -> 'servicio' -> 'tipo_actividad' is null;
--
-- 4.g Sin sesion los contadores son 0, no un error.
--     Esperado: notificaciones = 0, reservas = 0 (auth.uid() es NULL aqui).
-- select flow.cliente_home_feed() -> 'contadores' as contadores;
-- ============================================================================