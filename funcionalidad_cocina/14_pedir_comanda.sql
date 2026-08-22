-- ============================================================================
-- 14 · Fase 2 · Pedir: clasificar, mover stock y crear comanda
-- ============================================================================
-- Proyecto Supabase: vsieeihstajlrdvpuooh
--
-- ESTADO VERIFICADO ANTES DE ESCRIBIR ESTE ARCHIVO (via MCP)
-- ---------------------------------------------------------
--   app_dat_comanda (16 col) y app_dat_comanda_item (18 col)      aplicadas
--   los 5 campos nuevos de app_dat_mesa_cuenta_item               aplicados
--   fn_registrar_venta / _mesa: enruta=true, helper_viejo=false    aplicadas
--   las 11 RPC de cocina (07..11)                                 aplicadas
--
-- QUE HACE ESTE ARCHIVO
-- ---------------------
-- Implementa el "pedir" de la Fase 2: al agregar un item a una cuenta abierta
-- se clasifica la linea, se mueve el inventario y (si va a cocina) se crea la
-- comanda. El cobro deja de ser el momento del descuento; eso lo cierra el 15.
--
-- ESTRATEGIA: ADITIVA (mismo criterio que el 09)
-- ----------------------------------------------
-- NO se reemplaza fn_agregar_item_cuenta_mesa. Se crea fn_pedir_item_cuenta,
-- que la llama por dentro y le anade la parte de cocina/stock.
--
-- Razones:
--   1. fn_agregar_item_cuenta_mesa la usan rutas que no queremos cambiar de
--      golpe (agregarOrderItem del servicio Dart, por ejemplo).
--   2. Si algo sale mal en produccion, basta con que la app vuelva a llamar a
--      la vieja: el rollback es un cambio de una linea en Dart, no un SQL.
--   3. Las lineas creadas por la vieja quedan con stock_movido = false, que es
--      exactamente el marcador de "legado, descuenta al cobrar" que definio el
--      13. Las dos rutas conviven sin corromper datos.
--
-- ORDEN DE APLICACION
-- -------------------
--   1. Aplicar este archivo completo.
--   2. Correr la VERIFICACION del final.
--   3. Despues el 15 (cobro sin re-descontar) y el 16 (UI vendedor).
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 14.1 fn_siguiente_numero_comanda
--
-- Correlativo visible por tienda y dia ("marchando la 12"). Se reinicia cada
-- dia: un numero de 4 cifras es inutil para cantar en una cocina.
--
-- Se calcula con MAX+1 sobre el dia en curso en lugar de una secuencia porque
-- una secuencia global no se puede reiniciar por tienda ni por dia sin trucos.
-- El riesgo de colision bajo concurrencia se acota con un advisory lock por
-- tienda: dos meseros pidiendo a la vez no pueden obtener el mismo numero.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_siguiente_numero_comanda(
    p_id_tienda bigint
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_numero integer;
BEGIN
    -- Lock por tienda, liberado al terminar la transaccion. Serializa solo a
    -- los que piden en la MISMA tienda.
    PERFORM pg_advisory_xact_lock(
        hashtext('comanda_numero_' || p_id_tienda::text)::bigint
    );

    SELECT COALESCE(MAX(numero), 0) + 1
      INTO v_numero
      FROM app_dat_comanda
     WHERE id_tienda = p_id_tienda
       AND created_at >= date_trunc('day', now());

    RETURN v_numero;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_siguiente_numero_comanda(bigint)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 14.2 fn_disparar_comanda
--
-- Crea (o reusa) la comanda de una cocina para una cuenta, y le agrega una
-- linea. Es la RPC que pide el plan en 2.2.
--
-- REUSO POR DISPARO
-- El plan quiere "tandas de trabajo": si el mesero pide entradas y 20 minutos
-- despues los fuertes, deben ser dos comandas. Pero si agrega tres platos
-- seguidos, deben ir en la MISMA (es un solo viaje a la mesa).
--
-- Se resuelve con una ventana de agrupacion: se reusa la comanda PENDIENTE mas
-- reciente de esa (cuenta, cocina) si tiene menos de p_ventana_minutos y nadie
-- la ha empezado. En cuanto la cocina la toma (estado 2) o pasa la ventana, el
-- siguiente pedido abre comanda nueva. Asi la cocina nunca ve crecer un ticket
-- que ya esta cocinando.
--
-- p_id_item_cuenta es opcional: permite disparar comandas sin cuenta de mesa
-- (venta directa, Fase 5).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_disparar_comanda(
    p_id_cocina        bigint,
    p_id_producto      bigint,
    p_cantidad         numeric,
    p_id_cuenta        bigint  DEFAULT NULL,
    p_id_item_cuenta   bigint  DEFAULT NULL,
    p_id_tpv           bigint  DEFAULT NULL,
    p_uuid_vendedor    uuid    DEFAULT NULL,
    p_notas            text    DEFAULT NULL,
    p_movimiento_stock jsonb   DEFAULT NULL,
    p_ventana_minutos  integer DEFAULT 5
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_id_tienda     bigint;
    v_cocina_activa boolean;
    v_cocina_nombre text;
    v_id_mesa       bigint;
    v_id_comanda    bigint;
    v_numero        integer;
    v_id_item       bigint;
    v_prod          RECORD;
    v_nueva         boolean := false;
BEGIN
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La cantidad debe ser mayor que cero',
            'error_code', 'INVALID_QUANTITY'
        );
    END IF;

    SELECT c.id_tienda, c.activa, c.denominacion
      INTO v_id_tienda, v_cocina_activa, v_cocina_nombre
      FROM app_dat_cocina c
     WHERE c.id = p_id_cocina AND c.deleted_at IS NULL;

    IF v_id_tienda IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La cocina no existe',
            'error_code', 'COCINA_NOT_FOUND'
        );
    END IF;

    PERFORM check_user_has_access_to_tienda(v_id_tienda);

    IF NOT v_cocina_activa THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    'La cocina "' || v_cocina_nombre || '" no esta recibiendo pedidos',
            'error_code', 'COCINA_INACTIVA',
            'id_cocina',  p_id_cocina
        );
    END IF;

    -- Datos del producto para congelar denominacion y modo.
    SELECT p.denominacion,
           COALESCE(p.modo_elaboracion, 'al_pedido') AS modo_elaboracion
      INTO v_prod
      FROM app_dat_producto p
     WHERE p.id = p_id_producto AND p.deleted_at IS NULL;

    IF v_prod.denominacion IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El producto no existe',
            'error_code', 'PRODUCTO_NOT_FOUND'
        );
    END IF;

    -- Mesa de la cuenta, para que el KDS pueda mostrar "Mesa 3".
    IF p_id_cuenta IS NOT NULL THEN
        SELECT id_mesa INTO v_id_mesa
          FROM app_dat_mesa_cuenta_abierta
         WHERE id = p_id_cuenta;
    END IF;

    -- Reusar la comanda pendiente reciente de esta (cuenta, cocina).
    -- Solo estado 1: si la cocina ya la empezo, se abre otra.
    IF p_id_cuenta IS NOT NULL THEN
        SELECT co.id INTO v_id_comanda
          FROM app_dat_comanda co
         WHERE co.id_cuenta = p_id_cuenta
           AND co.id_cocina = p_id_cocina
           AND co.estado = 1
           AND co.created_at >= now() - make_interval(mins => p_ventana_minutos)
         ORDER BY co.created_at DESC
         LIMIT 1;
    END IF;

    IF v_id_comanda IS NULL THEN
        v_numero := fn_siguiente_numero_comanda(v_id_tienda);

        INSERT INTO app_dat_comanda (
            id_tienda, id_cocina, id_cuenta, id_mesa, id_tpv,
            numero, estado, uuid_vendedor
        ) VALUES (
            v_id_tienda, p_id_cocina, p_id_cuenta, v_id_mesa, p_id_tpv,
            v_numero, 1, p_uuid_vendedor
        ) RETURNING id INTO v_id_comanda;

        v_nueva := true;
    ELSE
        SELECT numero INTO v_numero FROM app_dat_comanda WHERE id = v_id_comanda;
    END IF;

    INSERT INTO app_dat_comanda_item (
        id_comanda, id_item_cuenta, id_producto,
        denominacion, cantidad, modo_elaboracion,
        estado, notas, movimiento_stock
    ) VALUES (
        v_id_comanda, p_id_item_cuenta, p_id_producto,
        v_prod.denominacion, p_cantidad, v_prod.modo_elaboracion,
        1, p_notas, p_movimiento_stock
    ) RETURNING id INTO v_id_item;

    RETURN jsonb_build_object(
        'status',          'success',
        'id_comanda',      v_id_comanda,
        'id_comanda_item', v_id_item,
        'numero',          v_numero,
        'comanda_nueva',   v_nueva,
        'id_cocina',       p_id_cocina,
        'cocina',          v_cocina_nombre,
        'id_mesa',         v_id_mesa,
        'message',         'Enviado a ' || v_cocina_nombre
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'status',   'error',
            'message',  'Error al disparar la comanda: ' || SQLERRM,
            'sqlstate', SQLSTATE
        );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_disparar_comanda(bigint, bigint, numeric, bigint, bigint, bigint, uuid, text, jsonb, integer)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 14.3 fn_pedir_item_cuenta
