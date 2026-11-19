-- Firmas de contabilización en newa. Ejecutar en el SQL Editor de **newa**.
--
-- Deja una sola firma por función, con p_id_tienda DEFAULT NULL, para que una
-- llamada de 2 argumentos (inventario) o de 1 (info / historial) no sea ambigua.
--
-- Info e historial de 2 parámetros ya las trajo response.sql desde main: este
-- script no las reescribe. Solo quita las de 1 parámetro.
-- La de 3 parámetros de fn_actualizar_operacion_contabilizada no entró en ese
-- paquete. Se crea aquí y se quita la de 2 parámetros.
--
-- El guardar sigue siendo gerente o supervisor. Info e historial siguen
-- aceptando también auditor, como ya quedaron en response.sql.

BEGIN;

DO $pre$
BEGIN
    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION 'Ejecutar como postgres';
    END IF;
    IF to_regprocedure('public.fn_info_contabilizacion_ordenes_carnaval(bigint[],bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta fn_info_contabilizacion_ordenes_carnaval(bigint[],bigint). response.sql no está aplicado.';
    END IF;
    IF to_regprocedure('public.fn_historial_contabilizacion_operacion(bigint,bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta fn_historial_contabilizacion_operacion(bigint,bigint). response.sql no está aplicado.';
    END IF;
END
$pre$;

CREATE OR REPLACE FUNCTION public.fn_actualizar_operacion_contabilizada(
    p_id_operacion BIGINT,
    p_contabilizada BOOLEAN,
    p_id_tienda BIGINT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Usuario no autenticado';
    END IF;

    IF p_id_tienda IS NOT NULL THEN
        -- Permiso contra la tienda desde la que se contabiliza (Carnaval),
        -- no contra la tienda propietaria de la operación.
        IF NOT EXISTS (
            SELECT 1
            FROM public.app_dat_tienda t
            WHERE t.id = p_id_tienda
              AND t.id IN (
                  SELECT g.id_tienda FROM public.app_dat_gerente g WHERE g.uuid = auth.uid()
                  UNION
                  SELECT s.id_tienda FROM public.app_dat_supervisor s WHERE s.uuid = auth.uid()
              )
        ) THEN
            RAISE EXCEPTION 'No tiene acceso a esta operación';
        END IF;
    ELSE
        IF NOT EXISTS (
            SELECT 1
            FROM public.app_dat_operaciones o
            WHERE o.id = p_id_operacion
              AND o.id_tienda IN (
                  SELECT g.id_tienda FROM public.app_dat_gerente g WHERE g.uuid = auth.uid()
                  UNION
                  SELECT s.id_tienda FROM public.app_dat_supervisor s WHERE s.uuid = auth.uid()
              )
        ) THEN
            RAISE EXCEPTION 'No tiene acceso a esta operación';
        END IF;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.app_dat_pago_venta pv
        JOIN public.app_nom_medio_pago mp ON mp.id = pv.id_medio_pago
        WHERE pv.id_operacion_venta = p_id_operacion
          AND mp.es_efectivo = TRUE
    ) THEN
        RAISE EXCEPTION 'Solo se pueden contabilizar operaciones que incluyan efectivo';
    END IF;

    UPDATE public.app_dat_operaciones
    SET contabilizada = p_contabilizada
    WHERE id = p_id_operacion
      AND contabilizada IS DISTINCT FROM p_contabilizada;

    RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_actualizar_operacion_contabilizada(bigint, boolean, bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_actualizar_operacion_contabilizada(bigint, boolean, bigint) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_actualizar_operacion_contabilizada(bigint, boolean, bigint) TO authenticated, service_role;

DROP FUNCTION IF EXISTS public.fn_actualizar_operacion_contabilizada(bigint, boolean);
DROP FUNCTION IF EXISTS public.fn_info_contabilizacion_ordenes_carnaval(bigint[]);
DROP FUNCTION IF EXISTS public.fn_historial_contabilizacion_operacion(bigint);

DO $chk$
DECLARE
    v_n integer;
BEGIN
    SELECT count(*) INTO v_n
      FROM pg_proc
     WHERE pronamespace = 'public'::regnamespace
       AND proname = 'fn_actualizar_operacion_contabilizada';
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'fn_actualizar_operacion_contabilizada quedó con % firmas', v_n;
    END IF;
    IF to_regprocedure('public.fn_actualizar_operacion_contabilizada(bigint,boolean,bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta la firma de 3 parámetros de fn_actualizar_operacion_contabilizada';
    END IF;

    SELECT count(*) INTO v_n
      FROM pg_proc
     WHERE pronamespace = 'public'::regnamespace
       AND proname = 'fn_info_contabilizacion_ordenes_carnaval';
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'fn_info_contabilizacion_ordenes_carnaval quedó con % firmas', v_n;
    END IF;

    SELECT count(*) INTO v_n
      FROM pg_proc
     WHERE pronamespace = 'public'::regnamespace
       AND proname = 'fn_historial_contabilizacion_operacion';
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'fn_historial_contabilizacion_operacion quedó con % firmas', v_n;
    END IF;

    IF has_function_privilege(
        'anon',
        'public.fn_actualizar_operacion_contabilizada(bigint,boolean,bigint)'::regprocedure,
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'anon puede ejecutar fn_actualizar_operacion_contabilizada';
    END IF;
END
$chk$;

COMMIT;

SELECT proname,
       pg_get_function_identity_arguments(oid) AS firma,
       has_function_privilege('anon', oid, 'EXECUTE') AS anon_ejecuta,
       has_function_privilege('authenticated', oid, 'EXECUTE') AS authenticated_ejecuta
  FROM pg_proc
 WHERE pronamespace = 'public'::regnamespace
   AND proname IN (
       'fn_actualizar_operacion_contabilizada',
       'fn_info_contabilizacion_ordenes_carnaval',
       'fn_historial_contabilizacion_operacion'
   )
 ORDER BY proname;
