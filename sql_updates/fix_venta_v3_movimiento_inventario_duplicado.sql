BEGIN;

DO $patch$
DECLARE
    v_firma text;
    v_oid regprocedure;
    v_def text;
    v_inicio text := '      INSERT INTO app_dat_inventario_productos (';
    v_final text := '      ) ip;';
    v_guard text := '      IF NOT COALESCE(v_stock_v2, false) THEN';
    v_cantidad integer;
BEGIN
    FOREACH v_firma IN ARRAY ARRAY[
        'public.fn_registrar_venta_v3(bigint,uuid,jsonb,text,text,text,smallint,bigint)',
        'public.fn_registrar_venta_mesa_v3(bigint,uuid,jsonb,text,text,text,smallint,bigint,bigint)'
    ]
    LOOP
        v_oid := to_regprocedure(v_firma);

        IF v_oid IS NULL THEN
            RAISE EXCEPTION 'No existe la función: %', v_firma;
        END IF;

        v_def := replace(
            pg_get_functiondef(v_oid),
            E'\r\n',
            E'\n'
        );

        IF position('v_stock_v2 := true;' IN v_def) = 0
           OR position('fn_ejecutar_entrega_fisica_v3(' IN v_def) = 0 THEN
            RAISE EXCEPTION
                'La función % no tiene la estructura de entrega física esperada',
                v_firma;
        END IF;

        v_cantidad := (
            length(v_def) -
            length(replace(v_def, v_inicio, ''))
        ) / length(v_inicio);

        IF v_cantidad <> 1 THEN
            RAISE EXCEPTION
                'En % se esperaba un INSERT antiguo de inventario; encontrados: %',
                v_firma, v_cantidad;
        END IF;

        v_cantidad := (
            length(v_def) -
            length(replace(v_def, v_final, ''))
        ) / length(v_final);

        IF v_cantidad <> 1 THEN
            RAISE EXCEPTION
                'En % se esperaba un cierre del INSERT antiguo; encontrados: %',
                v_firma, v_cantidad;
        END IF;

        IF position(v_guard || E'\n' || v_inicio IN v_def) > 0 THEN
            RAISE NOTICE 'La función % ya tiene la corrección', v_firma;
            CONTINUE;
        END IF;

        IF position(v_inicio IN v_def) >= position(v_final IN v_def) THEN
            RAISE EXCEPTION
                'El bloque de inventario no tiene el orden esperado en %',
                v_firma;
        END IF;

        v_def := replace(
            v_def,
            v_inicio,
            v_guard || E'\n' || v_inicio
        );

        v_def := replace(
            v_def,
            v_final,
            v_final || E'\n      END IF;'
        );

        EXECUTE v_def;

        RAISE NOTICE 'Función corregida: %', v_firma;
    END LOOP;
END;
$patch$;

COMMIT;

SELECT
    p.oid::regprocedure AS funcion,
    position(
        'IF NOT COALESCE(v_stock_v2, false) THEN'
        IN p.prosrc
    ) > 0 AS corregida
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
      'fn_registrar_venta_v3',
      'fn_registrar_venta_mesa_v3'
  );
