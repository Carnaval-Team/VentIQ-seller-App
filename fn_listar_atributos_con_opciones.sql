CREATE OR REPLACE FUNCTION fn_listar_atributos_con_opciones(
    p_id_tienda BIGINT DEFAULT NULL
)
RETURNS TABLE (
    id BIGINT,
    denominacion VARCHAR,
    label VARCHAR,
    descripcion VARCHAR,
    created_at TIMESTAMP WITH TIME ZONE,
    opciones JSON
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        a.id,
        a.denominacion,
        a.label,
        a.descripcion,
        a.created_at,
        COALESCE(
            (
                SELECT json_agg(
                    json_build_object(
                        'id', ao.id,
                        'valor', ao.valor,
                        'sku_codigo', ao.sku_codigo
                    )
                )
                FROM app_dat_atributo_opcion ao
                WHERE ao.id_atributo = a.id
            ),
            '[]'::json
        ) as opciones
    FROM app_dat_atributos a
    ORDER BY a.denominacion ASC;
END;
$$;
