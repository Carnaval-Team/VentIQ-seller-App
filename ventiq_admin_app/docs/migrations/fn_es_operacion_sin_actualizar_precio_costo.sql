-- ============================================================================
-- Operaciones que NO deben recalcular precio_promedio (costo):
--   - Recepción por transferencia (motivo = 2)
--   - Devolución de consignación (tipo_envio = 2)
--   - Cualquier op. vinculada en app_dat_operacion_transferencia
--
-- Usar al inicio de fn_actualizar_precio_promedio_recepcion_v2:
--
--   IF public.fn_es_operacion_sin_actualizar_precio_costo(p_id_operacion) THEN
--     RETURN QUERY SELECT true, 'Precio costo no actualizado (transferencia/devolución)'::TEXT, 0, 0;
--     RETURN;
--   END IF;
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_es_operacion_sin_actualizar_precio_costo(
  p_id_operacion BIGINT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT
    EXISTS (
      SELECT 1
      FROM public.app_dat_operacion_recepcion r
      WHERE r.id_operacion = p_id_operacion
        AND r.motivo = 2
    )
    OR EXISTS (
      SELECT 1
      FROM public.app_dat_consignacion_envio ce
      WHERE ce.id_operacion_recepcion = p_id_operacion
        AND ce.tipo_envio = 2
    )
    OR EXISTS (
      SELECT 1
      FROM public.app_dat_operacion_transferencia t
      WHERE t.id_recepcion = p_id_operacion
         OR t.id_extraccion = p_id_operacion
    );
$$;

COMMENT ON FUNCTION public.fn_es_operacion_sin_actualizar_precio_costo(BIGINT) IS
  'true si la operación es transferencia interna o devolución y no debe alterar precio_promedio.';

GRANT EXECUTE ON FUNCTION public.fn_es_operacion_sin_actualizar_precio_costo(BIGINT)
  TO authenticated, service_role;
