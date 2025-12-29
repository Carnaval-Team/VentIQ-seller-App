-- ============================================================================
-- VERSIÓN SIMPLIFICADA PARA DEBUG
-- Solo crea el envío sin procesar productos
-- ============================================================================

DROP FUNCTION IF EXISTS public.crear_envio_consignacion_simple(
  p_id_contrato BIGINT,
  p_id_almacen_origen BIGINT,
  p_id_almacen_destino BIGINT,
  p_id_usuario UUID,
  p_id_operacion_extraccion BIGINT,
  p_id_operacion_recepcion BIGINT
) CASCADE;

CREATE OR REPLACE FUNCTION public.crear_envio_consignacion_simple(
  p_id_contrato BIGINT,
  p_id_almacen_origen BIGINT,
  p_id_almacen_destino BIGINT,
  p_id_usuario UUID,
  p_id_operacion_extraccion BIGINT,
  p_id_operacion_recepcion BIGINT
)
RETURNS TABLE (
  success BOOLEAN,
  id_envio BIGINT,
  numero_envio VARCHAR,
  mensaje VARCHAR
) AS $$
DECLARE
  v_id_envio BIGINT;
  v_numero_envio VARCHAR;
BEGIN
  -- Generar número de envío único
  v_numero_envio := 'ENV-' || TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDD') || '-' || LPAD(nextval('app_dat_consignacion_envio_id_seq')::TEXT, 6, '0');
  
  -- Crear envío
  INSERT INTO app_dat_consignacion_envio (
    id_contrato_consignacion,
    id_operacion_extraccion,
    id_operacion_recepcion,
    numero_envio,
    estado_envio,
    fecha_propuesta,
    id_almacen_origen,
    id_almacen_destino,
    id_usuario_creador,
    estado,
    created_at,
    updated_at
  ) VALUES (
    p_id_contrato,
    p_id_operacion_extraccion,
    p_id_operacion_recepcion,
    v_numero_envio,
    1,
    CURRENT_TIMESTAMP,
    p_id_almacen_origen,
    p_id_almacen_destino,
    p_id_usuario,
    1,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  ) RETURNING id INTO v_id_envio;
  
  RETURN QUERY SELECT 
    true::BOOLEAN,
    v_id_envio::BIGINT,
    v_numero_envio::VARCHAR,
    'Envío creado exitosamente'::VARCHAR;

EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT 
    false::BOOLEAN,
    NULL::BIGINT,
    NULL::VARCHAR,
    ('Error: ' || SQLERRM)::VARCHAR;
END;
$$ LANGUAGE plpgsql;
