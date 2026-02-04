-- =====================================================
-- NUEVAS FUNCIONES RPC PARA ALMACENERO
-- Estas son funciones NUEVAS que no reemplazan las existentes
-- =====================================================

-- =====================================================
-- RPC: fn_insertar_trabajador_con_almacen
-- Descripción: Crea trabajador y asigna almacén en una sola operación
-- =====================================================

CREATE OR REPLACE FUNCTION public.fn_insertar_trabajador_con_almacen(
    p_id_tienda INTEGER,
    p_nombres VARCHAR,
    p_apellidos VARCHAR,
    p_usuario_uuid UUID,
    p_almacen_id INTEGER,
    p_salario_horas NUMERIC DEFAULT 0.0
)
RETURNS JSON
LANGUAGE plpgsql
AS $$
DECLARE
    v_trabajador_id INTEGER;
    v_almacenero_id INTEGER;
    v_result JSON;
BEGIN
    -- Validar que el almacén existe y pertenece a la tienda
    IF NOT EXISTS (
        SELECT 1 FROM public.app_dat_almacen 
        WHERE id = p_almacen_id AND id_tienda = p_id_tienda
    ) THEN
        RETURN json_build_object(
            'success', false,
            'message', 'El almacén no existe o no pertenece a esta tienda'
        );
    END IF;

    -- Insertar trabajador base
    INSERT INTO public.app_dat_trabajadores (
        id_tienda, 
        nombres, 
        apellidos, 
        usuario_uuid, 
        salario_horas,
        estado
    )
    VALUES (
        p_id_tienda, 
        p_nombres, 
        p_apellidos, 
        p_usuario_uuid, 
        p_salario_horas,
        1
    )
    RETURNING id INTO v_trabajador_id;

    -- Crear registro de almacenero
    INSERT INTO public.app_dat_almacenero (
        id_trabajador, 
        id_almacen, 
        id_tienda, 
        estado
    )
    VALUES (
        v_trabajador_id, 
        p_almacen_id, 
        p_id_tienda, 
        1
    )
    RETURNING id INTO v_almacenero_id;

    RETURN json_build_object(
        'success', true,
        'message', 'Almacenero creado exitosamente',
        'trabajador_id', v_trabajador_id,
        'almacenero_id', v_almacenero_id
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Error al crear almacenero: ' || SQLERRM
        );
END;
$$;

-- =====================================================
-- RPC: fn_agregar_rol_almacenero
-- Descripción: Agrega rol de almacenero a trabajador existente
-- =====================================================

CREATE OR REPLACE FUNCTION public.fn_agregar_rol_almacenero(
    p_trabajador_id INTEGER,
    p_almacen_id INTEGER
)
RETURNS JSON
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_tienda INTEGER;
    v_almacenero_id INTEGER;
BEGIN
    -- Obtener id_tienda del trabajador
    SELECT id_tienda INTO v_id_tienda
    FROM public.app_dat_trabajadores
    WHERE id = p_trabajador_id AND estado = 1;

    IF v_id_tienda IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Trabajador no encontrado o inactivo'
        );
    END IF;

    -- Validar que el almacén existe y pertenece a la tienda
    IF NOT EXISTS (
        SELECT 1 FROM public.app_dat_almacen 
        WHERE id = p_almacen_id AND id_tienda = v_id_tienda
    ) THEN
        RETURN json_build_object(
            'success', false,
            'message', 'El almacén no existe o no pertenece a esta tienda'
        );
    END IF;

    -- Verificar si ya es almacenero
    IF EXISTS (
        SELECT 1 FROM public.app_dat_almacenero 
        WHERE id_trabajador = p_trabajador_id 
        AND id_tienda = v_id_tienda 
        AND estado = 1
    ) THEN
        RETURN json_build_object(
            'success', false,
            'message', 'El trabajador ya tiene rol de almacenero activo'
        );
    END IF;

    -- Crear o reactivar registro de almacenero
    INSERT INTO public.app_dat_almacenero (
        id_trabajador, 
        id_almacen, 
        id_tienda, 
        estado
    )
    VALUES (
        p_trabajador_id, 
        p_almacen_id, 
        v_id_tienda, 
        1
    )
    ON CONFLICT (id_trabajador, id_tienda) 
    DO UPDATE SET 
        id_almacen = p_almacen_id,
        estado = 1,
        updated_at = NOW()
    RETURNING id INTO v_almacenero_id;

    RETURN json_build_object(
        'success', true,
        'message', 'Rol de almacenero agregado exitosamente',
        'almacenero_id', v_almacenero_id
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Error al agregar rol de almacenero: ' || SQLERRM
        );
