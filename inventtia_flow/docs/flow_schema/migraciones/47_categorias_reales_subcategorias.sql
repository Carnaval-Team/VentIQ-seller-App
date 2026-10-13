-- ============================================================================
-- MIGRACION 47: taxonomia de DOS NIVELES (categorias reales + subcategorias)
--
-- QUE RESUELVE
--   1. Las categorias sembradas por `22_categorias_marketplace.sql` eran de
--      prueba (belleza, unas, cejas_pestanas, gastronomia, transporte_omnibus,
--      salud, hogar, mascotas, eventos, tecnologia...). Se sustituyen por la
--      taxonomia REAL de 6 categorias.
--   2. Hasta ahora un servicio solo podia tener CATEGORIA. Ahora puede tener
--      CATEGORIA **y** SUBCATEGORIA.
--
-- DISENO: POR QUE `id_padre` EN VEZ DE UNA TABLA NUEVA
--   Se anade `nom_tipo_actividad_servicio.id_padre` (auto-referencia) en lugar de
--   crear `nom_subcategoria_servicio`. Motivo concreto, no estetico:
--
--   * `app_dat_servicios.id_tipo_actividad` sigue apuntando a la FILA HOJA. Si el
--     servicio es de una subcategoria, esa fila es la subcategoria; su
--     categoria es la del padre.
--   * Los codigos de las hojas NO cambian. Eso es critico para
--     'transporte_omnibus': `LocalServicio.esTransporteOmnibus`
--     (`lib/models/servicio.dart`) y los RPC `cliente_obtener_disponibilidad_
--     transporte`, `cliente_reservar_pasaje_omnibus` y
--     `admin_reservar_pasaje_omnibus` detectan ese flujo comparando el CODIGO de
--     la categoria del servicio. Con este diseno el codigo sigue siendo
--     'transporte_omnibus' y NINGUNO de esos cuatro sitios hay que tocarlo.
--   * No hay columna nueva en `app_dat_servicios`, asi que no hay migracion de
--     datos de la tabla de servicios ni riesgo de dejar filas a medias.
--
--   La profundidad se limita a 2 niveles con un trigger: una subcategoria no
--   puede ser padre de nada. Sin esa regla, "categoria -> subcategoria ->
--   servicio" dejaria de tener una interpretacion unica.
--
-- ORDEN DE APLICACION
--   47 (esta)  -> crea la jerarquia, siembra, reasigna servicios y deja los RPC
--                 de gestion.
--   48_home_feed_categorias_subcategorias.sql  -> el Home del cliente.
--   49_campanas_datos_local.sql                -> imagen/datos del local en las
--                 campanas patrocinadas.
--
-- DEPENDE DE: 22_categorias_marketplace.sql (los RPC de gestion) y de que
--   exista `public.fn_is_superadmin_full_access()` (helper del superadmin).
--
-- REVERSION
--   -- 1. Devolver los servicios movidos a sus categorias originales:
--   update flow.app_dat_servicios set id_tipo_actividad = 1 where id in (1, 4);
--   -- 2. Volver a dejar el nomenclador como estaba:
--   alter table flow.nom_tipo_actividad_servicio drop constraint if exists
--     nom_tipo_actividad_servicio_id_padre_fkey;
--   drop trigger if exists trg_nom_tipo_actividad_jerarquia
--     on flow.nom_tipo_actividad_servicio;
--   drop function if exists flow.validar_jerarquia_tipo_actividad();
--   alter table flow.nom_tipo_actividad_servicio drop column if exists id_padre;
--   alter table flow.nom_tipo_actividad_servicio drop column if exists orden;
--   -- 3. Los RPC de gestion vuelven a la version de 22_categorias_marketplace.sql.
-- ============================================================================

-- ============================================================================
-- 1. ESTRUCTURA: id_padre + orden
--
--   `orden` da control real sobre el riel del Home (chips) y sobre la pantalla
--   del superadmin: ordenar por `nombre` deja "Estética / Spa" antes que
--   "Uñas / Manicure" sin que nadie lo pueda cambiar.
-- ============================================================================
alter table flow.nom_tipo_actividad_servicio
  add column if not exists id_padre integer;

