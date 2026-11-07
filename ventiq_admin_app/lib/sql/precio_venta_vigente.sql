BEGIN;

CREATE OR REPLACE VIEW public.app_v_precio_venta_vigente
WITH (security_invoker = true) AS
SELECT DISTINCT ON (pv.id_producto, COALESCE(pv.id_variante, 0)) pv.*
FROM public.app_dat_precio_venta pv
WHERE pv.fecha_desde <= CURRENT_DATE
  AND (pv.fecha_hasta IS NULL OR pv.fecha_hasta >= CURRENT_DATE)
ORDER BY pv.id_producto, COALESCE(pv.id_variante, 0), pv.id DESC;

REVOKE ALL ON public.app_v_precio_venta_vigente FROM PUBLIC, anon;
GRANT SELECT ON public.app_v_precio_venta_vigente TO authenticated, service_role;

CREATE OR REPLACE VIEW public.app_v_precio_venta_base_vigente
WITH (security_invoker = true) AS
SELECT * FROM public.app_v_precio_venta_vigente
WHERE COALESCE(id_variante, 0) = 0;

REVOKE ALL ON public.app_v_precio_venta_base_vigente FROM PUBLIC, anon;
GRANT SELECT ON public.app_v_precio_venta_base_vigente TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_precio_venta_vigente(
    p_id_producto bigint,
    p_id_variante bigint DEFAULT NULL
)
RETURNS SETOF public.app_dat_precio_venta
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = public
AS $$
    SELECT pv.*
    FROM public.app_v_precio_venta_vigente pv
    WHERE pv.id_producto = p_id_producto
      AND (COALESCE(pv.id_variante, 0) = 0
           OR pv.id_variante = NULLIF(p_id_variante, 0))
    ORDER BY (COALESCE(pv.id_variante, 0) <> 0) DESC, pv.id DESC
    LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.fn_precio_venta_vigente(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_precio_venta_vigente(bigint, bigint) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_guardar_precio_venta_base(
    p_id_producto bigint,
    p_precio_venta_cup numeric,
    p_precio_venta_usd numeric DEFAULT NULL
)
RETURNS SETOF public.app_dat_precio_venta
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tienda bigint;
    v_anterior public.app_dat_precio_venta%ROWTYPE;
BEGIN
    SELECT p.id_tienda INTO v_tienda
    FROM public.app_dat_producto p WHERE p.id = p_id_producto FOR UPDATE;
    IF v_tienda IS NULL THEN
        RAISE EXCEPTION 'Producto inexistente' USING ERRCODE = '22023';
    END IF;
    IF auth.uid() IS NULL OR NOT (
        COALESCE(public.fn_user_is_gerente_or_superadmin(v_tienda), false)
        OR COALESCE(public.fn_user_is_dueno(v_tienda), false)
    ) THEN
        RAISE EXCEPTION 'Sin permiso para modificar precios' USING ERRCODE = '42501';
    END IF;
    IF p_precio_venta_cup IS NULL OR p_precio_venta_cup < 0
       OR p_precio_venta_cup::text IN ('NaN', 'Infinity', '-Infinity')
       OR p_precio_venta_usd < 0
       OR p_precio_venta_usd::text IN ('NaN', 'Infinity', '-Infinity') THEN
        RAISE EXCEPTION 'Precio inválido' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_anterior FROM public.fn_precio_venta_vigente(p_id_producto);
    IF FOUND AND v_anterior.precio_venta_cup IS NOT DISTINCT FROM p_precio_venta_cup
       AND (p_precio_venta_usd IS NULL
            OR v_anterior.precio_venta_usd IS NOT DISTINCT FROM p_precio_venta_usd) THEN
        RETURN NEXT v_anterior;
        RETURN;
    END IF;

    UPDATE public.app_dat_precio_venta pv
    SET fecha_hasta = GREATEST(pv.fecha_desde, CURRENT_DATE - 1)
    WHERE pv.id_producto = p_id_producto
      AND COALESCE(pv.id_variante, 0) = 0
      AND pv.fecha_desde <= CURRENT_DATE
      AND (pv.fecha_hasta IS NULL OR pv.fecha_hasta > CURRENT_DATE);

    RETURN QUERY
    INSERT INTO public.app_dat_precio_venta (
        id_producto, id_variante, precio_venta_cup, precio_venta_usd,
        precio_descuento, fecha_desde, fecha_hasta, created_at
    ) VALUES (
        p_id_producto, NULL, p_precio_venta_cup,
        COALESCE(p_precio_venta_usd, v_anterior.precio_venta_usd),
        v_anterior.precio_descuento, CURRENT_DATE, NULL, clock_timestamp()
    ) RETURNING *;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_guardar_precio_venta_base(bigint, numeric, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_guardar_precio_venta_base(bigint, numeric, numeric) TO authenticated;

DO $migration$
DECLARE
    v_name text;
    v_oid regprocedure;
    v_def text;
    v_next text;
BEGIN
    FOREACH v_name IN ARRAY ARRAY[
        'get_detalle_producto',
        'get_detalles_productos_batch',
        'get_productos_by_categoria_tpv_search_meta_v3',
        'get_productos_completos_by_tienda_optimized_v2',
        'rpc_get_products_last_price2',
        'fn_reporte_ventas_con_proveedor_precios_actuales',
        'get_precios_productos_tienda',
        'fn_productos_cocina_tpv',
        'rpc_apply_global_price_change',
        'rpc_apply_selected_price_change'
    ] LOOP
        SELECT p.oid::regprocedure INTO STRICT v_oid
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = v_name;
        v_def := pg_get_functiondef(v_oid);
        IF v_name IN ('get_detalle_producto', 'get_detalles_productos_batch') THEN
            v_next := regexp_replace(v_def,
                '(\mFROM\s+(?:public\.)?app_dat_producto_(?:multimedias|etiquetas)\s+WHERE\s+id_producto\s*=\s*p\.id)\s+AND\s+COALESCE\(id_variante,\s*0\)\s*=\s*0',
                '\1', 'gi');
            v_next := regexp_replace(v_next,
                '\mFROM\s+(?:public\.)?(?:app_dat_precio_venta|app_v_precio_venta_vigente)\M',
                'FROM public.app_v_precio_venta_base_vigente', 'gi');
            IF position('FROM public.app_v_precio_venta_base_vigente' IN v_next) = 0 THEN
                RAISE EXCEPTION 'Lectura de precio inesperada en %', v_name;
            END IF;
            IF v_next <> v_def THEN
                EXECUTE v_next;
            END IF;
            CONTINUE;
        END IF;
        IF position('app_v_precio_venta_vigente' IN v_def) > 0
           OR position('app_v_precio_venta_base_vigente' IN v_def) > 0 THEN
            CONTINUE;
        END IF;
        v_next := regexp_replace(v_def,
            '\mFROM\s+(public\.)?app_dat_precio_venta\M',
            'FROM public.app_v_precio_venta_vigente', 'gi');
        IF v_next = v_def THEN
            RAISE EXCEPTION 'No se encontró la lectura esperada en %', v_name;
        END IF;
        IF v_name IN ('get_precios_productos_tienda',
                      'rpc_apply_global_price_change',
                      'rpc_apply_selected_price_change') THEN
            v_next := replace(v_next, 'FROM public.app_v_precio_venta_vigente',
                'FROM public.app_v_precio_venta_base_vigente');
        END IF;
        IF v_name = 'rpc_get_products_last_price2' THEN
            v_next := regexp_replace(v_next,
                'where\s+apv\.id_producto\s*=\s*p\.id',
                'WHERE apv.id_producto = p.id AND COALESCE(apv.id_variante, 0) = 0', 'gi');
        ELSIF v_name = 'fn_reporte_ventas_con_proveedor_precios_actuales' THEN
            v_next := regexp_replace(v_next,
                'ORDER\s+BY\s+pv\.created_at\s+DESC',
                'ORDER BY (COALESCE(pv.id_variante, 0) <> 0) DESC, pv.id DESC', 'gi');
            IF v_next = regexp_replace(v_def,
                '\mFROM\s+(public\.)?app_dat_precio_venta\M',
                'FROM public.app_v_precio_venta_vigente', 'gi') THEN
                RAISE EXCEPTION 'Orden de variantes inesperado en %', v_name;
            END IF;
        END IF;
        EXECUTE v_next;
    END LOOP;
END;
$migration$;

DO $offline$
DECLARE
    v_oid regprocedure;
    v_def text;
    v_next text;
BEGIN
    SELECT p.oid::regprocedure INTO STRICT v_oid
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'fn_admin_caja_actualizar_precios_offline';
    v_def := pg_get_functiondef(v_oid);
    IF position('fn_guardar_precio_venta_base' IN v_def) = 0 THEN
        v_next := regexp_replace(v_def,
            'UPDATE\s+public\.app_dat_precio_venta\s+SET[^;]+;\s+IF\s+NOT\s+FOUND\s+THEN\s+INSERT\s+INTO\s+public\.app_dat_precio_venta[^;]+;\s+END\s+IF;',
            'PERFORM public.fn_guardar_precio_venta_base(p_id_producto, p_precio_venta_cup);', 'gi');
        IF v_next = v_def THEN
            RAISE EXCEPTION 'Escritura offline inesperada en %', v_oid;
        END IF;
        EXECUTE v_next;
    END IF;
END;
$offline$;

NOTIFY pgrst, 'reload schema';
COMMIT;
