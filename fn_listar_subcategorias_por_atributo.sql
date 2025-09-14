CREATE OR REPLACE FUNCTION fn_listar_subcategorias_por_atributo(
    p_id_atributo BIGINT
)
RETURNS TABLE (
    id_subcategoria BIGINT,
    denominacion_subcategoria VARCHAR,
    id_categoria BIGINT,
    denominacion_categoria VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT
        sc.id as id_subcategoria,
        sc.denominacion as denominacion_subcategoria,
        c.id as id_categoria,
        c.denominacion as denominacion_categoria
    FROM app_dat_variantes v
    INNER JOIN app_dat_subcategorias sc ON v.id_sub_categoria = sc.id
    INNER JOIN app_dat_categoria c ON sc.id_categoria = c.id
    WHERE v.id_atributo = p_id_atributo
    ORDER BY c.denominacion, sc.denominacion;
END;
$$;
