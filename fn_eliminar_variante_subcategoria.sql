CREATE OR REPLACE FUNCTION fn_eliminar_variante_subcategoria(
    p_id_atributo BIGINT,
    p_id_subcategoria BIGINT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_count INTEGER := 0;
    v_variant_exists BOOLEAN := FALSE;
    v_relation_exists BOOLEAN := FALSE;
    v_variant_id BIGINT;
BEGIN
    -- Set search path for security
    SET search_path = public;
    
    -- Find the variant ID that matches the attribute and subcategory
    SELECT v.id INTO v_variant_id
    FROM app_dat_variantes v
    WHERE v.id_atributo = p_id_atributo AND v.id_sub_categoria = p_id_subcategoria;
    
    -- Check if the variant-subcategory relationship exists
    IF v_variant_id IS NULL THEN
        RAISE EXCEPTION 'No existe relación entre el atributo % y la subcategoría %', p_id_atributo, p_id_subcategoria;
    END IF;
    
    -- Check if any products are using this variant-subcategory combination
    -- Check inventory operations
    SELECT COUNT(*) INTO v_count
    FROM app_dat_inventario_productos ip
    WHERE ip.id_variante = v_variant_id;
    
    IF v_count > 0 THEN
        RAISE EXCEPTION 'No se puede eliminar la relación porque % registro(s) de inventario están usando esta variante', v_count;
    END IF;
    
    -- Check reception operations
    SELECT COUNT(*) INTO v_count
    FROM app_dat_recepcion_productos rp
    WHERE rp.id_variante = v_variant_id;
    
    IF v_count > 0 THEN
        RAISE EXCEPTION 'No se puede eliminar la relación porque % operación(es) de recepción están usando esta variante', v_count;
    END IF;
    
    -- Check extraction operations
    SELECT COUNT(*) INTO v_count
    FROM app_dat_extraccion_productos ep
    WHERE ep.id_variante = v_variant_id;
    
    IF v_count > 0 THEN
        RAISE EXCEPTION 'No se puede eliminar la relación porque % operación(es) de extracción están usando esta variante', v_count;
    END IF;
    
    -- Check control operations
    SELECT COUNT(*) INTO v_count
    FROM app_dat_control_productos cp
    WHERE cp.id_variante = v_variant_id;
    
    IF v_count > 0 THEN
        RAISE EXCEPTION 'No se puede eliminar la relación porque % operación(es) de control están usando esta variante', v_count;
    END IF;
    
    -- Check if variant is used in any products directly
    SELECT COUNT(*) INTO v_count
    FROM app_dat_producto p
    WHERE p.id IN (
        SELECT DISTINCT ip.id_producto 
        FROM app_dat_inventario_productos ip 
        WHERE ip.id_variante = v_variant_id
        UNION
        SELECT DISTINCT rp.id_producto 
        FROM app_dat_recepcion_productos rp 
        WHERE rp.id_variante = v_variant_id
        UNION
        SELECT DISTINCT ep.id_producto 
        FROM app_dat_extraccion_productos ep 
        WHERE ep.id_variante = v_variant_id
        UNION
        SELECT DISTINCT cp.id_producto 
        FROM app_dat_control_productos cp 
        WHERE cp.id_variante = v_variant_id
    );
    
    IF v_count > 0 THEN
        RAISE EXCEPTION 'No se puede eliminar la relación porque la variante está siendo usada por % producto(s)', v_count;
    END IF;
    
    -- If we reach here, it's safe to delete the entire variant relationship
    -- Delete the variant row completely
    DELETE FROM app_dat_variantes 
    WHERE id = v_variant_id;
    
    -- Log the operation
    RAISE NOTICE 'Relación eliminada exitosamente: atributo % ya no está asociado con subcategoría %', p_id_atributo, p_id_subcategoria;
    
    RETURN TRUE;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error al eliminar relación atributo-subcategoría: %', SQLERRM;
        RETURN FALSE;
END;
$$;
