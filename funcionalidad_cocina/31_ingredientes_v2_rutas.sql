-- ============================================================================
-- 31 Â· Fase 1 Â· Rutas _v2 del BOM de elaborados y de la venta enrutada
-- ============================================================================
-- Proyectos Supabase: debug qhprswhhfasrikhawjoz + produccion vsieeihstajlrdvpuooh
-- Requiere: 30_ingredientes_por_equivalente_base.sql aplicado antes.
-- Idempotente: CREATE OR REPLACE. NO toca ninguna funcion viva.
--
-- Este archivo es la FRONTERA del contrato de error (decision 7 del plan): los
-- codigos finos que expone el kernel del 30 (INVALID_PRESENTATION_CHAIN,
-- NEGATIVE_STOCK_PRESENTACION, motivo CADENA_NO_DIVISIBLE_EN_ENTEROS) se traducen
-- aqui a los tres codigos estables que ya consume la app:
--
--     INSUFFICIENT_STOCK_INGREDIENT   (receta / ingrediente)
--     INSUFFICIENT_STOCK             (SKU propio)
--     INSUFFICIENT_PORTIONS          (SKU propio de cocina por_tanda)
--
-- ----------------------------------------------------------------------------
-- QUE TRAE
-- ----------------------------------------------------------------------------
-- 1. fn_validar_ingredientes_elaborado_v2(bigint, numeric, bigint)
--    MISMA FIRMA que la viva. Mide con fn_ingredientes_elaborado_base (unidades
--    base, misma funcion que usa el consumo: cierra C1) y responde el jsonb que
--    ya espera la app, con `cantidad_disponible` (= maximo consumible con
--    empaques enteros), `maximo_producible`, `presentacion` y `unidad`.
--    `unidad` sale de la presentacion BASE del ingrediente, no de
--    app_dat_producto_ingredientes.unidad_medida (que en la receta del caso real
--    es null, Â§2-bis).
--
-- 2. fn_descontar_ingredientes_elaborado_v2(bigint, numeric, bigint, bigint, integer)
--    MISMA FIRMA que la viva. Valida TODO antes de escribir y consume ingrediente
--    por ingrediente con fn_consumir_ingrediente_base_v2 (equivalente base exacto,
--    pasada 1 saldo propio + pasada 2 convertible). Mismo contrato jsonb:
--      success -> { status, id_almacen, lineas_afectadas, movimientos } (+ extras)
--      error   -> { status, error_code, message, id_ingrediente, cantidad_requerida,
--                   cantidad_disponible, id_almacen }  (cero escrituras)
--    Si el fallo ocurre DESPUES de haber escrito algun ingrediente, RAISE
--    EXCEPTION en vez de RETURN: la viva devolvia jsonb y confirmaba lo ya escrito
--    (defecto C10, sobreconsumo silencioso). Esto se cierra aqui.
--
-- 3. fn_descontar_venta_enrutada_v2(bigint, numeric, bigint, bigint, integer, boolean)
--    MISMA FIRMA y SECURITY DEFINER que la viva, con search_path corregido
--    (C9) y nombres calificados. Rama receta -> _v2; rama SKU -> 
--    fn_consumir_ingrediente_base_v2 (reemplaza el LEAST mixto de L118) y RAISE
--    defensivo si quedara pendiente.
--
--    p_cantidad va SIEMPRE en unidades base (igual que cuando la viva la llama
--    fn_registrar_venta tras fn_cantidad_en_base). El llamador que venda una
--    presentacion (p. ej. 1 Caja) debe convertir antes con fn_cantidad_en_base.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 31.1 Â· fn_validar_ingredientes_elaborado_v2
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_validar_ingredientes_elaborado_v2(
    p_id_producto_elaborado bigint,
    p_cantidad              numeric,
    p_id_almacen            bigint DEFAULT NULL::bigint
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_catalog
AS $function$
DECLARE
    v_base    jsonb;
    v_ing     jsonb;
    v_falt    jsonb;
    v_detalle jsonb := '[]'::jsonb;
BEGIN
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        -- Se conserva el contrato exacto de la viva para no cambiar el cliente.
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    'La cantidad a producir debe ser positiva',
            'error_code', 'INVALID_QUANTITY'
        );
    END IF;

    v_base := public.fn_ingredientes_elaborado_base(
                  p_id_producto_elaborado, p_cantidad, p_id_almacen, 'almacen');

    IF (v_base->>'status') <> 'success' THEN
        -- Problema estructural (cadena invalida, saldo negativo, sin
        -- presentaciones): se cruza la frontera con el codigo estable y se deja
        -- el motivo fino en `motivo_origen` + el detalle completo.
        RETURN jsonb_build_object(
            'status',        'error',
            'message',       COALESCE(v_base->>'message','No se pudo medir la receta'),
            'error_code',    'INSUFFICIENT_STOCK_INGREDIENT',
            'motivo_origen', v_base->>'error_code',
            'id_ingrediente',(v_base->>'id_ingrediente')::bigint,
            'cantidad_requerida', p_cantidad,
            'id_almacen',    p_id_almacen,
            'alcance',       'almacen',
            'detalle',       v_base);
    END IF;

    FOR v_ing IN
        SELECT value FROM jsonb_array_elements(COALESCE(v_base->'ingredientes','[]'::jsonb))
    LOOP
        v_detalle := v_detalle || jsonb_build_object(
            'id_ingrediente',      (v_ing->>'id_ingrediente')::bigint,
            'ingrediente',         v_ing->>'ingrediente',
            'cantidad_requerida',  (v_ing->>'cantidad_requerida_base')::numeric,
            'cantidad_disponible', (v_ing->>'maximo_producible')::numeric,
            'equivalente_base',    (v_ing->>'equivalente_base')::numeric,
            'maximo_producible',   (v_ing->>'maximo_producible')::numeric,
            'presentacion',        v_ing->>'presentacion_base',
            'unidad',              COALESCE(v_ing->>'unidad','unidad base'),
            'alcanza',             (v_ing->>'alcanza')::boolean,
            'motivo',              v_ing->>'motivo',
            'saldo_por_presentacion', v_ing->'saldo_por_presentacion');
    END LOOP;

    IF NOT COALESCE((v_base->>'alcanza')::boolean,false) THEN
        v_falt := v_base->'faltantes'->0;
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    format('Stock insuficiente para el ingrediente: %s (disponible: %s, requerido: %s %s)',
                                 COALESCE(v_falt->>'ingrediente','#'||COALESCE(v_falt->>'id_ingrediente','?')),
                                 COALESCE(v_falt->>'cantidad_disponible','0'),
                                 COALESCE(v_falt->>'cantidad_requerida_base','0'),
                                 COALESCE(v_falt->>'unidad','unidad base')),
            'error_code', 'INSUFFICIENT_STOCK_INGREDIENT',
            'id_ingrediente',      (v_falt->>'id_ingrediente')::bigint,
            'ingrediente',         v_falt->>'ingrediente',
            'cantidad_requerida',  (v_falt->>'cantidad_requerida_base')::numeric,
            'cantidad_disponible', (v_falt->>'cantidad_disponible')::numeric,
            'maximo_producible',   (v_falt->>'maximo_producible')::numeric,
            'presentacion',        v_falt->>'presentacion',
            'unidad',              COALESCE(v_falt->>'unidad','unidad base'),
            'motivo',              v_falt->>'motivo',
            'id_almacen',          p_id_almacen,
            'alcance',             'almacen',
            'maximo_producible_elaborado', (v_base->>'maximo_producible')::numeric,
            'ingredientes',        v_detalle,
            'faltantes',           v_base->'faltantes');
    END IF;

    RETURN jsonb_build_object(
        'status',            'success',
        'tiene_receta',      (v_base->>'tiene_receta')::boolean,
        'id_almacen',        p_id_almacen,
        'alcance',           'almacen',
        'unidad_cuenta',     'unidad_base',
        'maximo_producible', (v_base->>'maximo_producible')::numeric,
        'ingredientes',      v_detalle);
