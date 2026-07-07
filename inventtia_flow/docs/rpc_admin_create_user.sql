-- RPC para crear un nuevo usuario (auth.users + flow.perfil) desde el panel
-- de administración. Se ejecuta con SECURITY DEFINER para poder insertar en
-- auth.users, que normalmente no es accesible desde el rol authenticated.

CREATE OR REPLACE FUNCTION flow.admin_create_user(
  p_email text,
  p_password text,
  p_nombre text,
  p_apellidos text,
  p_ci text,
  p_telefono text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = flow, extensions, public, auth
AS $$
DECLARE
  v_uuid uuid;
  v_hash text;
BEGIN
  -- Normalizar email
  p_email := lower(trim(p_email));

  -- Verificar que no exista un usuario con ese email
  IF EXISTS (SELECT 1 FROM auth.users WHERE email = p_email) THEN
    RAISE EXCEPTION 'Ya existe un usuario con el correo %', p_email;
  END IF;

  -- Hashear la contraseña con bcrypt
  v_hash := crypt(p_password, gen_salt('bf'));

  -- Crear el usuario en auth.users
  INSERT INTO auth.users (
    id,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_user_meta_data
  )
  VALUES (
    gen_random_uuid(),
    p_email,
    v_hash,
    now(),
    jsonb_build_object('nombre', p_nombre, 'apellidos', p_apellidos)
  )
  RETURNING id INTO v_uuid;

  -- Crear el perfil en flow.perfil
  INSERT INTO flow.perfil (uuid_usuario, nombre, apellidos, ci, telefono)
  VALUES (v_uuid, p_nombre, p_apellidos, p_ci, p_telefono);

  RETURN v_uuid;
END;
$$;

-- Permitir que usuarios autenticados ejecuten la función.
GRANT EXECUTE ON FUNCTION flow.admin_create_user(text, text, text, text, text, text) TO authenticated;
