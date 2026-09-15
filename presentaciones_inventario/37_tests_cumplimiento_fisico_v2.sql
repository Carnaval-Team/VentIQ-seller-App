-- ============================================================================
-- 37 · Tests transaccionales de cumplimiento físico v2
-- Corte 1: catálogo exacto y validado de presentaciones
-- ============================================================================
-- Requiere 35. No persiste cambios: todo ocurre entre BEGIN y ROLLBACK.
-- Debe ejecutarse en Supabase SQL Editor con un rol propietario/postgres,
-- porque fn_presentaciones_producto_v2 es un helper interno de service_role.
-- ============================================================================

BEGIN;

DO $test$
DECLARE
    v_filas                 integer;
    v_id_producto           bigint;
    v_error_detectado       boolean;
    v_factores_no_enteros   integer;
    v_razones_inexactas     integer;
BEGIN
    SELECT count(*)::integer,
           count(*) FILTER (
               WHERE trunc(c.factor_entero) <> c.factor_entero
                  OR trunc(c.factor_base_entero) <> c.factor_base_entero
                  OR c.escala_entera <= 0
                  OR trunc(c.escala_entera) <> c.escala_entera
           )::integer,
           count(*) FILTER (
               WHERE c.factor_entero * c.factor_base_catalogo
                     <> c.factor_base_entero * c.factor_catalogo
           )::integer
      INTO v_filas, v_factores_no_enteros, v_razones_inexactas
      FROM public.fn_presentaciones_producto_v2(1072) AS c;

    IF v_filas <> 3 THEN
        RAISE EXCEPTION 'T1 producto 1072: esperaba 3 presentaciones, obtuvo %',
            v_filas;
    END IF;

    IF v_factores_no_enteros <> 0 OR v_razones_inexactas <> 0 THEN
        RAISE EXCEPTION
            'T1 producto 1072: enteros inválidos=%; razones inexactas=%',
            v_factores_no_enteros, v_razones_inexactas;
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM public.fn_presentaciones_producto_v2(1072) AS c
         WHERE c.factor_catalogo = 40
    ) OR NOT EXISTS (
        SELECT 1
          FROM public.fn_presentaciones_producto_v2(1072) AS c
         WHERE c.factor_catalogo = 6
    ) OR NOT EXISTS (
        SELECT 1
          FROM public.fn_presentaciones_producto_v2(1072) AS c
         WHERE c.factor_catalogo = 1
           AND c.es_base
    ) THEN
        RAISE EXCEPTION
            'T1 producto 1072: esperaba catálogo Caja 40 / Blíster 6 / Unidad base 1';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM public.fn_presentaciones_producto_v2(11001) AS c
         WHERE c.factor_catalogo = 24
           AND c.factor_entero = 240000
    ) OR NOT EXISTS (
        SELECT 1
          FROM public.fn_presentaciones_producto_v2(11001) AS c
         WHERE c.factor_catalogo = 0.0023
           AND c.factor_entero = 23
    ) THEN
        RAISE EXCEPTION
            'T2 producto 11001: esperaba normalización exacta 24→240000 y 0.0023→23';
    END IF;

    SELECT pp.id_producto
      INTO v_id_producto
      FROM public.app_dat_producto_presentacion AS pp
     GROUP BY pp.id_producto
    HAVING count(*) = 1
     ORDER BY pp.id_producto
     LIMIT 1;

    IF v_id_producto IS NULL THEN
        RAISE EXCEPTION 'T3 requiere un producto con una sola presentación';
    END IF;

    SELECT count(*)::integer
      INTO v_filas
      FROM public.fn_presentaciones_producto_v2(v_id_producto);

    IF v_filas <> 1 THEN
        RAISE EXCEPTION 'T3 producto de presentación única: obtuvo % filas', v_filas;
    END IF;

    SELECT p.id
      INTO v_id_producto
      FROM public.app_dat_producto AS p
     WHERE NOT EXISTS (
               SELECT 1
                 FROM public.app_dat_producto_presentacion AS pp
                WHERE pp.id_producto = p.id
           )
     ORDER BY p.id
     LIMIT 1;

    IF v_id_producto IS NULL THEN
        RAISE EXCEPTION 'T4 requiere un producto sin presentaciones';
    END IF;

    v_error_detectado := false;
    BEGIN
        PERFORM public.fn_presentaciones_producto_v2(v_id_producto);
    EXCEPTION
        WHEN SQLSTATE '22023' THEN
            v_error_detectado := SQLERRM LIKE '%no tiene presentaciones configuradas%';
    END;
    IF NOT v_error_detectado THEN
        RAISE EXCEPTION 'T4 no rechazó correctamente el producto sin presentaciones %',
            v_id_producto;
    END IF;

    SELECT pp.id_producto
      INTO v_id_producto
      FROM public.app_dat_producto_presentacion AS pp
     GROUP BY pp.id_producto
    HAVING count(DISTINCT pp.cantidad) <> count(*)
     ORDER BY pp.id_producto
     LIMIT 1;

    IF v_id_producto IS NULL THEN
        RAISE EXCEPTION 'T5 requiere un catálogo con factores duplicados';
    END IF;

    v_error_detectado := false;
    BEGIN
        PERFORM public.fn_presentaciones_producto_v2(v_id_producto);
    EXCEPTION
        WHEN SQLSTATE '22023' THEN
            v_error_detectado := SQLERRM LIKE '%factores duplicados%';
    END;
    IF NOT v_error_detectado THEN
        RAISE EXCEPTION 'T5 no rechazó factores duplicados del producto %',
            v_id_producto;
    END IF;

    SELECT pp.id_producto
      INTO v_id_producto
      FROM public.app_dat_producto_presentacion AS pp
     GROUP BY pp.id_producto
    HAVING count(*) FILTER (WHERE pp.es_base) > 1
     ORDER BY pp.id_producto
     LIMIT 1;

    IF v_id_producto IS NULL THEN
        RAISE EXCEPTION 'T6 requiere un catálogo con múltiples bases declaradas';
    END IF;

    v_error_detectado := false;
    BEGIN
        PERFORM public.fn_presentaciones_producto_v2(v_id_producto);
    EXCEPTION
        WHEN SQLSTATE '22023' THEN
            v_error_detectado := SQLERRM LIKE '%presentaciones base%';
    END;
    IF NOT v_error_detectado THEN
        RAISE EXCEPTION 'T6 no rechazó las múltiples bases del producto %',
            v_id_producto;
    END IF;

    RAISE NOTICE '37_tests_cumplimiento_fisico_v2: catálogo, 6 bloques OK';
END;
$test$;

ROLLBACK;
