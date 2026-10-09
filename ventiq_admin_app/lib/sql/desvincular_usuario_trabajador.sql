-- ============================================================================
-- fn_desvincular_usuario_trabajador
-- Quita la asociación Auth de un trabajador, elimina sus roles de aplicación
-- en todas las tablas de roles y deja el registro de trabajador intacto.
-- NO borra la cuenta del usuario en auth.users.
-- Ejecutar en Supabase SQL Editor antes de probar la app.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_desvincular_usuario_trabajador(
  p_trabajador_id bigint,
  p_id_tienda bigint
)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
  v_trabajador_existe boolean := false;
  v_trabajador_uuid uuid;
  v_roles_eliminados int := 0;
  v_count int := 0;
BEGIN
  -- Verificar que el trabajador existe en la tienda y obtener su UUID actual
  SELECT EXISTS(
    SELECT 1 FROM app_dat_trabajadores
    WHERE id = p_trabajador_id
      AND id_tienda = p_id_tienda
      AND deleted_at IS NULL
  ), uuid
  INTO v_trabajador_existe, v_trabajador_uuid
  FROM app_dat_trabajadores
  WHERE id = p_trabajador_id
    AND id_tienda = p_id_tienda
    AND deleted_at IS NULL
  LIMIT 1;

  IF NOT v_trabajador_existe THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Trabajador no encontrado',
      'error_code', 20001
    );
  END IF;

  -- Eliminar todos los roles de aplicación asociados al trabajador
  DELETE FROM app_dat_gerente WHERE id_trabajador = p_trabajador_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_roles_eliminados := v_roles_eliminados + v_count;

  DELETE FROM app_dat_supervisor WHERE id_trabajador = p_trabajador_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_roles_eliminados := v_roles_eliminados + v_count;

  DELETE FROM app_dat_vendedor WHERE id_trabajador = p_trabajador_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_roles_eliminados := v_roles_eliminados + v_count;

  DELETE FROM app_dat_almacenero WHERE id_trabajador = p_trabajador_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_roles_eliminados := v_roles_eliminados + v_count;

  DELETE FROM app_dat_recursos_humanos WHERE id_trabajador = p_trabajador_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_roles_eliminados := v_roles_eliminados + v_count;

  DELETE FROM auditor WHERE id_trabajador = p_trabajador_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_roles_eliminados := v_roles_eliminados + v_count;

  -- Desvincular el usuario Auth y el rol general del trabajador.
  -- No se elimina la cuenta de auth.users.
  UPDATE app_dat_trabajadores
  SET uuid = NULL,
      id_roll = NULL,
      user_mail = NULL
  WHERE id = p_trabajador_id
    AND id_tienda = p_id_tienda;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Usuario desvinculado y roles eliminados correctamente',
    'uuid_previo', v_trabajador_uuid,
    'roles_eliminados', v_roles_eliminados
  );

EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Error al desvincular usuario del trabajador: ' || SQLERRM,
      'error_code', 20000
    );
END;
$function$;

NOTIFY pgrst, 'reload schema';
