-- ============================================================================
-- MIGRACION 61: motivo de cancelacion + notificacion en rojo al cliente
--
-- QUE RESUELVE
--   1. El admin (y el vendedor) cancelaban una reserva SIN decir por que y, en el
--      caso de `admin_cancelar_agenda`, SIN avisar al cliente: la reserva
--      desaparecia de su lista sin una sola notificacion.
--   2. El cliente que cancelaba tampoco podia explicar nada.
--   3. Todas las notificaciones de cancelacion viajaban con `tipo = 'reserva'`,
--      el mismo que una reserva creada, asi que en la campana salian en verde.
--
-- QUE CAMBIA
--   * `flow.agenda` gana 4 columnas de auditoria de la cancelacion:
--       motivo_cancelacion  text  — lo que escribio quien cancelo
--       cancelado_por       uuid  — quien la cancelo
--       cancelado_por_rol   text  — 'cliente' | 'admin' | 'staff' | 'sistema'
--       cancelado_at        timestamptz
--   * Las 4 funciones de cancelacion aceptan `p_motivo text default null`
--     (se DROP-ean las versiones viejas: dejar dos sobrecargas rompe a PostgREST,
--     que no elige candidata entre aridades distintas).
--   * La notificacion al titular pasa a `tipo = 'cancelacion'` (rojo en la app)
--     y lleva el motivo en `mensaje` y en `data.motivo`.
--   * `admin_cancelar_agenda` AHORA SI notifica al titular. Antes no lo hacia.
--
-- LO QUE NO CAMBIA
--   * La liberacion de capacidad (tramos/`plan_servicios`) y la validacion de
--     estados: identicas.
--   * Reactivar y completar siguen notificando con `tipo = 'reserva'`.
--   * Las firmas VIEJAS dejan de existir (drop + create). Ninguna otra app del
--     repo llama a estas funciones.
--
-- REVERSION
--   `alter table flow.agenda drop column if exists motivo_cancelacion, ...` y
--   volver a aplicar los cuerpos de `24_staff_marcar_estado_agenda.sql`,
--   `58_reactivar_reserva_cancelada.sql`, `12_cliente_cancelar_reserva.sql`.
--
-- IDEMPOTENTE: `if not exists` + `drop function if exists` + `create or replace`.
-- ============================================================================

-- ══ 1. COLUMNAS DE CANCELACION ═════════════════════════════════════════════

alter table flow.agenda add column if not exists motivo_cancelacion text;
alter table flow.agenda add column if not exists cancelado_por       uuid;
alter table flow.agenda add column if not exists cancelado_por_rol   text;
alter table flow.agenda add column if not exists cancelado_at        timestamptz;

alter table flow.agenda drop constraint if exists agenda_cancelado_rol_chk;
alter table flow.agenda add  constraint agenda_cancelado_rol_chk
  check (cancelado_por_rol is null
         or cancelado_por_rol in ('cliente', 'admin', 'staff', 'sistema'));

comment on column flow.agenda.motivo_cancelacion is
  'Motivo que escribio quien cancelo la reserva. Se muestra al cliente en la notificacion y en el detalle de la reserva.';
comment on column flow.agenda.cancelado_por is 'Usuario que cancelo la reserva.';
comment on column flow.agenda.cancelado_por_rol is
  'Rol desde el que se cancelo: cliente, admin, staff o sistema (expiracion de pago).';
comment on column flow.agenda.cancelado_at is 'Momento de la cancelacion.';

create index if not exists idx_agenda_canceladas
  on flow.agenda (cancelado_at desc)
  where motivo_cancelacion is not null;

-- ══ 2. HELPER: texto de la notificacion de cancelacion ════════════════════
-- Una sola funcion arma el mensaje para las 4 vias de cancelacion: asi el
-- cliente lee siempre lo mismo, con o sin motivo.

