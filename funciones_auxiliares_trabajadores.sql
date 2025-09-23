-- =====================================================
-- FUNCIONES AUXILIARES PARA TRABAJADORES
-- =====================================================

-- =====================================================
-- FUNCIÓN PARA OBTENER ROLES DISPONIBLES DE UNA TIENDA
-- =====================================================
CREATE OR REPLACE FUNCTION fn_obtener_roles_tienda(
    p_id_tienda bigint
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    resultado jsonb := '[]'::jsonb;
    rol_record record;
BEGIN
    FOR rol_record IN
        SELECT id, denominacion, descripcion, created_at
        FROM seg_roll
        WHERE id_tienda = p_id_tienda
        ORDER BY denominacion
    LOOP
        resultado := resultado || jsonb_build_object(
            'id', rol_record.id,
            'denominacion', rol_record.denominacion,
            'descripcion', rol_record.descripcion,
            'created_at', rol_record.created_at
        );
    END LOOP;
    
    RETURN jsonb_build_object(
        'success', true,
        'message', 'Roles obtenidos correctamente',
        'data', resultado
    );
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Error al obtener roles: ' || SQLERRM,
            'data', '[]'::jsonb
        );
END;
$$;

-- =====================================================
-- FUNCIÓN PARA OBTENER TPVS DISPONIBLES DE UNA TIENDA
-- =====================================================
CREATE OR REPLACE FUNCTION fn_obtener_tpvs_tienda(
    p_id_tienda bigint
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    resultado jsonb := '[]'::jsonb;
    tpv_record record;
BEGIN
    FOR tpv_record IN
        SELECT 
            t.id,
            t.denominacion,
            t.created_at,
            a.denominacion as almacen_denominacion,
            a.id as almacen_id
        FROM app_dat_tpv t
        LEFT JOIN app_dat_almacen a ON t.id_almacen = a.id
        WHERE t.id_tienda = p_id_tienda
        ORDER BY t.denominacion
    LOOP
        resultado := resultado || jsonb_build_object(
            'id', tpv_record.id,
            'denominacion', tpv_record.denominacion,
            'almacen_id', tpv_record.almacen_id,
            'almacen_denominacion', tpv_record.almacen_denominacion,
            'created_at', tpv_record.created_at
        );
    END LOOP;
    
    RETURN jsonb_build_object(
        'success', true,
        'message', 'TPVs obtenidos correctamente',
        'data', resultado
    );
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Error al obtener TPVs: ' || SQLERRM,
            'data', '[]'::jsonb
        );
END;
$$;

-- =====================================================
-- FUNCIÓN PARA OBTENER ALMACENES DISPONIBLES DE UNA TIENDA
-- =====================================================
CREATE OR REPLACE FUNCTION fn_obtener_almacenes_tienda(
    p_id_tienda bigint
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    resultado jsonb := '[]'::jsonb;
    almacen_record record;
BEGIN
    FOR almacen_record IN
        SELECT 
            id,
            denominacion,
            direccion,
            ubicacion,
            created_at
        FROM app_dat_almacen
        WHERE id_tienda = p_id_tienda
        ORDER BY denominacion
    LOOP
        resultado := resultado || jsonb_build_object(
            'id', almacen_record.id,
            'denominacion', almacen_record.denominacion,
            'direccion', almacen_record.direccion,
            'ubicacion', almacen_record.ubicacion,
            'created_at', almacen_record.created_at
        );
    END LOOP;
    
    RETURN jsonb_build_object(
        'success', true,
        'message', 'Almacenes obtenidos correctamente',
        'data', resultado
    );
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Error al obtener almacenes: ' || SQLERRM,
            'data', '[]'::jsonb
        );
END;
$$;

