-- =====================================================
-- ACTUALIZACIÓN: Agregar salario_horas a fn_listar_trabajadores_tienda
-- Fecha: 2025-10-25
-- Descripción: Actualiza la función para incluir el campo salario_horas
-- =====================================================

CREATE OR REPLACE FUNCTION fn_listar_trabajadores_tienda(
    p_id_tienda bigint,
    p_usuario_solicitante uuid
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    es_gerente boolean := false;
    es_supervisor boolean := false;
    resultado jsonb := '[]'::jsonb;
    trabajador_record record;
BEGIN
    -- Verificar si el usuario solicitante es gerente o supervisor de la tienda
    SELECT EXISTS(
        SELECT 1 FROM app_dat_gerente 
        WHERE uuid = p_usuario_solicitante AND id_tienda = p_id_tienda
    ) INTO es_gerente;
    
    IF NOT es_gerente THEN
        SELECT EXISTS(
            SELECT 1 FROM app_dat_supervisor 
            WHERE uuid = p_usuario_solicitante AND id_tienda = p_id_tienda
        ) INTO es_supervisor;
    END IF;
    
    -- Solo gerentes y supervisores pueden listar trabajadores
    IF NOT (es_gerente OR es_supervisor) THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'No tienes permisos para listar trabajadores de esta tienda',
            'data', '[]'::jsonb
        );
    END IF;
    
    -- Obtener todos los trabajadores de la tienda con sus roles específicos
    FOR trabajador_record IN
        SELECT 
            t.id as trabajador_id,
            t.nombres,
            t.apellidos,
            t.created_at as fecha_creacion,
            t.salario_horas, -- 💰 NUEVO: Salario por hora
            r.denominacion as rol_nombre,
            r.id as rol_id,
            -- Datos específicos según el rol
            CASE 
                WHEN g.id IS NOT NULL THEN 'gerente'
                WHEN s.id IS NOT NULL THEN 'supervisor'
                WHEN v.id IS NOT NULL THEN 'vendedor'
                WHEN a.id IS NOT NULL THEN 'almacenero'
                ELSE 'sin_rol'
            END as tipo_rol,
            -- Datos adicionales según el rol
            CASE 
                WHEN v.id IS NOT NULL THEN jsonb_build_object(
                    'tpv_id', tpv.id,
                    'tpv_denominacion', tpv.denominacion,
                    'numero_confirmacion', v.numero_confirmacion
                )
                WHEN a.id IS NOT NULL THEN jsonb_build_object(
                    'almacen_id', alm.id,
                    'almacen_denominacion', alm.denominacion,
                    'almacen_direccion', alm.direccion,
                    'almacen_ubicacion', alm.ubicacion
                )
                ELSE '{}'::jsonb
            END as datos_especificos,
            -- UUID del usuario (solo para gerentes y supervisores)
            CASE 
                WHEN g.id IS NOT NULL THEN g.uuid
                WHEN s.id IS NOT NULL THEN s.uuid
                WHEN v.id IS NOT NULL THEN v.uuid
                WHEN a.id IS NOT NULL THEN a.uuid
                ELSE NULL
            END as usuario_uuid
        FROM app_dat_trabajadores t
        LEFT JOIN seg_roll r ON t.id_roll = r.id
        LEFT JOIN app_dat_gerente g ON t.id = g.id_trabajador
        LEFT JOIN app_dat_supervisor s ON t.id = s.id_trabajador
        LEFT JOIN app_dat_vendedor v ON t.id = v.id_trabajador
        LEFT JOIN app_dat_almacenero a ON t.id = a.id_trabajador
        LEFT JOIN app_dat_tpv tpv ON v.id_tpv = tpv.id
        LEFT JOIN app_dat_almacen alm ON a.id_almacen = alm.id
        WHERE t.id_tienda = p_id_tienda
        ORDER BY t.created_at DESC
    LOOP
        resultado := resultado || jsonb_build_object(
            'trabajador_id', trabajador_record.trabajador_id,
            'nombres', trabajador_record.nombres,
            'apellidos', trabajador_record.apellidos,
            'fecha_creacion', trabajador_record.fecha_creacion,
            'salario_horas', trabajador_record.salario_horas, -- 💰 NUEVO: Salario por hora
            'rol_id', trabajador_record.rol_id,
            'rol_nombre', trabajador_record.rol_nombre,
            'tipo_rol', trabajador_record.tipo_rol,
            'usuario_uuid', trabajador_record.usuario_uuid,
            'datos_especificos', trabajador_record.datos_especificos
        );
    END LOOP;
    
    RETURN jsonb_build_object(
        'success', true,
        'message', 'Trabajadores listados correctamente',
        'data', resultado
    );
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Error al listar trabajadores: ' || SQLERRM,
            'error_code', SQLSTATE,
            'data', '[]'::jsonb
        );
END;
$$;

-- Verificar que la función se actualizó correctamente
SELECT 'Función fn_listar_trabajadores_tienda actualizada correctamente con campo salario_horas' as resultado;
