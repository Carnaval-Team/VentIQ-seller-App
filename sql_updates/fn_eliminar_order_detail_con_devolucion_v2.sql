-- ============================================================
-- fn_eliminar_order_detail_con_devolucion  (v2 — delega al trigger)
-- ============================================================
-- CAMBIO IMPORTANTE respecto a la v1:
--   La v1 hacía ella misma la devolución de stock (Carnaval + Inventtia) y
--   DESPUÉS borraba el OrderDetail. Con el trigger nuevo
--   trg_orderdetails_ajustar_erp_del eso devolvería el stock DOS VECES.
--
--   Ahora esta función solo:
--     1) declara el motivo para la bitácora,
--     2) borra el OrderDetail,
--     3) devuelve lo que el trigger registró.
--   Toda la lógica de inventario/operaciones vive en un único lugar:
--   carnavalapp.fn_orderdetails_ajustar_erp(). Así da igual si la app usa esta
--   RPC o borra la línea directamente: el resultado es el mismo.
--
-- Se mantienen la firma de 1 argumento y las mismas claves del JSON de
-- respuesta, así que no hay que cambiar nada en el front. El 2º argumento
-- (p_motivo) es opcional y alimenta la bitácora de capitán.
--
-- REQUISITOS: aplicar antes
--   1) carnaval_orderdetails_bitacora.sql
--   2) carnaval_orderdetails_trigger_ajuste_inventario.sql
-- APLICAR MANUALMENTE en Supabase (SQL Editor).
-- ============================================================

-- La versión de 1 argumento se elimina para que la nueva (con default) no
-- quede ambigua al llamarla con un solo parámetro.
DROP FUNCTION IF EXISTS public.fn_eliminar_order_detail_con_devolucion(bigint);

CREATE OR REPLACE FUNCTION public.fn_eliminar_order_detail_con_devolucion(
    p_detail_id bigint,
    p_motivo    text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_detail          carnavalapp."OrderDetails";
    v_stock_antes     bigint;
    v_stock_despues   bigint;
    v_bitacora        carnavalapp.order_details_bitacora;
BEGIN
    IF p_detail_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'p_detail_id es obligatorio');
    END IF;

    SELECT * INTO v_detail
      FROM carnavalapp."OrderDetails"
     WHERE id = p_detail_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'OrderDetail no encontrado');
    END IF;

    SELECT stock INTO v_stock_antes
      FROM carnavalapp."Productos"
     WHERE id = v_detail.product_id;

    -- Motivo para la bitácora (lo lee el trigger).
    PERFORM set_config('carnavalapp.motivo_cambio',
                       COALESCE(p_motivo, 'Producto quitado de la orden desde la app'),
                       true);

    -- El trigger AFTER DELETE hace: inventario + operación de recepción (tipo 5,
    -- motivo 3) + corrección de la venta + bitácora.
    DELETE FROM carnavalapp."OrderDetails" WHERE id = p_detail_id;

    SELECT stock INTO v_stock_despues
      FROM carnavalapp."Productos"
     WHERE id = v_detail.product_id;

    SELECT * INTO v_bitacora
      FROM carnavalapp.order_details_bitacora
     WHERE order_detail_id = p_detail_id
       AND origen_tg = 'DELETE'
     ORDER BY id DESC
     LIMIT 1;

    RETURN jsonb_build_object(
        'success',                true,
        'message',                CASE
                                     WHEN v_bitacora.id IS NULL
                                       THEN 'Producto eliminado (sin registro de bitácora)'
                                     WHEN v_bitacora.aplicado_erp
                                       THEN 'Producto eliminado y stock devuelto'
                                     ELSE 'Producto eliminado; inventario Inventtia NO ajustado: '
                                          || COALESCE(v_bitacora.erp_error, 'motivo no registrado')
                                  END,
        'order_id',               v_detail.order_id,
        'product_id',             v_detail.product_id,
        'quantity',               v_detail.quantity,
        'carnaval_stock_antes',   v_stock_antes,
        'carnaval_stock_despues', v_stock_despues,
        'operacion_id',           v_bitacora.id_operacion_venta,
        'es_paqueteria',          NULL,
        -- extras nuevos
        'bitacora_id',            v_bitacora.id,
        'aplicado_erp',           COALESCE(v_bitacora.aplicado_erp, false),
        'erp_error',              v_bitacora.erp_error,
        'operacion_ajuste_id',    v_bitacora.id_operacion_ajuste,
        'inventario_antes',       v_bitacora.inventario_antes,
        'inventario_despues',     v_bitacora.inventario_despues
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object('success', false, 'message', SQLERRM);
END;
$$;

COMMENT ON FUNCTION public.fn_eliminar_order_detail_con_devolucion(bigint, text) IS
'Borra un OrderDetail de Carnaval. La devolución de stock/inventario y la bitácora las hace el trigger trg_orderdetails_ajustar_erp_del; aquí solo se declara el motivo y se reporta el resultado.';

GRANT EXECUTE ON FUNCTION public.fn_eliminar_order_detail_con_devolucion(bigint, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_eliminar_order_detail_con_devolucion(bigint, text) TO service_role;
