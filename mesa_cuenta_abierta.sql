-- ============================================================================
-- VentIQ - Modo Restaurante: CUENTAS ABIERTAS por mesa
-- ============================================================================
-- Estado intermedio entre "mesa libre" y "orden registrada".
--
-- Cuando el vendedor toca "Nueva Cuenta" en una mesa, se crea una fila en
-- app_dat_mesa_cuenta_abierta (cabecera) y los productos que va agregando se
-- guardan en app_dat_mesa_cuenta_item. NADA toca inventario hasta que el
-- vendedor decida "Cerrar Nota" — entonces fn_cerrar_cuenta_mesa convierte
-- la cuenta en los parámetros que ya espera fn_registrar_venta_mesa, y todo
-- el flujo normal de venta corre como siempre.
--
-- Ventajas frente a guardar la preorden sólo en memoria local:
--   - Sobrevive a cierres de app / cambios de dispositivo.
--   - Varios vendedores ven el mismo estado en tiempo real.
--   - La mesa queda "ocupada" en BD aunque el vendedor cambie de pantalla.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. TABLAS
-- ----------------------------------------------------------------------------

-- Cabecera: una fila por cuenta abierta de una mesa.
CREATE TABLE IF NOT EXISTS public.app_dat_mesa_cuenta_abierta
(
    id              bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_mesa         bigint      NOT NULL,
    id_tienda       bigint      NOT NULL,
    id_tpv          bigint,                                  -- TPV que abrió la cuenta (para filtrar por punto de venta)
    id_vendedor     bigint,                                  -- vendedor que abrió la cuenta (opcional, para auditoría)
    numero_comensales smallint,                              -- cantidad de comensales (opcional, capturable luego)
    notas           text,                                    -- notas internas de la cuenta
    estado          smallint    NOT NULL DEFAULT 1,          -- 1=Abierta, 2=Cerrada (registrada como venta), 3=Cancelada
    id_operacion_venta bigint,                               -- se rellena al cerrar la nota (vinculo a la venta real)
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    closed_at       timestamptz,
    CONSTRAINT app_dat_mesa_cuenta_mesa_fkey
        FOREIGN KEY (id_mesa) REFERENCES public.app_dat_mesas (id) ON DELETE CASCADE,
    CONSTRAINT app_dat_mesa_cuenta_tienda_fkey
        FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda (id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_mesa_cuenta_abierta_mesa_estado
    ON public.app_dat_mesa_cuenta_abierta (id_mesa, estado);
CREATE INDEX IF NOT EXISTS idx_mesa_cuenta_abierta_tienda_estado
    ON public.app_dat_mesa_cuenta_abierta (id_tienda, estado);

COMMENT ON TABLE  public.app_dat_mesa_cuenta_abierta IS 'Cabecera de cuenta abierta de una mesa antes del cierre/cobro.';
COMMENT ON COLUMN public.app_dat_mesa_cuenta_abierta.estado IS '1=Abierta, 2=Cerrada (convertida en venta), 3=Cancelada.';
COMMENT ON COLUMN public.app_dat_mesa_cuenta_abierta.id_operacion_venta IS 'Si está cerrada, apunta a la operación de venta real generada.';


-- Líneas: productos agregados a una cuenta abierta.
CREATE TABLE IF NOT EXISTS public.app_dat_mesa_cuenta_item
(
    id              bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_cuenta       bigint      NOT NULL,
    id_producto     bigint      NOT NULL,
    id_variante     bigint,
    id_opcion_variante bigint,
    id_presentacion bigint,
    id_ubicacion    bigint,                                  -- ubicación de almacén desde donde se vende
    cantidad        numeric(14,3) NOT NULL,
    precio_unitario numeric(14,2) NOT NULL,
    precio_base     numeric(14,2),                           -- precio "lista" antes de promoción (para comparar)
    id_metodo_pago  bigint,                                  -- metodo de pago por línea (opcional, se decide al cerrar)
    promotion_data  jsonb,                                   -- datos de promoción aplicada (replica de OrderItem.promotionData)
    inventory_data  jsonb,                                   -- ids de variante/presentacion/ubicacion serializados
    notas           text,                                    -- notas del item (ej. "sin cebolla")
    sku_producto    varchar,
    sku_ubicacion   varchar,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT app_dat_mesa_cuenta_item_cuenta_fkey
        FOREIGN KEY (id_cuenta) REFERENCES public.app_dat_mesa_cuenta_abierta (id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_mesa_cuenta_item_cuenta
    ON public.app_dat_mesa_cuenta_item (id_cuenta);

COMMENT ON TABLE  public.app_dat_mesa_cuenta_item IS 'Líneas de productos de una cuenta abierta de mesa (estado intermedio antes del checkout).';


-- ----------------------------------------------------------------------------
-- 2. RPCs
-- ----------------------------------------------------------------------------

-- 2.1 Abrir una cuenta nueva en una mesa.
-- Si la mesa ya tiene una cuenta abierta, NO crea otra: devuelve la existente.
-- Esto permite que el botón "Nueva Cuenta" sea idempotente y que distintos
-- dispositivos compartan la misma cuenta abierta.
CREATE OR REPLACE FUNCTION public.fn_abrir_cuenta_mesa(
    p_id_mesa         bigint,
    p_id_tpv          bigint  DEFAULT NULL,
    p_id_vendedor     bigint  DEFAULT NULL,
    p_numero_comensales smallint DEFAULT NULL,
    p_forzar_nueva    boolean DEFAULT false
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_tienda bigint;
    v_id_cuenta bigint;
BEGIN
    -- Validar mesa
    SELECT id_tienda INTO v_id_tienda
    FROM public.app_dat_mesas
    WHERE id = p_id_mesa AND activa = true;

    IF v_id_tienda IS NULL THEN
        RAISE EXCEPTION 'Mesa % no existe o está inactiva', p_id_mesa
            USING ERRCODE = 'P0001';
    END IF;

    IF NOT p_forzar_nueva THEN
        -- Reusar cuenta abierta existente (si la hay)
        SELECT id INTO v_id_cuenta
        FROM public.app_dat_mesa_cuenta_abierta
        WHERE id_mesa = p_id_mesa AND estado = 1
        ORDER BY created_at ASC
        LIMIT 1;

        IF v_id_cuenta IS NOT NULL THEN
            RETURN v_id_cuenta;
        END IF;
    END IF;

    INSERT INTO public.app_dat_mesa_cuenta_abierta
        (id_mesa, id_tienda, id_tpv, id_vendedor, numero_comensales, estado)
    VALUES
        (p_id_mesa, v_id_tienda, p_id_tpv, p_id_vendedor, p_numero_comensales, 1)
    RETURNING id INTO v_id_cuenta;

    RETURN v_id_cuenta;
END;
$$;


-- 2.2 Listar cuentas abiertas de una mesa (cabecera + total calculado).
CREATE OR REPLACE FUNCTION public.fn_listar_cuentas_mesa(
    p_id_mesa bigint
)
RETURNS TABLE (
    id                  bigint,
    id_mesa             bigint,
    id_tpv              bigint,
    id_vendedor         bigint,
    numero_comensales   smallint,
    notas               text,
    estado              smallint,
    total               numeric,
    cantidad_items      integer,
    created_at          timestamptz,
    updated_at          timestamptz
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        c.id,
        c.id_mesa,
        c.id_tpv,
        c.id_vendedor,
        c.numero_comensales,
        c.notas,
        c.estado,
        COALESCE(SUM(i.cantidad * i.precio_unitario), 0)::numeric AS total,
        COUNT(i.id)::int AS cantidad_items,
        c.created_at,
        c.updated_at
    FROM public.app_dat_mesa_cuenta_abierta c
    LEFT JOIN public.app_dat_mesa_cuenta_item i ON i.id_cuenta = c.id
    WHERE c.id_mesa = p_id_mesa AND c.estado = 1
    GROUP BY c.id
    ORDER BY c.created_at ASC;
$$;


-- 2.3 Obtener detalle completo de una cuenta (cabecera + items + producto info).
CREATE OR REPLACE FUNCTION public.fn_obtener_cuenta_mesa(
    p_id_cuenta bigint
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result jsonb;
BEGIN
    SELECT jsonb_build_object(
        'id', c.id,
        'id_mesa', c.id_mesa,
        'mesa_numero', m.numero,
        'mesa_zona', m.zona,
        'id_tpv', c.id_tpv,
        'id_vendedor', c.id_vendedor,
        'numero_comensales', c.numero_comensales,
        'notas', c.notas,
        'estado', c.estado,
        'created_at', c.created_at,
        'updated_at', c.updated_at,
        'items', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'id', i.id,
                'id_producto', i.id_producto,
                'producto_nombre', p.denominacion,
                'producto_sku', i.sku_producto,
                'producto_es_elaborado', p.es_elaborado,
                'producto_es_servicio', p.es_servicio,
                'id_variante', i.id_variante,
                'id_opcion_variante', i.id_opcion_variante,
                'variante_nombre',
                    CASE WHEN i.id_opcion_variante IS NOT NULL THEN
                        (SELECT ao.valor FROM public.app_dat_atributo_opcion ao
                         WHERE ao.id = i.id_opcion_variante LIMIT 1)
                    ELSE NULL END,
                'id_presentacion', i.id_presentacion,
                'presentacion_nombre',
                    CASE WHEN i.id_presentacion IS NOT NULL THEN
                        (SELECT pr.denominacion FROM public.app_nom_presentacion pr
                         WHERE pr.id = i.id_presentacion LIMIT 1)
                    ELSE NULL END,
                'id_ubicacion', i.id_ubicacion,
                'ubicacion_nombre',
                    CASE WHEN i.id_ubicacion IS NOT NULL THEN
                        (SELECT la.denominacion FROM public.app_dat_layout_almacen la
                         WHERE la.id = i.id_ubicacion LIMIT 1)
                    ELSE NULL END,
                'cantidad', i.cantidad,
                'precio_unitario', i.precio_unitario,
                'precio_base', i.precio_base,
                'subtotal', (i.cantidad * i.precio_unitario)::numeric,
                'id_metodo_pago', i.id_metodo_pago,
                'promotion_data', i.promotion_data,
                'inventory_data', i.inventory_data,
                'notas', i.notas,
                'sku_producto', i.sku_producto,
                'sku_ubicacion', i.sku_ubicacion,
                'created_at', i.created_at
            ) ORDER BY i.created_at ASC)
            FROM public.app_dat_mesa_cuenta_item i
            LEFT JOIN public.app_dat_producto p ON p.id = i.id_producto
            WHERE i.id_cuenta = c.id
        ), '[]'::jsonb),
        'total', COALESCE((
            SELECT SUM(i.cantidad * i.precio_unitario)
            FROM public.app_dat_mesa_cuenta_item i
            WHERE i.id_cuenta = c.id
        ), 0)::numeric
    ) INTO v_result
    FROM public.app_dat_mesa_cuenta_abierta c
    LEFT JOIN public.app_dat_mesas m ON m.id = c.id_mesa
    WHERE c.id = p_id_cuenta;

    IF v_result IS NULL THEN
        RAISE EXCEPTION 'Cuenta % no encontrada', p_id_cuenta USING ERRCODE = 'P0001';
    END IF;

    RETURN v_result;
END;
$$;


-- 2.4 Agregar item a la cuenta (consolida si ya existe el mismo producto+variante+presentacion+ubicacion).
CREATE OR REPLACE FUNCTION public.fn_agregar_item_cuenta_mesa(
    p_id_cuenta         bigint,
    p_id_producto       bigint,
    p_cantidad          numeric,
    p_precio_unitario   numeric,
    p_id_variante       bigint  DEFAULT NULL,
    p_id_opcion_variante bigint DEFAULT NULL,
    p_id_presentacion   bigint  DEFAULT NULL,
    p_id_ubicacion      bigint  DEFAULT NULL,
    p_precio_base       numeric DEFAULT NULL,
    p_id_metodo_pago    bigint  DEFAULT NULL,
    p_promotion_data    jsonb   DEFAULT NULL,
    p_inventory_data    jsonb   DEFAULT NULL,
    p_notas             text    DEFAULT NULL,
    p_sku_producto      varchar DEFAULT NULL,
    p_sku_ubicacion     varchar DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado smallint;
    v_id_item bigint;
BEGIN
    -- Validar que la cuenta esté abierta.
    SELECT estado INTO v_estado
    FROM public.app_dat_mesa_cuenta_abierta
    WHERE id = p_id_cuenta;

    IF v_estado IS NULL THEN
        RAISE EXCEPTION 'Cuenta % no existe', p_id_cuenta USING ERRCODE = 'P0001';
    END IF;

    IF v_estado <> 1 THEN
        RAISE EXCEPTION 'Cuenta % no está abierta (estado=%)', p_id_cuenta, v_estado
            USING ERRCODE = 'P0001';
    END IF;

    IF p_cantidad <= 0 THEN
        RAISE EXCEPTION 'Cantidad debe ser positiva (recibida %)', p_cantidad
            USING ERRCODE = 'P0001';
    END IF;

    -- Consolidación: si ya hay una línea exactamente igual (producto + variante +
    -- presentacion + ubicacion + metodo de pago), incrementar cantidad en lugar
    -- de crear una nueva. Esto refleja el comportamiento de
    -- OrderService.addItemToCurrentOrder.
    SELECT id INTO v_id_item
    FROM public.app_dat_mesa_cuenta_item
    WHERE id_cuenta = p_id_cuenta
      AND id_producto = p_id_producto
      AND COALESCE(id_variante, -1) = COALESCE(p_id_variante, -1)
      AND COALESCE(id_opcion_variante, -1) = COALESCE(p_id_opcion_variante, -1)
      AND COALESCE(id_presentacion, -1) = COALESCE(p_id_presentacion, -1)
      AND COALESCE(id_ubicacion, -1) = COALESCE(p_id_ubicacion, -1)
      AND COALESCE(id_metodo_pago, -1) = COALESCE(p_id_metodo_pago, -1)
    LIMIT 1;

    IF v_id_item IS NOT NULL THEN
        UPDATE public.app_dat_mesa_cuenta_item
        SET cantidad = cantidad + p_cantidad,
            updated_at = now(),
            -- refrescar promotion/inventory data por si cambia
            promotion_data = COALESCE(p_promotion_data, promotion_data),
            inventory_data = COALESCE(p_inventory_data, inventory_data),
            precio_unitario = p_precio_unitario,
            precio_base     = COALESCE(p_precio_base, precio_base)
        WHERE id = v_id_item;
    ELSE
        INSERT INTO public.app_dat_mesa_cuenta_item (
            id_cuenta, id_producto, id_variante, id_opcion_variante,
            id_presentacion, id_ubicacion,
            cantidad, precio_unitario, precio_base,
            id_metodo_pago, promotion_data, inventory_data,
            notas, sku_producto, sku_ubicacion
        )
        VALUES (
            p_id_cuenta, p_id_producto, p_id_variante, p_id_opcion_variante,
            p_id_presentacion, p_id_ubicacion,
            p_cantidad, p_precio_unitario, p_precio_base,
            p_id_metodo_pago, p_promotion_data, p_inventory_data,
            p_notas, p_sku_producto, p_sku_ubicacion
        )
        RETURNING id INTO v_id_item;
    END IF;

    UPDATE public.app_dat_mesa_cuenta_abierta
    SET updated_at = now()
    WHERE id = p_id_cuenta;

    RETURN v_id_item;
END;
$$;


-- 2.5 Actualizar la cantidad de un item (si cantidad <= 0 elimina la línea).
CREATE OR REPLACE FUNCTION public.fn_actualizar_item_cuenta_mesa(
    p_id_item   bigint,
    p_cantidad  numeric
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_cuenta bigint;
    v_estado    smallint;
BEGIN
    SELECT i.id_cuenta, c.estado INTO v_id_cuenta, v_estado
    FROM public.app_dat_mesa_cuenta_item i
    JOIN public.app_dat_mesa_cuenta_abierta c ON c.id = i.id_cuenta
    WHERE i.id = p_id_item;

    IF v_id_cuenta IS NULL THEN
        RAISE EXCEPTION 'Item % no existe', p_id_item USING ERRCODE = 'P0001';
    END IF;

    IF v_estado <> 1 THEN
        RAISE EXCEPTION 'Cuenta no abierta' USING ERRCODE = 'P0001';
    END IF;

    IF p_cantidad <= 0 THEN
        DELETE FROM public.app_dat_mesa_cuenta_item WHERE id = p_id_item;
    ELSE
        UPDATE public.app_dat_mesa_cuenta_item
        SET cantidad = p_cantidad, updated_at = now()
        WHERE id = p_id_item;
    END IF;

    UPDATE public.app_dat_mesa_cuenta_abierta
    SET updated_at = now()
    WHERE id = v_id_cuenta;
END;
$$;


-- 2.6 Actualizar el método de pago de un item específico.
CREATE OR REPLACE FUNCTION public.fn_actualizar_metodo_pago_item_cuenta(
    p_id_item        bigint,
    p_id_metodo_pago bigint
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_cuenta bigint;
    v_estado    smallint;
BEGIN
    SELECT i.id_cuenta, c.estado INTO v_id_cuenta, v_estado
    FROM public.app_dat_mesa_cuenta_item i
    JOIN public.app_dat_mesa_cuenta_abierta c ON c.id = i.id_cuenta
    WHERE i.id = p_id_item;

    IF v_id_cuenta IS NULL THEN
        RAISE EXCEPTION 'Item % no existe', p_id_item USING ERRCODE = 'P0001';
    END IF;

    IF v_estado <> 1 THEN
        RAISE EXCEPTION 'Cuenta no abierta' USING ERRCODE = 'P0001';
    END IF;

    UPDATE public.app_dat_mesa_cuenta_item
    SET id_metodo_pago = p_id_metodo_pago,
        updated_at = now()
    WHERE id = p_id_item;

    UPDATE public.app_dat_mesa_cuenta_abierta
    SET updated_at = now()
    WHERE id = v_id_cuenta;
END;
$$;


-- 2.7 Eliminar item.
CREATE OR REPLACE FUNCTION public.fn_eliminar_item_cuenta_mesa(
    p_id_item bigint
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_cuenta bigint;
    v_estado    smallint;
BEGIN
    SELECT i.id_cuenta, c.estado INTO v_id_cuenta, v_estado
    FROM public.app_dat_mesa_cuenta_item i
    JOIN public.app_dat_mesa_cuenta_abierta c ON c.id = i.id_cuenta
    WHERE i.id = p_id_item;

    IF v_id_cuenta IS NULL THEN
        RAISE EXCEPTION 'Item % no existe', p_id_item USING ERRCODE = 'P0001';
    END IF;

    IF v_estado <> 1 THEN
        RAISE EXCEPTION 'Cuenta no abierta' USING ERRCODE = 'P0001';
    END IF;

    DELETE FROM public.app_dat_mesa_cuenta_item WHERE id = p_id_item;

    UPDATE public.app_dat_mesa_cuenta_abierta
    SET updated_at = now()
    WHERE id = v_id_cuenta;
END;
$$;


-- 2.8 Cancelar una cuenta abierta sin convertirla en venta.
-- (El vendedor pulsa "Cancelar Cuenta" — los items se descartan.)
CREATE OR REPLACE FUNCTION public.fn_cancelar_cuenta_mesa(
    p_id_cuenta bigint
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado smallint;
BEGIN
    SELECT estado INTO v_estado
    FROM public.app_dat_mesa_cuenta_abierta
    WHERE id = p_id_cuenta;

    IF v_estado IS NULL THEN
        RAISE EXCEPTION 'Cuenta % no existe', p_id_cuenta USING ERRCODE = 'P0001';
    END IF;

    IF v_estado <> 1 THEN
        -- ya cerrada/cancelada: no-op idempotente
        RETURN;
    END IF;

    UPDATE public.app_dat_mesa_cuenta_abierta
    SET estado = 3,
        closed_at = now(),
        updated_at = now()
    WHERE id = p_id_cuenta;

    -- Los items se mantienen como histórico (no se borran). Si en algún momento
    -- ocupan demasiado, un job de mantenimiento puede purgarlos.
END;
$$;


-- 2.9 Marcar una cuenta como cerrada (post-checkout) vinculándola con la operación
-- de venta real. Esta función se llama DESPUÉS de fn_registrar_venta_mesa.
CREATE OR REPLACE FUNCTION public.fn_marcar_cuenta_cerrada(
    p_id_cuenta         bigint,
    p_id_operacion_venta bigint
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE public.app_dat_mesa_cuenta_abierta
    SET estado = 2,
        id_operacion_venta = p_id_operacion_venta,
        closed_at = now(),
        updated_at = now()
    WHERE id = p_id_cuenta AND estado = 1;

    IF NOT FOUND THEN
        RAISE WARNING 'fn_marcar_cuenta_cerrada: cuenta % no estaba abierta o no existe', p_id_cuenta;
    END IF;
END;
$$;


-- ----------------------------------------------------------------------------
-- 3. AJUSTE A fn_listar_mesas_con_stats (existente):
-- ----------------------------------------------------------------------------
-- En el modelo nuevo "una mesa está ocupada" cuando tiene una CUENTA ABIERTA
-- (estado=1) o cuando tiene órdenes de venta activas (estado pendiente). El
-- conteo de "ordenes_abiertas" debe incluir ambas dimensiones; la siguiente
-- migración es opcional pero recomendada para que la grilla refleje el estado
-- real desde el momento en que se abre la cuenta (no sólo al registrar venta).
--
-- NOTA: la función original (en mesas_schema.sql) se mantiene; aquí la
-- reemplazamos para sumar también las cuentas abiertas. Si tienes una versión
-- ya en producción, simplemente vuelve a ejecutar esta CREATE OR REPLACE.

CREATE OR REPLACE FUNCTION public.fn_listar_mesas_con_stats(
    p_id_tienda bigint,
    p_incluir_inactivas boolean DEFAULT false
)
RETURNS TABLE (
    id                              bigint,
    id_tienda                       bigint,
    numero                          text,
    capacidad                       smallint,
    zona                            text,
    notas                           text,
    activa                          boolean,
    ordenes_abiertas                bigint,    -- cuentas abiertas (estado 1) + ventas pendientes
    ordenes_completadas_historicas  bigint,
    comensales_activos              bigint     -- igual a ordenes_abiertas (compatibilidad)
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        m.id,
        m.id_tienda,
        m.numero,
        m.capacidad,
        m.zona,
        m.notas,
        m.activa,
        (
            -- Cuentas abiertas (estado intermedio antes de cobrar)
            COALESCE((
                SELECT COUNT(*)::bigint
                FROM public.app_dat_mesa_cuenta_abierta ca
                WHERE ca.id_mesa = m.id AND ca.estado = 1
            ), 0)
            +
            -- Ventas en estado pendiente que aún están asociadas a la mesa
            COALESCE((
                SELECT COUNT(DISTINCT ov.id_operacion)::bigint
                FROM public.app_dat_operacion_venta ov
                JOIN public.app_dat_estado_operacion eo ON eo.id_operacion = ov.id_operacion
                WHERE ov.id_mesa = m.id
                  AND eo.estado = 1                            -- Pendiente
                  AND eo.created_at = (
                        SELECT MAX(eo2.created_at)
                        FROM public.app_dat_estado_operacion eo2
                        WHERE eo2.id_operacion = ov.id_operacion
                  )
            ), 0)
        ) AS ordenes_abiertas,
        COALESCE((
            SELECT COUNT(DISTINCT ov.id_operacion)::bigint
            FROM public.app_dat_operacion_venta ov
            JOIN public.app_dat_estado_operacion eo ON eo.id_operacion = ov.id_operacion
            WHERE ov.id_mesa = m.id
              AND eo.estado IN (2, 10)                         -- Completada, Facturada
              AND eo.created_at = (
                    SELECT MAX(eo2.created_at)
                    FROM public.app_dat_estado_operacion eo2
                    WHERE eo2.id_operacion = ov.id_operacion
              )
        ), 0) AS ordenes_completadas_historicas,
        (
            COALESCE((
                SELECT COUNT(*)::bigint
                FROM public.app_dat_mesa_cuenta_abierta ca
                WHERE ca.id_mesa = m.id AND ca.estado = 1
            ), 0)
            +
            COALESCE((
                SELECT COUNT(DISTINCT ov.id_operacion)::bigint
                FROM public.app_dat_operacion_venta ov
                JOIN public.app_dat_estado_operacion eo ON eo.id_operacion = ov.id_operacion
                WHERE ov.id_mesa = m.id
                  AND eo.estado = 1
                  AND eo.created_at = (
                        SELECT MAX(eo2.created_at)
                        FROM public.app_dat_estado_operacion eo2
                        WHERE eo2.id_operacion = ov.id_operacion
                  )
            ), 0)
        ) AS comensales_activos
    FROM public.app_dat_mesas m
    WHERE m.id_tienda = p_id_tienda
      AND (p_incluir_inactivas OR m.activa = true)
    ORDER BY m.activa DESC, m.numero ASC;
$$;


-- ============================================================================
-- FIN
-- ============================================================================
