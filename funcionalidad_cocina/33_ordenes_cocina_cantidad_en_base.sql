-- ============================================================================
-- 33 Â· Fase 2 Â· Rutas de cocina: la cantidad vendida convertida a unidades BASE
--      public.fn_pedir_item_cuenta_v2(...)
--      public.fn_agregar_producto_orden_pendiente_v2(...)
--      public.fn_actualizar_cantidad_producto_orden_v2(...)
-- ============================================================================
-- Fase 2 del plan `docs/PLAN_CONSUMO_INGREDIENTES_ELABORADOS_PRESENTACIONES.md`
-- (Â§3.1 C5, Â§4 decision 1/2/3, Â§6 Fase 2) y Â§5 "rutas vivas y callers".
--
-- ----------------------------------------------------------------------------
-- EL DEFECTO (C5), medido sobre las definiciones VIVAS
-- ----------------------------------------------------------------------------
-- `fn_cantidad_en_base(p_id_presentacion, p_cantidad)` convierte la cantidad
-- expresada en la presentacion vendida a unidades base (Caja x24 -> 24).
-- Medido en produccion con el contador de conversiones sobre `prosrc`:
--
--   prosrc                        fn_cantidad_en_base  enrutada  desc_ing  devolver
--   fn_pedir_item_cuenta                    0             1         0         0
--   fn_agregar_producto_orden_pendiente     0             0         1         0
--   fn_actualizar_cantidad_producto_orden   0             0         1         1
--
-- Es decir: **ninguna de las tres convierte**. Vender 1 Caja (x24) de un
-- elaborado guarda la linea con 1 (correcto: la linea es la presentacion
-- vendida) y consume la receta de **1 unidad** (incorrecto por 24x).
--
-- Caso real medido (producto 219 "croqueta", base Unidad 339, Caja 340 x24):
--   fn_cantidad_en_base(340, 1)                 = 24
--   fn_obtener_ingredientes_recursivos(219, 1)  = [(216, 40), (218, 10)]
--   fn_obtener_ingredientes_recursivos(219, 24) = [(216, 960), (218, 240)]
--   => hoy el pliego 960/240 se descuenta como 40/10.
--
-- ----------------------------------------------------------------------------
-- SEMANTICA DE LA CADENA NUEVA (1B) Â· acordada con sql-core (tarea 30/31)
-- ----------------------------------------------------------------------------
--   Â· `fn_descontar_venta_enrutada_v2(...)` espera `p_cantidad` **SIEMPRE en
--     equivalente BASE** (rama receta = multiplicador ya base; rama SKU =
--     `fn_consumir_ingrediente_base_v2(p_cantidad_base)`).
--   Â· `fn_descontar_ingredientes_elaborado_v2(...)` espera el numero de
--     unidades BASE del elaborado (misma firma que la viva).
--   Â· `fn_devolver_ingredientes_elaborado_v2(...)` (35) devuelve en equivalente
--     BASE.
--   Por eso las tres `_v2` convierten **en la entrada** y la linea/importe
--   siguen guardando la cantidad en la PRESENTACION vendida (contrato de la app
--   intacto).
--
-- ----------------------------------------------------------------------------
-- QUE CREA ESTE ARCHIVO (nada de esto existe hoy)
-- ----------------------------------------------------------------------------
--   Â· `fn_pedir_item_cuenta_v2` â€” misma firma de 17 parametros que la viva
--     (incluidos los DEFAULT), mismo contrato jsonb de exito/error.
--     Cambios: `search_path = 'public, pg_catalog'`, guard `_safe`,
--     `v_cantidad_base := public.fn_cantidad_en_base(p_id_presentacion, p_cantidad)`
--     y `fn_descontar_venta_enrutada_v2(p_cantidad := v_cantidad_base)`.
--     La linea de cuenta (`fn_agregar_item_cuenta_mesa`) y la comanda siguen
--     recibiendo la cantidad en la presentacion vendida.
--   Â· `fn_agregar_producto_orden_pendiente_v2` â€” misma firma
--     `(p_id_operacion bigint, p_producto jsonb, p_uuid_usuario uuid)`.
--     Cambios: conversion a base en la rama elaborado y `_v2` de consumo;
--     el duplicado reenvia a `fn_actualizar_cantidad_producto_orden_v2`.
--   Â· `fn_actualizar_cantidad_producto_orden_v2` â€” misma firma
--     `(p_id_extraccion bigint, p_nueva_cantidad numeric, p_uuid_usuario uuid)`.
--     Cambios: `v_delta_base := public.fn_cantidad_en_base(v_extraccion.id_presentacion, v_delta)`;
--     delta > 0 -> `_v2` de consumo; delta < 0 -> `_v2` de devolucion (presentacion base).
--
-- ----------------------------------------------------------------------------
-- QUE **NO** TOCA
-- ----------------------------------------------------------------------------
--   Â· `fn_pedir_item_cuenta`               (viva; md5 76ec329cfdf357b6964dbc4cc7435987)
--   Â· `fn_agregar_producto_orden_pendiente`(viva; md5 f893ca19d735e861981d2de08e96915f)
--   Â· `fn_actualizar_cantidad_producto_orden`(viva; md5 30bd21384308342bc477d87c9816ee12)
--   Ni firmas ni cuerpos vivos. Solo objetos nuevos.
--
-- ----------------------------------------------------------------------------
-- DEPENDENCIAS Y ORDEN DE APLICACION
-- ----------------------------------------------------------------------------
--   Â· 45_guard_search_path.sql  -> `fn_check_user_has_access_to_tienda_safe`
--   Â· 24_bom_cantidad_en_base.sql -> `fn_cantidad_en_base` (YA aplicada)
--   Â· 30/31 (sql-core)          -> `fn_descontar_venta_enrutada_v2`,
--                                  `fn_descontar_ingredientes_elaborado_v2`
--   Â· 35 (este companero)       -> `fn_devolver_ingredientes_elaborado_v2`
--   Orden: **45 -> 30/31 -> 35 -> 33 -> 34**. Hay un gate al inicio que aborta
--   la aplicacion si falta alguna dependencia (VERIFICACION_PLAN_2 C9-a: la
--   cadena nueva no debe depender de nombres que no existan al ejecutar).
--
-- ----------------------------------------------------------------------------
-- HUECO CONOCIDO QUE ESTE ARCHIVO **NO** CIERRA (P1, reportado al lead)
-- ----------------------------------------------------------------------------
-- `fn_disparar_comanda(p_cantidad := p_cantidad)` sigue recibiendo la cantidad
-- en la presentacion vendida: vender 1 Caja de 24 croquetas genera una comanda
-- de **1** en el KDS. No se toca aqui porque cambia lo que ve cocina y el
-- alcance de la Fase 2 (C5) es el consumo de materia prima y el inventario; se
-- deja documentado para decidirlo con negocio.
-- ============================================================================

