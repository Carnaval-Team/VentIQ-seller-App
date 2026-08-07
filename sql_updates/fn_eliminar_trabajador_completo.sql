-- ============================================================================
-- fn_eliminar_trabajador_completo
-- Elimina todas las relaciones de roles del trabajador y, si no tiene
-- historial operativo/HR, borra el registro; si tiene historial, soft-delete.
-- Ejecutar en Supabase SQL Editor.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_eliminar_trabajador_completo(
  p_trabajador_id bigint,
  p_id_tienda bigint
)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
  v_tiene_operaciones boolean := false;
  v_trabajador_existe boolean := false;
  v_trabajador_uuid uuid;
  v_roles_eliminados int := 0;
  v_count int := 0;
BEGIN
  SELECT EXISTS(
    SELECT 1 FROM app_dat_trabajadores
    WHERE id = p_trabajador_id
      AND id_tienda = p_id_tienda
  ), uuid
  INTO v_trabajador_existe, v_trabajador_uuid
  FROM app_dat_trabajadores
  WHERE id = p_trabajador_id
    AND id_tienda = p_id_tienda
  LIMIT 1;

  IF NOT v_trabajador_existe THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Trabajador no encontrado',
      'error_code', 20001
    );
  END IF;

  SELECT
    EXISTS(SELECT 1 FROM app_dat_operaciones WHERE uuid = v_trabajador_uuid)
    OR EXISTS(
      SELECT 1 FROM app_dat_caja_turno ct
      WHERE ct.id_vendedor IN (
        SELECT v.id FROM app_dat_vendedor v WHERE v.id_trabajador = p_trabajador_id
      )
    )
    OR EXISTS(SELECT 1 FROM app_cont_gastos WHERE uuid = v_trabajador_uuid)
    OR EXISTS(SELECT 1 FROM app_dat_ajuste_inventario WHERE uuid_usuario = v_trabajador_uuid)
    OR EXISTS(SELECT 1 FROM app_cont_egresos_procesados WHERE procesado_por = v_trabajador_uuid)
    OR EXISTS(SELECT 1 FROM app_dat_estado_operacion WHERE uuid = v_trabajador_uuid)
    OR EXISTS(SELECT 1 FROM app_dat_pago_venta WHERE creado_por = v_trabajador_uuid)
    OR EXISTS(SELECT 1 FROM hr_dat_asistencia WHERE id_trabajador = p_trabajador_id)
    OR EXISTS(SELECT 1 FROM hr_dat_auditoria_salario WHERE id_trabajador = p_trabajador_id)
  INTO v_tiene_operaciones;

  -- Quitar TODAS las relaciones de roles de la app (siempre)
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

  IF v_tiene_operaciones THEN
    UPDATE app_dat_trabajadores
    SET deleted_at = NOW()
    WHERE id = p_trabajador_id
      AND id_tienda = p_id_tienda
      AND deleted_at IS NULL;

    IF NOT FOUND THEN
      RETURN jsonb_build_object(
        'success', true,
        'message', 'Roles eliminados; el trabajador ya estaba desactivado',
        'soft_delete', true,
        'roles_eliminados', v_roles_eliminados
      );
    END IF;

    RETURN jsonb_build_object(
      'success', true,
      'message', 'Trabajador desactivado y roles eliminados (tiene historial operativo)',
      'soft_delete', true,
      'roles_eliminados', v_roles_eliminados
    );
  ELSE
    DELETE FROM app_dat_trabajadores
    WHERE id = p_trabajador_id
      AND id_tienda = p_id_tienda;

    RETURN jsonb_build_object(
      'success', true,
      'message', 'Trabajador y roles eliminados completamente',
      'soft_delete', false,
      'roles_eliminados', v_roles_eliminados
    );
  END IF;

EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Error al eliminar trabajador: ' || SQLERRM,
      'error_code', 20000
    );
END;
$function$;
