CREATE OR REPLACE FUNCTION fn_eliminar_opcion_atributo(
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
    v_option_exists BOOLEAN;
    v_is_used BOOLEAN;
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
    
    -- Check if option is being used in inventory, receptions, extractions, etc.
    SELECT EXISTS(
        SELECT 1 FROM app_dat_inventario_productos 
        WHERE id_opcion_variante = p_id
        UNION ALL
        SELECT 1 FROM app_dat_recepcion_productos 
        WHERE id_opcion_variante = p_id
        UNION ALL
        SELECT 1 FROM app_dat_extraccion_productos 
        WHERE id_opcion_variante = p_id
        UNION ALL
        SELECT 1 FROM app_dat_control_productos 
        WHERE id_opcion_variante = p_id
    ) INTO v_is_used;
    
    IF v_is_used THEN
        RAISE EXCEPTION 'No se puede eliminar la opción porque está siendo usada en productos o operaciones';
    END IF;
    
    -- Delete option
    DELETE FROM app_dat_atributo_opcion WHERE id = p_id;
    
    RETURN FOUND;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error al eliminar opción de atributo: %', SQLERRM;
END;
$$;
