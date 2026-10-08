-- Edición transaccional v2 de órdenes pendientes.
-- No reemplaza las RPC legacy utilizadas por versiones ya desplegadas.

CREATE OR REPLACE FUNCTION public.fn_editar_orden_pendiente_v2(
    p_id_operacion bigint,
    p_operaciones jsonb,
    p_uuid_usuario uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_estado integer;
    v_id_tienda bigint;
    v_op jsonb;
    v_result jsonb;
    v_payload jsonb;
    v_payment_snapshot jsonb;
    v_payment_ids bigint[];
    v_total_bruto numeric := 0;
    v_total_final numeric := 0;
    v_descuento_id bigint;
    v_tipo_descuento integer;
    v_valor_descuento numeric;
    v_monto_descuento numeric := 0;
    v_total_equivalente_anterior numeric := 0;
    v_total_asignado numeric := 0;
    v_total_pagos numeric := 0;
    v_pago record;
    v_equivalente_anterior numeric;
    v_equivalente_nuevo numeric;
    v_monto_nuevo numeric;
    v_importe_sin_descuento numeric;
    v_id_ajuste bigint;
    v_diferencia numeric;
BEGIN
    IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_uuid_usuario THEN
        RAISE EXCEPTION 'Usuario no autorizado';
    END IF;

    IF jsonb_typeof(p_operaciones) IS DISTINCT FROM 'array' OR jsonb_array_length(p_operaciones) = 0 THEN
        RAISE EXCEPTION 'Debe enviar al menos una operación';
    END IF;

    SELECT o.id_tienda
      INTO v_id_tienda
      FROM public.app_dat_operaciones o
     WHERE o.id = p_id_operacion
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Orden no encontrada';
    END IF;

    PERFORM public.check_user_has_access_to_tienda(v_id_tienda);

    SELECT eo.estado
      INTO v_estado
      FROM public.app_dat_estado_operacion eo
     WHERE eo.id_operacion = p_id_operacion
     ORDER BY eo.created_at DESC, eo.id DESC
     LIMIT 1;

    IF v_estado IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'Solo se pueden editar órdenes en estado Pendiente';
    END IF;

    PERFORM 1
      FROM public.app_dat_pago_venta
     WHERE id_operacion_venta = p_id_operacion
     FOR UPDATE;

    SELECT COALESCE(jsonb_agg(to_jsonb(p) ORDER BY p.id), '[]'::jsonb),
           COALESCE(array_agg(p.id ORDER BY p.id), ARRAY[]::bigint[])
      INTO v_payment_snapshot, v_payment_ids
      FROM public.app_dat_pago_venta p
     WHERE p.id_operacion_venta = p_id_operacion;

    FOR v_pago IN
        SELECT *
          FROM jsonb_to_recordset(v_payment_snapshot) AS p(
              id bigint,
              monto numeric,
              moneda text,
              tasa_usd numeric,
              monto_cup_equivalente numeric
          )
    LOOP
        IF upper(COALESCE(NULLIF(trim(v_pago.moneda), ''), 'CUP')) = 'USD' THEN
            IF COALESCE(v_pago.tasa_usd, 0) <= 0 THEN
                RAISE EXCEPTION 'El pago USD % no tiene una tasa histórica válida', v_pago.id;
            END IF;
            v_equivalente_anterior := COALESCE(
                NULLIF(v_pago.monto_cup_equivalente, 0),
                COALESCE(v_pago.monto, 0) * v_pago.tasa_usd
            );
        ELSE
            v_equivalente_anterior := COALESCE(v_pago.monto, 0);
        END IF;
        v_total_equivalente_anterior := v_total_equivalente_anterior + v_equivalente_anterior;
    END LOOP;

    FOR v_op IN SELECT value FROM jsonb_array_elements(p_operaciones)
    LOOP
        CASE v_op->>'op'
            WHEN 'update' THEN
                v_result := public.fn_actualizar_cantidad_producto_orden(
                    (v_op->>'id_extraccion')::bigint,
                    (v_op->>'nueva_cantidad')::numeric,
                    p_uuid_usuario
                );
            WHEN 'remove' THEN
                v_result := public.fn_eliminar_producto_orden(
                    (v_op->>'id_extraccion')::bigint,
                    p_uuid_usuario
                );
            WHEN 'add' THEN
                v_payload := COALESCE(v_op->'payload', '{}'::jsonb);
                IF (v_payload->>'id_medio_pago')::integer = 999 THEN
                    v_payload := jsonb_set(v_payload, '{id_medio_pago}', '1'::jsonb);
                END IF;
                v_result := public.fn_agregar_producto_orden_pendiente(
                    p_id_operacion,
                    v_payload,
                    p_uuid_usuario
                );
            ELSE
                RAISE EXCEPTION 'Operación de edición no soportada: %', COALESCE(v_op->>'op', 'null');
        END CASE;

        IF COALESCE(v_result->>'status', 'error') <> 'success' THEN
            RAISE EXCEPTION '%', COALESCE(v_result->>'message', 'No se pudo editar la orden');
        END IF;
    END LOOP;

    SELECT COALESCE(SUM(e.cantidad * e.precio_unitario), 0)
      INTO v_total_bruto
      FROM public.app_dat_extraccion_productos e
     WHERE e.id_operacion = p_id_operacion;

    SELECT d.id, d.tipo_descuento, d.valor_descuento
      INTO v_descuento_id, v_tipo_descuento, v_valor_descuento
      FROM public.app_dat_descuentos_vendedor d
     WHERE d.id_operacion = p_id_operacion
     ORDER BY d.created_at DESC, d.id DESC
     LIMIT 1
     FOR UPDATE;

    IF v_descuento_id IS NOT NULL THEN
        IF v_tipo_descuento = 1 THEN
            v_monto_descuento := LEAST(
                v_total_bruto,
                GREATEST(0, v_total_bruto * COALESCE(v_valor_descuento, 0) / 100)
            );
        ELSE
            v_monto_descuento := LEAST(
                v_total_bruto,
                GREATEST(0, COALESCE(v_valor_descuento, 0))
            );
        END IF;

        UPDATE public.app_dat_descuentos_vendedor
           SET monto_real = v_total_bruto,
               monto_descontado = v_monto_descuento
         WHERE id = v_descuento_id;
    END IF;

    v_total_final := GREATEST(0, v_total_bruto - v_monto_descuento);

    UPDATE public.app_dat_operacion_venta
       SET importe_total = v_total_bruto,
           precio_con_descuento_total = CASE WHEN v_descuento_id IS NULL THEN NULL ELSE v_total_final END
     WHERE id_operacion = p_id_operacion;

    -- Las RPC legacy pueden crear pagos al agregar productos. Se restaura el
    -- conjunto original y se redistribuye una sola vez usando CUP equivalente.
    DELETE FROM public.app_dat_pago_venta
     WHERE id_operacion_venta = p_id_operacion
       AND NOT (id = ANY(v_payment_ids));

    IF cardinality(v_payment_ids) > 0 THEN
        IF v_total_equivalente_anterior <= 0 AND v_total_final > 0 THEN
            RAISE EXCEPTION 'Los pagos existentes no tienen un total válido para redistribuir';
        END IF;

        FOR v_pago IN
            SELECT *
              FROM jsonb_to_recordset(v_payment_snapshot) AS p(
                  id bigint,
                  monto numeric,
                  moneda text,
                  tasa_usd numeric,
                  monto_cup_equivalente numeric
              )
             ORDER BY COALESCE(p.monto_cup_equivalente, p.monto, 0) DESC, p.id
        LOOP
            IF upper(COALESCE(NULLIF(trim(v_pago.moneda), ''), 'CUP')) = 'USD' THEN
                v_equivalente_anterior := COALESCE(
                    NULLIF(v_pago.monto_cup_equivalente, 0),
                    COALESCE(v_pago.monto, 0) * v_pago.tasa_usd
                );
            ELSE
                v_equivalente_anterior := COALESCE(v_pago.monto, 0);
            END IF;

            v_equivalente_nuevo := CASE
                WHEN v_total_equivalente_anterior > 0
                    THEN round(v_total_final * v_equivalente_anterior / v_total_equivalente_anterior, 2)
                ELSE 0
            END;
            v_importe_sin_descuento := CASE
                WHEN v_total_final > 0 THEN round(v_total_bruto * v_equivalente_nuevo / v_total_final, 2)
                ELSE 0
            END;

            IF upper(COALESCE(NULLIF(trim(v_pago.moneda), ''), 'CUP')) = 'USD' THEN
                v_monto_nuevo := round(v_equivalente_nuevo / v_pago.tasa_usd, 2);
            ELSE
                v_monto_nuevo := v_equivalente_nuevo;
            END IF;

            UPDATE public.app_dat_pago_venta
               SET monto = v_monto_nuevo,
                   moneda = upper(COALESCE(NULLIF(trim(v_pago.moneda), ''), 'CUP')),
                   tasa_usd = CASE
                       WHEN upper(COALESCE(NULLIF(trim(v_pago.moneda), ''), 'CUP')) = 'USD'
                           THEN v_pago.tasa_usd
                       ELSE NULL
                   END,
                   monto_cup_equivalente = v_equivalente_nuevo,
                   importe_sin_descuento = v_importe_sin_descuento
             WHERE id = v_pago.id;

            v_total_asignado := v_total_asignado + v_equivalente_nuevo;
            IF v_id_ajuste IS NULL THEN v_id_ajuste := v_pago.id; END IF;
        END LOOP;

        v_diferencia := round(v_total_final - v_total_asignado, 2);
        IF v_diferencia <> 0 AND v_id_ajuste IS NOT NULL THEN
            UPDATE public.app_dat_pago_venta
               SET monto_cup_equivalente = monto_cup_equivalente + v_diferencia,
                   monto = CASE
                       WHEN moneda = 'USD' THEN round((monto_cup_equivalente + v_diferencia) / tasa_usd, 2)
                       ELSE monto + v_diferencia
                   END
             WHERE id = v_id_ajuste;
        END IF;
    END IF;

    SELECT COALESCE(SUM(
               CASE
                   WHEN upper(COALESCE(NULLIF(trim(moneda), ''), 'CUP')) = 'USD'
                       THEN COALESCE(monto_cup_equivalente, monto * tasa_usd)
                   ELSE monto
               END
           ), 0)
      INTO v_total_pagos
      FROM public.app_dat_pago_venta
     WHERE id_operacion_venta = p_id_operacion;

    IF cardinality(v_payment_ids) > 0 AND abs(v_total_pagos - v_total_final) > 0.01 THEN
        RAISE EXCEPTION 'Los pagos (%) no coinciden con el total final (%)', v_total_pagos, v_total_final;
    END IF;

    RETURN jsonb_build_object(
        'status', 'success',
        'total_bruto', v_total_bruto,
        'monto_descuento', v_monto_descuento,
        'total_final', v_total_final,
        'total_pagos_cup', v_total_pagos,
        'operaciones_aplicadas', jsonb_array_length(p_operaciones)
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'status', 'error',
        'message', SQLERRM,
        'sqlstate', SQLSTATE
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_editar_orden_pendiente_v2(bigint, jsonb, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_editar_orden_pendiente_v2(bigint, jsonb, uuid) TO authenticated;
