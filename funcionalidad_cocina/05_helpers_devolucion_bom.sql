-- ============================================================================
-- 05 · Fase 0 · Helpers de DEVOLUCION de receta + resolucion de almacen
-- ============================================================================
-- Proyecto Supabase: vsieeihstajlrdvpuooh
-- Aplicar en: SQL Editor del dashboard. Idempotente (CREATE OR REPLACE).
-- REQUISITO: 01_helpers_bom_almacen.sql ya aplicado.
--
-- Este archivo SOLO AGREGA funciones. No toca ninguna existente.
-- El reemplazo de las funciones de edicion de orden va en el 06.
--
-- POR QUE HACEN FALTA
-- -------------------
-- Las rutas de edicion de orden pendiente no solo DESCUENTAN materia prima:
-- tambien la DEVUELVEN (bajar cantidad, quitar un producto de la orden). El
-- helper del 01 solo sabe descontar. Aqui se agrega el inverso, con el mismo
-- criterio de acotar todo a un almacen.
--
-- Ademas estas funciones reciben un id_extraccion, no un id_tpv, asi que hay
-- que derivar a que almacen pertenece la linea. De ahi fn_almacen_de_extraccion.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 5.1 fn_almacen_de_extraccion
-- Devuelve el id_almacen al que corresponde una linea de extraccion.
--
-- Prioridad:
--   1. El almacen del layout de la propia linea (id_ubicacion). Es el dato mas
--      fiable: es donde realmente se movio el stock.
--   2. Si la linea no tiene ubicacion, el almacen del TPV de la venta.
--
-- Devuelve NULL si no se puede determinar (el caller debe tratarlo como error).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_almacen_de_extraccion(
    p_id_extraccion bigint
)
RETURNS bigint
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        -- 1. almacen del layout de la linea
        (SELECT la.id_almacen
           FROM public.app_dat_extraccion_productos ep
           JOIN public.app_dat_layout_almacen la ON la.id = ep.id_ubicacion
          WHERE ep.id = p_id_extraccion),
        -- 2. almacen del TPV de la venta
        (SELECT t.id_almacen
           FROM public.app_dat_extraccion_productos ep
           JOIN public.app_dat_operacion_venta ov ON ov.id_operacion = ep.id_operacion
           JOIN public.app_dat_tpv t ON t.id = ov.id_tpv
          WHERE ep.id = p_id_extraccion)
    );
$$;

COMMENT ON FUNCTION public.fn_almacen_de_extraccion(bigint)
    IS 'Almacen de una linea de extraccion: por el layout de la linea, o por el TPV de la venta.';

GRANT EXECUTE ON FUNCTION public.fn_almacen_de_extraccion(bigint)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 5.2 fn_almacen_de_operacion
-- Igual que la anterior pero a partir de la operacion de venta (para
-- fn_agregar_producto_orden_pendiente, que recibe id_operacion y todavia no
-- tiene linea).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_almacen_de_operacion(
    p_id_operacion bigint
)
RETURNS bigint
LANGUAGE sql
STABLE
AS $$
    SELECT t.id_almacen
      FROM public.app_dat_operacion_venta ov
      JOIN public.app_dat_tpv t ON t.id = ov.id_tpv
     WHERE ov.id_operacion = p_id_operacion
     LIMIT 1;
$$;

COMMENT ON FUNCTION public.fn_almacen_de_operacion(bigint)
    IS 'Almacen del TPV que registro una operacion de venta.';

