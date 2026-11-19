CREATE OR REPLACE FUNCTION public.fn_cancelar_item_pedido_v2(p_id_item bigint, p_motivo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_item               RECORD;
    v_id_tienda          bigint;
    v_estado_cta         smallint;
    v_com_item           RECORD;
    v_ya_servido         boolean := false;
    v_devuelto           jsonb   := NULL;
    v_movs               jsonb   := '[]'::jsonb;
    v_id_almacen         bigint;
    v_cantidad_base      numeric;
    v_id_ubicacion       bigint;
    v_id_presentacion    bigint;
    v_nombre_presentacion varchar;
    v_factor_base        numeric;
    v_delta_fisico       numeric;
    v_variante           bigint;
    v_opcion             bigint;
    v_actual             numeric;
    v_sku_producto       varchar;
    v_sku_ubicacion      varchar;
BEGIN
    SELECT i.id, i.id_cuenta, i.id_producto, i.id_presentacion, i.cantidad,
           i.origen_stock, i.id_cocina, i.id_comanda_item, i.stock_movido,
           i.inventory_data
      INTO v_item
      FROM public.app_dat_mesa_cuenta_item i
     WHERE i.id = p_id_item;

    IF v_item.id IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El item no existe',
            'error_code', 'ITEM_NOT_FOUND'
        );
    END IF;

    SELECT c.id_tienda, c.estado INTO v_id_tienda, v_estado_cta
      FROM public.app_dat_mesa_cuenta_abierta c
     WHERE c.id = v_item.id_cuenta;

    -- Guard seguro (search_path fijo): la viva no se toca.
    PERFORM public.fn_check_user_has_access_to_tienda_safe(v_id_tienda);

    IF v_estado_cta <> 1 THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    'La cuenta ya no esta abierta',
            'error_code', 'CUENTA_NO_ABIERTA'
        );
    END IF;

    -- â”€â”€ Estado en cocina â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    IF v_item.id_comanda_item IS NOT NULL THEN
        SELECT ci.id, ci.estado, ci.id_comanda
          INTO v_com_item
          FROM public.app_dat_comanda_item ci
         WHERE ci.id = v_item.id_comanda_item;

        -- 4 entregado. 3 listo tambien cuenta como servido: el plato existe.
        v_ya_servido := COALESCE(v_com_item.estado, 0) IN (3, 4);
    ELSIF v_item.origen_stock = 'tanda' THEN
        -- Una tanda se sirve al pedirla: ya salio de la cocina.
        v_ya_servido := true;
    END IF;

    IF v_ya_servido AND (p_motivo IS NULL OR trim(p_motivo) = '') THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    'El plato ya fue servido: hace falta un motivo para registrar la merma',
            'error_code', 'MOTIVO_REQUERIDO',
            'ya_servido', true
        );
    END IF;

    -- â”€â”€ Cancelar la comanda si estaba viva â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    IF v_com_item.id IS NOT NULL AND v_com_item.estado IN (1, 2) THEN
        UPDATE public.app_dat_comanda_item
           SET estado = 5, updated_at = now()
         WHERE id = v_com_item.id;

        -- Si no queda ninguna linea viva, cancelar la cabecera tambien.
        UPDATE public.app_dat_comanda co
           SET estado = 5, cancelled_at = now(), updated_at = now()
         WHERE co.id = v_com_item.id_comanda
           AND NOT EXISTS (
                SELECT 1 FROM public.app_dat_comanda_item ci2
                 WHERE ci2.id_comanda = co.id AND ci2.estado IN (1, 2, 3)
           );
    END IF;

    -- â”€â”€ Devolver stock solo si NO se sirvio â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    IF v_item.stock_movido AND NOT v_ya_servido THEN
        v_id_almacen := NULLIF(v_item.inventory_data->>'id_almacen', '')::bigint;

        -- C5/C7: la linea guarda la presentacion VENDIDA; la receta se consumio
        -- en equivalente BASE. Se convierte en la entrada (misma conversion que
        -- fn_pedir_item_cuenta_v2 / fn_actualizar_cantidad_producto_orden_v2).
        v_cantidad_base := public.fn_cantidad_en_base(v_item.id_presentacion, v_item.cantidad);

        IF v_id_almacen IS NULL THEN
            -- Sin traza del almacen no se adivina: se avisa en vez de devolver
            -- a un almacen equivocado.
            v_devuelto := jsonb_build_object(
                'status', 'warning',
                'message', 'No se pudo determinar el almacen de origen: revisar manualmente'
            );
        ELSIF v_item.origen_stock = 'al_pedido' THEN
            -- Se devuelven los INGREDIENTES a la cocina, a la presentacion base.
            v_devuelto := public.fn_devolver_ingredientes_elaborado_v2(
                p_id_producto_elaborado := v_item.id_producto,
                p_cantidad              := v_cantidad_base,
                p_id_almacen            := v_id_almacen,
                p_origen_cambio         := 4
            );
        ELSE
            -- Se devuelve el SKU propio (barra o porcion de tanda no servida).
            -- `_v2`: EN EQUIVALENTE BASE y a la presentacion BASE del producto.
            v_id_ubicacion := public.fn_ubicacion_destino_devolucion(v_item.id_producto, v_id_almacen);

            IF v_id_ubicacion IS NULL THEN
                v_devuelto := jsonb_build_object(
                    'status',  'warning',
                    'message', 'El almacen no tiene ubicacion donde devolver el producto: revisar manualmente'
                );
            ELSE
                SELECT c.id_presentacion, c.nombre, COALESCE(c.factor_rel, 1)
                  INTO v_id_presentacion, v_nombre_presentacion, v_factor_base
                  FROM public.fn_presentaciones_producto(v_item.id_producto) c
                 ORDER BY c.es_base DESC, c.factor_rel ASC NULLS LAST, c.id_presentacion ASC
                 LIMIT 1;

                IF v_id_presentacion IS NULL OR v_factor_base IS NULL OR v_factor_base <= 0 THEN
                    v_devuelto := jsonb_build_object(
                        'status',  'warning',
                        'message', 'El producto no tiene una presentacion base valida: revisar manualmente'
                    );
                ELSE
                    v_delta_fisico := v_cantidad_base / v_factor_base;

                    SELECT DISTINCT ON (COALESCE(ip.id_variante, 0), COALESCE(ip.id_opcion_variante, 0))
                           ip.id_variante,
                           ip.id_opcion_variante,
                           COALESCE(ip.cantidad_final, 0),
                           ip.sku_producto,
                           ip.sku_ubicacion
                      INTO v_variante, v_opcion, v_actual, v_sku_producto, v_sku_ubicacion
                      FROM public.app_dat_inventario_productos ip
                     WHERE ip.id_producto     = v_item.id_producto
                       AND ip.id_ubicacion    = v_id_ubicacion
                       AND ip.id_presentacion = v_id_presentacion
                     ORDER BY COALESCE(ip.id_variante, 0), COALESCE(ip.id_opcion_variante, 0), ip.id DESC
                     LIMIT 1;

                    v_actual := COALESCE(v_actual, 0);

                    IF v_sku_producto IS NULL THEN
                        SELECT p.sku INTO v_sku_producto FROM public.app_dat_producto p
                         WHERE p.id = v_item.id_producto;
                    END IF;
                    IF v_sku_ubicacion IS NULL THEN
                        SELECT la.sku_codigo INTO v_sku_ubicacion FROM public.app_dat_layout_almacen la
                         WHERE la.id = v_id_ubicacion;
                    END IF;

                    INSERT INTO public.app_dat_inventario_productos (
                        id_producto, id_variante, id_opcion_variante,
                        id_ubicacion, id_presentacion,
                        cantidad_inicial, cantidad_final,
                        sku_producto, sku_ubicacion,
                        origen_cambio, created_at
                    ) VALUES (
                        v_item.id_producto, v_variante, v_opcion,
                        v_id_ubicacion, v_id_presentacion,
                        v_actual, v_actual + v_delta_fisico,
                        v_sku_producto, v_sku_ubicacion,
                        4, now()
                    );

                    v_movs := v_movs || jsonb_build_object(
                        'id_ubicacion',    v_id_ubicacion,
                        'id_presentacion', v_id_presentacion,
                        'presentacion',    v_nombre_presentacion,
                        'factor_rel',      v_factor_base,
                        'devuelto',        v_delta_fisico,
                        'devuelto_base',   v_cantidad_base
                    );

                    v_devuelto := jsonb_build_object(
                        'status',      'success',
                        'presentacion','base',
                        'movimientos', v_movs
                    );
                END IF;
            END IF;
        END IF;
    END IF;

    -- â”€â”€ Quitar la linea de la cuenta â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    DELETE FROM public.app_dat_mesa_cuenta_item WHERE id = p_id_item;

    UPDATE public.app_dat_mesa_cuenta_abierta SET updated_at = now()
     WHERE id = v_item.id_cuenta;

    RETURN jsonb_build_object(
        'status',            'success',
        'id_item',           p_id_item,
        'ya_servido',        v_ya_servido,
        'stock_devuelto',    (v_item.stock_movido AND NOT v_ya_servido),
        'es_merma',          v_ya_servido,
        'motivo',            p_motivo,
        'comanda_cancelada', (v_com_item.id IS NOT NULL AND v_com_item.estado IN (1, 2)),
        'devolucion',        v_devuelto,
        'message',           CASE
            WHEN v_ya_servido
              THEN 'Item retirado de la cuenta y registrado como merma'
            WHEN v_item.stock_movido
              THEN 'Item cancelado y stock devuelto'
            ELSE 'Item cancelado'
        END
    );
END;
$function$

