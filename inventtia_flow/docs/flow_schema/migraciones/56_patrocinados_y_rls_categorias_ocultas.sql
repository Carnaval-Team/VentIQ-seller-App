-- ════════════════════════════════════════════════════════════════════════════
-- 56 · Tres fallos que destapó la prueba real de la 55
--
-- CONTEXTO
--   La 55 dejó la ocultación por entidad de categorías. Al probarla en vivo se
--   vieron tres agujeros que este archivo cierra. Ninguno rompía el
--   `create or replace` de la 55: son de SEMÁNTICA, por eso no los detecta ni
--   el analizador ni un `select` de humo.
--
-- ── FALLO 1 · los patrocinados se saltaban la ocultación ───────────────────
--   `flow.cliente_home_feed` publicaba `'patrocinados', flow.campanas_activas()`
--   tal cual, sin pasar por `entidad_categoria_oculta`. Resultado: la entidad
--   ocultaba una categoría, desaparecía del catálogo… pero su servicio seguía
--   saliendo en el carrusel de patrocinados del Home (y en el espacio
--   patrocinado), porque una campaña apunta a un `local_servicio` concreto y
--   nadie miraba si esa categoría estaba oculta.
--
--   Se arregla en `flow.campanas_activas()`, que es la única fuente de "qué
--   patrocinados enseño al cliente". Sus dos únicos consumidores son de cara al
--   cliente (`cliente_home_feed` y `CampanaService.activas()` de la app), así
--   que el filtro va ahí y no hay que reescribir el feed entero.
--   (Comprobado: `public.fn_marketing_dashboard_resumen` no llama a esta
--   función; su `'campanas_activas'` es un alias de columna sobre
--   `app_mkt_campanas`.)
--
-- ── FALLO 2 · RLS dejaba al cliente leer CERO filas ────────────────────────
--   `flow.entidad_categoria_oculta` tiene RLS con una política de SELECT que
--   solo deja ver las filas a `fn_is_superadmin_full_access()` o al admin de la
--   entidad. Pero las dos funciones que aplican el filtro
--   (`cliente_home_feed` y `cliente_obtener_servicios`) son **SECURITY INVOKER**
--   (`prosecdef = false`): corren con los permisos de quien llama.
--
--   Consecuencia, y es el fallo silencioso de verdad: cuando el que llama es un
--   cliente normal, el `not exists (select 1 from flow.entidad_categoria_oculta …)`
--   ve **cero filas**, así que el `not exists` es SIEMPRE verdadero y no se
--   oculta nada. Al admin, en cambio, le funciona (por eso la pantalla de
--   Categorías se ve bien y la prueba "en caliente" engaña).
--
--   La tabla no guarda nada privado: es una preferencia de escaparate ("esta
--   entidad no quiere enseñar esta categoría"). Lo único sensible es ESCRIBIRLA,
--   y eso se queda como está. El SELECT pasa a ser libre para `anon` y
--   `authenticated`, que son justo los roles que pueden ejecutar las funciones
--   del catálogo.
--   `cliente_obtener_servicios` está concedida también a `anon`, así que hace
--   falta además el GRANT de tabla: una política por sí sola no basta si el rol
--   no tiene permiso sobre la tabla.
--
-- ── FALLO 3 · las tarjetas de colección tampoco filtraban ──────────────────
--   `flow.colecciones_activas()` cuenta y publica los ids de todas las filas de
--   `coleccion_servicio`. El detalle de la colección sí pasa por el feed (y por
--   tanto sí filtra), así que la tarjeta del Home anunciaba "2 servicios" y al
--   entrar listaba 1, además de exponer el id de un servicio oculto. Va en el
--   bloque 3.
--
--   Los tres fallos son de la misma familia: superficies que enseñan un
--   servicio sin pasar por `entidad_categoria_oculta`. Al arreglar el de los
--   patrocinados se revisaron los otros dos sitios donde el Home resuelve un
--   servicio por su cuenta.
--
-- QUÉ NO CAMBIA
--   * `metadata.categorias` del feed (el riel) sigue SIN filtrarse: ocultar
--     esconde servicios, no filtros. Es lo que se pidió en la 55.
--   * Las políticas de INSERT y DELETE siguen restringidas a superadmin / admin
--     de la entidad. Ocultar es del admin; el catálogo de categorías, del
--     superadmin.
--   * `p_incluir_inactivos = true` sigue saltándose la ocultación, así que el
--     admin ve sus servicios aunque estén ocultos.
--
-- ORDEN
--   Aplicar DESPUÉS de la 55. Es idempotente.
-- ════════════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────────
-- 1 · RLS: que el cliente pueda LEER la lista de ocultos
-- ───────────────────────────────────────────────────────────────────────────
-- Se recrea la política de SELECT para `anon` y `authenticated`. Es una
-- política permisiva y con `using (true)`: la lectura no revela nada que el
-- propio catálogo no vaya a exponer igual (el servicio oculto simplemente no
-- aparece). Escribir sigue cerrado, ver el bloque 3.

alter table flow.entidad_categoria_oculta enable row level security;

drop policy if exists entidad_categoria_oculta_select on flow.entidad_categoria_oculta;
create policy entidad_categoria_oculta_select
  on flow.entidad_categoria_oculta
  for select
  to anon, authenticated
  using (true);

comment on policy entidad_categoria_oculta_select on flow.entidad_categoria_oculta is
  '[56] Lectura abierta a anon/authenticated a proposito: cliente_home_feed y '
  'cliente_obtener_servicios son SECURITY INVOKER y leen esta tabla con los '
  'permisos de quien llama. Con la politica restringida de la 55 un cliente '
  'veia cero filas y la ocultacion no se aplicaba. Datos no sensibles.';

-- Permiso de tabla para `anon`: sin esto la política no sirve de nada.
-- `cliente_obtener_servicios` está concedida a `anon`, así que el camino
-- anónimo del catálogo también tiene que poder leer los ocultos.
revoke all on flow.entidad_categoria_oculta from anon;
grant select on flow.entidad_categoria_oculta to anon;

-- `authenticated` ya tenía select/insert/delete de la 55: se repiten por si
-- esta migración se aplica suelta y para dejar el estado explícito.
grant select, insert, delete on flow.entidad_categoria_oculta to authenticated;

-- ───────────────────────────────────────────────────────────────────────────
-- 2 · Patrocinados: la campaña que apunta a un servicio oculto no se ofrece
-- ───────────────────────────────────────────────────────────────────────────
-- Copia exacta de la definición viva (misma firma, `stable`, mismo
-- `search_path`, sin `security definer`) + el join a la taxonomía y el
-- `not exists` final. Las claves del JSON no cambian: los patrocinados siguen
-- llegando al Home con la misma forma.
--
-- Nota: una campaña de ENTIDAD (sin `local_servicio`) deja `l.id_entidad` en
-- null, el `not exists` es verdadero y la campaña se conserva. Sin local no hay
-- categoría que ocultar, y descartarla sería inventarse una regla.

create or replace function flow.campanas_activas()
returns jsonb
language sql
stable
security invoker
set search_path to 'flow', 'public'
as $function$
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
    -- [56] Hace falta la hoja del servicio para poder compararla con lo oculto.
    left join flow.nom_tipo_actividad_servicio ta on ta.id = s.id_tipo_actividad
    left join flow.entidad          en on en.id = coalesce(l.id_entidad, c.id_entidad)
    where c.activo
      and (c.desde is null or (now() at time zone 'America/Havana') >= c.desde)
      and (c.hasta is null or (now() at time zone 'America/Havana') <  c.hasta)
      -- [56] Una campana es una forma mas de enseñar un servicio: si la entidad
      -- oculto su categoria (o su categoria padre), la campana tampoco sale.
      and not exists (
        select 1
        from flow.entidad_categoria_oculta o
        where o.id_entidad = l.id_entidad
          and (
            o.id_tipo_actividad = ta.id
            or o.id_tipo_actividad = ta.id_padre
          )
      )
  ) t;
