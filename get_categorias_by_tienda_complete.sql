-- Función para obtener categorías completas filtradas por tienda
-- Retorna todos los datos de la categoría para las categorías asignadas a una tienda específica

CREATE OR REPLACE FUNCTION get_categorias_by_tienda_complete(
    p_id_tienda BIGINT
)
RETURNS TABLE (
    id BIGINT,
    denominacion CHARACTER VARYING,
    descripcion CHARACTER VARYING,
    sku_codigo TEXT,
    image TEXT,
    created_at TIMESTAMP WITH TIME ZONE,
    categoria_tienda_id BIGINT,
    categoria_tienda_created_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.id,
        c.denominacion,
        c.descripcion,
        c.sku_codigo,
        c.image,
        c.created_at,
        ct.id as categoria_tienda_id,
        ct.created_at as categoria_tienda_created_at
    FROM 
        app_dat_categoria c
    INNER JOIN 
        app_dat_categoria_tienda ct ON c.id = ct.id_categoria
    WHERE 
        ct.id_tienda = p_id_tienda
    ORDER BY 
        c.denominacion ASC;
        
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error al obtener categorías para la tienda %: %', p_id_tienda, SQLERRM;
END;
$$;

-- Ejemplo de uso:
-- SELECT * FROM get_categorias_by_tienda_complete(1);

-- Comentarios sobre la función:
-- 1. Retorna todos los campos de la tabla app_dat_categoria
-- 2. Incluye información adicional de la relación categoria_tienda
-- 3. Filtra por id_tienda específico
-- 4. Ordena por denominación alfabéticamente
-- 5. Incluye manejo de errores
-- 6. Usa SECURITY DEFINER para ejecutar con permisos del propietario de la función
