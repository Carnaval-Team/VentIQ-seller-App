-- ============================================================================
-- MIGRACION 55: el admin de entidad ya NO gestiona la taxonomia; solo decide
--               que categorias oculta para SUS servicios
-- ============================================================================
--
-- REGLA DE NEGOCIO (definida por el dueño del producto)
--   1. Crear, editar, eliminar y desactivar categorias es EXCLUSIVO del
--      superadmin (`ventiq_superadmin`). El panel del admin de entidad
--      (`inventtia_flow`) ya no los ofrece.
--   2. Lo que el admin de entidad SI puede hacer es **ocultar** una categoria
--      para su propia entidad. Ocultar NO toca el nomenclador: la categoria
--      sigue activa y sigue pintada en el riel de filtros del Home. Lo unico que
--      cambia es que los servicios/locales de ESA entidad en esa categoria
--      desaparecen del catalogo del cliente.
--   3. Es reversible y por entidad: la entidad A puede ocultar "Belleza" sin
--      afectar a la entidad B.
--
-- QUE HACE ESTA MIGRACION
--   1. Crea `flow.entidad_categoria_oculta` (una fila = la entidad X oculta el
--      nodo Y del nomenclador).
--   2. RLS: solo el admin de la entidad (o el superadmin) ve y cambia sus filas.
--   3. RPC `flow.admin_ocultar_categoria_entidad(...)` para que la app no escriba
--      la tabla a mano.
--   4. Reescribe las DOS lecturas del cliente que muestran servicios para que
--      respeten la ocultacion:
--        * `flow.cliente_home_feed`           -> el Home y las colecciones.
--        * `flow.cliente_obtener_servicios`   -> catalogo y espacio patrocinado.
--
-- POR QUE EL RIEL NO CAMBIA
--   `cliente_home_feed` arma `metadata.categorias` desde
--   `flow.nom_tipo_actividad_servicio` (solo las activas). Esa parte NO se toca:
--   la ocultacion se aplica SOLO a la lista de items. Por eso "ocultar" no quita
--   la categoria del riel, que es exactamente lo pedido.
--
-- DEPENDE DE: 47_categorias_reales_subcategorias.sql (niveles `id_padre` y
--   `orden`) y 48_home_feed_categorias_subcategorias.sql (version actual de los
--   dos RPC del cliente). Los cuerpos de abajo se copiaron de la definicion VIVA
--   en la base, no del archivo, para no revertir nada.
--
-- REVERSION
--   drop function if exists flow.admin_ocultar_categoria_entidad(integer, integer, boolean);
--   drop table if exists flow.entidad_categoria_oculta;
--   -- y volver a ejecutar la seccion 2 de 48_home_feed_categorias_subcategorias.sql
--   -- para dejar los dos RPC del cliente sin el filtro.
--
-- ORDEN DE APLICACION: 54 -> 55 (no depende de la 54, pero se numeran en orden).
-- ============================================================================

-- ============================================================================
-- 1. TABLA: que categorias oculta cada entidad para si misma
-- ============================================================================
--   `id_tipo_actividad` puede ser una categoria raiz o una subcategoria:
--     * raiz        -> oculta los servicios de la raiz Y los de todas sus
--                      subcategorias (la comparacion es contra la hoja y contra
--                      su padre; ver seccion 4).
--     * subcategoria -> oculta solo los servicios de esa subcategoria.
--   No se valida en un CHECK porque la jerarquia vive en otra tabla; lo valida
--   el RPC de la seccion 3.
-- ============================================================================
create table if not exists flow.entidad_categoria_oculta (
  id_entidad        integer not null,
  id_tipo_actividad integer not null,
  created_at        timestamptz not null default now(),
  constraint entidad_categoria_oculta_pkey
    primary key (id_entidad, id_tipo_actividad),
  constraint entidad_categoria_oculta_entidad_fkey
    foreign key (id_entidad) references flow.entidad(id) on delete cascade,
  constraint entidad_categoria_oculta_tipo_fkey
    foreign key (id_tipo_actividad)
    references flow.nom_tipo_actividad_servicio(id) on delete cascade
);

comment on table flow.entidad_categoria_oculta is
  'Categorias que una entidad oculta para SI MISMA. No cambia el nomenclador ni '
  'el riel del Home: solo saca del catalogo del cliente los servicios de esa '
  'entidad en la categoria oculta (y en sus subcategorias, si se oculto la raiz).';

