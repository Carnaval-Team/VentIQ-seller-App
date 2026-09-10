-- ============================================================================
-- 34 · Tests transaccionales de visualización de stock mixto
-- ============================================================================
-- Requiere 31 y 32. No aplica cambios permanentes: todo ocurre entre BEGIN y
-- ROLLBACK. Usa la tienda/almacén/ubicación reales documentados para el producto
-- 11001 y crea un producto sintético aislado para comprobar los contratos.
--
-- Para que pase la validación de acceso, reemplazar <UUID_CON_ACCESO_TIENDA_223>
-- antes de ejecutar manualmente. Este archivo no se ejecuta automáticamente.
-- ============================================================================

BEGIN;

DO $test$
DECLARE
    v_uuid_text text := '<UUID_CON_ACCESO_TIENDA_223>';
    v_id_categoria bigint;
    v_id_producto bigint;
    v_id_caja bigint;
    v_id_bulto bigint;
    v_id_unidad bigint;
    v_id_otra_ubicacion bigint;
    v_texto text;
    v_texto_corto text;
    v_equiv numeric;
    v_desglose jsonb;
    v_filas integer;
    v_total_count bigint;
    v_cols_v2 integer;
    v_cols_v3 integer;
    v_prosecdef boolean;
    v_proconfig text[];
    v_public_acl boolean;
    v_anon_acl boolean;
    v_auth_acl boolean;
