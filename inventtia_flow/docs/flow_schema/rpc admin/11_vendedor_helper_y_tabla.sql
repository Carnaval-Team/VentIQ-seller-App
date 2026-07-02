-- ============================================================================
-- VENDEDOR: tabla entidad_vendedor + RLS + helper
-- Usuarios con rol vendedor asignados a una entidad.
-- Espejo de flow.entidad_admin.
-- ============================================================================

-- ── Tabla ─────────────────────────────────────────────────────────────────────

create sequence if not exists flow.entidad_vendedor_id_seq;

create table if not exists flow.entidad_vendedor (
  id           integer      not null default nextval('flow.entidad_vendedor_id_seq'::regclass),
  id_entidad   integer      not null,
  uuid_usuario uuid         not null,
  asignado_por uuid         not null,
  created_at   timestamp without time zone default current_timestamp,
  constraint entidad_vendedor_pkey
    primary key (id),
  constraint entidad_vendedor_id_entidad_fkey
    foreign key (id_entidad) references flow.entidad(id) on delete cascade,
  constraint entidad_vendedor_uuid_usuario_fkey
    foreign key (uuid_usuario) references auth.users(id),
  constraint entidad_vendedor_asignado_por_fkey
    foreign key (asignado_por) references auth.users(id),
  constraint entidad_vendedor_unique
    unique (id_entidad, uuid_usuario)
);

-- ── RLS ───────────────────────────────────────────────────────────────────────

alter table flow.entidad_vendedor enable row level security;

-- SELECT: el propio vendedor ve sus filas; owners y admins ven las de su entidad
create policy "vendedor_select"
  on flow.entidad_vendedor
  for select
  to authenticated
  using (
    uuid_usuario = auth.uid()
    or id_entidad in (
      select id_entidad from flow.admin_entidades_de_usuario(auth.uid())
    )
  );

-- INSERT: solo owners y admins de la entidad
create policy "vendedor_insert"
  on flow.entidad_vendedor
  for insert
  to authenticated
  with check (
    id_entidad in (
      select id_entidad from flow.admin_entidades_de_usuario(auth.uid())
    )
  );

-- DELETE: solo owners y admins de la entidad
create policy "vendedor_delete"
  on flow.entidad_vendedor
  for delete
  to authenticated
  using (
    id_entidad in (
      select id_entidad from flow.admin_entidades_de_usuario(auth.uid())
    )
  );

-- ── Helper ────────────────────────────────────────────────────────────────────
-- SECURITY DEFINER necesario para que la RPC principal pueda hacer el JOIN
-- contra entidad_vendedor sin que RLS filtre incorrectamente.

create or replace function flow.vendedor_entidades_de_usuario(
  p_uuid_usuario uuid
)
returns table (id_entidad integer)
language sql
stable
security definer
set search_path = flow, public
as $$
  select ev.id_entidad
  from flow.entidad_vendedor ev
  where ev.uuid_usuario = p_uuid_usuario;
$$;

grant execute on function flow.vendedor_entidades_de_usuario(uuid) to authenticated;
