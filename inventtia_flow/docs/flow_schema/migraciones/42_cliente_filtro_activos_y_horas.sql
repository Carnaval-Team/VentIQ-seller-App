-- ============================================================================
-- 42_cliente_filtro_activos_y_horas.sql
-- ============================================================================
-- QUE HACE
--   1. `cliente_obtener_servicios` → + `p_incluir_inactivos` (default false) y
--      filtra por `_ls_disponible`. Expone `activo` y `horario_detalle`.
--   2. `cliente_home_feed`         → filtra por activos y expone `activo` /
--      `horario_detalle` en el item, en `servicio` y en `local`.
--   3. `cliente_obtener_disponibilidad`        → guard: `[]` si no disponible.
--   4. `cliente_obtener_disponibilidad_transporte` → guard: `turnos: []`.
--   5. `cliente_obtener_fechas_disponibles_transporte` → guard: `[]`.
--   6. Horas del turno (`hora_inicio` / `hora_fin`) en la disponibilidad.
--   7. Triggers `before insert` en `agenda` y `sala_espera`: la última barrera.
--
-- `cliente_ranking_semanal` NO se toca (a propósito)
--   Su cuerpo vivo construye el item cruzando la ventana de `agenda` con
--   `jsonb_array_elements(flow.cliente_home_feed() -> 'items')`. Es decir, hereda
--   el filtro y los campos del feed: al filtrar aquí `cliente_home_feed`, el
--   ranking del Home deja de enseñar pares desactivados sin una línea más.
--   (Comprobado con `pg_get_functiondef`: el cuerpo no menciona `activo` ni la
--   tabla `local_servicio`.)
--
-- POR QUE UN PARAMETRO Y NO UN FILTRO A SECAS EN `cliente_obtener_servicios`
--   Ese RPC es el contrato compartido: lo usan el cliente, la administración de
--   `inventtia_flow` (Planificación, detalle de servicio) y `ventiq_superadmin`
--   (patrocinados y colecciones). Filtrar siempre dejaría al admin sin poder ver
--   —ni reactivar— lo que desactivó. Con `p_incluir_inactivos` (default false)
--   el cliente no cambia de comportamiento y el admin pide explícitamente ver
--   todo. Se hace `drop` + `create` para NO dejar una sobrecarga de 7
--   argumentos: PostgREST no resuelve homónimas y el error saldría en todas las
--   apps (mismo patrón que la migración 18).
--
-- POR QUE `cliente_home_feed` SE REESCRIBE ENTERO
--   La copia del repo (migración 35) está DESACTUALIZADA: la firma viva tiene
--   `p_query, p_id_categoria, p_provincia, p_id_coleccion, p_mejor_valorados`.
--   Este cuerpo se ha copiado de `pg_get_functiondef` en vivo y sólo se le han
--   metido los cambios marcados con `-- [42]`. El resto es idéntico.
--
-- POR QUE TRIGGERS Y NO REESCRIBIR LAS 7 RPC DE RESERVA
--   `cliente_reservar_directo` y `cliente_reservar_pasaje_omnibus` son SECURITY
--   DEFINER y largas; `sala_espera` tiene su propio camino; y `agenda` admite
--   además el insert directo del camino legacy (`AgendaService.crearTicket`).
--   Reescribir todas es donde se cuelan los errores. Un trigger `before insert`
--   es un único punto de paso que cubre TODOS los caminos, incluidos los que
--   nadie recuerda. La UI ya oculta lo inactivo; esto es la red de seguridad.
--
--   Los triggers NO bloquean a:
--     · sesiones sin `auth.uid()` → bots, `service_role`, migraciones;
--     · admins de la entidad dueña    → el mostrador sigue pudiendo reservar.
--   Sólo se rechaza a un cliente autenticado normal.
--
-- REVERSIBILIDAD
--   drop trigger if exists trg_agenda_ls_disponible on flow.agenda;
--   drop trigger if exists trg_sala_espera_ls_disponible on flow.sala_espera;
--   drop function if exists flow._bloquear_reserva_si_no_disponible();
--   drop function if exists flow.cliente_obtener_servicios(int,int,int,text,text,text,text,boolean);
--   y recrear las versiones anteriores de las 5 funciones.
--
-- ORDEN: después de 40 (usa `_ls_disponible` y `_caller_es_admin_de_ls`).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. `cliente_obtener_servicios` con `p_incluir_inactivos`
-- ---------------------------------------------------------------------------
drop function if exists flow.cliente_obtener_servicios(
  integer, integer, integer, text, text, text, text
);

