-- ============================================================
-- fn_cancelar_orden_carnaval_v2
-- ============================================================
-- Cancela una orden de Carnaval que ya fue entregada al repartidor
-- (estado 'Entregando' o posterior) devolviendo el inventario extraído.
--   1) Preserva los totales originales de la orden antes de borrar detalles.
--   2) Reutiliza fn_eliminar_order_detail_con_devolucion para cada detalle.
--   3) Marca la orden como 'Cancelado'.
--   4) Restaura los totales originales (la orden cancelada sigue mostrando
--      los montos que tenía).
--   5) Registra el cambio en order_status_history.
--
-- Idempotente: CREATE OR REPLACE.
-- APLICAR MANUALMENTE en Supabase (SQL Editor).
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_cancelar_orden_carnaval_v2(
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
    v_total_cup_orig numeric;
    v_total_usd_orig numeric;
    v_total_euro_orig numeric;
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

    -- Capturar los totales originales ANTES de eliminar los detalles.
    -- El trigger de OrderDetails recalcula los totales a 0 al borrar líneas,
    -- por eso los restauramos explícitamente al final.
    v_total_cup_orig  := COALESCE(v_order.total, 0)::numeric;
    v_total_usd_orig  := COALESCE(v_order."totalUsd", 0)::numeric;
    v_total_euro_orig := COALESCE(v_order."totalEuro", 0)::numeric;

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

    -- Restaurar los montos originales para que la orden cancelada
    -- siga mostrando los importes en pantalla y reportes.
    UPDATE carnavalapp."Orders"
    SET total       = v_total_cup_orig::real,
        "totalUsd"  = v_total_usd_orig::real,
        "totalEuro" = v_total_euro_orig::real
    WHERE id = p_order_id;

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Orden cancelada',
        'order_id', p_order_id,
        'detalles_cancelados', v_cancelados,
        'detalles_fallidos', v_fallidos,
        'total_cup_preservado', v_total_cup_orig,
        'total_usd_preservado', v_total_usd_orig,
        'total_euro_preservado', v_total_euro_orig
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', SQLERRM
        );
END;
$$;

COMMENT ON FUNCTION public.fn_cancelar_orden_carnaval_v2(bigint, text) IS
    'Cancela una orden Carnaval en entrega, devuelve stock y preserva los montos originales de la orden.';

GRANT EXECUTE ON FUNCTION public.fn_cancelar_orden_carnaval_v2(bigint, text)
    TO authenticated;

GRANT EXECUTE ON FUNCTION public.fn_cancelar_orden_carnaval_v2(bigint, text)
    TO service_role;

NOTIFY pgrst, 'reload schema';
