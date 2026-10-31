-- ============================================================================
-- MIGRACION 70: Realtime del circuito de pago por adelantado
--
-- QUE RESUELVE
--   El pago por adelantado se "mueve solo" en varios sitios a la vez: el cliente
--   pulsa "Ya he pagado", el admin lo ve en su bandeja, el admin verifica o el
--   cron expira y cancela. Hoy todas esas pantallas solo se enteran al
--   recargar. Para que se actualicen solas, las tablas que mueven el estado
--   tienen que estar en la publicacion de Supabase Realtime y —las que se
--   filtran por columnas que no son la PK— con `replica identity full`.
--
-- QUE HACE
--   1. Publica en `supabase_realtime`:
--        * flow.reserva_pago    (el intento: creado -> reportado -> verificado...)
--        * flow.cobro_config    (el admin activa/cambia el cobro de la entidad)
--        * flow.app_dat_servicios (el admin marca que servicio cobra; columna
--                                  `cobro_adelantado` de la migracion 67)
--   2. `alter table flow.reserva_pago replica identity full`.
--   3. Documenta la advertencia de RLS-en-Realtime de la migracion 37 y deja una
--      politica de lectura adicional apta para Realtime (sin ampliar permisos).
--
-- POR QUE `replica identity full` EN reserva_pago (y NO en las otras dos)
--   Es la misma razon que documenta la migracion 37 para `flow.agenda`: el WAL
--   de un UPDATE, con la identidad por defecto, solo lleva la PK y las columnas
--   que cambiaron; la tupla VIEJA queda recortada a la PK. Realtime necesita la
--   fila para evaluar la RLS y los filtros, y `reserva_pago` se suscribe
--   filtrando por `uuid_usuario` (no es la PK) porque el cliente solo debe
--   recibir SUS pagos. Con `full`, cada evento lleva la fila entera.
--
--   `flow.cobro_config`: su PK es `id_entidad`, que es justo por lo que se
--   filtran los admin (o se lee la tabla entera); la identidad por defecto basta.
--   `flow.app_dat_servicios`: se filtra por `id` (PK). Tampoco hace falta.
--   Las dos son tablas pequenas y de baja escritura. Si algun dia se suscribe
--   por una columna que no es la PK **y** se depende del registro viejo
--   (UPDATE/DELETE), habria que ponerlas en `full` tambien.
--
-- ADVERTENCIA DE RLS EN REALTIME (lo que ya documenta la migracion 37)
--   Realtime evalua la RLS de la tabla con el rol `authenticated` del JWT. Las
--   politicas que llaman a funciones `security definer` pueden evaluarse mal en
--   ese contexto y hacer que el evento se descarte EN SILENCIO. En la 37 paso en
--   `flow.agenda`, que usa `es_admin_o_dueno_de_entidad_de_agenda`; la prueba de
--   fuego es en dispositivo, porque desde el SQL Editor no se puede simular un
--   websocket vivo.
--
--   Estado de las tres tablas de esta migracion frente a esa advertencia:
--     * flow.app_dat_servicios -> policy `servicios_select_all` es `using (true)`.
--       Segura para Realtime.
--     * flow.reserva_pago -> policy `reserva_pago_select_propio` es
--       `uuid_usuario = auth.uid() OR flow._puede_ver_entidad(id_entidad)`.
--       La parte del cliente es una columna simple; la del admin depende de una
--       funcion definer.
--     * flow.cobro_config -> policy `cobro_config_select_entidad` usa
--       `_puede_ver_entidad`. Los CLIENTES no pueden leer esta tabla a
--       proposito (solo el admin de la entidad), asi que un cliente NUNCA
--       recibira eventos de config: no los necesita, porque lo que le importa
--       llega en `agenda`/`cobro_disponible` y, si el cobro se apaga, las RPC
--       devuelven el error accionable de la 68.
--
--   Por eso se agrega en `flow.reserva_pago` una politica de SELECT extra,
--   `reserva_pago_select_realtime`, basada SOLO en una columna simple
--   (`uuid_usuario = auth.uid()`). Es un subconjunto exacto de la politica que
--   ya existe: no amplia ni un permiso, no cambia filas visibles y se puede
--   borrar sin efecto funcional. Sirve para que la comprobacion de RLS del
--   camino del CLIENTE no dependa de una funcion.
--
--     NOTA: Postgres combina las politicas SELECT permisivas con OR, asi que en
--     el camino del ADMIN la funcion `_puede_ver_entidad` se sigue evaluando.
--     Si en dispositivo se comprueba que los eventos de admin no llegan, la
--     salida NO es tocar esta politica: es hacer que la pantalla del admin
--     recargue al abrir/enfocar (como ya hace la app con la red de seguridad de
--     `didChangeAppLifecycleState`) o exponer una vista/tabla espejo con RLS
--     simple para la bandeja.
--
-- LO QUE NO CAMBIA
--   * No se toca ninguna politica existente ni ningun grant.
--   * Las tablas ya tienen `grant select` a `authenticated` (migracion 62), que
--     es lo que Realtime necesita para el rol del JWT.
--   * `flow.agenda` y `flow.notificaciones` ya estaban publicadas (37 y 7).
--
-- REVERSION
--   alter publication supabase_realtime drop table flow.reserva_pago;
--   alter publication supabase_realtime drop table flow.cobro_config;
--   alter publication supabase_realtime drop table flow.app_dat_servicios;
--   alter table flow.reserva_pago replica identity default;
--   drop policy if exists reserva_pago_select_realtime on flow.reserva_pago;
--
-- IDEMPOTENTE: `add table` falla si la tabla ya esta publicada y el bloque DO
-- captura `duplicate_object`; `replica identity` y `drop policy if exists` se
-- pueden repetir.
-- ============================================================================

