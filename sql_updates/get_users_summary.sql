-- Función para obtener los totales por categoría
CREATE OR REPLACE FUNCTION get_users_count_summary()
RETURNS TABLE (
    total_usuarios bigint,
    total_inventtia bigint,
    total_carnaval bigint,
    total_catalogo bigint
) AS $$
BEGIN
    RETURN QUERY
    WITH user_categories AS (
        SELECT 
            u.id,
            CASE 
                WHEN EXISTS (SELECT 1 FROM public.app_dat_trabajadores t WHERE t.uuid = u.id) THEN 'Inventtia'
                WHEN EXISTS (SELECT 1 FROM carnavalapp.Usuarios c WHERE c.uuid = u.id) THEN 'Carnaval'
                ELSE 'Catalogo'
            END as category
        FROM auth.users u
    )
    SELECT 
        count(*),
        count(*) FILTER (WHERE category = 'Inventtia'),
        count(*) FILTER (WHERE category = 'Carnaval'),
        count(*) FILTER (WHERE category = 'Catalogo')
    FROM user_categories;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Función para obtener usuarios paginados, filtrados y buscables
CREATE OR REPLACE FUNCTION get_paginated_users_summary(
    p_limit int,
    p_offset int,
    p_search text DEFAULT '',
    p_category text DEFAULT 'todos'
)
RETURNS TABLE (
    id uuid,
    email text,
    name text,
    category text,
    created_at timestamp with time zone,
    last_sign_in_at timestamp with time zone,
    activo boolean,
    total_count bigint
) AS $$
BEGIN
    RETURN QUERY
    WITH base_users AS (
        SELECT 
            u.id,
            u.email::text,
            COALESCE(
                (SELECT t.nombres || ' ' || t.apellidos FROM public.app_dat_trabajadores t WHERE t.uuid = u.id LIMIT 1),
                (SELECT c.name FROM carnavalapp.Usuarios c WHERE c.uuid = u.id LIMIT 1),
                u.raw_user_meta_data->>'full_name',
                'Usuario'
            ) as name,
            CASE 
                WHEN EXISTS (SELECT 1 FROM public.app_dat_trabajadores t WHERE t.uuid = u.id) THEN 'Inventtia'
                WHEN EXISTS (SELECT 1 FROM carnavalapp.Usuarios c WHERE c.uuid = u.id) THEN 'Carnaval'
                ELSE 'Catalogo'
            END as category,
            u.created_at,
            u.last_sign_in_at,
            u.deleted_at IS NULL as activo
        FROM auth.users u
    ),
    filtered_users AS (
        SELECT * FROM base_users
        WHERE (p_search = '' OR name ILIKE '%' || p_search || '%' OR email ILIKE '%' || p_search || '%')
        AND (p_category = 'todos' OR category = p_category)
    )
    SELECT *, count(*) OVER() as total_count
    FROM filtered_users
    ORDER BY created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
