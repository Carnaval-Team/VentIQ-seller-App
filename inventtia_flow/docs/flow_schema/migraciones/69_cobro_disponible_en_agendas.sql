-- ============================================================================
-- MIGRACION 69: `cobro_disponible` en las agendas del cliente
--
-- QUE RESUELVE
--   Para saber si una reserva se puede pagar por adelantado, la app tenia que
--   llamar aparte a `flow.cliente_cobro_info(id_local_servicio)` (una RPC por
--   cada servicio de la lista). Eso sobra: el dato depende solo de la reserva.
--   Ahora `flow.cliente_obtener_agendas` devuelve un campo mas por ticket:
--
--     "cobro_disponible": true | false
--
--   Es exactamente el mismo criterio que `cliente_cobro_info` (migracion 67):
--
--     coalesce(app_dat_servicios.cobro_adelantado, false)
--     and coalesce(cobro_config.activo, false)         -- por ENTIDAD
--
--   De modo que la app pinta el boton "Pagar por adelantado" sin preguntar nada
--   mas, y sin N+1 consultas.
--
-- DETALLE IMPORTANTE: POR QUE NO ES UN `left join flow.cobro_config` A SECAS
--   `flow.cliente_obtener_agendas` NO es `security definer` (correcto: filtra
--   por `p_uuid_usuario`, y si fuera definer cualquier cliente podria pasar el
--   uuid de otro y leer sus reservas). Al correr con los permisos del llamador,
--   la RLS se aplica, y `flow.cobro_config` solo deja leer al admin de la
--   entidad:
--
--     policy cobro_config_select_entidad: using (flow._puede_ver_entidad(id_entidad)
--                                                 or fn_is_superadmin_full_access())
--
--   Con un `left join` directo, a un CLIENTE la fila de `cobro_config` le sale
--   NULL y `cobro_disponible` seria SIEMPRE false, justo para quien lo necesita.
--   Las dos salidas obvias son peores:
--     * abrir la RLS de `cobro_config` a `authenticated`: expone la tabla entera
--       (numero de proveedor, WhatsApp, plantillas) por PostgREST;
--     * hacer `cliente_obtener_agendas` security definer: IDOR de reservas.
--
--   Por eso el criterio vive en un helper minimo `security definer` que solo
--   devuelve un boolean (no revela nada nuevo: `cliente_cobro_info` ya expone
--   esa misma disponibilidad, y mas, a cualquier usuario con sesion), y la RPC
--   sigue siendo invoker. El `left join flow.cobro_config` del criterio queda
--   dentro del helper.
--
-- LO QUE NO CAMBIA
--   * El cuerpo desplegado de `cliente_obtener_agendas` se reproduce TAL CUAL
--     (mismas claves, mismos joins, mismo `order by`, mismo filtro por
--     `p_uuid_usuario` / `reservado_por`); solo se agrega una clave.
--   * Su firma, su DEFAULT (`p_id_estado integer default null`), su volatilidad
--     (STABLE), su `search_path` y sus grants (authenticated) son los mismos.
--     El campo nuevo es aditivo: una app vieja lo ignora.
--
-- REVERSION
--   Volver a aplicar el cuerpo anterior de `cliente_obtener_agendas` (migracion
--   63) y:
--     drop function if exists flow._cobro_disponible(integer);
--   El campo extra en el jsonb no rompe a nadie: se puede dejar.
--
-- IDEMPOTENTE: create or replace + revoke/grant.
-- ============================================================================

-- ══ 1. HELPER: ¿ESTE LOCAL-SERVICIO PIDE PAGO POR ADELANTADO? ═══════════════
-- Exige las DOS condiciones (servicio + interruptor maestro de la entidad), el
-- mismo criterio de `flow.cliente_cobro_info` (migracion 67). Va como definer
-- para que la RLS de `cobro_config` no lo apague cuando lo llama un cliente.

create or replace function flow._cobro_disponible(p_id_local_servicio integer)
returns boolean
language sql
stable
security definer
set search_path = flow, public
as $function$
  select coalesce(s.cobro_adelantado, false) and coalesce(c.activo, false)
  from flow.local_servicio ls
  join flow.app_dat_locales   l on l.id = ls.id_local
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  left join flow.cobro_config c on c.id_entidad = l.id_entidad
  where ls.id = p_id_local_servicio;
$function$;

comment on function flow._cobro_disponible(integer) is
  'true si este local-servicio se puede pagar por adelantado: cobro_adelantado del servicio Y cobro_config.activo de la entidad. Security definer para que la RLS de cobro_config no lo apague al llamarlo un cliente.';

-- ══ 2. AGENDAS DEL CLIENTE (+ cobro_disponible) ════════════════════════════

