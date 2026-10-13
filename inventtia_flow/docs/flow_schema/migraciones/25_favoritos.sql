-- ============================================================================
-- MIGRACION: favoritos del cliente
--
-- CONTEXTO
--   El Home pintaba un corazon que no persistia: `_savedIds` era un `Set<int>`
--   en memoria con ids 9001/9005, que ni siquiera existen como `local_servicio`
--   (los reales van del 7 al 17). Al tocar el corazon, el Home decia "guardado
--   en Mis Listas" — y "Mis Listas" es la **sala de espera** (`flow.sala_espera`),
--   no favoritos. Dos mentiras en un solo gesto.
--
--   Esta migracion crea la tabla real. Con esto el Paso 3 del plan puede cablear
--   el corazon, una pestana de favoritos y el estado persistente por usuario.
--
-- LA CLAVE FORANEA VA CONTRA auth.users, NO CONTRA flow.perfil
--   Medido en la base: hay 5261 usuarios en `auth.users` y solo 19 filas en
--   `flow.perfil`. Si la FK apuntara a `flow.perfil`, 5242 usuarios recibirian
--   una violacion de clave foranea al guardar su primer favorito. `flow.agenda`
--   y `flow.notificaciones` ya usan `auth.users`/`perfil`; aqui se elige
--   `auth.users` porque es la unica tabla que contiene a todos.
--
--   El `ON DELETE CASCADE` contra `auth.users` es correcto: si se borra la
--   cuenta, sus favoritos no tienen sentido.
--
-- QUE CREA
--   flow.favorito (uuid_usuario, id_local_servicio, created_at)
--     - PK compuesta (uuid_usuario, id_local_servicio): guardar dos veces el
--       mismo favorito no duplica, y el `on conflict do nothing` del cliente
--       es idempotente.
--     - indice por (uuid_usuario, created_at desc) para listar "mis favoritos"
--       sin ordenar en memoria.
--
-- RLS
--   Todo por `auth.uid()`: cada usuario ve y modifica SOLO sus favoritos.
--   No hay lectura publica: el numero de favoritos de otro no es asunto tuyo.
--   `auth.uid()` va en `USING` y en `WITH CHECK` — sin el `WITH CHECK` un
--   usuario podria insertar una fila con el uuid de otro.
--
-- REVERSION
--   drop table if exists flow.favorito;
--   (No toca ninguna tabla existente: es una creacion nueva.)
--
-- DEPENDE DE: nada. Se puede aplicar sola.
-- ============================================================================

create table if not exists flow.favorito (
  uuid_usuario       uuid        not null
                     references auth.users(id) on delete cascade,
  id_local_servicio  integer     not null
                     references flow.local_servicio(id) on delete cascade,
  created_at         timestamp   not null default current_timestamp,
  primary key (uuid_usuario, id_local_servicio)
);

comment on table flow.favorito is
  'Servicios guardados por cada cliente. PK compuesta: guardar dos veces no duplica.';

create index if not exists idx_favorito_usuario_fecha
  on flow.favorito (uuid_usuario, created_at desc);

-- ============================================================================
-- RLS: cada usuario, solo lo suyo
-- ============================================================================
alter table flow.favorito enable row level security;

drop policy if exists "favorito_select_propio" on flow.favorito;
drop policy if exists "favorito_insert_propio" on flow.favorito;
drop policy if exists "favorito_delete_propio" on flow.favorito;

create policy "favorito_select_propio"
on flow.favorito
for select
to authenticated
using (uuid_usuario = auth.uid());

create policy "favorito_insert_propio"
on flow.favorito
for insert
to authenticated
with check (uuid_usuario = auth.uid());

create policy "favorito_delete_propio"
on flow.favorito
for delete
to authenticated
using (uuid_usuario = auth.uid());

-- No hay politica de UPDATE a proposito: un favorito se pone o se quita, no se
-- edita. Sin politica, cualquier UPDATE queda denegado.

-- ============================================================================
-- Permisos explicitos
--
--   Los `alter default privileges` de la migracion 24 dejan los objetos nuevos
--   sin EXECUTE/SELECT para `anon`, pero conviene ser explicito aqui para que
--   esta migracion no dependa del orden de aplicacion.
-- ============================================================================
revoke all on flow.favorito from anon;
grant select, insert, delete on flow.favorito to authenticated;
grant all on flow.favorito to service_role;

-- No se crea ninguna funcion de agregado ("N personas lo guardaron"): expondria
-- datos de otros usuarios y el ranking por favoritos es el Paso 9 del plan.

-- ============================================================================
-- Recargar el cache de PostgREST
--
--   Sin esto, la API puede seguir respondiendo PGRST205 ("Could not find the
--   table") durante un rato despues de crear la tabla, porque PostgREST cachea
--   el esquema. La app trata ese codigo como "tabla ausente" y ocultaria el
--   corazon hasta la recarga automatica.
-- ============================================================================
notify pgrst, 'reload schema';

-- ============================================================================
-- Verificacion
-- ============================================================================
select 'tabla' as objeto,
       c.relname as nombre,
       c.relrowsecurity as rls_activo,
       coalesce(array_to_string(c.relacl::text[], ' | '), 'default') as acl
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'flow' and c.relname = 'favorito'
union all
select 'policy', policyname, true, cmd::text || ' → ' || roles::text
from pg_policies
where schemaname = 'flow' and tablename = 'favorito'
order by objeto desc, nombre;