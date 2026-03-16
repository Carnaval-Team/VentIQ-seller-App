-- Function: admin_change_user_password
-- Description: Allows a superadmin to change a user's password by email.
-- Requires: postgres role / service_role key (called via Supabase RPC with service_role).
-- Note: This function uses auth.users which requires elevated privileges.

CREATE OR REPLACE FUNCTION public.admin_change_user_password(
    p_email TEXT,
    p_new_password TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    -- Validate inputs
    IF p_email IS NULL OR TRIM(p_email) = '' THEN
        RETURN jsonb_build_object('success', false, 'message', 'El correo no puede estar vacío');
    END IF;

    IF p_new_password IS NULL OR LENGTH(p_new_password) < 6 THEN
        RETURN jsonb_build_object('success', false, 'message', 'La contraseña debe tener al menos 6 caracteres');
    END IF;

    -- Look up the user by email
    SELECT id INTO v_user_id
    FROM auth.users
    WHERE email = TRIM(LOWER(p_email))
    LIMIT 1;

    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'No se encontró ningún usuario con ese correo');
    END IF;

    -- Update the password using Supabase auth admin function
    UPDATE auth.users
    SET
        encrypted_password = crypt(p_new_password, gen_salt('bf')),
        updated_at = NOW()
    WHERE id = v_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Contraseña actualizada correctamente',
        'user_id', v_user_id::TEXT
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', SQLERRM
        );
END;
$$;

-- Grant execution to authenticated users with superadmin role
-- (Supabase service_role bypasses RLS so this is safe when called from superadmin app)
GRANT EXECUTE ON FUNCTION public.admin_change_user_password(TEXT, TEXT) TO service_role;