BEGIN
    IF v_uuid_text LIKE '<%>' THEN
        RAISE EXCEPTION
            'Reemplace <UUID_CON_ACCESO_TIENDA_223> por un usuario con acceso a la tienda 223';
    END IF;

    PERFORM set_config(
        'request.jwt.claims',
        json_build_object('sub', v_uuid_text, 'role', 'authenticated')::text,
        true
    );

    SELECT p.id_categoria
      INTO v_id_categoria
      FROM public.app_dat_producto AS p
     WHERE p.id_tienda = 223
     ORDER BY p.id
     LIMIT 1;

    IF v_id_categoria IS NULL THEN
        RAISE EXCEPTION 'La tienda 223 no tiene una categoría utilizable para el test';
    END IF;

    SELECT la.id
      INTO v_id_otra_ubicacion
      FROM public.app_dat_layout_almacen AS la
      JOIN public.app_dat_almacen AS a ON a.id = la.id_almacen
     WHERE a.id_tienda = 223
       AND la.id <> 349
       AND la.deleted_at IS NULL
       AND a.deleted_at IS NULL
     ORDER BY la.id
     LIMIT 1;

    IF v_id_otra_ubicacion IS NULL THEN
        RAISE EXCEPTION 'La tienda 223 necesita una segunda ubicación para el test';
    END IF;

    INSERT INTO public.app_dat_producto (
        id_tienda, id_categoria, denominacion, sku,
        es_vendible, es_inventariable, es_servicio, es_elaborado,
        mostrar_en_catalogo, created_at
    ) VALUES (
        223, v_id_categoria, 'ZZ TEST visualización stock mixto',
        'ZZ-TEST-STOCK-MIXTO', true, true, false, false, false, now()
    ) RETURNING id INTO v_id_producto;

    INSERT INTO public.app_dat_producto_presentacion (
        id_producto, id_presentacion, cantidad, es_base, precio_promedio, created_at
    ) VALUES
        (v_id_producto, 3, 24, false, 0, now()),
        (v_id_producto, 7, 5, false, 0, now()),
        (v_id_producto, 1, 1, true, 0, now());

    SELECT pp.id INTO v_id_caja
      FROM public.app_dat_producto_presentacion AS pp
     WHERE pp.id_producto = v_id_producto AND pp.id_presentacion = 3;
    SELECT pp.id INTO v_id_bulto
      FROM public.app_dat_producto_presentacion AS pp
     WHERE pp.id_producto = v_id_producto AND pp.id_presentacion = 7;
    SELECT pp.id INTO v_id_unidad
      FROM public.app_dat_producto_presentacion AS pp
     WHERE pp.id_producto = v_id_producto AND pp.id_presentacion = 1;

    PERFORM public.fn_ingresar_presentacion(v_id_producto, 349, v_id_caja, 49, 1);
    PERFORM public.fn_ingresar_presentacion(v_id_producto, 349, v_id_bulto, 2.8, 1);
    PERFORM public.fn_ingresar_presentacion(v_id_producto, 349, v_id_unidad, 0, 1);
    PERFORM public.fn_ingresar_presentacion(
        v_id_producto, v_id_otra_ubicacion, v_id_unidad, 3, 1
    );

    SELECT r.stock_texto, r.stock_texto_corto,
           r.stock_equivalente_base, r.stock_desglose
      INTO v_texto, v_texto_corto, v_equiv, v_desglose
      FROM public.fn_stock_mixto_producto_por_ubicacion(v_id_producto, NULL) AS r
     WHERE r.id_ubicacion = 349;

    IF v_texto <> '49 Cajas + 2.8 Bultos' THEN
        RAISE EXCEPTION 'T1 texto: esperaba 49 Cajas + 2.8 Bultos, obtuvo %', v_texto;
    END IF;
    IF v_texto_corto <> '49 CAJ + 2.8 BLT' THEN
        RAISE EXCEPTION 'T1 corto: esperaba 49 CAJ + 2.8 BLT, obtuvo %', v_texto_corto;
    END IF;
    IF v_equiv <> 1190 THEN
        RAISE EXCEPTION 'T1 equivalente: esperaba 1190, obtuvo %', v_equiv;
    END IF;
    IF v_texto LIKE '%51.8%' OR v_equiv = 51.8 THEN
        RAISE EXCEPTION 'T1 no debe exponer 51.8 como total físico ni equivalente';
    END IF;
    IF jsonb_array_length(v_desglose) <> 2 THEN
        RAISE EXCEPTION 'T1 debe omitir la presentación con saldo cero';
    END IF;

    SELECT count(*) INTO v_filas
      FROM public.fn_stock_mixto_producto_por_ubicacion(v_id_producto, NULL);
    IF v_filas <> 2 THEN
        RAISE EXCEPTION 'T2 multiubicación: esperaba 2 filas, obtuvo %', v_filas;
    END IF;

    SELECT r.stock_texto, r.stock_equivalente_base
      INTO v_texto, v_equiv
      FROM public.fn_stock_mixto_producto_por_ubicacion(v_id_producto, NULL) AS r
     WHERE r.id_ubicacion = v_id_otra_ubicacion;
    IF v_texto <> '3 Unidades' OR v_equiv <> 3 THEN
        RAISE EXCEPTION 'T2 ubicación simple: esperaba 3 Unidades / 3, obtuvo % / %',
            v_texto, v_equiv;
    END IF;

    SELECT r.stock_texto, r.stock_equivalente_base, r.total_count
      INTO v_texto, v_equiv, v_total_count
      FROM public.fn_inventario_resumen_por_usuario_almacen3(
               223, NULL, 'ZZ TEST visualización stock mixto', true, 'Todos', 20, 1
           ) AS r
     WHERE r.prod_id = v_id_producto
       AND r.variante_id IS NULL
       AND r.opcion_variante_id IS NULL;

    IF v_texto <> '49 Cajas + 2.8 Bultos + 3 Unidades' OR v_equiv <> 1193 THEN
        RAISE EXCEPTION 'T3 resumen v3: obtuvo % / %, esperaba mixto / 1193',
            v_texto, v_equiv;
    END IF;
    IF v_total_count <> 1 THEN
        RAISE EXCEPTION 'T3 paginación: total_count esperado 1, obtenido %', v_total_count;
    END IF;

    SELECT array_length(string_to_array(pg_get_function_result(
               'public.fn_inventario_resumen_por_usuario_almacen2(bigint,bigint,text,boolean,text,integer,integer)'::regprocedure
           ), ','), 1)
      INTO v_cols_v2;
    SELECT array_length(string_to_array(pg_get_function_result(
               'public.fn_inventario_resumen_por_usuario_almacen3(bigint,bigint,text,boolean,text,integer,integer)'::regprocedure
           ), ','), 1)
      INTO v_cols_v3;
    IF v_cols_v2 <> 14 OR v_cols_v3 <> 18 THEN
        RAISE EXCEPTION 'T4 contratos: v2=% columnas, v3=%; esperaba 14/18',
            v_cols_v2, v_cols_v3;
    END IF;

    SELECT p.prosecdef, p.proconfig,
           has_function_privilege('public', p.oid, 'EXECUTE'),
           has_function_privilege('anon', p.oid, 'EXECUTE'),
           has_function_privilege('authenticated', p.oid, 'EXECUTE')
      INTO v_prosecdef, v_proconfig, v_public_acl, v_anon_acl, v_auth_acl
      FROM pg_proc AS p
     WHERE p.oid = 'public.fn_inventario_resumen_por_usuario_almacen3(bigint,bigint,text,boolean,text,integer,integer)'::regprocedure;

    IF v_prosecdef OR v_proconfig IS DISTINCT FROM ARRAY['search_path=']::text[]
       OR v_public_acl OR v_anon_acl OR NOT v_auth_acl THEN
        RAISE EXCEPTION
            'T5 seguridad v3: definer=%, config=%, public=%, anon=%, auth=%',
            v_prosecdef, v_proconfig, v_public_acl, v_anon_acl, v_auth_acl;
    END IF;

    SELECT p.prosecdef, p.proconfig,
           has_function_privilege('public', p.oid, 'EXECUTE'),
           has_function_privilege('anon', p.oid, 'EXECUTE'),
           has_function_privilege('authenticated', p.oid, 'EXECUTE')
      INTO v_prosecdef, v_proconfig, v_public_acl, v_anon_acl, v_auth_acl
      FROM pg_proc AS p
     WHERE p.oid = 'public.fn_stock_mixto_producto_por_ubicacion(bigint,bigint)'::regprocedure;

    IF v_prosecdef OR v_proconfig IS DISTINCT FROM ARRAY['search_path=']::text[]
       OR v_public_acl OR v_anon_acl OR NOT v_auth_acl THEN
        RAISE EXCEPTION
            'T5 seguridad ubicación: definer=%, config=%, public=%, anon=%, auth=%',
            v_prosecdef, v_proconfig, v_public_acl, v_anon_acl, v_auth_acl;
    END IF;

    BEGIN
        PERFORM set_config(
            'request.jwt.claims',
            json_build_object(
                'sub', '00000000-0000-0000-0000-000000000000',
                'role', 'authenticated'
            )::text,
            true
        );
        PERFORM public.fn_stock_mixto_producto_por_ubicacion(v_id_producto, NULL);
        RAISE EXCEPTION 'T6 acceso cruzado: la llamada debió ser rechazada';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM = 'T6 acceso cruzado: la llamada debió ser rechazada' THEN
                RAISE;
            END IF;
    END;

    RAISE NOTICE '34_tests_visualizacion_stock: 6 bloques OK';
END;
$test$;

ROLLBACK;