-- =====================================================
-- FUNCIÓN PARA OBTENER DETALLES COMPLETOS DE UN TRABAJADOR
-- =====================================================
CREATE OR REPLACE FUNCTION fn_obtener_detalle_trabajador(
    p_trabajador_id bigint,
    p_id_tienda bigint
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    resultado jsonb := '{}'::jsonb;
    trabajador_record record;
BEGIN
    SELECT 
        t.id as trabajador_id,
        t.nombres,
        t.apellidos,
        t.created_at as fecha_creacion,
        r.denominacion as rol_nombre,
        r.id as rol_id,
        r.descripcion as rol_descripcion,
        -- Datos específicos según el rol
        CASE 
            WHEN g.id IS NOT NULL THEN 'gerente'
            WHEN s.id IS NOT NULL THEN 'supervisor'
            WHEN v.id IS NOT NULL THEN 'vendedor'
            WHEN a.id IS NOT NULL THEN 'almacenero'
            ELSE 'sin_rol'
        END as tipo_rol,
        -- UUID del usuario
        CASE 
            WHEN g.id IS NOT NULL THEN g.uuid
            WHEN s.id IS NOT NULL THEN s.uuid
            WHEN v.id IS NOT NULL THEN v.uuid
            WHEN a.id IS NOT NULL THEN a.uuid
            ELSE NULL
        END as usuario_uuid,
        -- Datos específicos del vendedor
        CASE WHEN v.id IS NOT NULL THEN
            jsonb_build_object(
                'tpv_id', tpv.id,
                'tpv_denominacion', tpv.denominacion,
                'numero_confirmacion', v.numero_confirmacion,
                'almacen_tpv_id', tpv.id_almacen,
                'almacen_tpv_denominacion', alm_tpv.denominacion
            )
        END as datos_vendedor,
        -- Datos específicos del almacenero
        CASE WHEN a.id IS NOT NULL THEN
            jsonb_build_object(
                'almacen_id', alm.id,
                'almacen_denominacion', alm.denominacion,
                'almacen_direccion', alm.direccion,
                'almacen_ubicacion', alm.ubicacion
            )
        END as datos_almacenero
    INTO trabajador_record
    FROM app_dat_trabajadores t
    LEFT JOIN seg_roll r ON t.id_roll = r.id
    LEFT JOIN app_dat_gerente g ON t.id = g.id_trabajador
    LEFT JOIN app_dat_supervisor s ON t.id = s.id_trabajador
    LEFT JOIN app_dat_vendedor v ON t.id = v.id_trabajador
    LEFT JOIN app_dat_almacenero a ON t.id = a.id_trabajador
    LEFT JOIN app_dat_tpv tpv ON v.id_tpv = tpv.id
    LEFT JOIN app_dat_almacen alm ON a.id_almacen = alm.id
    LEFT JOIN app_dat_almacen alm_tpv ON tpv.id_almacen = alm_tpv.id
    WHERE t.id = p_trabajador_id AND t.id_tienda = p_id_tienda;
    
    IF trabajador_record.trabajador_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Trabajador no encontrado o no pertenece a esta tienda'
        );
    END IF;
    
    resultado := jsonb_build_object(
        'trabajador_id', trabajador_record.trabajador_id,
        'nombres', trabajador_record.nombres,
        'apellidos', trabajador_record.apellidos,
        'fecha_creacion', trabajador_record.fecha_creacion,
        'rol_id', trabajador_record.rol_id,
        'rol_nombre', trabajador_record.rol_nombre,
        'rol_descripcion', trabajador_record.rol_descripcion,
        'tipo_rol', trabajador_record.tipo_rol,
        'usuario_uuid', trabajador_record.usuario_uuid,
        'datos_vendedor', COALESCE(trabajador_record.datos_vendedor, '{}'::jsonb),
        'datos_almacenero', COALESCE(trabajador_record.datos_almacenero, '{}'::jsonb)
    );
    
    RETURN jsonb_build_object(
        'success', true,
        'message', 'Detalle del trabajador obtenido correctamente',
        'data', resultado
    );
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Error al obtener detalle del trabajador: ' || SQLERRM,
            'error_code', SQLSTATE
        );
END;
$$;

-- =====================================================
-- FUNCIÓN PARA VERIFICAR PERMISOS DE USUARIO
-- =====================================================
CREATE OR REPLACE FUNCTION fn_verificar_permisos_usuario(
    p_usuario_uuid uuid,
    p_id_tienda bigint
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    es_gerente boolean := false;
    es_supervisor boolean := false;
    es_vendedor boolean := false;
    es_almacenero boolean := false;
    datos_usuario jsonb := '{}'::jsonb;
BEGIN
    -- Verificar si es gerente
    SELECT EXISTS(
        SELECT 1 FROM app_dat_gerente 
        WHERE uuid = p_usuario_uuid AND id_tienda = p_id_tienda
    ) INTO es_gerente;
    
    -- Verificar si es supervisor
    SELECT EXISTS(
        SELECT 1 FROM app_dat_supervisor 
        WHERE uuid = p_usuario_uuid AND id_tienda = p_id_tienda
    ) INTO es_supervisor;
    
    -- Verificar si es vendedor
    SELECT EXISTS(
        SELECT 1 FROM app_dat_vendedor v
        INNER JOIN app_dat_tpv t ON v.id_tpv = t.id
        WHERE v.uuid = p_usuario_uuid AND t.id_tienda = p_id_tienda
    ) INTO es_vendedor;
    
    -- Verificar si es almacenero
    SELECT EXISTS(
        SELECT 1 FROM app_dat_almacenero a
        INNER JOIN app_dat_almacen al ON a.id_almacen = al.id
        WHERE a.uuid = p_usuario_uuid AND al.id_tienda = p_id_tienda
    ) INTO es_almacenero;
    
    datos_usuario := jsonb_build_object(
        'es_gerente', es_gerente,
        'es_supervisor', es_supervisor,
        'es_vendedor', es_vendedor,
        'es_almacenero', es_almacenero,
        'puede_gestionar_trabajadores', (es_gerente OR es_supervisor),
        'pertenece_a_tienda', (es_gerente OR es_supervisor OR es_vendedor OR es_almacenero)
    );
    
    RETURN jsonb_build_object(
        'success', true,
        'message', 'Permisos verificados correctamente',
        'data', datos_usuario
    );
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Error al verificar permisos: ' || SQLERRM,
            'error_code', SQLSTATE
        );
