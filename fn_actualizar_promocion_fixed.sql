-- Drop existing function first to avoid conflicts
DROP FUNCTION IF EXISTS fn_actualizar_promocion;

-- Create the function with exact parameter signature that matches Dart service
CREATE OR REPLACE FUNCTION fn_actualizar_promocion(
    p_id BIGINT,
    p_uuid_usuario UUID,
    p_nombre VARCHAR DEFAULT NULL,
    p_descripcion TEXT DEFAULT NULL,
    p_codigo_promocion VARCHAR DEFAULT NULL,
    p_valor_descuento NUMERIC DEFAULT NULL,
    p_fecha_inicio TIMESTAMP DEFAULT NULL,
    p_fecha_fin TIMESTAMP DEFAULT NULL,
    p_min_compra NUMERIC DEFAULT NULL,
    p_limite_usos INTEGER DEFAULT NULL,
    p_aplica_todo BOOLEAN DEFAULT NULL,
    p_estado BOOLEAN DEFAULT NULL,
    p_id_tipo_promocion INTEGER DEFAULT NULL,
    p_requiere_medio_pago BOOLEAN DEFAULT NULL,
    p_id_medio_pago_requerido INTEGER DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_promotion_exists BOOLEAN := FALSE;
    v_updated_rows INTEGER := 0;
BEGIN
    -- Verificar que la promoción existe
    SELECT EXISTS(
        SELECT 1 FROM app_mkt_promociones 
        WHERE id = p_id
    ) INTO v_promotion_exists;
    
    IF NOT v_promotion_exists THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'La promoción especificada no existe'
        );
    END IF;
    
    -- Actualizar la promoción usando COALESCE para mantener valores existentes
    UPDATE app_mkt_promociones SET
        nombre = COALESCE(p_nombre, nombre),
        descripcion = COALESCE(p_descripcion, descripcion),
        codigo_promocion = COALESCE(p_codigo_promocion, codigo_promocion),
        valor_descuento = COALESCE(p_valor_descuento, valor_descuento),
        fecha_inicio = COALESCE(p_fecha_inicio, fecha_inicio),
        fecha_fin = COALESCE(p_fecha_fin, fecha_fin),
        min_compra = COALESCE(p_min_compra, min_compra),
        limite_usos = COALESCE(p_limite_usos, limite_usos),
        aplica_todo = COALESCE(p_aplica_todo, aplica_todo),
        estado = COALESCE(p_estado, estado),
        id_tipo_promocion = COALESCE(p_id_tipo_promocion, id_tipo_promocion),
        requiere_medio_pago = COALESCE(p_requiere_medio_pago, requiere_medio_pago),
        id_medio_pago_requerido = CASE
            WHEN p_requiere_medio_pago IS FALSE THEN NULL
            ELSE COALESCE(p_id_medio_pago_requerido, id_medio_pago_requerido)
        END
    WHERE id = p_id;
    
    GET DIAGNOSTICS v_updated_rows = ROW_COUNT;
    
    IF v_updated_rows > 0 THEN
        RETURN jsonb_build_object(
            'success', true,
            'message', 'Promoción actualizada exitosamente',
            'id', p_id
        );
    ELSE
        RETURN jsonb_build_object(
            'success', false,
            'message', 'No se pudo actualizar la promoción'
        );
    END IF;
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Error interno: ' || SQLERRM
        );
END;
$$;