$function$;

comment on function flow.campanas_activas() is
  '[56] Patrocinados visibles para el cliente. Excluye las campanas cuyo '
  'servicio pertenece a una categoria que su entidad oculto, para que el '
  'carrusel del Home no sea una puerta trasera a un servicio oculto.';

-- ───────────────────────────────────────────────────────────────────────────
-- 3 · Colecciones: la tarjeta no puede prometer servicios que no va a listar
-- ───────────────────────────────────────────────────────────────────────────
-- Mismo razonamiento que los patrocinados, y se destapó al revisar el caso:
-- la colección "transporte" contiene el `local_servicio` del servicio oculto.
--
-- `flow.colecciones_activas()` cuenta y publica los ids de TODAS las filas de
-- `coleccion_servicio`, sin mirar la ocultación. El detalle de la colección sí
-- los filtra (`cliente_home_feed` con `p_id_coleccion`), así que el resultado
-- era incoherente: la tarjeta del Home anunciaba "2 servicios" y al entrar
-- aparecía 1. Y el array `servicios` exponía el id de un servicio oculto.
--
-- Se cuentan y se listan solo los visibles, y una colección que se queda sin
-- ninguno desaparece del Home (antes bastaba con que tuviera filas).
--
-- Único consumidor de esta función: `flow.cliente_home_feed`. Comprobado.

