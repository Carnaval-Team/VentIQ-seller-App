CREATE OR REPLACE FUNCTION fn_crear_atributo(
    p_denominacion VARCHAR,
    p_label VARCHAR,
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
BEGIN
    -- Validate user exists
    SELECT EXISTS(
        SELECT 1 FROM auth.users 
        WHERE id = p_uuid_usuario
    ) INTO v_user_exists;
    
    IF NOT v_user_exists THEN
        RAISE EXCEPTION 'Usuario no válido';
    END IF;
    
    -- Validate required fields
    IF p_denominacion IS NULL OR TRIM(p_denominacion) = '' THEN
        RAISE EXCEPTION 'La denominación es requerida';
    END IF;
    
    IF p_label IS NULL OR TRIM(p_label) = '' THEN
        RAISE EXCEPTION 'El label es requerido';
    END IF;
    
    -- Insert new attribute
    INSERT INTO app_dat_atributos (
        denominacion,
        label,
        descripcion,
        created_at
    ) VALUES (
        TRIM(p_denominacion),
        TRIM(p_label),
        TRIM(p_descripcion),
        NOW()
    );
    
    RETURN TRUE;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error al crear atributo: %', SQLERRM;
END;
$$;
