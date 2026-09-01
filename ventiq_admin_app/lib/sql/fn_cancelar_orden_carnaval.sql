-- ============================================================
-- fn_cancelar_orden_carnaval
-- ============================================================
-- Cancela una orden de Carnaval que ya fue entregada al repartidor
-- (estado 'Entregando' o posterior) devolviendo el inventario extraído.
--   1) Reutiliza fn_eliminar_order_detail_con_devolucion para cada detalle.
--   2) Marca la orden como 'Cancelado'.
--   3) Registra el cambio en order_status_history.
--
-- Idempotente: CREATE OR REPLACE.
-- APLICAR MANUALMENTE en Supabase (SQL Editor).
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_cancelar_orden_carnaval(
    p_order_id bigint,
    p_changed_by text default null
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_order RECORD;
    v_detail_ids bigint[];
    v_detail_id bigint;
    v_result jsonb;
    v_cancelados int := 0;
    v_fallidos int := 0;
BEGIN
    SELECT *
    INTO v_order
    FROM carnavalapp."Orders"
    WHERE id = p_order_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Orden no encontrada'
        );
    END IF;

    IF v_order.status IN ('Completado', 'Cancelado') THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'La orden ya está ' || v_order.status
        );
    END IF;

    -- Capturar IDs antes de ir eliminándolos
    SELECT array_agg(id)
    INTO v_detail_ids
    FROM carnavalapp."OrderDetails"
    WHERE order_id = p_order_id;

    IF v_detail_ids IS NOT NULL THEN
        FOREACH v_detail_id IN ARRAY v_detail_ids
        LOOP
            v_result := public.fn_eliminar_order_detail_con_devolucion(v_detail_id);
            IF (v_result->>'success')::boolean THEN
                v_cancelados := v_cancelados + 1;
            ELSE
                v_fallidos := v_fallidos + 1;
            END IF;
        END LOOP;
    END IF;

    UPDATE carnavalapp."Orders"
    SET status = 'Cancelado'
    WHERE id = p_order_id;

    INSERT INTO carnavalapp.order_status_history (
        order_id,
        status,
        changed_by
    ) VALUES (
        p_order_id,
        'Cancelado',
        p_changed_by
    );

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Orden cancelada',
        'order_id', p_order_id,
        'detalles_cancelados', v_cancelados,
        'detalles_fallidos', v_fallidos
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', SQLERRM
        );
END;
$$;

COMMENT ON FUNCTION public.fn_cancelar_orden_carnaval(bigint, text) IS
    'Cancela una orden Carnaval en entrega y devuelve el inventario correspondiente.';

GRANT EXECUTE ON FUNCTION public.fn_cancelar_orden_carnaval(bigint, text)
    TO authenticated;

GRANT EXECUTE ON FUNCTION public.fn_cancelar_orden_carnaval(bigint, text)
    TO service_role;
