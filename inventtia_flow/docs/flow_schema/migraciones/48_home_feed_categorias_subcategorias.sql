-- ============================================================================
-- MIGRACION 48: el Home del cliente entiende CATEGORIA y SUBCATEGORIA
--
-- DEPENDE DE: 47_categorias_reales_subcategorias.sql (anade `id_padre` y
--   `orden` al nomenclador). Sin la 47 esta creacion falla: el cuerpo referencia
--   `ta.id_padre` y `ta.orden`.
--
-- QUE CAMBIA RESPECTO DE 35_home_feed.sql
--   1. Nuevo parametro `p_id_subcategoria`. Filtrar por una subcategoria es
--      `s.id_tipo_actividad = p_id_subcategoria`; filtrar por una categoria
--      incluye sus subcategorias (`s.id_tipo_actividad = p_id_categoria OR
--      ta.id_padre = p_id_categoria`). Esa segunda condicion es la clave: sin
--      ella, tocar "Belleza" en el riel no devolveria los servicios que viven en
--      "Uñas / Manicure".
--   2. El item emite `categoria_codigo`/`categoria_nombre` (el PADRE) y
--      `subcategoria_codigo`/`subcategoria_nombre` (la HOJA). Si la hoja no
--      tiene padre, la categoria es la propia hoja y no hay subcategoria.
--   3. `servicio.tipo_actividad.codigo` SIGUE SIENDO EL CODIGO DE LA HOJA.
--      Es obligatorio: `LocalServicio.esTransporteOmnibus` compara ese valor con
--      'transporte_omnibus'. Cambiarlo ahi por el codigo del padre romperia el
--      flujo de pasajes en la app.
--   4. `metadata.categorias` pasa de lista plana a raices con `subcategorias`
--      anidadas, para que el Home pueda pintar los chips sin una segunda
--      lectura.
--
-- POR QUE SE ELIMINA LA FIRMA VIEJA
--   Anadir `p_id_subcategoria` con `create or replace` habria creado una
--   SEGUNDA funcion (5 y 6 argumentos) y PostgREST respondería "Could not choose
--   the best candidate function". Con el `drop` previo queda una sola firma; los
--   llamadores actuales siguen funcionando porque el parametro nuevo tiene
--   DEFAULT.
--
-- REVERSION
--   Ejecutar de nuevo 35_home_feed.sql (recrea la firma de 5 argumentos), o
--   simplemente `drop function if exists
--   flow.cliente_home_feed(text, integer, text, integer, boolean, integer);`
--   y volver a crear la version de la migracion 35.
-- ============================================================================

drop function if exists flow.cliente_home_feed(text, integer, text, integer, boolean);

