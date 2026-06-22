-- ============================================================================
-- MIGRACION: tabla de registro de intentos de fraude en sala_espera
-- Guarda cada intento sospechoso para auditoria / bloqueo posterior.
-- ============================================================================

create table if not exists flow.sala_espera_fraude (
  id                bigint generated always as identity primary key,
  uuid_usuario      uuid,
  id_local_servicio integer,
  motivo            text not null,          -- 'duplicado', 'flood', 'local_servicio_inexistente', ...
  detalle           jsonb,                  -- contexto libre (conteos, ventanas, etc.)
  created_at        timestamp without time zone not null default current_timestamp,
  constraint sala_espera_fraude_uuid_fkey
    foreign key (uuid_usuario) references flow.perfil(uuid_usuario)
);

-- Consultas tipicas: "intentos de este usuario", "fraudes recientes"
create index if not exists idx_fraude_usuario
  on flow.sala_espera_fraude (uuid_usuario, created_at desc);

create index if not exists idx_fraude_created
  on flow.sala_espera_fraude (created_at desc);