comment on column flow.entidad_categoria_oculta.id_tipo_actividad is
  'Nodo del nomenclador (categoria raiz o subcategoria) que la entidad oculta.';

create index if not exists idx_entidad_categoria_oculta_tipo
  on flow.entidad_categoria_oculta (id_tipo_actividad);

-- ============================================================================
-- 2. RLS: cada admin solo ve y cambia lo de SUS entidades
-- ============================================================================
--   `flow.is_entidad_admin(p_id_entidad)` ya resuelve owner + `entidad_admin`
--   contra `auth.uid()`. Se anade el superadmin por coherencia con el resto.
--   No hay politica de UPDATE: se oculta con INSERT y se muestra con DELETE, la
--   pareja es la clave primaria.
-- ============================================================================
alter table flow.entidad_categoria_oculta enable row level security;

drop policy if exists "entidad_categoria_oculta_select" on flow.entidad_categoria_oculta;
drop policy if exists "entidad_categoria_oculta_insert" on flow.entidad_categoria_oculta;
drop policy if exists "entidad_categoria_oculta_delete" on flow.entidad_categoria_oculta;

create policy "entidad_categoria_oculta_select"
on flow.entidad_categoria_oculta
for select
to authenticated
using (
  public.fn_is_superadmin_full_access()
  or flow.is_entidad_admin(id_entidad)
);

create policy "entidad_categoria_oculta_insert"
on flow.entidad_categoria_oculta
for insert
to authenticated
with check (
  public.fn_is_superadmin_full_access()
  or flow.is_entidad_admin(id_entidad)
);

create policy "entidad_categoria_oculta_delete"
on flow.entidad_categoria_oculta
for delete
to authenticated
using (
  public.fn_is_superadmin_full_access()
  or flow.is_entidad_admin(id_entidad)
);

-- `anon` NO se concede: esto es configuracion de administracion, no catalogo.
revoke all on table flow.entidad_categoria_oculta from public, anon;
grant select, insert, delete on table flow.entidad_categoria_oculta
  to authenticated, service_role;

-- ============================================================================
-- 3. RPC: ocultar / mostrar una categoria para una entidad
-- ============================================================================
--   `security invoker`: la autorizacion real la hacen la comprobacion explicita
--   de abajo Y las politicas RLS. La funcion no recibe el uuid del usuario: lo
--   lee de `auth.uid()`.
-- ============================================================================
create or replace function flow.admin_ocultar_categoria_entidad(
  p_id_entidad integer,
  p_id_tipo_actividad integer,
  p_oculto boolean
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = flow, public
as $$
declare
  v_oculto boolean := coalesce(p_oculto, false);
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;

  if not (
    public.fn_is_superadmin_full_access()
    or flow.is_entidad_admin(p_id_entidad)
  ) then
    return jsonb_build_object('ok', false, 'error', 'No administras esa entidad');
  end if;

  if not exists (select 1 from flow.entidad e where e.id = p_id_entidad) then
    return jsonb_build_object('ok', false, 'error', 'Entidad inexistente');
  end if;

  if not exists (
    select 1 from flow.nom_tipo_actividad_servicio t
    where t.id = p_id_tipo_actividad
  ) then
    return jsonb_build_object('ok', false, 'error', 'Categoria inexistente');
  end if;

  if v_oculto then
    if not exists (
      select 1 from flow.entidad_categoria_oculta o
      where o.id_entidad = p_id_entidad
        and o.id_tipo_actividad = p_id_tipo_actividad
    ) then
      insert into flow.entidad_categoria_oculta (id_entidad, id_tipo_actividad)
      values (p_id_entidad, p_id_tipo_actividad);
    end if;
  else
    delete from flow.entidad_categoria_oculta o
    where o.id_entidad = p_id_entidad
      and o.id_tipo_actividad = p_id_tipo_actividad;
  end if;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id_entidad', p_id_entidad,
      'id_tipo_actividad', p_id_tipo_actividad,
      'oculta', v_oculto
    )
  );
end;
$$;

revoke all on function flow.admin_ocultar_categoria_entidad(integer, integer, boolean)
  from public, anon;
