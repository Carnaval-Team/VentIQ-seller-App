create or replace function update_updated_at_column()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create table if not exists public.app_dat_preferencias_notificaciones (
  id_usuario uuid not null,
  estado text not null,
  created_at timestamp with time zone null default now(),
  updated_at timestamp with time zone null default now(),
  constraint app_dat_preferencias_notificaciones_pkey primary key (id_usuario),
  constraint app_dat_preferencias_notificaciones_id_usuario_fkey foreign key (id_usuario) references auth.users (id) on delete cascade,
  constraint app_dat_preferencias_notificaciones_estado_check check (estado in ('aceptado', 'denegado', 'mas_tarde', 'nunca'))
) tablespace pg_default;

create index if not exists idx_preferencias_notificaciones_estado
on public.app_dat_preferencias_notificaciones using btree (estado)
TABLESPACE pg_default;

create trigger update_preferencias_notificaciones_updated_at before
update on app_dat_preferencias_notificaciones for EACH row
execute FUNCTION update_updated_at_column ();

alter table public.app_dat_preferencias_notificaciones enable row level security;

create policy "Usuarios pueden ver su preferencia de notificaciones"
on public.app_dat_preferencias_notificaciones
for select
using (auth.uid() = id_usuario);

create policy "Usuarios pueden crear su preferencia de notificaciones"
on public.app_dat_preferencias_notificaciones
for insert
with check (auth.uid() = id_usuario);

create policy "Usuarios pueden actualizar su preferencia de notificaciones"
on public.app_dat_preferencias_notificaciones
for update
using (auth.uid() = id_usuario)
with check (auth.uid() = id_usuario);

create policy "Usuarios pueden eliminar su preferencia de notificaciones"
on public.app_dat_preferencias_notificaciones
for delete
using (auth.uid() = id_usuario);

create table if not exists public.app_dat_suscripcion_notificaciones_tienda (
  id bigserial not null,
  id_usuario uuid not null,
  id_tienda bigint not null,
  activo boolean not null default true,
  created_at timestamp with time zone null default now(),
  updated_at timestamp with time zone null default now(),
  constraint app_dat_suscripcion_notificaciones_tienda_pkey primary key (id),
  constraint app_dat_suscripcion_notificaciones_tienda_id_usuario_fkey foreign KEY (id_usuario) references auth.users (id) on delete CASCADE,
  constraint app_dat_suscripcion_notificaciones_tienda_id_tienda_fkey foreign KEY (id_tienda) references public.app_dat_tienda (id) on delete CASCADE,
  constraint app_dat_suscripcion_notificaciones_tienda_id_usuario_id_tienda_key unique (id_usuario, id_tienda)
) TABLESPACE pg_default;

create index IF not exists idx_suscripcion_notif_tienda_usuario
on public.app_dat_suscripcion_notificaciones_tienda using btree (id_usuario)
TABLESPACE pg_default;

create index IF not exists idx_suscripcion_notif_tienda_tienda
on public.app_dat_suscripcion_notificaciones_tienda using btree (id_tienda)
TABLESPACE pg_default;

create index IF not exists idx_suscripcion_notif_tienda_activo
on public.app_dat_suscripcion_notificaciones_tienda using btree (activo)
TABLESPACE pg_default;

create trigger update_suscripcion_notificaciones_tienda_updated_at BEFORE
update on app_dat_suscripcion_notificaciones_tienda for EACH row
execute FUNCTION update_updated_at_column ();

alter table public.app_dat_suscripcion_notificaciones_tienda enable row level security;

create policy "Usuarios pueden ver sus suscripciones a tiendas"
on public.app_dat_suscripcion_notificaciones_tienda
for select
using (auth.uid() = id_usuario);

create policy "Usuarios pueden crear sus suscripciones a tiendas"
on public.app_dat_suscripcion_notificaciones_tienda
for insert
with check (auth.uid() = id_usuario);

create policy "Usuarios pueden actualizar sus suscripciones a tiendas"
on public.app_dat_suscripcion_notificaciones_tienda
for update
using (auth.uid() = id_usuario)
with check (auth.uid() = id_usuario);

create policy "Usuarios pueden eliminar sus suscripciones a tiendas"
on public.app_dat_suscripcion_notificaciones_tienda
for delete
using (auth.uid() = id_usuario);

create table if not exists public.app_dat_suscripcion_notificaciones_producto (
  id bigserial not null,
  id_usuario uuid not null,
  id_producto bigint not null,
  activo boolean not null default true,
  created_at timestamp with time zone null default now(),
  updated_at timestamp with time zone null default now(),
  constraint app_dat_suscripcion_notificaciones_producto_pkey primary key (id),
  constraint app_dat_suscripcion_notificaciones_producto_id_usuario_fkey foreign KEY (id_usuario) references auth.users (id) on delete CASCADE,
  constraint app_dat_suscripcion_notificaciones_producto_id_producto_fkey foreign KEY (id_producto) references public.app_dat_producto (id) on delete CASCADE,
  constraint app_dat_suscripcion_notificaciones_producto_id_usuario_id_producto_key unique (id_usuario, id_producto)
) TABLESPACE pg_default;

create index IF not exists idx_suscripcion_notif_producto_usuario
on public.app_dat_suscripcion_notificaciones_producto using btree (id_usuario)
TABLESPACE pg_default;

create index IF not exists idx_suscripcion_notif_producto_producto
on public.app_dat_suscripcion_notificaciones_producto using btree (id_producto)
TABLESPACE pg_default;

create index IF not exists idx_suscripcion_notif_producto_activo
on public.app_dat_suscripcion_notificaciones_producto using btree (activo)
TABLESPACE pg_default;

create trigger update_suscripcion_notificaciones_producto_updated_at BEFORE
update on app_dat_suscripcion_notificaciones_producto for EACH row
execute FUNCTION update_updated_at_column ();

alter table public.app_dat_suscripcion_notificaciones_producto enable row level security;

create policy "Usuarios pueden ver sus suscripciones a productos"
on public.app_dat_suscripcion_notificaciones_producto
for select
using (auth.uid() = id_usuario);

create policy "Usuarios pueden crear sus suscripciones a productos"
on public.app_dat_suscripcion_notificaciones_producto
for insert
with check (auth.uid() = id_usuario);

create policy "Usuarios pueden actualizar sus suscripciones a productos"
on public.app_dat_suscripcion_notificaciones_producto
for update
using (auth.uid() = id_usuario)
with check (auth.uid() = id_usuario);

create policy "Usuarios pueden eliminar sus suscripciones a productos"
on public.app_dat_suscripcion_notificaciones_producto
for delete
using (auth.uid() = id_usuario);
