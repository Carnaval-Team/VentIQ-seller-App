-- ============================================================================
-- RPC ADMIN/STAFF: actualizar datos_adicionales de una reserva y recalcular
-- precio_total / moneda si cambian aspectos que afectan el precio
-- (reglas de config_precio del servicio o precios fijos del turno).
--
-- SECURITY DEFINER: escribe en agenda bajo RLS.
-- Autorizacion: owner / admin / vendedor de la entidad del local.
-- Devuelve jsonb con la agenda actualizada (precio incluido).
-- ============================================================================

create or replace function flow.admin_actualizar_datos_reserva(
  p_id_agenda         integer,
  p_datos_adicionales jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = flow, public
as $$
declare
  v_agenda      record;
  v_id_servicio integer;
  v_precio      numeric;
  v_moneda      varchar;
  v_unit        numeric;
  v_result      jsonb;
begin
  if p_id_agenda is null then
    raise exception 'id_agenda requerido';
  end if;
  if p_datos_adicionales is null then
    raise exception 'datos_adicionales requerido';
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

  select a.id,
         a.id_local_servicio,
         a.cantidad,
         a.moneda,
         a.id_turno,
         ls.id_servicio
    into v_agenda
  from flow.agenda a
  join flow.local_servicio ls on ls.id = a.id_local_servicio
  where a.id = p_id_agenda;

  if not found then
    raise exception 'Reserva no encontrada';
  end if;

  v_id_servicio := v_agenda.id_servicio;

  if v_agenda.id_turno is not null then
    select cp.precio_total, cp.moneda, cp.precio_unit
      into v_precio, v_moneda, v_unit
    from flow.calcular_precio_turno(
      v_id_servicio,
      v_agenda.id_turno,
      p_datos_adicionales,
      v_agenda.moneda,
      greatest(coalesce(v_agenda.cantidad, 1), 1)
    ) cp;
  else
    select cp.precio_total, cp.moneda, cp.precio_unit
      into v_precio, v_moneda, v_unit
    from flow.calcular_precio_reserva(
      v_id_servicio,
      p_datos_adicionales,
      v_agenda.moneda,
      greatest(coalesce(v_agenda.cantidad, 1), 1)
    ) cp;
  end if;

  update flow.agenda
     set datos_adicionales = p_datos_adicionales,
         precio_total      = v_precio,
         moneda            = v_moneda,
         updated_at        = current_timestamp
   where id = p_id_agenda;

  select jsonb_build_object(
           'ok', true,
           'id', a.id,
           'precio_total', a.precio_total,
           'moneda', a.moneda,
           'precio_unit', v_unit,
           'datos_adicionales', a.datos_adicionales,
           'updated_at', a.updated_at
         )
    into v_result
  from flow.agenda a
  where a.id = p_id_agenda;

  return v_result;
end;
$$;

grant execute on function flow.admin_actualizar_datos_reserva(integer, jsonb) to authenticated;
