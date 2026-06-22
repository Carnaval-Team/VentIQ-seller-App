-- ============================================================================
-- MIGRACION: habilitar Supabase Realtime en flow.notificaciones
--
-- La app cliente escucha INSERTs de esta tabla por usuario (la RLS de
-- 06_tabla_notificaciones.sql garantiza que cada quien solo recibe los suyos)
-- para mostrar notificaciones al instante mientras la app esta activa.
--
-- Sin esto, el .stream() de supabase_flutter no emite eventos.
-- Idempotente: si ya esta en la publicacion, no falla.
-- ============================================================================

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'flow'
      and tablename = 'notificaciones'
  ) then
    alter publication supabase_realtime add table flow.notificaciones;
  end if;
end$$;

-- Realtime entrega solo las columnas nuevas en INSERT por defecto; con
-- REPLICA IDENTITY FULL tambien viaja el row completo en UPDATE/DELETE
-- (util si luego se quiere reaccionar a "marcar leida" en otros dispositivos).
alter table flow.notificaciones replica identity full;
