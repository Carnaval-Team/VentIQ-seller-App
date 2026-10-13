-- ============================================================================
-- MIGRACION: categorias de marketplace + RLS del nomenclador
--
-- CONTEXTO
--   `flow.nom_tipo_actividad_servicio` nacio para distinguir el transporte en
--   omnibus del resto ("general"). El Home del cliente necesitaba un riel de
--   categorias y, al no existir, lo inventaba en el cliente con 8 categorias
--   fijas que ningun servicio podia tener.
--
--   Esta migracion:
--     1. Siembra la taxonomia de marketplace (idempotente).
--     2. Activa RLS en el nomenclador, hoy desactivado: con `grant` a `anon`,
--        cualquiera con la publishable key podia insertar/borrar categorias.
--     3. Deja lectura publica y escritura solo a quien administra una entidad.
--     4. Activa RLS en `bot_log` y `sala_espera_fraude` (tablas internas).
--
-- REVERSION
--   Las categorias sembradas se pueden quitar con:
--     delete from flow.nom_tipo_actividad_servicio
--      where codigo in (...);  -- ver lista abajo
--   siempre que ningun servicio las este usando (hay FK).
-- ============================================================================

-- ============================================================================
-- 1. TAXONOMIA DE MARKETPLACE
--
-- `general` se conserva como valor por defecto: `app_dat_servicios.
-- id_tipo_actividad` es NOT NULL y los servicios ya existentes apuntan ahi.
-- `transporte_omnibus` no se toca: tiene logica propia en la app.
-- ============================================================================
insert into flow.nom_tipo_actividad_servicio (codigo, nombre)
values
  ('general',            'General'),
  ('belleza',            'Belleza'),
  ('unas',               'Uñas'),
  ('cejas_pestanas',     'Cejas y Pestañas'),
  ('peluqueria',         'Peluquería y Barbería'),
  ('estetica_spa',       'Estética y Spa'),
  ('salud',              'Salud'),
  ('hogar',              'Hogar y Reparaciones'),
  ('mascotas',           'Mascotas'),
  ('gastronomia',        'Gastronomía'),
  ('eventos',            'Eventos y Celebraciones'),
  ('tecnologia',         'Tecnología'),
  ('transporte_omnibus', 'Transporte en ómnibus'),
  ('transporte_privado', 'Transporte privado')
on conflict (codigo) do update
  set nombre = excluded.nombre,
      activo = true;

-- ============================================================================
-- 2. RLS: nom_tipo_actividad_servicio
--
--   SELECT → publico (el riel de categorias se lee antes y despues del login).
--   INSERT/UPDATE/DELETE → solo usuarios autenticados que administren al menos
--     una entidad (owner o entidad_admin). Es una taxonomia de plataforma, pero
--     cualquier comercio puede proponer categorias; si mas adelante se quiere
--     curar centralmente, basta con borrar estas tres politicas y gestionar el
--     nomenclador por migracion.
-- ============================================================================
alter table flow.nom_tipo_actividad_servicio enable row level security;

drop policy if exists "nom_tipo_actividad_select_all" on flow.nom_tipo_actividad_servicio;
drop policy if exists "nom_tipo_actividad_insert_admin" on flow.nom_tipo_actividad_servicio;
drop policy if exists "nom_tipo_actividad_update_admin" on flow.nom_tipo_actividad_servicio;
drop policy if exists "nom_tipo_actividad_delete_admin" on flow.nom_tipo_actividad_servicio;

create policy "nom_tipo_actividad_select_all"
on flow.nom_tipo_actividad_servicio
for select
to authenticated, anon
using (true);

create policy "nom_tipo_actividad_insert_admin"
on flow.nom_tipo_actividad_servicio
for insert
to authenticated
with check (
  exists (select 1 from flow.admin_entidades_de_usuario(auth.uid()))
);

create policy "nom_tipo_actividad_update_admin"
on flow.nom_tipo_actividad_servicio
for update
to authenticated
using (
  exists (select 1 from flow.admin_entidades_de_usuario(auth.uid()))
)
with check (
  exists (select 1 from flow.admin_entidades_de_usuario(auth.uid()))
);

create policy "nom_tipo_actividad_delete_admin"
on flow.nom_tipo_actividad_servicio
for delete
to authenticated
using (
  exists (select 1 from flow.admin_entidades_de_usuario(auth.uid()))
);

