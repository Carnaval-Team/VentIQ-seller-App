-- ============================================================================
-- AJUSTE AUTOMÁTICO DE INVENTARIO/OPERACIONES AL VARIAR carnavalapp."OrderDetails"
-- ============================================================================
-- Problema que resuelve: el repartidor puede subir/bajar cantidades o borrar
-- una línea completa, y hoy eso SOLO queda en "OrderDetails". El inventario de
-- Inventtia (public) y el dinero de la venta quedan mintiendo.
--
-- Lo que hace, al igual que los triggers de crear/cancelar orden:
--   1) BEFORE UPDATE:
--      a) Descarta el precio si llega cambiado junto con la cantidad (el
--         precio es UNITARIO; las APKs viejas lo recalculaban y lo corrompían).
--      b) Topa la cantidad para que el stock no quede negativo.
--   2) AFTER UPDATE/DELETE:
--      a) Crea la operación de ajuste en public:
--           delta < 0 (el cliente devolvió)  -> RECEPCIÓN,  tipo 5,  motivo 3 (Devolución)
--           delta > 0 (el cliente quiso más) -> EXTRACCIÓN, tipo 24, motivo 14 (Venta online)
--      b) Inserta la nueva row en public.app_dat_inventario_productos con
--         origen_cambio = 5 (cantidad_final + devuelto) o 24 (cantidad_final - cantidad),
--         SIN dejar el stock negativo (se extrae LEAST(pedido, disponible)).
--      c) Actualiza la línea de extracción de la VENTA original con la cantidad
--         real y el dinero real, y recalcula importe_total / pago.
--      d) Recalcula total / totalUsd / totalEuro de la orden desde sus líneas.
--      e) Escribe la bitácora de capitán (quién, qué, cuándo, por qué).
--
-- REQUISITOS: aplicar antes carnaval_orderdetails_bitacora.sql
-- APLICAR MANUALMENTE en Supabase (SQL Editor). Idempotente.
--
-- NOTAS DE DISEÑO IMPORTANTES
-- ---------------------------------------------------------------------------
-- * NUNCA se borra la línea de extracción de la venta: se pone en la cantidad
--   real (o en 0). app_dat_inventario_productos.id_extraccion es ON DELETE
--   CASCADE, así que borrar la línea destruiría el historial de inventario.
-- * pg_trigger_depth() > 1  => el cambio NO lo hizo una persona directamente,
--   lo hizo otro trigger. Dos casos reales:
--     - fn_crear_operacion_desde_orden2, desde dentro del trigger de INSERT,
--       hace "UPDATE OrderDetails SET quantity = <lo disponible>" y
--       "DELETE FROM OrderDetails" cuando no hay stock. Ahí NO hay nada que
--       compensar: la venta nunca extrajo esa cantidad.
--     - Borrados en cascada: OrderDetails.order_id -> Orders(id) y
--       OrderDetails.product_id -> Productos(id) son ON DELETE CASCADE.
--   En ambos casos se registra en bitácora como 'ajuste_sistema' y NO se
--   compensa: es mejor no mover inventario que moverlo dos veces. Si en el
--   futuro se quiere devolver stock al borrar una orden completa, hay que
--   hacerlo explícito (no por cascada). Se revisan con:
--       WHERE accion = 'ajuste_sistema'
-- * Si el ajuste de inventario en public se aplica, fn_sincronizar_stock_producto
--   ya pone carnavalapp."Productos".stock en valor absoluto. Solo se toca el
--   stock de Carnaval a mano cuando ese camino NO corrió (paquetería, producto
--   sin mapear, error). Así no se descuenta dos veces.
-- * La app puede declarar el motivo antes de escribir:
--       SELECT set_config('carnavalapp.motivo_cambio','el cliente devolvió 2 panes', true);
--       SELECT set_config('carnavalapp.nota_cambio','...', true);
-- * Los totales de "Orders" solo se escriben si están mal. "Orders" tiene dos
--   triggers HTTP sin condición (notificar-proveedores-orden,
--   notificar_orden_asignada) que corren en CADA update: escribir de gratis son
--   dos llamadas a edge functions de gratis. Con esto, si la app ya dejó el
--   total correcto, el trigger no vuelve a tocar la fila.
-- ============================================================================


-- ============================================================================
-- 1) BEFORE UPDATE — defensa de precio + que no se quede sin stock
-- ============================================================================
CREATE OR REPLACE FUNCTION carnavalapp.fn_orderdetails_topar_cantidad()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, carnavalapp, pg_temp
AS $$
DECLARE
    v_delta      numeric;
    v_stock      numeric;
    v_permitido  numeric;
