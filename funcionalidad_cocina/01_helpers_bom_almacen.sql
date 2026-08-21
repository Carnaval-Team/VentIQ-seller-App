-- ============================================================================
-- 01 · Fase 0 · Helpers de descuento de receta (BOM) acotado a un almacen
-- ============================================================================
-- Proyecto Supabase: vsieeihstajlrdvpuooh
-- Aplicar en: SQL Editor del dashboard. Idempotente (CREATE OR REPLACE).
--
-- PROBLEMA QUE RESUELVE
-- ---------------------
-- Hoy fn_registrar_venta / fn_registrar_venta_mesa descuentan la materia prima
-- de un elaborado asi:
--
--   SELECT ... FROM app_dat_inventario_productos
--   WHERE id_producto = v_ingrediente.id_ingrediente
--   ORDER BY id desc, created_at DESC
--   LIMIT 1;
--
-- Esa es la ultima fila GLOBAL del ingrediente. No filtra por el almacen del
-- TPV que vende y solo mira UNA ubicacion. Dos fallos reales:
--
--   1. Descuenta materia prima de otro almacen (o, con la Fase 1, de otra cocina).
--   2. Si el ingrediente esta repartido en varias ubicaciones del almacen
--      correcto, dice "stock insuficiente" aunque en total si alcance.
--      Caso verificado en produccion: producto 216 tiene 4.0 en la ubicacion 37
--      y 1.0 en la ubicacion 41, ambas del almacen 12. La logica actual solo ve
--      4.0 y rechaza una necesidad de 5.
--
-- ESTE ARCHIVO NO TOCA NINGUNA FUNCION EXISTENTE.
-- Solo agrega helpers nuevos. El reemplazo del bloque dentro de las funciones
-- de venta va en el archivo 03.
--
-- CONVENCION DE p_id_almacen
-- --------------------------
-- p_id_almacen NOT NULL -> se acota a los layouts de ese almacen (comportamiento
--                          correcto, es el que usaran las funciones de venta).
-- p_id_almacen NULL     -> no filtra por almacen (comportamiento amplio, util
--                          para diagnostico y para llamadas legacy).
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1.1 fn_stock_producto_almacen_detalle
-- Stock vigente de un producto, una fila por ubicacion/variante/presentacion.
--
-- "Vigente" = la fila mas reciente (id DESC) de app_dat_inventario_productos
-- para cada combinacion unica, que es como el resto del sistema calcula stock.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_stock_producto_almacen_detalle(
    p_id_producto bigint,
    p_id_almacen  bigint DEFAULT NULL
)
RETURNS TABLE (
    id_ubicacion        bigint,
    id_almacen          bigint,
    id_variante         bigint,
    id_opcion_variante  bigint,
    id_presentacion     bigint,
    cantidad_final      numeric,
    sku_producto        varchar,
    sku_ubicacion       varchar
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        v.id_ubicacion,
        v.id_almacen,
        v.id_variante,
        v.id_opcion_variante,
        v.id_presentacion,
        v.cantidad_final,
        v.sku_producto,
        v.sku_ubicacion
    FROM (
        SELECT DISTINCT ON (
                   ip.id_ubicacion,
                   COALESCE(ip.id_variante, 0),
                   COALESCE(ip.id_opcion_variante, 0),
                   COALESCE(ip.id_presentacion, 0)
               )
               ip.id_ubicacion,
               la.id_almacen,
               ip.id_variante,
               ip.id_opcion_variante,
               ip.id_presentacion,
               ip.cantidad_final,
               ip.sku_producto,
               ip.sku_ubicacion
          FROM public.app_dat_inventario_productos ip
          JOIN public.app_dat_layout_almacen la ON la.id = ip.id_ubicacion
         WHERE ip.id_producto = p_id_producto
           AND la.deleted_at IS NULL
           AND (p_id_almacen IS NULL OR la.id_almacen = p_id_almacen)
         ORDER BY
               ip.id_ubicacion,
               COALESCE(ip.id_variante, 0),
               COALESCE(ip.id_opcion_variante, 0),
               COALESCE(ip.id_presentacion, 0),
               ip.id DESC
    ) v
    WHERE COALESCE(v.cantidad_final, 0) > 0
    ORDER BY v.cantidad_final DESC, v.id_ubicacion;
$$;

COMMENT ON FUNCTION public.fn_stock_producto_almacen_detalle(bigint, bigint)
    IS 'Stock vigente de un producto desglosado por ubicacion, acotado a un almacen (NULL = todos).';

GRANT EXECUTE ON FUNCTION public.fn_stock_producto_almacen_detalle(bigint, bigint)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 1.2 fn_stock_producto_almacen
-- Total disponible de un producto en un almacen (suma de todas sus ubicaciones).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_stock_producto_almacen(
    p_id_producto bigint,
    p_id_almacen  bigint DEFAULT NULL
)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(SUM(d.cantidad_final), 0)::numeric
      FROM public.fn_stock_producto_almacen_detalle(p_id_producto, p_id_almacen) d;
$$;

COMMENT ON FUNCTION public.fn_stock_producto_almacen(bigint, bigint)
    IS 'Total de stock vigente de un producto en un almacen (NULL = todos los almacenes).';

GRANT EXECUTE ON FUNCTION public.fn_stock_producto_almacen(bigint, bigint)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 1.3 fn_validar_ingredientes_elaborado
-- Valida que TODOS los ingredientes de un elaborado alcancen en el almacen,
-- ANTES de descontar ninguno. Devuelve jsonb, no lanza excepcion.
--
--   { "status": "success", "ingredientes": [...] }
--   { "status": "error", "error_code": "INSUFFICIENT_STOCK_INGREDIENT", ... }
--
-- Los campos de error replican exactamente los que ya devuelven las funciones
-- de venta, para no romper el manejo de errores del cliente Flutter.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_validar_ingredientes_elaborado(
    p_id_producto_elaborado bigint,
    p_cantidad              numeric,
    p_id_almacen            bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_ing            RECORD;
    v_disponible     numeric;
    v_denominacion   text;
    v_detalle        jsonb := '[]'::jsonb;
    v_hubo_receta    boolean := false;
BEGIN
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    'La cantidad a producir debe ser positiva',
            'error_code', 'INVALID_QUANTITY'
        );
    END IF;

    FOR v_ing IN
        SELECT id_ingrediente, cantidad_total_necesaria
          FROM public.fn_obtener_ingredientes_recursivos(p_id_producto_elaborado, p_cantidad)
    LOOP
        v_hubo_receta := true;

        v_disponible := public.fn_stock_producto_almacen(v_ing.id_ingrediente, p_id_almacen);

        SELECT denominacion INTO v_denominacion
          FROM public.app_dat_producto
         WHERE id = v_ing.id_ingrediente;

        IF v_disponible < v_ing.cantidad_total_necesaria THEN
            RETURN jsonb_build_object(
                'status',              'error',
                'message',             'Stock insuficiente para el ingrediente: '
                                       || COALESCE(v_denominacion, '#' || v_ing.id_ingrediente)
                                       || ' (disponible: ' || v_disponible
                                       || ', requerido: ' || v_ing.cantidad_total_necesaria || ')',
                'error_code',          'INSUFFICIENT_STOCK_INGREDIENT',
                'id_ingrediente',      v_ing.id_ingrediente,
                'ingrediente',         v_denominacion,
                'cantidad_requerida',  v_ing.cantidad_total_necesaria,
                'cantidad_disponible', v_disponible,
                'id_almacen',          p_id_almacen
            );
        END IF;

        v_detalle := v_detalle || jsonb_build_object(
            'id_ingrediente',      v_ing.id_ingrediente,
            'ingrediente',         v_denominacion,
            'cantidad_requerida',  v_ing.cantidad_total_necesaria,
            'cantidad_disponible', v_disponible
        );
    END LOOP;

    RETURN jsonb_build_object(
        'status',       'success',
        'tiene_receta', v_hubo_receta,
        'id_almacen',   p_id_almacen,
        'ingredientes', v_detalle
    );
END;
$$;

COMMENT ON FUNCTION public.fn_validar_ingredientes_elaborado(bigint, numeric, bigint)
    IS 'Valida stock de todos los ingredientes de un elaborado en un almacen, sin descontar.';

GRANT EXECUTE ON FUNCTION public.fn_validar_ingredientes_elaborado(bigint, numeric, bigint)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 1.4 fn_descontar_ingredientes_elaborado
-- Descuenta la materia prima de un elaborado consumiendo ubicacion por
-- ubicacion dentro del almacen indicado.
--
-- Reglas:
--   - Valida TODO antes de descontar nada (si falta uno, no se toca inventario).
--   - Consume las ubicaciones de mayor a menor stock hasta cubrir lo necesario.
--   - Inserta una fila nueva en app_dat_inventario_productos por cada ubicacion
--     afectada (mismo patron de auditoria que usa el sistema hoy).
--   - origen_cambio configurable; las ventas usan 4 (consumo por elaborado).
--
-- El caller decide que hacer con el error: las funciones de venta hacen
-- RETURN del jsonb tal cual, abortando la transaccion sin descuento parcial.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_descontar_ingredientes_elaborado(
    p_id_producto_elaborado bigint,
    p_cantidad              numeric,
    p_id_almacen            bigint,
    p_id_extraccion         bigint  DEFAULT NULL,
    p_origen_cambio         integer DEFAULT 4
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_validacion   jsonb;
    v_ing          RECORD;
    v_ubic         RECORD;
    v_pendiente    numeric;
    v_a_descontar  numeric;
    v_movimientos  jsonb := '[]'::jsonb;
    v_total_lineas integer := 0;
BEGIN
    -- 1. Validar todo antes de tocar inventario.
    v_validacion := public.fn_validar_ingredientes_elaborado(
        p_id_producto_elaborado, p_cantidad, p_id_almacen
    );

    IF (v_validacion->>'status') <> 'success' THEN
        RETURN v_validacion;
    END IF;

    -- 2. Descontar ingrediente por ingrediente.
    FOR v_ing IN
        SELECT id_ingrediente, cantidad_total_necesaria
          FROM public.fn_obtener_ingredientes_recursivos(p_id_producto_elaborado, p_cantidad)
    LOOP
        v_pendiente := v_ing.cantidad_total_necesaria;

        FOR v_ubic IN
            SELECT *
              FROM public.fn_stock_producto_almacen_detalle(v_ing.id_ingrediente, p_id_almacen)
        LOOP
            EXIT WHEN v_pendiente <= 0;

            v_a_descontar := LEAST(v_ubic.cantidad_final, v_pendiente);

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
                v_ing.id_ingrediente,
                v_ubic.id_variante,
                v_ubic.id_opcion_variante,
                v_ubic.id_ubicacion,
                v_ubic.id_presentacion,
                v_ubic.cantidad_final,
                v_ubic.cantidad_final - v_a_descontar,
                v_ubic.sku_producto,
                v_ubic.sku_ubicacion,
                p_origen_cambio,
                p_id_extraccion,
                NOW()
            );

            v_movimientos := v_movimientos || jsonb_build_object(
                'id_ingrediente', v_ing.id_ingrediente,
                'id_ubicacion',   v_ubic.id_ubicacion,
                'descontado',     v_a_descontar,
                'stock_previo',   v_ubic.cantidad_final,
                'stock_nuevo',    v_ubic.cantidad_final - v_a_descontar
            );

            v_total_lineas := v_total_lineas + 1;
            v_pendiente := v_pendiente - v_a_descontar;
        END LOOP;

        -- Salvaguarda: no deberia pasar porque ya validamos, pero si entre la
        -- validacion y el descuento cambio el stock, abortamos con el mismo
        -- error_code que espera el cliente.
        IF v_pendiente > 0 THEN
            RETURN jsonb_build_object(
                'status',              'error',
                'message',             'Stock insuficiente para el ingrediente: '
                                       || COALESCE((SELECT denominacion FROM public.app_dat_producto
                                                     WHERE id = v_ing.id_ingrediente),
                                                   '#' || v_ing.id_ingrediente)
                                       || ' (faltan ' || v_pendiente || ')',
                'error_code',          'INSUFFICIENT_STOCK_INGREDIENT',
                'id_ingrediente',      v_ing.id_ingrediente,
                'cantidad_requerida',  v_ing.cantidad_total_necesaria,
                'cantidad_disponible', v_ing.cantidad_total_necesaria - v_pendiente,
                'id_almacen',          p_id_almacen
            );
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'status',           'success',
        'id_almacen',       p_id_almacen,
        'lineas_afectadas', v_total_lineas,
        'movimientos',      v_movimientos
    );