END;
$$;

-- =====================================================
-- RPC: fn_actualizar_almacen_almacenero
-- Descripción: Actualiza el almacén asignado a un almacenero
-- =====================================================

CREATE OR REPLACE FUNCTION public.fn_actualizar_almacen_almacenero(
    p_trabajador_id INTEGER,
    p_almacen_id INTEGER
)
RETURNS JSON
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_tienda INTEGER;
    v_rows_affected INTEGER;
BEGIN
    -- Obtener id_tienda del trabajador
    SELECT id_tienda INTO v_id_tienda
    FROM public.app_dat_trabajadores
    WHERE id = p_trabajador_id AND estado = 1;

    IF v_id_tienda IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Trabajador no encontrado o inactivo'
        );
    END IF;

    -- Validar que el almacén existe y pertenece a la tienda
    IF NOT EXISTS (
        SELECT 1 FROM public.app_dat_almacen 
        WHERE id = p_almacen_id AND id_tienda = v_id_tienda
    ) THEN
        RETURN json_build_object(
            'success', false,
            'message', 'El almacén no existe o no pertenece a esta tienda'
        );
    END IF;

    -- Actualizar almacén
    UPDATE public.app_dat_almacenero
    SET 
        id_almacen = p_almacen_id,
        updated_at = NOW()
    WHERE id_trabajador = p_trabajador_id 
    AND id_tienda = v_id_tienda 
    AND estado = 1;

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

    IF v_rows_affected = 0 THEN
        RETURN json_build_object(
            'success', false,
            'message', 'El trabajador no tiene rol de almacenero activo'
        );
    END IF;

    RETURN json_build_object(
        'success', true,
        'message', 'Almacén actualizado exitosamente'
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Error al actualizar almacén: ' || SQLERRM
        );
END;
$$;

-- =====================================================
-- RPC: fn_listar_trabajadores_con_roles
-- Descripción: Lista trabajadores con todos sus roles (incluyendo almacenero)
-- =====================================================

CREATE OR REPLACE FUNCTION public.fn_listar_trabajadores_con_roles(
    p_id_tienda INTEGER,
    p_usuario_solicitante UUID
)
RETURNS JSON
LANGUAGE plpgsql
AS $$
DECLARE
    v_result JSON;
BEGIN
    -- Construir resultado con todos los trabajadores y sus roles
    SELECT json_build_object(
        'success', true,
        'data', COALESCE(json_agg(trabajador_data), '[]'::json)
    ) INTO v_result
    FROM (
        SELECT 
            t.id as trabajador_id,
            t.nombres,
            t.apellidos,
            t.usuario_uuid,
            t.salario_horas,
            t.maneja_apertura_control,
            t.created_at as fecha_creacion,
            u.email,
            -- Detectar roles
            (t.usuario_uuid IS NOT NULL) as tiene_usuario,
            (g.id IS NOT NULL) as es_gerente,
            (s.id IS NOT NULL) as es_supervisor,
            (v.id IS NOT NULL) as es_vendedor,
            (a.id IS NOT NULL) as es_almacenero,
            -- Datos específicos según rol
            CASE 
                WHEN a.id IS NOT NULL THEN json_build_object(
                    'almacen_id', alm.id,
                    'almacen_denominacion', alm.denominacion,
                    'almacen_direccion', alm.direccion,
                    'almacen_ubicacion', alm.ubicacion
                )
                WHEN v.id IS NOT NULL THEN json_build_object(
                    'tpv_id', tpv.id,
                    'tpv_denominacion', tpv.denominacion,
                    'numero_confirmacion', v.numero_confirmacion
                )
                ELSE '{}'::json
            END as datos_especificos,
            -- Rol principal (para compatibilidad)
            CASE 
                WHEN g.id IS NOT NULL THEN 1
                WHEN s.id IS NOT NULL THEN 2
                WHEN v.id IS NOT NULL THEN 3
                WHEN a.id IS NOT NULL THEN 4
                ELSE 0
            END as rol_id,
            CASE 
                WHEN g.id IS NOT NULL THEN 'Gerente'
                WHEN s.id IS NOT NULL THEN 'Supervisor'
                WHEN v.id IS NOT NULL THEN 'Vendedor'
                WHEN a.id IS NOT NULL THEN 'Almacenero'
                ELSE 'Sin Rol'
            END as rol_nombre,
            CASE 
                WHEN g.id IS NOT NULL THEN 'gerente'
                WHEN s.id IS NOT NULL THEN 'supervisor'
                WHEN v.id IS NOT NULL THEN 'vendedor'
                WHEN a.id IS NOT NULL THEN 'almacenero'
                ELSE 'none'
            END as tipo_rol
        FROM public.app_dat_trabajadores t
        LEFT JOIN auth.users u ON t.usuario_uuid = u.id
        LEFT JOIN public.app_dat_gerente g ON t.id = g.id_trabajador AND g.id_tienda = p_id_tienda AND g.estado = 1
        LEFT JOIN public.app_dat_supervisor s ON t.id = s.id_trabajador AND s.id_tienda = p_id_tienda AND s.estado = 1
        LEFT JOIN public.app_dat_vendedor v ON t.id = v.id_trabajador AND v.id_tienda = p_id_tienda AND v.estado = 1
        LEFT JOIN public.app_dat_almacenero a ON t.id = a.id_trabajador AND a.id_tienda = p_id_tienda AND a.estado = 1
        LEFT JOIN public.app_dat_tpv tpv ON v.id_tpv = tpv.id
        LEFT JOIN public.app_dat_almacen alm ON a.id_almacen = alm.id
        WHERE t.id_tienda = p_id_tienda 
        AND t.estado = 1
        ORDER BY t.created_at DESC
    ) trabajador_data;

    RETURN v_result;

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Error al listar trabajadores: ' || SQLERRM
        );