create or replace function flow.colecciones_activas()
returns jsonb
language sql
stable
security invoker
set search_path to 'flow', 'public'
as $function$
  with visibles as (
    -- [56] Una fila de `coleccion_servicio` cuenta solo si la entidad de su
    -- local no tiene oculta la categoria del servicio. Es el mismo predicado
    -- que usan el feed y los patrocinados: hoja o padre.
    select
      cs.id_coleccion,
      cs.id_local_servicio,
      cs.orden
    from flow.coleccion_servicio cs
    join flow.local_servicio ls on ls.id = cs.id_local_servicio
    join flow.app_dat_locales l on l.id = ls.id_local
    left join flow.app_dat_servicios s on s.id = ls.id_servicio
    left join flow.nom_tipo_actividad_servicio ta on ta.id = s.id_tipo_actividad
    where not exists (
      select 1
      from flow.entidad_categoria_oculta o
      where o.id_entidad = l.id_entidad
        and (
          o.id_tipo_actividad = ta.id
          or o.id_tipo_actividad = ta.id_padre
        )
    )
  )
  select coalesce(
    jsonb_agg(to_jsonb(t) order by t.orden asc, t.id asc),
    '[]'::jsonb
  )
  from (
    select
      c.id,
      c.titulo,
      c.subtitulo,
      c.icono,
      c.color_inicio,
      c.color_fin,
      c.orden,
      c.hasta,
      (select count(*)
         from visibles v
        where v.id_coleccion = c.id) as total_servicios,
      (select coalesce(
                jsonb_agg(v.id_local_servicio
                          order by v.orden asc, v.id_local_servicio asc),
                '[]'::jsonb)
         from visibles v
        where v.id_coleccion = c.id) as servicios
    from flow.coleccion c
    where c.activo
      and (c.desde is null or (now() at time zone 'America/Havana') >= c.desde)
      and (c.hasta is null or (now() at time zone 'America/Havana') <  c.hasta)
      and exists (select 1 from visibles v where v.id_coleccion = c.id)
  ) t;
$function$;

comment on function flow.colecciones_activas() is
  '[56] Colecciones visibles para el cliente. `total_servicios` y `servicios` '
  'solo cuentan filas cuya categoria no este oculta para la entidad del local, '
  'para que la tarjeta del Home no anuncie mas servicios de los que el detalle '
  'va a listar. Una coleccion sin servicios visibles no se devuelve.';

-- ───────────────────────────────────────────────────────────────────────────
-- 4 · Escribir sigue siendo solo del superadmin / admin de la entidad
-- ───────────────────────────────────────────────────────────────────────────
-- Se recrean tal cual estaban en la 55. Van aquí para que el archivo deje el
-- estado completo y no haya que leer dos migraciones para saber quién manda.

drop policy if exists entidad_categoria_oculta_insert on flow.entidad_categoria_oculta;
create policy entidad_categoria_oculta_insert
  on flow.entidad_categoria_oculta
  for insert
  to authenticated
  with check (public.fn_is_superadmin_full_access() or flow.is_entidad_admin(id_entidad));

