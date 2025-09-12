CREATE OR REPLACE FUNCTION fn_actualizar_operacion_recepcion(
    p_id_operacion BIGINT,
    p_entregado_por VARCHAR DEFAULT NULL,
    p_recibido_por VARCHAR DEFAULT NULL,
    p_monto_total NUMERIC DEFAULT NULL,
    p_observaciones VARCHAR DEFAULT NULL,
    p_numero_factura VARCHAR DEFAULT NULL,
    p_fecha_factura DATE DEFAULT NULL,
    p_monto_factura NUMERIC DEFAULT NULL,
    p_moneda_factura CHAR(3) DEFAULT NULL,
    p_pdf_factura TEXT DEFAULT NULL,
    p_observaciones_compra TEXT DEFAULT NULL,
    -- Parámetros para productos (JSON array)
    p_productos_data JSONB DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_exists BOOLEAN;
    v_producto JSONB;
    v_id_producto BIGINT;
    v_precio_unitario NUMERIC;
    v_precio_referencia NUMERIC;
    v_descuento_porcentaje NUMERIC;
    v_descuento_monto NUMERIC;
    v_bonificacion_cantidad NUMERIC;
    v_updated_count INTEGER := 0;
BEGIN
    -- Verificar que la operación existe y es de tipo recepción
    SELECT EXISTS(
        SELECT 1 
        FROM app_dat_operaciones o
        INNER JOIN app_dat_operacion_recepcion r ON o.id = r.id_operacion
        WHERE o.id = p_id_operacion
    ) INTO v_exists;
    
    IF NOT v_exists THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Operación de recepción no encontrada'
        );
    END IF;
    
    -- Actualizar datos de la operación de recepción
    UPDATE app_dat_operacion_recepcion SET
        entregado_por = COALESCE(p_entregado_por, entregado_por),
        recibido_por = COALESCE(p_recibido_por, recibido_por),
        monto_total = COALESCE(p_monto_total, monto_total),
        observaciones = COALESCE(p_observaciones, observaciones),
        numero_factura = COALESCE(p_numero_factura, numero_factura),
        fecha_factura = COALESCE(p_fecha_factura, fecha_factura),
        monto_factura = COALESCE(p_monto_factura, monto_factura),
        moneda_factura = COALESCE(p_moneda_factura, moneda_factura),
        pdf_factura = COALESCE(p_pdf_factura, pdf_factura),
        observaciones_compra = COALESCE(p_observaciones_compra, observaciones_compra)
    WHERE id_operacion = p_id_operacion;
    
    -- Actualizar datos de productos si se proporcionan
    IF p_productos_data IS NOT NULL THEN
        FOR v_producto IN SELECT * FROM jsonb_array_elements(p_productos_data)
        LOOP
            -- Extraer datos del producto
            v_id_producto := (v_producto->>'id_producto')::BIGINT;
            v_precio_unitario := (v_producto->>'precio_unitario')::NUMERIC;
            v_precio_referencia := (v_producto->>'precio_referencia')::NUMERIC;
            v_descuento_porcentaje := (v_producto->>'descuento_porcentaje')::NUMERIC;
            v_descuento_monto := (v_producto->>'descuento_monto')::NUMERIC;
            v_bonificacion_cantidad := (v_producto->>'bonificacion_cantidad')::NUMERIC;
            
            -- Actualizar solo campos de precios y descuentos (NO cantidad ni ubicación)
            UPDATE app_dat_recepcion_productos SET
                precio_unitario = COALESCE(v_precio_unitario, precio_unitario),
                precio_referencia = COALESCE(v_precio_referencia, precio_referencia),
                descuento_porcentaje = COALESCE(v_descuento_porcentaje, descuento_porcentaje),
                descuento_monto = COALESCE(v_descuento_monto, descuento_monto),
                bonificacion_cantidad = COALESCE(v_bonificacion_cantidad, bonificacion_cantidad)
            WHERE id_operacion = p_id_operacion 
              AND id_producto = v_id_producto;
            
            GET DIAGNOSTICS v_updated_count = ROW_COUNT;
        END LOOP;
    END IF;
    
    -- Recalcular monto total si no se proporcionó explícitamente
    IF p_monto_total IS NULL THEN
        UPDATE app_dat_operacion_recepcion SET
            monto_total = (
                SELECT COALESCE(SUM(
                    (cantidad + COALESCE(bonificacion_cantidad, 0)) * 
                    COALESCE(costo_real, precio_unitario, 0)
                ), 0)
                FROM app_dat_recepcion_productos
                WHERE id_operacion = p_id_operacion
            )
        WHERE id_operacion = p_id_operacion;
    END IF;
    
    RETURN json_build_object(
        'success', true,
        'message', 'Operación de recepción actualizada correctamente',
        'id_operacion', p_id_operacion,
        'productos_actualizados', v_updated_count
    );
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Error al actualizar operación: ' || SQLERRM
        );
END;
$$;
