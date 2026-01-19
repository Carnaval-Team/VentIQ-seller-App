-- Function to update a product's supplier
CREATE OR REPLACE FUNCTION public.fn_actualizar_proveedor_producto(
    p_id_producto BIGINT,
    p_id_proveedor INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public.app_dat_producto
    SET id_proveedor = p_id_proveedor
    WHERE id = p_id_producto;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.fn_actualizar_proveedor_producto(BIGINT, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_actualizar_proveedor_producto(BIGINT, INTEGER) TO service_role;
