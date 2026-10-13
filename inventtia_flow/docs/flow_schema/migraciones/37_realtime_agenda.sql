-- ============================================================================
-- 37 - Realtime del contador de reservas
-- ============================================================================
-- QUE HACE
--   1) Publica `flow.agenda` en `supabase_realtime`, para que el cliente pueda
--      suscribirse a los cambios de sus reservas.
--   2) Pone `replica identity full` en `flow.agenda`.
--
-- POR QUE `replica identity full`
--   El badge se suscribe filtrando por `uuid_usuario` y por `reservado_por`, que
--   NO son la clave primaria. Con la identidad por defecto, el WAL de un UPDATE
--   solo lleva la PK y las columnas que cambiaron: al cambiar `id_estado`, el
--   filtro por `uuid_usuario` no se puede evaluar y el evento se descarta, justo
--   en el caso que interesa (Reservado -> Completado/Cancelado). Con `full`,
--   cada evento lleva la fila entera y el filtro funciona.
--
--   Esto no es una suposicion: `flow.notificaciones` YA esta en `full` y su
--   watcher filtra por `uuid_usuario`; `flow.agenda` estaba en `default`, que es
--   la diferencia entre que el badge se mueva o no.
--
--   Coste: la tabla tiene ~125 filas y poca escritura, asi que el WAL extra es
--   despreciable.
--
-- POR QUE VA TODO EN LA MISMA MIGRACION
--   Publicar sin `replica identity full` daria un badge que a veces no se
--   actualiza: un fallo silencioso y dificil de atribuir. Van juntos.
--
-- ALCANCE
--   Solo `flow.agenda`. Las notificaciones ya estaban publicadas por una
--   migracion anterior y su watcher no se toca.
--
-- ROLLBACK
--   alter publication supabase_realtime drop table flow.agenda;
--   alter table flow.agenda replica identity default;
--   Y revertir el commit del cliente (el provider vuelve a no tener realtime).
--
-- IDEMPOTENTE
--   `add table` falla si la tabla ya es miembro de la publicacion, asi que se
--   comprueba antes.
-- ============================================================================

do $pre$
begin
  if not exists (
    select 1
      from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'flow'
       and tablename = 'agenda'
  ) then
    alter publication supabase_realtime add table flow.agenda;
  end if;
end
$pre$;

alter table flow.agenda replica identity full;

-- ============================================================================
-- VERIFICACION (ejecutar a mano despues de aplicar)
-- ============================================================================
-- 4.a `flow.agenda` es miembro de la publicacion de realtime.
--     Esperado: agenda y notificaciones.
-- select schemaname, tablename
--   from pg_publication_tables
--  where pubname = 'supabase_realtime' and schemaname = 'flow'
--  order by tablename;
--
-- 4.b `replica identity` es `full` en las dos tablas que alimentan badges.
--     Esperado: agenda = full, notificaciones = full.
-- select c.relname,
--        case c.relreplident when 'd' then 'default' when 'f' then 'full'
--                             else c.relreplident::text end as replica_identity
--   from pg_class c
--   join pg_namespace n on n.oid = c.relnamespace
--  where n.nspname = 'flow' and c.relname in ('agenda', 'notificaciones')
--  order by c.relname;
--
-- 4.c La RLS no se toca: es la que Realtime va a evaluar.
--     Esperado: agenda_select_own y agenda_select_dueno_y_admins.
-- select pol.polname
--   from pg_policy pol
--   join pg_class c on c.oid = pol.polrelid
--   join pg_namespace n on n.oid = c.relnamespace
--  where n.nspname = 'flow' and c.relname = 'agenda'
--  order by pol.polname;
--
-- PRUEBA EN DISPOSITIVO
--   Esto NO se puede comprobar desde el agente: hace falta un websocket vivo.
--   1. Abre la app en /home con sesion de cliente y deja el badge a la vista.
--   2. Desde la administracion (o el SQL Editor) cambia una reserva de ese
--      usuario de `Reservado` a `Completado`.
--   3. El badge debe bajar SOLO, sin recargar la pantalla ni volver a la app.
--      (Volver a la app tambien lo actualiza, pero por la red de seguridad de
--      `didChangeAppLifecycleState`, asi que esa no cuenta como prueba.)
--   4. Si no baja, el problema esta en la evaluacion de RLS por parte de
--      Realtime: `agenda_select_dueno_y_admins` llama a una funcion
--      (`es_admin_o_dueno_de_entidad_de_agenda`). Los filtros por
--      `uuid_usuario` y `reservado_por` son columnas simples, asi que si falla,
--      la causa es esa funcion.
-- ============================================================================
