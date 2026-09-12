-- ============================================================================
-- 35 · Cumplimiento físico por presentaciones v2
-- Corte 1: catálogo exacto y validado de presentaciones
-- ============================================================================
-- Aditivo: no reemplaza ninguna función viva.

CREATE OR REPLACE FUNCTION public.fn_presentaciones_producto_v2(
    p_id_producto bigint
)
RETURNS TABLE (
    id_presentacion       bigint,
    id_nom_presentacion   bigint,
    nombre                varchar,
    factor_catalogo       numeric,
    factor_base_catalogo  numeric,
    factor_entero         numeric,
    factor_base_entero    numeric,
    escala_entera         numeric,
    es_base               boolean,
    base_declarada        boolean,
    es_fraccionable       boolean,
    sku_codigo            varchar,
    nivel                 integer
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
    v_total              integer;
    v_bases_declaradas   integer;
    v_factores_distintos integer;
    v_factor_invalido    boolean;
    v_id_base            bigint;
    v_factor_base        numeric;
    v_decimales          integer;
    v_escala             numeric;
    v_gcd                numeric;
    v_factor_escalado    numeric;
    v_dividendo          numeric;
    v_divisor            numeric;
    v_resto              numeric;
BEGIN
    IF p_id_producto IS NULL THEN
        RAISE EXCEPTION 'id_producto es obligatorio'
            USING ERRCODE = '22023';
    END IF;

    SELECT count(*)::integer,
           count(*) FILTER (WHERE pp.es_base)::integer,
           count(DISTINCT pp.cantidad)::integer,
           bool_or(pp.cantidad IS NULL OR pp.cantidad <= 0),
           COALESCE(max(scale(pp.cantidad)), 0)
      INTO v_total, v_bases_declaradas, v_factores_distintos,
           v_factor_invalido, v_decimales
      FROM public.app_dat_producto_presentacion AS pp
     WHERE pp.id_producto = p_id_producto;

    IF v_total = 0 THEN
        RAISE EXCEPTION 'El producto % no tiene presentaciones configuradas',
            p_id_producto
            USING ERRCODE = '22023';
    END IF;

    IF v_factor_invalido THEN
        RAISE EXCEPTION 'CATALOGO_PRESENTACIONES_INVALIDO: el producto % tiene factores nulos o no positivos',
            p_id_producto
            USING ERRCODE = '22023';
    END IF;

    IF v_bases_declaradas > 1 THEN
        RAISE EXCEPTION 'CATALOGO_PRESENTACIONES_INVALIDO: el producto % tiene % presentaciones base',
            p_id_producto, v_bases_declaradas
            USING ERRCODE = '22023';
    END IF;

    IF v_factores_distintos <> v_total THEN
        RAISE EXCEPTION 'CATALOGO_PRESENTACIONES_INVALIDO: el producto % tiene factores duplicados',
            p_id_producto
            USING ERRCODE = '22023';
    END IF;

    SELECT pp.id, pp.cantidad
      INTO v_id_base, v_factor_base
      FROM public.app_dat_producto_presentacion AS pp
     WHERE pp.id_producto = p_id_producto
     ORDER BY pp.es_base DESC, pp.cantidad ASC, pp.id ASC
     LIMIT 1;

    v_escala := power(10::numeric, v_decimales);
    v_gcd := 0;

    FOR v_factor_escalado IN
        SELECT pp.cantidad * v_escala
          FROM public.app_dat_producto_presentacion AS pp
         WHERE pp.id_producto = p_id_producto
    LOOP
        IF trunc(v_factor_escalado) <> v_factor_escalado THEN
            RAISE EXCEPTION 'CATALOGO_PRESENTACIONES_INVALIDO: no se pudo escalar exactamente el producto %',
                p_id_producto
                USING ERRCODE = '22023';
        END IF;

        v_dividendo := greatest(v_gcd, v_factor_escalado);
        v_divisor := least(v_gcd, v_factor_escalado);
        WHILE v_divisor <> 0 LOOP
            v_resto := mod(v_dividendo, v_divisor);
            v_dividendo := v_divisor;
            v_divisor := v_resto;
        END LOOP;
        v_gcd := v_dividendo;
    END LOOP;

    IF v_gcd IS NULL OR v_gcd <= 0 THEN
        RAISE EXCEPTION 'CATALOGO_PRESENTACIONES_INVALIDO: no se pudo normalizar el producto %',
            p_id_producto
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    SELECT pp.id,
           pp.id_presentacion,
           COALESCE(np.denominacion, 'Presentacion')::varchar,
           pp.cantidad,
           v_factor_base,
           pp.cantidad * v_escala / v_gcd,
           v_factor_base * v_escala / v_gcd,
           v_escala,
           pp.id = v_id_base,
           pp.es_base,
           COALESCE(np.es_fraccionable, false),
           np.sku_codigo,
           row_number() OVER (
               ORDER BY pp.cantidad DESC, pp.id ASC
           )::integer
      FROM public.app_dat_producto_presentacion AS pp
      LEFT JOIN public.app_nom_presentacion AS np
        ON np.id = pp.id_presentacion
     WHERE pp.id_producto = p_id_producto
     ORDER BY pp.cantidad DESC, pp.id ASC;
END;
$function$;

COMMENT ON FUNCTION public.fn_presentaciones_producto_v2(bigint) IS
    'Catálogo v2 validado. Conserva factores NUMERIC exactos y devuelve coeficientes '
    'enteros normalizados por el máximo común divisor del catálogo; escala_entera '
    'conserva el multiplicador decimal común original. Rechaza factores no positivos, '
    'duplicados y múltiples bases declaradas.';

REVOKE ALL ON FUNCTION public.fn_presentaciones_producto_v2(bigint)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_presentaciones_producto_v2(bigint)
    TO service_role;