create or replace function flow.cliente_obtener_servicios(
  p_id_local integer default null,
  p_id_servicio integer default null,
  p_id_entidad integer default null,
  p_nombre_local text default null,
  p_nombre_servicio text default null,
  p_pais text default null,
  p_provincia text default null,
  -- [42] false = sólo lo visible para el cliente (comportamiento por defecto).
  --       true  = todo, para la administración (poder ver y reactivar).
  p_incluir_inactivos boolean default false
)
returns jsonb
language sql
stable
set search_path to 'flow', 'public'
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
          'tipo_actividad', case when ta.id is null then null else jsonb_build_object(
            'id', ta.id,
            'codigo', ta.codigo
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

comment on function flow.cliente_obtener_servicios(integer, integer, integer, text, text, text, text, boolean) is
  'Contrato de catalogo compartido cliente/admin/superadmin. Con p_incluir_inactivos=false (default) devuelve solo lo visible y reservable para el cliente.';

-- ---------------------------------------------------------------------------
-- 2. `cliente_home_feed`: filtro de activos + horario_detalle
-- ---------------------------------------------------------------------------
-- Cuerpo copiado de `pg_get_functiondef` en vivo. Los cambios van marcados con
-- `-- [42]`; todo lo demás es idéntico a lo que corre hoy.
create or replace function flow.cliente_home_feed(
  p_query text default null,
  p_id_categoria integer default null,
  p_provincia text default null,
  p_id_coleccion integer default null,
  p_mejor_valorados boolean default false
)
returns jsonb
language sql
stable
set search_path to 'flow', 'public'
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
    -- `ta.nombre` viaja aqui para que el riel de categorias no necesite una
    -- segunda lectura del nomenclador (era el objetivo del Paso 9).
    ta.codigo                      as categoria_codigo,
    ta.nombre                      as categoria_nombre,
    ta.activo                      as categoria_activa,
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
        -- [42] mismo estado que `cliente_obtener_servicios`, para que el modelo
        -- Dart lo lea igual venga del feed o del catalogo.
        'activo',                  o.ls_activo,
        'solo_turnos',             o.solo_turnos,
        'sin_tramos',              o.sin_tramos,

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
          -- [42]
          'activo',             o.servicio_activo,
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

-- `cliente_ranking_semanal` NO se toca: compone sobre `cliente_home_feed() -> 'items'`
-- con un inner join, asi que al filtrar el feed los inactivos desaparecen solos.

-- ---------------------------------------------------------------------------
-- 3. Disponibilidad: sin turnos si el par no esta disponible
-- ---------------------------------------------------------------------------
-- Cuerpo vivo + guard al principio. El admin de la entidad sigue viendo la
-- disponibilidad (mostrador); el cliente recibe `[]` y la UI muestra
-- "sin disponibilidad" en vez de un error.
create or replace function flow.cliente_obtener_disponibilidad(
  p_id_local_servicio integer,
  p_desde date default null,
  p_hasta date default null
)
returns jsonb
language plpgsql
stable
set search_path to 'flow', 'public'
as $function$
declare
  v_desde date;
  v_hasta date;
  v_data  jsonb;
begin
  -- [42] Si no esta publicado, no hay nada que ofrecer al cliente.
  if not coalesce(flow._ls_disponible(p_id_local_servicio), false)
     and not flow._caller_es_admin_de_ls(p_id_local_servicio) then
    return '[]'::jsonb;
  end if;

  v_desde := coalesce(p_desde, (current_timestamp at time zone 'America/Havana')::date);
  v_hasta := coalesce(p_hasta, (current_timestamp at time zone 'America/Havana')::date + 90);

  if not flow._ls_tiene_recursos(p_id_local_servicio) then
    -- ── Camino legacy: cupo por dia desde plan_servicios (formato original) ──
    with por_dia as (
      select (ps.fecha at time zone 'America/Havana')::date as dia,
             sum(ps.cantidad)  as cantidad,
             sum(ps.agendados) as agendados
      from flow.plan_servicios ps
      where ps.id_local_servicio = p_id_local_servicio
        and ps.cantidad is not null
        and (ps.fecha at time zone 'America/Havana')::date between v_desde and v_hasta
      group by (ps.fecha at time zone 'America/Havana')::date
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'fecha',       to_char(pd.dia, 'YYYY-MM-DD'),
             'cantidad',    pd.cantidad,
             'agendados',   pd.agendados,
             'disponibles', pd.cantidad - pd.agendados
           ) order by pd.dia), '[]'::jsonb)
      into v_data
    from por_dia pd
    where pd.cantidad - pd.agendados > 0;

    return v_data;
  end if;

  -- ── Camino recursos: disponibilidad por turno y por dia ──
  with turnos_dia as (
    select
      (pt.fecha at time zone 'America/Havana')::date as dia,
      r.id     as id_recurso,
      r.nombre as recurso,
      r.orden  as r_orden,
      t.id     as id_turno,
      t.nombre as turno,
      t.orden  as t_orden,
      -- [42] horas opcionales del turno (punto 7)
      t.hora_inicio,
      t.hora_fin,
      min(pt.cantidad - pt.agendados)                    as disp,
      count(*)                                           as n_plan,
      (select count(*) from flow.turno_tramo tt2
         where tt2.id_turno = t.id)                      as n_turno
    from flow.turno t
    join flow.recurso r      on r.id = t.id_recurso and r.activo
    join flow.turno_tramo tt on tt.id_turno = t.id
    join flow.tramo tr       on tr.id = tt.id_tramo and tr.activo
    join flow.plan_tramo pt  on pt.id_tramo = tr.id
    where r.id_local_servicio = p_id_local_servicio
      and t.activo
      and (pt.fecha at time zone 'America/Havana')::date between v_desde and v_hasta
    group by dia, r.id, r.nombre, r.orden, t.id, t.nombre, t.orden, t.hora_inicio, t.hora_fin
  ),
  turnos_ok as (
    -- El turno solo cuenta si TODOS sus tramos tienen cupo ese dia y disp > 0.
    select * from turnos_dia
    where n_plan = n_turno and disp > 0
  ),
  por_dia as (
    select
      dia,
      sum(disp) as disponibles,
      jsonb_agg(jsonb_build_object(
        'id_recurso',  id_recurso,
        'recurso',     recurso,
        'id_turno',    id_turno,
        'turno',       turno,
        'disponibles', disp,
        -- [42] "09:00" / "11:00" o null. `to_char` para no mandar "09:00:00".
        'hora_inicio', case when hora_inicio is null then null
                            else to_char(hora_inicio, 'HH24:MI') end,
        'hora_fin',    case when hora_fin is null then null
                            else to_char(hora_fin, 'HH24:MI') end
      ) order by r_orden, id_recurso, t_orden, id_turno) as turnos
    from turnos_ok
    group by dia
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'fecha',       to_char(pd.dia, 'YYYY-MM-DD'),
           'cantidad',    pd.disponibles,   -- agregado (no hay un unico "total")
           'agendados',   0,
           'disponibles', pd.disponibles,
           'turnos',      pd.turnos
         ) order by pd.dia), '[]'::jsonb)
    into v_data
  from por_dia pd
  where pd.disponibles > 0;

  return v_data;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 4. Disponibilidad de transporte: guard + horas del turno
