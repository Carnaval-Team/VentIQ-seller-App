CREATE OR REPLACE FUNCTION fn_crear_opcion_atributo(
    p_id_atributo BIGINT,
    p_valor VARCHAR,
    p_sku_codigo TEXT,
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
        WHERE id = p_id_atributo
    ) INTO v_attribute_exists;
    
    IF NOT v_attribute_exists THEN
        RAISE EXCEPTION 'Atributo no encontrado';
    END IF;
    
    -- Validate required fields
    IF p_valor IS NULL OR TRIM(p_valor) = '' THEN
        RAISE EXCEPTION 'El valor es requerido';
    END IF;
    
    IF p_sku_codigo IS NULL OR TRIM(p_sku_codigo) = '' THEN
        RAISE EXCEPTION 'El código SKU es requerido';
    END IF;
    
    -- Insert new option
    INSERT INTO app_dat_atributo_opcion (
        id_atributo,
        valor,
        sku_codigo,
        created_at
    ) VALUES (
        p_id_atributo,
        TRIM(p_valor),
        TRIM(p_sku_codigo),
        NOW()
    );
    
    RETURN TRUE;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error al crear opción de atributo: %', SQLERRM;
END;
$$;
