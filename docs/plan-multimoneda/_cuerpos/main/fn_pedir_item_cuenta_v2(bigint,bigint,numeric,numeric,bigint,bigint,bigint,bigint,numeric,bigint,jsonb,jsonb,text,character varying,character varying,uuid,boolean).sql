CREATE OR REPLACE FUNCTION public.fn_pedir_item_cuenta_v2(p_id_cuenta bigint, p_id_producto bigint, p_cantidad numeric, p_precio_unitario numeric, p_id_variante bigint DEFAULT NULL::bigint, p_id_opcion_variante bigint DEFAULT NULL::bigint, p_id_presentacion bigint DEFAULT NULL::bigint, p_id_ubicacion bigint DEFAULT NULL::bigint, p_precio_base numeric DEFAULT NULL::numeric, p_id_metodo_pago bigint DEFAULT NULL::bigint, p_promotion_data jsonb DEFAULT NULL::jsonb, p_inventory_data jsonb DEFAULT NULL::jsonb, p_notas text DEFAULT NULL::text, p_sku_producto character varying DEFAULT NULL::character varying, p_sku_ubicacion character varying DEFAULT NULL::character varying, p_uuid_vendedor uuid DEFAULT NULL::uuid, p_forzar_sin_stock boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_cuenta         RECORD;
    v_ruta           jsonb;
    v_origen         text;
    v_origen_stock   text;
    v_id_cocina      bigint;
    v_descuento      jsonb;
    v_stock_movido   boolean := false;
    v_aviso_stock    jsonb   := NULL;
    v_id_item        bigint;
    v_comanda        jsonb   := NULL;
    v_id_com_item    bigint;
    v_estado_serv    smallint := NULL;
    v_cantidad_base  numeric;
BEGIN
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La cantidad debe ser mayor que cero',
            'error_code', 'INVALID_QUANTITY'
        );
    END IF;

    -- â”€â”€ 1. Cuenta abierta â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    SELECT c.id, c.id_tienda, c.id_tpv, c.id_mesa, c.estado
      INTO v_cuenta
      FROM public.app_dat_mesa_cuenta_abierta c
     WHERE c.id = p_id_cuenta;

    IF v_cuenta.id IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La cuenta no existe',
            'error_code', 'CUENTA_NOT_FOUND'
        );
    END IF;

    -- Guard seguro (search_path fijo). La viva no se toca.
    PERFORM public.fn_check_user_has_access_to_tienda_safe(v_cuenta.id_tienda);

    IF v_cuenta.estado <> 1 THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    'La cuenta no esta abierta',
            'error_code', 'CUENTA_NO_ABIERTA',
            'estado',     v_cuenta.estado
        );
    END IF;

    -- Sin TPV no se puede resolver el origen: el enrutamiento depende de a que
    -- cocinas esta ligado ese punto de venta.
    IF v_cuenta.id_tpv IS NULL THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    'La cuenta no tiene TPV asociado: no se puede enrutar el pedido',
            'error_code', 'CUENTA_SIN_TPV'
        );
    END IF;

    -- â”€â”€ 2. Clasificar (y validar enrutamiento) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    v_ruta := public.fn_resolver_origen_venta(p_id_producto, v_cuenta.id_tpv);

    IF (v_ruta->>'status') <> 'success' THEN
        -- COCINA_NO_LIGADA / COCINA_INACTIVA / SIN_RECETA llegan aqui. Se corta:
        -- no se agrega a la nota algo que este TPV no puede servir.
        RETURN v_ruta;
    END IF;

    v_origen    := v_ruta->>'origen';
    v_id_cocina := NULLIF(v_ruta->>'id_cocina', '')::bigint;

    -- Traducir el origen tecnico al vocabulario del plan (2.1).
    v_origen_stock := CASE v_origen
        WHEN 'barra'            THEN 'tpv'
        WHEN 'cocina_por_tanda' THEN 'tanda'
        WHEN 'cocina_al_pedido' THEN 'al_pedido'
        WHEN 'servicio'         THEN 'servicio'
        ELSE 'tpv'
    END;

    -- â”€â”€ 3. Mover inventario AHORA (esto es "pedir != cobrar") â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    -- p_ya_descontado_sku := false porque aqui NADIE descontÃ³ antes: no hay
    -- INSERT de venta previo como en fn_registrar_venta.
    --
    -- FASE 2 / C5: `p_cantidad` llega en la PRESENTACION VENDIDA (1 Caja) y el
    -- inventario se mueve por equivalente BASE (24). La conversion se hace en la
    -- entrada, para las DOS ramas: la cadena `_v2` (receta y SKU) consume base.
    v_cantidad_base := public.fn_cantidad_en_base(p_id_presentacion, p_cantidad);

    v_descuento := public.fn_descontar_venta_enrutada_v2(
        p_id_producto       := p_id_producto,
        p_cantidad          := v_cantidad_base,
        p_id_tpv            := v_cuenta.id_tpv,
        p_id_extraccion     := NULL,
        p_origen_cambio     := 4,
        p_ya_descontado_sku := false
    );

    IF (v_descuento->>'status') <> 'success' THEN
        IF NOT p_forzar_sin_stock THEN
            RETURN v_descuento;
        END IF;

        -- Modo permisivo: se deja constancia y se sigue sin mover stock.
        v_aviso_stock := v_descuento;
        v_stock_movido := false;
    ELSE
        v_stock_movido := (v_descuento->>'descontado') = 'true';
    END IF;

    -- â”€â”€ 4. Agregar la linea a la cuenta (delegando en la funcion existente) â”€â”€
    -- La LINEA guarda la cantidad en la presentacion vendida: la app y el
    -- importe no cambian.
    v_id_item := public.fn_agregar_item_cuenta_mesa(
        p_id_cuenta          := p_id_cuenta,
        p_id_producto        := p_id_producto,
        p_cantidad           := p_cantidad,
        p_precio_unitario    := p_precio_unitario,
        p_id_variante        := p_id_variante,
        p_id_opcion_variante := p_id_opcion_variante,
        p_id_presentacion    := p_id_presentacion,
        p_id_ubicacion       := COALESCE(
                                    p_id_ubicacion,
                                    NULLIF(v_descuento #>> '{movimientos,0,id_ubicacion}', '')::bigint
                                ),
        p_precio_base        := p_precio_base,
        p_id_metodo_pago     := p_id_metodo_pago,
        p_promotion_data     := p_promotion_data,
        p_inventory_data     := COALESCE(p_inventory_data, v_descuento),
        p_notas              := p_notas,
        p_sku_producto       := p_sku_producto,
        p_sku_ubicacion      := p_sku_ubicacion
    );

    -- â”€â”€ 5. Disparar comanda si el plato va a cocina â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    -- Un producto de barra o un servicio no genera comanda: el plan lo dice
    -- explicito ("Cocina solo ve comandas de su estacion, no bebidas del bar").
    --
    -- Una TANDA tampoco genera comanda de coccion: la porcion ya esta hecha, se
    -- sirve. El plan lo marca como "sin comanda de coccion (pase opcional)".
    --
    -- P1 documentado (no se cambia aqui): la comanda sigue llevando `p_cantidad`
    -- en la presentacion vendida.
    IF v_id_cocina IS NOT NULL AND v_origen = 'cocina_al_pedido' THEN
        v_comanda := public.fn_disparar_comanda(
            p_id_cocina        := v_id_cocina,
            p_id_producto      := p_id_producto,
            p_cantidad         := p_cantidad,
            p_id_cuenta        := p_id_cuenta,
            p_id_item_cuenta   := v_id_item,
            p_id_tpv           := v_cuenta.id_tpv,
            p_uuid_vendedor    := p_uuid_vendedor,
            p_notas            := p_notas,
            p_movimiento_stock := v_descuento
        );

        IF (v_comanda->>'status') <> 'success' THEN
            -- Falla el disparo -> se aborta todo. Mejor que el cliente pida de
            -- nuevo que tener stock descontado sin comanda en la cocina.
            RAISE EXCEPTION 'No se pudo enviar a la cocina: %',
                COALESCE(v_comanda->>'message', 'error desconocido')
                USING ERRCODE = 'P0001';
        END IF;

        v_id_com_item := (v_comanda->>'id_comanda_item')::bigint;
        v_estado_serv := 1;   -- pendiente en cocina
    ELSIF v_origen = 'cocina_por_tanda' THEN
        -- Servido de inmediato desde la cocina: no espera preparacion.
        v_estado_serv := 4;   -- entregado
    END IF;

    -- â”€â”€ 6. Marcar la linea con lo que paso â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    UPDATE public.app_dat_mesa_cuenta_item
       SET origen_stock    = v_origen_stock,
           id_cocina       = v_id_cocina,
           id_comanda_item = COALESCE(v_id_com_item, id_comanda_item),
           estado_servicio = COALESCE(v_estado_serv, estado_servicio),
           stock_movido    = (stock_movido OR v_stock_movido),
           updated_at      = now()
     WHERE id = v_id_item;

    RETURN jsonb_build_object(
        'status',          'success',
        'id_item',         v_id_item,
        'id_cuenta',       p_id_cuenta,
        'origen',          v_origen,
        'origen_stock',    v_origen_stock,
        'id_cocina',       v_id_cocina,
        'cocina',          v_ruta->'cocina',
        'stock_movido',    v_stock_movido,
        'id_comanda',      v_comanda->'id_comanda',
        'id_comanda_item', v_id_com_item,
        'numero_comanda',  v_comanda->'numero',
        'estado_servicio', v_estado_serv,
        'aviso_stock',     v_aviso_stock,
        'descuento',       v_descuento,
        'cantidad_base',   v_cantidad_base,
        'message',         CASE
            WHEN v_comanda IS NOT NULL
              THEN 'Enviado a ' || COALESCE(v_ruta->>'cocina', 'cocina')
            WHEN v_origen = 'cocina_por_tanda'
              THEN 'Servido de ' || COALESCE(v_ruta->>'cocina', 'cocina')
            ELSE 'Agregado a la cuenta'
        END
    );
END;
$function$

