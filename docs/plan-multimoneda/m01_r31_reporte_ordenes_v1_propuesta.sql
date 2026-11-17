BEGIN;

-- BORRADOR M06-R02. NO EJECUTAR sin revisión y puerta DB correspondiente.
-- `reporte_ordenes_json_v2`: lectura versionada por línea para ventas
-- producto-v1. Aditiva: la `reporte_ordenes_json` legacy queda intacta para
-- los clientes que ya la consumen.
--
-- Qué corrige respecto a la v1 del reporte:
--   · Cada item declara su versión monetaria y, si es producto-v1, expone
--     id_linea_cliente, moneda_venta, componentes de ajuste (bruto/descuento
--     manual/neto nativo), tasa fijada y equivalentes CUP históricos — como
--     cadenas decimales exactas, no números flotantes.
--   · El cobro se emite por identidad de pago con sus aplicaciones a líneas
--     (app_dat_pago_aplicacion), sin join detalle×pago que multiplique
--     ingresos. Un pago cubre N líneas; el monto del pago no se repite por
--     línea ni la línea por pago.
--   · Los pagos ya no filtran por medio activo: desactivar un medio no
--     puede borrar cobros históricos del reporte (LEFT JOIN al catálogo).
--   · El medio de pago SELECCIONADO en la línea viaja separado del cobrado
--     real: `seleccion_pendiente`/CxC no se lee como pago recibido.
--   · Envelope de contrato (R01): version_reporte, versiones_monetarias
--     observadas, magnitud/base_temporal declaradas y completitud con
--     motivos. Una venta v1 sin líneas v1 se cuenta como metadato faltante,
--     no como venta de cero.
--   · Autorización en servidor: exige fn_config_tienda_puede_leer($1). La
--     v1 legacy no la tenía; SECURITY DEFINER no sustituye ese chequeo.
--
-- Magnitudes declaradas (spec §3): los importes de línea son VENTA NETA
-- (neto fijado tras ajustes, por moneda nativa) y su NETO CONTABLE CUP
-- (equivalente histórico por línea). Los de `pagos`/`aplicaciones` son
-- COBRADO. `total_operacion`/`importe_total` se conservan como referencia
-- legacy, sin reetiquetar.

SET LOCAL app.m01_r31_ordenes_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r31_ordenes_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador M06-R02: NO EJECUTAR sin revision en newa';
    END IF;
    -- Requiere el contrato v1 de líneas y la atribución de cobros (R12/R15).
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'app_dat_extraccion_productos'
          AND column_name = 'version_monetaria'
    ) OR to_regclass('public.app_dat_pago_aplicacion') IS NULL THEN
        RAISE EXCEPTION 'Falta el contrato producto-v1 (extraccion/pago_aplicacion)';
    END IF;
    IF to_regprocedure(
        'public.reporte_ordenes_json_v2(bigint,timestamptz,timestamptz,bigint)'
    ) IS NOT NULL THEN
        RAISE EXCEPTION 'reporte_ordenes_json_v2 ya existe';
    END IF;
END;
$preflight$;