alter table flow.nom_tipo_actividad_servicio
  add column if not exists orden integer not null default 0;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'nom_tipo_actividad_servicio_id_padre_fkey'
  ) then
    alter table flow.nom_tipo_actividad_servicio
      add constraint nom_tipo_actividad_servicio_id_padre_fkey
      foreign key (id_padre)
      references flow.nom_tipo_actividad_servicio(id)
      on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'nom_tipo_actividad_servicio_no_autopadre'
  ) then
    alter table flow.nom_tipo_actividad_servicio
      add constraint nom_tipo_actividad_servicio_no_autopadre
      check (id_padre is null or id_padre <> id);
  end if;
end $$;

create index if not exists idx_nom_tipo_actividad_padre
  on flow.nom_tipo_actividad_servicio (id_padre);

comment on column flow.nom_tipo_actividad_servicio.id_padre is
  'Categoria padre. NULL = categoria raiz (nivel 1). No NULL = subcategoria (nivel 2). Un servicio apunta SIEMPRE a la hoja: si es subcategoria, su categoria es este padre.';
comment on column flow.nom_tipo_actividad_servicio.orden is
  'Orden en el riel del Home y en la pantalla del superadmin. Menor = antes.';

-- ---------------------------------------------------------------------------
-- 1.1 Profundidad maxima: 2 niveles
--
--   El trigger cubre los dos caminos que romperian la jerarquia:
--     a) colgar una subcategoria de otra subcategoria (nivel 3);
--     b) convertir en subcategoria una categoria que ya tiene hijas.
-- ---------------------------------------------------------------------------
create or replace function flow.validar_jerarquia_tipo_actividad()
returns trigger
language plpgsql
security invoker
set search_path = flow, public
as $$
begin
  if new.id_padre is not null then
    if new.id_padre = new.id then
      raise exception 'Una categoria no puede ser su propio padre';
    end if;

    if exists (
      select 1 from flow.nom_tipo_actividad_servicio p
      where p.id = new.id_padre and p.id_padre is not null
    ) then
      raise exception
        'Solo se admiten dos niveles: una subcategoria no puede tener subcategorias';
    end if;

    if tg_op = 'UPDATE' and exists (
      select 1 from flow.nom_tipo_actividad_servicio h
      where h.id_padre = new.id
    ) then
      raise exception
        'Esta categoria ya tiene subcategorias: no puede convertirse en subcategoria';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_nom_tipo_actividad_jerarquia
  on flow.nom_tipo_actividad_servicio;

create trigger trg_nom_tipo_actividad_jerarquia
before insert or update of id_padre on flow.nom_tipo_actividad_servicio
for each row execute function flow.validar_jerarquia_tipo_actividad();

-- ============================================================================
-- 2. RLS: la gestion deja de ser exclusiva del admin de entidad
--
--   Antes (22_categorias_marketplace.sql) solo podia escribir quien administra
--   una entidad. El requisito nuevo es que el SUPERADMIN gestione el catalogo
--   completo desde `ventiq_superadmin`, asi que se anade
--   `public.fn_is_superadmin_full_access()` a las tres politicas de escritura.
--
--   La lectura sigue siendo publica: el riel se pinta antes y despues del login.
-- ============================================================================
drop policy if exists "nom_tipo_actividad_insert_admin" on flow.nom_tipo_actividad_servicio;
drop policy if exists "nom_tipo_actividad_update_admin" on flow.nom_tipo_actividad_servicio;
drop policy if exists "nom_tipo_actividad_delete_admin" on flow.nom_tipo_actividad_servicio;

create policy "nom_tipo_actividad_insert_admin"
on flow.nom_tipo_actividad_servicio
for insert
to authenticated
with check (
  exists (select 1 from flow.admin_entidades_de_usuario(auth.uid()))
  or public.fn_is_superadmin_full_access()
);

create policy "nom_tipo_actividad_update_admin"
on flow.nom_tipo_actividad_servicio
for update
to authenticated
using (
  exists (select 1 from flow.admin_entidades_de_usuario(auth.uid()))
  or public.fn_is_superadmin_full_access()
)
with check (
  exists (select 1 from flow.admin_entidades_de_usuario(auth.uid()))
  or public.fn_is_superadmin_full_access()
);

