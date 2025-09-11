CREATE OR REPLACE FUNCTION fn_cambiar_estado_promocion(
    p_id_promocion BIGINT,
    p_nuevo_estado BOOLEAN,
    p_usuario_modificador VARCHAR DEFAULT 'sistema'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    SET search_path = public;
    
    -- Validar que la promoción existe
    IF NOT EXISTS (SELECT 1 FROM app_mkt_promociones WHERE id = p_id_promocion) THEN
        RAISE EXCEPTION 'Promoción con ID % no encontrada', p_id_promocion;
    END IF;
    
    -- Actualizar el estado de la promoción
    UPDATE app_mkt_promociones 
    SET 
        estado = p_nuevo_estado,
        created_at = COALESCE(created_at, NOW()) -- Mantener fecha original o usar NOW si es null
    WHERE id = p_id_promocion;
    
    -- Verificar que se actualizó correctamente
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No se pudo actualizar el estado de la promoción %', p_id_promocion;
    END IF;
    
    RETURN TRUE;
END;
$$;
