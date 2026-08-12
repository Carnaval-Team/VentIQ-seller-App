-- ============================================================
-- fn_eliminar_order_detail_con_devolucion
-- ============================================================
-- Al quitar un producto de una orden Carnaval:
--   1) Devuelve stock en carnavalapp."Productos"
--   2) Devuelve stock en Inventtia (inventario + limpia extracción)
--   3) Ajusta importe de la venta Inventtia
--   4) Elimina el OrderDetail
--
-- Idempotente: CREATE OR REPLACE.
-- APLICAR MANUALMENTE en Supabase (SQL Editor).
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_eliminar_order_detail_con_devolucion(
    p_detail_id bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_detail RECORD;
    v_order RECORD;
    v_es_paqueteria boolean := false;
    v_producto_inventtia bigint;
    v_tienda_id bigint;
    v_operacion_id bigint;
    v_extraccion RECORD;
    v_inventario_actual RECORD;
    v_presentacion_id bigint;
    v_nuevo_importe numeric;
    v_carnaval_stock_antes bigint;
    v_carnaval_stock_despues bigint;
BEGIN
    IF p_detail_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'p_detail_id es obligatorio'
        );
    END IF;

    SELECT *
    INTO v_detail
    FROM carnavalapp."OrderDetails"
    WHERE id = p_detail_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'OrderDetail no encontrado'
        );
    END IF;

    SELECT *
    INTO v_order
    FROM carnavalapp."Orders"
    WHERE id = v_detail.order_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Orden Carnaval no encontrada'
        );
    END IF;

    v_es_paqueteria := COALESCE(
        v_order.paqueteria IS NOT NULL
        AND v_order.paqueteria <> 'null'::jsonb
        AND jsonb_typeof(v_order.paqueteria) = 'object'
        AND v_order.paqueteria <> '{}'::jsonb,
        false
    );

    -- --------------------------------------------------------
    -- 1) Devolver stock en Carnaval
    -- --------------------------------------------------------
    SELECT stock INTO v_carnaval_stock_antes
    FROM carnavalapp."Productos"
    WHERE id = v_detail.product_id;

    UPDATE carnavalapp."Productos"
    SET stock = COALESCE(stock, 0) + COALESCE(v_detail.quantity, 1)
    WHERE id = v_detail.product_id
    RETURNING stock INTO v_carnaval_stock_despues;

    -- --------------------------------------------------------
    -- 2) Devolver inventario Inventtia (si no es paquetería)
    -- --------------------------------------------------------
    IF NOT v_es_paqueteria THEN
        SELECT id INTO v_producto_inventtia
        FROM public.app_dat_producto
        WHERE id_vendedor_app = v_detail.product_id
        LIMIT 1;

        IF v_producto_inventtia IS NOT NULL THEN
            -- Tienda del proveedor del detalle
            IF v_detail.proveedor IS NOT NULL THEN
                SELECT id INTO v_tienda_id
                FROM public.app_dat_tienda
                WHERE id_tienda_carnaval = v_detail.proveedor
                LIMIT 1;
            END IF;

            -- Operación Inventtia ligada a la orden
            SELECT o.id INTO v_operacion_id
            FROM public.app_dat_operaciones o
            WHERE (
                    o.id_carnaval_order = v_order.id
                    OR o.observaciones = 'Venta desde orden ' || v_order.id
                  )
              AND (v_tienda_id IS NULL OR o.id_tienda = v_tienda_id)
            ORDER BY o.id DESC
            LIMIT 1;

            IF v_operacion_id IS NOT NULL THEN
                -- Preferir extracción con misma cantidad; si no, la más reciente del producto
                SELECT *
                INTO v_extraccion
                FROM public.app_dat_extraccion_productos
                WHERE id_operacion = v_operacion_id
                  AND id_producto = v_producto_inventtia
                  AND cantidad = COALESCE(v_detail.quantity, 1)
                ORDER BY id DESC
                LIMIT 1;

                IF NOT FOUND THEN
                    SELECT *
                    INTO v_extraccion
                    FROM public.app_dat_extraccion_productos
                    WHERE id_operacion = v_operacion_id
                      AND id_producto = v_producto_inventtia
                    ORDER BY id DESC
                    LIMIT 1;
                END IF;

                IF FOUND THEN
                    -- Último inventario de esa ubicación/variante (mismo criterio que cancelación)
                    SELECT *
                    INTO v_inventario_actual
                    FROM public.app_dat_inventario_productos
                    WHERE id_producto = v_extraccion.id_producto
                      AND id_variante IS NOT DISTINCT FROM v_extraccion.id_variante
                      AND id_opcion_variante IS NOT DISTINCT FROM v_extraccion.id_opcion_variante
                      AND id_ubicacion IS NOT DISTINCT FROM v_extraccion.id_ubicacion
                    ORDER BY created_at DESC, id DESC
                    LIMIT 1;

                    v_presentacion_id := COALESCE(
                        v_extraccion.id_presentacion,
                        v_inventario_actual.id_presentacion
                    );

                    IF v_presentacion_id IS NULL THEN
                        SELECT id INTO v_presentacion_id
                        FROM public.app_dat_producto_presentacion
                        WHERE id_producto = v_producto_inventtia
                        ORDER BY id ASC
                        LIMIT 1;
                    END IF;

                    IF v_presentacion_id IS NOT NULL THEN
                        INSERT INTO public.app_dat_inventario_productos (
                            id_producto,
                            id_variante,
                            id_opcion_variante,
                            id_ubicacion,
                            id_presentacion,
                            cantidad_inicial,
                            cantidad_final,
                            sku_producto,
                            sku_ubicacion,
                            origen_cambio,
                            id_extraccion,
                            created_at
                        ) VALUES (
                            v_extraccion.id_producto,
                            v_extraccion.id_variante,
                            v_extraccion.id_opcion_variante,
                            v_extraccion.id_ubicacion,
                            v_presentacion_id,
                            COALESCE(v_inventario_actual.cantidad_final, 0),
                            COALESCE(v_inventario_actual.cantidad_final, 0)
                                + COALESCE(v_extraccion.cantidad, 0),
                            v_extraccion.sku_producto,
                            v_extraccion.sku_ubicacion,
                            5, -- Cancelación / devolución de línea
                            NULL,
                            now()
                        );
                    END IF;

                    -- Quitar la extracción de la venta
                    DELETE FROM public.app_dat_extraccion_productos
                    WHERE id = v_extraccion.id;

                    -- Recalcular importe de la venta Inventtia
                    SELECT COALESCE(SUM(importe_real), 0)
                    INTO v_nuevo_importe
                    FROM public.app_dat_extraccion_productos
                    WHERE id_operacion = v_operacion_id;

                    UPDATE public.app_dat_operacion_venta
                    SET importe_total = v_nuevo_importe
                    WHERE id_operacion = v_operacion_id;

                    UPDATE public.app_dat_pago_venta
                    SET monto = v_nuevo_importe
                    WHERE id_operacion_venta = v_operacion_id;
                END IF;
            END IF;
        END IF;
    END IF;

    -- --------------------------------------------------------
    -- 3) Eliminar OrderDetail
    -- --------------------------------------------------------
    DELETE FROM carnavalapp."OrderDetails"
    WHERE id = p_detail_id;

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Producto eliminado y stock devuelto',
        'order_id', v_detail.order_id,
        'product_id', v_detail.product_id,
        'quantity', v_detail.quantity,
        'carnaval_stock_antes', v_carnaval_stock_antes,
        'carnaval_stock_despues', v_carnaval_stock_despues,
        'operacion_id', v_operacion_id,
        'es_paqueteria', v_es_paqueteria
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', SQLERRM
        );
END;
$$;

COMMENT ON FUNCTION public.fn_eliminar_order_detail_con_devolucion(bigint) IS
'Elimina un OrderDetail de Carnaval y devuelve stock en Carnaval e Inventtia.';

GRANT EXECUTE ON FUNCTION public.fn_eliminar_order_detail_con_devolucion(bigint)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_eliminar_order_detail_con_devolucion(bigint)
    TO service_role;