create or replace function flow._mensaje_cancelacion(
  p_servicio text,
  p_local    text,
  p_fecha    timestamptz,
  p_rol      text,
  p_motivo   text
)
returns text
language sql
immutable
set search_path = flow, public
as $function$
  select
    case
      when coalesce(btrim(p_motivo), '') <> '' then
        'Se ha cancelado tu reserva para "' || coalesce(p_servicio, 'el servicio')
        || '" en "' || coalesce(p_local, 'el local') || '" del '
        || to_char(p_fecha, 'DD/MM/YYYY') || '. Motivo: ' || btrim(p_motivo)
      else
        'Se ha cancelado tu reserva para "' || coalesce(p_servicio, 'el servicio')
        || '" en "' || coalesce(p_local, 'el local') || '" del '
        || to_char(p_fecha, 'DD/MM/YYYY')
        || case when p_rol = 'cliente' then '.' else ' por la administracion.' end
    end;
$function$;

comment on function flow._mensaje_cancelacion(text, text, timestamptz, text, text) is
  'Mensaje unico de la notificacion de cancelacion, con el motivo al final cuando existe.';

-- ══ 3. staff_marcar_estado_agenda (+ p_motivo) ════════════════════════════

drop function if exists flow.staff_marcar_estado_agenda(integer, integer);