-- ---------------------------------------------------------------------------
-- Se conserva el cuerpo original verbatim y se envuelve en un `case`: es la
-- edicion mas pequeña posible sobre una funcion larga.
create or replace function flow.cliente_obtener_disponibilidad_transporte(
  p_id_local_servicio integer,
  p_fecha date,
  p_tipo_trayecto character varying default null
)
returns jsonb
language sql
stable
set search_path to 'flow', 'public'
as $function$
  select case
    when not coalesce(flow._ls_disponible(p_id_local_servicio), false)
         and not flow._caller_es_admin_de_ls(p_id_local_servicio)
    then jsonb_build_object(
           'ok', false,
           'fecha', to_char(p_fecha, 'YYYY-MM-DD'),
           'turnos', '[]'::jsonb
         )
    else (
  with actividad as (
    select 1
    from flow.local_servicio ls
    join flow.app_dat_servicios s on s.id = ls.id_servicio
    join flow.nom_tipo_actividad_servicio ta on ta.id = s.id_tipo_actividad
    where ls.id = p_id_local_servicio
      and ta.codigo = 'transporte_omnibus'
  ), por_turno as (
    select
      t.id as id_turno,
      r.id as id_recurso,
      r.nombre as recurso,
      t.nombre as turno,
      t.precios,
      tr.tipo_trayecto,
      min(pt.cantidad) as cantidad,
      min(pt.agendados) as agendados,
      min(pt.cantidad - pt.agendados) as disponibles,
      (
        select count(*)::int
        from flow.turno_tramo tt_c
        join flow.tramo tr_c on tr_c.id = tt_c.id_tramo and tr_c.activo
        where tt_c.id_turno = t.id
      ) as num_tramos,
      exists (
        select 1
        from flow.turno_tramo tt_i
        join flow.tramo tr_i on tr_i.id = tt_i.id_tramo and tr_i.activo
        where tt_i.id_turno = t.id and tr_i.tipo_trayecto = 'ida'
      ) and exists (
        select 1
        from flow.turno_tramo tt_v
        join flow.tramo tr_v on tr_v.id = tt_v.id_tramo and tr_v.activo
        where tt_v.id_turno = t.id and tr_v.tipo_trayecto = 'vuelta'
      ) as es_combinado
    from flow.turno t
    join flow.recurso r on r.id = t.id_recurso and r.activo
    join flow.turno_tramo tt on tt.id_turno = t.id
    join flow.tramo tr on tr.id = tt.id_tramo and tr.activo
    join flow.plan_tramo pt on pt.id_tramo = tr.id
    where r.id_local_servicio = p_id_local_servicio
      and t.activo
      and (pt.fecha at time zone 'America/Havana')::date = p_fecha
      and (p_tipo_trayecto is null or tr.tipo_trayecto = p_tipo_trayecto)
    group by t.id, r.id, r.nombre, t.nombre, t.precios, tr.tipo_trayecto
    having count(*) = 1
  )
  select jsonb_build_object(
    'ok', exists(select 1 from actividad),
    'fecha', to_char(p_fecha, 'YYYY-MM-DD'),
    'turnos', coalesce(jsonb_agg(jsonb_build_object(
      'id_turno', id_turno,
      'id_recurso', id_recurso,
      'recurso', recurso,
      'turno', turno,
      'precios', precios,
      'tipo_trayecto', tipo_trayecto,
      'cantidad', cantidad,
      'agendados', agendados,
      'disponibles', disponibles,
      'num_tramos', num_tramos,
      'es_combinado', es_combinado or num_tramos > 1
    ) order by recurso, turno), '[]'::jsonb)
  )
  from por_turno
    )
  end;
