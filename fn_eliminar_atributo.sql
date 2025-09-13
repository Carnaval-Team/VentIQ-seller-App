CREATE OR REPLACE FUNCTION fn_eliminar_atributo(
    p_id BIGINT,
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
    v_has_options BOOLEAN;
    v_has_variants BOOLEAN;
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
    
    -- Check if attribute has options
    SELECT EXISTS(
        SELECT 1 FROM app_dat_atributo_opcion 
        WHERE id_atributo = p_id
    ) INTO v_has_options;
    
    -- Check if attribute is used in variants
    SELECT EXISTS(
        SELECT 1 FROM app_dat_variantes 
        WHERE id_atributo = p_id
    ) INTO v_has_variants;
    
    IF v_has_variants THEN
        RAISE EXCEPTION 'No se puede eliminar el atributo porque está siendo usado en variantes de productos';
    END IF;
    
    -- Delete options first if they exist
    IF v_has_options THEN
        DELETE FROM app_dat_atributo_opcion WHERE id_atributo = p_id;
    END IF;
    
    -- Delete attribute
    DELETE FROM app_dat_atributos WHERE id = p_id;
    
    RETURN FOUND;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error al eliminar atributo: %', SQLERRM;
END;
$$;
