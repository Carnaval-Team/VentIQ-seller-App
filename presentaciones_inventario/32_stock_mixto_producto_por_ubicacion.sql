-- ============================================================================
-- 32 · Stock mixto de un producto por ubicación
-- ============================================================================
-- RPC aditiva para la ficha de producto. Devuelve una fila por ubicación con
-- stock vigente, sin sumar cantidades físicas de presentaciones diferentes.
--
-- Seguridad: SECURITY INVOKER, search_path vacío, objetos calificados, acceso a
-- tienda validado y EXECUTE limitado a authenticated. No reemplaza funciones
-- consumidas por clientes existentes.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_stock_mixto_producto_por_ubicacion(
    p_id_producto bigint,
    p_id_almacen  bigint DEFAULT NULL::bigint
)
RETURNS TABLE (
    id_almacen             bigint,
    almacen                varchar,
    id_ubicacion           bigint,
    ubicacion              varchar,
    stock_desglose         jsonb,
    stock_texto            text,
    stock_texto_corto      text,
    stock_equivalente_base numeric
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
    v_id_tienda bigint;
BEGIN
    -- check_user_has_access_to_tienda resuelve tablas SIN calificar
    -- (app_dat_vendedor, etc.). Con el SET search_path = '' de proconfig
    -- fallaria con «relation "app_dat_vendedor" does not exist» (42P01).
    -- Restauramos public, pg_catalog ANTES de la guarda. El cambio persiste
    -- hasta el fin de la transaccion de la llamada RPC.
    PERFORM set_config('search_path', 'public, pg_catalog', false);

    SELECT p.id_tienda
      INTO v_id_tienda
      FROM public.app_dat_producto AS p
     WHERE p.id = p_id_producto;

    IF v_id_tienda IS NULL THEN
        RETURN;
    END IF;

    PERFORM public.check_user_has_access_to_tienda(v_id_tienda);

    IF p_id_almacen IS NOT NULL
       AND NOT EXISTS (
           SELECT 1
             FROM public.app_dat_almacen AS a
            WHERE a.id = p_id_almacen
              AND a.id_tienda = v_id_tienda
              AND a.deleted_at IS NULL
       ) THEN
        RAISE EXCEPTION 'El almacén % no pertenece a la tienda del producto %',
            p_id_almacen, p_id_producto
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    WITH vigente AS (
        SELECT DISTINCT ON (
                   ip.id_ubicacion,
                   COALESCE(ip.id_variante, 0),
                   COALESCE(ip.id_opcion_variante, 0),
                   ip.id_presentacion
               )
               la.id_almacen,
               a.denominacion AS almacen_nombre,
               ip.id_ubicacion,
               la.denominacion AS ubicacion_nombre,
               ip.id_presentacion,
               COALESCE(ip.cantidad_final, 0)::numeric AS saldo
          FROM public.app_dat_inventario_productos AS ip
          JOIN public.app_dat_layout_almacen AS la
            ON la.id = ip.id_ubicacion
           AND la.deleted_at IS NULL
          JOIN public.app_dat_almacen AS a
            ON a.id = la.id_almacen
           AND a.deleted_at IS NULL
         WHERE ip.id_producto = p_id_producto
           AND a.id_tienda = v_id_tienda
           AND (p_id_almacen IS NULL OR la.id_almacen = p_id_almacen)
         ORDER BY ip.id_ubicacion,
                  COALESCE(ip.id_variante, 0),
                  COALESCE(ip.id_opcion_variante, 0),
                  ip.id_presentacion,
                  ip.id DESC
    ),
    por_presentacion AS (
        SELECT v.id_almacen,
               v.almacen_nombre,
               v.id_ubicacion,
               v.ubicacion_nombre,
               v.id_presentacion,
               MIN(c.nombre)::varchar AS presentacion_nombre,
               MIN(c.sku_codigo)::varchar AS presentacion_sku,
               MIN(c.factor_rel)::numeric AS factor_rel,
               BOOL_OR(COALESCE(c.es_base, false)) AS es_base,
               MIN(c.nivel)::integer AS nivel,
               SUM(v.saldo)::numeric AS saldo,
               SUM(v.saldo * COALESCE(c.factor_rel, 1))::numeric AS equivalente_base
          FROM vigente AS v
          LEFT JOIN LATERAL public.fn_presentaciones_producto(p_id_producto) AS c
            ON c.id_presentacion = v.id_presentacion
         GROUP BY v.id_almacen, v.almacen_nombre, v.id_ubicacion,
                  v.ubicacion_nombre, v.id_presentacion
        HAVING SUM(v.saldo) <> 0
    ),
    por_ubicacion AS (
        SELECT pp.id_almacen,
               pp.almacen_nombre,
               pp.id_ubicacion,
               pp.ubicacion_nombre,
               jsonb_agg(
                   jsonb_build_object(
                       'id_presentacion', pp.id_presentacion,
                       'nombre', COALESCE(pp.presentacion_nombre, 'Presentación'),
                       'sku_codigo', pp.presentacion_sku,
                       'cantidad', pp.saldo,
                       'factor_rel', COALESCE(pp.factor_rel, 1),
                       'es_base', pp.es_base,
                       'nivel', pp.nivel,
                       'equivalente_base', pp.equivalente_base
                   ) ORDER BY pp.nivel NULLS LAST, pp.id_presentacion
               ) AS desglose,
               SUM(pp.equivalente_base)::numeric AS equivalente_base
          FROM por_presentacion AS pp
         GROUP BY pp.id_almacen, pp.almacen_nombre,
                  pp.id_ubicacion, pp.ubicacion_nombre
    )
    SELECT pu.id_almacen,
           pu.almacen_nombre,
           pu.id_ubicacion,
           pu.ubicacion_nombre,
           pu.desglose,
           public.fn_formatear_stock_mixto(pu.desglose, false, 'Sin stock'),
           public.fn_formatear_stock_mixto(pu.desglose, true, 'Sin stock'),
           pu.equivalente_base
      FROM por_ubicacion AS pu
     ORDER BY pu.almacen_nombre, pu.ubicacion_nombre, pu.id_ubicacion;
END;
$function$;

COMMENT ON FUNCTION public.fn_stock_mixto_producto_por_ubicacion(bigint, bigint) IS
'Stock vigente de un producto por ubicación. Conserva el desglose físico por '
'presentación y devuelve por separado su equivalente en unidades base. Valida '
'acceso a la tienda; no suma cantidades físicas heterogéneas.';

REVOKE ALL ON FUNCTION public.fn_stock_mixto_producto_por_ubicacion(bigint, bigint)
    FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_stock_mixto_producto_por_ubicacion(bigint, bigint)
    FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_stock_mixto_producto_por_ubicacion(bigint, bigint)
    TO authenticated;
