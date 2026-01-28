create or replace function update_updated_at_column()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create table if not exists public.app_dat_actividad_usuario (
  token uuid not null,
  app text not null,
  ultimo_accesso timestamp with time zone not null default now(),
  cantidad_de_accessos integer not null default 1,
  created_at timestamp with time zone null default now(),
  updated_at timestamp with time zone null default now(),
  constraint app_dat_actividad_usuario_pkey primary key (token, app)
) tablespace pg_default;

create index if not exists idx_actividad_usuario_app
on public.app_dat_actividad_usuario using btree (app)
TABLESPACE pg_default;

create trigger update_actividad_usuario_updated_at before
update on app_dat_actividad_usuario for EACH row
execute FUNCTION update_updated_at_column ();

alter table public.app_dat_actividad_usuario enable row level security;

create policy "Public puede insertar actividad"
on public.app_dat_actividad_usuario
for insert
with check (true);

create policy "Public puede actualizar actividad"
on public.app_dat_actividad_usuario
for update
using (true)
with check (true);

create or replace function public.fn_upsert_actividad_usuario(
  p_token uuid,
  p_app text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.app_dat_actividad_usuario (
    token,
    app,
    ultimo_accesso,
    cantidad_de_accessos
  )
  values (p_token, p_app, now(), 1)
  on conflict (token, app)
  do update
  set ultimo_accesso = now(),
      cantidad_de_accessos =
          app_dat_actividad_usuario.cantidad_de_accessos + 1;
end;
$$;

grant execute on function public.fn_upsert_actividad_usuario(uuid, text)
  to anon, authenticated;