END;
$$;

-- =====================================================
-- RPC: fn_obtener_estadisticas_trabajadores_v2
-- Descripción: Obtiene estadísticas de trabajadores incluyendo almaceneros
-- =====================================================

CREATE OR REPLACE FUNCTION public.fn_obtener_estadisticas_trabajadores_v2(
    p_id_tienda INTEGER
)
RETURNS JSON
LANGUAGE plpgsql
AS $$
DECLARE
    v_result JSON;
BEGIN
    SELECT json_build_object(
        'success', true,
        'data', json_build_object(
            'total_trabajadores', (
                SELECT COUNT(DISTINCT id) 
                FROM public.app_dat_trabajadores 
                WHERE id_tienda = p_id_tienda AND estado = 1
            ),
            'total_gerentes', (
                SELECT COUNT(*) 
                FROM public.app_dat_gerente 
                WHERE id_tienda = p_id_tienda AND estado = 1
            ),
            'total_supervisores', (
                SELECT COUNT(*) 
                FROM public.app_dat_supervisor 
                WHERE id_tienda = p_id_tienda AND estado = 1
            ),
            'total_vendedores', (
                SELECT COUNT(*) 
                FROM public.app_dat_vendedor 
                WHERE id_tienda = p_id_tienda AND estado = 1
            ),
            'total_almaceneros', (
                SELECT COUNT(*) 
                FROM public.app_dat_almacenero 
                WHERE id_tienda = p_id_tienda AND estado = 1
            ),
            'con_usuario', (
                SELECT COUNT(*) 
                FROM public.app_dat_trabajadores 
                WHERE id_tienda = p_id_tienda 
                AND estado = 1 
                AND usuario_uuid IS NOT NULL
            ),
            'sin_usuario', (
                SELECT COUNT(*) 
                FROM public.app_dat_trabajadores 
                WHERE id_tienda = p_id_tienda 
                AND estado = 1 
                AND usuario_uuid IS NULL
            )
        )
    ) INTO v_result;

    RETURN v_result;

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Error al obtener estadísticas: ' || SQLERRM
        );
END;
$$;

-- =====================================================
-- COMENTARIOS Y NOTAS
-- =====================================================

COMMENT ON FUNCTION fn_insertar_trabajador_con_almacen IS 'Crea un nuevo trabajador con rol de almacenero en una sola operación';
COMMENT ON FUNCTION fn_agregar_rol_almacenero IS 'Agrega el rol de almacenero a un trabajador existente';
COMMENT ON FUNCTION fn_actualizar_almacen_almacenero IS 'Actualiza el almacén asignado a un almacenero';
COMMENT ON FUNCTION fn_listar_trabajadores_con_roles IS 'Lista todos los trabajadores con sus roles múltiples incluyendo almacenero';
COMMENT ON FUNCTION fn_obtener_estadisticas_trabajadores_v2 IS 'Obtiene estadísticas de trabajadores incluyendo contador de almaceneros';
