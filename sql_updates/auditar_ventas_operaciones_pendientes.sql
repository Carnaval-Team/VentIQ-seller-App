WITH ultimo_estado AS (
    SELECT DISTINCT ON (eo.id_operacion)
        eo.id_operacion,
        eo.estado,
        eo.created_at AS fecha_ultimo_estado,
        eo.comentario
    FROM public.app_dat_estado_operacion eo
    ORDER BY eo.id_operacion, eo.id DESC
),
ventas_pendientes AS (
    SELECT
        o.id AS id_operacion,
        o.id_tienda,
        t.denominacion AS tienda,
        o.created_at AS fecha_venta,
        ov.id_tpv,
        tpv.denominacion AS tpv,
        ov.importe_total,
        ov.es_pagada,
        ue.fecha_ultimo_estado,
        ue.comentario AS comentario_estado
    FROM public.app_dat_operaciones o
    INNER JOIN public.app_dat_operacion_venta ov
        ON ov.id_operacion = o.id
    INNER JOIN ultimo_estado ue
        ON ue.id_operacion = o.id
       AND ue.estado = 1
    LEFT JOIN public.app_dat_tienda t
        ON t.id = o.id_tienda
    LEFT JOIN public.app_dat_tpv tpv
        ON tpv.id = ov.id_tpv
)
SELECT
    COUNT(*) AS cantidad_ventas_con_operacion_pendiente,
    COUNT(*) FILTER (WHERE es_pagada = TRUE) AS ventas_pagadas_pendientes,
    COUNT(*) FILTER (WHERE es_pagada = FALSE) AS ventas_cuenta_por_cobrar_pendientes,
    COALESCE(SUM(importe_total), 0) AS importe_total_pendiente,
    MIN(fecha_venta) AS venta_pendiente_mas_antigua,
    MAX(fecha_venta) AS venta_pendiente_mas_reciente
FROM ventas_pendientes;

WITH ultimo_estado AS (
    SELECT DISTINCT ON (eo.id_operacion)
        eo.id_operacion,
        eo.estado,
        eo.created_at AS fecha_ultimo_estado,
        eo.comentario
    FROM public.app_dat_estado_operacion eo
    ORDER BY eo.id_operacion, eo.id DESC
)
SELECT
    o.id AS id_operacion,
    o.id_tienda,
    t.denominacion AS tienda,
    ov.id_tpv,
    tpv.denominacion AS tpv,
    o.created_at AS fecha_venta,
    ov.importe_total,
    ov.es_pagada,
    ue.fecha_ultimo_estado,
    ue.comentario AS comentario_estado,
    o.observaciones
FROM public.app_dat_operaciones o
INNER JOIN public.app_dat_operacion_venta ov
    ON ov.id_operacion = o.id
INNER JOIN ultimo_estado ue
    ON ue.id_operacion = o.id
   AND ue.estado = 1
LEFT JOIN public.app_dat_tienda t
    ON t.id = o.id_tienda
LEFT JOIN public.app_dat_tpv tpv
    ON tpv.id = ov.id_tpv
ORDER BY o.created_at ASC;