END;
$$;

-- =====================================================
-- FUNCIÓN PARA OBTENER ESTADÍSTICAS DE TRABAJADORES
-- =====================================================
CREATE OR REPLACE FUNCTION fn_estadisticas_trabajadores_tienda(
    p_id_tienda bigint
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    total_trabajadores integer := 0;
    total_gerentes integer := 0;
    total_supervisores integer := 0;
    total_vendedores integer := 0;
    total_almaceneros integer := 0;
    total_sin_rol integer := 0;
    resultado jsonb := '{}'::jsonb;
BEGIN
    -- Contar total de trabajadores
    SELECT COUNT(*) INTO total_trabajadores
    FROM app_dat_trabajadores
    WHERE id_tienda = p_id_tienda;
    
    -- Contar gerentes
    SELECT COUNT(*) INTO total_gerentes
    FROM app_dat_trabajadores t
    INNER JOIN app_dat_gerente g ON t.id = g.id_trabajador
    WHERE t.id_tienda = p_id_tienda;
    
    -- Contar supervisores
    SELECT COUNT(*) INTO total_supervisores
    FROM app_dat_trabajadores t
    INNER JOIN app_dat_supervisor s ON t.id = s.id_trabajador
    WHERE t.id_tienda = p_id_tienda;
    
    -- Contar vendedores
    SELECT COUNT(*) INTO total_vendedores
    FROM app_dat_trabajadores t
    INNER JOIN app_dat_vendedor v ON t.id = v.id_trabajador
    WHERE t.id_tienda = p_id_tienda;
    
    -- Contar almaceneros
    SELECT COUNT(*) INTO total_almaceneros
    FROM app_dat_trabajadores t
    INNER JOIN app_dat_almacenero a ON t.id = a.id_trabajador
    WHERE t.id_tienda = p_id_tienda;
    
    -- Calcular trabajadores sin rol específico
    total_sin_rol := total_trabajadores - (total_gerentes + total_supervisores + total_vendedores + total_almaceneros);
    
    resultado := jsonb_build_object(
        'total_trabajadores', total_trabajadores,
        'por_rol', jsonb_build_object(
            'gerentes', total_gerentes,
            'supervisores', total_supervisores,
            'vendedores', total_vendedores,
            'almaceneros', total_almaceneros,
            'sin_rol', total_sin_rol
        ),
        'porcentajes', jsonb_build_object(
            'gerentes', CASE WHEN total_trabajadores > 0 THEN ROUND((total_gerentes::decimal / total_trabajadores) * 100, 2) ELSE 0 END,
            'supervisores', CASE WHEN total_trabajadores > 0 THEN ROUND((total_supervisores::decimal / total_trabajadores) * 100, 2) ELSE 0 END,
            'vendedores', CASE WHEN total_trabajadores > 0 THEN ROUND((total_vendedores::decimal / total_trabajadores) * 100, 2) ELSE 0 END,
            'almaceneros', CASE WHEN total_trabajadores > 0 THEN ROUND((total_almaceneros::decimal / total_trabajadores) * 100, 2) ELSE 0 END
        )
    );
    
    RETURN jsonb_build_object(
        'success', true,
        'message', 'Estadísticas obtenidas correctamente',
        'data', resultado
    );
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Error al obtener estadísticas: ' || SQLERRM,
            'error_code', SQLSTATE
        );
END;
$$;

-- =====================================================
-- EJEMPLOS DE USO DE LAS FUNCIONES AUXILIARES
-- =====================================================

/*
-- Obtener roles disponibles de una tienda
SELECT fn_obtener_roles_tienda(1);

-- Obtener TPVs disponibles de una tienda
SELECT fn_obtener_tpvs_tienda(1);

-- Obtener almacenes disponibles de una tienda
SELECT fn_obtener_almacenes_tienda(1);

-- Obtener detalle completo de un trabajador
SELECT fn_obtener_detalle_trabajador(1, 1);

-- Verificar permisos de un usuario
SELECT fn_verificar_permisos_usuario('uuid-del-usuario'::uuid, 1);

-- Obtener estadísticas de trabajadores de una tienda
SELECT fn_estadisticas_trabajadores_tienda(1);
*/
