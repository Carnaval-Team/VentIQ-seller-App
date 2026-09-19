-- ============================================================================
-- 04 · RPCs servicentro por TPV
-- ============================================================================
-- REQUISITO: 03_migracion_tpv.sql aplicado.
-- Idempotente. DROP de firmas viejas (por tienda) + CREATE por TPV.
-- ============================================================================


-- Quitar firmas antiguas (p_id_tienda)
DROP FUNCTION IF EXISTS public.fn_set_modo_servicentro(bigint, boolean, smallint);
DROP FUNCTION IF EXISTS public.fn_get_servicentro_config(bigint);
DROP FUNCTION IF EXISTS public.fn_listar_servicentro_productos(bigint, bigint);
DROP FUNCTION IF EXISTS public.fn_upsert_servicentro_producto(bigint, bigint, smallint, text);
DROP FUNCTION IF EXISTS public.fn_eliminar_servicentro_producto(bigint, bigint);
DROP FUNCTION IF EXISTS public.fn_reordenar_servicentro_productos(bigint, bigint[]);


-- Helper: resuelve tienda del TPV y exige gerente
CREATE OR REPLACE FUNCTION public.fn_require_gerente_tpv(p_id_tpv bigint)
RETURNS bigint  -- id_tienda
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_id_tienda bigint;
BEGIN
    SELECT tpv.id_tienda INTO v_id_tienda
      FROM public.app_dat_tpv tpv
     WHERE tpv.id = p_id_tpv;

    IF v_id_tienda IS NULL THEN
        RAISE EXCEPTION 'TPV no encontrado'
            USING ERRCODE = 'P0002';
    END IF;

    PERFORM public.fn_require_gerente_tienda(v_id_tienda);
    RETURN v_id_tienda;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_require_gerente_tpv(bigint)
    TO authenticated, service_role;