create or replace function flow.cliente_obtener_agendas(
  p_uuid_usuario uuid,
  p_id_estado    integer default null
)
returns jsonb
language sql
stable
set search_path = flow, public
as $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',                   a.id,
        'fecha_hora_reserva',   a.fecha_hora_reserva,
        'fecha_hora_atencion',  a.fecha_hora_atencion,
        'created_at',           a.created_at,
        'updated_at',           a.updated_at,
        'cantidad',             a.cantidad,
        'datos_adicionales',    a.datos_adicionales,
        'reservado_por',        a.reservado_por,
        'precio_total',         a.precio_total,
        'moneda',               a.moneda,
        'uuid_usuario',         a.uuid_usuario,
        'motivo_cancelacion',   a.motivo_cancelacion,
        'cancelado_por',        a.cancelado_por,
        'cancelado_por_rol',    a.cancelado_por_rol,
        'cancelado_at',         a.cancelado_at,
        'pago_estado',          a.pago_estado,
        'pago_monto',           a.pago_monto,
        'pago_moneda',          a.pago_moneda,
        -- [69] El cliente ya no tiene que preguntar por servicio: aqui viene si
        -- esta reserva se puede pagar por adelantado (servicio + entidad).
        'cobro_disponible',     coalesce(flow._cobro_disponible(ls.id), false),
        'estado', jsonb_build_object(
          'id',          e.id,
          'nombre',      e.nombre,
          'descripcion', e.descripcion
        ),
        'id_local_servicio', ls.id,
        'local_servicio', jsonb_build_object(
          'id',                     ls.id,
          'permite_reserva_directa', ls.permite_reserva_directa,
          'cantidad_default',       ls.cantidad_default,
          'cantidad_max_capacidad', ls.cantidad_max_capacidad
        ),
        'servicio', jsonb_build_object(
          'id',                 s.id,
          'nombre',             s.nombre,
          'descripcion',        s.descripcion,
          'foto',               s.foto,
          'campos_adicionales', s.campos_adicionales
        ),
        'local', jsonb_build_object(
          'id',               l.id,
          'nombre',           l.nombre,
          'direccion',        l.direccion,
          'pais',             l.pais,
          'provincia',        l.provincia,
          'horario_atencion', l.horario_atencion,
          'coordenadas',      l.coordenadas,
          'foto',             l.foto
        ),
        'entidad', jsonb_build_object(
          'id',                             en.id,
          'denominacion',                   en.denominacion,
          'horas_anticipacion_cancelacion', en.horas_anticipacion_cancelacion
        ),
        -- Titular de la reserva (para mostrar "Para: <nombre>" si es un tercero)
        'cliente', case when p.id is null then null else jsonb_build_object(
          'id',           p.id,
          'uuid_usuario', p.uuid_usuario,
          'nombre',       p.nombre,
          'apellidos',    p.apellidos,
          'ci',           p.ci,
          'telefono',     p.telefono
        ) end
      )
      order by a.fecha_hora_reserva desc
    ),
    '[]'::jsonb
  )
  from flow.agenda a
  join flow.local_servicio    ls on ls.id = a.id_local_servicio
  join flow.app_dat_locales   l  on l.id  = ls.id_local
  join flow.app_dat_servicios s  on s.id  = ls.id_servicio
  join flow.nom_estado_agenda e  on e.id  = a.id_estado
  join flow.entidad          en on en.id = l.id_entidad
  left join flow.perfil       p  on p.uuid_usuario = a.uuid_usuario
  -- El usuario ve sus propias reservas Y las que hizo para terceros.
  where (a.uuid_usuario = p_uuid_usuario or a.reservado_por = p_uuid_usuario)
    and (p_id_estado is null or a.id_estado = p_id_estado);
$function$;

comment on function flow.cliente_obtener_agendas(uuid, integer) is
  'Tickets del cliente (propios y a nombre de terceros). Incluye desde la 69 `cobro_disponible`, que combina servicio.cobro_adelantado y cobro_config.activo. Invoker a proposito: la RLS filtra por cliente; NO hacerla security definer.';

-- ══ 3. GRANTS ══════════════════════════════════════════════════════════════

revoke all on function flow._cobro_disponible(integer) from public, anon;
revoke all on function flow.cliente_obtener_agendas(uuid, integer) from public, anon;

grant execute on function flow._cobro_disponible(integer) to authenticated;
grant execute on function flow.cliente_obtener_agendas(uuid, integer) to authenticated;

notify pgrst, 'reload schema';

-- ══ 4. VERIFICACION (ejecutar a mano DESPUES de aplicar) ═══════════════════
--
-- 4.a La firma no cambio y sigue siendo INVOKER (prosecdef = false).
-- select p.proname, p.prosecdef, pg_get_function_identity_arguments(p.oid) as args
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'flow'
--    and p.proname in ('cliente_obtener_agendas', '_cobro_disponible');
--   -- cliente_obtener_agendas: prosecdef = false; _cobro_disponible: true
--
-- 4.b El campo llega en el jsonb de cada ticket:
-- select e ->> 'cobro_disponible' as cobro_disponible
--   from jsonb_array_elements(flow.cliente_obtener_agendas('<uuid_cliente>', null)) e
--  limit 5;
--   -- true/false por reserva; NUNCA null
--
-- 4.c El criterio es el mismo que `cliente_cobro_info` (migracion 67).
--     Escoge un id_local_servicio y compara:
-- select flow._cobro_disponible(<id_local_servicio>)             as helper,
--        flow.cliente_cobro_info(<id_local_servicio>)
--          -> 'data' ->> 'disponible'                              as rpc;
--   -- true/false + null | "true"
--
-- 4.d Con el cobro apagado no aparece (se prueba desde una sesion de admin):
-- update flow.app_dat_servicios set cobro_adelantado = false where id = <id_servicio>;
-- select flow._cobro_disponible(<id_local_servicio>);   -- false
-- update flow.app_dat_servicios set cobro_adelantado = true  where id = <id_servicio>;
-- select flow._cobro_disponible(<id_local_servicio>);   -- true (si la entidad lo tiene activo)
--
-- 4.e PRUEBA CON SESION DE CLIENTE (la que de verdad importa): abrir "Mis
--     reservas" con un cliente y comprobar que el boton "Pagar por adelantado"
--     aparece en las reservas de servicios que cobran y NO en las demas. Desde
--     el SQL Editor el rol es `postgres` y la RLS de `cobro_config` no aplica,
--     asi que ese caso (cliente sin permisos sobre la entidad) solo se ve en la
--     app o con un JWT de cliente.