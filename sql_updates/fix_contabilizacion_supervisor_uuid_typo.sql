-- Corrige el alias de tabla en la subconsulta de supervisor de las funciones
-- de contabilización de órdenes Carnaval. Usaba `g.uuid` en lugar de `s.uuid`.

CREATE OR REPLACE FUNCTION public.fn_ordenes_carnaval_por_contabilizacion(
    p_id_tienda BIGINT,
    p_contabilizada BOOLEAN
)
RETURNS TABLE(order_id BIGINT)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT DISTINCT (regexp_match(o.observaciones, 'Venta desde orden\s+(\d+)'))[1]::BIGINT
    FROM public.app_dat_operaciones o
    WHERE o.id_tienda = p_id_tienda
      AND o.contabilizada = p_contabilizada
      AND o.observaciones ~ 'Venta desde orden\s+\d+'
      AND o.id_tienda IN (
          SELECT g.id_tienda FROM public.app_dat_gerente g WHERE g.uuid = auth.uid()
          UNION
          SELECT s.id_tienda FROM public.app_dat_supervisor s WHERE s.uuid = auth.uid()
          UNION
          SELECT a.id_tienda FROM public.auditor a WHERE a.uuid = auth.uid()
      );
$$;

CREATE OR REPLACE FUNCTION public.fn_info_contabilizacion_ordenes_carnaval(
    p_order_ids BIGINT[]
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
      AND o.id_tienda IN (
          SELECT g.id_tienda FROM public.app_dat_gerente g WHERE g.uuid = auth.uid()
          UNION
          SELECT s.id_tienda FROM public.app_dat_supervisor s WHERE s.uuid = auth.uid()
          UNION
          SELECT a.id_tienda FROM public.auditor a WHERE a.uuid = auth.uid()
      );
$$;

GRANT EXECUTE ON FUNCTION public.fn_ordenes_carnaval_por_contabilizacion(BIGINT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_info_contabilizacion_ordenes_carnaval(BIGINT[]) TO authenticated;