$function$;

-- ---------------------------------------------------------------------------
-- 5. Fechas disponibles de transporte: guard
-- ---------------------------------------------------------------------------
create or replace function flow.cliente_obtener_fechas_disponibles_transporte(
  p_id_local_servicio integer,
  p_tipo_trayecto character varying
)
returns jsonb
language sql
stable
set search_path to 'flow', 'public'
as $function$
  select case
    when not coalesce(flow._ls_disponible(p_id_local_servicio), false)
         and not flow._caller_es_admin_de_ls(p_id_local_servicio)
    then '[]'::jsonb
    else (
      select coalesce(jsonb_agg(fecha order by fecha), '[]'::jsonb)
      from (
        select distinct (pt.fecha at time zone 'America/Havana')::date as fecha
        from flow.plan_tramo pt
        join flow.tramo tr on tr.id = pt.id_tramo and tr.activo
        join flow.recurso r on r.id = tr.id_recurso and r.activo
        join flow.turno_tramo tt on tt.id_tramo = tr.id
        join flow.turno t on t.id = tt.id_turno and t.activo
        where r.id_local_servicio = p_id_local_servicio
          and tr.tipo_trayecto = p_tipo_trayecto
          and pt.cantidad > pt.agendados
          and (pt.fecha at time zone 'America/Havana')::date >= current_date
      ) fechas
    )
  end;