-- â”€â”€ Gate de dependencias â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
DO $gate$
BEGIN
    IF to_regprocedure('public.fn_check_user_has_access_to_tienda_safe(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta fn_check_user_has_access_to_tienda_safe: aplica antes presentaciones_inventario/45_guard_search_path.sql';
    END IF;
    IF to_regprocedure('public.fn_cantidad_en_base(bigint,numeric)') IS NULL THEN
        RAISE EXCEPTION 'Falta fn_cantidad_en_base: aplica antes presentaciones_inventario/24_bom_cantidad_en_base.sql';
    END IF;
    IF to_regprocedure('public.fn_descontar_venta_enrutada_v2(bigint,numeric,bigint,bigint,integer,boolean)') IS NULL THEN
        RAISE EXCEPTION 'Falta fn_descontar_venta_enrutada_v2: aplica antes funcionalidad_cocina/30_ingredientes_por_equivalente_base.sql + 31_ingredientes_v2_rutas.sql';
    END IF;
    IF to_regprocedure('public.fn_descontar_ingredientes_elaborado_v2(bigint,numeric,bigint,bigint,integer)') IS NULL THEN
        RAISE EXCEPTION 'Falta fn_descontar_ingredientes_elaborado_v2: aplica antes 30/31_ingredientes_v2_rutas.sql';
    END IF;
    IF to_regprocedure('public.fn_devolver_ingredientes_elaborado_v2(bigint,numeric,bigint,bigint,integer)') IS NULL THEN
        RAISE EXCEPTION 'Falta fn_devolver_ingredientes_elaborado_v2: aplica antes funcionalidad_cocina/35_devoluciones_presentacion.sql';
    END IF;
END
$gate$;


-- ============================================================================
-- 33.1 Â· fn_pedir_item_cuenta_v2
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_pedir_item_cuenta_v2(
    p_id_cuenta bigint,
    p_id_producto bigint,
    p_cantidad numeric,
    p_precio_unitario numeric,
    p_id_variante bigint DEFAULT NULL::bigint,
    p_id_opcion_variante bigint DEFAULT NULL::bigint,
    p_id_presentacion bigint DEFAULT NULL::bigint,
    p_id_ubicacion bigint DEFAULT NULL::bigint,
    p_precio_base numeric DEFAULT NULL::numeric,
    p_id_metodo_pago bigint DEFAULT NULL::bigint,
    p_promotion_data jsonb DEFAULT NULL::jsonb,
    p_inventory_data jsonb DEFAULT NULL::jsonb,
    p_notas text DEFAULT NULL::text,
    p_sku_producto character varying DEFAULT NULL::character varying,
    p_sku_ubicacion character varying DEFAULT NULL::character varying,
    p_uuid_vendedor uuid DEFAULT NULL::uuid,
    p_forzar_sin_stock boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
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
$function$;

COMMENT ON FUNCTION public.fn_pedir_item_cuenta_v2(bigint, bigint, numeric, numeric, bigint, bigint, bigint, bigint, numeric, bigint, jsonb, jsonb, text, varchar, varchar, uuid, boolean) IS
    'Fase 2 / C5: copia de fn_pedir_item_cuenta con search_path correcto, guard seguro y la cantidad convertida a unidades base (fn_cantidad_en_base) antes de fn_descontar_venta_enrutada_v2. La linea de cuenta y la comanda conservan la cantidad en la presentacion vendida. La viva no se toca.';

REVOKE ALL ON FUNCTION public.fn_pedir_item_cuenta_v2(bigint, bigint, numeric, numeric, bigint, bigint, bigint, bigint, numeric, bigint, jsonb, jsonb, text, varchar, varchar, uuid, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_pedir_item_cuenta_v2(bigint, bigint, numeric, numeric, bigint, bigint, bigint, bigint, numeric, bigint, jsonb, jsonb, text, varchar, varchar, uuid, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_pedir_item_cuenta_v2(bigint, bigint, numeric, numeric, bigint, bigint, bigint, bigint, numeric, bigint, jsonb, jsonb, text, varchar, varchar, uuid, boolean)
    TO authenticated, service_role;


-- ============================================================================
-- 33.2 Â· fn_agregar_producto_orden_pendiente_v2
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_agregar_producto_orden_pendiente_v2(
    p_id_operacion bigint,
    p_producto jsonb,
    p_uuid_usuario uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $function$
DECLARE
    v_estado           INT;
    v_id_extraccion    BIGINT;
    v_importe          NUMERIC;
    v_nuevo_total      NUMERIC;
    v_es_elaborado     BOOLEAN;
    v_extraccion_exist RECORD;   -- para detectar duplicado
    v_nueva_cantidad   NUMERIC;
    v_id_medio_pago    INT;
    v_id_almacen       BIGINT;
    v_bom              JSONB;
    v_cantidad_base    NUMERIC;
BEGIN
    -- 1. Verificar estado Pendiente
    SELECT eo.estado INTO v_estado
      FROM public.app_dat_estado_operacion eo
     WHERE eo.id_operacion = p_id_operacion
     ORDER BY eo.created_at DESC, eo.id DESC
     LIMIT 1;

    IF v_estado IS DISTINCT FROM 1 THEN
        RETURN jsonb_build_object('status','error','message','Solo se pueden editar Ã³rdenes en estado Pendiente');
    END IF;

    -- 2. Validar campos mÃ­nimos
    IF p_producto->>'id_producto'     IS NULL OR
       p_producto->>'cantidad'        IS NULL OR
       p_producto->>'precio_unitario' IS NULL OR
       p_producto->>'id_medio_pago'   IS NULL THEN
        RETURN jsonb_build_object('status','error','message','El producto debe incluir id_producto, cantidad, precio_unitario e id_medio_pago');
    END IF;

    v_id_medio_pago := (p_producto->>'id_medio_pago')::INT;

    -- 3. Buscar si ya existe una extracciÃ³n con el mismo producto/variante/ubicaciÃ³n
    SELECT ep.id, ep.cantidad
      INTO v_extraccion_exist
      FROM public.app_dat_extraccion_productos ep
     WHERE ep.id_operacion = p_id_operacion
       AND ep.id_producto  = (p_producto->>'id_producto')::BIGINT
       AND COALESCE(ep.id_variante,  0) = COALESCE(NULLIF(p_producto->>'id_variante',  '')::BIGINT, 0)
       AND COALESCE(ep.id_ubicacion, 0) = COALESCE(NULLIF(p_producto->>'id_ubicacion', '')::BIGINT, 0)
     ORDER BY ep.created_at DESC
     LIMIT 1;

    IF FOUND THEN
        -- â”€â”€ Producto duplicado: redirigir a la version _v2 del ajuste â”€â”€
        v_nueva_cantidad := v_extraccion_exist.cantidad + (p_producto->>'cantidad')::NUMERIC;

        RETURN public.fn_actualizar_cantidad_producto_orden_v2(
            v_extraccion_exist.id,
            v_nueva_cantidad,
            p_uuid_usuario
        );
    END IF;

    v_importe := (p_producto->>'cantidad')::NUMERIC * (p_producto->>'precio_unitario')::NUMERIC;

    -- 4. Insertar extracciÃ³n (producto nuevo en la orden). La cantidad de la
    --    LINEA sigue en la presentacion vendida.
    INSERT INTO public.app_dat_extraccion_productos (
        id_operacion, id_producto, id_variante, id_opcion_variante,
        id_ubicacion, id_presentacion,
        cantidad, precio_unitario, importe, importe_real,
        sku_producto, sku_ubicacion, created_at
    ) VALUES (
        p_id_operacion,
        (p_producto->>'id_producto')::BIGINT,
        NULLIF(p_producto->>'id_variante',       '')::BIGINT,
        NULLIF(p_producto->>'id_opcion_variante','')::BIGINT,
        NULLIF(p_producto->>'id_ubicacion',      '')::BIGINT,
        NULLIF(p_producto->>'id_presentacion',   '')::BIGINT,
        (p_producto->>'cantidad')::NUMERIC,
        (p_producto->>'precio_unitario')::NUMERIC,
        v_importe,
        (p_producto->>'cantidad')::NUMERIC * COALESCE(
            NULLIF(p_producto->>'precio_real','')::NUMERIC,
            (p_producto->>'precio_unitario')::NUMERIC
        ),
        p_producto->>'sku_producto',
        p_producto->>'sku_ubicacion',
        NOW()
    ) RETURNING id INTO v_id_extraccion;

    -- 5. Verificar si es elaborado
    SELECT (es_elaborado or es_servicio) INTO v_es_elaborado
      FROM public.app_dat_producto WHERE id = (p_producto->>'id_producto')::BIGINT;

    -- 6. Ajustar inventario
    IF v_es_elaborado IS NOT TRUE THEN
        INSERT INTO public.app_dat_inventario_productos (
            id_producto, id_variante, id_opcion_variante, id_ubicacion, id_presentacion,
            cantidad_inicial, cantidad_final, sku_producto, sku_ubicacion,
            origen_cambio, id_extraccion, created_at
        )
        SELECT
            (p_producto->>'id_producto')::BIGINT,
            NULLIF(p_producto->>'id_variante',       '')::BIGINT,
            NULLIF(p_producto->>'id_opcion_variante','')::BIGINT,
            NULLIF(p_producto->>'id_ubicacion',      '')::BIGINT,
            NULLIF(p_producto->>'id_presentacion',   '')::BIGINT,
            COALESCE(ip.cantidad_final, 0),
            COALESCE(ip.cantidad_final, 0) - (p_producto->>'cantidad')::NUMERIC,
            p_producto->>'sku_producto',
            p_producto->>'sku_ubicacion',
            3, v_id_extraccion, NOW()
        FROM (
            SELECT cantidad_final
              FROM public.app_dat_inventario_productos
             WHERE id_producto = (p_producto->>'id_producto')::BIGINT
               AND COALESCE(id_variante,  0) = COALESCE(NULLIF(p_producto->>'id_variante','')::BIGINT, 0)
               AND COALESCE(id_ubicacion, 0) = COALESCE(NULLIF(p_producto->>'id_ubicacion','')::BIGINT, 0)
             ORDER BY created_at DESC, id DESC
             LIMIT 1
        ) ip;
        -- NOTA: el SKU propio se mueve en la presentacion vendida (fisico), igual
        -- que la viva: la linea y el ledger hablan la misma unidad.
    ELSE
        -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
        -- FASE 2 / C5 Â· Descuento de materia prima por EQUIVALENTE BASE.
        -- La linea trae la cantidad en la presentacion vendida; la receta se
        -- multiplica por unidades base. Si la linea no trae presentacion,
        -- fn_cantidad_en_base devuelve la cantidad sin tocar (comportamiento
        -- anterior, compatible con builds viejos).
        -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
        v_id_almacen := COALESCE(
            public.fn_almacen_de_extraccion(v_id_extraccion),
            public.fn_almacen_de_operacion(p_id_operacion)
        );

        IF v_id_almacen IS NULL THEN
            RETURN jsonb_build_object(
                'status','error',
                'message','No se pudo determinar el almacen para descontar la materia prima',
                'error_code','ALMACEN_NOT_RESOLVED',
                'id_operacion', p_id_operacion
            );
        END IF;

        v_cantidad_base := public.fn_cantidad_en_base(
            NULLIF(p_producto->>'id_presentacion', '')::BIGINT,
            (p_producto->>'cantidad')::NUMERIC
        );

        v_bom := public.fn_descontar_ingredientes_elaborado_v2(
            p_id_producto_elaborado := (p_producto->>'id_producto')::BIGINT,
            p_cantidad              := v_cantidad_base,
            p_id_almacen            := v_id_almacen,
            p_id_extraccion         := v_id_extraccion,
            p_origen_cambio         := 4
        );

        IF (v_bom->>'status') <> 'success' THEN
            RETURN jsonb_build_object(
                'status',        'error',
                'message',       COALESCE(v_bom->>'message', 'Error descontando materia prima'),
                'error_code',    COALESCE(v_bom->>'error_code', 'BOM_ERROR'),
                'id_ingrediente', v_bom->'id_ingrediente',
                'disponible',    COALESCE(v_bom->'cantidad_disponible', to_jsonb(0)),
                'requerido',     COALESCE(v_bom->'cantidad_requerida',  to_jsonb(0)),
                'id_almacen',    v_id_almacen
            );
        END IF;
    END IF;

    -- 7. Recalcular total
    SELECT COALESCE(SUM(cantidad * precio_unitario), 0)
      INTO v_nuevo_total
      FROM public.app_dat_extraccion_productos
     WHERE id_operacion = p_id_operacion;

    UPDATE public.app_dat_operacion_venta
       SET importe_total = v_nuevo_total
     WHERE id_operacion = p_id_operacion;

    -- 8. Registrar/acumular pago para el mÃ©todo seleccionado
    IF EXISTS (
        SELECT 1 FROM public.app_dat_pago_venta
         WHERE id_operacion_venta = p_id_operacion
           AND id_medio_pago = v_id_medio_pago
    ) THEN
        UPDATE public.app_dat_pago_venta
           SET monto = monto + v_importe
         WHERE id_operacion_venta = p_id_operacion
           AND id_medio_pago = v_id_medio_pago;
    ELSE
        INSERT INTO public.app_dat_pago_venta (id_operacion_venta, id_medio_pago, monto, created_at)
        VALUES (p_id_operacion, v_id_medio_pago, v_importe, NOW());
    END IF;

    -- 9. Log
    INSERT INTO public.app_dat_log_modificacion_orden
        (id_operacion, uuid_usuario, accion, detalle, created_at)
    VALUES (
        p_id_operacion,
        p_uuid_usuario,
        'add_product',
        jsonb_build_object(
            'id_extraccion',    v_id_extraccion,
            'producto',         p_producto,
            'importe',          v_importe,
            'id_medio_pago',    v_id_medio_pago,
            'nuevo_total_orden',v_nuevo_total,
            'id_almacen_bom',   v_id_almacen,
            'cantidad_base',    v_cantidad_base
        ),
        NOW()
    );

    RETURN jsonb_build_object(
        'status',        'success',
        'id_extraccion', v_id_extraccion,
        'importe',       v_importe,
        'total_orden',   v_nuevo_total,
        'message',       'Producto agregado correctamente'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('status','error','message','Error: ' || SQLERRM, 'sqlstate', SQLSTATE);
END;
$function$;

COMMENT ON FUNCTION public.fn_agregar_producto_orden_pendiente_v2(bigint, jsonb, uuid) IS
    'Fase 2 / C5: copia de fn_agregar_producto_orden_pendiente con search_path correcto y la cantidad de la rama elaborado convertida a unidades base (fn_cantidad_en_base) antes de fn_descontar_ingredientes_elaborado_v2. El SKU propio sigue moviendose en la presentacion vendida. La viva no se toca.';

REVOKE ALL ON FUNCTION public.fn_agregar_producto_orden_pendiente_v2(bigint, jsonb, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_agregar_producto_orden_pendiente_v2(bigint, jsonb, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_agregar_producto_orden_pendiente_v2(bigint, jsonb, uuid)
    TO authenticated, service_role;


-- ============================================================================
-- 33.3 Â· fn_actualizar_cantidad_producto_orden_v2
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_actualizar_cantidad_producto_orden_v2(
    p_id_extraccion bigint,
    p_nueva_cantidad numeric,
    p_uuid_usuario uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $function$
DECLARE
    v_extraccion        RECORD;
    v_operacion         RECORD;
    v_ultimo_inventario RECORD;
    v_delta             NUMERIC;
    v_delta_base        NUMERIC;
    v_nuevo_importe     NUMERIC;
    v_nuevo_total       NUMERIC;
    v_es_elaborado      BOOLEAN;
    v_id_almacen        BIGINT;
    v_bom               JSONB;
BEGIN
    -- 1. Obtener datos actuales de la extracciÃ³n
    SELECT e.*, o.id AS op_id
      INTO v_extraccion
      FROM public.app_dat_extraccion_productos e
      JOIN public.app_dat_operaciones           o ON o.id = e.id_operacion
     WHERE e.id = p_id_extraccion;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('status','error','message','ExtracciÃ³n no encontrada');
    END IF;

    -- 2. Verificar que la orden estÃ© en estado Pendiente (estado = 1)
    SELECT eo.estado INTO v_operacion
      FROM public.app_dat_estado_operacion eo
     WHERE eo.id_operacion = v_extraccion.op_id
     ORDER BY eo.created_at DESC, eo.id DESC
     LIMIT 1;

    IF v_operacion.estado IS DISTINCT FROM 1 THEN
        RETURN jsonb_build_object('status','error','message','Solo se pueden editar Ã³rdenes en estado Pendiente');
    END IF;

    IF p_nueva_cantidad <= 0 THEN
        RETURN jsonb_build_object('status','error','message','La nueva cantidad debe ser mayor que 0. Para eliminar usa fn_eliminar_producto_orden.');
    END IF;

    -- 3. Calcular delta (diferencia entre nueva y antigua cantidad).
    --    El delta esta en la PRESENTACION vendida; FASE 2 lo convierte a base.
    v_delta := p_nueva_cantidad - v_extraccion.cantidad;

    -- 4. Verificar si el producto es elaborado
    SELECT (es_elaborado or es_servicio) INTO v_es_elaborado
      FROM public.app_dat_producto
     WHERE id = v_extraccion.id_producto;

    -- 5. Si no es elaborado, verificar/ajustar inventario base
    IF v_es_elaborado IS NOT TRUE THEN
        SELECT cantidad_final
          INTO v_ultimo_inventario
          FROM public.app_dat_inventario_productos
         WHERE id_producto = v_extraccion.id_producto
           AND COALESCE(id_variante,  0) = COALESCE(v_extraccion.id_variante,  0)
           AND COALESCE(id_ubicacion, 0) = COALESCE(v_extraccion.id_ubicacion, 0)
         ORDER BY created_at DESC, id DESC
         LIMIT 1;

        IF v_delta > 0 AND (v_ultimo_inventario IS NULL OR v_ultimo_inventario.cantidad_final < v_delta) THEN
            RETURN jsonb_build_object(
                'status','error',
                'message','Stock insuficiente para aumentar la cantidad',
                'disponible', COALESCE(v_ultimo_inventario.cantidad_final, 0),
                'requerido',  v_delta
            );
        END IF;

        -- Registrar ajuste de inventario del producto base (presentacion vendida)
        INSERT INTO public.app_dat_inventario_productos (
            id_producto, id_variante, id_opcion_variante, id_ubicacion, id_presentacion,
            cantidad_inicial, cantidad_final,
            sku_producto, sku_ubicacion,
            origen_cambio, id_extraccion, created_at
        )
        SELECT
            v_extraccion.id_producto,
            v_extraccion.id_variante,
            v_extraccion.id_opcion_variante,
            v_extraccion.id_ubicacion,
            v_extraccion.id_presentacion,
            COALESCE(ip.cantidad_final, 0),
            COALESCE(ip.cantidad_final, 0) - v_delta,
            v_extraccion.sku_producto,
            v_extraccion.sku_ubicacion,
            3,   -- Origen: Venta / ajuste
            p_id_extraccion,
            NOW()
        FROM (
            SELECT cantidad_final
              FROM public.app_dat_inventario_productos
             WHERE id_producto = v_extraccion.id_producto
               AND COALESCE(id_variante,  0) = COALESCE(v_extraccion.id_variante,  0)
               AND COALESCE(id_ubicacion, 0) = COALESCE(v_extraccion.id_ubicacion, 0)
             ORDER BY created_at DESC, id DESC
             LIMIT 1
        ) ip;
    ELSE
        -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
        -- FASE 2 / C5 Â· Ajuste de materia prima por EQUIVALENTE BASE.
        -- `v_delta` viene en la presentacion vendida; se convierte con
        -- fn_cantidad_en_base(id_presentacion de la linea, delta) y el consumo
        -- y la devolucion son simetricos (ambos `_v2`).
        -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
        v_id_almacen := public.fn_almacen_de_extraccion(p_id_extraccion);

        IF v_id_almacen IS NULL THEN
            RETURN jsonb_build_object(
                'status','error',
                'message','No se pudo determinar el almacen de la linea para ajustar la materia prima',
                'error_code','ALMACEN_NOT_RESOLVED',
                'id_extraccion', p_id_extraccion
            );
        END IF;

        v_delta_base := public.fn_cantidad_en_base(v_extraccion.id_presentacion, v_delta);

        IF v_delta > 0 THEN
            -- Aumentar cantidad â†’ descontar mÃ¡s ingredientes (en base)
            v_bom := public.fn_descontar_ingredientes_elaborado_v2(
                p_id_producto_elaborado := v_extraccion.id_producto,
                p_cantidad              := v_delta_base,
                p_id_almacen            := v_id_almacen,
                p_id_extraccion         := p_id_extraccion,
                p_origen_cambio         := 4
            );
        ELSIF v_delta < 0 THEN
            -- Disminuir cantidad â†’ devolver ingredientes a la presentacion BASE
            v_bom := public.fn_devolver_ingredientes_elaborado_v2(
                p_id_producto_elaborado := v_extraccion.id_producto,
                p_cantidad              := ABS(v_delta_base),
                p_id_almacen            := v_id_almacen,
                p_id_extraccion         := p_id_extraccion,
                p_origen_cambio         := 4
            );
        ELSE
            -- delta = 0: nada que mover
            v_bom := jsonb_build_object('status','success','lineas_afectadas',0);
        END IF;

        IF (v_bom->>'status') <> 'success' THEN
            -- Reescribir al formato de error que ya espera esta pantalla,
            -- conservando el detalle del helper.
            RETURN jsonb_build_object(
                'status',        'error',
                'message',       COALESCE(v_bom->>'message', 'Error ajustando materia prima'),
                'error_code',    COALESCE(v_bom->>'error_code', 'BOM_ERROR'),
                'id_ingrediente', v_bom->'id_ingrediente',
                'disponible',    COALESCE(v_bom->'cantidad_disponible', to_jsonb(0)),
                'requerido',     COALESCE(v_bom->'cantidad_requerida',  to_jsonb(0)),
                'id_almacen',    v_id_almacen
            );
        END IF;
    END IF;

    -- 6. Actualizar extracciÃ³n (la LINEA sigue en la presentacion vendida)
    v_nuevo_importe := p_nueva_cantidad * v_extraccion.precio_unitario;

    UPDATE public.app_dat_extraccion_productos
       SET cantidad        = p_nueva_cantidad,
           importe         = v_nuevo_importe,
           importe_real    = p_nueva_cantidad * COALESCE(v_extraccion.precio_unitario, 0)
     WHERE id = p_id_extraccion;

    -- 7. Recalcular importe total de la venta
    SELECT COALESCE(SUM(cantidad * precio_unitario), 0)
      INTO v_nuevo_total
      FROM public.app_dat_extraccion_productos
     WHERE id_operacion = v_extraccion.op_id;

    UPDATE public.app_dat_operacion_venta
       SET importe_total = v_nuevo_total
     WHERE id_operacion = v_extraccion.op_id;

    -- 8. Redistribuir pagos proporcionalmente
    PERFORM public._fn_distribuir_pagos_orden(v_extraccion.op_id, v_nuevo_total);

    -- 9. Log
    INSERT INTO public.app_dat_log_modificacion_orden
        (id_operacion, uuid_usuario, accion, detalle, created_at)
    VALUES (
        v_extraccion.op_id,
        p_uuid_usuario,
        'update_quantity',
        jsonb_build_object(
            'id_extraccion',    p_id_extraccion,
            'id_producto',      v_extraccion.id_producto,
            'cantidad_anterior',v_extraccion.cantidad,
            'cantidad_nueva',   p_nueva_cantidad,
            'importe_anterior', v_extraccion.importe,
            'importe_nuevo',    v_nuevo_importe,
            'delta',            v_delta,
            'delta_base',       v_delta_base,
            'nuevo_total_orden',v_nuevo_total,
            'id_almacen_bom',   v_id_almacen
        ),
        NOW()
    );

    RETURN jsonb_build_object(
        'status',         'success',
        'id_extraccion',  p_id_extraccion,
        'cantidad_nueva', p_nueva_cantidad,
        'importe_nuevo',  v_nuevo_importe,
        'total_orden',    v_nuevo_total,
        'message',        'Cantidad actualizada correctamente'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('status','error','message','Error: ' || SQLERRM, 'sqlstate', SQLSTATE);
END;
$function$;

COMMENT ON FUNCTION public.fn_actualizar_cantidad_producto_orden_v2(bigint, numeric, uuid) IS
    'Fase 2 / C5: copia de fn_actualizar_cantidad_producto_orden con search_path correcto y delta convertido a unidades base (fn_cantidad_en_base) para el consumo (_v2) y la devolucion (_v2, presentacion base). El SKU propio sigue ajustandose en la presentacion vendida. La viva no se toca.';

REVOKE ALL ON FUNCTION public.fn_actualizar_cantidad_producto_orden_v2(bigint, numeric, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_actualizar_cantidad_producto_orden_v2(bigint, numeric, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_actualizar_cantidad_producto_orden_v2(bigint, numeric, uuid)
    TO authenticated, service_role;


-- ============================================================================
-- VERIFICACION (comentada)
-- ============================================================================
--
-- V1 Â· Las tres `_v2` existen con la MISMA firma que las vivas y con
--      `search_path = 'public, pg_catalog'`:
--
--   SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args,
--          p.prorettype::regtype AS ret, p.proconfig
--     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname='public'
--      AND p.proname IN ('fn_pedir_item_cuenta_v2',
--                        'fn_agregar_producto_orden_pendiente_v2',
--                        'fn_actualizar_cantidad_producto_orden_v2')
--    ORDER BY 1;
--   -- comparar los `args` con los de las vivas (deben ser identicos).
--
-- V2 Â· Exactamente UNA conversion por funcion (y las llamadas a la cadena `_v2`):
--
--   SELECT p.proname,
--          (SELECT count(*) FROM regexp_matches(p.prosrc, 'fn_cantidad_en_base\(', 'g')) AS conversiones,
--          (SELECT count(*) FROM regexp_matches(p.prosrc, 'fn_descontar_venta_enrutada_v2\(', 'g')) AS enrutada_v2,
--          (SELECT count(*) FROM regexp_matches(p.prosrc, 'fn_descontar_ingredientes_elaborado_v2\(', 'g')) AS desc_ing_v2,
--          (SELECT count(*) FROM regexp_matches(p.prosrc, 'fn_devolver_ingredientes_elaborado_v2\(', 'g')) AS devolver_v2
--     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname='public'
--      AND p.proname IN ('fn_pedir_item_cuenta_v2',
--                        'fn_agregar_producto_orden_pendiente_v2',
--                        'fn_actualizar_cantidad_producto_orden_v2')
--    ORDER BY 1;
--   -- esperado: (1,1,0,0) / (1,0,1,0) / (1,0,1,1)
--
-- V3 Â· Las VIVAS siguen intactas:
--
--   SELECT p.proname, md5(pg_get_functiondef(p.oid)) AS md5
--     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname='public'
--      AND p.proname IN ('fn_pedir_item_cuenta','fn_agregar_producto_orden_pendiente',
--                        'fn_actualizar_cantidad_producto_orden') ORDER BY 1;
--   -- esperado: 76ec329cfdf357b6964dbc4cc7435987 / f893ca19d735e861981d2de08e96915f / 30bd21384308342bc477d87c9816ee12
--
-- ============================================================================
-- TESTS
-- ============================================================================
-- T-A y T-C corren en produccion con el MCP en modo lectura. T-B necesita
-- escritura (debug `qhprswhhfasrikhawjoz` o SQL Editor).
-- ============================================================================

-- ############################################################################
-- SECCION T-A Â· El defecto C5 y la conversion (solo lectura)
-- ############################################################################

SELECT
    public.fn_cantidad_en_base(340, 1)                        AS caja_340_x1,      -- 24
    public.fn_cantidad_en_base(340, 2)                        AS caja_340_x2,      -- 48
    public.fn_cantidad_en_base(339, 5)                        AS base_339_x5,      -- 5  (no doble conversion)
    public.fn_cantidad_en_base(NULL, 5)                       AS sin_presentacion, -- 5  (fallback builds viejos)
    (SELECT jsonb_agg(jsonb_build_object('id_ingrediente', id_ingrediente,
                                         'cantidad', cantidad_total_necesaria)
                      ORDER BY id_ingrediente)
       FROM public.fn_obtener_ingredientes_recursivos(219, 1))  AS receta_x1,        -- 216->40, 218->10
    (SELECT jsonb_agg(jsonb_build_object('id_ingrediente', id_ingrediente,
                                         'cantidad', cantidad_total_necesaria)
                      ORDER BY id_ingrediente)
       FROM public.fn_obtener_ingredientes_recursivos(219, 24)) AS receta_x24,       -- 216->960, 218->240
    (SELECT count(*) FROM (
        SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public'
           AND p.proname IN ('fn_pedir_item_cuenta','fn_agregar_producto_orden_pendiente',
                             'fn_actualizar_cantidad_producto_orden')) s
      WHERE position('fn_cantidad_en_base' IN s.prosrc) > 0)    AS vivas_con_conversion;
-- Esperado (medido en produccion): 24 / 48 / 5 / 5 / [{216,40},{218,10}] /
--                                  [{216,960},{218,240}] / 0
-- El ultimo 0 es el defecto C5: ninguna ruta viva convierte.

-- ############################################################################
-- SECCION T-B Â· La conversion cambia el consumo x factor (requiere escritura)
-- ############################################################################

-- COMMIT OBLIGATORIO antes de los tests: el `ROLLBACK` del final revierte la
-- transaccion en curso y, si el DDL de arriba comparte esa transaccion (el SQL
-- Editor y el MCP mandan el archivo como UN solo batch), el DDL se perderia.
COMMIT;

-- T-B1 Â· CON la conversion de la Fase 2 (lo que hace `fn_pedir_item_cuenta_v2`)
BEGIN;

DO $test$
DECLARE
    v_id_almacen bigint;
    v_disp216    numeric;
    v_disp218    numeric;
    v_cajas      numeric;
    v_base       numeric;
    v_antes216   numeric;
    v_antes218   numeric;
    v_desc       jsonb;
BEGIN
    IF to_regprocedure('public.fn_descontar_ingredientes_elaborado_v2(bigint,numeric,bigint,bigint,integer)') IS NULL THEN
        RAISE NOTICE 'T-B1 OMITIDO: falta fn_descontar_ingredientes_elaborado_v2 (aplica antes 30/31). El DDL de este archivo ya quedo aplicado.';
        RETURN;
    END IF;

    SELECT la.id_almacen INTO v_id_almacen
      FROM public.app_dat_inventario_productos ip
      JOIN public.app_dat_layout_almacen la ON la.id = ip.id_ubicacion
     WHERE ip.id_producto IN (216, 218) AND la.deleted_at IS NULL
     GROUP BY la.id_almacen
     ORDER BY count(DISTINCT ip.id_producto) DESC, sum(ip.cantidad_final) DESC NULLS LAST
     LIMIT 1;

    IF v_id_almacen IS NULL THEN
        RAISE NOTICE 'T-B1 OMITIDO: no hay almacen con movimiento de 216/218 en este proyecto.';
        RETURN;
    END IF;

    v_disp216 := public.fn_stock_producto_almacen(216, v_id_almacen);
    v_disp218 := public.fn_stock_producto_almacen(218, v_id_almacen);
    v_cajas   := floor(LEAST(v_disp216 / (40 * 24), v_disp218 / (10 * 24)));

    IF v_cajas < 1 THEN
        RAISE NOTICE 'T-B1 OMITIDO: stock insuficiente para 1 Caja (disp 216=%, disp 218=%).', v_disp216, v_disp218;
        RETURN;
    END IF;

    v_base     := 24 * v_cajas;   -- 1 Caja x24 convertida a base
    v_antes216 := v_disp216;
    v_antes218 := v_disp218;

    v_desc := public.fn_descontar_ingredientes_elaborado_v2(
        p_id_producto_elaborado := 219,
        p_cantidad              := v_base,
        p_id_almacen            := v_id_almacen,
        p_id_extraccion         := NULL,
        p_origen_cambio         := 4);

    IF (v_desc->>'status') <> 'success' THEN
        RAISE EXCEPTION 'T-B1: descuento fallo: %', v_desc;
    END IF;

    IF public.fn_stock_producto_almacen(216, v_id_almacen) <> v_antes216 - 40 * v_base THEN
        RAISE EXCEPTION 'T-B1: 216 deberia bajar % (x24 de la receta); quedo en %',
            40 * v_base, public.fn_stock_producto_almacen(216, v_id_almacen);
    END IF;
    IF public.fn_stock_producto_almacen(218, v_id_almacen) <> v_antes218 - 10 * v_base THEN
        RAISE EXCEPTION 'T-B1: 218 deberia bajar % (x24 de la receta); quedo en %',
            10 * v_base, public.fn_stock_producto_almacen(218, v_id_almacen);
    END IF;
END $test$;

ROLLBACK;

-- T-B2 Â· SIN la conversion (comportamiento de la viva hoy): la receta baja 1x.
--        Demuestra el defecto C5 sobre los mismos datos.
BEGIN;

DO $test$
DECLARE
    v_id_almacen bigint;
    v_disp216    numeric;
    v_antes216   numeric;
    v_desc       jsonb;
BEGIN
    IF to_regprocedure('public.fn_descontar_ingredientes_elaborado_v2(bigint,numeric,bigint,bigint,integer)') IS NULL THEN
        RAISE NOTICE 'T-B2 OMITIDO: falta fn_descontar_ingredientes_elaborado_v2 (aplica antes 30/31).';
        RETURN;
    END IF;

    SELECT la.id_almacen INTO v_id_almacen
      FROM public.app_dat_inventario_productos ip
      JOIN public.app_dat_layout_almacen la ON la.id = ip.id_ubicacion
     WHERE ip.id_producto = 216 AND la.deleted_at IS NULL
     GROUP BY la.id_almacen
     ORDER BY sum(ip.cantidad_final) DESC NULLS LAST
     LIMIT 1;

    v_disp216  := public.fn_stock_producto_almacen(216, v_id_almacen);
    v_antes216 := v_disp216;

    IF v_disp216 < 40 THEN
        RAISE NOTICE 'T-B2 OMITIDO: falta stock de 216 (disp %).', v_disp216;
        RETURN;
    END IF;

    -- 1 = la cantidad CRUDA de "1 Caja" (lo que pasan hoy las tres rutas vivas)
    v_desc := public.fn_descontar_ingredientes_elaborado_v2(
        p_id_producto_elaborado := 219,
        p_cantidad              := 1,
        p_id_almacen            := v_id_almacen,
        p_id_extraccion         := NULL,
        p_origen_cambio         := 4);

    IF (v_desc->>'status') <> 'success' THEN
        RAISE EXCEPTION 'T-B2: descuento fallo: %', v_desc;
    END IF;

    IF public.fn_stock_producto_almacen(216, v_id_almacen) <> v_antes216 - 40 THEN
        RAISE EXCEPTION 'T-B2: sin conversion 216 deberia bajar 40 (1x la receta); quedo en %',
            public.fn_stock_producto_almacen(216, v_id_almacen);
    END IF;
END $test$;

ROLLBACK;

-- ############################################################################
-- SECCION T-C Â· Reverificacion: nada aplicado y md5 vivos intactos
--              (corre tambien en produccion con MCP lectura)
-- ############################################################################

SELECT
    to_regprocedure('public.fn_pedir_item_cuenta_v2(bigint,bigint,numeric,numeric,bigint,bigint,bigint,bigint,numeric,bigint,jsonb,jsonb,text,varchar,varchar,uuid,boolean)') IS NULL
        AS pedir_v2_no_creada,
    to_regprocedure('public.fn_agregar_producto_orden_pendiente_v2(bigint,jsonb,uuid)') IS NULL
        AS agregar_v2_no_creada,
    to_regprocedure('public.fn_actualizar_cantidad_producto_orden_v2(bigint,numeric,uuid)') IS NULL
        AS actualizar_v2_no_creada,
    md5(pg_get_functiondef('public.fn_pedir_item_cuenta(bigint,bigint,numeric,numeric,bigint,bigint,bigint,bigint,numeric,bigint,jsonb,jsonb,text,varchar,varchar,uuid,boolean)'::regprocedure))
        = '76ec329cfdf357b6964dbc4cc7435987'  AS pedir_viva_intacta,
    md5(pg_get_functiondef('public.fn_agregar_producto_orden_pendiente(bigint,jsonb,uuid)'::regprocedure))
        = 'f893ca19d735e861981d2de08e96915f'  AS agregar_viva_intacta,
    md5(pg_get_functiondef('public.fn_actualizar_cantidad_producto_orden(bigint,numeric,uuid)'::regprocedure))
        = '30bd21384308342bc477d87c9816ee12'  AS actualizar_viva_intacta;
-- Esperado: true / true / true / true / true / true

-- ============================================================================
-- RESULTADO MEDIDO EN PRODUCCION (`vsieeihstajlrdvpuooh`, MCP read-only)
-- ============================================================================
--   Â· T-A: 24 / 48 / 5 / 5 / [{216,40},{218,10}] / [{216,960},{218,240}] / 0
--   Â· Contadores de prosrc en las VIVAS (C5): fn_cantidad_en_base = 0 en las
--     tres; fn_pedir_item_cuenta llama a fn_descontar_venta_enrutada (1);
--     fn_agregar_producto_orden_pendiente y fn_actualizar_cantidad_producto_orden
--     llaman a fn_descontar_ingredientes_elaborado (1 cada una) y la segunda a
--     fn_devolver_ingredientes_elaborado (1).
--   Â· Las tres `_v2` = NULL en produccion (nada aplicado).
--   Â· md5 vivos: 76ec329cfdf357b6964dbc4cc7435987 / f893ca19d735e861981d2de08e96915f /
--                30bd21384308342bc477d87c9816ee12.
--   Â· T-B1/T-B2 NO se pudieron correr contra produccion: el rol del MCP es
--     `supabase_read_only_user` (sin CREATE en public, sin EXECUTE en el guard).
--     Quedan listos para debug `qhprswhhfasrikhawjoz` o el SQL Editor, despues
--     de aplicar 45 -> 30/31 -> 35.
-- ============================================================================