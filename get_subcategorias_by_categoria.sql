-- Función para obtener subcategorías y total de productos por subcategoría
-- Parámetro: p_id_categoria (ID de la categoría padre)
-- Retorna: Lista de subcategorías con su información y total de productos

CREATE OR REPLACE FUNCTION get_subcategorias_by_categoria(p_id_categoria bigint)
RETURNS TABLE (
    id bigint,
    denominacion character varying,
    sku_codigo character varying,
    created_at timestamp with time zone,
    total_productos bigint
) 
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        s.id,
        s.denominacion,
        s.sku_codigo,
        s.created_at,
        COALESCE(COUNT(ps.id_producto), 0) as total_productos
    FROM 
        app_dat_subcategorias s
    LEFT JOIN 
        app_dat_productos_subcategorias ps ON s.id = ps.id_sub_categoria
    LEFT JOIN 
        app_dat_producto p ON ps.id_producto = p.id
    WHERE 
        s.idcategoria = p_id_categoria
    GROUP BY 
        s.id, s.denominacion, s.sku_codigo, s.created_at
    ORDER BY 
        s.denominacion ASC;
END;
$$;

-- Ejemplo de uso:
-- SELECT * FROM get_subcategorias_by_categoria(1);

-- Comentarios sobre la función:
-- 1. Recibe como parámetro el ID de la categoría padre
-- 2. Hace JOIN con la tabla de productos_subcategorias para contar productos
-- 3. Usa LEFT JOIN para incluir subcategorías sin productos (total_productos = 0)
-- 4. Agrupa por los campos de subcategoría para evitar duplicados
-- 5. Ordena alfabéticamente por denominación
-- 6. Retorna el conteo de productos por subcategoría usando COUNT()