create policy "nom_tipo_actividad_delete_admin"
on flow.nom_tipo_actividad_servicio
for delete
to authenticated
using (
  exists (select 1 from flow.admin_entidades_de_usuario(auth.uid()))
  or public.fn_is_superadmin_full_access()
);

-- ============================================================================
-- 3. RPC DE GESTION
--
--   IMPORTANTE: se ELIMINA la firma vieja antes de crear la nueva. Anadir
--   `p_id_padre` con `create or replace` habria dejado DOS funciones (una de
--   4 argumentos y otra de 6) y PostgREST rechazaria la llamada por ambigua.
--
--   `security invoker`: la autorizacion la hacen las politicas RLS de arriba y
--   el chequeo explicito de abajo. Nunca se confia en un uuid de parametro.
-- ============================================================================
drop function if exists flow.admin_guardar_tipo_actividad(text, text, boolean, integer);

create or replace function flow.admin_guardar_tipo_actividad(
  p_codigo text,
  p_nombre text,
  p_activo boolean default true,
  p_id integer default null,
  p_id_padre integer default null,
  p_orden integer default 0
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = flow, public
as $$
declare
  v_codigo text;
  v_id integer;
begin
  if auth.uid() is null
     or (
       not exists (select 1 from flow.admin_entidades_de_usuario(auth.uid()))
       and not public.fn_is_superadmin_full_access()
     )
  then
    return jsonb_build_object('ok', false, 'error', 'No administras ninguna entidad');
  end if;

  -- Misma normalizacion que `TipoActividad.codigoDesdeNombre` en la app.
  v_codigo := lower(trim(coalesce(p_codigo, '')));
  v_codigo := translate(v_codigo, 'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunAEIOUUN');
  v_codigo := regexp_replace(v_codigo, '[^a-z0-9]+', '_', 'g');
  v_codigo := trim(both '_' from v_codigo);

  if trim(coalesce(p_nombre, '')) = '' then
    return jsonb_build_object('ok', false, 'error', 'El nombre es obligatorio');
  end if;
  if v_codigo !~ '^[a-z0-9_]{3,64}$' then
    return jsonb_build_object(
      'ok', false,
      'error', 'El codigo debe tener 3-64 caracteres: minusculas, numeros o guion bajo'
    );
  end if;

  if p_id_padre is not null then
    if not exists (
      select 1 from flow.nom_tipo_actividad_servicio p
      where p.id = p_id_padre and p.id_padre is null
    ) then
      return jsonb_build_object(
        'ok', false,
        'error', 'La categoria padre no existe o es a su vez una subcategoria'
      );
    end if;
  end if;

  if p_id is null then
    if exists (
      select 1 from flow.nom_tipo_actividad_servicio where codigo = v_codigo
    ) then
      return jsonb_build_object('ok', false, 'error', 'Ya existe una categoria con ese codigo');
    end if;
    insert into flow.nom_tipo_actividad_servicio
      (codigo, nombre, activo, id_padre, orden)
    values
      (v_codigo, trim(p_nombre), coalesce(p_activo, true), p_id_padre, coalesce(p_orden, 0))
    returning id into v_id;
  else
    -- El codigo es la clave estable que ya viaja dentro de
    -- `cliente_obtener_servicios` y de `cliente_home_feed`, y que usan los
    -- detectores de transporte: al editar NO se modifica.
    update flow.nom_tipo_actividad_servicio
       set nombre = trim(p_nombre),
           activo = coalesce(p_activo, true),
           id_padre = p_id_padre,
           orden = coalesce(p_orden, orden)
     where id = p_id
     returning id, codigo into v_id, v_codigo;

    if v_id is null then
      return jsonb_build_object('ok', false, 'error', 'Categoria inexistente');
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id', v_id, 'codigo', v_codigo, 'id_padre', p_id_padre
    )
  );
end;
$$;

