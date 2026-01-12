-- Función RPC para obtener todos los gerentes con datos de trabajador y tienda
CREATE OR REPLACE FUNCTION get_gerentes_completo()
RETURNS TABLE (
  id_gerente BIGINT,
  uuid UUID,
  id_tienda BIGINT,
  id_trabajador BIGINT,
  nombres VARCHAR,
  apellidos VARCHAR,
  tienda_denominacion VARCHAR,
  created_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    g.id::BIGINT,
    g.uuid,
    g.id_tienda::BIGINT,
    g.id_trabajador::BIGINT,
    COALESCE(t.nombres, 'Sin asignar') AS nombres,
    COALESCE(t.apellidos, '') AS apellidos,
    COALESCE(ti.denominacion, 'Sin tienda') AS tienda_denominacion,
    g.created_at
  FROM app_dat_gerente g
  LEFT JOIN app_dat_trabajadores t ON g.id_trabajador = t.id
  LEFT JOIN app_dat_tienda ti ON g.id_tienda = ti.id
  ORDER BY g.created_at DESC;
END;
$$ LANGUAGE plpgsql;