BEGIN
    -- Los ajustes que hace otro trigger ya vienen topados por él.
    IF pg_trigger_depth() > 1 THEN
        RETURN NEW;
    END IF;

    -- =====================================================================
    -- DEFENSA DE PRECIO
    -- ---------------------------------------------------------------------
    -- price, precio_usd y precio_euro son precios UNITARIOS. Versiones viejas
    -- de la app del repartidor los recalculaban al bajar la cantidad
    --     price := (price / quantity) * (quantity - 1)
    -- lo que corrompía el precio unitario y con él el importe de la venta, el
    -- inventario y el total de la orden. Y una vez corrompido no hay forma de
    -- recuperar el precio real.
    --
    -- Si el precio llega cambiado EN EL MISMO UPDATE que la cantidad, se
    -- descarta: esa es la firma exacta de ese bug. Un cambio de precio
    -- legítimo (un descuento) llega sin tocar la cantidad y sí se respeta.
    --
    -- Esto protege al ERP de las APKs viejas que sigan en la calle.
    -- =====================================================================
    IF NEW.quantity IS DISTINCT FROM OLD.quantity
       AND (NEW.price       IS DISTINCT FROM OLD.price
         OR NEW.precio_usd  IS DISTINCT FROM OLD.precio_usd
         OR NEW.precio_euro IS DISTINCT FROM OLD.precio_euro)
    THEN
        RAISE WARNING 'OrderDetails %: se ignora el precio enviado (% -> %); el precio es unitario y no se recalcula al cambiar la cantidad (app desactualizada).',
            NEW.id, OLD.price, NEW.price;

        -- Se deja constancia para la bitácora. Se prefija con el id de la
        -- línea porque en un UPDATE de varias filas todos los BEFORE corren
        -- antes que los AFTER: así el AFTER solo usa la nota si es la suya.
        PERFORM set_config(
            'carnavalapp.precio_ignorado',
            NEW.id || '|Se ignoró el precio unitario que envió la app (' ||
            COALESCE(OLD.price::text, 'null') || ' -> ' || COALESCE(NEW.price::text, 'null') ||
            '): el precio no se recalcula al cambiar la cantidad. App del repartidor desactualizada.',
            true);

        NEW.price       := OLD.price;
        NEW.precio_usd  := OLD.precio_usd;
        NEW.precio_euro := OLD.precio_euro;
    END IF;

    -- =====================================================================
    -- TOPE DE STOCK
    -- =====================================================================
    v_delta := COALESCE(NEW.quantity, 0)::numeric - COALESCE(OLD.quantity, 0)::numeric;

    -- Solo interesa cuando se PIDE MÁS que antes.
    IF v_delta <= 0 THEN
        RETURN NEW;
    END IF;

    SELECT COALESCE(stock, 0)::numeric
      INTO v_stock
      FROM carnavalapp."Productos"
     WHERE id = NEW.product_id;

    IF v_stock IS NULL THEN            -- producto inexistente: no interferir
        RETURN NEW;
    END IF;

    IF v_delta > v_stock THEN
        v_permitido := COALESCE(OLD.quantity, 0)::numeric + GREATEST(v_stock, 0);
        RAISE NOTICE 'OrderDetails %: se pidieron % uds pero solo hay % de stock; se topa en %',
            NEW.id, NEW.quantity, v_stock, v_permitido;
        NEW.quantity := v_permitido::smallint;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION carnavalapp.fn_orderdetails_topar_cantidad() IS
'Ignora los precios que la app manda junto a un cambio de cantidad (el precio es unitario) e impide que un aumento de cantidad deje el stock de Productos negativo.';


-- ============================================================================
-- 2) AFTER UPDATE OR DELETE — compensación en public + bitácora
-- ============================================================================
CREATE OR REPLACE FUNCTION carnavalapp.fn_orderdetails_ajustar_erp()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, carnavalapp, pg_temp
AS $$
DECLARE
    -- fila afectada -----------------------------------------------------------
    v_row               carnavalapp."OrderDetails";
    v_es_delete         boolean;
    v_cant_ant          numeric;
    v_cant_new          numeric;
    v_delta             numeric;
    v_precio_ant        numeric;
    v_precio_new        numeric;
    v_accion            text;
    v_sistema           boolean;

    -- contexto ---------------------------------------------------------------
    v_order             carnavalapp."Orders";
    v_es_paqueteria     boolean := false;
    v_producto_nombre   text;
    v_repartidor_nombre text;

    -- actor ------------------------------------------------------------------
    v_uid               uuid;
    v_actor_tipo        text := 'desconocido';
    v_actor_id          bigint;
    v_actor_nombre      text;
    v_actor_tel         text;
    v_actor_rol         text;

    -- ERP --------------------------------------------------------------------
    v_aplicado          boolean := false;
    v_error             text;
    v_producto_erp      bigint;
    v_tienda            bigint;
    v_op_venta          bigint;
    v_op_venta_uuid     uuid;
    v_op_venta_tienda   bigint;
    v_extraccion        public.app_dat_extraccion_productos;
    v_inv_actual        public.app_dat_inventario_productos;
    v_presentacion      bigint;
    v_origen_cambio     smallint;
    v_inv_antes         numeric;
    v_inv_despues       numeric;
    v_mov_pedido        numeric;   -- lo que se pidió mover (abs del delta)
    v_mov_real          numeric;   -- lo que realmente se pudo mover
    v_op_ajuste         bigint;
    v_linea_ajuste      bigint;
    v_precio_unit       numeric;
    v_linea_cant_new    numeric;
    v_importe_venta     numeric;
    v_stock_ajustado    boolean := false;

    -- totales de la orden ----------------------------------------------------
    v_total_cup         numeric;
    v_total_usd         numeric;
    v_total_euro        numeric;

    -- notas ------------------------------------------------------------------
    v_nota_precio       text;
