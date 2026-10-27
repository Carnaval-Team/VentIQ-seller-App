BEGIN;

CREATE OR REPLACE FUNCTION public.get_productos_catalogo_stock_v2(p_id_tienda integer)
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, pg_catalog
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Se requiere una sesión autenticada' USING ERRCODE = '42501';
  END IF;
  PERFORM public.check_user_has_access_to_tienda(p_id_tienda::bigint);

  RETURN QUERY
  WITH catalogo AS MATERIALIZED (
    SELECT c.* FROM public.get_productos_catalogo_validacion(p_id_tienda) AS c
  ), vigente AS (
    SELECT DISTINCT ON (
      ip.id_producto, ip.id_ubicacion,
      COALESCE(ip.id_variante, 0), COALESCE(ip.id_opcion_variante, 0),
      ip.id_presentacion, COALESCE(ip.id_lote, 0)
    ) ip.id_producto, ip.id_presentacion, COALESCE(ip.cantidad_final, 0) AS saldo
    FROM public.app_dat_inventario_productos AS ip
    JOIN catalogo AS c ON c.id = ip.id_producto
    JOIN public.app_dat_layout_almacen AS la ON la.id = ip.id_ubicacion
      AND la.deleted_at IS NULL
    JOIN public.app_dat_almacen AS a ON a.id = la.id_almacen
      AND a.id_tienda = p_id_tienda AND a.deleted_at IS NULL
    ORDER BY ip.id_producto, ip.id_ubicacion,
      COALESCE(ip.id_variante, 0), COALESCE(ip.id_opcion_variante, 0),
      ip.id_presentacion, COALESCE(ip.id_lote, 0), ip.id DESC
  ), factores AS MATERIALIZED (
    SELECT c.id AS id_producto, pr.id_presentacion, pr.factor_rel
    FROM catalogo AS c
    CROSS JOIN LATERAL public.fn_presentaciones_producto(c.id) AS pr
  ), stock AS (
    SELECT v.id_producto, SUM(v.saldo * COALESCE(f.factor_rel, 1)) AS cantidad
    FROM vigente AS v
    LEFT JOIN factores AS f ON f.id_producto = v.id_producto
      AND f.id_presentacion = v.id_presentacion
    GROUP BY v.id_producto
  )
  SELECT to_jsonb(c) || jsonb_build_object('stock_disponible', COALESCE(s.cantidad, 0))
  FROM catalogo AS c
  LEFT JOIN stock AS s ON s.id_producto = c.id
  ORDER BY c.denominacion, c.id;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_productos_catalogo_stock_v2(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_productos_catalogo_stock_v2(integer) TO authenticated;

COMMIT;