-- ══ 1. PUBLICAR LAS TABLAS DEL COBRO ═══════════════════════════════════════

do $realtime$
declare
  v_tabla text;
begin
  foreach v_tabla in array array['cobro_config', 'app_dat_servicios', 'reserva_pago']
  loop
    begin
      execute format('alter publication supabase_realtime add table flow.%I', v_tabla);
    exception
      when duplicate_object then
        null;  -- ya estaba publicada: no hay nada que hacer
      when undefined_object then
        raise notice 'La publicacion supabase_realtime no existe; no se publico flow.%', v_tabla;
    end;
  end loop;
end
$realtime$;

-- ══ 2. REPLICA IDENTITY PARA PODER FILTRAR POR uuid_usuario ════════════════

alter table flow.reserva_pago replica identity full;

-- ══ 3. RLS APTA PARA REALTIME (ADITIVA, NO AMPLIA PERMISOS) ════════════════
-- Subconjunto exacto de `reserva_pago_select_propio`
-- (uuid_usuario = auth.uid() YA es una de sus dos ramas). Existe para que el
-- camino del cliente en Realtime evalue una columna simple y no una funcion
-- definer. Si alguna vez estorba, se borra sin cambiar nada visible.

drop policy if exists reserva_pago_select_realtime on flow.reserva_pago;

create policy reserva_pago_select_realtime on flow.reserva_pago
  for select to authenticated
  using (uuid_usuario = auth.uid());

notify pgrst, 'reload schema';

-- ══ 4. VERIFICACION (ejecutar a mano DESPUES de aplicar) ═══════════════════
--
-- 4.a Las tres tablas estan publicadas (ademas de agenda y notificaciones).
-- select schemaname, tablename
--   from pg_publication_tables
--  where pubname = 'supabase_realtime' and schemaname = 'flow'
--  order by tablename;
--   -- agenda, app_dat_servicios, cobro_config, notificaciones, reserva_pago
--
-- 4.b `reserva_pago` quedo en `full`; las otras dos siguen en `default`.
-- select c.relname,
--        case c.relreplident when 'd' then 'default' when 'f' then 'full'
--                             else c.relreplident::text end as replica_identity
--   from pg_class c
--   join pg_namespace n on n.oid = c.relnamespace
--  where n.nspname = 'flow'
--    and c.relname in ('reserva_pago', 'cobro_config', 'app_dat_servicios')
--  order by c.relname;
--   -- reserva_pago = full; las otras dos = default
--
-- 4.c La politica nueva es un subconjunto de la existente.
-- select polname, pg_get_expr(polqual, polrelid) as using_expr
--   from pg_policy
--  where polrelid = 'flow.reserva_pago'::regclass
--  order by polname;
--
-- 4.d Una tabla ya publicada no rompe si se reaplica la migracion:
--     ejecutar este archivo dos veces seguidas y comprobar que no hay error.
--
-- PRUEBA EN DISPOSITIVO (no se puede hacer desde el agente)
--   1. Cliente con sesion en "Mis reservas" con una reserva que cobra por
--      adelantado; dejar la pantalla a la vista.
--   2. Desde el panel del admin (u otra sesion), verificar/rechazar ese pago
--      (o ejecutar `select flow.admin_rechazar_pago_reserva(<id>, 'prueba')`).
--   3. El chip de pago del cliente debe cambiar SOLO, sin recargar.
--   4. Si no cambia: mirar si el cliente es el dueño del intento
--      (`uuid_usuario = auth.uid()`), que la tabla este publicada (4.a) y que
--      `replica identity` sea `full` (4.b). Con el filtro por `id_agenda` o
--      `uuid_usuario`, el evento no necesita la funcion definer.
--   5. Prueba equivalente del lado admin con la bandeja de pagos. Si falla, ver
--      la NOTA sobre `_puede_ver_entidad` de la cabecera: no se arregla con una
--      politica, se arregla con recarga al enfocar.