CREATE OR REPLACE FUNCTION fn_actualizar_opcion_atributo(
    p_id BIGINT,
    p_uuid_usuario UUID,
    p_valor VARCHAR DEFAULT NULL,
    p_sku_codigo TEXT DEFAULT NULL    
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_exists BOOLEAN;
    v_option_exists BOOLEAN;
BEGIN
    -- Validate user exists
    SELECT EXISTS(
        SELECT 1 FROM auth.users 
        WHERE id = p_uuid_usuario
    ) INTO v_user_exists;
    
    IF NOT v_user_exists THEN
        RAISE EXCEPTION 'Usuario no válido';
    END IF;
    
    -- Validate option exists
    SELECT EXISTS(
        SELECT 1 FROM app_dat_atributo_opcion 
        WHERE id = p_id
    ) INTO v_option_exists;
    
    IF NOT v_option_exists THEN
        RAISE EXCEPTION 'Opción de atributo no encontrada';
    END IF;
    
    -- Update option
    UPDATE app_dat_atributo_opcion SET
        valor = COALESCE(NULLIF(TRIM(p_valor), ''), valor),
        sku_codigo = COALESCE(NULLIF(TRIM(p_sku_codigo), ''), sku_codigo)
    WHERE id = p_id;
    
    RETURN FOUND;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error al actualizar opción de atributo: %', SQLERRM;
END;
$$;
