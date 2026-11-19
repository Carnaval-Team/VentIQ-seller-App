-- =============================================================================
-- Pedido de mesa M01: reutilizar la ruta, y lock_timeout en las ventas v1
-- =============================================================================
-- Aplica en newa, después de sql_updates/optimizar_venta_v3_ruta_y_lock_timeout.sql
-- (fn_descontar_venta_enrutada_v2 ya acepta p_ruta).
--
-- 1. fn_m01_pedir_item_mesa_v1 calcula la ruta, inserta el ítem y luego
--    fn_descontar_venta_enrutada_v2 la vuelve a calcular. La comanda usa la
--    primera y el inventario la segunda. Se le pasa p_ruta := v_origen, que es
--    la ruta ya validada antes del INSERT. El descuento la reutiliza solo si
--    trae status success y el mismo producto.
--    No se toca fn_m01_registrar_venta_v1, fn_m01_finalizar_cuenta_v1 ni
--    fn_m01_ajustar_linea_v1: no resuelven la ruta antes de descontar.
--
-- 2. lock_timeout = '3s' en las cuatro funciones que toman el candado del
--    producto. Es la espera para adquirir el candado, no el tiempo total.
--    Cubre el camino del flag producto-v1; el de la venta v3 ya está puesto.
--
-- El cuerpo se reescribe desde la definición viva. La llamada se localiza por
-- el nombre y los paréntesis, sin exigir los saltos de línea del archivo.
-- Si no está, o está más de una vez, el script aborta sin tocar nada.
-- No volver a correr m01_r19 ni m01_r24: reemplazarían el cuerpo vivo.
-- =============================================================================

BEGIN;

DO $$
DECLARE
    v_fn     regprocedure;
    v_def    text;
    v_name   constant text := 'fn_descontar_venta_enrutada_v2';
    v_pos    integer;
    v_open   integer;
    v_close  integer;
    v_depth  integer;
    v_i      integer;
    v_sig    text;
    v_funcs  constant text[] := ARRAY[
        'public.fn_m01_registrar_venta_v1(jsonb)',
        'public.fn_m01_pedir_item_mesa_v1(jsonb)',
        'public.fn_m01_finalizar_cuenta_v1(jsonb)',
        'public.fn_m01_ajustar_linea_v1(jsonb)'
    ];
BEGIN
    v_fn := to_regprocedure('public.fn_m01_pedir_item_mesa_v1(jsonb)');
    IF v_fn IS NULL THEN
        RAISE EXCEPTION 'No existe fn_m01_pedir_item_mesa_v1(jsonb)';
    END IF;

    -- El cuerpo vivo puede traer CRLF o otra indentación que el archivo del repo.
    v_def := replace(replace(pg_get_functiondef(v_fn), E'\r\n', E'\n'), E'\r', E'\n');

    IF position('p_ruta := v_origen' IN v_def) > 0 THEN
        RAISE NOTICE 'fn_m01_pedir_item_mesa_v1 ya pasa p_ruta: se omite el reemplazo';
    ELSE
        v_pos := position(v_name IN v_def);
        IF v_pos = 0 THEN
            RAISE EXCEPTION 'fn_m01_pedir_item_mesa_v1 no llama a %', v_name;
        END IF;
        IF position(v_name IN substr(v_def, v_pos + length(v_name))) > 0 THEN
            RAISE EXCEPTION '% aparece más de una vez en fn_m01_pedir_item_mesa_v1', v_name;
        END IF;

        v_open := v_pos + position('(' IN substr(v_def, v_pos)) - 1;
        v_depth := 0;
        v_close := 0;
        FOR v_i IN v_open .. length(v_def) LOOP
            IF substr(v_def, v_i, 1) = '(' THEN
                v_depth := v_depth + 1;
            ELSIF substr(v_def, v_i, 1) = ')' THEN
                v_depth := v_depth - 1;
                IF v_depth = 0 THEN
                    v_close := v_i;
                    EXIT;
                END IF;
            END IF;
        END LOOP;
        IF v_close = 0 OR substr(v_def, v_close, 1) <> ')' THEN
            RAISE EXCEPTION 'No se cerró la llamada a %', v_name;
        END IF;

        v_def := substr(v_def, 1, v_close - 1)
              || E',\n        p_ruta := v_origen'
              || substr(v_def, v_close);
        EXECUTE v_def;
        RAISE NOTICE 'fn_m01_pedir_item_mesa_v1: el descuento reutiliza v_origen';
    END IF;

    FOREACH v_sig IN ARRAY v_funcs
    LOOP
        v_fn := to_regprocedure(v_sig);
        IF v_fn IS NULL THEN
            RAISE EXCEPTION 'No existe %', v_sig;
        END IF;
        EXECUTE format('ALTER FUNCTION %s SET lock_timeout = %L', v_fn, '3s');
        RAISE NOTICE '%: lock_timeout = 3s', v_fn;
    END LOOP;
END
$$;

COMMIT;

-- ── Verificación ─────────────────────────────────────────────────────────────
SELECT proname,
       pg_get_function_identity_arguments(oid) AS firma,
       proconfig,
       position('p_ruta := v_origen' IN prosrc) > 0 AS pasa_ruta
  FROM pg_proc
 WHERE pronamespace = 'public'::regnamespace
   AND proname IN (
       'fn_m01_registrar_venta_v1',
       'fn_m01_pedir_item_mesa_v1',
       'fn_m01_finalizar_cuenta_v1',
       'fn_m01_ajustar_linea_v1'
   )
 ORDER BY proname;
