BEGIN;

-- BORRADOR MC-048. NO EJECUTAR en main.
-- Los scripts 41 a 44 ya están en newa. Al crearlas, Supabase concedió
-- EXECUTE a anon además de PUBLIC. Quitar PUBLIC no quita esa concesión.
-- Este corte no enciende el flag ni escribe ventas, mesas ni deudas.

SET LOCAL app.m01_r23_anon_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r23_anon_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador MC-048: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF to_regprocedure('public.fn_m01_pedir_item_mesa_v1(jsonb)') IS NULL
       OR to_regprocedure('public.fn_m01_devolver_linea_v1(jsonb)') IS NULL THEN
        RAISE EXCEPTION 'Faltan las funciones de mesa o de devolucion';
    END IF;
    IF has_function_privilege('anon', 'public.fn_m01_pedir_item_mesa_v1(jsonb)', 'EXECUTE') IS FALSE
       AND has_function_privilege('anon', 'public.fn_m01_devolver_linea_v1(jsonb)', 'EXECUTE') IS FALSE THEN
        RAISE EXCEPTION 'anon ya no ejecuta el pedido ni la devolucion v1';
    END IF;
END;
$preflight$;

REVOKE ALL ON FUNCTION public.fn_m01_pedir_item_mesa_v1(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_m01_cancelar_item_mesa_v1(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_m01_finalizar_cuenta_v1(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_m01_cxc_registrar_v1(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_m01_cxc_saldo_v1(bigint) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_m01_cxc_liquidar_v1(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_m01_devolver_linea_v1(jsonb) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.fn_m01_pedir_item_mesa_v1(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_m01_cancelar_item_mesa_v1(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_m01_finalizar_cuenta_v1(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_m01_cxc_registrar_v1(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_m01_cxc_saldo_v1(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_m01_cxc_liquidar_v1(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_m01_devolver_linea_v1(jsonb) TO authenticated;

COMMIT;
