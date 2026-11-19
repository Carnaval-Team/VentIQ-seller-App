CREATE OR REPLACE FUNCTION public.fn_devolver_ingredientes_elaborado_v2(p_id_producto_elaborado bigint, p_cantidad numeric, p_id_almacen bigint, p_id_extraccion bigint DEFAULT NULL::bigint, p_origen_cambio integer DEFAULT 4)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_ing             RECORD;
    v_plan            jsonb   := '[]'::jsonb;
    v_paso            jsonb;
    v_id_ubicacion    bigint;
    v_id_presentacion bigint;
    v_nombre_pres     varchar;
    v_factor_base     numeric;
    v_es_fraccionable boolean;
    v_cantidad_base   numeric;
    v_cantidad_fisica numeric;
    v_variante        bigint;
    v_opcion          bigint;
    v_actual          numeric;
    v_sku_producto    varchar;
    v_sku_ubicacion   varchar;
    v_movimientos     jsonb   := '[]'::jsonb;
    v_lineas          integer := 0;
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

    -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    -- PASADA 1 Â· resolver y validar TODO, sin escribir
    --   (atomicidad: si algo no cuadra se sale con status='error' y 0 filas)
    -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    FOR v_ing IN
        SELECT i.id_ingrediente, i.cantidad_total_necesaria
          FROM public.fn_obtener_ingredientes_recursivos(p_id_producto_elaborado, p_cantidad) i
         ORDER BY i.id_ingrediente
    LOOP
        v_cantidad_base := COALESCE(v_ing.cantidad_total_necesaria, 0);

        IF v_cantidad_base <= 0 THEN
            CONTINUE;   -- nada que devolver por este ingrediente
        END IF;

        -- (1) ubicacion destino dentro del almacen (helper vivo, sin cambios)
        v_id_ubicacion := public.fn_ubicacion_destino_devolucion(v_ing.id_ingrediente, p_id_almacen);

        IF v_id_ubicacion IS NULL THEN
            RETURN jsonb_build_object(
                'status',         'error',
                'message',        'El almacen no tiene ubicacion donde devolver el ingrediente: '
                                  || COALESCE((SELECT p.denominacion FROM public.app_dat_producto p
                                                WHERE p.id = v_ing.id_ingrediente),
                                              '#' || v_ing.id_ingrediente),
                'error_code',     'NO_RETURN_LOCATION',
                'id_ingrediente', v_ing.id_ingrediente,
                'id_almacen',     p_id_almacen
            );
        END IF;

        -- (2) presentacion BASE del ingrediente: misma cascada canonica que
        --     fn_presentaciones_producto (es_base DESC, menor factor, menor id).
        --     Su factor_rel es 1 por definicion, pero NO se asume: se lee.
        SELECT c.id_presentacion, c.nombre, COALESCE(c.factor_rel, 1), COALESCE(c.es_fraccionable, false)
          INTO v_id_presentacion, v_nombre_pres, v_factor_base, v_es_fraccionable
          FROM public.fn_presentaciones_producto(v_ing.id_ingrediente) c
         ORDER BY c.es_base DESC, c.factor_rel ASC NULLS LAST, c.id_presentacion ASC
         LIMIT 1;

        IF v_id_presentacion IS NULL THEN
            RETURN jsonb_build_object(
                'status',         'error',
                'message',        'El ingrediente no tiene presentaciones configuradas: '
                                  || COALESCE((SELECT p.denominacion FROM public.app_dat_producto p
                                                WHERE p.id = v_ing.id_ingrediente),
                                              '#' || v_ing.id_ingrediente),
                'error_code',     'NO_BASE_PRESENTATION',
                'id_ingrediente', v_ing.id_ingrediente,
                'id_almacen',     p_id_almacen
            );
        END IF;

        IF v_factor_base IS NULL OR v_factor_base <= 0 THEN
            RETURN jsonb_build_object(
                'status',         'error',
                'message',        'CATALOGO_PRESENTACIONES_INVALIDO: el ingrediente '
                                  || v_ing.id_ingrediente || ' tiene factor_rel ' || v_factor_base
                                  || ' en su presentacion base',
                'error_code',     'CATALOGO_PRESENTACIONES_INVALIDO',
                'id_ingrediente', v_ing.id_ingrediente,
                'id_almacen',     p_id_almacen
            );
        END IF;

        -- (3) equivalente base -> unidades FISICAS de esa presentacion
        v_cantidad_fisica := v_cantidad_base / v_factor_base;

        IF round(v_cantidad_fisica * v_factor_base, 6) <> round(v_cantidad_base, 6) THEN
            RETURN jsonb_build_object(
                'status',         'error',
                'message',        'Devolucion no exacta: ' || v_cantidad_base || ' base del ingrediente '
                                  || v_ing.id_ingrediente || ' no es multiplo exacto de '
                                  || COALESCE(v_nombre_pres, 'la presentacion base')
                                  || ' (factor ' || v_factor_base || ')',
                'error_code',     'NON_INTEGER_DECOMPOSITION',
                'id_ingrediente', v_ing.id_ingrediente,
                'id_almacen',     p_id_almacen
            );
        END IF;

        -- Sin fracciones de empaque salvo que la presentacion sea fraccionable.
        IF NOT v_es_fraccionable AND v_cantidad_fisica <> trunc(v_cantidad_fisica) THEN
            RETURN jsonb_build_object(
                'status',         'error',
                'message',        'Devolucion con fraccion de empaque: ' || v_cantidad_fisica || ' '
                                  || COALESCE(v_nombre_pres, 'unidades') || ' del ingrediente '
                                  || v_ing.id_ingrediente || ' (no fraccionable)',
                'error_code',     'NON_INTEGER_DECOMPOSITION',
                'id_ingrediente', v_ing.id_ingrediente,
                'id_almacen',     p_id_almacen
            );
        END IF;

        v_plan := v_plan || jsonb_build_object(
            'id_ingrediente',  v_ing.id_ingrediente,
            'id_ubicacion',    v_id_ubicacion,
            'id_presentacion', v_id_presentacion,
            'presentacion',    v_nombre_pres,
            'factor_rel',      v_factor_base,
            'cantidad_base',   v_cantidad_base,
            'cantidad_fisica', v_cantidad_fisica
        );
    END LOOP;

    -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    -- PASADA 2 Â· escribir el plan (una fila de ledger por ingrediente)
    -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    FOR v_paso IN SELECT e.value FROM jsonb_array_elements(v_plan) AS e
    LOOP
        -- Fila VIGENTE de ESA presentacion base en la ubicacion destino.
        -- Mismo criterio que fn_stock_saldos_presentacion (ultima fila por clave
        -- ubicacion + variante + opcion + presentacion). Si no hay fila, se parte
        -- de 0: el saldo de la presentacion base en esa ubicacion es 0.
        SELECT DISTINCT ON (COALESCE(ip.id_variante, 0), COALESCE(ip.id_opcion_variante, 0))
               ip.id_variante,
               ip.id_opcion_variante,
               COALESCE(ip.cantidad_final, 0),
               ip.sku_producto,
               ip.sku_ubicacion
          INTO v_variante, v_opcion, v_actual, v_sku_producto, v_sku_ubicacion
          FROM public.app_dat_inventario_productos ip
         WHERE ip.id_producto     = (v_paso->>'id_ingrediente')::bigint
           AND ip.id_ubicacion    = (v_paso->>'id_ubicacion')::bigint
           AND ip.id_presentacion = (v_paso->>'id_presentacion')::bigint
         ORDER BY COALESCE(ip.id_variante, 0), COALESCE(ip.id_opcion_variante, 0), ip.id DESC
         LIMIT 1;

        v_actual := COALESCE(v_actual, 0);

        IF v_sku_producto IS NULL THEN
            SELECT p.sku INTO v_sku_producto
              FROM public.app_dat_producto p
             WHERE p.id = (v_paso->>'id_ingrediente')::bigint;
        END IF;

        IF v_sku_ubicacion IS NULL THEN
            SELECT la.sku_codigo INTO v_sku_ubicacion
              FROM public.app_dat_layout_almacen la
             WHERE la.id = (v_paso->>'id_ubicacion')::bigint;
        END IF;

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
            (v_paso->>'id_ingrediente')::bigint,
            v_variante,
            v_opcion,
            (v_paso->>'id_ubicacion')::bigint,
            (v_paso->>'id_presentacion')::bigint,
            v_actual,
            v_actual + (v_paso->>'cantidad_fisica')::numeric,
            v_sku_producto,
            v_sku_ubicacion,
            p_origen_cambio,
            p_id_extraccion,
            now()
        );

        v_movimientos := v_movimientos || jsonb_build_object(
            'id_ingrediente',  (v_paso->>'id_ingrediente')::bigint,
            'id_ubicacion',    (v_paso->>'id_ubicacion')::bigint,
            'id_presentacion', (v_paso->>'id_presentacion')::bigint,
            'presentacion',    v_paso->>'presentacion',
            'factor_rel',      (v_paso->>'factor_rel')::numeric,
            'devuelto',        (v_paso->>'cantidad_fisica')::numeric,   -- unidades fisicas
            'devuelto_base',   (v_paso->>'cantidad_base')::numeric,     -- equivalente base
            'stock_previo',    v_actual,
            'stock_nuevo',     v_actual + (v_paso->>'cantidad_fisica')::numeric
        );

        v_lineas := v_lineas + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'status',           'success',
        'id_almacen',       p_id_almacen,
        'lineas_afectadas', v_lineas,
        'presentacion',     'base',
        'movimientos',      v_movimientos
    );
END;
$function$

