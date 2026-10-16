-- ============================================================================
-- MIGRACION 50: eliminar un turno no puede fallar por clave foranea (FK).
--
-- Problema (F4 del plan): `flow.agenda.id_turno` y `flow.sala_espera.id_turno`
-- se crearon SIN `on delete` (16_recursos_tramos_turnos.sql:130-138), asi que
-- el `delete from flow.turno where id = p_id` de `admin_eliminar_turno`
-- (docs/flow_schema/rpc admin/25_admin_recursos.sql:329) fallaba con 23503
-- cuando el turno tenia reservas o gente en cola.
--
-- Decision del usuario (D1 del plan), distinta por tabla:
--   * `agenda`      -> ON DELETE SET NULL: la reserva ya cobrada NO se pierde,
--                      solo queda sin vinculo al turno (el historial y los
--                      importes se conservan intactos).
--   * `sala_espera` -> ON DELETE CASCADE: una fila de cola con `id_turno` NULL
--                      significa "cualquier turno" para el bot, asi que no
--                      puede quedar NULL; si el turno desaparece, la entrada de
--                      la cola deja de tener sentido y se borra.
--   * `turno_tramo` -> ya cascadeaba (16_...); se reafirma por idempotencia.
--
-- Idempotente: `drop constraint if exists` + `add constraint` con los mismos
-- nombres reales (`agenda_id_turno_fkey`, `sala_espera_id_turno_fkey`,
-- `turno_tramo_id_turno_fkey`), verificados en SQL_OPTIMIZATION/flow.sql:88,103.
--
-- NOTA: lo aplica el usuario a mano en Supabase -> SQL Editor (decision D9).
-- Este fichero no se ejecuta solo.
-- ============================================================================

-- Eliminar un turno ya no puede fallar por FK.
alter table flow.agenda drop constraint if exists agenda_id_turno_fkey;
alter table flow.agenda
  add constraint agenda_id_turno_fkey
  foreign key (id_turno) references flow.turno(id) on delete set null;

alter table flow.sala_espera drop constraint if exists sala_espera_id_turno_fkey;
alter table flow.sala_espera
  add constraint sala_espera_id_turno_fkey
  foreign key (id_turno) references flow.turno(id) on delete cascade;

alter table flow.turno_tramo drop constraint if exists turno_tramo_id_turno_fkey;
alter table flow.turno_tramo
  add constraint turno_tramo_id_turno_fkey
  foreign key (id_turno) references flow.turno(id) on delete cascade;