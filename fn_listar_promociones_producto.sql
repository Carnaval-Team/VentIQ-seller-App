CREATE OR REPLACE FUNCTION fn_listar_promociones_producto(
    p_id_producto BIGINT
)
RETURNS TABLE (
    id BIGINT,
    nombre TEXT,
    descripcion TEXT,
    valor_descuento NUMERIC,
    fecha_inicio TIMESTAMP,
    fecha_fin TIMESTAMP,
    precio_base NUMERIC,
    es_recargo BOOLEAN,
    estado BOOLEAN,
    codigo_promocion TEXT,
    tipo_promocion TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Validar que el usuario tenga acceso a la tienda del producto
    IF NOT EXISTS (
        SELECT 1 FROM app_dat_producto p
        WHERE p.id = p_id_producto
        AND EXISTS (
            SELECT 1 FROM (
                SELECT g.id_tienda FROM app_dat_gerente g WHERE g.uuid = auth.uid()
                UNION
                SELECT s.id_tienda FROM app_dat_supervisor s WHERE s.uuid = auth.uid()
                UNION
                SELECT a.id_tienda FROM app_dat_almacenero al 
                JOIN app_dat_almacen a ON al.id_almacen = a.id 
                WHERE al.uuid = auth.uid()
                UNION
                SELECT tpv.id_tienda FROM app_dat_vendedor v 
                JOIN app_dat_tpv tpv ON v.id_tpv = tpv.id 
                WHERE v.uuid = auth.uid()
            ) accesos
            WHERE accesos.id_tienda = p.id_tienda
        )
    ) THEN
        RAISE EXCEPTION 'No tiene acceso al producto especificado';
    END IF;

    RETURN QUERY
    SELECT 
        pr.id::BIGINT,
        pr.nombre::TEXT,
        pr.descripcion::TEXT,
        pr.valor_descuento::NUMERIC,
        pr.fecha_inicio::TIMESTAMP,
        pr.fecha_fin::TIMESTAMP,
        COALESCE(pv.precio_venta_cup, 0.0)::NUMERIC as precio_base,
        CASE 
            WHEN tp.denominacion ILIKE '%recargo%' OR tp.denominacion ILIKE '%aumento%' THEN true
            ELSE false
        END::BOOLEAN as es_recargo,
        pr.estado::BOOLEAN,
        pr.codigo_promocion::TEXT,
        tp.denominacion::TEXT as tipo_promocion
    FROM app_mkt_promociones pr
    INNER JOIN app_mkt_tipo_promocion tp ON pr.id_tipo_promocion = tp.id
    INNER JOIN app_mkt_promocion_productos pp ON pr.id = pp.id_promocion
    LEFT JOIN app_dat_precio_venta pv ON pp.id_producto = pv.id_producto
        AND pv.fecha_desde <= CURRENT_DATE 
        AND (pv.fecha_hasta IS NULL OR pv.fecha_hasta >= CURRENT_DATE)
    WHERE pp.id_producto = p_id_producto
        AND pr.estado = true
        AND pr.fecha_inicio <= CURRENT_TIMESTAMP
        AND pr.fecha_fin >= CURRENT_TIMESTAMP
    ORDER BY pr.created_at DESC;
END;
$$;
