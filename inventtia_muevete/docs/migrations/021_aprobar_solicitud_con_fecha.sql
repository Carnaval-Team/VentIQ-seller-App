-- =============================================================================
-- MIGRACIÓN 021: Reemplazar p_fecha_inicio por p_fecha_vencimiento
-- El administrador establece el día 2 del mes hasta el que vence el plan.
-- La función valida que sea exactamente día 2.
-- =============================================================================

-- Eliminar versiones anteriores para evitar ambigüedad
DROP FUNCTION IF EXISTS muevete.fn_aprobar_solicitud_plan(BIGINT, UUID, TEXT, TEXT);
DROP FUNCTION IF EXISTS muevete.fn_aprobar_solicitud_plan(BIGINT, UUID, TEXT, TEXT, DATE);

CREATE OR REPLACE FUNCTION muevete.fn_aprobar_solicitud_plan(
  p_solicitud_id         BIGINT,
  p_admin_uuid           UUID,
  p_codigo_transferencia TEXT,
  p_observaciones        TEXT  DEFAULT NULL,
  p_fecha_vencimiento    DATE  DEFAULT NULL  -- Debe ser día 2. NULL = próximo día 2 desde hoy +1 mes
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_usuario_uuid UUID;
  v_plan_codigo  TEXT;
  v_inicio       DATE := CURRENT_DATE;
  v_vencimiento  DATE;
BEGIN
  -- Validar que si se pasa fecha, sea exactamente día 2
  IF p_fecha_vencimiento IS NOT NULL AND EXTRACT(DAY FROM p_fecha_vencimiento) != 2 THEN
    RAISE EXCEPTION 'La fecha de vencimiento debe ser el día 2 de un mes (recibido: %)', p_fecha_vencimiento;
  END IF;

  -- Resolver vencimiento
  IF p_fecha_vencimiento IS NOT NULL THEN
    v_vencimiento := p_fecha_vencimiento;
  ELSE
    v_vencimiento := muevete.fn_proximo_dia_2(CURRENT_DATE + interval '1 month');
  END IF;

  -- Obtener datos de la solicitud
  SELECT usuario_uuid, plan_codigo
  INTO v_usuario_uuid, v_plan_codigo
  FROM muevete.solicitudes_plan
  WHERE id = p_solicitud_id AND estado = 'pendiente';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Solicitud no encontrada o no está pendiente';
  END IF;

  -- Marcar solicitud como aprobada
  UPDATE muevete.solicitudes_plan
  SET estado                = 'aprobada',
      codigo_transferencia  = p_codigo_transferencia,
      observaciones         = p_observaciones,
      admin_uuid            = p_admin_uuid,
      updated_at            = now()
  WHERE id = p_solicitud_id;

  -- Cancelar suscripciones activas previas del usuario
  UPDATE muevete.suscripciones
  SET estado     = 'cancelada',
      updated_at = now()
  WHERE usuario_uuid = v_usuario_uuid
    AND estado = 'activa';

  -- Crear nueva suscripción activa
  INSERT INTO muevete.suscripciones
    (usuario_uuid, plan_codigo, estado, inicio, vencimiento, renovacion_auto, notas)
  VALUES
    (v_usuario_uuid, v_plan_codigo, 'activa', v_inicio, v_vencimiento, true,
     'Activado por admin · solicitud #' || p_solicitud_id ||
     ' · vence ' || to_char(v_vencimiento, 'DD/MM/YYYY'));
END;
$$;

COMMENT ON FUNCTION muevete.fn_aprobar_solicitud_plan IS
  'Aprueba la solicitud. El vencimiento debe ser día 2 de un mes futuro. '
  'Si no se especifica, calcula el próximo día 2 después de 1 mes desde hoy.';
