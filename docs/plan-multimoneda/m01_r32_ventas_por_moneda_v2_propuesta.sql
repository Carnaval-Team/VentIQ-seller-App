BEGIN;

-- BORRADOR M06-R05. NO EJECUTAR sin revisión y puerta DB correspondiente.
-- `fn_reporte_ventas_por_moneda_v2`: la semántica REAL de la v1 declarada en
-- contrato. La v1 queda intacta para los clientes que ya la consumen.
--
-- Qué responde la función (inspección de newa, huella 91c3bae4...):
--   «Para las ventas creadas en [desde, hasta] con último estado 2
--    (completada), ¿cuánto se cobró en cada divisa y a cuánto equivale en
--    CUP?»
--
-- Eso es una COHORTE DE VENTAS, no un flujo de caja del período: el pago se
-- atribuye a la venta por `id_operacion_venta` sin mirar `fecha_pago`. Una
-- liquidación CxC de una venta de ayer cobrada hoy cuenta en la cohorte de
-- ayer. La v2 lo declara en el envelope (`base_temporal = 'cohorte_ventas'`,
-- `magnitud = 'cobrado'`) en vez de dejar que el consumidor lo interprete
-- como caja del período.
--
-- Cambios respecto a la v1, todos de contrato — el cálculo es el mismo:
--   · Envelope R01: version_reporte, versiones_monetarias, magnitud, base
--     temporal, corte temporal resuelto y completitud.
--   · Importes como cadenas decimales exactas (spec §7), nunca double.
--   · `pagos_sin_equivalente` cuenta cobros con `monto_cup_equivalente`
--     NULL: faltan del consolidado base y se declaran como incompletitud,
--     no se convierten silenciosamente en 0.
--   · LEFT JOIN al catálogo de medios: la baja de un medio no borra el
--     cobro histórico (en la v1 era JOIN interno; el catálogo nominal rara
--     vez borra, pero el contrato no lo exige).
--   · `tasa_promedio` se declara informativa (ponderada base/nativo): no es
--     fuente para recalcular registros.
--   · `importe_consolidado` = equivalente CUP × tasa de consolidación
--     ACTUAL: es presentación, no contabilidad. La v1 ya lo hacía; aquí se
--     etiqueta `presentacion_consolidada` para que nadie lo sume como
--     magnitud contable.
--   · Autorización en servidor: fn_config_tienda_puede_leer(p_id_tienda).

SET LOCAL app.m01_r32_moneda_cohorte_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r32_moneda_cohorte_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador M06-R05: NO EJECUTAR sin revision en newa';
    END IF;
    IF to_regprocedure(
        'public.fn_reporte_ventas_por_moneda(bigint,date,date,bigint)'
    ) IS NULL
       OR to_regprocedure('public.fn_moneda_consolidacion(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta la v1 por moneda o la consolidacion de tienda';
    END IF;
    IF to_regprocedure(
        'public.fn_reporte_ventas_por_moneda_v2(bigint,date,date,bigint)'
    ) IS NOT NULL THEN
        RAISE EXCEPTION 'fn_reporte_ventas_por_moneda_v2 ya existe';
    END IF;
END;
$preflight$;

CREATE FUNCTION public.fn_reporte_ventas_por_moneda_v2(
    p_id_tienda bigint,
    p_desde     date,
    p_hasta     date,
    p_id_tpv    bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
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
    -- [desde, hasta] inclusive (criterio legacy, conservado) con último
    -- estado 2. La fecha del pago no filtra — por eso NO es flujo de caja.
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
                -- Informativa: ponderada por importe. NO recalcula registros.
                'tasa_promedio',     a.tasa_promedio::text,
                'moneda_consolidacion', c.moneda::text,
                -- Presentación con tasa de consolidación actual; no es la
                -- magnitud contable (esa es importe_base en CUP histórico).
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
    public.fn_reporte_ventas_por_moneda_v2(bigint,date,date,bigint)
FROM anon;
GRANT EXECUTE ON FUNCTION
    public.fn_reporte_ventas_por_moneda_v2(bigint,date,date,bigint)
TO authenticated;

COMMENT ON FUNCTION public.fn_reporte_ventas_por_moneda_v2(bigint,date,date,bigint) IS
    'Cohorte de ventas completadas: cobrado por divisa (nativo exacto), equivalente CUP histórico y consolidado de presentación. NO es flujo de caja del período.';

COMMIT;

-- Verificación de lectura (tras aplicar):
--   SELECT fn_reporte_ventas_por_moneda_v2(<id_tienda>, '2026-01-01', '2026-12-31');
--   ->'base_temporal' = 'cohorte_ventas'; ->'completitud' declara estado;
--   las filas traen importes como cadenas decimales.