BEGIN
    v_es_delete := (TG_OP = 'DELETE');
    -- Asignación con IF (no con CASE): PL/pgSQL no maneja bien los tipos
    -- compuestos OLD/NEW dentro de una expresión CASE.
    IF v_es_delete THEN
        v_row := OLD;
    ELSE
        v_row := NEW;
    END IF;

    -- ---------------------------------------------------------------------
    -- Cantidades, precios y tipo de acción
    -- ---------------------------------------------------------------------
    IF v_es_delete THEN
        v_cant_ant   := COALESCE(OLD.quantity, 0)::numeric;
        v_cant_new   := 0;
        v_precio_ant := COALESCE(OLD.price, 0)::numeric;
        v_precio_new := v_precio_ant;
        v_accion     := 'eliminacion';
    ELSE
        v_cant_ant   := COALESCE(OLD.quantity, 0)::numeric;
        v_cant_new   := COALESCE(NEW.quantity, 0)::numeric;
        v_precio_ant := COALESCE(OLD.price, 0)::numeric;
        v_precio_new := COALESCE(NEW.price, 0)::numeric;

        -- Nada relevante cambió: no ensuciar la bitácora.
        -- (los triggers de status solo tocan "completada", caen aquí)
        IF v_cant_ant = v_cant_new AND v_precio_ant = v_precio_new THEN
            RETURN NULL;
        END IF;

        v_accion := CASE
                        WHEN v_cant_new > v_cant_ant THEN 'aumento'
                        WHEN v_cant_new < v_cant_ant THEN 'disminucion'
                        ELSE 'cambio_precio'
                    END;
    END IF;

    v_delta := v_cant_new - v_cant_ant;

    -- ¿Lo hizo otro trigger (creación de orden sin stock, borrado en cascada)
    -- y no una persona?
    v_sistema := (pg_trigger_depth() > 1);
    IF v_sistema THEN
        v_accion := 'ajuste_sistema';
        v_error  := 'Cambio provocado por otro trigger (recorte por falta de stock al crear la orden, ' ||
                    'o borrado en cascada de la orden/producto). No se compensa inventario para no duplicar movimientos.';
    END IF;

    -- ---------------------------------------------------------------------
    -- Contexto: orden, producto, repartidor
    -- ---------------------------------------------------------------------
    SELECT * INTO v_order FROM carnavalapp."Orders" WHERE id = v_row.order_id;

    v_es_paqueteria := COALESCE(
        v_order.paqueteria IS NOT NULL
        AND v_order.paqueteria <> 'null'::jsonb
        AND jsonb_typeof(v_order.paqueteria) = 'object'
        AND v_order.paqueteria <> '{}'::jsonb,
        false
    );

    SELECT name INTO v_producto_nombre
      FROM carnavalapp."Productos" WHERE id = v_row.product_id;

    IF v_order.repartidor IS NOT NULL THEN
        SELECT nombre INTO v_repartidor_nombre
          FROM carnavalapp.repartidores WHERE id = v_order.repartidor;
    END IF;

    -- ---------------------------------------------------------------------
    -- ¿Quién lo hizo?
    -- ---------------------------------------------------------------------
    IF v_sistema THEN
        v_actor_tipo := 'sistema';
    ELSE
        BEGIN
            v_uid := auth.uid();
        EXCEPTION WHEN OTHERS THEN
            v_uid := NULL;
        END;

        IF v_uid IS NOT NULL THEN
            SELECT id, nombre, telefono::text
              INTO v_actor_id, v_actor_nombre, v_actor_tel
              FROM carnavalapp.repartidores
             WHERE uuid = v_uid
             LIMIT 1;

            IF v_actor_id IS NOT NULL THEN
                v_actor_tipo := 'repartidor';
            ELSE
                SELECT id, name, telefono::text, rol
                  INTO v_actor_id, v_actor_nombre, v_actor_tel, v_actor_rol
                  FROM carnavalapp."Usuarios"
                 WHERE uuid = v_uid
                 LIMIT 1;

                IF v_actor_id IS NOT NULL THEN
                    v_actor_tipo := 'usuario';
                END IF;
            END IF;
        END IF;
    END IF;

    -- =====================================================================
    -- COMPENSACIÓN EN public (todo o nada; cualquier fallo queda en erp_error)
    -- =====================================================================
    BEGIN
      <<erp>>
      BEGIN
        IF v_sistema THEN
            EXIT erp;                                  -- v_error ya explicado
        END IF;

        IF v_delta = 0 THEN
            v_error := 'Solo cambió el precio: se recalcula el dinero, no hay movimiento de inventario.';
        END IF;

        IF v_es_paqueteria THEN
            v_error := 'Orden de paquetería: no genera operaciones en Inventtia.';
            EXIT erp;
        END IF;

        SELECT id INTO v_producto_erp
          FROM public.app_dat_producto
         WHERE id_vendedor_app = v_row.product_id
         LIMIT 1;

        IF v_producto_erp IS NULL THEN
            v_error := 'El producto Carnaval ' || v_row.product_id ||
                       ' no está mapeado a ningún app_dat_producto (id_vendedor_app).';
            EXIT erp;
        END IF;

        IF v_row.proveedor IS NOT NULL THEN
            SELECT id INTO v_tienda
              FROM public.app_dat_tienda
             WHERE id_tienda_carnaval = v_row.proveedor
             LIMIT 1;

            -- Si la línea dice de qué proveedor es pero ese proveedor no
            -- corresponde a ninguna tienda Inventtia, NO se sigue: en una orden
            -- con varios proveedores acabaríamos ajustando la venta de otro.
            IF v_tienda IS NULL THEN
                v_error := 'El proveedor ' || v_row.proveedor ||
                           ' no corresponde a ninguna tienda (app_dat_tienda.id_tienda_carnaval). Ajustar a mano.';
                EXIT erp;
            END IF;
        END IF;

        -- Venta original: SIEMPRE id_tipo_operacion = 2, así los ajustes
        -- (tipo 5 / 24) que creamos aquí nunca se confunden con la venta.
        SELECT o.id, o.uuid, o.id_tienda
          INTO v_op_venta, v_op_venta_uuid, v_op_venta_tienda
          FROM public.app_dat_operaciones o
         WHERE o.id_tipo_operacion = 2
           AND (o.id_carnaval_order = v_row.order_id
                OR o.observaciones = 'Venta desde orden ' || v_row.order_id)
           AND (v_tienda IS NULL OR o.id_tienda = v_tienda)
         ORDER BY o.id DESC
         LIMIT 1;

        IF v_op_venta IS NULL THEN
            v_error := 'No existe operación de venta (tipo 2) para la orden ' ||
                       v_row.order_id || COALESCE(' / tienda ' || v_tienda, '') || '.';
            EXIT erp;
        END IF;

        v_tienda := COALESCE(v_tienda, v_op_venta_tienda);

        -- Línea de extracción de esa venta para este producto.
        SELECT * INTO v_extraccion
          FROM public.app_dat_extraccion_productos
         WHERE id_operacion = v_op_venta
           AND id_producto  = v_producto_erp
         ORDER BY id DESC
         LIMIT 1;

        IF v_extraccion.id IS NULL THEN
            -- Sin la línea de la venta no sabemos de qué ubicación/variante salió.
            -- Se registra en bitácora para arreglo manual en vez de adivinar.
            v_error := 'La venta ' || v_op_venta || ' no tiene línea de extracción para el producto ERP ' ||
                       v_producto_erp || ': no se puede determinar ubicación/variante. Ajustar a mano.';
            EXIT erp;
        END IF;

        -- Último inventario de esa ubicación/variante (mismo criterio que cancelación).
        SELECT * INTO v_inv_actual
          FROM public.app_dat_inventario_productos
         WHERE id_producto = v_extraccion.id_producto
           AND id_variante         IS NOT DISTINCT FROM v_extraccion.id_variante
           AND id_opcion_variante  IS NOT DISTINCT FROM v_extraccion.id_opcion_variante
           AND id_ubicacion        IS NOT DISTINCT FROM v_extraccion.id_ubicacion
         ORDER BY created_at DESC, id DESC
         LIMIT 1;

        v_presentacion := COALESCE(v_extraccion.id_presentacion, v_inv_actual.id_presentacion);
        IF v_presentacion IS NULL THEN
            -- id_presentacion referencia app_dat_producto_presentacion(id);
            -- se prefiere la presentación base del producto.
            SELECT id INTO v_presentacion
              FROM public.app_dat_producto_presentacion
             WHERE id_producto = v_producto_erp
             ORDER BY es_base DESC, id ASC
             LIMIT 1;
        END IF;

        IF v_presentacion IS NULL THEN
            v_error := 'El producto ERP ' || v_producto_erp || ' no tiene presentación: no se puede mover inventario.';
            EXIT erp;
        END IF;

        v_inv_antes   := COALESCE(v_inv_actual.cantidad_final, 0);
        v_precio_unit := COALESCE(NULLIF(v_precio_new, 0),
                                  v_extraccion.precio_unitario,
                                  v_precio_ant, 0);

        -- -----------------------------------------------------------------
        -- Solo cambió el precio: dinero sí, inventario no.
        -- -----------------------------------------------------------------
        IF v_delta = 0 THEN
            UPDATE public.app_dat_extraccion_productos
               SET precio_unitario = v_precio_unit,
                   importe         = COALESCE(cantidad, 0) * v_precio_unit,
                   importe_real    = COALESCE(cantidad, 0) * v_precio_unit
             WHERE id = v_extraccion.id;

            v_inv_despues := v_inv_antes;
            v_aplicado    := true;
        ELSE
            v_mov_pedido := ABS(v_delta);

            IF v_delta < 0 THEN
                -- ============ EL CLIENTE DEVOLVIÓ -> ENTRADA (tipo 5) ============
                v_origen_cambio := 5;
                -- Nunca devolver más de lo que realmente salió: la venta pudo
                -- haberse recortado al crearse por falta de stock, o ya haber
                -- recibido otro ajuste.
                v_mov_real    := LEAST(v_mov_pedido, COALESCE(v_extraccion.cantidad, 0));
                v_inv_despues := v_inv_antes + v_mov_real;

                IF v_mov_real < v_mov_pedido THEN
                    v_error := 'Se quitaron ' || v_mov_pedido || ' uds pero la venta solo tiene ' ||
                               COALESCE(v_extraccion.cantidad, 0) || ' extraídas. Se devolvieron ' ||
                               v_mov_real || '.';
                END IF;

                IF v_mov_real > 0 THEN
                    INSERT INTO public.app_dat_operaciones (
                        id_tipo_operacion, id_tienda, uuid, observaciones, created_at, id_carnaval_order
                    ) VALUES (
                        5, v_tienda, COALESCE(v_uid, v_op_venta_uuid),
                        'Devolución de cliente por ajuste de línea en orden Carnaval ' || v_row.order_id ||
                        ' (producto ' || COALESCE(v_producto_nombre, v_row.product_id::text) ||
                        ', ' || v_mov_real || ' uds)',
                        now(), v_row.order_id
                    ) RETURNING id INTO v_op_ajuste;

                    INSERT INTO public.app_dat_operacion_recepcion (
                        id_operacion, entregado_por, recibido_por, monto_total, observaciones, motivo
                    ) VALUES (
                        v_op_ajuste,
                        COALESCE(v_repartidor_nombre, 'Repartidor Carnaval'),
                        COALESCE(v_actor_nombre, 'Sistema Carnaval'),
                        v_mov_real * v_precio_unit,
                        'Devolución por ajuste de cantidad en orden ' || v_row.order_id,
                        3   -- app_nom_motivo_recepcion: Devolución
                    );

                    INSERT INTO public.app_dat_recepcion_productos (
                        id_operacion, id_producto, id_variante, id_opcion_variante,
                        id_ubicacion, id_presentacion, cantidad, precio_unitario,
                        sku_producto, sku_ubicacion
                    ) VALUES (
                        v_op_ajuste, v_extraccion.id_producto, v_extraccion.id_variante,
                        v_extraccion.id_opcion_variante, v_extraccion.id_ubicacion,
                        v_presentacion, v_mov_real, v_precio_unit,
                        v_extraccion.sku_producto, v_extraccion.sku_ubicacion
                    ) RETURNING id INTO v_linea_ajuste;

                    INSERT INTO public.app_dat_inventario_productos (
                        id_producto, id_variante, id_opcion_variante, id_ubicacion,
                        id_presentacion, cantidad_inicial, cantidad_final,
                        sku_producto, sku_ubicacion, origen_cambio, id_recepcion,
                        id_proveedor, created_at
                    ) VALUES (
                        v_extraccion.id_producto, v_extraccion.id_variante,
                        v_extraccion.id_opcion_variante, v_extraccion.id_ubicacion,
                        v_presentacion, v_inv_antes, v_inv_despues,
                        v_extraccion.sku_producto, v_extraccion.sku_ubicacion,
                        v_origen_cambio, v_linea_ajuste,
                        v_inv_actual.id_proveedor, now()
                    );
                END IF;
            ELSE
                -- ============ EL CLIENTE QUISO MÁS -> SALIDA (tipo 24) ===========
                v_origen_cambio := 24;
                -- que NO quede sin stock: solo se saca lo que hay
                v_mov_real    := LEAST(v_mov_pedido, GREATEST(v_inv_antes, 0));
                v_inv_despues := v_inv_antes - v_mov_real;

                IF v_mov_real < v_mov_pedido THEN
                    v_error := 'Stock insuficiente en Inventtia: se pidieron ' || v_mov_pedido ||
                               ' uds y solo había ' || v_inv_antes || '. Se extrajeron ' || v_mov_real || '.';
                END IF;

                IF v_mov_real > 0 THEN
                    INSERT INTO public.app_dat_operaciones (
                        id_tipo_operacion, id_tienda, uuid, observaciones, created_at, id_carnaval_order
                    ) VALUES (
                        24, v_tienda, COALESCE(v_uid, v_op_venta_uuid),
                        'Ajuste por error en cantidades de la orden Carnaval ' || v_row.order_id ||
                        ' (producto ' || COALESCE(v_producto_nombre, v_row.product_id::text) ||
                        ', +' || v_mov_real || ' uds)',
                        now(), v_row.order_id
                    ) RETURNING id INTO v_op_ajuste;

                    INSERT INTO public.app_dat_operacion_extraccion (
                        id_operacion, id_motivo_operacion, observaciones,
                        autorizado_por, entregado_por, recibido_por
                    ) VALUES (
                        v_op_ajuste,
                        14,  -- app_nom_motivo_extraccion: Venta online
                        'Cantidad adicional pedida por el cliente en la orden ' || v_row.order_id,
                        COALESCE(v_actor_nombre, 'Sistema Carnaval'),
                        COALESCE(v_actor_nombre, 'Sistema Carnaval'),
                        COALESCE(v_repartidor_nombre, 'Repartidor Carnaval')
                    );

                    INSERT INTO public.app_dat_extraccion_productos (
                        id_operacion, id_producto, id_variante, id_opcion_variante,
                        id_ubicacion, id_presentacion, cantidad, precio_unitario,
                        importe, importe_real, sku_producto, sku_ubicacion
                    ) VALUES (
                        v_op_ajuste, v_extraccion.id_producto, v_extraccion.id_variante,
                        v_extraccion.id_opcion_variante, v_extraccion.id_ubicacion,
                        v_presentacion, v_mov_real, v_precio_unit,
                        v_mov_real * v_precio_unit, v_mov_real * v_precio_unit,
                        v_extraccion.sku_producto, v_extraccion.sku_ubicacion
                    ) RETURNING id INTO v_linea_ajuste;

                    INSERT INTO public.app_dat_inventario_productos (
                        id_producto, id_variante, id_opcion_variante, id_ubicacion,
                        id_presentacion, cantidad_inicial, cantidad_final,
                        sku_producto, sku_ubicacion, origen_cambio, id_extraccion,
                        id_proveedor, created_at
                    ) VALUES (
                        v_extraccion.id_producto, v_extraccion.id_variante,
                        v_extraccion.id_opcion_variante, v_extraccion.id_ubicacion,
                        v_presentacion, v_inv_antes, v_inv_despues,
                        v_extraccion.sku_producto, v_extraccion.sku_ubicacion,
                        v_origen_cambio, v_linea_ajuste,
                        v_inv_actual.id_proveedor, now()
                    );
                END IF;
            END IF;

            -- Estado "completada" de la operación de ajuste.
            -- comentario NUNCA nulo y NUNCA con la frase 'Venta desde orden N'
            -- (fn_sincronizar_estado_orden_inverso la usa para matchear).
            IF v_op_ajuste IS NOT NULL THEN
                INSERT INTO public.app_dat_estado_operacion (
                    id_operacion, estado, uuid, comentario
                ) VALUES (
                    v_op_ajuste, 2, COALESCE(v_uid, v_op_venta_uuid),
                    'Ajuste automático de línea (orden Carnaval ' || v_row.order_id ||
                    ', ' || v_accion || ', ' || v_mov_real || ' uds)'
                );
            END IF;

            -- -------------------------------------------------------------
            -- La VENTA original queda con la cantidad y el dinero REALES.
            -- Nunca se borra la línea: id_extraccion es ON DELETE CASCADE y
            -- borrarla se llevaría el historial de inventario por delante.
            -- -------------------------------------------------------------
            v_linea_cant_new := GREATEST(
                0,
                COALESCE(v_extraccion.cantidad, 0) +
                CASE WHEN v_delta < 0 THEN -v_mov_real ELSE v_mov_real END
            );

            UPDATE public.app_dat_extraccion_productos
               SET cantidad        = v_linea_cant_new,
                   precio_unitario = v_precio_unit,
                   importe         = v_linea_cant_new * v_precio_unit,
                   importe_real    = v_linea_cant_new * v_precio_unit
             WHERE id = v_extraccion.id;

            -- Solo se considera aplicado si de verdad se movió inventario.
            -- Si v_mov_real = 0 (no había stock, o la venta ya no tenía qué
            -- devolver) el dinero sí se corrige, pero queda en bitácora como
            -- NO aplicado con su erp_error para revisarlo.
            v_aplicado := (v_mov_real > 0);
        END IF;

        -- -----------------------------------------------------------------
        -- Dinero de la venta: misma fórmula que fn_crear_operacion_desde_orden2
        -- -----------------------------------------------------------------
        SELECT COALESCE(SUM(od.price::numeric * COALESCE(od.quantity, 1)), 0)
          INTO v_importe_venta
          FROM carnavalapp."OrderDetails" od
         WHERE od.order_id  = v_row.order_id
           AND od.proveedor IS NOT DISTINCT FROM v_row.proveedor;

        UPDATE public.app_dat_operacion_venta
           SET importe_total = v_importe_venta
         WHERE id_operacion = v_op_venta;

        UPDATE public.app_dat_pago_venta
           SET monto = v_importe_venta
         WHERE id_operacion_venta = v_op_venta;
      END;
    EXCEPTION WHEN OTHERS THEN
        -- El sub-bloque se revierte solo; el cambio en OrderDetails y la
        -- bitácora se conservan para que quede constancia del problema.
        v_aplicado := false;
        v_error    := 'Excepción al ajustar Inventtia: ' || SQLERRM;
    END;

    -- ---------------------------------------------------------------------
    -- TOTALES DE LA ORDEN (carnavalapp."Orders")
    -- ---------------------------------------------------------------------
    -- Se recalculan desde las líneas que quedan, igual que hace la app:
    --   total = SUM(price * quantity)  (price es UNITARIO)
    -- Sobre TODAS las líneas de la orden, de todos los proveedores — a
    -- diferencia del importe de la venta, que es por tienda. El envío va
    -- aparte en costo_envio y no se toca aquí.
    --
    -- Se corre siempre (aunque la compensación del ERP no haya podido
    -- aplicarse) porque el dinero que se le cobra al cliente tiene que
    -- cuadrar con las líneas sí o sí.
    --
    -- Solo se ESCRIBE si lo guardado está mal: "Orders" tiene dos triggers
    -- HTTP (notificar-proveedores-orden, notificar_orden_asignada) que corren
    -- en CADA update sin condición, así que un update de gratis son dos
    -- llamadas a edge functions de gratis.
    --
    -- totalUsd/totalEuro solo se tocan si TODAS las líneas tienen precio en
    -- esa moneda; si no, SUM() ignoraría las nulas y daría un total corto
    -- (hay 262 órdenes viejas, anteriores a mayo 2025, sin precios en divisa).
    IF v_row.order_id IS NOT NULL THEN
        BEGIN
            SELECT COALESCE(SUM(od.price::numeric * COALESCE(od.quantity, 1)), 0),
                   CASE WHEN count(*) = count(od.precio_usd)
                        THEN COALESCE(SUM(od.precio_usd::numeric  * COALESCE(od.quantity, 1)), 0) END,
                   CASE WHEN count(*) = count(od.precio_euro)
                        THEN COALESCE(SUM(od.precio_euro::numeric * COALESCE(od.quantity, 1)), 0) END
              INTO v_total_cup, v_total_usd, v_total_euro
              FROM carnavalapp."OrderDetails" od
             WHERE od.order_id = v_row.order_id;

            -- La tolerancia absorbe el ruido de float4 (total, totalUsd y
            -- totalEuro son real): sin ella se reescribiría el mismo valor
            -- una y otra vez por diferencias en el sexto decimal.
            UPDATE carnavalapp."Orders" o
               SET total       = v_total_cup,
                   "totalUsd"  = COALESCE(v_total_usd,  o."totalUsd"),
                   "totalEuro" = COALESCE(v_total_euro, o."totalEuro")
             WHERE o.id = v_row.order_id
               AND (
                     ABS(COALESCE(o.total, 0)::numeric - v_total_cup)
                         > GREATEST(0.01, ABS(v_total_cup) * 0.000001)
                  OR (v_total_usd IS NOT NULL
                      AND ABS(COALESCE(o."totalUsd", 0)::numeric - v_total_usd)
                          > GREATEST(0.01, ABS(v_total_usd) * 0.000001))
                  OR (v_total_euro IS NOT NULL
                      AND ABS(COALESCE(o."totalEuro", 0)::numeric - v_total_euro)
                          > GREATEST(0.01, ABS(v_total_euro) * 0.000001))
                   );

        EXCEPTION WHEN OTHERS THEN
            -- Si la orden se está borrando en cascada esto no encuentra fila y
            -- no pasa nada. Cualquier otro fallo queda anotado, no tumba nada.
            v_error := COALESCE(v_error || ' | ', '') ||
                       'No se pudieron recalcular los totales de la orden: ' || SQLERRM;
        END;
    END IF;

    -- ---------------------------------------------------------------------
    -- Stock de Carnaval: SOLO si el ERP no lo sincronizó
    -- (fn_sincronizar_stock_producto ya lo pone en valor absoluto).
    -- ---------------------------------------------------------------------
    IF NOT v_aplicado AND NOT v_sistema AND v_delta <> 0 THEN
        BEGIN
            UPDATE carnavalapp."Productos"
               SET stock = GREATEST(0, COALESCE(stock, 0) - v_delta)
             WHERE id = v_row.product_id;
            v_stock_ajustado := true;
        EXCEPTION WHEN OTHERS THEN
            -- p.ej. block_proveedor_3 en Productos
            v_error := COALESCE(v_error || ' | ', '') ||
                       'No se pudo ajustar stock en Carnaval: ' || SQLERRM;
        END;
    END IF;

    -- ---------------------------------------------------------------------
    -- BITÁCORA DE CAPITÁN — siempre se escribe
    -- ---------------------------------------------------------------------
    -- Si el BEFORE descartó un precio, la nota viene prefijada con el id de la
    -- línea: solo se usa si es de ESTA línea (ver fn_orderdetails_topar_cantidad).
    v_nota_precio := NULLIF(current_setting('carnavalapp.precio_ignorado', true), '');
    IF v_nota_precio IS NOT NULL THEN
        IF split_part(v_nota_precio, '|', 1) = v_row.id::text THEN
            v_nota_precio := substr(v_nota_precio, strpos(v_nota_precio, '|') + 1);
        ELSE
            v_nota_precio := NULL;
        END IF;
    END IF;

    INSERT INTO carnavalapp.order_details_bitacora (
        accion, origen_tg, order_id, order_detail_id, product_id, producto_nombre,
        proveedor, order_status,
        cantidad_anterior, cantidad_nueva, delta,
        precio_anterior, precio_nuevo, importe_anterior, importe_nuevo, importe_delta,
        actor_uuid, actor_tipo, actor_id, actor_nombre, actor_telefono, actor_rol,
        repartidor_id, repartidor_nombre, cajero,
        motivo, nota,
        aplicado_erp, erp_error, origen_cambio, id_tienda, id_producto_erp,
        id_operacion_venta, id_operacion_ajuste, id_linea_ajuste,
        inventario_antes, inventario_despues, stock_carnaval_ajustado
    ) VALUES (
        v_accion, TG_OP, v_row.order_id, v_row.id, v_row.product_id, v_producto_nombre,
        v_row.proveedor, v_order.status,
        v_cant_ant, v_cant_new, v_delta,
        v_precio_ant, v_precio_new,
        v_cant_ant * v_precio_ant, v_cant_new * v_precio_new,
        (v_cant_new * v_precio_new) - (v_cant_ant * v_precio_ant),
        v_uid, v_actor_tipo, v_actor_id, v_actor_nombre, v_actor_tel, v_actor_rol,
        v_order.repartidor, v_repartidor_nombre, v_row.cajero,
        NULLIF(current_setting('carnavalapp.motivo_cambio', true), ''),
        NULLIF(concat_ws(' | ',
                   NULLIF(current_setting('carnavalapp.nota_cambio', true), ''),
                   v_nota_precio), ''),
        v_aplicado, v_error, v_origen_cambio, v_tienda, v_producto_erp,
        v_op_venta, v_op_ajuste, v_linea_ajuste,
        v_inv_antes, v_inv_despues, v_stock_ajustado
    );

    RETURN NULL;   -- trigger AFTER: el valor de retorno se ignora