create or replace function flow.cliente_home_feed(
  p_query text default null,
  p_id_categoria integer default null,
  p_provincia text default null,
  p_id_coleccion integer default null,
  p_mejor_valorados boolean default false,
  p_id_subcategoria integer default null
)
returns jsonb
language sql
stable
security invoker
set search_path = flow, public
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
    -- [42] estado del par y modo de gestion
    ls.activo                      as ls_activo,
    ls.solo_turnos,
    ls.sin_tramos,
    s.id                           as id_servicio,
    s.nombre                       as servicio,
    s.descripcion                  as descripcion,
    s.foto                         as foto_servicio,
    -- [42]
    s.activo                       as servicio_activo,
    s.campos_adicionales,
    s.permite_tercero,
    s.config_precio,
    s.id_tipo_actividad,
    -- [47] La fila a la que apunta el servicio es la HOJA: o una subcategoria
    -- (con padre) o una categoria raiz. Se traen las dos cosas para poder emitir
    -- categoria y subcategoria por separado.
    ta.codigo                      as actividad_codigo,
    ta.nombre                      as actividad_nombre,
    ta.id_padre                    as actividad_id_padre,
    ta.activo                      as actividad_activa,
    tp.codigo                      as padre_codigo,
    tp.nombre                      as padre_nombre,
    tp.activo                      as padre_activo,
    l.id                           as id_local,
    l.nombre                       as local,
    l.descripcion                  as local_descripcion,
    l.horario_atencion,
    -- [42] horario estructurado (punto 10)
    l.horario_detalle,
    -- [42]
    l.activo                       as local_activo,
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
  -- [47] El padre. Solo existe cuando el servicio esta en una subcategoria.
  left join flow.nom_tipo_actividad_servicio tp on tp.id = ta.id_padre
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
  where
    -- [47] Filtrar por categoria incluye sus subcategorias.
    (
      p_id_categoria is null
      or s.id_tipo_actividad = p_id_categoria
      or ta.id_padre = p_id_categoria
    )
    -- [47] La subcategoria manda sobre la categoria: si llegan las dos, el
    -- resultado son los servicios de esa subcategoria concreta.
    and (p_id_subcategoria is null or s.id_tipo_actividad = p_id_subcategoria)
    and (p_id_coleccion is null or cs.id_coleccion is not null)
    -- [42] EL filtro del punto 3/4/8: lo que no esta publicado no existe para
    -- el cliente. Se evalua antes que el resto para descartar temprano.
    and flow._ls_disponible(ls.id)
    -- Provincia: comparacion exacta sin acentos, igual que hoy en la app.
    -- No se usa unaccent aqui a proposito: la app tampoco lo hace.
    and (
      p_provincia is null
      or btrim(p_provincia) = ''
      or lower(btrim(l.provincia)) = lower(btrim(p_provincia))
    )
    -- `strpos` en vez de `like`: un `%` escrito por el usuario es un caracter
    -- literal, no un comodin. Asi el comportamiento es identico al `contains`
    -- de Dart. [47] Se busca tambien en la categoria padre.
    and (
      b.q is null
      or strpos(
           unaccent(lower(
             coalesce(s.nombre, '') || ' ' ||
             coalesce(l.nombre, '') || ' ' ||
             coalesce(nullif(btrim(ta.nombre), ''),
                      replace(coalesce(ta.codigo, ''), '_', ' '),
                      'General') || ' ' ||
             coalesce(nullif(btrim(tp.nombre), ''), '')
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
        -- [42] mismo estado que `cliente_obtener_servicios`, para que el modelo
        -- Dart lo lea igual venga del feed o del catalogo.
        'activo',                  o.ls_activo,
        'solo_turnos',             o.solo_turnos,
        'sin_tramos',              o.sin_tramos,

        -- Extras del feed (no venian en `cliente_obtener_servicios`).
        'rating',         o.rating,
        'total_resenas',  o.total_resenas,
        -- [47] Categoria = padre cuando existe; si la hoja es raiz, ella misma.
        'categoria_codigo', coalesce(o.padre_codigo, o.actividad_codigo),
        -- Se emite la categoria SOLO si esta activa. Con la categoria apagada
        -- queda NULL y el cliente cae a su respaldo (el codigo legible), que es
        -- lo que hacia antes: el nomenclador activo no la conocia.
        'categoria_nombre', case
                              when coalesce(o.padre_activo, o.actividad_activa)
                                then nullif(btrim(coalesce(o.padre_nombre, o.actividad_nombre)), '')
                              else null
                            end,
        -- [47] Subcategoria: solo si la hoja cuelga de una categoria. Se exige
        -- que la hoja este activa: una subcategoria desactivada deja de existir
        -- para el cliente aunque su categoria siga encendida.
        'subcategoria_codigo', case
                                 when o.actividad_id_padre is null then null
                                 when o.actividad_activa then o.actividad_codigo
                                 else null
                               end,
        'subcategoria_nombre', case
                                 when o.actividad_id_padre is null then null
                                 when o.actividad_activa
                                   then nullif(btrim(o.actividad_nombre), '')
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
          -- [42]
          'activo',             o.servicio_activo,
          -- [47] OJO: `codigo` es el de la HOJA (puede ser una subcategoria).
          -- `LocalServicio.esTransporteOmnibus` depende de que 'transporte_omnibus'
          -- siga llegando aqui. `id_padre` viaja para que el cliente pueda
          -- resolver la categoria sin otra consulta.
          'tipo_actividad', jsonb_build_object(
            'id',       o.id_tipo_actividad,
            'codigo',   o.actividad_codigo,
            'nombre',   o.actividad_nombre,
            'id_padre', o.actividad_id_padre
          )
        ),

        'local', jsonb_build_object(
          'id',               o.id_local,
          'nombre',           o.local,
          'descripcion',      o.local_descripcion,
          'horario_atencion', o.horario_atencion,
          -- [42]
          'horario_detalle',  o.horario_detalle,
          'coordenadas',      o.coordenadas,
          'direccion',        o.direccion,
          'pais',             o.pais,
          'provincia',        o.provincia,
          'foto',             o.foto_local,
          -- [42]
          'activo',           o.local_activo
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
  -- [47] Solo raices activas. Cada una lleva sus subcategorias activas
  -- anidadas: el Home pinta el riel y, al tocar una categoria, los chips de
  -- debajo sin pedir nada mas.
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id',     ta.id,
             'codigo', ta.codigo,
             'nombre', ta.nombre,
             'id_padre', null,
             'subcategorias', coalesce((
               select jsonb_agg(
                        jsonb_build_object(
                          'id',       h.id,
                          'codigo',   h.codigo,
                          'nombre',   h.nombre,
                          'id_padre', h.id_padre
                        )
                        order by h.orden, lower(h.nombre)
                      )
               from flow.nom_tipo_actividad_servicio h
               where h.id_padre = ta.id
                 and h.activo
                 and btrim(h.nombre) <> ''
             ), '[]'::jsonb)
           )
           order by ta.orden, lower(ta.nombre)
         ), '[]'::jsonb) as categorias
  from flow.nom_tipo_actividad_servicio ta
  where ta.activo
    and ta.id_padre is null
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

revoke all on function flow.cliente_home_feed(text, integer, text, integer, boolean, integer)
  from public, anon;
grant execute on function flow.cliente_home_feed(text, integer, text, integer, boolean, integer)
  to authenticated, service_role;

-- ============================================================================
-- 2. `cliente_obtener_servicios`: la hoja viaja con su padre
--
--   Misma funcion, mismos parametros y el mismo cuerpo: solo se anade
--   `id_padre` y `nombre` al objeto `tipo_actividad`. Es puramente aditivo, asi
--   que `create or replace` no rompe a nadie y los grants se conservan.
--
--   Hace falta porque el detalle del servicio, el catalogo y la vista de
--   marketing del local usan este RPC (no el feed) para leer los servicios, y
--   sin `id_padre` no pueden saber si `codigo` es una categoria o una
--   subcategoria.
-- ============================================================================
create or replace function flow.cliente_obtener_servicios(
  p_id_local integer default null,
  p_id_servicio integer default null,
  p_id_entidad integer default null,
  p_nombre_local text default null,
  p_nombre_servicio text default null,
  p_pais text default null,
  p_provincia text default null,
  p_incluir_inactivos boolean default false
)
returns jsonb
language sql
stable
security invoker
set search_path = flow, public
as $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id_local_servicio',       ls.id,
        'created_at',              ls.created_at,
        'permite_reserva_directa', ls.permite_reserva_directa,
        'cantidad_default',        ls.cantidad_default,
        'cantidad_max_capacidad',  ls.cantidad_max_capacidad,
        -- [42] Estado y modo del par, para pintar chips y atenuar en el admin.
        'activo',                  ls.activo,
        'solo_turnos',             ls.solo_turnos,
        'sin_tramos',              ls.sin_tramos,
        'servicio', jsonb_build_object(
          'id',                 s.id,
          'nombre',             s.nombre,
          'descripcion',        s.descripcion,
          'foto',               s.foto,
          'campos_adicionales', s.campos_adicionales,
          'permite_tercero',    s.permite_tercero,
          'config_precio',      s.config_precio,
          'id_tipo_actividad', s.id_tipo_actividad,
          -- [42]
          'activo',             s.activo,
          -- [47] `id_padre` y `nombre`: la app resuelve con ellos si el codigo
          -- es una categoria (padre null) o una subcategoria.
          'tipo_actividad', case when ta.id is null then null else jsonb_build_object(
            'id',       ta.id,
            'codigo',   ta.codigo,
            'nombre',   ta.nombre,
            'id_padre', ta.id_padre
          ) end
        ),
        'local', jsonb_build_object(
          'id',               l.id,
          'nombre',           l.nombre,
          'descripcion',      l.descripcion,
          'horario_atencion', l.horario_atencion,
          -- [42] Horario estructurado del punto 10.
          'horario_detalle',  l.horario_detalle,
          'coordenadas',      l.coordenadas,
          'direccion',        l.direccion,
          'pais',             l.pais,
          'provincia',        l.provincia,
          'foto',             l.foto,
          -- [42]
          'activo',           l.activo
        ),
        'entidad', case when en.id is null then null else jsonb_build_object(
          'id',                           en.id,
          'denominacion',                 en.denominacion,
          'direccion',                    en.direccion,
          'telefono',                     en.telefono,
          'horas_anticipacion_cancelacion', en.horas_anticipacion_cancelacion
        ) end
      )
      order by l.nombre, s.nombre
    ),
    '[]'::jsonb
  )
  from flow.local_servicio ls
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  left join flow.nom_tipo_actividad_servicio ta on ta.id = s.id_tipo_actividad
  join flow.app_dat_locales   l on l.id = ls.id_local
  left join flow.entidad     en on en.id = l.id_entidad
  where (p_id_local        is null or ls.id_local    = p_id_local)
    and (p_id_servicio     is null or ls.id_servicio = p_id_servicio)
    and (p_id_entidad      is null or l.id_entidad   = p_id_entidad)
    and (p_nombre_local    is null or l.nombre    ilike '%' || p_nombre_local    || '%')
    and (p_nombre_servicio is null or s.nombre    ilike '%' || p_nombre_servicio || '%')
    and (p_pais            is null or l.pais      ilike '%' || p_pais            || '%')
    and (p_provincia       is null or l.provincia ilike '%' || p_provincia       || '%')
    -- [42] La única regla de visibilidad. `p_incluir_inactivos` la salta para el
    -- admin; el resto del mundo ve exactamente lo reservable.
    and (p_incluir_inactivos or flow._ls_disponible(ls.id));
$function$;

notify pgrst, 'reload schema';

-- ============================================================================
-- VERIFICACION
--   Con la taxonomia real el nomenclador debe traer 6 raices y 5 hijas cada
--   una. El filtro por categoria tiene que incluir los servicios de sus
--   subcategorias: cambiar 10 por el id de 'belleza' debe devolver los 3
--   servicios de uñas/cejas.
-- ============================================================================
select jsonb_array_length(
         (flow.cliente_home_feed() -> 'metadata' -> 'categorias')
       ) as categorias_raiz,
       (
         select coalesce(sum(jsonb_array_length(c -> 'subcategorias')), 0)
         from jsonb_array_elements(
                flow.cliente_home_feed() -> 'metadata' -> 'categorias'
              ) c
       ) as subcategorias_activas;

select (flow.cliente_home_feed() -> 'total')::integer as total_sin_filtro,
       (
         select count(*)::integer
         from jsonb_array_elements(flow.cliente_home_feed() -> 'items') i
         where i ? 'subcategoria_codigo' and i ->> 'subcategoria_codigo' is not null
       ) as items_con_subcategoria;
