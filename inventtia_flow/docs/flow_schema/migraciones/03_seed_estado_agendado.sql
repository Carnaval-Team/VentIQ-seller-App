-- ============================================================================
-- MIGRACION: asegurar un estado "Agendado" en nom_estado_agenda.
-- El bot lo usa como id_estado al crear agendas desde la sala de espera.
-- ============================================================================

insert into flow.nom_estado_agenda (nombre, descripcion)
select 'Agendado', 'Reserva creada automaticamente desde la sala de espera'
where not exists (
  select 1 from flow.nom_estado_agenda where nombre = 'Agendado'
);
