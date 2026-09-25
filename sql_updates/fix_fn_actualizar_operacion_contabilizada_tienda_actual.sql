-- Fix: fn_actualizar_operacion_contabilizada debe validar el permiso contra la
-- tienda Inventtia desde la cual se está operando (la tienda actual del admin
-- de Carnaval), no contra la tienda propietaria de la operación. Esto es
-- necesario porque las órdenes de Carnaval pueden generar operaciones VentIQ
-- vinculadas a otra tienda, pero el gerente/supervisor de la tienda 177 debe
-- poder contabilizar las órdenes de Carnaval que ve en su vista.
--
-- Se mantiene el comportamiento legacy cuando no se pasa p_id_tienda.
--
-- También se ajusta fn_info_contabilizacion_ordenes_carnaval para que, si se le
-- pasa la tienda actual y el usuario tiene rol en ella, devuelva la información
-- de contabilización sin filtrar por la tienda propietaria de la operación.

CREATE OR REPLACE FUNCTION public.fn_info_contabilizacion_ordenes_carnaval(
    p_order_ids BIGINT[],
    p_id_tienda BIGINT DEFAULT NULL
)
RETURNS TABLE(
    order_id BIGINT,
    operation_id BIGINT,
    contabilizada BOOLEAN,
    contabilizada_at TIMESTAMPTZ,
    contabilizada_por_nombre TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        (regexp_match(o.observaciones, 'Venta desde orden\s+(\d+)'))[1]::BIGINT,
        o.id,
        o.contabilizada,
        o.contabilizada_at,
        COALESCE(tr.nombres || ' ' || tr.apellidos, o.contabilizada_por::TEXT)
    FROM public.app_dat_operaciones o
    LEFT JOIN LATERAL (
        SELECT t.nombres, t.apellidos
        FROM public.app_dat_trabajadores t
        WHERE t.uuid = o.contabilizada_por
          AND t.id_tienda = o.id_tienda
        ORDER BY t.deleted_at NULLS FIRST, t.id DESC
        LIMIT 1
    ) tr ON TRUE
    WHERE o.observaciones ~ 'Venta desde orden\s+\d+'
      AND (regexp_match(o.observaciones, 'Venta desde orden\s+(\d+)'))[1]::BIGINT = ANY(p_order_ids)
      AND (
          -- Nueva lógica: si se pasa tienda actual y el usuario tiene rol en ella,
          -- no filtrar por tienda propietaria de la operación.
          (p_id_tienda IS NOT NULL AND EXISTS (
              SELECT 1
              FROM public.app_dat_tienda t
              WHERE t.id = p_id_tienda
                AND t.id IN (
                    SELECT g.id_tienda FROM public.app_dat_gerente g WHERE g.uuid = auth.uid()
                    UNION
                    SELECT s.id_tienda FROM public.app_dat_supervisor s WHERE s.uuid = auth.uid()
                    UNION
                    SELECT a.id_tienda FROM public.auditor a WHERE a.uuid = auth.uid()
                )
          ))
          OR
          -- Lógica legacy: filtrar por tienda propietaria de la operación.
          o.id_tienda IN (
              SELECT g.id_tienda FROM public.app_dat_gerente g WHERE g.uuid = auth.uid()
              UNION
              SELECT s.id_tienda FROM public.app_dat_supervisor s WHERE s.uuid = auth.uid()
              UNION
              SELECT a.id_tienda FROM public.auditor a WHERE a.uuid = auth.uid()
          )
      );
$$;

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
        -- Nueva lógica: permiso basado en la tienda Inventtia actual (desde
        -- donde se está contabilizando la orden de Carnaval).
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
        -- Lógica legacy: permiso basado en la tienda propietaria de la operación.
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

GRANT EXECUTE ON FUNCTION public.fn_info_contabilizacion_ordenes_carnaval(BIGINT[], BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_actualizar_operacion_contabilizada(BIGINT, BOOLEAN, BIGINT) TO authenticated;

-- Ajuste análogo para el historial de contabilización: permitir ver el
-- historial si se tiene rol en la tienda actual de Carnaval, aunque la operación
-- pertenezca a otra tienda.

CREATE OR REPLACE FUNCTION public.fn_historial_contabilizacion_operacion(
    p_id_operacion BIGINT,
    p_id_tienda BIGINT DEFAULT NULL
)
RETURNS TABLE(
    id BIGINT,
    contabilizada BOOLEAN,
    cambiado_por UUID,
    cambiado_por_nombre TEXT,
    cambiado_at TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        h.id,
        h.contabilizada,
        h.cambiado_por,
        COALESCE(tr.nombres || ' ' || tr.apellidos, h.cambiado_por::TEXT),
        h.cambiado_at
    FROM public.app_dat_operacion_contabilizacion_historial h
    JOIN public.app_dat_operaciones o ON o.id = h.id_operacion
    LEFT JOIN LATERAL (
        SELECT t.nombres, t.apellidos
        FROM public.app_dat_trabajadores t
        WHERE t.uuid = h.cambiado_por
          AND t.id_tienda = o.id_tienda
        ORDER BY t.deleted_at NULLS FIRST, t.id DESC
        LIMIT 1
    ) tr ON TRUE
    WHERE h.id_operacion = p_id_operacion
      AND (
          (p_id_tienda IS NOT NULL AND EXISTS (
              SELECT 1
              FROM public.app_dat_tienda t
              WHERE t.id = p_id_tienda
                AND t.id IN (
                    SELECT g.id_tienda FROM public.app_dat_gerente g WHERE g.uuid = auth.uid()
                    UNION
                    SELECT s.id_tienda FROM public.app_dat_supervisor s WHERE s.uuid = auth.uid()
                    UNION
                    SELECT a.id_tienda FROM public.auditor a WHERE a.uuid = auth.uid()
                )
          ))
          OR
          o.id_tienda IN (
              SELECT g.id_tienda FROM public.app_dat_gerente g WHERE g.uuid = auth.uid()
              UNION
              SELECT s.id_tienda FROM public.app_dat_supervisor s WHERE s.uuid = auth.uid()
              UNION
              SELECT a.id_tienda FROM public.auditor a WHERE a.uuid = auth.uid()
          )
      )
    ORDER BY h.cambiado_at DESC, h.id DESC;
$$;

GRANT EXECUTE ON FUNCTION public.fn_historial_contabilizacion_operacion(BIGINT, BIGINT) TO authenticated;
