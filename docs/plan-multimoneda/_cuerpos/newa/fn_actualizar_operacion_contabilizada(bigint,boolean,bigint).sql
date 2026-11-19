CREATE OR REPLACE FUNCTION public.fn_actualizar_operacion_contabilizada(p_id_operacion bigint, p_contabilizada boolean, p_id_tienda bigint DEFAULT NULL::bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$

