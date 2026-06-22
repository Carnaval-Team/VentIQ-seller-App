-- ============================================================================
-- MIGRACION: tabla de log del bot que reparte agendas (flow.bot_procesar_plan)
-- Guarda CADA corrida sobre un plan: que se hizo, si fallo y por que, y
-- cuantas agendas repartio. Sirve para auditoria y para depurar el background.
-- ============================================================================

create table if not exists flow.bot_log (
  id                bigint generated always as identity primary key,
  id_plan           bigint,                 -- plan procesado (null si ni se leyo)
  id_local_servicio integer,                -- servicio afectado (null si aun no se conocia)
  resultado         text not null,          -- 'ok' | 'sin_movimiento' | 'sin_cupo' | 'error'
  movidos           integer not null default 0,  -- cuantas agendas se crearon en esta corrida
  mensaje           text,                   -- motivo legible / texto del error
  detalle           jsonb,                  -- contexto extra (cupo, sqlstate, etc.)
  created_at        timestamp without time zone not null default current_timestamp
);

-- Consultas tipicas: "ultimas corridas", "historial de un plan / servicio",
-- "solo los errores".
create index if not exists idx_bot_log_created
  on flow.bot_log (created_at desc);

create index if not exists idx_bot_log_plan
  on flow.bot_log (id_plan, created_at desc);

create index if not exists idx_bot_log_local_servicio
  on flow.bot_log (id_local_servicio, created_at desc);

-- Indice parcial para revisar fallos rapido (suelen ser pocos).
create index if not exists idx_bot_log_errores
  on flow.bot_log (created_at desc)
  where resultado = 'error';
