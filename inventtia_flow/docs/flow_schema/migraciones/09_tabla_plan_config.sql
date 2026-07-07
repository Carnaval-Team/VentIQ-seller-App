-- ============================================================================
-- MIGRACION: tabla flow.plan_config
--
-- Configuracion RECURRENTE de capacidades por dia de la semana para un
-- local_servicio. Permite que cada mes sea solo "revisar -> generar" en vez
-- de planificar dia a dia. Una fila por local_servicio (unique).
--
-- Formato de 'config' (jsonb):
--   {
--     "default": 30,                      -- capacidad por defecto
--     "por_dia": { "1": 50, "4": 60 }     -- override por dia ISO (1=lunes..7=domingo)
--   }
--   - Dia sin entrada en por_dia        -> usa "default".
--   - Capacidad 0                        -> ese dia NO se planifica (local cerrado).
--
-- RLS: igual que flow.plan_servicios (ver 05_rls_plan_servicios.sql):
--   SELECT  -> cualquier autenticado.
--   INSERT/UPDATE/DELETE -> solo si el local_servicio pertenece a una entidad
--                           que administra auth.uid().
-- ============================================================================

create table if not exists flow.plan_config (
  id                bigint generated always as identity primary key,
  id_local_servicio integer not null unique
                    references flow.local_servicio(id) on delete cascade,
  config            jsonb   not null,
  activo            boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

comment on table flow.plan_config is
  'Config recurrente de capacidades por dia de la semana para generar plan_servicios en lote.';

-- ----------------------------------------------------------------------------
-- RLS
-- ----------------------------------------------------------------------------
alter table flow.plan_config enable row level security;

drop policy if exists "plan_config_select" on flow.plan_config;
drop policy if exists "plan_config_insert" on flow.plan_config;
drop policy if exists "plan_config_update" on flow.plan_config;
drop policy if exists "plan_config_delete" on flow.plan_config;

-- SELECT: cualquier autenticado puede leer
create policy "plan_config_select"
on flow.plan_config
for select
to authenticated
using (true);

-- INSERT: solo sobre local_servicio de una entidad que administra el usuario
create policy "plan_config_insert"
on flow.plan_config
for insert
to authenticated
with check (
  exists (
    select 1
    from flow.local_servicio  ls
    join flow.app_dat_locales l on l.id = ls.id_local
    where ls.id = plan_config.id_local_servicio
      and l.id_entidad in (
        select id_entidad from flow.admin_entidades_de_usuario(auth.uid())
      )
  )
);

-- UPDATE
create policy "plan_config_update"
on flow.plan_config
for update
to authenticated
using (
  exists (
    select 1
    from flow.local_servicio  ls
    join flow.app_dat_locales l on l.id = ls.id_local
    where ls.id = plan_config.id_local_servicio
      and l.id_entidad in (
        select id_entidad from flow.admin_entidades_de_usuario(auth.uid())
      )
  )
)
with check (
  exists (
    select 1
    from flow.local_servicio  ls
    join flow.app_dat_locales l on l.id = ls.id_local
    where ls.id = plan_config.id_local_servicio
      and l.id_entidad in (
        select id_entidad from flow.admin_entidades_de_usuario(auth.uid())
      )
  )
);

-- DELETE
create policy "plan_config_delete"
on flow.plan_config
for delete
to authenticated
using (
  exists (
    select 1
    from flow.local_servicio  ls
    join flow.app_dat_locales l on l.id = ls.id_local
    where ls.id = plan_config.id_local_servicio
      and l.id_entidad in (
        select id_entidad from flow.admin_entidades_de_usuario(auth.uid())
      )
  )
);
