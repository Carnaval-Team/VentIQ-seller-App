-- ============================================================================
-- MIGRACION: cantidad + datos adicionales + reservado_por en agenda/sala_espera.
--
-- agenda.cantidad           : nº de turnos de UNA reserva directa (1..disponibles).
--                             La cola (sala_espera) siempre vale 1 por persona.
-- agenda.datos_adicionales  : valores que llenó el cliente (jsonb { clave: valor }).
-- agenda.reservado_por      : uuid del usuario autenticado que CREÓ la reserva.
--                             Si reservó para sí mismo == uuid_usuario; si reservó
--                             para un tercero, apunta al que la hizo (para que la
--                             vea en "Mis Reservas"). Sin FK a proposito: puede ser
--                             un auth.uid sin perfil; se valida en RPC.
--
-- sala_espera replica datos_adicionales y reservado_por para que el bot los
-- copie a la agenda al repartir la cola.
-- ============================================================================

alter table flow.agenda
  add column if not exists cantidad          integer not null default 1,
  add column if not exists datos_adicionales jsonb,
  add column if not exists reservado_por     uuid;

alter table flow.sala_espera
  add column if not exists datos_adicionales jsonb,
  add column if not exists reservado_por     uuid;

comment on column flow.agenda.cantidad is
  'Cantidad de turnos de una reserva directa (1..disponibles). Cola = 1.';
comment on column flow.agenda.datos_adicionales is
  'Valores de los campos_adicionales del servicio (jsonb { clave: valor }).';
comment on column flow.agenda.reservado_por is
  'Uuid del usuario que creó la reserva (== uuid_usuario si es para sí mismo).';

-- ----------------------------------------------------------------------------
-- RLS sala_espera: permitir anotar/sacar a un TERCERO.
--
-- Las politicas actuales exigen uuid_usuario = auth.uid(), lo que impide que un
-- usuario anote a otra persona (uuid distinto) desde cliente_entrar_sala_espera
-- (security invoker). Se amplian INSERT y DELETE para permitir tambien cuando el
-- usuario autenticado es quien reserva (reservado_por = auth.uid()).
-- ----------------------------------------------------------------------------
drop policy if exists "sala_espera_insert_own" on flow.sala_espera;
create policy "sala_espera_insert_own"
on flow.sala_espera
for insert
to authenticated
with check (
  uuid_usuario = auth.uid() or reservado_por = auth.uid()
);

drop policy if exists "sala_espera_delete_own" on flow.sala_espera;
create policy "sala_espera_delete_own"
on flow.sala_espera
for delete
to authenticated
using (
  uuid_usuario = auth.uid() or reservado_por = auth.uid()
);