GRANT EXECUTE ON FUNCTION public.fn_almacen_de_operacion(bigint)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 5.3 fn_ubicacion_destino_devolucion
-- A que ubicacion se devuelve el stock de un producto dentro de un almacen.
--
-- Prioridad:
--   1. Ubicacion del almacen que YA tiene stock de ese producto (la de mayor
--      cantidad). Devolver donde ya hay es lo que menos ensucia el inventario.
--   2. Ultima ubicacion del almacen donde ese producto tuvo movimiento (aunque
--      hoy este en 0).
--   3. Primer layout no borrado del almacen (ultimo recurso).
--
-- Devuelve NULL si el almacen no tiene layouts utilizables.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_ubicacion_destino_devolucion(
    p_id_producto bigint,
    p_id_almacen  bigint
)
RETURNS bigint
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        -- 1. donde ya hay stock
        (SELECT d.id_ubicacion
           FROM public.fn_stock_producto_almacen_detalle(p_id_producto, p_id_almacen) d
          ORDER BY d.cantidad_final DESC
          LIMIT 1),
        -- 2. ultimo movimiento historico en ese almacen
        (SELECT ip.id_ubicacion
           FROM public.app_dat_inventario_productos ip
           JOIN public.app_dat_layout_almacen la ON la.id = ip.id_ubicacion
          WHERE ip.id_producto = p_id_producto
            AND la.id_almacen = p_id_almacen
            AND la.deleted_at IS NULL
          ORDER BY ip.id DESC
          LIMIT 1),
        -- 3. cualquier layout del almacen
        (SELECT la.id
           FROM public.app_dat_layout_almacen la
          WHERE la.id_almacen = p_id_almacen
            AND la.deleted_at IS NULL
          ORDER BY la.id ASC
          LIMIT 1)
    );
$$;

COMMENT ON FUNCTION public.fn_ubicacion_destino_devolucion(bigint, bigint)
    IS 'Ubicacion destino para devolver stock de un producto dentro de un almacen.';

GRANT EXECUTE ON FUNCTION public.fn_ubicacion_destino_devolucion(bigint, bigint)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 5.4 fn_devolver_ingredientes_elaborado
-- Inverso de fn_descontar_ingredientes_elaborado: devuelve la materia prima de
-- un elaborado al almacen indicado.
--
-- Se usa cuando se baja la cantidad de un plato en una orden pendiente o se
-- quita el plato de la orden.
--
-- No valida stock (devolver siempre puede) pero SI valida que exista una
-- ubicacion destino en ese almacen; si no, devuelve error sin escribir nada.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_devolver_ingredientes_elaborado(
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
    v_ing           RECORD;
    v_id_ubicacion  bigint;
    v_actual        numeric;
    v_sku_producto  varchar;
    v_sku_ubicacion varchar;
    v_movimientos   jsonb := '[]'::jsonb;
    v_lineas        integer := 0;
BEGIN
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    'La cantidad a devolver debe ser positiva',
            'error_code', 'INVALID_QUANTITY'
        );
    END IF;

    IF p_id_almacen IS NULL THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    'No se pudo determinar el almacen para devolver la materia prima',
            'error_code', 'ALMACEN_NOT_RESOLVED'
        );
    END IF;

    -- Primera pasada: comprobar que cada ingrediente tenga ubicacion destino
    -- ANTES de escribir nada.
    FOR v_ing IN
        SELECT id_ingrediente, cantidad_total_necesaria
          FROM public.fn_obtener_ingredientes_recursivos(p_id_producto_elaborado, p_cantidad)
    LOOP
        IF public.fn_ubicacion_destino_devolucion(v_ing.id_ingrediente, p_id_almacen) IS NULL THEN
            RETURN jsonb_build_object(
                'status',         'error',
                'message',        'El almacen no tiene ubicacion donde devolver el ingrediente: '
                                  || COALESCE((SELECT denominacion FROM public.app_dat_producto
                                                WHERE id = v_ing.id_ingrediente),
                                              '#' || v_ing.id_ingrediente),
                'error_code',     'NO_RETURN_LOCATION',
                'id_ingrediente', v_ing.id_ingrediente,
                'id_almacen',     p_id_almacen
            );
        END IF;
    END LOOP;

    -- Segunda pasada: devolver.
    FOR v_ing IN
        SELECT id_ingrediente, cantidad_total_necesaria
          FROM public.fn_obtener_ingredientes_recursivos(p_id_producto_elaborado, p_cantidad)
    LOOP
        v_id_ubicacion := public.fn_ubicacion_destino_devolucion(v_ing.id_ingrediente, p_id_almacen);

        -- Stock vigente en esa ubicacion (0 si nunca tuvo).
        SELECT ip.cantidad_final, ip.sku_producto, ip.sku_ubicacion
          INTO v_actual, v_sku_producto, v_sku_ubicacion
          FROM public.app_dat_inventario_productos ip
         WHERE ip.id_producto  = v_ing.id_ingrediente
           AND ip.id_ubicacion = v_id_ubicacion
         ORDER BY ip.id DESC
         LIMIT 1;

        v_actual := COALESCE(v_actual, 0);

        IF v_sku_producto IS NULL THEN
            SELECT sku INTO v_sku_producto
              FROM public.app_dat_producto
             WHERE id = v_ing.id_ingrediente;
        END IF;

        IF v_sku_ubicacion IS NULL THEN
            SELECT sku_codigo INTO v_sku_ubicacion
              FROM public.app_dat_layout_almacen
             WHERE id = v_id_ubicacion;
        END IF;

        INSERT INTO public.app_dat_inventario_productos (
            id_producto,
            id_ubicacion,
            cantidad_inicial,
            cantidad_final,
            sku_producto,
            sku_ubicacion,
            origen_cambio,
            id_extraccion,
            created_at
        ) VALUES (
            v_ing.id_ingrediente,
            v_id_ubicacion,
            v_actual,
            v_actual + v_ing.cantidad_total_necesaria,
            v_sku_producto,
            v_sku_ubicacion,
            p_origen_cambio,
            p_id_extraccion,
            NOW()
        );

        v_movimientos := v_movimientos || jsonb_build_object(
            'id_ingrediente', v_ing.id_ingrediente,
            'id_ubicacion',   v_id_ubicacion,
            'devuelto',       v_ing.cantidad_total_necesaria,
            'stock_previo',   v_actual,
            'stock_nuevo',    v_actual + v_ing.cantidad_total_necesaria
        );

        v_lineas := v_lineas + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'status',           'success',
        'id_almacen',       p_id_almacen,
        'lineas_afectadas', v_lineas,
        'movimientos',      v_movimientos
    );
