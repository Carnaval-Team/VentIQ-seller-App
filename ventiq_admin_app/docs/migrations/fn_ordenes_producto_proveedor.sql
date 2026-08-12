-- =============================================================================
-- fn_ordenes_producto_proveedor
-- Misma lógica de filtrado que fn_reporte_ventas_con_proveedor2
-- (ventas completadas + pagadas en el rango).
-- =============================================================================

DROP FUNCTION IF EXISTS public.fn_ordenes_producto_proveedor(
  BIGINT, BIGINT, BIGINT[], DATE, DATE, BIGINT
);
DROP FUNCTION IF EXISTS public.fn_ordenes_producto_proveedor(
  BIGINT, BIGINT, DATE, DATE, BIGINT
);
DROP FUNCTION IF EXISTS public.fn_ordenes_producto_proveedor(
  BIGINT, BIGINT, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE, BIGINT
);

CREATE OR REPLACE FUNCTION public.fn_ordenes_producto_proveedor(
    p_id_tienda    BIGINT,
    p_id_proveedor BIGINT,
    p_fecha_desde  TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    p_fecha_hasta  TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    p_id_almacen   BIGINT DEFAULT NULL
)
RETURNS TABLE (
    id_producto       BIGINT,
    id_operacion      BIGINT,
    fecha_creacion    TIMESTAMPTZ,
    fecha_completado  TIMESTAMPTZ,
    cantidad          NUMERIC,
    nombre_cliente    TEXT
)
LANGUAGE sql
SECURITY DEFINER
AS $$
    SELECT
        ep.id_producto::BIGINT,
        o.id::BIGINT AS id_operacion,
        o.created_at AS fecha_creacion,
        eo.created_at AS fecha_completado,
        SUM(ep.cantidad)::NUMERIC AS cantidad,
        COALESCE(
            NULLIF(TRIM(cli.nombre_completo::TEXT), ''),
            NULLIF(TRIM(ov.denominacion::TEXT), ''),
            'Sin cliente'
        ) AS nombre_cliente
    FROM app_dat_operaciones o
    JOIN app_dat_operacion_venta ov
      ON o.id = ov.id_operacion
    JOIN app_dat_extraccion_productos ep
      ON o.id = ep.id_operacion
    JOIN app_dat_producto p
      ON ep.id_producto = p.id
    JOIN app_dat_estado_operacion eo
      ON o.id = eo.id_operacion
    LEFT JOIN app_dat_clientes cli
      ON ov.id_cliente = cli.id
    WHERE o.id_tienda = p_id_tienda
      AND COALESCE(p.id_proveedor, 0)::BIGINT = p_id_proveedor
      AND eo.estado = 2
      AND eo.id = (
            SELECT MAX(id)
            FROM app_dat_estado_operacion
            WHERE id_operacion = o.id
          )
      AND ov.es_pagada = true
      AND o.id_tipo_operacion = (
            SELECT id
            FROM app_nom_tipo_operacion
            WHERE LOWER(denominacion) = 'venta'
            LIMIT 1
          )
      AND (p_fecha_desde IS NULL OR o.created_at::DATE >= p_fecha_desde::DATE)
      AND (p_fecha_hasta IS NULL OR o.created_at::DATE <= p_fecha_hasta::DATE)
      AND (
            p_id_almacen IS NULL
            OR ep.id_ubicacion IN (
                SELECT id
                FROM app_dat_layout_almacen
                WHERE id_almacen = p_id_almacen
              )
          )
      AND ep.cantidad > 0
    GROUP BY
        ep.id_producto,
        o.id,
        o.created_at,
        eo.created_at,
        cli.nombre_completo,
        ov.denominacion
    ORDER BY ep.id_producto, o.created_at DESC, o.id DESC;
$$;

GRANT EXECUTE ON FUNCTION public.fn_ordenes_producto_proveedor(
  BIGINT, BIGINT, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE, BIGINT
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.fn_ordenes_producto_proveedor(
  BIGINT, BIGINT, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE, BIGINT
) TO service_role;
