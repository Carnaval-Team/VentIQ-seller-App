-- RPC para listar márgenes comerciales de una tienda con datos del producto
-- Optimizado con JOIN directo en lugar de subconsultas
-- Columnas validadas contra VentiQ.sql:
--   app_cont_margen_comercial: id, id_producto, id_variante, id_tienda, margen_deseado, tipo_margen, fecha_desde, fecha_hasta, created_at, updated_at
--   app_dat_producto: id, denominacion, sku, imagen
--   app_dat_variantes: id, id_sub_categoria, id_atributo (NO tiene denominacion)
--   app_dat_subcategorias: id, denominacion
--   app_dat_atributos: id, denominacion, label
--   app_dat_precio_venta: id, id_producto, id_variante, precio_venta_cup, fecha_desde, fecha_hasta, created_at
--   app_dat_producto_presentacion: id, id_producto, es_base, precio_promedio (tipo real)
CREATE OR REPLACE FUNCTION public.get_margenes_comerciales_by_tienda(
  p_id_tienda BIGINT
)
RETURNS TABLE (
  id BIGINT,
  id_producto BIGINT,
  producto_denominacion VARCHAR,
  producto_sku VARCHAR,
  producto_imagen TEXT,
  id_variante BIGINT,
  variante_denominacion TEXT,
  margen_deseado NUMERIC,
  tipo_margen SMALLINT,
  fecha_desde DATE,
  fecha_hasta DATE,
  precio_venta_cup NUMERIC,
  precio_promedio_usd REAL,
  created_at TIMESTAMP WITH TIME ZONE,
  updated_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    mc.id::BIGINT,
    mc.id_producto::BIGINT,
    p.denominacion::VARCHAR,
    p.sku::VARCHAR,
    p.imagen::TEXT,
    mc.id_variante::BIGINT,
    -- Variante no tiene denominacion propia; se construye desde subcategoria + atributo
    CASE
      WHEN mc.id_variante IS NOT NULL
        THEN (sc.denominacion || ' - ' || a.denominacion)::TEXT
      ELSE NULL
    END,
    mc.margen_deseado::NUMERIC,
    mc.tipo_margen::SMALLINT,
    mc.fecha_desde::DATE,
    mc.fecha_hasta::DATE,
    pv.precio_venta_cup::NUMERIC,
    pp.precio_promedio::REAL,
    mc.created_at::TIMESTAMP WITH TIME ZONE,
    mc.updated_at::TIMESTAMP WITH TIME ZONE
  FROM app_cont_margen_comercial mc
  INNER JOIN app_dat_producto p ON mc.id_producto = p.id
  LEFT JOIN app_dat_variantes v ON mc.id_variante = v.id
  LEFT JOIN app_dat_subcategorias sc ON v.id_sub_categoria = sc.id
  LEFT JOIN app_dat_atributos a ON v.id_atributo = a.id
  LEFT JOIN LATERAL (
    SELECT pv_inner.precio_venta_cup
    FROM app_dat_precio_venta pv_inner
    WHERE pv_inner.id_producto = mc.id_producto
      AND (mc.id_variante IS NULL OR pv_inner.id_variante = mc.id_variante)
      AND pv_inner.fecha_desde <= CURRENT_DATE
      AND (pv_inner.fecha_hasta IS NULL OR pv_inner.fecha_hasta >= CURRENT_DATE)
    ORDER BY pv_inner.created_at DESC
    LIMIT 1
  ) pv ON TRUE
  LEFT JOIN LATERAL (
    SELECT pp_inner.precio_promedio
    FROM app_dat_producto_presentacion pp_inner
    WHERE pp_inner.id_producto = mc.id_producto
      AND pp_inner.es_base = true
    LIMIT 1
  ) pp ON TRUE
  WHERE mc.id_tienda = p_id_tienda
  ORDER BY p.denominacion ASC, mc.created_at DESC;
END;
$$ LANGUAGE plpgsql;
