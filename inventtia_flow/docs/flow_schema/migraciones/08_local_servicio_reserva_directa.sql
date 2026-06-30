-- ============================================================================
-- MIGRACION: flag 'permite_reserva_directa' en flow.local_servicio
--
-- Marca, por servicio-en-un-local, si el cliente puede RESERVAR DIRECTO
-- (saltarse la sala_espera) cuando exista un plan_servicios con cupo ese dia.
--   false (default) -> solo el flujo de cola actual (sala_espera + bot).
--   true            -> ademas habilita "Reservar ahora" en el detalle.
-- Se decide por local_servicio (no por servicio global): un mismo servicio
-- puede permitir reserva directa en un local y no en otro.
-- ============================================================================

alter table flow.local_servicio
  add column if not exists permite_reserva_directa boolean not null default false;

comment on column flow.local_servicio.permite_reserva_directa is
  'Si true, el cliente puede reservar directo (sin cola) cuando hay plan con cupo.';

-- ----------------------------------------------------------------------------
-- Politica RLS de UPDATE (faltaba en local_servicio).
--
-- local_servicio tiene RLS con politicas SELECT/INSERT/DELETE pero NO UPDATE.
-- Como admin_set_reserva_directa corre 'security invoker', sin esta politica el
-- UPDATE se bloquea silenciosamente (0 filas) -> "local_servicio inexistente o
-- sin permiso". Usa el mismo helper flow.is_entidad_admin (security definer) que
-- las demas politicas de la tabla, para consistencia.
-- ----------------------------------------------------------------------------
drop policy if exists "local_servicio_update_admin" on flow.local_servicio;

create policy "local_servicio_update_admin"
on flow.local_servicio
for update
to authenticated
using (
  exists (
    select 1 from flow.app_dat_locales l
    where l.id = local_servicio.id_local
      and flow.is_entidad_admin(l.id_entidad)
  )
)
with check (
  exists (
    select 1 from flow.app_dat_locales l
    where l.id = local_servicio.id_local
      and flow.is_entidad_admin(l.id_entidad)
  )
);
