-- ============================================================================
-- MIGRACION: columna 'agendados' en flow.plan_servicios
-- Lleva la cuenta de cuantas agendas ha creado el bot para ese plan.
-- Mientras agendados < cantidad, el bot sigue moviendo gente de sala_espera.
-- ============================================================================

alter table flow.plan_servicios
  add column if not exists agendados integer not null default 0;

-- Indice parcial: el sweep de background solo busca planes con cupo libre.
-- (cantidad null -> predicado null -> fila fuera del indice, que es lo deseado)
create index if not exists idx_plan_servicios_con_cupo
  on flow.plan_servicios (fecha)
  where agendados < cantidad;
