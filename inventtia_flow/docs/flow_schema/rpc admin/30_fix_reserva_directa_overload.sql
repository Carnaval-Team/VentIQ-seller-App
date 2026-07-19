-- ============================================================================
-- FIX PGRST203: elimina el overload viejo de admin_crear_reserva_directa.
--
-- Existian DOS funciones con el mismo nombre:
--   (integer, date, integer, jsonb, uuid)            <- vieja, sin turno
--   (integer, date, integer, jsonb, uuid, integer)   <- nueva, con p_id_turno
-- PostgREST no puede elegir cual llamar y devuelve:
--   PGRST203 "Could not choose the best candidate function ...".
--
-- Nos quedamos con la de 6 args (soporta reservas con y sin turno; p_id_turno
-- default null = comportamiento legacy). Aplicar manualmente.
-- ============================================================================

drop function if exists flow.admin_crear_reserva_directa(integer, date, integer, jsonb, uuid);

-- Verificacion (debe quedar UNA sola fila, la de 6 args):
--   select p.oid, pg_get_function_identity_arguments(p.oid)
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'flow' and p.proname = 'admin_crear_reserva_directa';
