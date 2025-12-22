-- Rating Global
create table public.app_dat_application_rating (
  id bigserial not null,
  id_usuario uuid not null,
  rating numeric(2, 1) not null,
  comentario text null,
  created_at timestamp with time zone null default now(),
  updated_at timestamp with time zone null default now(),
  constraint app_dat_app_rating_pkey primary key (id),
  constraint app_dat_tienda_rating_id_usuario_fkey foreign KEY (id_usuario) references auth.users (id) on delete CASCADE,
  constraint app_dat_app_rating_rating_check check (
    (
      (rating >= 1.0)
      and (rating <= 5.0)
    )
  )
) TABLESPACE pg_default;

-- Rating Tienda
create table public.app_dat_tienda_rating (
  id bigserial not null,
  id_tienda bigint not null,
  id_usuario uuid not null,
  rating numeric(2, 1) not null,
  comentario text null,
  created_at timestamp with time zone null default now(),
  updated_at timestamp with time zone null default now(),
  constraint app_dat_tienda_rating_pkey primary key (id),
  constraint app_dat_tienda_rating_id_tienda_id_usuario_key unique (id_tienda, id_usuario),
  constraint app_dat_tienda_rating_id_tienda_fkey foreign KEY (id_tienda) references app_dat_tienda (id) on delete CASCADE,
  constraint app_dat_tienda_rating_id_usuario_fkey foreign KEY (id_usuario) references auth.users (id) on delete CASCADE,
  constraint app_dat_tienda_rating_rating_check check (
    (
      (rating >= 1.0)
      and (rating <= 5.0)
    )
  )
) TABLESPACE pg_default;

create index IF not exists idx_tienda_rating_tienda on public.app_dat_tienda_rating using btree (id_tienda) TABLESPACE pg_default;

create index IF not exists idx_tienda_rating_usuario on public.app_dat_tienda_rating using btree (id_usuario) TABLESPACE pg_default;

create index IF not exists idx_tienda_rating_created on public.app_dat_tienda_rating using btree (created_at desc) TABLESPACE pg_default;

create trigger update_tienda_rating_updated_at BEFORE
update on app_dat_tienda_rating for EACH row
execute FUNCTION update_updated_at_column ();

-- Rating Producto
create table public.app_dat_producto_rating (
  id bigserial not null,
  id_producto bigint not null,
  id_usuario uuid not null,
  rating numeric(2, 1) not null,
  comentario text null,
  created_at timestamp with time zone null default now(),
  updated_at timestamp with time zone null default now(),
  constraint app_dat_producto_rating_pkey primary key (id),
  constraint app_dat_producto_rating_id_producto_id_usuario_key unique (id_producto, id_usuario),
  constraint app_dat_producto_rating_id_producto_fkey foreign KEY (id_producto) references app_dat_producto (id) on delete CASCADE,
  constraint app_dat_producto_rating_id_usuario_fkey foreign KEY (id_usuario) references auth.users (id) on delete CASCADE,
  constraint app_dat_producto_rating_rating_check check (
    (
      (rating >= 1.0)
      and (rating <= 5.0)
    )
  )
) TABLESPACE pg_default;

create index IF not exists idx_producto_rating_producto on public.app_dat_producto_rating using btree (id_producto) TABLESPACE pg_default;

create index IF not exists idx_producto_rating_usuario on public.app_dat_producto_rating using btree (id_usuario) TABLESPACE pg_default;

create index IF not exists idx_producto_rating_created on public.app_dat_producto_rating using btree (created_at desc) TABLESPACE pg_default;

create trigger update_producto_rating_updated_at BEFORE
update on app_dat_producto_rating for EACH row
execute FUNCTION update_updated_at_column ();