grant execute on function flow.admin_ocultar_categoria_entidad(integer, integer, boolean)
  to authenticated, service_role;

comment on function flow.admin_ocultar_categoria_entidad(integer, integer, boolean) is
  'Oculta o vuelve a mostrar una categoria para los servicios de UNA entidad. No '
  'modifica el nomenclador: la categoria sigue en el riel del Home. Solo el admin '
  'de esa entidad (o el superadmin) puede llamarlo.';

-- ============================================================================
-- 4. `cliente_home_feed`: excluir lo que la entidad oculto
-- ============================================================================
--   Misma firma que la 48, asi que `create or replace` no crea una sobrecarga ni
--   rompe los grants. El UNICO cambio respecto de la 48 es el bloque marcado
--   [55]: se compara contra la HOJA (`ta.id`) y contra su PADRE (`ta.id_padre`),
--   de modo que ocultar una raiz esconde tambien sus subcategorias.
--   `metadata.categorias` (el riel) queda intacto a proposito.
-- ============================================================================
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
    -- [55] Lo que la ENTIDAD oculto para si misma. Se compara contra la HOJA y
    -- contra su PADRE: ocultar una categoria raiz esconde tambien los servicios
    -- de sus subcategorias. `l.id_entidad` nulo (dato viejo) nunca casa, asi que
    -- no oculta nada por accidente.
    and not exists (
      select 1
      from flow.entidad_categoria_oculta o
      where o.id_entidad = l.id_entidad
        and (
          o.id_tipo_actividad = ta.id
          or o.id_tipo_actividad = ta.id_padre
        )
    )
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
  -- [55] NO se filtra por `entidad_categoria_oculta`: la categoria oculta sigue
  -- en el riel. Ocultar esconde servicios, no filtros.
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

-- ============================================================================
-- 5. `cliente_obtener_servicios`: el admin sigue viendo TODO lo suyo
-- ============================================================================
--   El parametro `p_incluir_inactivos` es el que ya usa la administracion para
--   ver y reactivar lo desactivado. Aqui se reutiliza con el mismo sentido: con
--   `true` la ocultacion NO aplica (el admin tiene que poder seguir gestionando
--   sus servicios ocultos). El detalle de un servicio por id va por
--   `local_servicio` directo, asi que un enlace guardado sigue funcionando.
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
    and (p_incluir_inactivos or flow._ls_disponible(ls.id))
    -- [55] La ocultacion por entidad. El admin (`p_incluir_inactivos = true`) la
    -- salta: tiene que poder ver y reactivar SUS servicios ocultos.
    and (
      p_incluir_inactivos
      or not exists (
        select 1
        from flow.entidad_categoria_oculta o
        where o.id_entidad = l.id_entidad
          and (
            o.id_tipo_actividad = ta.id
            or o.id_tipo_actividad = ta.id_padre
          )
      )
    );
$function$;

notify pgrst, 'reload schema';

-- ============================================================================
-- 6. VERIFICACION (ejecutar despues de aplicar)
-- ============================================================================
--   a) La tabla y el RPC existen:
--        select to_regclass('flow.entidad_categoria_oculta') as tabla,
--               to_regprocedure(
--                 'flow.admin_ocultar_categoria_entidad(integer,integer,boolean)'
--               ) as rpc;
--
--   b) El riel NO cambia al ocultar (debe dar el mismo numero con y sin filas):
--        select jsonb_array_length(
--                 (flow.cliente_home_feed() -> 'metadata' -> 'categorias')
--               ) as categorias_raiz;
--
--   c) Ocultar de verdad reduce los items (sustituir 1 y 6 por una entidad y una
--      categoria reales):
--        select (flow.cliente_home_feed() -> 'total')::integer as antes;
--        insert into flow.entidad_categoria_oculta (id_entidad, id_tipo_actividad)
--        values (1, 6) on conflict do nothing;
--        select (flow.cliente_home_feed() -> 'total')::integer as despues;
--        delete from flow.entidad_categoria_oculta
--         where id_entidad = 1 and id_tipo_actividad = 6;
--
--   d) El admin sigue viendo todo lo suyo:
--        select jsonb_array_length(
--                 flow.cliente_obtener_servicios(
--                   p_id_entidad => 1, p_incluir_inactivos => true
--                 )
--               ) as admin_ve;
-- ============================================================================
