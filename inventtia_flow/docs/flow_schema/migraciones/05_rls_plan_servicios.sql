-- ============================================================================
-- MIGRACION: RLS para flow.plan_servicios
--
-- Reglas:
--   SELECT  → cualquier usuario autenticado puede leer (panel admin + cliente).
--   INSERT  → solo si el id_local_servicio pertenece a una entidad que el
--             usuario administra (owner_uuid o entidad_admin).
--   UPDATE  → igual que INSERT (solo sus propios plan_servicios).
--   DELETE  → igual que INSERT.
--
-- La cadena de propiedad es:
--   plan_servicios.id_local_servicio
--     → local_servicio.id_local
--       → app_dat_locales.id_entidad
--         → entidad.owner_uuid  /  entidad_admin.uuid_usuario
-- ============================================================================

-- 1. Habilitar RLS
alter table flow.plan_servicios enable row level security;

-- 2. Eliminar politicas previas si existen (idempotente)
drop policy if exists "plan_servicios_select"  on flow.plan_servicios;
drop policy if exists "plan_servicios_insert"  on flow.plan_servicios;
drop policy if exists "plan_servicios_update"  on flow.plan_servicios;
drop policy if exists "plan_servicios_delete"  on flow.plan_servicios;

-- ============================================================================
-- SELECT: cualquier autenticado puede leer
-- ============================================================================
create policy "plan_servicios_select"
on flow.plan_servicios
for select
to authenticated
using (true);

-- ============================================================================
-- Helper inline: ¿el usuario actual administra la entidad del local_servicio?
-- Reutiliza flow.admin_entidades_de_usuario para no duplicar lógica.
-- ============================================================================

-- INSERT
create policy "plan_servicios_insert"
on flow.plan_servicios
for insert
to authenticated
with check (
  exists (
    select 1
    from flow.local_servicio    ls
    join flow.app_dat_locales   l  on l.id = ls.id_local
    where ls.id = plan_servicios.id_local_servicio
      and l.id_entidad in (
        select id_entidad
        from flow.admin_entidades_de_usuario(auth.uid())
      )
  )
);

-- UPDATE
create policy "plan_servicios_update"
on flow.plan_servicios
for update
to authenticated
using (
  exists (
    select 1
    from flow.local_servicio    ls
    join flow.app_dat_locales   l  on l.id = ls.id_local
    where ls.id = plan_servicios.id_local_servicio
      and l.id_entidad in (
        select id_entidad
        from flow.admin_entidades_de_usuario(auth.uid())
      )
  )
)
with check (
  exists (
    select 1
    from flow.local_servicio    ls
    join flow.app_dat_locales   l  on l.id = ls.id_local
    where ls.id = plan_servicios.id_local_servicio
      and l.id_entidad in (
        select id_entidad
        from flow.admin_entidades_de_usuario(auth.uid())
      )
  )
);

-- DELETE
create policy "plan_servicios_delete"
on flow.plan_servicios
for delete
to authenticated
using (
  exists (
    select 1
    from flow.local_servicio    ls
    join flow.app_dat_locales   l  on l.id = ls.id_local
    where ls.id = plan_servicios.id_local_servicio
      and l.id_entidad in (
        select id_entidad
        from flow.admin_entidades_de_usuario(auth.uid())
      )
  )
);
