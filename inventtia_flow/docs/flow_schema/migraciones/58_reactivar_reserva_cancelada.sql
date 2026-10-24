-- ============================================================================
-- MIGRACION 58: reactivar una reserva cancelada (volver a PENDIENTE)
--
-- QUE ARREGLA
--   `flow.staff_marcar_estado_agenda` solo aceptaba estados destino 2
--   (Cancelado) y 3 (Completado). El boton «Reactivar» del admin y del vendedor
--   manda 1 (Reservado) —es lo que promete reactivar— y el servidor respondia
--       «Estado destino no permitido (use Cancelado o Completado)»
--   asi que reactivar era imposible desde la app.
--
-- QUE CAMBIA (solo esta funcion; firma y columnas de retorno intactas)
--   1. Se acepta el destino 1 (Reservado) ADEMAS de 2 y 3.
--   2. Reactivar (1) solo vale desde Cancelado y solo si la reserva es de HOY o
--      FUTURA: devolver a «pendiente» una cita que ya paso no significa nada
--      (para eso esta Completado). Es la regla que ya documentaba la pantalla
--      del vendedor.
--   3. Reactivar re-consumE la capacidad que libero la cancelacion (los mismos
--      tramos del turno, o `plan_servicios`), acotada a la capacidad total,
--      igual que el paso de cancelada a completada.
--   4. Al reactivar se limpia `fecha_hora_atencion`: la reserva vuelve a estar
--      pendiente de atencion.
--   5. Se notifica al titular cuando la reserva sale de Cancelado (a pendiente o
--      a completada). La app ya decia «cliente notificado» y era mentira: la
--      funcion solo notificaba al cancelar.
--
-- LO QUE NO CAMBIA
--   * Cancelar (2) sigue exigiendo que la reserva este Reservado.
--   * Completar (3) desde cancelada sigue exigiendo fecha de hoy o anterior.
--   * Permisos (owner / admin / vendedor de la entidad) y el json de retorno.
--
-- REVERSION
--   Volver a aplicar el cuerpo anterior (`24_staff_marcar_estado_agenda.sql`).
--   La funcion es la misma: no hay firmas nuevas que borrar.
-- ============================================================================

create or replace function flow.staff_marcar_estado_agenda(
  p_id_agenda integer,
  p_id_estado integer
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
begin
  -- [58] Estados destino validos: Reservado (1, solo al reactivar), Cancelado (2)
  -- o Completado (3).
  if p_id_estado not in (1, 2, 3) then
    raise exception 'Estado destino no permitido (use Reservado, Cancelado o Completado)';
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
  update flow.agenda
     set id_estado = p_id_estado,
         fecha_hora_atencion = case
                                 when p_id_estado = 3 then current_timestamp
                                 when p_id_estado = 1 then null
                                 else fecha_hora_atencion
                               end,
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
      insert into flow.notificaciones
        (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
      values (
        v_agenda.uuid_usuario, 'reserva', 'Reserva cancelada',
        'Su reserva para "' || coalesce(v_nombre_serv, 'el servicio')
          || '" en "' || coalesce(v_nombre_local, 'el local')
          || '" del ' || to_char(v_agenda.fecha_hora_reserva, 'DD/MM/YYYY')
          || ' ha sido cancelada por la administracion.',
        v_agenda.id_local_servicio, p_id_agenda,
        jsonb_build_object('fecha', v_agenda.fecha_hora_reserva)
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

  -- Devolver la agenda actualizada (formato Agenda.fromJson).
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

notify pgrst, 'reload schema';


-- ============================================================================
-- VERIFICACION (ejecutar despues de aplicar; los ids de estado reales son
-- 1=Reservado, 2=Cancelado, 3=Completado)
--
--   -- 1. La funcion acepta los tres destinos (ya no revienta al validar).
--   select pg_get_functiondef(p.oid) like '%not in (1, 2, 3)%' as acepta_tres
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'flow' and p.proname = 'staff_marcar_estado_agenda';
--
--   -- 2. Reactivar una cancelada FUTURA debe funcionar y devolver estado 1:
--   --    (sustituir 999 por una agenda cancelada futura real)
--   select flow.staff_marcar_estado_agenda(999, 1) -> 'nom_estado_agenda';
--
--   -- 3. Reactivar una cancelada PASADA debe fallar con el mensaje nuevo:
--   --    «Solo se pueden reactivar reservas de hoy o fechas futuras».
--   -- 4. Completar una cancelada FUTURA sigue fallando:
--   --    «Solo se pueden completar reservas canceladas de hoy o fechas anteriores».
-- ============================================================================