--
-- EL CORAZON DE LA FASE 2. Agrega un item a una cuenta abierta y, en el mismo
-- acto, clasifica la linea, mueve el inventario y dispara la comanda si va a
-- cocina. "Pedir = servir / mandar a cocina", como dice el plan.
--
-- Envuelve a fn_agregar_item_cuenta_mesa (no la reemplaza) y le anade:
--
--   1. clasificar con fn_resolver_origen_venta (valida enrutamiento tambien)
--   2. descontar con fn_descontar_venta_enrutada del almacen correcto
--   3. crear comanda si el plato va a cocina
--   4. marcar la linea: origen_stock, id_cocina, id_comanda_item,
--      estado_servicio, stock_movido = true
--
-- ORDEN DE LAS OPERACIONES (importa)
-- ----------------------------------
-- Se descuenta ANTES de insertar la linea. Si el stock no alcanza, la funcion
-- sale con error y la cuenta queda intacta: no se le cobra al cliente algo que
-- la cocina no puede hacer. Al revés (insertar y luego descontar) dejaria la
-- linea en la nota tras un fallo.
--
-- Todo corre en la transaccion implicita de la RPC: si el disparo de comanda
-- falla despues del descuento, Postgres revierte el descuento tambien.
--
-- SOBRE LA CONSOLIDACION
-- ----------------------
-- fn_agregar_item_cuenta_mesa consolida lineas iguales (cantidad += N). Eso es
-- correcto para cobrar. La comanda, en cambio, se dispara SIEMPRE por la
-- cantidad pedida ahora: si el cliente pide otra croqueta, la cocina tiene que
-- recibir otra croqueta aunque la linea de la nota diga 2.
--
-- Como una linea consolidada puede tener varias comandas, id_comanda_item en la
-- linea guarda LA ULTIMA. Es lo que necesita la UI (estado de lo mas reciente);
-- el historial completo esta en app_dat_comanda_item.id_item_cuenta.
--
-- p_forzar_sin_stock: valvula para el caso "permite_vender_aun_sin_disponibilidad"
-- que ya existe en la configuracion de tienda. Si es true y el descuento falla
-- por stock, la linea se agrega igual pero con stock_movido = false, y queda
-- registrado en la respuesta para que la UI avise. NO se dispara comanda de algo
-- que no se puede producir salvo que el plato sea al_pedido (la cocina decide).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_pedir_item_cuenta(
    p_id_cuenta          bigint,
    p_id_producto        bigint,
    p_cantidad           numeric,
    p_precio_unitario    numeric,
    p_id_variante        bigint  DEFAULT NULL,
    p_id_opcion_variante bigint  DEFAULT NULL,
    p_id_presentacion    bigint  DEFAULT NULL,
    p_id_ubicacion       bigint  DEFAULT NULL,
    p_precio_base        numeric DEFAULT NULL,
    p_id_metodo_pago     bigint  DEFAULT NULL,
    p_promotion_data     jsonb   DEFAULT NULL,
    p_inventory_data     jsonb   DEFAULT NULL,
    p_notas              text    DEFAULT NULL,
    p_sku_producto       varchar DEFAULT NULL,
    p_sku_ubicacion      varchar DEFAULT NULL,
    p_uuid_vendedor      uuid    DEFAULT NULL,
    p_forzar_sin_stock   boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_cuenta        RECORD;
    v_ruta          jsonb;
    v_origen        text;
    v_origen_stock  text;
    v_id_cocina     bigint;
    v_descuento     jsonb;
    v_stock_movido  boolean := false;
    v_aviso_stock   jsonb   := NULL;
    v_id_item       bigint;
    v_comanda       jsonb   := NULL;
    v_id_com_item   bigint;
    v_estado_serv   smallint := NULL;
BEGIN
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La cantidad debe ser mayor que cero',
            'error_code', 'INVALID_QUANTITY'
        );
    END IF;

    -- ── 1. Cuenta abierta ─────────────────────────────────────────────────
    SELECT c.id, c.id_tienda, c.id_tpv, c.id_mesa, c.estado
      INTO v_cuenta
      FROM app_dat_mesa_cuenta_abierta c
     WHERE c.id = p_id_cuenta;

    IF v_cuenta.id IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La cuenta no existe',
            'error_code', 'CUENTA_NOT_FOUND'
        );
    END IF;

    PERFORM check_user_has_access_to_tienda(v_cuenta.id_tienda);

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

    -- ── 2. Clasificar (y validar enrutamiento) ────────────────────────────
    v_ruta := fn_resolver_origen_venta(p_id_producto, v_cuenta.id_tpv);

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

    -- ── 3. Mover inventario AHORA (esto es "pedir != cobrar") ─────────────
    -- p_ya_descontado_sku := false porque aqui NADIE descontó antes: no hay
    -- INSERT de venta previo como en fn_registrar_venta.
    v_descuento := fn_descontar_venta_enrutada(
        p_id_producto       := p_id_producto,
        p_cantidad          := p_cantidad,
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

    -- ── 4. Agregar la linea a la cuenta (delegando en la funcion existente) ──
    v_id_item := fn_agregar_item_cuenta_mesa(
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

    -- ── 5. Disparar comanda si el plato va a cocina ───────────────────────
    -- Un producto de barra o un servicio no genera comanda: el plan lo dice
    -- explicito ("Cocina solo ve comandas de su estacion, no bebidas del bar").
    --
    -- Una TANDA tampoco genera comanda de coccion: la porcion ya esta hecha, se
    -- sirve. El plan lo marca como "sin comanda de coccion (pase opcional)".
    IF v_id_cocina IS NOT NULL AND v_origen = 'cocina_al_pedido' THEN
        v_comanda := fn_disparar_comanda(
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

    -- ── 6. Marcar la linea con lo que paso ────────────────────────────────
    UPDATE app_dat_mesa_cuenta_item
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

GRANT EXECUTE ON FUNCTION public.fn_pedir_item_cuenta(bigint, bigint, numeric, numeric, bigint, bigint, bigint, bigint, numeric, bigint, jsonb, jsonb, text, varchar, varchar, uuid, boolean)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 14.4 fn_cancelar_item_pedido
--
-- Quitar una linea de la cuenta despues de haberla pedido. El plan lo pide en
-- 2.3: "Cancelar item no servido -> devolver reserva" y "Item ya servido ->
-- merma / anulacion con motivo".
--
-- Dos casos, y la diferencia es contable, no cosmetica:
--
--   NO SERVIDO (comanda pendiente o en preparacion)
--     Se cancela la comanda y se DEVUELVE el stock: la materia prima no se
--     consumio (o se puede recuperar). Se registra un movimiento de entrada.
--
--   YA SERVIDO/ENTREGADO
--     El plato existe fisicamente. Devolver el stock seria mentir: los
--     ingredientes se gastaron. Se quita de la cuenta (el cliente no lo paga)
--     pero el inventario NO se devuelve: es MERMA. Exige p_motivo.
--
-- Devolver stock de algo ya cocinado es el error clasico que descuadra un
-- inventario de restaurante, por eso se separa explicitamente.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_cancelar_item_pedido(
    p_id_item bigint,
    p_motivo  text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_item         RECORD;
    v_id_tienda    bigint;
    v_estado_cta   smallint;
    v_com_item     RECORD;
    v_ya_servido   boolean := false;
    v_devuelto     jsonb   := NULL;
    v_ubic         RECORD;
    v_pendiente    numeric;
    v_a_devolver   numeric;
    v_movs         jsonb   := '[]'::jsonb;
    v_id_almacen   bigint;
BEGIN
    SELECT i.id, i.id_cuenta, i.id_producto, i.cantidad,
           i.origen_stock, i.id_cocina, i.id_comanda_item, i.stock_movido,
           i.inventory_data
      INTO v_item
      FROM app_dat_mesa_cuenta_item i
     WHERE i.id = p_id_item;

    IF v_item.id IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El item no existe',
            'error_code', 'ITEM_NOT_FOUND'
        );
    END IF;

    SELECT c.id_tienda, c.estado INTO v_id_tienda, v_estado_cta
      FROM app_dat_mesa_cuenta_abierta c
     WHERE c.id = v_item.id_cuenta;

    PERFORM check_user_has_access_to_tienda(v_id_tienda);

    IF v_estado_cta <> 1 THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    'La cuenta ya no esta abierta',
            'error_code', 'CUENTA_NO_ABIERTA'
        );
    END IF;

    -- ── Estado en cocina ──────────────────────────────────────────────────
    IF v_item.id_comanda_item IS NOT NULL THEN
        SELECT ci.id, ci.estado, ci.id_comanda
          INTO v_com_item
          FROM app_dat_comanda_item ci
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

    -- ── Cancelar la comanda si estaba viva ────────────────────────────────
    IF v_com_item.id IS NOT NULL AND v_com_item.estado IN (1, 2) THEN
        UPDATE app_dat_comanda_item
           SET estado = 5, updated_at = now()
         WHERE id = v_com_item.id;

        -- Si no queda ninguna linea viva, cancelar la cabecera tambien.
        UPDATE app_dat_comanda co
           SET estado = 5, cancelled_at = now(), updated_at = now()
         WHERE co.id = v_com_item.id_comanda
           AND NOT EXISTS (
                SELECT 1 FROM app_dat_comanda_item ci2
                 WHERE ci2.id_comanda = co.id AND ci2.estado IN (1, 2, 3)
           );
    END IF;

    -- ── Devolver stock solo si NO se sirvio ───────────────────────────────
    IF v_item.stock_movido AND NOT v_ya_servido THEN
        v_id_almacen := NULLIF(v_item.inventory_data->>'id_almacen', '')::bigint;

        IF v_id_almacen IS NULL THEN
            -- Sin traza del almacen no se adivina: se avisa en vez de devolver
            -- a un almacen equivocado.
            v_devuelto := jsonb_build_object(
                'status', 'warning',
                'message', 'No se pudo determinar el almacen de origen: revisar manualmente'
            );
        ELSIF v_item.origen_stock = 'al_pedido' THEN
            -- Se devuelven los INGREDIENTES a la cocina.
            v_devuelto := fn_devolver_ingredientes_elaborado(
                p_id_producto_elaborado := v_item.id_producto,
                p_cantidad              := v_item.cantidad,
                p_id_almacen            := v_id_almacen,
                p_origen_cambio         := 4
            );
        ELSE
            -- Se devuelve el SKU propio (barra o porcion de tanda no servida).
            v_pendiente := v_item.cantidad;

            FOR v_ubic IN
                SELECT * FROM fn_stock_producto_almacen_detalle(v_item.id_producto, v_id_almacen)
            LOOP
                EXIT WHEN v_pendiente <= 0;
                v_a_devolver := v_pendiente;

                INSERT INTO app_dat_inventario_productos (
                    id_producto, id_variante, id_opcion_variante,
                    id_ubicacion, id_presentacion,
                    cantidad_inicial, cantidad_final,
                    sku_producto, sku_ubicacion,
                    origen_cambio, created_at
                ) VALUES (
                    v_item.id_producto, v_ubic.id_variante, v_ubic.id_opcion_variante,
                    v_ubic.id_ubicacion, v_ubic.id_presentacion,
                    v_ubic.cantidad_final, v_ubic.cantidad_final + v_a_devolver,
                    v_ubic.sku_producto, v_ubic.sku_ubicacion,
                    4, now()
                );

                v_movs := v_movs || jsonb_build_object(
                    'id_ubicacion', v_ubic.id_ubicacion,
                    'devuelto',     v_a_devolver
                );
                v_pendiente := 0;
            END LOOP;

            v_devuelto := jsonb_build_object(
                'status',      'success',
                'movimientos', v_movs
            );
        END IF;
    END IF;

    -- ── Quitar la linea de la cuenta ──────────────────────────────────────
    DELETE FROM app_dat_mesa_cuenta_item WHERE id = p_id_item;

    UPDATE app_dat_mesa_cuenta_abierta SET updated_at = now()
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
$function$;

GRANT EXECUTE ON FUNCTION public.fn_cancelar_item_pedido(bigint, text)
    TO anon, authenticated, service_role;


-- ============================================================================
-- VERIFICACION
-- ============================================================================

-- (a) Las 4 funciones nuevas, todas SECURITY DEFINER con search_path fijo
SELECT p.oid::regprocedure AS firma,
       p.prosecdef         AS security_definer,
       p.proconfig         AS config
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_siguiente_numero_comanda', 'fn_disparar_comanda',
                     'fn_pedir_item_cuenta', 'fn_cancelar_item_pedido')
 ORDER BY p.proname;

-- (b) Dependencias que deben existir -> 5 filas
SELECT p.oid::regprocedure AS dependencia
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_resolver_origen_venta', 'fn_descontar_venta_enrutada',
                     'fn_agregar_item_cuenta_mesa', 'fn_devolver_ingredientes_elaborado',
                     'fn_stock_producto_almacen_detalle')
 ORDER BY p.proname;

