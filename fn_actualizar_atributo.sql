CREATE OR REPLACE FUNCTION fn_actualizar_atributo(
    p_id BIGINT,
    p_denominacion VARCHAR DEFAULT NULL,
    p_descripcion VARCHAR DEFAULT NULL,
    p_uuid_usuario UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_exists BOOLEAN;
    v_attribute_exists BOOLEAN;
BEGIN
    -- Validate user exists
    SELECT EXISTS(
        SELECT 1 FROM auth.users 
        WHERE id = p_uuid_usuario
    ) INTO v_user_exists;
    
    IF NOT v_user_exists THEN
        RAISE EXCEPTION 'Usuario no válido';
    END IF;
    
    -- Validate attribute exists
    SELECT EXISTS(
        SELECT 1 FROM app_dat_atributos 
        WHERE id = p_id
    ) INTO v_attribute_exists;
    
    IF NOT v_attribute_exists THEN
        RAISE EXCEPTION 'Atributo no encontrado';
    END IF;
    
    -- Update attribute
    UPDATE app_dat_atributos SET
        denominacion = COALESCE(NULLIF(TRIM(p_denominacion), ''), denominacion),
        descripcion = COALESCE(NULLIF(TRIM(p_descripcion), ''), descripcion)
    WHERE id = p_id;
    
    RETURN FOUND;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error al actualizar atributo: %', SQLERRM;
END;
$$;