-- ============================================================================
-- 3. RLS: tablas internas
--
--   OJO, las dos tablas NO se pueden tratar igual:
--
--   * `bot_log` solo la escriben `bot_procesar_plan` y
--     `bot_procesar_recurso_dia`, que son SECURITY DEFINER y por tanto corren
--     como el owner (que no esta sujeto a RLS). Se activa RLS sin politicas:
--     nadie salvo el owner puede leerla ni escribirla, y el bot sigue igual.
--
--   * `sala_espera_fraude` la escriben `cliente_entrar_sala_espera_cola` y
--     `cliente_entrar_sala_espera_reserva`, que son SECURITY INVOKER. Activar
--     RLS ahi SIN politica de INSERT romperia la entrada a la cola con
--     "new row violates row-level security policy". Se replican exactamente los
--     accesos que ya hacen esas funciones: insertar y contar filas propias.
--     (Ni UPDATE ni DELETE: la tabla es un log append-only.)
-- ============================================================================
alter table flow.bot_log enable row level security;

alter table flow.sala_espera_fraude enable row level security;

drop policy if exists "sala_espera_fraude_insert_propio" on flow.sala_espera_fraude;
drop policy if exists "sala_espera_fraude_select_propio" on flow.sala_espera_fraude;

create policy "sala_espera_fraude_insert_propio"
on flow.sala_espera_fraude
for insert
to authenticated
with check (uuid_usuario = auth.uid());

-- El chequeo antifraude de flood cuenta las filas propias de la ventana:
--   select count(*) from flow.sala_espera_fraude
--    where uuid_usuario = p_uuid_usuario and created_at >= now() - '1 minute'
-- Asi que la politica de lectura tiene que dejar ver las filas propias.
create policy "sala_espera_fraude_select_propio"
on flow.sala_espera_fraude
for select
to authenticated
using (uuid_usuario = auth.uid());

-- ============================================================================
-- 4. RPC de gestion (pantalla "Categorias" del panel admin)
--
--   `security invoker`: la autorizacion la hacen las politicas RLS de arriba y
--   el chequeo explicito de abajo.
--
--   IMPORTANTE: estas funciones NO reciben `p_uuid_usuario`. Varios RPC admin
--   del proyecto si lo reciben y confian en el, pero con `security definer` eso
--   es suplantable: basta pasar el uuid de otro administrador. Aqui se usa
--   `auth.uid()`, que lo pone el motor y no el cliente.
--
--   Ademas se revoca `execute` de `public` y `anon`: en Postgres toda funcion
--   nueva queda ejecutable por PUBLIC, y `grants_flow.sql` ademas da EXECUTE a
--   `anon`. Sin este revoke, un anonimo podria invocarlas.
-- ============================================================================
create or replace function flow.admin_guardar_tipo_actividad(
  p_codigo text,
  p_nombre text,
  p_activo boolean default true,
  p_id integer default null
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
     or not exists (select 1 from flow.admin_entidades_de_usuario(auth.uid()))
  then
    return jsonb_build_object('ok', false, 'error', 'No administras ninguna entidad');
  end if;

  -- Misma normalizacion que `TipoActividad.codigoDesdeNombre` en la app.
  v_codigo := lower(trim(coalesce(p_codigo, '')));
  v_codigo := translate(v_codigo, 'áéíóúüñ', 'aeiouun');
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

  if p_id is null then
    if exists (
      select 1 from flow.nom_tipo_actividad_servicio where codigo = v_codigo
    ) then
      return jsonb_build_object('ok', false, 'error', 'Ya existe una categoria con ese codigo');
    end if;
    insert into flow.nom_tipo_actividad_servicio (codigo, nombre, activo)
    values (v_codigo, trim(p_nombre), coalesce(p_activo, true))
    returning id into v_id;
  else
    -- El codigo es la clave estable que ya viaja dentro de
    -- `cliente_obtener_servicios` y en las filas ya guardadas, asi que al
    -- editar NO se modifica: solo cambian el nombre y el estado.
    update flow.nom_tipo_actividad_servicio
       set nombre = trim(p_nombre),
           activo = coalesce(p_activo, true)
     where id = p_id
     returning id, codigo into v_id, v_codigo;

    if v_id is null then
      return jsonb_build_object('ok', false, 'error', 'Categoria inexistente');
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object('id', v_id, 'codigo', v_codigo)
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
begin
  if auth.uid() is null
     or not exists (select 1 from flow.admin_entidades_de_usuario(auth.uid()))
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

  delete from flow.nom_tipo_actividad_servicio where id = p_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Categoria inexistente');
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function flow.admin_guardar_tipo_actividad(text, text, boolean, integer)
  from public, anon;
revoke all on function flow.admin_eliminar_tipo_actividad(integer)
  from public, anon;

grant execute on function flow.admin_guardar_tipo_actividad(text, text, boolean, integer)
  to authenticated;
grant execute on function flow.admin_eliminar_tipo_actividad(integer)
  to authenticated;
