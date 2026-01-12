-- RPC para crear un gerente desde email, nombres, apellidos e id_tienda
-- Crea un nuevo trabajador y lo asigna como gerente en una transacción
-- SECURITY DEFINER permite que usuarios normales accedan a auth.users
CREATE OR REPLACE FUNCTION create_gerente_from_email(
  p_email TEXT,
  p_nombres TEXT,
  p_apellidos TEXT,
  p_id_tienda BIGINT
)
RETURNS TABLE (
  gerente_id BIGINT,
  trabajador_id BIGINT,
  uuid UUID,
  email TEXT,
  nombres TEXT,
  apellidos TEXT,
  id_tienda BIGINT,
  created_at TIMESTAMP WITH TIME ZONE
) SECURITY DEFINER AS $$
DECLARE
  v_user_id UUID;
  v_trabajador_id BIGINT;
  v_gerente_id BIGINT;
  v_nombres TEXT;
  v_apellidos TEXT;
BEGIN
  -- 1. Buscar el usuario en auth.users por email
  SELECT auth.users.id INTO v_user_id
  FROM auth.users
  WHERE auth.users.email = p_email
  LIMIT 1;

  -- Si no existe el usuario, lanzar error
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario con email % no encontrado en auth.users', p_email;
  END IF;

  -- Convertir a TEXT para consistencia
  v_nombres := p_nombres::TEXT;
  v_apellidos := p_apellidos::TEXT;

  -- 2. Crear el trabajador
  INSERT INTO app_dat_trabajadores (uuid, nombres, apellidos, id_tienda)
  VALUES (v_user_id, v_nombres, v_apellidos, p_id_tienda)
  RETURNING id INTO v_trabajador_id;

  -- 3. Crear el gerente
  INSERT INTO app_dat_gerente (uuid, id_tienda, id_trabajador)
  VALUES (v_user_id, p_id_tienda, v_trabajador_id)
  RETURNING id INTO v_gerente_id;

  -- 4. Retornar los datos creados
  RETURN QUERY
  SELECT 
    v_gerente_id::BIGINT,
    v_trabajador_id::BIGINT,
    v_user_id::UUID,
    p_email::TEXT,
    v_nombres::TEXT,
    v_apellidos::TEXT,
    p_id_tienda::BIGINT,
    NOW()::TIMESTAMP WITH TIME ZONE;
END;
$$ LANGUAGE plpgsql;