CREATE FUNCTION public.reporte_ordenes_json_v2(
    p_id_tienda   bigint,
    p_fecha_desde timestamptz DEFAULT NULL,
    p_fecha_hasta timestamptz DEFAULT NULL,
    p_id_tpv      bigint      DEFAULT NULL
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
    -- Autorización en servidor, independiente de preferencias del cliente.
    IF public.fn_config_tienda_puede_leer(p_id_tienda) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    WITH
    params AS MATERIALIZED (
        SELECT
            COALESCE(p_fecha_desde, CURRENT_TIMESTAMP - INTERVAL '30 days') AS fecha_desde,
            COALESCE(p_fecha_hasta, CURRENT_TIMESTAMP)                      AS fecha_hasta
    ),
    tipo_venta AS (
        SELECT id FROM public.app_nom_tipo_operacion
        WHERE LOWER(denominacion) = 'venta' LIMIT 1
    ),
    base_ops AS (
        SELECT
            o.id, o.created_at, o.uuid, o.id_tienda,
            ov.id_operacion AS id_operacion_venta,
            ov.id_tpv, ov.id_cliente, ov.importe_total, ov.es_pagada,
            ov.version_monetaria AS venta_version,
            ov.id_revision_politica, ov.id_constancia_politica
        FROM public.app_dat_operaciones o
        CROSS JOIN tipo_venta tv
        LEFT JOIN public.app_dat_operacion_venta ov ON ov.id_operacion = o.id
        CROSS JOIN params pr
        WHERE o.id_tipo_operacion = tv.id
          AND o.id_tienda = p_id_tienda
          AND o.created_at >= pr.fecha_desde
          AND o.created_at <  pr.fecha_hasta
          AND (p_id_tpv IS NULL OR ov.id_tpv = p_id_tpv)
    ),
    ultimo_estado AS (
        SELECT DISTINCT ON (eo.id_operacion)
            eo.id_operacion, eo.estado
        FROM public.app_dat_estado_operacion eo
        JOIN base_ops bo ON eo.id_operacion = bo.id
        ORDER BY eo.id_operacion, eo.id DESC
    ),
    trabajadores AS (
        SELECT uuid, nombres || ' ' || apellidos AS nombre_completo
        FROM public.app_dat_trabajadores
        WHERE uuid IN (SELECT DISTINCT uuid FROM base_ops WHERE uuid IS NOT NULL)
    ),
    descuento_reciente AS (
        SELECT DISTINCT ON (dv.id_operacion)
            dv.id_operacion,
            jsonb_build_object(
                'monto_real',       dv.monto_real,
                'monto_descontado', dv.monto_descontado,
                'tipo_descuento',   dv.tipo_descuento,
                'valor_descuento',  dv.valor_descuento
            ) AS descuento_json
        FROM public.app_dat_descuentos_vendedor dv
        JOIN base_ops bo ON dv.id_operacion = bo.id
        ORDER BY dv.id_operacion, dv.created_at DESC
    ),
    -- Items: un solo scan; la línea v1 expone sus componentes persistidos
    -- como cadenas decimales (spec §7: la autoridad monetaria no pasa por
    -- double). Legacy conserva los campos de siempre y `linea_v1` = NULL.
    items_agg AS (
        SELECT
            ep.id_operacion,
            COUNT(*)::integer                                     AS cantidad_items,
            COALESCE(SUM(ep.importe), 0)                          AS total_operacion,
            COUNT(*) FILTER (WHERE ip.id IS NULL)::integer        AS items_sin_inventario,
            COUNT(*) FILTER (
                WHERE ep.version_monetaria = 'producto-v1'
            )::integer                                            AS lineas_v1,
            jsonb_agg(
                jsonb_build_object(
                    'id_extraccion',    ep.id,
                    'id_producto',      ep.id_producto,
                    'producto_nombre',  p.denominacion,
                    'cantidad',         ep.cantidad,
                    'precio_unitario',  ep.precio_unitario,
                    'importe',          ep.importe,
                    'es_elaborado',     p.es_elaborado,
                    'tiene_inventario', (ip.id IS NOT NULL),
                    'inventario', CASE
                        WHEN ip.id IS NOT NULL THEN jsonb_build_object(
                            'id_inventario',    ip.id,
                            'cantidad_inicial', ip.cantidad_inicial,
                            'cantidad_final',   ip.cantidad_final,
                            'origen_cambio',    ip.origen_cambio,
                            'created_at',       ip.created_at
                        ) ELSE NULL
                    END,
                    'variante', CASE
                        WHEN ep.id_variante IS NOT NULL THEN jsonb_build_object(
                            'id', ep.id_variante, 'atributo', atr.denominacion,
                            'opcion', aop.valor
                        ) ELSE NULL
                    END,
                    'presentacion', np.denominacion,
                    'version_monetaria', ep.version_monetaria,
                    -- Componentes v1: bruto → descuento manual unitario →
                    -- neto nativo, más equivalentes CUP fijados en la venta.
                    'linea_v1', CASE
                        WHEN ep.version_monetaria = 'producto-v1'
                        THEN jsonb_build_object(
                            'id_linea_cliente',               ep.id_linea_cliente,
                            'moneda_venta',                   ep.moneda_venta,
                            'precio_unitario_nativo',         ep.precio_unitario_nativo::text,
                            'descuento_manual_unitario_nativo', ep.descuento_manual_unitario_nativo::text,
                            'precio_unitario_neto_nativo',    ep.precio_unitario_neto_nativo::text,
                            'importe_bruto_nativo',           ep.importe_bruto_nativo::text,
                            'importe_neto_nativo',            ep.importe_neto_nativo::text,
                            'tasa_cambio_cup',                ep.tasa_cambio_cup::text,
                            'importe_bruto_cup_equivalente',  ep.importe_bruto_cup_equivalente::text,
                            'importe_neto_cup_equivalente',   ep.importe_neto_cup_equivalente::text,
                            'seleccion_pendiente',            ep.seleccion_pendiente,
                            'medio_pago_seleccionado',        jsonb_build_object(
                                'id',           ep.id_medio_pago_seleccionado,
                                'denominacion', mps.denominacion
                            )
                        ) ELSE NULL
                    END
                ) ORDER BY ep.id
            ) AS items_json,
            -- Totales nativos por moneda de la orden (venta neta por línea).
            -- Solo líneas v1 aportan moneda; las legacy no se reetiquetan.
            (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'moneda',                      m.moneda_venta,
                        'neto_nativo',                 m.neto::text,
                        'neto_cup_equivalente',        m.neto_cup::text,
                        'lineas',                      m.lineas
                    ) ORDER BY m.moneda_venta
                )
                FROM (
                    SELECT ep2.moneda_venta,
                           SUM(ep2.importe_neto_nativo)          AS neto,
                           SUM(ep2.importe_neto_cup_equivalente) AS neto_cup,
                           COUNT(*)::integer                     AS lineas
                    FROM public.app_dat_extraccion_productos ep2
                    WHERE ep2.id_operacion = ep.id_operacion
                      AND ep2.version_monetaria = 'producto-v1'
                    GROUP BY ep2.moneda_venta
                ) m
            ) AS totales_por_moneda
        FROM base_ops bo
        JOIN public.app_dat_extraccion_productos ep ON ep.id_operacion = bo.id
        JOIN public.app_dat_producto p ON ep.id_producto = p.id
        LEFT JOIN public.app_dat_inventario_productos ip ON ip.id_extraccion = ep.id
        LEFT JOIN public.app_dat_variantes var ON ep.id_variante = var.id
        LEFT JOIN public.app_dat_atributos atr ON var.id_atributo = atr.id
        LEFT JOIN public.app_dat_atributo_opcion aop ON ep.id_opcion_variante = aop.id
        LEFT JOIN public.app_dat_producto_presentacion pp ON ep.id_presentacion = pp.id
        LEFT JOIN public.app_nom_presentacion np ON pp.id_presentacion = np.id
        LEFT JOIN public.app_nom_medio_pago mps
               ON mps.id = ep.id_medio_pago_seleccionado
        GROUP BY ep.id_operacion
    ),
    -- Cobros: por identidad de pago, con sus aplicaciones a líneas.
    -- LEFT JOIN al catálogo de medios: un medio desactivado o retirado no
    -- borra el cobro histórico (la versión anterior filtraba por activo).
    pagos_agg AS (
        SELECT
            pv.id_operacion_venta,
            jsonb_agg(
                jsonb_build_object(
                    'id_pago',               pv.id,
                    'medio_pago',            mp.denominacion,
                    'id_medio_pago',         pv.id_medio_pago,
                    'monto',                 pv.monto,
                    'moneda',                pv.moneda,
                    'monto_nativo',          pv.monto::text,
                    'tasa_cambio',           pv.tasa_cambio::text,
                    'monto_cup_equivalente', pv.monto_cup_equivalente::text,
                    'importe_sin_descuento', pv.importe_sin_descuento,
                    'referencia_pago',       pv.referencia_pago,
                    'fecha_pago',            pv.fecha_pago,
                    'es_digital',            mp.es_digital,
                    'es_efectivo',           mp.es_efectivo,
                    'aplicaciones',          COALESCE(ap.aplicaciones_json, '[]'::jsonb)
                ) ORDER BY pv.id
            ) AS pagos_json
        FROM base_ops bo
        JOIN public.app_dat_pago_venta pv ON pv.id_operacion_venta = bo.id_operacion_venta
        LEFT JOIN public.app_nom_medio_pago mp ON pv.id_medio_pago = mp.id
        LEFT JOIN LATERAL (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'id_linea_cliente',        a.id_linea_cliente,
                    'id_extraccion',           a.id_extraccion,
                    'moneda',                  a.moneda,
                    'monto_nativo',            a.monto_nativo::text,
                    'tasa_cambio_cup',         a.tasa_cambio_cup::text,
                    'importe_cup_equivalente', a.importe_cup_equivalente::text
                ) ORDER BY a.id
            ) AS aplicaciones_json
            FROM public.app_dat_pago_aplicacion a
            WHERE a.id_pago = pv.id
        ) ap ON true
        GROUP BY pv.id_operacion_venta
    ),
    base AS (
        SELECT
            o.*,
            t.denominacion AS tienda_nombre,
            COALESCE(tr.nombre_completo, u.email, 'Sistema') AS vendedor_nombre,
            u.email AS vendedor_email,
            ue.estado AS ultimo_estado,
            (o.id_operacion_venta IS NOT NULL) AS tiene_venta,
            tpv.denominacion AS tpv_nombre,
            cli.nombre_completo AS cliente_nombre,
            cli.telefono AS cliente_telefono,
            COALESCE(ia.cantidad_items, 0) AS cantidad_items,
            COALESCE(ia.total_operacion, 0) AS total_operacion,
            COALESCE(ia.items_sin_inventario, 0) AS items_sin_inventario,
            COALESCE(ia.lineas_v1, 0) AS lineas_v1,
            ia.items_json, ia.totales_por_moneda,
            pa.pagos_json, dr.descuento_json,
            (
                o.id_operacion_venta IS NOT NULL
                AND COALESCE(ia.cantidad_items, 0) > 0
                AND COALESCE(ia.items_sin_inventario, 0) = 0
            ) AS es_completa,
            -- Metadato faltante: la venta dice v1 pero no hay línea que lo
            -- demuestre. No es una venta de cero: es un reporte incompleto.
            (
                o.venta_version = 'producto-v1'
                AND COALESCE(ia.lineas_v1, 0) = 0
            ) AS v1_sin_lineas
        FROM base_ops o
        JOIN public.app_dat_tienda t ON o.id_tienda = t.id
        LEFT JOIN auth.users u ON o.uuid = u.id
        LEFT JOIN trabajadores tr ON tr.uuid = o.uuid
        LEFT JOIN ultimo_estado ue ON ue.id_operacion = o.id
        LEFT JOIN public.app_dat_tpv tpv ON o.id_tpv = tpv.id
        LEFT JOIN public.app_dat_clientes cli ON o.id_cliente = cli.id
        LEFT JOIN items_agg ia ON ia.id_operacion = o.id
        LEFT JOIN pagos_agg pa ON pa.id_operacion_venta = o.id_operacion_venta
        LEFT JOIN descuento_reciente dr ON dr.id_operacion = o.id
    ),
    orden_doc AS (
        SELECT
            es_completa, v1_sin_lineas, venta_version, created_at,
            jsonb_build_object(
                'id_operacion',    id,
                'fecha_operacion', created_at,
                'tienda',   jsonb_build_object('id', id_tienda, 'nombre', tienda_nombre),
                'vendedor', jsonb_build_object(
                    'uuid', uuid, 'nombre_completo', vendedor_nombre,
                    'email', vendedor_email
                ),
                'estado',   jsonb_build_object(
                    'codigo', ultimo_estado,
                    'nombre', CASE ultimo_estado
                        WHEN 1 THEN 'Pendiente' WHEN 2 THEN 'Completada'
                        WHEN 3 THEN 'Cancelada' WHEN 4 THEN 'En Proceso'
                        ELSE 'Desconocido' END
                ),
                'venta',    CASE WHEN tiene_venta THEN jsonb_build_object(
                    'id_tpv', id_tpv, 'tpv_nombre', tpv_nombre,
                    'id_cliente', id_cliente,
                    'cliente_nombre', cliente_nombre,
                    'cliente_telefono', cliente_telefono,
                    'importe_total', importe_total, 'es_pagada', es_pagada,
                    'version_monetaria', venta_version,
                    'id_revision_politica', id_revision_politica,
                    'id_constancia_politica', id_constancia_politica,
                    'totales_por_moneda', COALESCE(totales_por_moneda, '[]'::jsonb)
                ) ELSE NULL END,
                'total_operacion', total_operacion,
                'cantidad_items',  cantidad_items,
                'items',           COALESCE(items_json, '[]'::jsonb),
                'pagos',           COALESCE(pagos_json, '[]'::jsonb),
                'descuento',       descuento_json,
                'razones_incompletitud', CASE WHEN NOT es_completa OR v1_sin_lineas THEN (
                    SELECT jsonb_agg(r) FROM (VALUES
                        (CASE WHEN NOT tiene_venta THEN 'SIN_OPERACION_VENTA' END),
                        (CASE WHEN tiene_venta AND cantidad_items = 0
                              THEN 'SIN_ITEMS_EXTRACCION' END),
                        (CASE WHEN items_sin_inventario > 0
                              THEN 'SIN_INVENTARIO_EN_ITEMS' END),
                        (CASE WHEN v1_sin_lineas
                              THEN 'V1_SIN_METADATA_DE_LINEA' END)
                    ) t(r) WHERE r IS NOT NULL
                ) ELSE NULL END
            ) AS doc
        FROM base
    )
    SELECT jsonb_build_object(
        -- ── Envelope de contrato (R01 / spec §7) ──────────────────────────
        'version_reporte', 'ordenes-json-v2',
        'versiones_monetarias', (
            SELECT COALESCE(jsonb_agg(DISTINCT v ORDER BY v), '[]'::jsonb)
            FROM (
                SELECT COALESCE(venta_version, 'legacy') AS v FROM orden_doc
            ) vv
        ),
        'magnitud',        'mixta_declarada_por_campo',
        'base_temporal',   'comercial',
        'grano',           'operacion',
        'completitud',     jsonb_build_object(
            'estado', CASE
                WHEN COUNT(*) FILTER (WHERE v1_sin_lineas) > 0 THEN 'incompleto'
                ELSE 'completo' END,
            'motivos', CASE
                WHEN COUNT(*) FILTER (WHERE v1_sin_lineas) > 0
                THEN jsonb_build_array('VENTA_V1_SIN_METADATA_DE_LINEA')
                ELSE '[]'::jsonb END,
            'ventas_v1_sin_lineas', COUNT(*) FILTER (WHERE v1_sin_lineas)::integer
        ),
        'periodo', jsonb_build_object(
            'fecha_desde', (SELECT fecha_desde FROM params),
            'fecha_hasta', (SELECT fecha_hasta FROM params)
        ),
        'resumen', jsonb_build_object(
            'total_completas',   COUNT(*) FILTER (WHERE es_completa AND NOT v1_sin_lineas),
            'total_incompletas', COUNT(*) FILTER (WHERE NOT es_completa OR v1_sin_lineas)
        ),
        'ordenes_completas', COALESCE(
            jsonb_agg(doc ORDER BY created_at DESC)
            FILTER (WHERE es_completa AND NOT v1_sin_lineas), '[]'::jsonb),
        'ordenes_incompletas', COALESCE(
            jsonb_agg(doc ORDER BY created_at DESC)
            FILTER (WHERE NOT es_completa OR v1_sin_lineas), '[]'::jsonb)
    ) INTO v_doc
    FROM orden_doc;

    RETURN v_doc;
END;
$function$;

-- La firma cambia respecto a la legacy: es una función NUEVA. Revocar el
-- acceso anónimo por simetría con M01; autenticados la ejecutan bajo la
-- validación de tienda del cuerpo.
REVOKE EXECUTE ON FUNCTION
    public.reporte_ordenes_json_v2(bigint,timestamptz,timestamptz,bigint)
FROM anon;
GRANT EXECUTE ON FUNCTION
    public.reporte_ordenes_json_v2(bigint,timestamptz,timestamptz,bigint)
TO authenticated;

COMMIT;

-- Verificación de lectura (tras aplicar):
--   SELECT reporte_ordenes_json_v2(<id_tienda>);
--   ->'completitud' debe declarar estado/motivos;
--   cada orden v1 ->'venta'->'totales_por_moneda' suma líneas, no pagos;
--   cada pago trae 'aplicaciones' con su id_linea_cliente.
