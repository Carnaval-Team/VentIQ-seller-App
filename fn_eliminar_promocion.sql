CREATE OR REPLACE FUNCTION fn_eliminar_promocion(
    p_id_promocion BIGINT,
    p_usuario_eliminador VARCHAR DEFAULT 'sistema'
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
    
    -- Eliminar registros relacionados en orden correcto para evitar violaciones de FK
    
    -- 1. Eliminar relaciones con segmentos
    DELETE FROM app_mkt_promocion_segmento WHERE id_promocion = p_id_promocion;
    
    -- 2. Eliminar relaciones con productos
    DELETE FROM app_mkt_promocion_productos WHERE id_promocion = p_id_promocion;
    
    -- 3. Eliminar usos de clientes (si existen)
    DELETE FROM app_mkt_cliente_promociones WHERE id_promocion = p_id_promocion;
    
    -- 4. Finalmente eliminar la promoción principal
    DELETE FROM app_mkt_promociones WHERE id = p_id_promocion;
    
    -- Verificar que se eliminó correctamente
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No se pudo eliminar la promoción %', p_id_promocion;
    END IF;
    
    RETURN TRUE;
END;
$$;
