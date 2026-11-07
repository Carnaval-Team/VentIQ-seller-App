BEGIN;

DO $repair$
DECLARE
    v_name text;
    v_oid regprocedure;
    v_def text;
    v_next text;
BEGIN
    IF to_regclass('public.app_v_precio_venta_base_vigente') IS NULL THEN
        RAISE EXCEPTION 'Falta la vista de precio base vigente';
    END IF;
    FOREACH v_name IN ARRAY ARRAY[
        'get_detalle_producto', 'get_detalles_productos_batch'
    ] LOOP
        SELECT p.oid::regprocedure INTO STRICT v_oid
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = v_name;
        v_def := pg_get_functiondef(v_oid);
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
    END LOOP;
END;
$repair$;

NOTIFY pgrst, 'reload schema';
COMMIT;