$function$;

-- ---------------------------------------------------------------------------
-- 6. Ultima barrera: no se reserva ni se entra en cola de algo no publicado
-- ---------------------------------------------------------------------------
create or replace function flow._bloquear_reserva_si_no_disponible()
returns trigger
language plpgsql
set search_path to 'flow', 'public'
as $function$
begin
  -- Sin sesion (bots, service_role, migraciones) no se bloquea nada.
  if auth.uid() is null then
    return new;
  end if;

  -- El admin de la entidad sigue pudiendo reservar/encolar desde el mostrador.
  if flow._caller_es_admin_de_ls(new.id_local_servicio) then
    return new;
  end if;

  if not coalesce(flow._ls_disponible(new.id_local_servicio), false) then
    raise exception using
      errcode = 'P0001',
      message = 'LS_NO_DISPONIBLE',
      detail  = 'local_servicio=' || new.id_local_servicio,
      hint    = 'Este servicio no esta disponible para reservar en este momento.';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_agenda_ls_disponible on flow.agenda;
create trigger trg_agenda_ls_disponible
  before insert on flow.agenda
  for each row execute function flow._bloquear_reserva_si_no_disponible();

drop trigger if exists trg_sala_espera_ls_disponible on flow.sala_espera;
create trigger trg_sala_espera_ls_disponible
  before insert on flow.sala_espera
  for each row execute function flow._bloquear_reserva_si_no_disponible();

-- ---------------------------------------------------------------------------
-- 7. Verificacion posterior (ejecutar a mano)
-- ---------------------------------------------------------------------------
-- 7.a Con todo activo, el feed y el catalogo no cambian de tamaño.
-- select jsonb_array_length(flow.cliente_home_feed() -> 'items');
-- select jsonb_array_length(flow.cliente_obtener_servicios());
--
-- 7.b El admin sigue viendo todo (incluye lo inactivo).
-- select jsonb_array_length(flow.cliente_obtener_servicios(p_incluir_inactivos => true));
--
-- 7.c No quedan sobrecargas de 7 argumentos: esperado 1 fila.
-- select pg_get_function_identity_arguments(p.oid)
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'flow' and p.proname = 'cliente_obtener_servicios';
--
-- 7.d Los triggers existen.
-- select tgname from pg_trigger t
--   join pg_class c on c.oid = t.tgrelid
--   join pg_namespace n on n.oid = c.relnamespace
--  where n.nspname = 'flow' and not t.tgisinternal
--    and tgname in ('trg_agenda_ls_disponible', 'trg_sala_espera_ls_disponible');
--
-- 7.e Prueba de humo del filtro: desactivar UN local_servicio y comprobar que
--     desaparece del feed y que la disponibilidad responde [] (como cliente,
--     no como admin).
-- ============================================================================