create or replace function flow.staff_marcar_estado_agenda(
  p_id_agenda integer,
  p_id_estado integer,
  p_motivo    text default null
)
returns json
language plpgsql
security definer
set search_path = flow, public
as $function$
declare
  v_agenda        record;
  v_id_reservado  int;
  v_id_cancelado  int;
  v_plan_id       bigint;
  v_result        json;
  v_nombre_serv   text;
  v_nombre_local  text;
  v_fecha_dia     date;
  v_hoy           date;
  v_motivo        text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  -- [58] Estados destino validos: Reservado (1, solo al reactivar), Cancelado (2)
  -- o Completado (3).
  if p_id_estado not in (1, 2, 3) then
    raise exception 'Estado destino no permitido (use Reservado, Cancelado o Completado)';
  end if;

  -- [61] El motivo es obligatorio al cancelar desde el panel: el cliente tiene
  -- que saber por que le quitaron la reserva.
  if p_id_estado = 2 and v_motivo is null then
    raise exception 'Debes indicar el motivo de la cancelacion';
  end if;

  -- Autorizacion: owner / admin / vendedor de la entidad de la reserva.
  if not exists (
    select 1
    from flow.agenda a
    join flow.local_servicio ls on ls.id = a.id_local_servicio
    join flow.app_dat_locales l on l.id = ls.id_local
    where a.id = p_id_agenda
      and (
        l.id_entidad in (select id from flow.entidad where owner_uuid = auth.uid())
        or exists (
          select 1 from flow.entidad_admin ea
          where ea.id_entidad = l.id_entidad and ea.uuid_usuario = auth.uid()
        )
        or exists (
          select 1 from flow.entidad_vendedor ev
          where ev.id_entidad = l.id_entidad and ev.uuid_usuario = auth.uid()
        )
      )
  ) then
    raise exception 'No tiene permisos sobre esta reserva';
  end if;

  -- Cargar la reserva (incluye id_turno para re-consumir la capacidad correcta).
  select a.id, a.uuid_usuario, a.id_local_servicio, a.id_estado,
         a.fecha_hora_reserva, a.cantidad, a.id_turno
    into v_agenda
    from flow.agenda a
   where a.id = p_id_agenda;

  select id into v_id_reservado from flow.nom_estado_agenda where nombre = 'Reservado';
  select id into v_id_cancelado from flow.nom_estado_agenda where nombre = 'Cancelado';

  v_fecha_dia := (v_agenda.fecha_hora_reserva at time zone 'America/Havana')::date;
  v_hoy       := (current_timestamp at time zone 'America/Havana')::date;

  -- Reglas por transicion.
  if p_id_estado = 2 then
    -- Cancelar: solo desde activa (Reservado).
    if v_agenda.id_estado is distinct from v_id_reservado then
      raise exception 'Solo se pueden cancelar reservas activas';
    end if;
  elsif p_id_estado = 1 then
    -- [58] Reactivar: solo desde cancelada y solo si no ha pasado.
    if v_agenda.id_estado is distinct from v_id_cancelado then
      raise exception 'Solo se pueden reactivar reservas canceladas';
    end if;
    if v_fecha_dia < v_hoy then
      raise exception 'Solo se pueden reactivar reservas de hoy o fechas futuras';
    end if;
  else
    -- Completar: desde activa, o desde cancelada si la fecha es hoy o anterior.
    if v_agenda.id_estado = v_id_reservado then
      null;  -- ok
    elsif v_agenda.id_estado = v_id_cancelado then
      if v_fecha_dia > v_hoy then
        raise exception 'Solo se pueden completar reservas canceladas de hoy o fechas anteriores';
      end if;
    else
      raise exception 'Esta reserva no se puede completar en su estado actual';
    end if;
  end if;

  -- Capacidad:
  --   cancelar           -> liberar (baja agendados)
  --   reactivar          -> re-consumir lo que libero la cancelacion
  --   completar desde
  --     cancelada        -> re-consumir (sube agendados, acotado a la capacidad)
  --     reservado        -> no toca (ya estaba consumida al reservar)
  if p_id_estado = 2 then
    if v_agenda.id_turno is not null then
      update flow.plan_tramo pt
         set agendados = greatest(0, pt.agendados - v_agenda.cantidad)
      from flow.turno_tramo tt
      join flow.tramo tr on tr.id = tt.id_tramo
      where tt.id_turno = v_agenda.id_turno
        and pt.id_tramo = tr.id
        and (pt.fecha at time zone 'America/Havana')::date = v_fecha_dia;
    else
      select ps.id into v_plan_id
        from flow.plan_servicios ps
       where ps.id_local_servicio = v_agenda.id_local_servicio
         and (ps.fecha at time zone 'America/Havana')::date = v_fecha_dia
       limit 1;
      if v_plan_id is not null then
        update flow.plan_servicios
           set agendados = greatest(0, agendados - v_agenda.cantidad)
         where id = v_plan_id;
      end if;
    end if;
  elsif p_id_estado in (1, 3) and v_agenda.id_estado = v_id_cancelado then
    -- [58] Re-consumir capacidad liberada por la cancelacion (acotado a la
    -- capacidad total). Vale para reactivar (1) y para completar (3).
    if v_agenda.id_turno is not null then
      update flow.plan_tramo pt
         set agendados = least(pt.cantidad, pt.agendados + v_agenda.cantidad)
      from flow.turno_tramo tt
      join flow.tramo tr on tr.id = tt.id_tramo
      where tt.id_turno = v_agenda.id_turno
        and pt.id_tramo = tr.id
        and (pt.fecha at time zone 'America/Havana')::date = v_fecha_dia;
    else
      select ps.id into v_plan_id
        from flow.plan_servicios ps
       where ps.id_local_servicio = v_agenda.id_local_servicio
         and (ps.fecha at time zone 'America/Havana')::date = v_fecha_dia
       limit 1;
      if v_plan_id is not null then
        update flow.plan_servicios
           set agendados = least(cantidad, agendados + v_agenda.cantidad)
         where id = v_plan_id;
      end if;
    end if;
  end if;

  -- Actualizar el estado. Al completar se sella la atencion; al reactivar se
  -- limpia (vuelve a estar pendiente de atencion).
  -- [61] Al cancelar se guarda el motivo y quien cancelo. Al reactivar se borra
  -- la huella de la cancelacion anterior (la reserva vuelve a estar viva).
  update flow.agenda
     set id_estado = p_id_estado,
         fecha_hora_atencion = case
                                 when p_id_estado = 3 then current_timestamp
                                 when p_id_estado = 1 then null
                                 else fecha_hora_atencion
                               end,
         motivo_cancelacion = case when p_id_estado = 2 then v_motivo
                                   when p_id_estado = 1 then null
                                   else motivo_cancelacion end,
         cancelado_por      = case when p_id_estado = 2 then auth.uid()
                                   when p_id_estado = 1 then null
                                   else cancelado_por end,
         cancelado_por_rol  = case when p_id_estado = 2 then 'staff'
                                   when p_id_estado = 1 then null
                                   else cancelado_por_rol end,
         cancelado_at       = case when p_id_estado = 2 then current_timestamp
                                   when p_id_estado = 1 then null
                                   else cancelado_at end,
         updated_at = current_timestamp
   where id = p_id_agenda;

  -- Notificar al titular: al cancelar, y tambien cuando la reserva SALE de
  -- cancelada (reactivada a pendiente, o completada desde cancelada).
  if p_id_estado in (1, 2, 3) and v_agenda.uuid_usuario is not null then
    select s.nombre, l.nombre into v_nombre_serv, v_nombre_local
      from flow.local_servicio ls
      join flow.app_dat_servicios s on s.id = ls.id_servicio
      join flow.app_dat_locales   l on l.id = ls.id_local
     where ls.id = v_agenda.id_local_servicio;

    if p_id_estado = 2 then
      -- [61] tipo 'cancelacion' => se pinta en ROJO en la campana del cliente.
      insert into flow.notificaciones
        (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
      values (
        v_agenda.uuid_usuario, 'cancelacion', 'Reserva cancelada',
        flow._mensaje_cancelacion(v_nombre_serv, v_nombre_local,
                                  v_agenda.fecha_hora_reserva, 'staff', v_motivo),
        v_agenda.id_local_servicio, p_id_agenda,
        jsonb_build_object(
          'fecha',    v_agenda.fecha_hora_reserva,
          'motivo',   v_motivo,
          'cancelada_por', 'administracion'
        )
      );
    elsif v_agenda.id_estado = v_id_cancelado then
      insert into flow.notificaciones
        (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
      values (
        v_agenda.uuid_usuario, 'reserva',
        case when p_id_estado = 1 then 'Reserva reactivada'
             else 'Reserva completada' end,
        case when p_id_estado = 1
             then 'Su reserva para "' || coalesce(v_nombre_serv, 'el servicio')
                  || '" en "' || coalesce(v_nombre_local, 'el local')
                  || '" del ' || to_char(v_agenda.fecha_hora_reserva, 'DD/MM/YYYY')
                  || ' vuelve a estar activa.'
             else 'Su reserva para "' || coalesce(v_nombre_serv, 'el servicio')
                  || '" en "' || coalesce(v_nombre_local, 'el local')
                  || '" del ' || to_char(v_agenda.fecha_hora_reserva, 'DD/MM/YYYY')
                  || ' se ha marcado como completada.'
        end,
        v_agenda.id_local_servicio, p_id_agenda,
        jsonb_build_object('fecha', v_agenda.fecha_hora_reserva, 'estado', p_id_estado)
      );
    end if;
  end if;

  -- Devolver la agenda actualizada (formato Agenda.fromJson) + los campos nuevos.
  select json_build_object(
    'id', a.id,
    'uuid_usuario', a.uuid_usuario,
    'id_local_servicio', a.id_local_servicio,
    'id_estado', a.id_estado,
    'fecha_hora_reserva', a.fecha_hora_reserva,
    'fecha_hora_atencion', a.fecha_hora_atencion,
    'created_at', a.created_at,
    'updated_at', a.updated_at,
    'cantidad', a.cantidad,
    'datos_adicionales', a.datos_adicionales,
    'reservado_por', a.reservado_por,
    'id_turno', a.id_turno,
    'motivo_cancelacion', a.motivo_cancelacion,
    'cancelado_por', a.cancelado_por,
    'cancelado_por_rol', a.cancelado_por_rol,
    'cancelado_at', a.cancelado_at,
    'nom_estado_agenda', json_build_object(
      'id', nea.id, 'nombre', nea.nombre, 'descripcion', nea.descripcion
    )
  ) into v_result
  from flow.agenda a
  join flow.nom_estado_agenda nea on nea.id = a.id_estado
  where a.id = p_id_agenda;

  return v_result;
end;
$function$;

-- ══ 4. staff_cancelar_reserva (+ p_motivo) ════════════════════════════════

drop function if exists flow.staff_cancelar_reserva(integer);

create or replace function flow.staff_cancelar_reserva(
  p_id_agenda integer,
  p_motivo    text default null
)
returns json
language plpgsql
security definer
set search_path = flow, public
as $function$
DECLARE
  v_agenda    RECORD;
  v_regreso   RECORD;
  v_result    JSON;
  v_id_reservado INTEGER;
  v_motivo    TEXT := nullif(btrim(coalesce(p_motivo, '')), '');
BEGIN
  IF v_motivo IS NULL THEN
    RAISE EXCEPTION 'Debes indicar el motivo de la cancelacion';
  END IF;

  SELECT a.id, a.id_viaje, a.tipo_trayecto
  INTO v_agenda
  FROM flow.agenda a
  WHERE a.id = p_id_agenda
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Reserva no encontrada';
  END IF;

  SELECT id
  INTO v_id_reservado
  FROM flow.nom_estado_agenda
  WHERE nombre = 'Reservado';

  v_result := flow.staff_marcar_estado_agenda(p_id_agenda, 2, v_motivo);

  IF v_agenda.tipo_trayecto = 'ida' AND v_agenda.id_viaje IS NOT NULL THEN
    FOR v_regreso IN
      SELECT a.id
      FROM flow.agenda a
      WHERE a.id_viaje = v_agenda.id_viaje
        AND a.tipo_trayecto = 'vuelta'
        AND a.id_estado = v_id_reservado
      ORDER BY a.id
      FOR UPDATE
    LOOP
      PERFORM flow.staff_marcar_estado_agenda(v_regreso.id, 2, v_motivo);
    END LOOP;
  END IF;

  RETURN v_result;
END;
$function$;

-- ══ 5. admin_cancelar_agenda (+ p_motivo, + notificacion) ═════════════════

drop function if exists flow.admin_cancelar_agenda(integer);

create or replace function flow.admin_cancelar_agenda(
  p_id_agenda integer,
  p_motivo    text default null
)
returns json
language plpgsql
security definer
set search_path = flow
as $function$
declare
  v_id_estado int;
  v_id_estado_reservado int;
  v_result json;
  v_agenda record;
  v_plan_id bigint;
  v_nombre_serv text;
  v_nombre_local text;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_rol text;
  v_resultado jsonb;
begin
  if v_motivo is null then
    raise exception 'Debes indicar el motivo de la cancelacion';
  end if;

  if not exists (
    select 1
    from flow.agenda a
    join flow.local_servicio ls on ls.id = a.id_local_servicio
    join flow.app_dat_locales l on l.id = ls.id_local
    where a.id = p_id_agenda
      and (
        auth.uid() = a.uuid_usuario
        or l.id_entidad in (select id from flow.entidad where owner_uuid = auth.uid())
        or exists (
          select 1 from flow.entidad_admin ea
          where ea.id_entidad = l.id_entidad and ea.uuid_usuario = auth.uid()
        )
      )
  ) then
    raise exception 'No tiene permisos para cancelar esta reserva';
  end if;

  select a.id, a.uuid_usuario, a.id_local_servicio, a.id_estado,
         a.fecha_hora_reserva, a.cantidad, a.id_turno
    into v_agenda
    from flow.agenda a
   where a.id = p_id_agenda;

  select id into v_id_estado_reservado from flow.nom_estado_agenda where nombre = 'Reservado';

  if v_agenda.id_estado is distinct from v_id_estado_reservado then
    raise exception 'Solo se pueden cancelar reservas activas';
  end if;

  select id into v_id_estado from flow.nom_estado_agenda where nombre = 'Cancelado';
  if v_id_estado is null then
    raise exception 'Estado cancelado no encontrado';
  end if;

  -- [61] Quien cancela: el propio titular o la administracion.
  v_rol := case when auth.uid() = v_agenda.uuid_usuario then 'cliente' else 'admin' end;

  update flow.agenda
     set id_estado = v_id_estado,
         motivo_cancelacion = v_motivo,
         cancelado_por = auth.uid(),
         cancelado_por_rol = v_rol,
         cancelado_at = current_timestamp,
         updated_at = current_timestamp
   where id = p_id_agenda;

  -- Liberar capacidad: plan_tramo si la reserva tiene turno, si no plan_servicios.
  if v_agenda.id_turno is not null then
    perform flow._liberar_tramos_turno(
      v_agenda.id_turno,
      (v_agenda.fecha_hora_reserva at time zone 'America/Havana')::date,
      v_agenda.cantidad);
  else
    select ps.id into v_plan_id
      from flow.plan_servicios ps
     where ps.id_local_servicio = v_agenda.id_local_servicio
       and (ps.fecha at time zone 'America/Havana')::date =
           (v_agenda.fecha_hora_reserva at time zone 'America/Havana')::date
     limit 1;
    if v_plan_id is not null then
      update flow.plan_servicios
         set agendados = greatest(0, agendados - v_agenda.cantidad)
       where id = v_plan_id;
    end if;
  end if;

  -- [61] Notificar al TITULAR (antes esta funcion no avisaba a nadie). Si el que
  -- cancela es el propio titular —caso raro por esta via— no se auto-notifica.
  if v_agenda.uuid_usuario is not null and v_agenda.uuid_usuario <> auth.uid() then
    select s.nombre, l.nombre into v_nombre_serv, v_nombre_local
      from flow.local_servicio ls
      join flow.app_dat_servicios s on s.id = ls.id_servicio
      join flow.app_dat_locales   l on l.id = ls.id_local
     where ls.id = v_agenda.id_local_servicio;

    insert into flow.notificaciones
      (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
    values (
      v_agenda.uuid_usuario,
      'cancelacion',
      'Reserva cancelada',
      flow._mensaje_cancelacion(v_nombre_serv, v_nombre_local,
                                v_agenda.fecha_hora_reserva, v_rol, v_motivo),
      v_agenda.id_local_servicio,
      v_agenda.id,
      jsonb_build_object(
        'fecha',         v_agenda.fecha_hora_reserva,
        'motivo',        v_motivo,
        'cancelada_por', v_rol
      )
    );
  end if;

  select json_build_object(
    'id', a.id,
    'uuid_usuario', a.uuid_usuario,
    'id_local_servicio', a.id_local_servicio,
    'id_estado', a.id_estado,
    'fecha_hora_reserva', a.fecha_hora_reserva,
    'fecha_hora_atencion', a.fecha_hora_atencion,
    'created_at', a.created_at,
    'updated_at', a.updated_at,
    'cantidad', a.cantidad,
    'datos_adicionales', a.datos_adicionales,
    'reservado_por', a.reservado_por,
    'id_turno', a.id_turno,
    'motivo_cancelacion', a.motivo_cancelacion,
    'cancelado_por', a.cancelado_por,
    'cancelado_por_rol', a.cancelado_por_rol,
    'cancelado_at', a.cancelado_at,
    'nom_estado_agenda', json_build_object(
      'id', nea.id, 'nombre', nea.nombre, 'descripcion', nea.descripcion
    ),
    'local_servicio', json_build_object(
      'id', ls.id,
      'id_local', ls.id_local,
      'id_servicio', ls.id_servicio,
      'permite_reserva_directa', ls.permite_reserva_directa,
      'app_dat_locales', (select row_to_json(x) from (
        select ll.id, ll.nombre, ll.direccion from flow.app_dat_locales ll where ll.id = ls.id_local) x),
      'app_dat_servicios', (select row_to_json(y) from (
        select ss.id, ss.nombre from flow.app_dat_servicios ss where ss.id = ls.id_servicio) y)
    )
  ) into v_result
  from flow.agenda a
  join flow.nom_estado_agenda nea on nea.id = a.id_estado
  join flow.local_servicio ls on ls.id = a.id_local_servicio
  where a.id = p_id_agenda;

  return v_result;
end;
$function$;

-- ══ 6. cliente_cancelar_reserva (+ p_motivo opcional) ═════════════════════

drop function if exists flow.cliente_cancelar_reserva(uuid, integer);

create or replace function flow.cliente_cancelar_reserva(
  p_uuid_usuario uuid,
  p_id_agenda    integer,
  p_motivo       text default null
)
returns jsonb
language plpgsql
security definer
set search_path = flow, public
as $function$
declare
  v_agenda              flow.agenda%rowtype;
  v_estado_reservado    integer;
  v_estado_cancelado    integer;
  v_horas_anticipacion  integer;
  v_limite              timestamp without time zone;
  v_plan_id             bigint;
  v_nombre_servicio     text;
  v_nombre_local        text;
  v_motivo              text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  if p_uuid_usuario is null or p_id_agenda is null then
    return jsonb_build_object('ok', false, 'error', 'parametros obligatorios faltantes');
  end if;

  -- Estados
  select id into v_estado_reservado from flow.nom_estado_agenda where nombre = 'Reservado' limit 1;
  select id into v_estado_cancelado from flow.nom_estado_agenda where nombre = 'Cancelado' limit 1;
  if v_estado_reservado is null or v_estado_cancelado is null then
    return jsonb_build_object('ok', false, 'error', 'faltan estados de agenda');
  end if;

  -- Cargar la reserva y validar propiedad
  select a.* into v_agenda
  from flow.agenda a
  where a.id = p_id_agenda;

  if v_agenda.id is null then
    return jsonb_build_object('ok', false, 'error', 'Reserva no encontrada');
  end if;

  if v_agenda.uuid_usuario != p_uuid_usuario and v_agenda.reservado_por != p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'No tienes permiso para cancelar esta reserva');
  end if;

  if v_agenda.id_estado != v_estado_reservado then
    return jsonb_build_object('ok', false, 'error', 'Solo se pueden cancelar reservas activas');
  end if;

  -- Configuracion de cancelacion de la entidad
  select e.horas_anticipacion_cancelacion
    into v_horas_anticipacion
  from flow.local_servicio ls
  join flow.app_dat_locales l on l.id = ls.id_local
  join flow.entidad         e on e.id = l.id_entidad
  where ls.id = v_agenda.id_local_servicio;

  -- Solo validar ventana si la entidad configuro horas de anticipacion (>0).
  -- Si no hay configuracion (0 o null), el cliente puede cancelar en cualquier momento.
  if coalesce(v_horas_anticipacion, 0) > 0 then
    v_limite := v_agenda.fecha_hora_reserva - (v_horas_anticipacion || ' hours')::interval;
    if current_timestamp > v_limite then
      return jsonb_build_object('ok', false, 'error',
        'Solo puedes cancelar hasta ' || v_horas_anticipacion || ' horas antes de la reserva');
    end if;
  end if;

  -- Aplicar cancelacion en una transaccion implicita
  update flow.agenda
     set id_estado = v_estado_cancelado,
         motivo_cancelacion = v_motivo,
         cancelado_por = p_uuid_usuario,
         cancelado_por_rol = 'cliente',
         cancelado_at = current_timestamp,
         updated_at = current_timestamp
   where id = p_id_agenda;

  if v_agenda.id_turno is not null then
    update flow.plan_tramo pt
       set agendados = greatest(0, pt.agendados - v_agenda.cantidad)
      from flow.turno_tramo tt
     where tt.id_turno = v_agenda.id_turno
       and pt.id_tramo = tt.id_tramo
       and (pt.fecha at time zone 'America/Havana')::date =
           (v_agenda.fecha_hora_reserva at time zone 'America/Havana')::date;
  else
    -- Buscar plan del dia para restar agendados (sin forzar: puede no existir si el plan fue borrado)
    select ps.id
      into v_plan_id
    from flow.plan_servicios ps
    where ps.id_local_servicio = v_agenda.id_local_servicio
      and (ps.fecha at time zone 'America/Havana')::date =
          (v_agenda.fecha_hora_reserva at time zone 'America/Havana')::date
    limit 1;

    if v_plan_id is not null then
      update flow.plan_servicios
         set agendados = greatest(0, agendados - v_agenda.cantidad)
       where id = v_plan_id;
    end if;
  end if;

  -- Notificacion al cliente que cancelo (tipo 'cancelacion' = ROJO en la app)
  select s.nombre, l.nombre
    into v_nombre_servicio, v_nombre_local
  from flow.local_servicio ls
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  join flow.app_dat_locales   l on l.id = ls.id_local
  where ls.id = v_agenda.id_local_servicio;

  insert into flow.notificaciones
    (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
  values
    (p_uuid_usuario,
     'cancelacion',
     'Reserva cancelada',
     flow._mensaje_cancelacion(v_nombre_servicio, v_nombre_local,
                               v_agenda.fecha_hora_reserva, 'cliente', v_motivo),
     v_agenda.id_local_servicio,
     v_agenda.id,
     jsonb_build_object(
       'fecha',         v_agenda.fecha_hora_reserva,
       'servicio',      v_nombre_servicio,
       'local',         v_nombre_local,
       'cantidad',      v_agenda.cantidad,
       'motivo',        v_motivo,
       'cancelada_por', 'cliente'
     ));

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id_agenda', p_id_agenda,
      'fecha',     to_char(v_agenda.fecha_hora_reserva, 'YYYY-MM-DD')
    )
  );

exception
  when others then
    return jsonb_build_object('ok', false, 'error', sqlerrm, 'sqlstate', sqlstate);
end;
$function$;

-- ══ 7. GRANTS ══════════════════════════════════════════════════════════════

revoke all on function flow._mensaje_cancelacion(text, text, timestamptz, text, text) from public, anon;

revoke all on function flow.staff_marcar_estado_agenda(integer, integer, text) from public, anon;
revoke all on function flow.staff_cancelar_reserva(integer, text) from public, anon;
revoke all on function flow.admin_cancelar_agenda(integer, text) from public, anon;
revoke all on function flow.cliente_cancelar_reserva(uuid, integer, text) from public, anon;

grant execute on function flow.staff_marcar_estado_agenda(integer, integer, text) to authenticated;
grant execute on function flow.staff_cancelar_reserva(integer, text) to authenticated;
grant execute on function flow.admin_cancelar_agenda(integer, text) to authenticated;
grant execute on function flow.cliente_cancelar_reserva(uuid, integer, text) to authenticated;

-- ══ 8. VERIFICACION (ejecutar a mano despues de aplicar) ══════════════════
--
-- 8.a Las columnas nuevas existen.
-- select column_name, data_type from information_schema.columns
--  where table_schema='flow' and table_name='agenda'
--    and column_name in ('motivo_cancelacion','cancelado_por','cancelado_por_rol','cancelado_at');
--
-- 8.b Solo queda UNA version de cada funcion (sin sobrecargas).
-- select p.proname, count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--  where n.nspname='flow' and p.proname in ('staff_marcar_estado_agenda','staff_cancelar_reserva',
--        'admin_cancelar_agenda','cliente_cancelar_reserva')
--  group by p.proname;   -- cada una: 1
--
-- 8.c Cancelar sin motivo debe fallar (con una sesion de admin real).
-- select flow.admin_cancelar_agenda(1);            -- ERROR: Debes indicar el motivo...
-- select flow.staff_cancelar_reserva(1);           -- ERROR: Debes indicar el motivo...
--
-- 8.d Cancelar con motivo deja la huella y la notificacion en rojo.
-- select flow.admin_cancelar_agenda(1, 'Cambio de horario del local');
-- select id, id_estado, motivo_cancelacion, cancelado_por_rol, cancelado_at
--   from flow.agenda where id = 1;
-- select tipo, titulo, mensaje, data from flow.notificaciones
--  where id_referencia = 1 order by id desc limit 1;   -- tipo = 'cancelacion'
