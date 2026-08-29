CREATE OR REPLACE FUNCTION flow.staff_cancelar_reserva(
  p_id_agenda INTEGER
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'flow', 'public'
AS $function$
DECLARE
  v_agenda RECORD;
  v_regreso RECORD;
  v_result JSON;
  v_id_reservado INTEGER;
BEGIN
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

  v_result := flow.staff_marcar_estado_agenda(p_id_agenda, 2);

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
      PERFORM flow.staff_marcar_estado_agenda(v_regreso.id, 2);
    END LOOP;
  END IF;

  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION flow.staff_cancelar_reserva(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION flow.staff_cancelar_reserva(INTEGER) TO authenticated;
