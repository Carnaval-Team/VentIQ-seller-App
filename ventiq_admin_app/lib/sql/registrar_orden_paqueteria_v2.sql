-- ============================================================================
-- fn_registrar_orden_paqueteria_v2
--   Versión 2 de la RPC: acepta un parámetro `extra` (decimal) en el payload
--   para soportar cantidades fraccionarias (p. ej. 10.2 libras => cantidad=10,
--   extra=0.2). El `extra` se persiste en `OrderDetails.extra` (nueva columna)
--   y, al final, se suma a la cantidad en `app_dat_extraccion_productos` para
--   reflejar la cantidad real (cantidad + extra) en el inventario.
--
-- Cambios respecto a v1:
--   * Acepta `extra NUMERIC` en el payload (default 0).
--   * Inserta `extra` en carnavalapp."OrderDetails".
--   * Tras crear la operación Inventtia, actualiza
--     app_dat_extraccion_productos.cantidad = cantidad + extra
--     where id_operacion = v_id_operacion AND id_producto = v_id_producto_inventtia
--           AND id_ubicacion = v_id_ubicacion (cuando v_id_ubicacion no es NULL).
-- ============================================================================

-- Asegurar columna `extra` en carnavalapp."OrderDetails"
ALTER TABLE carnavalapp."OrderDetails"
    ADD COLUMN IF NOT EXISTS extra NUMERIC NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION public.fn_registrar_orden_paqueteria_v2(p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_id_producto_inventtia BIGINT;
    v_id_producto_carnaval  BIGINT;
    v_id_ubicacion          BIGINT;
    v_cantidad              INT;
    v_extra                 NUMERIC;
    v_precio_unitario       NUMERIC;
    v_precio_descuento      NUMERIC;
    v_id_proveedor_carnaval BIGINT;
    v_id_tienda             BIGINT;
    v_metodo_pago           TEXT;
    v_uuid_vendedor         UUID;

    v_paquete               JSONB;
    v_remitente             JSONB;
    v_destinatario          JSONB;

    v_producto_nombre       TEXT;

    v_producto_descripcion  TEXT;
    v_producto_image        TEXT;
    v_categoria_id          BIGINT;

    v_dest_telefono         TEXT;
    v_dest_email            TEXT;
    v_dest_nombre           TEXT;
    v_dest_direccion_full   TEXT;
    v_remit_direccion_full  TEXT;
    v_user_id_carnaval      BIGINT;
    v_user_id_seller        UUID;
    v_tpv_id                BIGINT;

    v_order_id              BIGINT;
    v_id_operacion          BIGINT;

    v_total                 NUMERIC;
    v_cantidad_total        NUMERIC;
    v_peso_text             TEXT;

    v_orderdetail_id        BIGINT;
    v_paqueteria_ordenes_id BIGINT;
    v_step                  TEXT;
BEGIN
    v_step := 'init';

    -- ---------- 1. Extraer y validar payload ----------
    IF p_payload IS NULL THEN
        RETURN jsonb_build_object('status','error','message','payload vacío');
    END IF;
    v_step := 'payload_parsed';

    v_id_producto_inventtia := (p_payload->>'id_producto_inventtia')::BIGINT;
    v_cantidad              := COALESCE((p_payload->>'cantidad')::INT, 1);
    v_extra                 := COALESCE(NULLIF(p_payload->>'extra','')::NUMERIC, 0);
    v_precio_unitario       := (p_payload->>'precio_unitario')::NUMERIC;
    v_precio_descuento      := NULLIF(p_payload->>'precio_descuento','')::NUMERIC;
    v_id_proveedor_carnaval := 38;
    v_id_tienda             := (p_payload->>'id_tienda')::BIGINT;
    v_metodo_pago           := COALESCE(p_payload->>'metodo_pago','Efectivo');
    v_uuid_vendedor         := NULLIF(p_payload->>'uuid_vendedor','')::UUID;

    v_paquete      := p_payload->'paquete';
    v_remitente    := p_payload->'remitente';
    v_destinatario := p_payload->'destinatario';

    IF v_id_producto_inventtia IS NULL OR v_precio_unitario IS NULL
       OR v_id_proveedor_carnaval IS NULL OR v_id_tienda IS NULL THEN
        RETURN jsonb_build_object('status','error',
            'message','Faltan campos obligatorios en el payload (id_producto_inventtia, precio_unitario, id_proveedor_carnaval, id_tienda)');
    END IF;

    IF v_destinatario IS NULL OR v_destinatario->>'nombre' IS NULL THEN
        RETURN jsonb_build_object('status','error',
            'message','Datos de destinatario incompletos');
    END IF;

    v_dest_telefono := NULLIF(trim(v_destinatario->>'telefono'),'');
    v_dest_email    := NULLIF(trim(v_destinatario->>'email'),'');
    v_dest_nombre   := COALESCE(v_destinatario->>'nombre','Destinatario');

    v_dest_direccion_full := concat_ws(', ',
        NULLIF(trim(COALESCE(v_destinatario->>'direccion','')),''),
        NULLIF(trim(COALESCE(v_destinatario->>'municipio_nombre','')),''),
        NULLIF(trim(COALESCE(v_destinatario->>'provincia_nombre','')),'')
    );

    v_remit_direccion_full := concat_ws(', ',
        NULLIF(trim(COALESCE(v_remitente->>'direccion','')),''),
        NULLIF(trim(COALESCE(v_remitente->>'municipio_nombre','')),''),
        NULLIF(trim(COALESCE(v_remitente->>'provincia_nombre','')),'')
    );

    -- Cantidad real (entero + decimal) para totales monetarios
    v_cantidad_total := v_cantidad + v_extra;
    v_total := v_cantidad_total * COALESCE(v_precio_descuento, v_precio_unitario);

    v_peso_text := NULLIF(trim(COALESCE(v_paquete->>'peso','')),'');

    v_step := 'resolving_product';

    -- ---------- 2. Resolver producto Carnaval ----------
    SELECT rpc.id_producto_carnaval, rpc.id_ubicacion
      INTO v_id_producto_carnaval, v_id_ubicacion
      FROM public.relation_products_carnaval rpc
     WHERE rpc.id_producto = v_id_producto_inventtia
     LIMIT 1;

    IF v_id_producto_carnaval IS NULL THEN
        SELECT denominacion, descripcion, imagen
          INTO v_producto_nombre, v_producto_descripcion, v_producto_image
          FROM public.app_dat_producto
         WHERE id = v_id_producto_inventtia;

        IF v_producto_nombre IS NULL THEN
            RETURN jsonb_build_object('status','error',
                'message','Producto Inventtia no existe (id='||v_id_producto_inventtia||')');
        END IF;

        SELECT id_ubicacion INTO v_id_ubicacion
          FROM public.app_dat_inventario_productos
         WHERE id_producto = v_id_producto_inventtia
         ORDER BY id DESC
         LIMIT 1;

        SELECT id INTO v_categoria_id
          FROM carnavalapp."Categorias"
         WHERE name ILIKE '%paquet%'
         LIMIT 1;

        IF v_categoria_id IS NULL THEN
            SELECT COALESCE(MAX(id),0)+1 INTO v_categoria_id FROM carnavalapp."Categorias";
            INSERT INTO carnavalapp."Categorias" (id, name, descripcion, es_alimento)
            VALUES (v_categoria_id, 'Paquetería', 'Envíos y paquetería', false);
        END IF;

        INSERT INTO carnavalapp."Productos" (
            name, description, price, stock, category_id,
            image, precio_descuento, status, proveedor
        ) VALUES (
            v_producto_nombre,
            COALESCE(v_producto_descripcion,'Servicio de paquetería'),
            v_precio_unitario,
            999999,
            v_categoria_id,
            COALESCE(v_producto_image,
                'https://kvgbekelvmkbxydqvtuy.supabase.co/storage/v1/object/public/productos/imagenes/imagen_articulo_por_defecto.jpg'),
            COALESCE(v_precio_descuento,0),
            true,
            v_id_proveedor_carnaval
        )
        RETURNING id INTO v_id_producto_carnaval;

        INSERT INTO public.relation_products_carnaval
            (id_producto, id_producto_carnaval, id_ubicacion)
        VALUES
            (v_id_producto_inventtia, v_id_producto_carnaval, v_id_ubicacion);

        UPDATE public.app_dat_producto
           SET id_vendedor_app = v_id_producto_carnaval
         WHERE id = v_id_producto_inventtia
           AND id_vendedor_app IS NULL;
    END IF;
    v_step := 'product_resolved';


    IF v_id_producto_carnaval IS not NULL THEN
        UPDATE carnavalapp."Productos" set stock = 9999 , status = true where id = v_id_producto_carnaval;
    END IF;

    -- ---------- 3. Crear usuario destinatario en Carnaval ----------
    v_user_id_carnaval := NULL;
    v_user_id_seller   := v_uuid_vendedor;

    v_step := 'inserting_usuario';
    INSERT INTO carnavalapp."Usuarios" (
        email, name, telefono, rol, email_confirmacion, tienda
    ) VALUES (
        COALESCE(v_dest_email, 'paqueteria.' || md5(random()::text) || '@noemail.com'),
        v_dest_nombre,
        v_dest_telefono,
        'Cliente',
        false,
        v_id_proveedor_carnaval
    )
    RETURNING id INTO v_user_id_carnaval;
    v_step := 'usuario_created';

    -- ---------- 4. Crear Orden en Carnaval ----------
    v_step := 'inserting_order';
    INSERT INTO carnavalapp."Orders" (
        user_id,
        total,
        status,
        metodo_entrega,
        direccion,
        metodo_pago,
        descrpcion,
        notas,
        destinatario,
        telefono_destinatario,
        proveedor_id,
        proveedores,
        moneda,
        paqueteria,
        "totalUsd",
        "totalEuro",
        costo_envio,
        "envioUsd",
        "EnvioEuro",
        tax,
        direccion_recogida,
        peso,
        es_alimento,
        cajero,
        created_time
    ) VALUES (
        v_user_id_carnaval,
        v_total,
        'En Revision',
        'Entrega a domicilio',
        COALESCE(NULLIF(v_dest_direccion_full,''), v_destinatario->>'direccion', ''),
        v_metodo_pago,
        COALESCE(v_paquete->>'descripcion', 'Orden de paquetería'),
        'Paquete #' || COALESCE(v_paquete->>'numero','SIN-NUMERO'),
        v_dest_nombre,
        v_dest_telefono,
        v_id_proveedor_carnaval,
        ARRAY[v_id_proveedor_carnaval::BIGINT]::BIGINT[],
        'CUP',
        jsonb_build_object(
            'remitente',    v_remitente,
            'destinatario', v_destinatario,
            'paquete',      v_paquete
        ),
        0,
        0,
        0,
        0,
        0,
        0,
        COALESCE(NULLIF(v_remit_direccion_full,''), v_remitente->>'direccion', ''),
        v_peso_text,
        false,
        null,
        now()::time
    )
    RETURNING id INTO v_order_id;
    v_step := 'order_created';

    -- ---------- 5. Insertar OrderDetail (incluye `extra`) ----------
    v_step := 'inserting_orderdetail';
    INSERT INTO carnavalapp."OrderDetails" (
        order_id, product_id, quantity, price, proveedor, cajero,
        status_aprobacion, completada, transferencia, extra
    ) VALUES (
        v_order_id,
        v_id_producto_carnaval,
        v_cantidad,
        COALESCE(v_precio_descuento, v_precio_unitario),
        v_id_proveedor_carnaval,
        null,
        false,
        false,
        (v_metodo_pago ILIKE 'Transferencia'),
        v_extra
    )
    RETURNING id INTO v_orderdetail_id;
    v_step := 'orderdetail_created';

    -- ---------- 6. Recuperar id_operacion creado por el trigger ----------
    v_step := 'fetching_operacion';
    SELECT id INTO v_id_operacion
      FROM public.app_dat_operaciones
     WHERE observaciones = 'Venta desde orden ' || v_order_id
     ORDER BY id DESC
     LIMIT 1;
    v_step := 'operacion_fetched';

    -- ---------- 7. Insertar public.paqueteria_ordenes y sincronizar uuid ----------
    IF v_id_operacion IS NOT NULL THEN
        v_step := 'inserting_paqueteria_ordenes';
        INSERT INTO public.paqueteria_ordenes (
            id_operacion, id_orden_carnaval,
            numero_paquete, descripcion, foto_url
        ) VALUES (
            v_id_operacion,
            v_order_id,
            COALESCE(v_paquete->>'numero', 'SIN-NUMERO'),
            v_paquete->>'descripcion',
            NULLIF(v_paquete->>'foto_url','')
        )
        RETURNING id INTO v_paqueteria_ordenes_id;
        v_step := 'paqueteria_ordenes_created';

        IF v_uuid_vendedor IS NOT NULL THEN
            v_step := 'updating_operacion_uuid';
            UPDATE public.app_dat_operaciones
               SET uuid = v_uuid_vendedor , id_tienda = v_id_tienda
             WHERE id = v_id_operacion;
            v_step := 'operacion_uuid_updated';

            SELECT id_tpv into v_tpv_id from public.app_dat_vendedor where uuid = v_uuid_vendedor;

            update public.app_dat_operacion_venta set id_tpv = v_tpv_id where id_operacion = v_id_operacion;
        END IF;

        -- ---------- 7.b Sumar `extra` a la extracción de inventario ----------
        IF v_extra IS NOT NULL AND v_extra > 0 THEN
            v_step := 'updating_extraccion_extra';
            IF v_id_ubicacion IS NOT NULL THEN
                UPDATE public.app_dat_extraccion_productos
                   SET cantidad = v_cantidad + v_extra
                 WHERE id_operacion = v_id_operacion
                   AND id_producto  = v_id_producto_inventtia
                   AND id_ubicacion = v_id_ubicacion;
            ELSE
                UPDATE public.app_dat_extraccion_productos
                   SET cantidad = v_cantidad + v_extra
                 WHERE id_operacion = v_id_operacion
                   AND id_producto  = v_id_producto_inventtia;
            END IF;
            v_step := 'extraccion_extra_updated';
        END IF;
    END IF;

    IF v_id_producto_carnaval IS not NULL THEN
        UPDATE carnavalapp."Productos" set  status = false where id = v_id_producto_carnaval;
    END IF;

    v_step := 'completed';

    RETURN jsonb_build_object(
        'status',                  'success',
        'id_orden_carnaval',       v_order_id,
        'id_operacion',            v_id_operacion,
        'id_producto_carnaval',    v_id_producto_carnaval,
        'id_usuario_carnaval',     v_user_id_carnaval,
        'id_usuario_vendedor',     v_user_id_seller,
        'id_orderdetail_carnaval', v_orderdetail_id,
        'id_paqueteria_ordenes',   v_paqueteria_ordenes_id,
        'last_step',               v_step,
        'cantidad',                v_cantidad,
        'extra',                   v_extra,
        'cantidad_total',          v_cantidad_total,
        'total',                   v_total
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'status',                  'error',
        'message',                 'Error al registrar orden de paquetería: ' || SQLERRM,
        'sqlstate',                SQLSTATE,
        'last_step',               v_step,
        'id_usuario_carnaval',     v_user_id_carnaval,
        'id_usuario_vendedor',     v_user_id_seller,
        'id_producto_carnaval',    v_id_producto_carnaval,
        'id_orden_carnaval',       v_order_id,
        'id_orderdetail_carnaval', v_orderdetail_id,
        'id_operacion',            v_id_operacion,
        'id_paqueteria_ordenes',   v_paqueteria_ordenes_id
    );
END;
$$;
