CREATE OR REPLACE FUNCTION public.fn_pedir_item_cuenta_offline(p_client_uuid uuid, p_id_cuenta bigint, p_id_producto bigint, p_cantidad numeric, p_precio_unitario numeric, p_id_variante bigint DEFAULT NULL::bigint, p_id_opcion_variante bigint DEFAULT NULL::bigint, p_id_presentacion bigint DEFAULT NULL::bigint, p_id_ubicacion bigint DEFAULT NULL::bigint, p_precio_base numeric DEFAULT NULL::numeric, p_id_metodo_pago bigint DEFAULT NULL::bigint, p_promotion_data jsonb DEFAULT NULL::jsonb, p_inventory_data jsonb DEFAULT NULL::jsonb, p_notas text DEFAULT NULL::text, p_sku_producto text DEFAULT NULL::text, p_sku_ubicacion text DEFAULT NULL::text, p_uuid_vendedor uuid DEFAULT NULL::uuid, p_forzar_sin_stock boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_existing bigint;
    v_res      jsonb;
    v_id_item  bigint;
BEGIN
    IF p_client_uuid IS NULL THEN
        RETURN jsonb_build_object('status','error',
            'message','Falta el client_uuid: sin el no se puede garantizar que el pedido no se duplique al reintentar',
            'error_code','CLIENT_UUID_REQUERIDO');
    END IF;

    SELECT id_operacion INTO v_existing
      FROM app_dat_operacion_offline_idempotencia
     WHERE client_uuid = p_client_uuid AND tipo = 'pedir_item';

    IF v_existing IS NOT NULL THEN
        RETURN (
            SELECT jsonb_build_object(
                     'status','success','idempotent',true,
                     'id_item',i.id,'id_cuenta',i.id_cuenta,
                     'origen_stock',i.origen_stock,'id_cocina',i.id_cocina,
                     'cocina',ck.denominacion,'stock_movido',i.stock_movido,
                     'id_comanda_item',i.id_comanda_item,'id_comanda',ci.id_comanda,
                     'numero_comanda',co.numero,'estado_servicio',i.estado_servicio,
                     'message','Este pedido ya se habia registrado')
              FROM app_dat_mesa_cuenta_item i
              LEFT JOIN app_dat_cocina ck ON ck.id = i.id_cocina
              LEFT JOIN app_dat_comanda_item ci ON ci.id = i.id_comanda_item
              LEFT JOIN app_dat_comanda co ON co.id = ci.id_comanda
             WHERE i.id = v_existing
        );
    END IF;

    v_res := fn_pedir_item_cuenta(
        p_id_cuenta          := p_id_cuenta,
        p_id_producto        := p_id_producto,
        p_cantidad           := p_cantidad,
        p_precio_unitario    := p_precio_unitario,
        p_id_variante        := p_id_variante,
        p_id_opcion_variante := p_id_opcion_variante,
        p_id_presentacion    := p_id_presentacion,
        p_id_ubicacion       := p_id_ubicacion,
        p_precio_base        := p_precio_base,
        p_id_metodo_pago     := p_id_metodo_pago,
        p_promotion_data     := p_promotion_data,
        p_inventory_data     := p_inventory_data,
        p_notas              := p_notas,
        p_sku_producto       := p_sku_producto,
        p_sku_ubicacion      := p_sku_ubicacion,
        p_uuid_vendedor      := p_uuid_vendedor,
        p_forzar_sin_stock   := p_forzar_sin_stock
    );

    IF (v_res->>'status') = 'success' THEN
        v_id_item := (v_res->>'id_item')::bigint;
        INSERT INTO app_dat_operacion_offline_idempotencia
            (client_uuid, id_operacion, tipo, uuid_usuario)
        VALUES (p_client_uuid, v_id_item, 'pedir_item', COALESCE(p_uuid_vendedor, auth.uid()))
        ON CONFLICT (client_uuid) DO NOTHING;

        v_res := v_res || jsonb_build_object('idempotent', false);
    END IF;

    RETURN v_res;
END;
$function$