EXCEPTION WHEN OTHERS THEN
    -- La bitácora/compensación NUNCA debe tumbar la operación del repartidor.
    RAISE WARNING 'fn_orderdetails_ajustar_erp falló en OrderDetail % (%): %',
        v_row.id, TG_OP, SQLERRM;
    RETURN NULL;   -- trigger AFTER: el valor de retorno se ignora
END;
$$;

COMMENT ON FUNCTION carnavalapp.fn_orderdetails_ajustar_erp() IS
'Al variar cantidad/precio o borrar una línea de OrderDetails: ajusta inventario y operaciones en public (origen_cambio 5 devolución / 24 error en cantidades), corrige la venta, recalcula los totales de la orden y escribe la bitácora de capitán.';


-- ============================================================================
-- 3) Triggers
-- ============================================================================
DROP TRIGGER IF EXISTS trg_orderdetails_topar_cantidad ON carnavalapp."OrderDetails";
CREATE TRIGGER trg_orderdetails_topar_cantidad
    BEFORE UPDATE OF quantity ON carnavalapp."OrderDetails"
    FOR EACH ROW
    EXECUTE FUNCTION carnavalapp.fn_orderdetails_topar_cantidad();

DROP TRIGGER IF EXISTS trg_orderdetails_ajustar_erp_upd ON carnavalapp."OrderDetails";
CREATE TRIGGER trg_orderdetails_ajustar_erp_upd
    AFTER UPDATE ON carnavalapp."OrderDetails"
    FOR EACH ROW
    EXECUTE FUNCTION carnavalapp.fn_orderdetails_ajustar_erp();

DROP TRIGGER IF EXISTS trg_orderdetails_ajustar_erp_del ON carnavalapp."OrderDetails";
CREATE TRIGGER trg_orderdetails_ajustar_erp_del
    AFTER DELETE ON carnavalapp."OrderDetails"
    FOR EACH ROW
    EXECUTE FUNCTION carnavalapp.fn_orderdetails_ajustar_erp();


-- ============================================================================
-- 4) Verificación rápida (correr después de aplicar)
-- ============================================================================
-- SELECT tgname, pg_get_triggerdef(oid)
--   FROM pg_trigger
--  WHERE tgrelid = 'carnavalapp."OrderDetails"'::regclass AND NOT tgisinternal
--  ORDER BY tgname;
--
-- Últimos movimientos registrados:
-- SELECT * FROM carnavalapp.v_bitacora_capitan LIMIT 50;
--
-- Cambios que NO se pudieron reflejar en Inventtia (revisar a mano):
-- SELECT id, created_at, order_id, producto_nombre, delta, erp_error
--   FROM carnavalapp.order_details_bitacora
--  WHERE NOT aplicado_erp AND accion <> 'ajuste_sistema'
--  ORDER BY created_at DESC;