END;
$$;

COMMENT ON FUNCTION public.fn_descontar_ingredientes_elaborado(bigint, numeric, bigint, bigint, integer)
    IS 'Descuenta materia prima de un elaborado en los layouts de un almacen, multi-ubicacion y con validacion previa.';

GRANT EXECUTE ON FUNCTION public.fn_descontar_ingredientes_elaborado(bigint, numeric, bigint, bigint, integer)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 1.5 Indice de apoyo
-- El lookup de stock filtra por id_producto y ordena por id DESC. Sin este
-- indice, cada ingrediente de cada venta hace un scan mas caro de lo necesario.
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_inv_prod_producto_ubicacion_id
    ON public.app_dat_inventario_productos (id_producto, id_ubicacion, id DESC);


-- ============================================================================
-- VERIFICACION (correr despues de aplicar; no modifica datos)
-- ============================================================================
-- Caso real: el ingrediente 216 tiene stock en 2 ubicaciones del almacen 12
-- (37 con 4.0 y 41 con 1.0). Antes solo se veia una.
--
--   SELECT * FROM public.fn_stock_producto_almacen_detalle(216, 12);
--   -- esperado: 2 filas, ubicaciones 37 y 41
--
--   SELECT public.fn_stock_producto_almacen(216, 12);
--   -- esperado: 5.0 (antes la logica de venta solo veia 4.0)
--
-- El elaborado 219 necesita 40 g de 216 y 10 g de 218 por unidad:
--
--   SELECT public.fn_validar_ingredientes_elaborado(219, 1, 12);
--   -- devuelve status success/error con el desglose por ingrediente
--
-- NO correr fn_descontar_ingredientes_elaborado en produccion para probar:
--   descuenta inventario de verdad. Probar dentro de BEGIN ... ROLLBACK.
-- ============================================================================
