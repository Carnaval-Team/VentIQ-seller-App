CREATE OR REPLACE FUNCTION public.fn_insertar_promocion(
    p_uuid_usuario uuid, 
    p_id_campana bigint, 
    p_id_tienda bigint, 
    p_id_tipo_promocion smallint, 
    p_codigo_promocion character varying, 
    p_nombre character varying, 
    p_descripcion text, 
    p_valor_descuento numeric, 
    p_fecha_inicio timestamp with time zone, 
    p_fecha_fin timestamp with time zone, 
    p_min_compra numeric DEFAULT NULL::numeric, 
    p_limite_usos integer DEFAULT NULL::integer, 
    p_aplica_todo boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
    nuevo_id BIGINT;
    v_tiene_permiso BOOLEAN;
    v_campana_tienda BIGINT;
    v_tipo_valido BOOLEAN;
BEGIN
    SET search_path = public;

    -- Validar autenticación
    IF p_uuid_usuario IS NULL OR p_uuid_usuario != auth.uid() THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Usuario no autenticado o no coincide'
        );
    END IF;

    -- Validar permisos del usuario
    SELECT EXISTS (
        SELECT 1 FROM app_dat_gerente WHERE uuid = p_uuid_usuario AND id_tienda = p_id_tienda
        UNION
        SELECT 1 FROM app_dat_supervisor WHERE uuid = p_uuid_usuario AND id_tienda = p_id_tienda
    ) INTO v_tiene_permiso;

    IF NOT v_tiene_permiso THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'No tiene permisos para crear promociones en esta tienda'
        );
    END IF;

    -- Validar que la campaña pertenezca a la tienda
    IF p_id_campana IS NOT NULL THEN
        SELECT id_tienda INTO v_campana_tienda 
        FROM app_mkt_campanas 
        WHERE id = p_id_campana;

        IF NOT FOUND OR v_campana_tienda != p_id_tienda THEN
            RETURN jsonb_build_object(
                'success', false,
                'message', 'La campaña no existe o no pertenece a esta tienda'
            );
        END IF;
    END IF;

    -- Validar fechas (modificado para manejar p_fecha_fin NULL)
    IF p_fecha_fin IS NOT NULL AND p_fecha_fin <= p_fecha_inicio THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'La fecha de fin debe ser posterior a la fecha de inicio'
        );
    END IF;

    -- Validar tipo de promoción
    SELECT EXISTS (
        SELECT 1 FROM app_mkt_tipo_promocion WHERE id = p_id_tipo_promocion
    ) INTO v_tipo_valido;

    IF NOT v_tipo_valido THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Tipo de promoción no válido'
        );
    END IF;

    -- Validar valor de descuento para tipos que lo requieren
    IF p_id_tipo_promocion IN (1, 2) AND p_valor_descuento IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Debe especificar un valor de descuento para este tipo de promoción'
        );
    END IF;

    -- Validar código único por tienda
    IF EXISTS (
        SELECT 1 FROM app_mkt_promociones 
        WHERE codigo_promocion = p_codigo_promocion 
          AND id_tienda = p_id_tienda
    ) THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'El código de promoción ya existe en esta tienda'
        );
    END IF;

    -- Insertar promoción (removidas las columnas de medio de pago)
    INSERT INTO app_mkt_promociones (
        id_campana,
        id_tienda,
        id_tipo_promocion,
        codigo_promocion,
        nombre,
        descripcion,
        valor_descuento,
        fecha_inicio,
        fecha_fin,
        min_compra,
        limite_usos,
        aplica_todo,
        estado
    )
    VALUES (
        p_id_campana,
        p_id_tienda,
        p_id_tipo_promocion,
        p_codigo_promocion,
        p_nombre,
        p_descripcion,
        p_valor_descuento,
        p_fecha_inicio,
        p_fecha_fin,
        p_min_compra,
        p_limite_usos,
        p_aplica_todo,
        true
    )
    RETURNING id INTO nuevo_id;

    RETURN jsonb_build_object(
        'success', true,
        'id', nuevo_id,
        'message', 'Promoción creada exitosamente'
    );

EXCEPTION
    WHEN others THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Error inesperado: ' || SQLERRM
        );
END;
$function$;
