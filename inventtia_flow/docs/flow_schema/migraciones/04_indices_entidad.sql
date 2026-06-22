-- ============================================================================
-- MIGRACION: indices por id_entidad
-- Aceleran los filtros por entidad en las RPC de cliente y admin
-- (locales/servicios de una entidad, joins de seguridad del panel admin).
-- ============================================================================

create index if not exists idx_locales_entidad
  on flow.app_dat_locales (id_entidad);

create index if not exists idx_servicios_entidad
  on flow.app_dat_servicios (id_entidad);

-- Apoyo para el helper admin_entidades_de_usuario:
create index if not exists idx_entidad_admin_usuario
  on flow.entidad_admin (uuid_usuario);

create index if not exists idx_entidad_owner
  on flow.entidad (owner_uuid);