-- ----------------------------------------------------------------------------
-- fn_set_modo_servicentro (por TPV)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_set_modo_servicentro(
    p_id_tpv               bigint,
    p_activo               boolean,
    p_servicentro_columnas smallint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_id_tienda bigint;
    v_columnas  smallint;
BEGIN
    v_id_tienda := public.fn_require_gerente_tpv(p_id_tpv);

    SELECT tpv.servicentro_columnas INTO v_columnas
      FROM public.app_dat_tpv tpv
     WHERE tpv.id = p_id_tpv;

    IF p_servicentro_columnas IS NOT NULL THEN
        IF p_servicentro_columnas < 1 OR p_servicentro_columnas > 4 THEN
            RETURN jsonb_build_object(
                'status', 'error',
                'message', 'servicentro_columnas debe estar entre 1 y 4',
                'error_code', 'COLUMNAS_INVALIDAS'
            );
        END IF;
        v_columnas := p_servicentro_columnas;
    END IF;

    UPDATE public.app_dat_tpv
       SET modo_servicentro = p_activo,
           servicentro_columnas = COALESCE(v_columnas, 2)
     WHERE id = p_id_tpv;

    RETURN jsonb_build_object(
        'status', 'success',
        'id_tpv', p_id_tpv,
        'id_tienda', v_id_tienda,
        'modo_servicentro', p_activo,
        'servicentro_columnas', COALESCE(v_columnas, 2)
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_set_modo_servicentro(bigint, boolean, smallint)
    TO authenticated, anon, service_role;


-- ----------------------------------------------------------------------------
-- fn_get_servicentro_config (por TPV)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_get_servicentro_config(
    p_id_tpv bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_id_tienda bigint;
    v_modo      boolean := false;
    v_columnas  smallint := 2;
    v_nombre    text;
    v_productos jsonb;
BEGIN
    SELECT tpv.id_tienda, COALESCE(tpv.modo_servicentro, false),
           COALESCE(tpv.servicentro_columnas, 2), tpv.denominacion
      INTO v_id_tienda, v_modo, v_columnas, v_nombre
      FROM public.app_dat_tpv tpv
     WHERE tpv.id = p_id_tpv;

    IF v_id_tienda IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'TPV no encontrado',
            'error_code', 'TPV_NOT_FOUND'
        );
    END IF;

    PERFORM public.check_user_has_access_to_tienda(v_id_tienda);

    SELECT COALESCE(jsonb_agg(row_to_json(x)::jsonb ORDER BY x.orden, x.id), '[]'::jsonb)
      INTO v_productos
      FROM (
        SELECT sp.id,
               sp.id_producto,
               sp.orden,
               sp.color,
               p.denominacion,
               p.sku,
               p.um,
               p.imagen,
               p.es_combustible,
               p.es_vendible,
               COALESCE(pv.precio_venta_cup, 0) AS precio_venta
          FROM public.app_dat_servicentro_producto sp
          JOIN public.app_dat_producto p ON p.id = sp.id_producto
          LEFT JOIN LATERAL (
              SELECT pv_inner.precio_venta_cup
                FROM public.app_dat_precio_venta pv_inner
               WHERE pv_inner.id_producto = p.id
                 AND (pv_inner.id_variante IS NULL OR pv_inner.id_variante = 0)
                 AND (pv_inner.fecha_hasta IS NULL OR pv_inner.fecha_hasta >= CURRENT_DATE)
               ORDER BY pv_inner.fecha_desde DESC
               LIMIT 1
          ) pv ON TRUE
         WHERE sp.id_tpv = p_id_tpv
           AND p.deleted_at IS NULL
      ) x;

    RETURN jsonb_build_object(
        'status', 'success',
        'id_tpv', p_id_tpv,
        'id_tienda', v_id_tienda,
        'tpv_denominacion', v_nombre,
        'modo_servicentro', v_modo,
        'servicentro_columnas', v_columnas,
        'productos', v_productos
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_get_servicentro_config(bigint)
    TO authenticated, anon, service_role;


-- ----------------------------------------------------------------------------
-- fn_listar_servicentro_productos (grid vendedor por TPV)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_listar_servicentro_productos(
    p_id_tpv bigint
)
RETURNS TABLE (
    id                bigint,
    id_producto       bigint,
    orden             smallint,
    color             text,
    denominacion      text,
    sku               text,
    um                text,
    imagen            text,
    precio_venta      numeric,
    stock_disponible  numeric,
    tiene_stock       boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_id_tienda  bigint;
    v_id_almacen bigint;
BEGIN
    SELECT tpv.id_tienda, tpv.id_almacen
      INTO v_id_tienda, v_id_almacen
      FROM public.app_dat_tpv tpv
     WHERE tpv.id = p_id_tpv;

    IF v_id_tienda IS NULL THEN
        RETURN;
    END IF;

    PERFORM public.check_user_has_access_to_tienda(v_id_tienda);

    RETURN QUERY
    SELECT
        sp.id,
        sp.id_producto,
        sp.orden,
        sp.color,
        p.denominacion::text,
        p.sku::text,
        p.um::text,
        p.imagen::text,
        COALESCE(pv.precio_venta_cup, 0)::numeric AS precio_venta,
        COALESCE((
            SELECT SUM(ip.cantidad_final)
              FROM public.app_dat_inventario_productos ip
              JOIN public.app_dat_layout_almacen la ON ip.id_ubicacion = la.id
             WHERE ip.id_producto = p.id
               AND la.id_almacen = v_id_almacen
               AND ip.cantidad_final > 0
               AND ip.id = (
                   SELECT MAX(ip2.id)
                     FROM public.app_dat_inventario_productos ip2
                    WHERE ip2.id_producto = ip.id_producto
                      AND COALESCE(ip2.id_variante, 0) = COALESCE(ip.id_variante, 0)
                      AND COALESCE(ip2.id_opcion_variante, 0) = COALESCE(ip.id_opcion_variante, 0)
                      AND COALESCE(ip2.id_presentacion, 0) = COALESCE(ip.id_presentacion, 0)
                      AND COALESCE(ip2.id_ubicacion, 0) = COALESCE(ip.id_ubicacion, 0)
               )
        ), 0)::numeric AS stock_disponible,
        COALESCE((
            SELECT SUM(ip.cantidad_final) > 0
              FROM public.app_dat_inventario_productos ip
              JOIN public.app_dat_layout_almacen la ON ip.id_ubicacion = la.id
             WHERE ip.id_producto = p.id
               AND la.id_almacen = v_id_almacen
               AND ip.cantidad_final > 0
               AND ip.id = (
                   SELECT MAX(ip2.id)
                     FROM public.app_dat_inventario_productos ip2
                    WHERE ip2.id_producto = ip.id_producto
                      AND COALESCE(ip2.id_variante, 0) = COALESCE(ip.id_variante, 0)
                      AND COALESCE(ip2.id_opcion_variante, 0) = COALESCE(ip.id_opcion_variante, 0)
                      AND COALESCE(ip2.id_presentacion, 0) = COALESCE(ip.id_presentacion, 0)
                      AND COALESCE(ip2.id_ubicacion, 0) = COALESCE(ip.id_ubicacion, 0)
               )
        ), false) AS tiene_stock
    FROM public.app_dat_servicentro_producto sp
    JOIN public.app_dat_producto p ON p.id = sp.id_producto
    LEFT JOIN LATERAL (
        SELECT pv_inner.precio_venta_cup
          FROM public.app_dat_precio_venta pv_inner
         WHERE pv_inner.id_producto = p.id
           AND (pv_inner.id_variante IS NULL OR pv_inner.id_variante = 0)
           AND (pv_inner.fecha_hasta IS NULL OR pv_inner.fecha_hasta >= CURRENT_DATE)
         ORDER BY pv_inner.fecha_desde DESC
         LIMIT 1
    ) pv ON TRUE
    WHERE sp.id_tpv = p_id_tpv
      AND p.deleted_at IS NULL
      AND p.es_combustible = true
      AND p.es_vendible = true
    ORDER BY sp.orden ASC, sp.id ASC;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_listar_servicentro_productos(bigint)
    TO authenticated, anon, service_role;


-- ----------------------------------------------------------------------------
-- fn_upsert_servicentro_producto
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_upsert_servicentro_producto(
    p_id_tpv      bigint,
    p_id_producto bigint,
    p_orden       smallint DEFAULT NULL,
    p_color       text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_id_tienda bigint;
    v_id        bigint;
    v_orden     smallint;
    v_color     text;
BEGIN
    v_id_tienda := public.fn_require_gerente_tpv(p_id_tpv);

    v_color := COALESCE(NULLIF(trim(p_color), ''), '#64748B');
    IF v_color !~ '^#[0-9A-Fa-f]{6}$' THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'color debe ser hex #RRGGBB',
            'error_code', 'COLOR_INVALIDO'
        );
    END IF;

    IF p_orden IS NULL THEN
        SELECT COALESCE(MAX(sp.orden), -1) + 1
          INTO v_orden
          FROM public.app_dat_servicentro_producto sp
         WHERE sp.id_tpv = p_id_tpv;
    ELSE
        v_orden := p_orden;
    END IF;

    INSERT INTO public.app_dat_servicentro_producto
        (id_tienda, id_tpv, id_producto, orden, color)
    VALUES (v_id_tienda, p_id_tpv, p_id_producto, v_orden, v_color)
    ON CONFLICT (id_tpv, id_producto) DO UPDATE
        SET orden = COALESCE(p_orden, public.app_dat_servicentro_producto.orden),
            color = CASE
                      WHEN NULLIF(trim(p_color), '') IS NULL
                        THEN public.app_dat_servicentro_producto.color
                      ELSE v_color
                    END,
            updated_at = now()
    RETURNING id, orden, color INTO v_id, v_orden, v_color;

    RETURN jsonb_build_object(
        'status', 'success',
        'id', v_id,
        'id_tpv', p_id_tpv,
        'id_tienda', v_id_tienda,
        'id_producto', p_id_producto,
        'orden', v_orden,
        'color', v_color
    );
EXCEPTION
    WHEN check_violation OR foreign_key_violation THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', SQLERRM,
            'error_code', 'SERVICENTRO_PRODUCTO_INVALIDO'
        );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_upsert_servicentro_producto(bigint, bigint, smallint, text)
    TO authenticated, anon, service_role;


-- ----------------------------------------------------------------------------
-- fn_eliminar_servicentro_producto
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_eliminar_servicentro_producto(
    p_id_tpv      bigint,
    p_id_producto bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_deleted int;
BEGIN
    PERFORM public.fn_require_gerente_tpv(p_id_tpv);

    DELETE FROM public.app_dat_servicentro_producto
     WHERE id_tpv = p_id_tpv
       AND id_producto = p_id_producto;

    GET DIAGNOSTICS v_deleted = ROW_COUNT;

    IF v_deleted = 0 THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El producto no está en la lista servicentro de este TPV',
            'error_code', 'NOT_FOUND'
        );
    END IF;

    RETURN jsonb_build_object(
        'status', 'success',
        'id_tpv', p_id_tpv,
        'id_producto', p_id_producto
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_eliminar_servicentro_producto(bigint, bigint)
    TO authenticated, anon, service_role;


-- ----------------------------------------------------------------------------
-- fn_reordenar_servicentro_productos
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_reordenar_servicentro_productos(
    p_id_tpv        bigint,
    p_ids_producto  bigint[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_i int;
    v_updated int := 0;
BEGIN
    PERFORM public.fn_require_gerente_tpv(p_id_tpv);

    IF p_ids_producto IS NULL OR array_length(p_ids_producto, 1) IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'p_ids_producto no puede estar vacío',
            'error_code', 'EMPTY_ORDER'
        );
    END IF;

    FOR v_i IN 1 .. array_length(p_ids_producto, 1) LOOP
        UPDATE public.app_dat_servicentro_producto
           SET orden = (v_i - 1),
               updated_at = now()
         WHERE id_tpv = p_id_tpv
           AND id_producto = p_ids_producto[v_i];
        IF FOUND THEN
            v_updated := v_updated + 1;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'status', 'success',
        'actualizados', v_updated,
        'orden', to_jsonb(p_ids_producto)
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_reordenar_servicentro_productos(bigint, bigint[])
    TO authenticated, anon, service_role;