END;
$function$;

COMMENT ON FUNCTION public.fn_validar_ingredientes_elaborado_v2(bigint,numeric,bigint)
    IS 'Validacion v2 de la receta de un elaborado: mide con fn_ingredientes_elaborado_base (equivalente base + maximo consumible con empaques enteros), mismo contrato jsonb que la viva, con presentacion/unidad y maximo_producible. STABLE, no escribe. Fase 1, archivo 31.';

REVOKE ALL ON FUNCTION public.fn_validar_ingredientes_elaborado_v2(bigint,numeric,bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_validar_ingredientes_elaborado_v2(bigint,numeric,bigint)
    TO authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 31.2 Â· fn_descontar_ingredientes_elaborado_v2
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_descontar_ingredientes_elaborado_v2(
    p_id_producto_elaborado bigint,
    p_cantidad              numeric,
    p_id_almacen            bigint,
    p_id_extraccion         bigint  DEFAULT NULL::bigint,
    p_origen_cambio         integer DEFAULT 4
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SET search_path = public, pg_catalog
AS $function$
DECLARE
    v_val            jsonb;
    v_ing            record;
    v_res            jsonb;
    v_nombre         text;
    v_escrito        boolean := false;
    v_total          integer := 0;
    v_movimientos    jsonb := '[]'::jsonb;
    v_lineas_fisicas jsonb := '[]'::jsonb;
    v_conversiones   jsonb := '[]'::jsonb;
    v_consumidos     jsonb := '[]'::jsonb;
BEGIN
    -- 1 Â· Validar TODO antes de tocar inventario (una sola medida, en base).
    v_val := public.fn_validar_ingredientes_elaborado_v2(
                 p_id_producto_elaborado, p_cantidad, p_id_almacen);

    IF (v_val->>'status') <> 'success' THEN
        RETURN v_val;   -- CERO escrituras
    END IF;

    -- 2 Â· Consumir ingrediente por ingrediente, en orden determinista.
    FOR v_ing IN
        SELECT i.id_ingrediente, i.cantidad_total_necesaria
          FROM public.fn_obtener_ingredientes_recursivos(p_id_producto_elaborado, p_cantidad) i
         ORDER BY i.id_ingrediente
    LOOP
        v_res := public.fn_consumir_ingrediente_base_v2(
                     p_id_producto   := v_ing.id_ingrediente,
                     p_id_almacen    := p_id_almacen,
                     p_cantidad_base := v_ing.cantidad_total_necesaria,
                     p_origen_cambio := p_origen_cambio,
                     p_id_extraccion := p_id_extraccion,
                     p_motivo        := 'consumo_elaborado');

        IF (v_res->>'status') <> 'success' THEN
            SELECT p.denominacion INTO v_nombre
              FROM public.app_dat_producto p WHERE p.id = v_ing.id_ingrediente;

            IF NOT v_escrito THEN
                -- Nada escrito todavia: se conserva el contrato jsonb de la viva
                -- (la app ya sabe leerlo) con los codigos traducidos.
                RETURN jsonb_build_object(
                    'status',     'error',
                    'message',    format('Stock insuficiente para el ingrediente: %s (disponible: %s, requerido: %s %s)',
                                         COALESCE(v_nombre,'#'||v_ing.id_ingrediente),
                                         COALESCE(v_res->>'cantidad_disponible','0'),
                                         v_ing.cantidad_total_necesaria,
                                         COALESCE(v_res->>'presentacion','unidad base')),
                    'error_code', 'INSUFFICIENT_STOCK_INGREDIENT',
                    'id_ingrediente',      v_ing.id_ingrediente,
                    'ingrediente',         v_nombre,
                    'cantidad_requerida',  v_ing.cantidad_total_necesaria,
                    'cantidad_disponible', (v_res->>'cantidad_disponible')::numeric,
                    'maximo_producible',   (v_res->>'maximo_producible')::numeric,
                    'presentacion',        v_res->>'presentacion',
                    'unidad',              COALESCE(v_res->>'presentacion','unidad base'),
                    'motivo',              v_res->>'motivo',
                    'motivo_origen',       v_res->>'error_code',
                    'id_almacen',          p_id_almacen,
                    'respuesta_ingrediente', v_res);
            END IF;

            -- Ya hay movimientos de otros ingredientes: la viva devolvia jsonb y
            -- confirmaba el descuento parcial (C10). Aqui se aborta la transaccion.
            RAISE EXCEPTION 'INSUFFICIENT_STOCK_INGREDIENT: fallo el ingrediente % al descontar la receta del elaborado % en el almacen % (%). Se aborta para no dejar descuento parcial',
                v_ing.id_ingrediente, p_id_producto_elaborado, p_id_almacen,
                COALESCE(v_res->>'message', v_res->>'error_code')
                USING ERRCODE = 'P0001',
                      HINT = 'Defecto C10: si el BOM falla despues de escribir, la transaccion debe revertirse.';
        END IF;

        v_escrito := true;
        v_total   := v_total + COALESCE((v_res->>'lineas_afectadas')::integer,0);
        v_movimientos    := v_movimientos    || COALESCE(v_res->'movimientos','[]'::jsonb);
        v_lineas_fisicas := v_lineas_fisicas || COALESCE(v_res->'lineas_fisicas','[]'::jsonb);
        v_conversiones   := v_conversiones   || COALESCE(v_res->'conversiones','[]'::jsonb);
        v_consumidos := v_consumidos || jsonb_build_object(
            'id_ingrediente',        v_ing.id_ingrediente,
            'cantidad_base',         v_ing.cantidad_total_necesaria,
            'equivalente_consumido', (v_res->>'equivalente_consumido')::numeric,
            'presentacion_base',     v_res->>'presentacion_base',
            'lineas_afectadas',      COALESCE((v_res->>'lineas_afectadas')::integer,0));
    END LOOP;

    RETURN jsonb_build_object(
        'status',           'success',
        'id_almacen',       p_id_almacen,
        'lineas_afectadas', v_total,
        'movimientos',      v_movimientos,
        'lineas_fisicas',   v_lineas_fisicas,
        'conversiones',     v_conversiones,
        'ingredientes_consumidos', v_consumidos);
END;
$function$;

COMMENT ON FUNCTION public.fn_descontar_ingredientes_elaborado_v2(bigint,numeric,bigint,bigint,integer)
    IS 'Descuenta la receta de un elaborado por EQUIVALENTE BASE: valida todo antes de escribir (fn_ingredientes_elaborado_base) y consume por ubicacion con fn_consumir_ingrediente_base_v2 (empaques enteros + conversion auditada). Mismo contrato jsonb que la viva; RAISE si hay que abortar tras escribir (C10). Fase 1, archivo 31.';

REVOKE ALL ON FUNCTION public.fn_descontar_ingredientes_elaborado_v2(bigint,numeric,bigint,bigint,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_descontar_ingredientes_elaborado_v2(bigint,numeric,bigint,bigint,integer)
    TO authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 31.3 Â· fn_descontar_venta_enrutada_v2
-- Copia de la viva (fn_descontar_venta_enrutada, md5 d56b117f2c9307a8c6bfaac29ce5e1e8)
-- con: search_path public+pg_catalog, nombres calificados, rama receta -> _v2 y
-- rama SKU -> fn_consumir_ingrediente_base_v2 (sin LEAST mixto).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_descontar_venta_enrutada_v2(
    p_id_producto          bigint,
    p_cantidad             numeric,
    p_id_tpv               bigint,
    p_id_extraccion        bigint  DEFAULT NULL::bigint,
    p_origen_cambio        integer DEFAULT 4,
    p_ya_descontado_sku    boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $function$
DECLARE
    v_ruta        jsonb;
    v_origen      text;
    v_descontar   text;
    v_id_almacen  bigint;
    v_resultado   jsonb;
    v_disponible  numeric;
BEGIN
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La cantidad debe ser mayor que cero',
            'error_code', 'INVALID_QUANTITY'
        );
    END IF;

    -- 1. Resolver de donde sale y validar el enrutamiento.
    v_ruta := public.fn_resolver_origen_venta(p_id_producto, p_id_tpv);

    IF (v_ruta->>'status') <> 'success' THEN
        RETURN v_ruta;
    END IF;

    v_origen     := v_ruta->>'origen';
    v_descontar  := v_ruta->>'descontar';
    v_id_almacen := (v_ruta->>'id_almacen')::bigint;

    -- 2. Servicio: no hay inventario que mover.
    IF v_descontar = 'nada' THEN
        RETURN v_ruta || jsonb_build_object(
            'descontado', false,
            'message',    'Servicio: sin movimiento de inventario'
        );
    END IF;

    -- 3. Receta: delegar en la cadena _v2 con el almacen resuelto.
    IF v_descontar = 'ingredientes' THEN
        v_resultado := public.fn_descontar_ingredientes_elaborado_v2(
            p_id_producto_elaborado := p_id_producto,
            p_cantidad              := p_cantidad,
            p_id_almacen            := v_id_almacen,
            p_id_extraccion         := p_id_extraccion,
            p_origen_cambio         := p_origen_cambio
        );

        IF (v_resultado->>'status') <> 'success' THEN
            -- Enriquecer el error con el contexto de cocina para que el
            -- vendedor sepa DONDE falta la materia prima.
            RETURN v_resultado || jsonb_build_object(
                'origen',     v_origen,
                'id_almacen', v_id_almacen,
                'id_cocina',  v_ruta->'id_cocina',
                'cocina',     v_ruta->'cocina'
            );
        END IF;

        RETURN v_resultado || jsonb_build_object(
            'origen',     v_origen,
            'id_almacen', v_id_almacen,
            'id_cocina',  v_ruta->'id_cocina',
            'cocina',     v_ruta->'cocina',
            'descontado', true
        );
    END IF;

    -- 4. SKU propio.
    --    En barra la venta ya inserto su movimiento: aqui solo se valida.
    IF v_origen = 'barra' AND p_ya_descontado_sku THEN
        RETURN v_ruta || jsonb_build_object(
            'descontado', false,
            'message',    'Producto de barra: descontado por la funcion de venta'
        );
    END IF;

    -- Validar que alcance antes de mover nada (base contra base).
    v_disponible := public.fn_stock_producto_almacen(p_id_producto, v_id_almacen);

    IF COALESCE(v_disponible, 0) < p_cantidad THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    CASE
                WHEN v_origen = 'cocina_por_tanda' THEN
                    'No hay suficientes porciones preparadas en "'
                    || COALESCE(v_ruta->>'cocina', 'la cocina')
                    || '" (disponibles: ' || COALESCE(v_disponible, 0)
                    || ', requeridas: ' || p_cantidad || ')'
                ELSE
                    'Stock insuficiente (disponible: ' || COALESCE(v_disponible, 0)
                    || ', requerido: ' || p_cantidad || ')'
            END,
            'error_code',          CASE WHEN v_origen = 'cocina_por_tanda'
                                        THEN 'INSUFFICIENT_PORTIONS'
                                        ELSE 'INSUFFICIENT_STOCK' END,
            'origen',              v_origen,
            'id_almacen',          v_id_almacen,
            'id_cocina',           v_ruta->'id_cocina',
            'cocina',              v_ruta->'cocina',
            'cantidad_disponible', COALESCE(v_disponible, 0),
            'cantidad_requerida',  p_cantidad
        );
    END IF;

    -- Descontar por equivalente base, ubicacion por ubicacion (sin LEAST mixto).
    v_resultado := public.fn_consumir_ingrediente_base_v2(
        p_id_producto   => p_id_producto,
        p_id_almacen    => v_id_almacen,
        p_cantidad_base => p_cantidad,
        p_origen_cambio => p_origen_cambio,
        p_id_extraccion => p_id_extraccion,
        p_motivo        => 'venta'
    );

    IF (v_resultado->>'status') <> 'success' THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    CASE
                WHEN v_origen = 'cocina_por_tanda' THEN
                    'No hay suficientes porciones preparadas en "'
                    || COALESCE(v_ruta->>'cocina','la cocina')
                    || '" (disponibles: ' || COALESCE(v_resultado->>'cantidad_disponible','0')
                    || ', requeridas: ' || p_cantidad || ')'
                ELSE
                    'Stock insuficiente (disponible: ' || COALESCE(v_resultado->>'cantidad_disponible','0')
                    || ', requerido: ' || p_cantidad || ')'
            END,
            'error_code',          CASE WHEN v_origen = 'cocina_por_tanda'
                                        THEN 'INSUFFICIENT_PORTIONS'
                                        ELSE 'INSUFFICIENT_STOCK' END,
            'origen',              v_origen,
            'id_almacen',          v_id_almacen,
            'id_cocina',           v_ruta->'id_cocina',
            'cocina',              v_ruta->'cocina',
            'id_producto',         p_id_producto,
            'cantidad_disponible', (v_resultado->>'cantidad_disponible')::numeric,
            'cantidad_requerida',  p_cantidad,
            'maximo_producible',   (v_resultado->>'maximo_producible')::numeric,
            'presentacion',        v_resultado->>'presentacion',
            'motivo',              v_resultado->>'motivo',
            'motivo_origen',       v_resultado->>'error_code',
            'respuesta_ingrediente', v_resultado);
    END IF;

    -- Defensa (C10): si quedara pendiente, abortar en vez de confirmar parcial.
    IF COALESCE((v_resultado->>'equivalente_consumido')::numeric,0) <> p_cantidad THEN
        RAISE EXCEPTION 'DESCUENTO_SKU_INCOMPLETO: se pidio descontar % del producto % en el almacen % y se descontaron %',
            p_cantidad, p_id_producto, v_id_almacen,
            COALESCE(v_resultado->>'equivalente_consumido','0')
            USING ERRCODE = 'P0001',
                  HINT = 'La transaccion debe revertirse para no dejar descuento parcial (C10).';
    END IF;

    RETURN jsonb_build_object(
        'status',      'success',
        'origen',      v_origen,
        'id_almacen',  v_id_almacen,
        'id_cocina',   v_ruta->'id_cocina',
        'cocina',      v_ruta->'cocina',
        'id_producto', p_id_producto,
        'cantidad',    p_cantidad,
        'descontado',  true,
        'lineas_afectadas', COALESCE((v_resultado->>'lineas_afectadas')::integer,0),
        'movimientos',      v_resultado->'movimientos',
        'lineas_fisicas',   v_resultado->'lineas_fisicas',
        'conversiones',     v_resultado->'conversiones');
END;
$function$;

COMMENT ON FUNCTION public.fn_descontar_venta_enrutada_v2(bigint,numeric,bigint,bigint,integer,boolean)
    IS 'Enrutado de descuento con search_path corregido (C9): rama receta -> fn_descontar_ingredientes_elaborado_v2; rama SKU -> fn_consumir_ingrediente_base_v2 en unidades base (sin LEAST mixto) con RAISE si quedara pendiente. Misma firma y mismos codigos de error que la viva. Fase 1, archivo 31.';

REVOKE ALL ON FUNCTION public.fn_descontar_venta_enrutada_v2(bigint,numeric,bigint,bigint,integer,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_descontar_venta_enrutada_v2(bigint,numeric,bigint,bigint,integer,boolean)
    TO authenticated, service_role;


-- ============================================================================
-- VERIFICACION (correr despues de aplicar; no modifica datos)
-- ============================================================================
-- V1 Â· Frontera del contrato de error: la viva y la _v2 devuelven las mismas
--      claves en el exito.
--
--   SELECT public.fn_validar_ingredientes_elaborado(10800, 10, 331) AS viva,
--          public.fn_validar_ingredientes_elaborado_v2(10800, 10, 331) AS v2;
--   -- esperado: las dos status success, tiene_receta true, id_almacen 331 e
--   --           `ingredientes` con cantidad_requerida / cantidad_disponible.
--
-- V2 Â· Caso real de insuficiencia (11007 en el almacen 331: maximo consumible
--      860 con empaques enteros): la validacion v2 rechaza 1000 y el descuento
--      NO escribe ninguna fila.
--
--   SELECT public.fn_validar_ingredientes_elaborado_v2(<elaborado_con_11007>, 1, 331) AS validacion;
--   SELECT count(*) FROM public.app_dat_inventario_productos
--    WHERE id_producto = 11007 AND id_ubicacion = 349;   -- antes y despues: igual
--
-- V3 Â· No-regresion de firmas y privilegios (las vivas no se tocan):
--
--   SELECT p.oid::regprocedure::text AS firma, p.prosecdef, p.proconfig, p.proacl
--     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname='public' AND p.proname IN (
--      'fn_descontar_venta_enrutada','fn_descontar_venta_enrutada_v2',
--      'fn_descontar_ingredientes_elaborado','fn_descontar_ingredientes_elaborado_v2',
--      'fn_validar_ingredientes_elaborado','fn_validar_ingredientes_elaborado_v2')
--    ORDER BY 1;
-- ============================================================================