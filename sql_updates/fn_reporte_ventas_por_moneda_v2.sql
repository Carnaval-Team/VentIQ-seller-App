-- Aditivo: fn_reporte_ventas_por_moneda_v2 en main (ya existe en newa).
-- Misma semántica que docs/plan-multimoneda/m01_r32_ventas_por_moneda_v2_propuesta.sql
-- sin el preflight de borrador. Requiere v1 y fn_moneda_consolidacion.
--
-- Aplicar en el SQL Editor del proyecto main (vsieeihstajlrdvpuooh).

DO $preflight$
BEGIN
    IF to_regprocedure(
        'public.fn_reporte_ventas_por_moneda(bigint,date,date,bigint)'
    ) IS NULL
       OR to_regprocedure('public.fn_moneda_consolidacion(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta la v1 por moneda o la consolidacion de tienda';
    END IF;
    IF to_regprocedure(
        'public.fn_config_tienda_puede_leer(bigint)'
    ) IS NULL THEN
        RAISE EXCEPTION 'Falta fn_config_tienda_puede_leer';
    END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.fn_reporte_ventas_por_moneda_v2(
    p_id_tienda bigint,
    p_desde date,
    p_hasta date,
    p_id_tpv bigint DEFAULT NULL::bigint
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
    v_doc jsonb;
BEGIN
    IF public.fn_config_tienda_puede_leer(p_id_tienda) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    WITH cons AS (
        SELECT * FROM public.fn_moneda_consolidacion(p_id_tienda)
    ),
    -- Cobros atribuidos a la cohorte: ventas por created_at en el rango
    -- [desde, hasta] inclusive con último estado 2. NO es flujo de caja.
    cohorte AS (
        SELECT pv.id, pv.id_operacion_venta, pv.monto,
               pv.monto_cup_equivalente, pv.moneda, pv.id_medio_pago,
               mp.es_efectivo
        FROM public.app_dat_pago_venta pv
        JOIN public.app_dat_operacion_venta ov
          ON ov.id_operacion = pv.id_operacion_venta
        JOIN public.app_dat_operaciones o ON o.id = ov.id_operacion
        LEFT JOIN public.app_nom_medio_pago mp ON mp.id = pv.id_medio_pago
        WHERE o.id_tienda = p_id_tienda
          AND o.created_at::date BETWEEN p_desde AND p_hasta
          AND (p_id_tpv IS NULL OR ov.id_tpv = p_id_tpv)
          AND EXISTS (
              SELECT 1 FROM public.app_dat_estado_operacion eo
              WHERE eo.id_operacion = o.id AND eo.estado = 2
                AND eo.id = (
                    SELECT max(eo2.id) FROM public.app_dat_estado_operacion eo2
                    WHERE eo2.id_operacion = o.id
                )
          )
    ),
    agg AS (
        SELECT
            upper(trim(moneda))                                AS moneda,
            count(DISTINCT id_operacion_venta)                 AS operaciones,
            sum(monto)                                         AS importe_nativo,
            sum(monto_cup_equivalente)                         AS importe_base,
            sum(monto) FILTER (WHERE es_efectivo)              AS efectivo_nativo,
            sum(monto) FILTER (WHERE NOT coalesce(es_efectivo, false))
                                                               AS digital_nativo,
            round(sum(monto_cup_equivalente) / nullif(sum(monto), 0), 4)
                                                               AS tasa_promedio
        FROM cohorte
        GROUP BY 1
    ),
    filas AS (
        SELECT jsonb_agg(
            jsonb_build_object(
                'moneda',            a.moneda,
                'operaciones',       a.operaciones,
                'importe_nativo',    a.importe_nativo::text,
                'importe_base',      a.importe_base::text,
                'efectivo_nativo',   a.efectivo_nativo::text,
                'digital_nativo',    a.digital_nativo::text,
                'tasa_promedio',     a.tasa_promedio::text,
                'moneda_consolidacion', c.moneda::text,
                'importe_consolidado', (
                    CASE WHEN a.moneda = c.moneda THEN a.importe_nativo
                         ELSE a.importe_base * c.tasa_cup END
                )::text
            ) ORDER BY a.importe_base DESC NULLS LAST
        ) AS filas_json
        FROM agg a CROSS JOIN cons c
    ),
    incompletos AS (
        SELECT count(*)::integer AS n
        FROM cohorte
        WHERE monto_cup_equivalente IS NULL
    )
    SELECT jsonb_build_object(
        'version_reporte',      'ventas-por-moneda-v2',
        'versiones_monetarias', jsonb_build_array('legacy', 'producto-v1'),
        'magnitud',             'cobrado',
        'base_temporal',        'cohorte_ventas',
        'corte',                jsonb_build_object(
            'desde',          p_desde,
            'hasta',          p_hasta,
            'hasta_inclusivo', true,
            'estados',         jsonb_build_array(2),
            'nota', 'Pagos atribuidos a ventas de la cohorte, no por fecha de pago'
        ),
        'moneda_base',          'CUP',
        'completitud',          jsonb_build_object(
            'estado', CASE WHEN (SELECT n FROM incompletos) > 0
                           THEN 'incompleto' ELSE 'completo' END,
            'motivos', CASE WHEN (SELECT n FROM incompletos) > 0
                            THEN jsonb_build_array('PAGOS_SIN_EQUIVALENTE_CUP')
                            ELSE '[]'::jsonb END,
            'pagos_sin_equivalente', (SELECT n FROM incompletos)
        ),
        'filas',                COALESCE((SELECT filas_json FROM filas), '[]'::jsonb)
    ) INTO v_doc;

    RETURN v_doc;
END;
$function$;

REVOKE EXECUTE ON FUNCTION
    public.fn_reporte_ventas_por_moneda_v2(bigint, date, date, bigint)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
    public.fn_reporte_ventas_por_moneda_v2(bigint, date, date, bigint)
TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_reporte_ventas_por_moneda_v2(bigint, date, date, bigint) IS
    'Cohorte de ventas completadas: cobrado por divisa (nativo exacto), equivalente CUP histórico y consolidado de presentación. NO es flujo de caja del período.';
