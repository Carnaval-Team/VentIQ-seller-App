-- ============================================================================
-- 31 · Resumen de inventario v3 con stock mixto
-- ============================================================================
-- Wrapper aditivo de la v2 viva. Conserva sus 14 columnas, en el mismo orden,
-- y agrega exclusivamente las cuatro columnas stock_* al final.
--
-- Contrato v2 confirmado el 2026-09-09 en contracts/README.md. La v2 queda
-- intacta. La descripción del producto no forma parte de v2 ni de v3.
--
-- |-- Seguridad propia: SECURITY INVOKER, search_path vacío, objetos calificados,
-- |-- validación de acceso y EXECUTE limitado a authenticated. No se copia la
-- |-- condición SECURITY DEFINER ni el ACL amplio de la v2. Antes de invocar la v2
-- |-- restaura search_path a public, pg_catalog (la v2 resuelve relaciones sin
-- |-- calificar); proconfig lo vuelve a restaurar al salir.
-- |-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_inventario_resumen_por_usuario_almacen3(
    p_id_tienda          bigint,
    p_id_almacen         bigint DEFAULT NULL::bigint,
    p_busqueda           text DEFAULT NULL::text,
    p_mostrar_sin_stock  boolean DEFAULT NULL::boolean,
    p_filtro_stock       text DEFAULT NULL::text,
    p_limite             integer DEFAULT 20,
    p_pagina             integer DEFAULT 1
)
RETURNS TABLE (
    prod_id                  bigint,
    prod_nombre              varchar,
    prod_sku                 varchar,
    variante_id              bigint,
    variante_valor           varchar,
    opcion_variante_id       bigint,
    opcion_variante_valor    varchar,
    cant_unidades_base       numeric,
    cant_almacen_total       numeric,
    stock_disponible         numeric,
    stock_reservado          numeric,
    zonas_count              integer,
    presentaciones_count     integer,
    total_count              bigint,
    stock_desglose           jsonb,
    stock_texto              text,
    stock_texto_corto        text,
    stock_equivalente_base   numeric
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
BEGIN
    -- La guarda de acceso (check_user_has_access_to_tienda) y la v2 envuelta
    -- resuelven relaciones SIN calificar (app_dat_vendedor, app_dat_almacenero,
    -- etc.). Con el SET search_path = '' de proconfig ambas fallan en runtime
    -- con «relation "app_dat_vendedor" does not exist» (42P01). Por eso
    -- restauramos public, pg_catalog ANTES de cualquier query, incluida la
    -- guarda. El cambio persiste hasta el fin de la transaccion de la llamada
    -- RPC, que en la practica termina cuando la funcion devuelve.
    PERFORM set_config('search_path', 'public, pg_catalog', false);

    PERFORM public.check_user_has_access_to_tienda(p_id_tienda);

    IF p_id_almacen IS NOT NULL
       AND NOT EXISTS (
           SELECT 1
             FROM public.app_dat_almacen AS a
            WHERE a.id = p_id_almacen
              AND a.id_tienda = p_id_tienda
              AND a.deleted_at IS NULL
       ) THEN
        RAISE EXCEPTION 'El almacén % no pertenece a la tienda %',
            p_id_almacen, p_id_tienda
            USING ERRCODE = '42501';
    END IF;

    -- La v2 envuelta es SECURITY DEFINER y resuelve relaciones sin calificar en
    -- su cuerpo; ya cuenta con el search_path restaurado arriba.

    RETURN QUERY
    WITH base AS MATERIALIZED (
        SELECT r.*
          FROM public.fn_inventario_resumen_por_usuario_almacen2(
                   p_id_tienda,
                   p_id_almacen,
                   p_busqueda,
                   p_mostrar_sin_stock,
                   p_filtro_stock,
                   p_limite,
                   p_pagina
               ) AS r
    )
    SELECT b.prod_id,
           b.prod_nombre,
           b.prod_sku,
           b.variante_id,
           b.variante_valor,
           b.opcion_variante_id,
           b.opcion_variante_valor,
           b.cant_unidades_base,
           b.cant_almacen_total,
           b.stock_disponible,
           b.stock_reservado,
           b.zonas_count,
           b.presentaciones_count,
           b.total_count,
           COALESCE(s.stock_desglose, '[]'::jsonb) AS stock_desglose,
           public.fn_formatear_stock_mixto(
               COALESCE(s.stock_desglose, '[]'::jsonb), false, 'Sin stock'
           ) AS stock_texto,
           public.fn_formatear_stock_mixto(
               COALESCE(s.stock_desglose, '[]'::jsonb), true, 'Sin stock'
           ) AS stock_texto_corto,
           COALESCE(s.stock_equivalente_base, 0)::numeric AS stock_equivalente_base
      FROM base AS b
      LEFT JOIN LATERAL (
          SELECT jsonb_agg(
                     jsonb_build_object(
                         'id_presentacion', x.id_presentacion,
                         'nombre', COALESCE(x.presentacion_nombre, 'Presentación'),
                         'sku_codigo', x.presentacion_sku,
                         'cantidad', x.saldo,
                         'factor_rel', COALESCE(x.factor_rel, 1),
                         'es_base', x.es_base,
                         'nivel', x.nivel,
                         'equivalente_base', x.equivalente_base
                     ) ORDER BY x.nivel NULLS LAST, x.id_presentacion
                 ) AS stock_desglose,
                 SUM(x.equivalente_base)::numeric AS stock_equivalente_base
            FROM (
                SELECT s.id_presentacion,
                       MIN(s.presentacion_nombre)::varchar AS presentacion_nombre,
                       MIN(s.sku_codigo)::varchar AS presentacion_sku,
                       MIN(s.factor_rel)::numeric AS factor_rel,
                       BOOL_OR(COALESCE(s.es_base, false)) AS es_base,
                       MIN(s.nivel)::integer AS nivel,
                       SUM(s.saldo)::numeric AS saldo,
                       SUM(s.equivalente_base)::numeric AS equivalente_base
                  FROM public.fn_stock_saldos_presentacion(
                           b.prod_id, p_id_almacen, NULL::bigint, false
                       ) AS s
                 WHERE s.id_variante IS NOT DISTINCT FROM b.variante_id
                   AND s.id_opcion_variante IS NOT DISTINCT FROM b.opcion_variante_id
                 GROUP BY s.id_presentacion
                HAVING SUM(s.saldo) <> 0
            ) AS x
      ) AS s ON true;
END;
$function$;

COMMENT ON FUNCTION public.fn_inventario_resumen_por_usuario_almacen3(
    bigint, bigint, text, boolean, text, integer, integer
) IS
'Wrapper aditivo de fn_inventario_resumen_por_usuario_almacen2: conserva sus '
'14 columnas y agrega stock_desglose, stock_texto, stock_texto_corto y '
'stock_equivalente_base. El desglose respeta producto, variante, opción y '
'almacén. No incluye descripción porque no pertenece al contrato v2.';

REVOKE ALL ON FUNCTION public.fn_inventario_resumen_por_usuario_almacen3(
    bigint, bigint, text, boolean, text, integer, integer
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_inventario_resumen_por_usuario_almacen3(
    bigint, bigint, text, boolean, text, integer, integer
) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_inventario_resumen_por_usuario_almacen3(
    bigint, bigint, text, boolean, text, integer, integer
) TO authenticated;