END;
$$;

COMMENT ON FUNCTION public.fn_devolver_ingredientes_elaborado(bigint, numeric, bigint, bigint, integer)
    IS 'Devuelve materia prima de un elaborado a los layouts de un almacen (inverso de fn_descontar_ingredientes_elaborado).';

GRANT EXECUTE ON FUNCTION public.fn_devolver_ingredientes_elaborado(bigint, numeric, bigint, bigint, integer)
    TO anon, authenticated, service_role;


-- ============================================================================
-- VERIFICACION (no modifica datos)
-- ============================================================================
-- Los helpers deben existir -> 4 filas
--
--   SELECT p.oid::regprocedure
--     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname = 'public'
--      AND p.proname IN ('fn_almacen_de_extraccion','fn_almacen_de_operacion',
--                        'fn_ubicacion_destino_devolucion',
--                        'fn_devolver_ingredientes_elaborado')
--    ORDER BY p.proname;
--
-- Resolucion de almacen sobre una linea real (elegir un id_extraccion existente):
--
--   SELECT ep.id, ep.id_producto, ep.id_ubicacion,
--          public.fn_almacen_de_extraccion(ep.id) AS almacen_resuelto
--     FROM app_dat_extraccion_productos ep
--    ORDER BY ep.id DESC
--    LIMIT 10;
--
-- Ubicacion destino para devolver harina de trigo (216) al almacen 12:
--   esperado 37 (la de mayor stock)
--
--   SELECT public.fn_ubicacion_destino_devolucion(216, 12);
--
-- NO correr fn_devolver_ingredientes_elaborado en produccion para probar:
--   inserta inventario de verdad. Probar dentro de BEGIN ... ROLLBACK.
-- ============================================================================