create or replace function flow.admin_alternar_tipo_actividad(
  p_id integer,
  p_activo boolean
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = flow, public
as $$
declare
  v_hijas integer;
begin
  if auth.uid() is null
     or (
       not exists (select 1 from flow.admin_entidades_de_usuario(auth.uid()))
       and not public.fn_is_superadmin_full_access()
     )
  then
    return jsonb_build_object('ok', false, 'error', 'No administras ninguna entidad');
  end if;

  update flow.nom_tipo_actividad_servicio
     set activo = coalesce(p_activo, true)
   where id = p_id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Categoria inexistente');
  end if;

  -- Apagar una categoria apaga sus subcategorias: dejarlas activas las sacaria
  -- en el riel de un padre que ya no se muestra.
  if coalesce(p_activo, true) = false then
    update flow.nom_tipo_actividad_servicio
       set activo = false
     where id_padre = p_id;
  end if;

  select count(*) into v_hijas
  from flow.nom_tipo_actividad_servicio where id_padre = p_id;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object('id', p_id, 'activo', coalesce(p_activo, true), 'subcategorias', v_hijas)
  );
end;
$$;

create or replace function flow.admin_eliminar_tipo_actividad(
  p_id integer
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = flow, public
as $$
declare
  v_servicios integer;
  v_hijas integer;
begin
  if auth.uid() is null
     or (
       not exists (select 1 from flow.admin_entidades_de_usuario(auth.uid()))
       and not public.fn_is_superadmin_full_access()
     )
  then
    return jsonb_build_object('ok', false, 'error', 'No administras ninguna entidad');
  end if;

  select count(*) into v_servicios
  from flow.app_dat_servicios
  where id_tipo_actividad = p_id;

  if v_servicios > 0 then
    return jsonb_build_object(
      'ok', false,
      'error', format(
        'No se puede eliminar: %s servicio(s) usan esta categoria. Desactivala en su lugar.',
        v_servicios
      )
    );
  end if;

  select count(*) into v_hijas
  from flow.nom_tipo_actividad_servicio
  where id_padre = p_id;

  if v_hijas > 0 then
    return jsonb_build_object(
      'ok', false,
      'error', format(
        'No se puede eliminar: tiene %s subcategoria(s). Eliminalas o desactivala.',
        v_hijas
      )
    );
  end if;

  delete from flow.nom_tipo_actividad_servicio where id = p_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Categoria inexistente');
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function flow.admin_guardar_tipo_actividad(text, text, boolean, integer, integer, integer) from public, anon;
revoke all on function flow.admin_alternar_tipo_actividad(integer, boolean) from public, anon;
revoke all on function flow.admin_eliminar_tipo_actividad(integer) from public, anon;

grant execute on function flow.admin_guardar_tipo_actividad(text, text, boolean, integer, integer, integer) to authenticated, service_role;
grant execute on function flow.admin_alternar_tipo_actividad(integer, boolean) to authenticated, service_role;
grant execute on function flow.admin_eliminar_tipo_actividad(integer) to authenticated, service_role;

-- ============================================================================
-- 4. SEED: la taxonomia REAL
--
--   Se resuelve el padre por CODIGO (no por id fijo) para que funcione igual en
--   los dos proyectos Supabase, donde los ids pueden diferir.
--   Idempotente: `on conflict (codigo) do update` deja el mismo estado si se
--   vuelve a ejecutar.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 4.1 Categorias raiz (nivel 1)
--
--   `belleza` (id 6) y `gastronomia` (id 14) YA EXISTEN desde la migracion 22:
--   se reutilizan en vez de duplicarlas (el codigo es unico). Se reescribe el
--   nombre exacto y se fuerzan a raiz e inactivas→activas.
-- ---------------------------------------------------------------------------
insert into flow.nom_tipo_actividad_servicio
  (codigo, nombre, activo, id_padre, orden)
values
  ('alojamiento', 'Alojamiento',  true, null, 10),
  ('gastronomia', 'Gastronomía',  true, null, 20),
  ('belleza',     'Belleza',      true, null, 30),
  ('transporte',  'Transporte',   true, null, 40),
  ('recreacion',  'Recreación',   true, null, 50),
  ('juridicos',   'Jurídicos',    true, null, 60)
on conflict (codigo) do update
  set nombre   = excluded.nombre,
      activo   = true,
      id_padre = null,
      orden    = excluded.orden;

-- ---------------------------------------------------------------------------
-- 4.2 Subcategorias (nivel 2): 5 por categoria, 30 en total
--
--   VARIAS YA EXISTEN como categorias de la migracion 22 (`unas`,
--   `cejas_pestanas`, `peluqueria`, `estetica_spa`, `transporte_omnibus`,
--   `transporte_privado`). Se REUTILIZAN cambiandoles solo el padre: con ello
--   los servicios que ya apuntaban a ellas quedan automaticamente en la
--   subcategoria correcta, sin mover una sola fila. Es el caso de
--   `transporte_omnibus`, cuyo codigo NO puede cambiar (ver cabecera).
-- ---------------------------------------------------------------------------
with taxonomia(padre, codigo, nombre, orden) as (
  values
    -- Alojamiento
    ('alojamiento', 'hoteleria_hostal',            'Hotelería / Hostal',             10),
    ('alojamiento', 'casa_particular_apartamento', 'Casa particular / Apartamento',  20),
    ('alojamiento', 'campismo_cabanas',            'Campismo / Cabañas',             30),
    ('alojamiento', 'alojamiento_rural_finca',     'Alojamiento rural / Finca',      40),
    ('alojamiento', 'resort_todo_incluido',        'Resort / Todo incluido',         50),
    -- Gastronomia
    ('gastronomia', 'restaurantes',                'Restaurantes',                   10),
    ('gastronomia', 'cafeteria',                   'Cafetería',                      20),
    ('gastronomia', 'paladar_comida_criolla',      'Paladar / Comida criolla',       30),
    ('gastronomia', 'bar_cocteleria',              'Bar / Coctelería',               40),
    ('gastronomia', 'reposteria_panaderia',        'Repostería / Panadería',         50),
    -- Belleza
    ('belleza', 'peluqueria',      'Peluquería / Barbería',  10),
    ('belleza', 'unas',            'Uñas / Manicure',        20),
    ('belleza', 'cejas_pestanas',  'Cejas y Pestañas',       30),
    ('belleza', 'estetica_spa',    'Estética / Spa',         40),
    ('belleza', 'maquillaje',      'Maquillaje',             50),
    -- Transporte
    ('transporte', 'transporte_omnibus',   'Transporte en ómnibus',      10),
    ('transporte', 'transporte_privado',   'Transporte privado / Taxi',  20),
    ('transporte', 'alquiler_vehiculos',   'Alquiler de vehículos',      30),
    ('transporte', 'talleres_gasolineras', 'Talleres / Gasolineras',     40),
    ('transporte', 'grua_fregado_carros',  'Grúa / Fregado de carros',   50),
    -- Recreacion
    ('recreacion', 'turismo_excursiones',      'Turismo / Excursiones',      10),
    ('recreacion', 'cine_teatro',              'Cine / Teatro',              20),
    ('recreacion', 'fiestas_eventos',          'Fiestas / Eventos',          30),
    ('recreacion', 'deportes_gimnasio',        'Deportes / Gimnasio',        40),
    ('recreacion', 'parques_entretenimiento',  'Parques / Entretenimiento',  50),
    -- Juridicos
    ('juridicos', 'asesoria_legal',       'Asesoría legal',       10),
    ('juridicos', 'notaria_documentos',   'Notaría / Documentos', 20),
    ('juridicos', 'penal_civil',          'Penal / Civil',        30),
    ('juridicos', 'laboral_migratorio',   'Laboral / Migratorio', 40),
    ('juridicos', 'contabilidad_fiscal',  'Contabilidad / Fiscal', 50)
)
insert into flow.nom_tipo_actividad_servicio
  (codigo, nombre, activo, id_padre, orden)
select t.codigo, t.nombre, true, p.id, t.orden
from taxonomia t
join flow.nom_tipo_actividad_servicio p on p.codigo = t.padre
on conflict (codigo) do update
  set nombre   = excluded.nombre,
      activo   = true,
      id_padre = excluded.id_padre,
      orden    = excluded.orden;

-- ---------------------------------------------------------------------------
-- 4.3 Apagar la taxonomia de prueba
--
--   Solo raices: las subcategorias quedan activas. Nada se borra porque
--   `app_dat_servicios` tiene FK y hay reservas historicas que referencian esos
--   codigos; desactivarlas las saca del riel del Home sin romper el pasado.
--
--   `general` se queda como cajon de sastre INACTIVO: el unico servicio que
--   todavia apunta ahi es 'test' (fila de prueba). Ver nota al final.
-- ---------------------------------------------------------------------------
update flow.nom_tipo_actividad_servicio
   set activo = false
 where id_padre is null
   and codigo not in (
     'alojamiento', 'gastronomia', 'belleza', 'transporte', 'recreacion', 'juridicos'
   );

-- ---------------------------------------------------------------------------
-- 4.4 Reasignar los servicios existentes
--
--   La mayoria YA queda en su sitio por reutilizar filas (ver 4.2):
--     2  'Alquiler de asientos de camion' -> transporte_privado
--     6  'Transportacion'                 -> transporte_omnibus
--     7  'Carnaval Transportacion'        -> transporte_omnibus
--     8  'Arreglo de uñas'                -> unas
--     13 'Depilación De Cejas'            -> cejas_pestanas
--     14 'Lifting De Cejas'               -> cejas_pestanas
--     15 'Real'                           -> transporte_privado
--   Solo hay que mover dos:
--     1  'Gas'                       -> talleres_gasolineras (era 'general')
--     4  'Transportación Privada'    -> transporte_privado    (era 'general')
--
--   NO SE TOCA 'test' (id 3): es una fila de prueba. Se queda en la categoria
--   'general', ahora inactiva, asi que no aparece en el riel. Si se quiere
--   publicar, reasignarlo o borrarlo es una decision de negocio, no de esquema.
-- ---------------------------------------------------------------------------
update flow.app_dat_servicios s
   set id_tipo_actividad = t.id
  from flow.nom_tipo_actividad_servicio t
 where t.codigo = 'talleres_gasolineras'
   and s.id = 1;

update flow.app_dat_servicios s
   set id_tipo_actividad = t.id
  from flow.nom_tipo_actividad_servicio t
 where t.codigo = 'transporte_privado'
   and s.id = 4;

-- ============================================================================
-- 5. VERIFICACION
--   a) 6 categorias raiz activas con 5 subcategorias activas cada una.
--   b) ningun servicio apunta a una categoria raiz inactiva (salvo 'test').
--   c) los dos servicios de omnibus conservan el codigo que activa su flujo.
-- ============================================================================
select r.codigo as categoria,
       r.nombre as categoria_nombre,
       count(h.id) filter (where h.activo) as subcategorias_activas
from flow.nom_tipo_actividad_servicio r
left join flow.nom_tipo_actividad_servicio h on h.id_padre = r.id
where r.id_padre is null
  and r.codigo in ('alojamiento','gastronomia','belleza','transporte','recreacion','juridicos')
group by r.codigo, r.nombre, r.orden
order by r.orden;

select s.id as id_servicio,
       s.nombre as servicio,
       t.codigo as hoja,
       t.nombre as hoja_nombre,
       p.codigo as categoria,
       p.nombre as categoria_nombre,
       t.activo as hoja_activa,
       p.activo as categoria_activa
from flow.app_dat_servicios s
join flow.nom_tipo_actividad_servicio t on t.id = s.id_tipo_actividad
left join flow.nom_tipo_actividad_servicio p on p.id = t.id_padre
order by s.id;

-- Los dos servicios de omnibus deben seguir dando 'transporte_omnibus': es lo
-- que activa el flujo de pasajes ida/vuelta en la app y en los RPC.
select count(*) as servicios_omnibus_detectables
from flow.app_dat_servicios s
join flow.nom_tipo_actividad_servicio t on t.id = s.id_tipo_actividad
where t.codigo = 'transporte_omnibus';

notify pgrst, 'reload schema';
