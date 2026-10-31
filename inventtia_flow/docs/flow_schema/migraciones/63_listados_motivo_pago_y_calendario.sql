-- ============================================================================
-- MIGRACION 63: listados con motivo de cancelacion y estado de pago +
--               resumen calendario de reservas para el admin
--
-- QUE RESUELVE
--   1. El motivo de la cancelacion (migracion 61) y el estado del pago por
--      adelantado (migracion 62) tienen que LLEGAR a la app. Se devuelven en los
--      4 listados existentes. NO se meten en `datos_adicionales` a proposito:
--      `reservas_screen` autodescubre las claves de ese jsonb y las pinta como
--      filas y como COLUMNAS del PDF/Excel, asi que un motivo ahi se filtraria
--      a las exportaciones y a reservas que no se cancelaron.
--   2. El admin necesita un resumen-calendario de TODAS las reservas de su
--      entidad, desde hoy hasta el ultimo mes que tenga reservas, con vista de
--      calendario y vista de lista (estilo to-do).
--
-- FUNCIONES RECREADAS (misma firma: CREATE OR REPLACE, sin sobrecargas)
--   * flow.admin_listar_agendas             (+6 campos)
--   * flow.admin_listar_agendas_por_estado  (+6 campos)
--   * flow.vendedor_listar_agendas          (+6 campos)
--   * flow.cliente_obtener_agendas          (+6 campos)
--   Campos nuevos en cada item:
--     motivo_cancelacion, cancelado_por, cancelado_por_rol, cancelado_at,
--     pago_estado, pago_monto, pago_moneda
--
-- FUNCION NUEVA
--   * flow.admin_calendario_reservas(p_uuid_usuario, p_id_entidad, p_desde, p_hasta)
--     - rango por defecto: de HOY al ULTIMO mes con reservas de la entidad.
--     - devuelve un dia por fecha (incluidos los dias sin reservas, con total 0)
--       y, dentro de cada dia, los items ya listos para pintar.
--
-- LO QUE NO CAMBIA
--   * Los filtros y el orden de los listados: identicos (fecha_hora_reserva desc).
--   * `cliente_obtener_agendas` sigue devolviendo las reservas propias Y las que
--     el usuario hizo para terceros.
--
-- REVERSION
--   Volver a aplicar los cuerpos de `sync_flow_newa_desde_main.sql` (listados) y
--   `drop function if exists flow.admin_calendario_reservas(uuid, integer, date, date);`
--
-- IDEMPOTENTE: create or replace en todo.
-- ============================================================================

-- ══ 1. admin_listar_agendas ════════════════════════════════════════════════

