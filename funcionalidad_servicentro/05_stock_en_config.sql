-- ============================================================================
-- 05 · Stock en fn_get_servicentro_config + filtros vendible/combustible
-- ============================================================================
-- El sync del TPV usa fn_get_servicentro_config; sin stock_disponible el grid
-- no puede deshabilitar cartas sin inventario.
-- Idempotente. Aplicar en SQL Editor (o tras 04_rpcs_tpv.sql).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_get_servicentro_config(
    p_id_tpv bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_id_tienda  bigint;
    v_id_almacen bigint;
    v_modo       boolean := false;
    v_columnas   smallint := 2;
    v_nombre     text;
    v_productos  jsonb;
BEGIN
    SELECT tpv.id_tienda,
           tpv.id_almacen,
           COALESCE(tpv.modo_servicentro, false),
           COALESCE(tpv.servicentro_columnas, 2),
           tpv.denominacion
      INTO v_id_tienda, v_id_almacen, v_modo, v_columnas, v_nombre
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
        SELECT
            sp.id,
            sp.id_producto,
            sp.orden,
            sp.color,
            p.denominacion,
            p.sku,
            p.um,
            p.imagen,
            p.es_combustible,
            p.es_vendible,
            COALESCE(pv.precio_venta_cup, 0) AS precio_venta,
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
           AND COALESCE(p.es_combustible, false) = true
           AND COALESCE(p.es_vendible, false) = true
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
