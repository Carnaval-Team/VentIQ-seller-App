-- RPC para cancelar una reserva desde el panel de administración.
-- Se ejecuta con SECURITY DEFINER para bypassar RLS y valida internamente
-- que el usuario autenticado sea el dueño de la reserva, dueño de la entidad
-- o administrador de la entidad.

CREATE OR REPLACE FUNCTION flow.admin_cancelar_agenda(p_id_agenda integer)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = flow
AS $$
DECLARE
  v_id_estado int;
  v_id_estado_reservado int;
  v_result json;
  v_agenda record;
  v_plan_id bigint;
BEGIN
  -- 1. Verificar que el usuario autenticado tenga permisos sobre la reserva.
  IF NOT EXISTS (
    SELECT 1
    FROM flow.agenda a
    JOIN flow.local_servicio ls ON ls.id = a.id_local_servicio
    JOIN flow.app_dat_locales l ON l.id = ls.id_local
    WHERE a.id = p_id_agenda
      AND (
        auth.uid() = a.uuid_usuario
        OR l.id_entidad IN (SELECT id FROM flow.entidad WHERE owner_uuid = auth.uid())
        OR EXISTS (
          SELECT 1 FROM flow.entidad_admin ea
          WHERE ea.id_entidad = l.id_entidad
            AND ea.uuid_usuario = auth.uid()
        )
      )
  ) THEN
    RAISE EXCEPTION 'No tiene permisos para cancelar esta reserva';
  END IF;

  -- 2. Cargar la reserva y validar que esté activa.
  SELECT a.id, a.uuid_usuario, a.id_local_servicio, a.id_estado,
         a.fecha_hora_reserva, a.cantidad
    INTO v_agenda
    FROM flow.agenda a
   WHERE a.id = p_id_agenda;

  SELECT id INTO v_id_estado_reservado
    FROM flow.nom_estado_agenda
   WHERE nombre = 'Reservado';

  IF v_agenda.id_estado IS DISTINCT FROM v_id_estado_reservado THEN
    RAISE EXCEPTION 'Solo se pueden cancelar reservas activas';
  END IF;

  -- 3. Obtener el id del estado 'cancelado'.
  SELECT id INTO v_id_estado
    FROM flow.nom_estado_agenda
   WHERE nombre = 'Cancelado';

  IF v_id_estado IS NULL THEN
    RAISE EXCEPTION 'Estado cancelado no encontrado';
  END IF;

  -- 4. Buscar el plan del día para liberar la capacidad.
  SELECT ps.id INTO v_plan_id
    FROM flow.plan_servicios ps
   WHERE ps.id_local_servicio = v_agenda.id_local_servicio
     AND (ps.fecha at time zone 'America/Havana')::date =
         (v_agenda.fecha_hora_reserva at time zone 'America/Havana')::date
   LIMIT 1;

  -- 5. Actualizar el estado de la agenda.
  UPDATE flow.agenda
     SET id_estado = v_id_estado,
         updated_at = current_timestamp
   WHERE id = p_id_agenda;

  -- 6. Liberar la capacidad ocupada por la reserva.
  IF v_plan_id IS NOT NULL THEN
    UPDATE flow.plan_servicios
       SET agendados = GREATEST(0, agendados - v_agenda.cantidad)
     WHERE id = v_plan_id;
  END IF;

  -- 7. Devolver la agenda actualizada en el formato que espera Agenda.fromJson.
  SELECT json_build_object(
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
    'nom_estado_agenda', json_build_object(
      'id', nea.id,
      'nombre', nea.nombre,
      'descripcion', nea.descripcion
    ),
    'local_servicio', json_build_object(
      'id', ls.id,
      'id_local', ls.id_local,
      'id_servicio', ls.id_servicio,
      'permite_reserva_directa', ls.permite_reserva_directa,
      'cantidad_default', ls.cantidad_default,
      'cantidad_max_capacidad', ls.cantidad_max_capacidad,
      'created_at', ls.created_at,
      'local', json_build_object(
        'id', l.id,
        'nombre', l.nombre,
        'descripcion', l.descripcion,
        'horario_atencion', l.horario_atencion,
        'terminos_condiciones', l.terminos_condiciones,
        'coordenadas', l.coordenadas,
        'direccion', l.direccion,
        'pais', l.pais,
        'provincia', l.provincia,
        'foto', l.foto,
        'created_at', l.created_at,
        'updated_at', l.updated_at
      ),
      'servicio', json_build_object(
        'id', s.id,
        'nombre', s.nombre,
        'descripcion', s.descripcion,
        'foto', s.foto,
        'created_at', s.created_at,
        'updated_at', s.updated_at,
        'id_entidad', s.id_entidad,
        'campos_adicionales', s.campos_adicionales,
        'permite_tercero', s.permite_tercero
      )
    )
  ) INTO v_result
  FROM flow.agenda a
  JOIN flow.nom_estado_agenda nea ON nea.id = a.id_estado
  JOIN flow.local_servicio ls ON ls.id = a.id_local_servicio
  JOIN flow.app_dat_locales l ON l.id = ls.id_local
  JOIN flow.app_dat_servicios s ON s.id = ls.id_servicio
  WHERE a.id = p_id_agenda;

  RETURN v_result;
END;
$$;

-- Permitir que usuarios autenticados ejecuten la función.
GRANT EXECUTE ON FUNCTION flow.admin_cancelar_agenda(integer) TO authenticated;
