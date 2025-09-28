-- Funciones RPC para optimizar consultas del StoreService
-- Ejecutar estas funciones en Supabase SQL Editor

-- 1. Función para obtener estadísticas de ventas por tienda
CREATE OR REPLACE FUNCTION get_ventas_stats_por_tienda()
RETURNS TABLE (
  id_tienda INTEGER,
  total_ventas BIGINT
) 
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    t.id as id_tienda,
    COALESCE(COUNT(ov.id_operacion), 0) as total_ventas
  FROM app_dat_tienda t
  LEFT JOIN app_dat_tpv tpv ON tpv.id_tienda = t.id
  LEFT JOIN app_dat_operacion_venta ov ON ov.id_tpv = tpv.id
  GROUP BY t.id;
END;
$$;

-- 2. Función para obtener conteo de productos por tienda
CREATE OR REPLACE FUNCTION get_productos_count_por_tienda()
RETURNS TABLE (
  id_tienda INTEGER,
  total_productos BIGINT
) 
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    t.id as id_tienda,
    COALESCE(COUNT(p.id), 0) as total_productos
  FROM app_dat_tienda t
  LEFT JOIN app_dat_producto p ON p.id_tienda = t.id
  GROUP BY t.id;
END;
$$;

-- 3. Función para obtener conteo de trabajadores por tienda
CREATE OR REPLACE FUNCTION get_trabajadores_count_por_tienda()
RETURNS TABLE (
  id_tienda INTEGER,
  total_trabajadores BIGINT
) 
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    t.id as id_tienda,
    COALESCE(COUNT(tr.id), 0) as total_trabajadores
  FROM app_dat_tienda t
  LEFT JOIN app_dat_trabajadores tr ON tr.id_tienda = t.id
  GROUP BY t.id;
END;
$$;

-- 4. Función para obtener ventas del mes por tienda
CREATE OR REPLACE FUNCTION get_ventas_mes_por_tienda(fecha_inicio TIMESTAMP)
RETURNS TABLE (
  id_tienda INTEGER,
  ventas_mes NUMERIC
) 
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    t.id as id_tienda,
    COALESCE(SUM(ov.importe_total), 0) as ventas_mes
  FROM app_dat_tienda t
  LEFT JOIN app_dat_tpv tpv ON tpv.id_tienda = t.id
  LEFT JOIN app_dat_operacion_venta ov ON ov.id_tpv = tpv.id 
    AND ov.created_at >= fecha_inicio
  GROUP BY t.id;
END;
$$;

-- 5. Función optimizada para obtener todas las estadísticas de una vez
CREATE OR REPLACE FUNCTION get_tiendas_con_estadisticas()
RETURNS TABLE (
  id INTEGER,
  denominacion VARCHAR,
  direccion VARCHAR,
  ubicacion VARCHAR,
  created_at TIMESTAMP,
  total_ventas BIGINT,
  total_productos BIGINT,
  total_trabajadores BIGINT,
  ventas_mes NUMERIC,
  plan_nombre VARCHAR,
  plan_precio NUMERIC,
  fecha_vencimiento TIMESTAMP
) 
LANGUAGE plpgsql
AS $$
DECLARE
  fecha_inicio_mes TIMESTAMP := DATE_TRUNC('month', CURRENT_DATE);
BEGIN
  RETURN QUERY
  SELECT 
    t.id,
    t.denominacion,
    t.direccion,
    t.ubicacion,
    t.created_at,
    COALESCE(ventas_stats.total_ventas, 0) as total_ventas,
    COALESCE(productos_stats.total_productos, 0) as total_productos,
    COALESCE(trabajadores_stats.total_trabajadores, 0) as total_trabajadores,
    COALESCE(ventas_mes_stats.ventas_mes, 0) as ventas_mes,
    sp.denominacion as plan_nombre,
    sp.precio_mensual as plan_precio,
    s.fecha_fin as fecha_vencimiento
  FROM app_dat_tienda t
  
  -- Estadísticas de ventas
  LEFT JOIN (
    SELECT 
      t2.id as id_tienda,
      COUNT(ov.id_operacion) as total_ventas
    FROM app_dat_tienda t2
    LEFT JOIN app_dat_tpv tpv ON tpv.id_tienda = t2.id
    LEFT JOIN app_dat_operacion_venta ov ON ov.id_tpv = tpv.id
    GROUP BY t2.id
  ) ventas_stats ON ventas_stats.id_tienda = t.id
  
  -- Estadísticas de productos
  LEFT JOIN (
    SELECT 
      id_tienda,
      COUNT(id) as total_productos
    FROM app_dat_producto
    GROUP BY id_tienda
  ) productos_stats ON productos_stats.id_tienda = t.id
  
  -- Estadísticas de trabajadores
  LEFT JOIN (
    SELECT 
      id_tienda,
      COUNT(id) as total_trabajadores
    FROM app_dat_trabajadores
    GROUP BY id_tienda
  ) trabajadores_stats ON trabajadores_stats.id_tienda = t.id
  
  -- Ventas del mes
  LEFT JOIN (
    SELECT 
      t3.id as id_tienda,
      SUM(ov.importe_total) as ventas_mes
    FROM app_dat_tienda t3
    LEFT JOIN app_dat_tpv tpv ON tpv.id_tienda = t3.id
    LEFT JOIN app_dat_operacion_venta ov ON ov.id_tpv = tpv.id 
      AND ov.created_at >= fecha_inicio_mes
    GROUP BY t3.id
  ) ventas_mes_stats ON ventas_mes_stats.id_tienda = t.id
  
  -- Suscripción activa
  LEFT JOIN app_suscripciones s ON s.id_tienda = t.id AND s.estado = 1
  LEFT JOIN app_suscripciones_plan sp ON sp.id = s.id_plan
  
  ORDER BY t.denominacion;
END;
$$;

-- 6. Función para obtener estadísticas de ventas del dashboard
CREATE OR REPLACE FUNCTION get_dashboard_ventas_stats()
RETURNS TABLE (
  ventas_totales NUMERIC,
  ventas_mes NUMERIC
) 
LANGUAGE plpgsql
AS $$
DECLARE
  fecha_inicio_mes TIMESTAMP := DATE_TRUNC('month', CURRENT_DATE);
BEGIN
  RETURN QUERY
  SELECT 
    COALESCE(SUM(ov.importe_total), 0) as ventas_totales,
    COALESCE(SUM(CASE WHEN ov.created_at >= fecha_inicio_mes THEN ov.importe_total ELSE 0 END), 0) as ventas_mes
  FROM app_dat_operacion_venta ov;
END;
$$;