-- (c) fn_agregar_item_cuenta_mesa NO debe haber cambiado (estrategia aditiva):
--     sigue sin tocar inventario -> toca_inventario = false
SELECT p.proname,
       length(p.prosrc) AS largo,
       (p.prosrc ILIKE '%app_dat_inventario_productos%') AS toca_inventario
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'fn_agregar_item_cuenta_mesa';


-- ----------------------------------------------------------------------------
-- PRUEBA FUNCIONAL (transaccion revertida)
--
-- Datos reales: tienda 11, TPV 18 -> almacen 12, mesa 1,
--               219 croqueta = 40 g harina (216) + 10 g sal (218)
--
-- Sustituir <UUID> por un uuid de trabajador valido de la tienda 11.
-- ----------------------------------------------------------------------------
/*
BEGIN;

    -- Montaje ------------------------------------------------------------
    SELECT public.fn_crear_cocina(11, 'PRUEBA Cocina 14') AS cocina;
    SELECT public.fn_asignar_tpv_cocina(
        18, (SELECT id FROM app_dat_cocina WHERE denominacion = 'PRUEBA Cocina 14')
    ) AS ligar;

    -- MP solo en la cocina
    INSERT INTO app_dat_inventario_productos
        (id_producto, id_ubicacion, cantidad_inicial, cantidad_final, created_at)
    SELECT 216, la.id, 500, 500, now() FROM app_dat_layout_almacen la
      JOIN app_dat_cocina c ON c.id_almacen = la.id_almacen
     WHERE c.denominacion = 'PRUEBA Cocina 14' LIMIT 1;

    INSERT INTO app_dat_inventario_productos
        (id_producto, id_ubicacion, cantidad_inicial, cantidad_final, created_at)
    SELECT 218, la.id, 200, 200, now() FROM app_dat_layout_almacen la
      JOIN app_dat_cocina c ON c.id_almacen = la.id_almacen
     WHERE c.denominacion = 'PRUEBA Cocina 14' LIMIT 1;

    UPDATE app_dat_producto
       SET id_cocina = (SELECT id FROM app_dat_cocina WHERE denominacion = 'PRUEBA Cocina 14'),
           modo_elaboracion = 'al_pedido'
     WHERE id = 219;

    SELECT public.fn_abrir_cuenta_mesa(
        p_id_mesa := 1, p_id_tpv := 18, p_forzar_nueva := true
    ) AS id_cuenta;
    -- ANOTAR el id devuelto; los pasos siguientes lo recalculan con subconsulta

    -- 1. PEDIR un al_pedido -> debe crear comanda y descontar de la COCINA ---
    SELECT public.fn_pedir_item_cuenta(
        p_id_cuenta       := (SELECT max(id) FROM app_dat_mesa_cuenta_abierta WHERE id_mesa = 1),
        p_id_producto     := 219,
        p_cantidad        := 2,
        p_precio_unitario := 100,
        p_notas           := 'sin sal',
        p_uuid_vendedor   := '<UUID>'::uuid
    ) AS pedido_al_pedido;
    -- esperado: status success, origen cocina_al_pedido, origen_stock al_pedido,
    --           stock_movido true, id_comanda + numero_comanda presentes,
    --           estado_servicio 1, message "Enviado a PRUEBA Cocina 14"

    -- 2. El stock salio de la COCINA, no de la barra ----------------------
    SELECT public.fn_stock_producto_almacen(216, 12) AS harina_barra,
           public.fn_stock_producto_almacen(216,
             (SELECT id_almacen FROM app_dat_cocina
               WHERE denominacion = 'PRUEBA Cocina 14')) AS harina_cocina;
    -- esperado: harina_barra 5.0 (INTACTA), harina_cocina 420 (500 - 80)

    -- 3. La comanda existe con su linea y su nota -------------------------
    SELECT co.id, co.numero, co.estado AS estado_comanda, co.id_mesa,
           ci.denominacion, ci.cantidad, ci.modo_elaboracion,
           ci.estado AS estado_item, ci.notas,
           (ci.movimiento_stock IS NOT NULL) AS tiene_traza_stock
      FROM app_dat_comanda co
      JOIN app_dat_comanda_item ci ON ci.id_comanda = co.id
      JOIN app_dat_cocina c ON c.id = co.id_cocina
     WHERE c.denominacion = 'PRUEBA Cocina 14';
    -- esperado: 1 fila, numero 1, estado 1, cantidad 2, notas 'sin sal',
    --           tiene_traza_stock true

    -- 4. La linea de cuenta quedo marcada --------------------------------
    SELECT i.id, i.cantidad, i.origen_stock, i.stock_movido,
           i.estado_servicio, (i.id_cocina IS NOT NULL) AS tiene_cocina,
           (i.id_comanda_item IS NOT NULL) AS tiene_comanda
      FROM app_dat_mesa_cuenta_item i
     WHERE i.id_cuenta = (SELECT max(id) FROM app_dat_mesa_cuenta_abierta WHERE id_mesa = 1);
    -- esperado: origen_stock 'al_pedido', stock_movido true, estado_servicio 1

    -- 5. Pedir OTRA vez lo mismo: la cuenta CONSOLIDA, la comanda NO -----
    SELECT public.fn_pedir_item_cuenta(
        p_id_cuenta       := (SELECT max(id) FROM app_dat_mesa_cuenta_abierta WHERE id_mesa = 1),
        p_id_producto     := 219,
        p_cantidad        := 1,
        p_precio_unitario := 100
    ) AS segundo_pedido;

    SELECT (SELECT count(*) FROM app_dat_mesa_cuenta_item
             WHERE id_cuenta = (SELECT max(id) FROM app_dat_mesa_cuenta_abierta WHERE id_mesa = 1))
           AS lineas_de_cuenta,
           (SELECT sum(cantidad) FROM app_dat_mesa_cuenta_item
             WHERE id_cuenta = (SELECT max(id) FROM app_dat_mesa_cuenta_abierta WHERE id_mesa = 1))
           AS cantidad_total,
           (SELECT count(*) FROM app_dat_comanda_item ci
              JOIN app_dat_comanda co ON co.id = ci.id_comanda
              JOIN app_dat_cocina c ON c.id = co.id_cocina
             WHERE c.denominacion = 'PRUEBA Cocina 14') AS lineas_de_comanda;
    -- esperado: lineas_de_cuenta 1, cantidad_total 3, lineas_de_comanda 2
    --
    -- ESTA ES LA COMPROBACION CLAVE DEL DISENO: la nota consolida (1 linea de 3)
    -- pero la cocina recibio DOS avisos. Si lineas_de_comanda fuera 1, la
    -- segunda croqueta nunca se cocinaria.

    -- 6. Agrupacion por ventana: ambas en la MISMA comanda ---------------
    SELECT count(DISTINCT co.id) AS comandas_abiertas
      FROM app_dat_comanda co JOIN app_dat_cocina c ON c.id = co.id_cocina
     WHERE c.denominacion = 'PRUEBA Cocina 14';
    -- esperado: 1  (dos pedidos seguidos = un solo viaje a la mesa)

    -- 7. Si la cocina ya empezo, el siguiente pedido abre comanda NUEVA --
    UPDATE app_dat_comanda SET estado = 2, started_at = now()
     WHERE id_cocina = (SELECT id FROM app_dat_cocina WHERE denominacion = 'PRUEBA Cocina 14');

    SELECT public.fn_pedir_item_cuenta(
        p_id_cuenta       := (SELECT max(id) FROM app_dat_mesa_cuenta_abierta WHERE id_mesa = 1),
        p_id_producto     := 219,
        p_cantidad        := 1,
        p_precio_unitario := 100
    ) AS pedido_tras_empezar;

    SELECT count(DISTINCT co.id) AS comandas_totales
      FROM app_dat_comanda co JOIN app_dat_cocina c ON c.id = co.id_cocina
     WHERE c.denominacion = 'PRUEBA Cocina 14';
    -- esperado: 2  <- no se cuela trabajo en un ticket que ya se esta cocinando

    -- 8. Un producto de BARRA no genera comanda --------------------------
    SELECT public.fn_pedir_item_cuenta(
        p_id_cuenta       := (SELECT max(id) FROM app_dat_mesa_cuenta_abierta WHERE id_mesa = 1),
        p_id_producto     := 216,
        p_cantidad        := 1,
        p_precio_unitario := 10
    ) AS pedido_barra;
    -- esperado: origen barra, origen_stock 'tpv', id_comanda null,
    --           message 'Agregado a la cuenta'
    -- El plan: "Cocina solo ve comandas de su estacion, no bebidas del bar"

    SELECT public.fn_stock_producto_almacen(216, 12) AS harina_barra_tras_pedir;
    -- esperado: 4.0  <- la barra SI se descuenta al pedir

    -- 9. por_tanda: descuenta porcion, NO crea comanda de coccion --------
    UPDATE app_dat_producto SET modo_elaboracion = 'por_tanda' WHERE id = 219;

    INSERT INTO app_dat_inventario_productos
        (id_producto, id_ubicacion, cantidad_inicial, cantidad_final, created_at)
    SELECT 219, la.id, 7, 7, now() FROM app_dat_layout_almacen la
      JOIN app_dat_cocina c ON c.id_almacen = la.id_almacen
     WHERE c.denominacion = 'PRUEBA Cocina 14' LIMIT 1;

    SELECT public.fn_pedir_item_cuenta(
        p_id_cuenta       := (SELECT max(id) FROM app_dat_mesa_cuenta_abierta WHERE id_mesa = 1),
        p_id_producto     := 219,
        p_cantidad        := 2,
        p_precio_unitario := 100
    ) AS pedido_tanda;
    -- esperado: origen cocina_por_tanda, origen_stock 'tanda',
    --           id_comanda null, estado_servicio 4 (entregado),
    --           message 'Servido de PRUEBA Cocina 14'

    SELECT public.fn_stock_producto_almacen(219,
             (SELECT id_almacen FROM app_dat_cocina
               WHERE denominacion = 'PRUEBA Cocina 14')) AS porciones,
           public.fn_stock_producto_almacen(216,
             (SELECT id_almacen FROM app_dat_cocina
               WHERE denominacion = 'PRUEBA Cocina 14')) AS harina_cocina;
    -- esperado: porciones 5 (7 - 2), harina_cocina sin cambio respecto al paso 7
    -- La tanda consume la PORCION, no la receta.

    -- 10. Cancelar un item NO servido -> devuelve stock ------------------
    UPDATE app_dat_producto SET modo_elaboracion = 'al_pedido' WHERE id = 219;

    SELECT public.fn_pedir_item_cuenta(
        p_id_cuenta       := (SELECT max(id) FROM app_dat_mesa_cuenta_abierta WHERE id_mesa = 1),
        p_id_producto     := 219,
        p_cantidad        := 1,
        p_precio_unitario := 100,
        p_id_metodo_pago  := 999
    ) AS pedido_a_cancelar;
    -- (id_metodo_pago distinto fuerza una linea nueva, sin consolidar)

    SELECT public.fn_stock_producto_almacen(216,
             (SELECT id_almacen FROM app_dat_cocina
               WHERE denominacion = 'PRUEBA Cocina 14')) AS harina_antes_cancelar;

    SELECT public.fn_cancelar_item_pedido(
        (SELECT max(id) FROM app_dat_mesa_cuenta_item
          WHERE id_cuenta = (SELECT max(id) FROM app_dat_mesa_cuenta_abierta WHERE id_mesa = 1))
    ) AS cancelacion;
    -- esperado: ya_servido false, stock_devuelto true, es_merma false,
    --           comanda_cancelada true

    SELECT public.fn_stock_producto_almacen(216,
             (SELECT id_almacen FROM app_dat_cocina
               WHERE denominacion = 'PRUEBA Cocina 14')) AS harina_tras_cancelar;
    -- esperado: 40 g MAS que harina_antes_cancelar (la receta volvio)

    -- 11. Cancelar un item YA SERVIDO sin motivo -> debe rechazar --------
    SELECT public.fn_pedir_item_cuenta(
        p_id_cuenta       := (SELECT max(id) FROM app_dat_mesa_cuenta_abierta WHERE id_mesa = 1),
        p_id_producto     := 219,
        p_cantidad        := 1,
        p_precio_unitario := 100,
        p_id_metodo_pago  := 998
    ) AS pedido_servido;

    -- Marcar como entregado en cocina
    UPDATE app_dat_comanda_item SET estado = 4, delivered_at = now()
     WHERE id = (SELECT id_comanda_item FROM app_dat_mesa_cuenta_item
                  WHERE id_metodo_pago = 998
                  ORDER BY id DESC LIMIT 1);

    SELECT public.fn_cancelar_item_pedido(
        (SELECT id FROM app_dat_mesa_cuenta_item
          WHERE id_metodo_pago = 998 ORDER BY id DESC LIMIT 1)
    ) AS cancelar_servido_sin_motivo;
    -- esperado: error_code MOTIVO_REQUERIDO, ya_servido true

    -- 12. Con motivo -> se retira como MERMA, sin devolver stock ---------
    SELECT public.fn_stock_producto_almacen(216,
             (SELECT id_almacen FROM app_dat_cocina
               WHERE denominacion = 'PRUEBA Cocina 14')) AS harina_antes_merma;

    SELECT public.fn_cancelar_item_pedido(
        (SELECT id FROM app_dat_mesa_cuenta_item
          WHERE id_metodo_pago = 998 ORDER BY id DESC LIMIT 1),
        'El cliente lo devolvio frio'
    ) AS merma;
    -- esperado: es_merma true, stock_devuelto false

    SELECT public.fn_stock_producto_almacen(216,
             (SELECT id_almacen FROM app_dat_cocina
               WHERE denominacion = 'PRUEBA Cocina 14')) AS harina_tras_merma;
    -- esperado: IGUAL a harina_antes_merma
    --
    -- El plato ya estaba cocinado: los ingredientes se gastaron. Devolverlos
    -- seria mentirle al inventario. El cliente no paga, pero la MP se perdio.

    -- 13. Rechazos de enrutamiento ---------------------------------------
    SELECT public.fn_desasignar_tpv_cocina(
        18, (SELECT id FROM app_dat_cocina WHERE denominacion = 'PRUEBA Cocina 14')
    );

    SELECT public.fn_pedir_item_cuenta(
        p_id_cuenta       := (SELECT max(id) FROM app_dat_mesa_cuenta_abierta WHERE id_mesa = 1),
        p_id_producto     := 219,
        p_cantidad        := 1,
        p_precio_unitario := 100
    ) AS pedido_no_ligado;
    -- esperado: error_code COCINA_NO_LIGADA y la cuenta SIN linea nueva
    -- (no se agrega a la nota algo que este TPV no puede servir)

    -- 14. Casos borde ----------------------------------------------------
    SELECT public.fn_pedir_item_cuenta(
        (SELECT max(id) FROM app_dat_mesa_cuenta_abierta WHERE id_mesa = 1), 219, 0, 100
    ) AS cantidad_cero;
    -- esperado: INVALID_QUANTITY

    SELECT public.fn_pedir_item_cuenta(999999, 219, 1, 100) AS cuenta_inexistente;
    -- esperado: CUENTA_NOT_FOUND

ROLLBACK;
*/

-- Tras el ROLLBACK: todo limpio
-- SELECT count(*) AS comandas FROM app_dat_comanda;
-- SELECT id, denominacion FROM app_dat_cocina WHERE denominacion LIKE 'PRUEBA%';
-- SELECT public.fn_stock_producto_almacen(216, 12) AS harina_barra;  -- 5.0
