-- ============================================================================
-- MIGRACION: tiempo de anticipacion para cancelacion de reservas en entidad
--
-- Cada entidad define las horas de anticipacion (respecto a la fecha_hora_reserva)
-- dentro de las cuales un cliente puede cancelar su propia reserva.
--   null/0 -> cancelacion deshabilitada (default hasta que se configure)
--   > 0    -> cancelacion permitida si aun faltan al menos N horas
-- ============================================================================

alter table flow.entidad
  add column if not exists horas_anticipacion_cancelacion integer not null default 0;

comment on column flow.entidad.horas_anticipacion_cancelacion is
  'Horas de anticipacion antes de la fecha_hora_reserva dentro de las cuales el cliente puede cancelar su reserva. 0 = cancelacion deshabilitada.';
