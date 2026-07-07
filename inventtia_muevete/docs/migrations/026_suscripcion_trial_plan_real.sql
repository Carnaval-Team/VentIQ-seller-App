-- Suscripción inicial con plan de pago real y primer mes sin cargo (promoción registro)
CREATE OR REPLACE FUNCTION muevete.fn_crear_suscripcion_trial(
  p_usuario_uuid UUID,
  p_tipo_usuario TEXT   -- 'shipper' | 'carrier' | 'dispatcher'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_inicio       DATE := CURRENT_DATE;
  v_un_mes       DATE := v_inicio + interval '1 month';
  v_vencimiento  DATE;
  v_plan_codigo  TEXT;
BEGIN
  v_plan_codigo := CASE p_tipo_usuario
    WHEN 'shipper'    THEN 'shipper_plan'
    WHEN 'carrier'    THEN 'carrier_basico_v2'
    WHEN 'dispatcher' THEN 'dispatcher_plan'
    ELSE p_tipo_usuario || '_gratis'
  END;

  IF NOT EXISTS (
    SELECT 1 FROM muevete.planes
    WHERE codigo = v_plan_codigo AND activo = true
  ) THEN
    v_plan_codigo := p_tipo_usuario || '_gratis';
  END IF;

  v_vencimiento := muevete.fn_proximo_dia_2(v_un_mes);

  IF EXISTS (
    SELECT 1 FROM muevete.suscripciones
    WHERE usuario_uuid = p_usuario_uuid AND estado = 'activa'
  ) THEN
    RETURN;
  END IF;

  INSERT INTO muevete.suscripciones
    (usuario_uuid, plan_codigo, estado, inicio, vencimiento, renovacion_auto, notas)
  VALUES
    (
      p_usuario_uuid,
      v_plan_codigo,
      'activa',
      v_inicio,
      v_vencimiento,
      false,
      'Promoción registro: primer mes sin cargo'
    );
END;
$$;

COMMENT ON FUNCTION muevete.fn_crear_suscripcion_trial IS
  'Asigna el plan estándar del tipo con promoción de primer mes sin cargo.';
