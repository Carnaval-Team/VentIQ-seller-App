-- ============================================================================
-- MIGRACION: capacidades por defecto y maxima por reserva en local_servicio
--
-- cantidad_default: valor inicial cuando un cliente reserva turnos (sin alterar
-- el cupo total del plan).
-- cantidad_max_capacidad: limite maximo de turnos que un cliente puede reservar
-- en una sola operacion (validado contra el cliente de la reserva).
-- ============================================================================

alter table flow.local_servicio
  add column if not exists cantidad_default integer not null default 1,
  add column if not exists cantidad_max_capacidad integer not null default 1;

comment on column flow.local_servicio.cantidad_default is
  'Cantidad de turnos que se ofrece por defecto al cliente cuando hace una reserva.';
comment on column flow.local_servicio.cantidad_max_capacidad is
  'Cantidad maxima de turnos que un cliente puede reservar en una sola operacion.';