drop policy if exists entidad_categoria_oculta_delete on flow.entidad_categoria_oculta;
create policy entidad_categoria_oculta_delete
  on flow.entidad_categoria_oculta
  for delete
  to authenticated
  using (public.fn_is_superadmin_full_access() or flow.is_entidad_admin(id_entidad));

-- ───────────────────────────────────────────────────────────────────────────
-- 5 · PostgREST tiene que releer el esquema
-- ───────────────────────────────────────────────────────────────────────────
-- Sin esto el `rpc` sigue sirviendo la definición vieja de `campanas_activas`
-- hasta que alguien reinicie el servicio.

notify pgrst, 'reload schema';

-- ───────────────────────────────────────────────────────────────────────────
-- 6 · Verificación
-- ───────────────────────────────────────────────────────────────────────────
-- El bloque de abajo comprueba las dos invariantes que importan, sin depender
-- de ningún dato concreto:
--   1. NINGUNA campaña activa puede apuntar a un servicio cuya categoría esté
--      oculta para su entidad.
--   2. NINGUNA colección puede listar en `servicios` un `local_servicio` con la
--      categoría oculta.
-- Si algo quedó mal, aborta la transacción entera en vez de dejar la base a
-- medias.

do $verificar$
declare
  v_malas integer;
begin
  -- ── 1. Patrocinados ──────────────────────────────────────────────────────
  select count(*)
    into v_malas
  from jsonb_array_elements(flow.campanas_activas()) elem
  join flow.local_servicio ls on ls.id = (elem ->> 'id_local_servicio_real')::integer
  join flow.app_dat_locales l on l.id = ls.id_local
  left join flow.app_dat_servicios s on s.id = ls.id_servicio
  left join flow.nom_tipo_actividad_servicio ta on ta.id = s.id_tipo_actividad
  where exists (
    select 1
    from flow.entidad_categoria_oculta o
    where o.id_entidad = l.id_entidad
      and (o.id_tipo_actividad = ta.id or o.id_tipo_actividad = ta.id_padre)
  );

  if v_malas > 0 then
    raise exception 'Quedaron % campanas apuntando a servicios ocultos', v_malas;
  end if;

  -- ── 2. Colecciones ───────────────────────────────────────────────────────
  select count(*)
    into v_malas
  from (
    select (sid.value)::integer as id_local_servicio
    from jsonb_array_elements(flow.colecciones_activas()) elem,
         lateral jsonb_array_elements_text(elem -> 'servicios') sid
  ) x
  join flow.local_servicio ls on ls.id = x.id_local_servicio
  join flow.app_dat_locales l on l.id = ls.id_local
  left join flow.app_dat_servicios s on s.id = ls.id_servicio
  left join flow.nom_tipo_actividad_servicio ta on ta.id = s.id_tipo_actividad
  where exists (
    select 1
    from flow.entidad_categoria_oculta o
    where o.id_entidad = l.id_entidad
      and (o.id_tipo_actividad = ta.id or o.id_tipo_actividad = ta.id_padre)
  );

  if v_malas > 0 then
    raise exception 'Quedaron % servicios ocultos anunciados en colecciones', v_malas;
  end if;
end
$verificar$;

-- Comprobaciones a mano, después de aplicar (en el editor SQL corre como
-- `postgres`, así que NO reproduce lo que ve un cliente; para eso hay que
-- mirar desde la app):
--
--   -- 1. La política permite leer a anon y authenticated.
--   select polname, polroles::regrole[]::text, pg_get_expr(polqual, polrelid)
--   from pg_policy pol
--   join pg_class c on c.oid = polrelid
--   join pg_namespace n on n.oid = c.relnamespace
--   where n.nspname = 'flow' and c.relname = 'entidad_categoria_oculta';
--
--   -- 2. El riel NO cambia al ocultar (debe dar los mismos ids en ambas).
--   select jsonb_path_query_array(
--            (flow.cliente_home_feed()) -> 'metadata' -> 'categorias', '$[*].id'
--          );
--
--   -- 3. La campaña del servicio oculto ya no sale.
--   select elem ->> 'titulo', elem ->> 'servicio'
--   from jsonb_array_elements(flow.campanas_activas()) elem;
