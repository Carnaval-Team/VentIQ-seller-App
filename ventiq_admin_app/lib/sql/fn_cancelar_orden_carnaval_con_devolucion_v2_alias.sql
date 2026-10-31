-- ============================================================
-- Alias de compatibilidad
-- fn_cancelar_orden_carnaval_con_devolucion_v2
-- ============================================================
-- Builds antiguos de la app llamaban este nombre; la RPC real es
-- fn_cancelar_orden_carnaval_v2 (ver fn_cancelar_orden_carnaval_v2.sql).
-- Este wrapper evita PGRST202 sin forzar redeploy inmediato del cliente.
--
-- APLICAR en Supabase SQL Editor (main).
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_cancelar_orden_carnaval_con_devolucion_v2(
    p_order_id bigint,
    p_changed_by text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
    RETURN public.fn_cancelar_orden_carnaval_v2(p_order_id, p_changed_by);
END;
$$;

COMMENT ON FUNCTION public.fn_cancelar_orden_carnaval_con_devolucion_v2(bigint, text) IS
    'Alias de fn_cancelar_orden_carnaval_v2 para clientes que aún usan el nombre antiguo.';

GRANT EXECUTE ON FUNCTION public.fn_cancelar_orden_carnaval_con_devolucion_v2(bigint, text)
    TO authenticated;

GRANT EXECUTE ON FUNCTION public.fn_cancelar_orden_carnaval_con_devolucion_v2(bigint, text)
    TO service_role;

NOTIFY pgrst, 'reload schema';