create or replace function flow.admin_listar_agendas(
  p_uuid_usuario uuid,
  p_id_entidad integer default null,
  p_id_local integer default null,
  p_id_local_servicio integer default null,
  p_id_estado integer default null,
  p_desde timestamp without time zone default null,
  p_hasta timestamp without time zone default null
)
returns jsonb
language sql
stable
security definer
set search_path = flow, public
as $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',                  a.id,
        'uuid_usuario',        a.uuid_usuario,
        'id_estado',           a.id_estado,
        'fecha_hora_reserva',  a.fecha_hora_reserva,
        'fecha_hora_atencion', a.fecha_hora_atencion,
        'created_at',          a.created_at,
        'updated_at',          a.updated_at,
        'cantidad',            a.cantidad,
        'datos_adicionales',   a.datos_adicionales,
        'reservado_por',       a.reservado_por,
        'precio_total',        a.precio_total,
        'moneda',              a.moneda,
        'id_turno',            a.id_turno,
        'id_viaje',            a.id_viaje,
        'tipo_trayecto',       a.tipo_trayecto,
        -- [63] Cancelacion y pago
        'motivo_cancelacion',  a.motivo_cancelacion,
        'cancelado_por',       a.cancelado_por,
        'cancelado_por_rol',   a.cancelado_por_rol,
        'cancelado_at',        a.cancelado_at,
        'pago_estado',         a.pago_estado,
        'pago_monto',          a.pago_monto,
        'pago_moneda',         a.pago_moneda,
        'turno', case when t.id is null then null else jsonb_build_object(
          'id',     t.id,
          'nombre', t.nombre,
          'recurso', jsonb_build_object('id', r.id, 'nombre', r.nombre)
        ) end,
        'estado', jsonb_build_object(
          'id',          es.id,
          'nombre',      es.nombre,
          'descripcion', es.descripcion
        ),
        'id_local_servicio', ls.id,
        'servicio', jsonb_build_object(
          'id',                 s.id,
          'nombre',             s.nombre,
          'descripcion',        s.descripcion,
          'foto',               s.foto,
          'campos_adicionales', s.campos_adicionales,
          'config_precio',      s.config_precio
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
          'id',           en.id,
          'denominacion', en.denominacion,
          'direccion',    en.direccion,
          'telefono',     en.telefono
        ),
        'cliente', case when p.id is null then null else jsonb_build_object(
          'id',           p.id,
          'uuid_usuario', p.uuid_usuario,
          'nombre',       p.nombre,
          'apellidos',    p.apellidos,
          'ci',           p.ci,
          'telefono',     p.telefono,
          'created_at',   p.created_at,
          'updated_at',   p.updated_at
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
  join flow.entidad           en on en.id = l.id_entidad
  join flow.nom_estado_agenda es on es.id = a.id_estado
  left join flow.perfil       p  on p.uuid_usuario = a.uuid_usuario
  left join flow.turno        t  on t.id = a.id_turno
  left join flow.recurso      r  on r.id = t.id_recurso
  join flow.admin_entidades_de_usuario(auth.uid()) mine on mine.id_entidad = l.id_entidad
  where (p_id_entidad        is null or l.id_entidad         = p_id_entidad)
    and (p_id_local          is null or ls.id_local          = p_id_local)
    and (p_id_local_servicio is null or a.id_local_servicio  = p_id_local_servicio)
    and (p_id_estado         is null or a.id_estado          = p_id_estado)
    and (p_desde             is null or a.fecha_hora_reserva::date >= p_desde::date)
    and (p_hasta             is null or a.fecha_hora_reserva::date <= p_hasta::date);
$function$;

-- ══ 2. admin_listar_agendas_por_estado ════════════════════════════════════

create or replace function flow.admin_listar_agendas_por_estado(
  p_uuid_usuario uuid,
  p_id_entidad integer default null,
  p_id_local integer default null,
  p_id_local_servicio integer default null,
  p_id_estado integer default null
)
returns jsonb
language sql
stable
security definer
set search_path = flow, public
as $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',                  a.id,
        'uuid_usuario',        a.uuid_usuario,
        'id_estado',           a.id_estado,
        'fecha_hora_reserva',  a.fecha_hora_reserva,
        'fecha_hora_atencion', a.fecha_hora_atencion,
        'created_at',          a.created_at,
        'updated_at',          a.updated_at,
        'cantidad',            a.cantidad,
        'datos_adicionales',   a.datos_adicionales,
        'reservado_por',       a.reservado_por,
        'precio_total',        a.precio_total,
        'moneda',              a.moneda,
        'id_turno',            a.id_turno,
        'id_viaje',            a.id_viaje,
        'tipo_trayecto',       a.tipo_trayecto,
        'motivo_cancelacion',  a.motivo_cancelacion,
        'cancelado_por',       a.cancelado_por,
        'cancelado_por_rol',   a.cancelado_por_rol,
        'cancelado_at',        a.cancelado_at,
        'pago_estado',         a.pago_estado,
        'pago_monto',          a.pago_monto,
        'pago_moneda',         a.pago_moneda,
        'turno', case when t.id is null then null else jsonb_build_object(
          'id',     t.id,
          'nombre', t.nombre,
          'recurso', jsonb_build_object('id', r.id, 'nombre', r.nombre)
        ) end,
        'estado', jsonb_build_object(
          'id',          es.id,
          'nombre',      es.nombre,
          'descripcion', es.descripcion
        ),
        'id_local_servicio', ls.id,
        'servicio', jsonb_build_object(
          'id',                 s.id,
          'nombre',             s.nombre,
          'descripcion',        s.descripcion,
          'foto',               s.foto,
          'campos_adicionales', s.campos_adicionales,
          'config_precio',      s.config_precio
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
          'id',           en.id,
          'denominacion', en.denominacion,
          'direccion',    en.direccion,
          'telefono',     en.telefono
        ),
        'cliente', case when p.id is null then null else jsonb_build_object(
          'id',           p.id,
          'uuid_usuario', p.uuid_usuario,
          'nombre',       p.nombre,
          'apellidos',    p.apellidos,
          'ci',           p.ci,
          'telefono',     p.telefono,
          'created_at',   p.created_at,
          'updated_at',   p.updated_at
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
  join flow.entidad           en on en.id = l.id_entidad
  join flow.nom_estado_agenda es on es.id = a.id_estado
  left join flow.perfil       p  on p.uuid_usuario = a.uuid_usuario
  left join flow.turno        t  on t.id = a.id_turno
  left join flow.recurso      r  on r.id = t.id_recurso
  join flow.admin_entidades_de_usuario(auth.uid()) mine
    on mine.id_entidad = l.id_entidad
  where (p_id_entidad        is null or l.id_entidad         = p_id_entidad)
    and (p_id_local          is null or ls.id_local          = p_id_local)
    and (p_id_local_servicio is null or a.id_local_servicio  = p_id_local_servicio)
    and (p_id_estado         is null or a.id_estado          = p_id_estado)
    and a.fecha_hora_reserva::date >= (timezone('America/Havana', now()))::date;
$function$;

-- ══ 3. vendedor_listar_agendas ════════════════════════════════════════════

create or replace function flow.vendedor_listar_agendas(
  p_uuid_usuario uuid,
  p_id_entidad integer default null,
  p_id_local integer default null,
  p_id_local_servicio integer default null,
  p_id_estado integer default null,
  p_desde timestamp without time zone default null,
  p_hasta timestamp without time zone default null
)
returns jsonb
language sql
stable
security definer
set search_path = flow, public
as $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',                  a.id,
        'fecha_hora_reserva',  a.fecha_hora_reserva,
        'fecha_hora_atencion', a.fecha_hora_atencion,
        'created_at',          a.created_at,
        'updated_at',          a.updated_at,
        'cantidad',            a.cantidad,
        'datos_adicionales',   a.datos_adicionales,
        'reservado_por',       a.reservado_por,
        'precio_total',        a.precio_total,
        'moneda',              a.moneda,
        'id_estado',           a.id_estado,
        'id_turno',            a.id_turno,
        'id_viaje',            a.id_viaje,
        'tipo_trayecto',       a.tipo_trayecto,
        'motivo_cancelacion',  a.motivo_cancelacion,
        'cancelado_por',       a.cancelado_por,
        'cancelado_por_rol',   a.cancelado_por_rol,
        'cancelado_at',        a.cancelado_at,
        'pago_estado',         a.pago_estado,
        'pago_monto',          a.pago_monto,
        'pago_moneda',         a.pago_moneda,
        'turno', case when t.id is null then null else jsonb_build_object(
          'id',     t.id,
          'nombre', t.nombre,
          'recurso', jsonb_build_object('id', r.id, 'nombre', r.nombre)
        ) end,
        'estado', jsonb_build_object(
          'id',          es.id,
          'nombre',      es.nombre,
          'descripcion', es.descripcion
        ),
        'id_local_servicio', ls.id,
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
          'id',           en.id,
          'denominacion', en.denominacion,
          'direccion',    en.direccion,
          'telefono',     en.telefono
        ),
        'cliente', case when p.id is null then null else jsonb_build_object(
          'id',           p.id,
          'uuid_usuario', p.uuid_usuario,
          'nombre',       p.nombre,
          'apellidos',    p.apellidos,
          'ci',           p.ci,
          'telefono',     p.telefono,
          'created_at',   p.created_at,
          'updated_at',   p.updated_at
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
  join flow.entidad           en on en.id = l.id_entidad
  join flow.nom_estado_agenda es on es.id = a.id_estado
  left join flow.perfil       p  on p.uuid_usuario = a.uuid_usuario
  left join flow.turno        t  on t.id = a.id_turno
  left join flow.recurso      r  on r.id = t.id_recurso
  join flow.entidad_vendedor  ev on ev.id_entidad  = l.id_entidad
                                and ev.uuid_usuario = auth.uid()
  where (p_id_entidad        is null or l.id_entidad         = p_id_entidad)
    and (p_id_local          is null or ls.id_local          = p_id_local)
    and (p_id_local_servicio is null or a.id_local_servicio  = p_id_local_servicio)
    and (p_id_estado         is null or a.id_estado          = p_id_estado)
    and (p_desde             is null or a.fecha_hora_reserva >= p_desde)
    and (p_hasta             is null or a.fecha_hora_reserva <= p_hasta);
$function$;

-- ══ 4. cliente_obtener_agendas ════════════════════════════════════════════

create or replace function flow.cliente_obtener_agendas(
  p_uuid_usuario uuid,
  p_id_estado integer default null
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

-- ══ 5. admin_calendario_reservas ══════════════════════════════════════════
-- Resumen-calendario: un dia por fecha desde HOY hasta el ULTIMO mes con
-- reservas de la entidad (o hasta `p_hasta` si el admin lo pide). Cada dia trae
-- sus items ya listos para la vista de lista (to-do) y los contadores para la
-- vista de calendario. Los dias sin reservas vienen con total 0: el calendario
-- necesita la serie completa para pintar el mes.

create or replace function flow.admin_calendario_reservas(
  p_uuid_usuario  uuid,
  p_id_entidad    integer,
  p_desde         date default null,
  p_hasta         date default null,
  p_incluir_items boolean default true
)
returns jsonb
language plpgsql
stable
security definer
set search_path = flow, public
as $function$
declare
  v_hoy        date := (timezone('America/Havana', now()))::date;
  v_desde      date;
  v_hasta      date;
  v_ultimo     date;
  v_truncado   boolean := false;
  v_tope       date;
  v_dias       jsonb;
  v_resumen    jsonb;
  v_permitido  boolean;
begin
  select exists (
    select 1 from flow.admin_entidades_de_usuario(p_uuid_usuario) m
    where m.id_entidad = p_id_entidad
  ) or public.fn_is_superadmin_full_access()
    into v_permitido;

  if not v_permitido then
    return jsonb_build_object('ok', false, 'error', 'No tiene permisos sobre esta entidad');
  end if;

  v_desde := coalesce(p_desde, v_hoy);

  -- Ultimo dia con reserva de la entidad (de hoy en adelante).
  select max((a.fecha_hora_reserva at time zone 'America/Havana')::date)
    into v_ultimo
  from flow.agenda a
  join flow.local_servicio  ls on ls.id = a.id_local_servicio
  join flow.app_dat_locales l  on l.id  = ls.id_local
  where l.id_entidad = p_id_entidad
    and (a.fecha_hora_reserva at time zone 'America/Havana')::date >= v_desde;

  -- Por defecto se llega al ultimo dia del ultimo mes con reservas.
  v_hasta := coalesce(
    p_hasta,
    case when v_ultimo is null then v_desde
         else (date_trunc('month', v_ultimo::timestamp) + interval '1 month - 1 day')::date
    end
  );

  if v_hasta < v_desde then
    v_hasta := v_desde;
  end if;

  -- Tope de seguridad: 24 meses. Un rango absurdo no puede tumbar la pantalla.
  v_tope := (v_desde + interval '24 months')::date;
  if v_hasta > v_tope then
    v_hasta := v_tope;
    v_truncado := true;
  end if;

  with base as (
    select
      a.id,
      a.fecha_hora_reserva,
      a.fecha_hora_atencion,
      a.cantidad,
      a.precio_total,
      a.moneda,
      a.id_estado,
      a.motivo_cancelacion,
      a.cancelado_por_rol,
      a.pago_estado,
      a.pago_monto,
      a.pago_moneda,
      (a.fecha_hora_reserva at time zone 'America/Havana')::date as dia,
      es.nombre  as estado_nombre,
      s.nombre   as servicio_nombre,
      l.nombre   as local_nombre,
      ls.id      as id_local_servicio,
      coalesce(nullif(btrim(coalesce(p.nombre, '') || ' ' || coalesce(p.apellidos, '')), ''),
               'Cliente') as cliente_nombre,
      p.telefono as cliente_telefono,
      t.nombre   as turno_nombre
    from flow.agenda a
    join flow.local_servicio    ls on ls.id = a.id_local_servicio
    join flow.app_dat_locales   l  on l.id  = ls.id_local
    join flow.app_dat_servicios s  on s.id  = ls.id_servicio
    join flow.nom_estado_agenda es on es.id = a.id_estado
    left join flow.perfil       p  on p.uuid_usuario = a.uuid_usuario
    left join flow.turno        t  on t.id = a.id_turno
    where l.id_entidad = p_id_entidad
      and (a.fecha_hora_reserva at time zone 'America/Havana')::date
          between v_desde and v_hasta
  ),
  por_dia as (
    select
      dia,
      count(*)::int                                                   as total,
      count(*) filter (where id_estado = 1)::int                      as reservadas,
      count(*) filter (where id_estado = 2)::int                      as canceladas,
      count(*) filter (where id_estado = 3)::int                      as completadas,
      coalesce(sum(cantidad), 0)::int                                 as personas,
      count(*) filter (where pago_estado is not null
                         and pago_estado <> 'verificado')::int        as pagos_pendientes
    from base
    group by dia
  ),
  items as (
    select
      dia,
      jsonb_agg(
        jsonb_build_object(
          'id',                  id,
          'fecha_hora_reserva',  fecha_hora_reserva,
          'fecha_hora_atencion', fecha_hora_atencion,
          'cantidad',            cantidad,
          'precio_total',        precio_total,
          'moneda',              moneda,
          'id_estado',           id_estado,
          'estado',              estado_nombre,
          'servicio',            servicio_nombre,
          'local',               local_nombre,
          'id_local_servicio',   id_local_servicio,
          'turno',               turno_nombre,
          'cliente',             cliente_nombre,
          'cliente_telefono',    cliente_telefono,
          'motivo_cancelacion',  motivo_cancelacion,
          'cancelado_por_rol',   cancelado_por_rol,
          'pago_estado',         pago_estado,
          'pago_monto',          pago_monto,
          'pago_moneda',         pago_moneda
        )
        order by fecha_hora_reserva, id
      ) as lista
    from base
    group by dia
  ),
  serie as (
    select (generate_series(v_desde::timestamp, v_hasta::timestamp, interval '1 day'))::date as dia
  )
  select
    coalesce(jsonb_agg(
      jsonb_build_object(
        'fecha',       s.dia,
        'total',       coalesce(d.total, 0),
        'reservadas',  coalesce(d.reservadas, 0),
        'canceladas',  coalesce(d.canceladas, 0),
        'completadas', coalesce(d.completadas, 0),
        'personas',    coalesce(d.personas, 0),
        'pagos_pendientes', coalesce(d.pagos_pendientes, 0),
        -- `p_incluir_items = false` devuelve solo los contadores: es lo que pinta
        -- los marcadores del calendario, sin arrastrar la lista completa.
        'items',       case when p_incluir_items
                            then coalesce(i.lista, '[]'::jsonb)
                            else '[]'::jsonb end
      )
      order by s.dia
    ), '[]'::jsonb)
  into v_dias
  from serie s
  left join por_dia d on d.dia = s.dia
  left join items   i on i.dia = s.dia;

  -- Resumen del rango: totales por estado y por servicio.
  with base as (
    select a.id_estado, es.nombre as estado_nombre, s.nombre as servicio_nombre,
           a.cantidad, a.precio_total
    from flow.agenda a
    join flow.local_servicio    ls on ls.id = a.id_local_servicio
    join flow.app_dat_locales   l  on l.id  = ls.id_local
    join flow.app_dat_servicios s  on s.id  = ls.id_servicio
    join flow.nom_estado_agenda es on es.id = a.id_estado
    where l.id_entidad = p_id_entidad
      and (a.fecha_hora_reserva at time zone 'America/Havana')::date
          between v_desde and v_hasta
  )
  select jsonb_build_object(
    'total',      (select count(*)::int from base),
    'reservadas', (select count(*)::int from base where id_estado = 1),
    'canceladas', (select count(*)::int from base where id_estado = 2),
    'completadas',(select count(*)::int from base where id_estado = 3),
    'por_servicio', coalesce((
      select jsonb_agg(jsonb_build_object('servicio', servicio_nombre, 'total', t) order by t desc)
      from (
        select servicio_nombre, count(*)::int as t
        from base group by servicio_nombre order by count(*) desc limit 15
      ) x
    ), '[]'::jsonb)
  ) into v_resumen;

  return jsonb_build_object(
    'ok', true,
    'rango', jsonb_build_object(
      'hoy',                    v_hoy,
      'desde',                  v_desde,
      'hasta',                  v_hasta,
      'ultimo_dia_con_reserva', v_ultimo,
      'truncado',               v_truncado
    ),
    'resumen', v_resumen,
    'dias',    v_dias
  );
end;
$function$;

comment on function flow.admin_calendario_reservas(uuid, integer, date, date, boolean) is
  'Resumen-calendario de las reservas de una entidad: de hoy al ultimo mes con reservas (o al rango pedido). Un elemento por dia, con contadores e items.';

-- ══ 6. GRANTS ══════════════════════════════════════════════════════════════

revoke all on function flow.admin_listar_agendas(uuid, integer, integer, integer, integer, timestamp without time zone, timestamp without time zone) from public, anon;
revoke all on function flow.admin_listar_agendas_por_estado(uuid, integer, integer, integer, integer) from public, anon;
revoke all on function flow.vendedor_listar_agendas(uuid, integer, integer, integer, integer, timestamp without time zone, timestamp without time zone) from public, anon;
revoke all on function flow.cliente_obtener_agendas(uuid, integer) from public, anon;
revoke all on function flow.admin_calendario_reservas(uuid, integer, date, date, boolean) from public, anon;

grant execute on function flow.admin_listar_agendas(uuid, integer, integer, integer, integer, timestamp without time zone, timestamp without time zone) to authenticated;
grant execute on function flow.admin_listar_agendas_por_estado(uuid, integer, integer, integer, integer) to authenticated;
grant execute on function flow.vendedor_listar_agendas(uuid, integer, integer, integer, integer, timestamp without time zone, timestamp without time zone) to authenticated;
grant execute on function flow.cliente_obtener_agendas(uuid, integer) to authenticated;
grant execute on function flow.admin_calendario_reservas(uuid, integer, date, date, boolean) to authenticated;

notify pgrst, 'reload schema';

-- ══ 7. VERIFICACION (ejecutar a mano despues de aplicar) ══════════════════
--
-- 7.a Los listados devuelven los campos nuevos (con una sesion de admin real).
-- select jsonb_pretty(flow.admin_listar_agendas(auth.uid(), 1, null, null, null,
--          now()::date - 1, now()::date + 400) -> 0);
--   -- el primer item debe traer motivo_cancelacion, pago_estado, pago_monto,
--   -- pago_moneda, cancelado_por, cancelado_por_rol, cancelado_at
--
-- 7.b El cliente ve el motivo de su reserva cancelada.
-- select jsonb_pretty(flow.cliente_obtener_agendas(auth.uid()) -> 0);
--
-- 7.c El calendario arranca hoy y llega al ultimo mes con reservas.
-- select flow.admin_calendario_reservas(auth.uid(), 1) -> 'rango';
--   -- desde = hoy; hasta = ultimo dia del mes de la ultima reserva;
--   -- ultimo_dia_con_reserva = null si no hay ninguna reserva futura
-- select jsonb_array_length(flow.admin_calendario_reservas(auth.uid(), 1) -> 'dias');
-- select flow.admin_calendario_reservas(auth.uid(), 1) -> 'resumen';
-- -- Solo contadores (lo que pinta el calendario): los items vienen vacios.
-- select flow.admin_calendario_reservas(auth.uid(), 1, null, null, false) -> 'dias' -> 0 -> 'items';
--
-- 7.d Un rango absurdo se recorta a 24 meses y lo dice.
-- select flow.admin_calendario_reservas(auth.uid(), 1, now()::date, now()::date + 3000) -> 'rango';
--
-- 7.e Sin permisos devuelve error, no datos.
-- select flow.admin_calendario_reservas(gen_random_uuid(), 1);   -- {ok:false, error:...}
