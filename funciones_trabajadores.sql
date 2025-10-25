-- =====================================================
-- FUNCIONES PARA MANEJO COMPLETO DE TRABAJADORES
-- =====================================================

-- =====================================================
-- 1. FUNCIÓN PARA LISTAR TRABAJADORES DE UNA TIENDA
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

-- =====================================================
-- 2. FUNCIÓN PARA INSERTAR UN TRABAJADOR COMPLETO
-- =====================================================
CREATE OR REPLACE FUNCTION fn_insertar_trabajador_completo(
    p_id_tienda bigint,
    p_nombres character varying,
    p_apellidos character varying,
    p_tipo_rol character varying, -- 'gerente', 'supervisor', 'vendedor', 'almacenero'
    p_usuario_uuid uuid,
    p_tpv_id bigint DEFAULT NULL, -- Solo para vendedores
    p_almacen_id bigint DEFAULT NULL, -- Solo para almaceneros
    p_numero_confirmacion character varying DEFAULT NULL -- Solo para vendedores
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    nuevo_trabajador_id bigint;
    rol_id bigint;
    resultado jsonb := '{}'::jsonb;
BEGIN
    -- Validar que el tipo de rol sea válido
    IF p_tipo_rol NOT IN ('gerente', 'supervisor', 'vendedor', 'almacenero') THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Tipo de rol inválido. Debe ser: gerente, supervisor, vendedor o almacenero'
        );
    END IF;
    
    -- Obtener el ID del rol según el tipo
    SELECT id INTO rol_id 
    FROM seg_roll 
    WHERE denominacion = p_tipo_rol AND id_tienda = p_id_tienda
    LIMIT 1;
    
    -- Si no existe el rol, crearlo
    IF rol_id IS NULL THEN
        INSERT INTO seg_roll (denominacion, descripcion, id_tienda, created_at)
        VALUES (
            p_tipo_rol,
            'Rol ' || p_tipo_rol || ' creado automáticamente',
            p_id_tienda,
            NOW()
        ) RETURNING id INTO rol_id;
    END IF;
    
    -- ✅ CORREGIDO: Crear el trabajador base CON UUID
    INSERT INTO app_dat_trabajadores (
        id_tienda,
        id_roll,
        nombres,
        apellidos,
        uuid,
        created_at
    ) VALUES (
        p_id_tienda,
        rol_id,
        p_nombres,
        p_apellidos,
        p_usuario_uuid,  -- ✅ AGREGADO: Insertar UUID en trabajadores
        NOW()
    ) RETURNING id INTO nuevo_trabajador_id;
    
    resultado := jsonb_set(resultado, '{trabajador_id}', to_jsonb(nuevo_trabajador_id));
    
    -- Asignar a la tabla específica según el rol
    CASE p_tipo_rol
        WHEN 'gerente' THEN
            INSERT INTO app_dat_gerente (
                uuid,
                id_tienda,
                id_trabajador,
                created_at
            ) VALUES (
                p_usuario_uuid,
                p_id_tienda,
                nuevo_trabajador_id,
                NOW()
            );
            resultado := jsonb_set(resultado, '{rol_especifico}', '"gerente"');
            
        WHEN 'supervisor' THEN
            INSERT INTO app_dat_supervisor (
                uuid,
                id_tienda,
                id_trabajador,
                created_at
            ) VALUES (
                p_usuario_uuid,
                p_id_tienda,
                nuevo_trabajador_id,
                NOW()
            );
            resultado := jsonb_set(resultado, '{rol_especifico}', '"supervisor"');
            
        WHEN 'vendedor' THEN
            -- Validar que se proporcione TPV para vendedores
            IF p_tpv_id IS NULL THEN
                -- Buscar el primer TPV disponible de la tienda
                SELECT id INTO p_tpv_id 
                FROM app_dat_tpv 
                WHERE id_tienda = p_id_tienda 
                LIMIT 1;
                
                IF p_tpv_id IS NULL THEN
                    RAISE EXCEPTION 'No hay TPVs disponibles en la tienda para asignar al vendedor';
                END IF;
            END IF;
            
            INSERT INTO app_dat_vendedor (
                uuid,
                id_tpv,
                id_trabajador,
                numero_confirmacion,
                created_at
            ) VALUES (
                p_usuario_uuid,
                p_tpv_id,
                nuevo_trabajador_id,
                p_numero_confirmacion,
                NOW()
            );
            resultado := jsonb_set(resultado, '{rol_especifico}', '"vendedor"');
            resultado := jsonb_set(resultado, '{tpv_asignado}', to_jsonb(p_tpv_id));
            
        WHEN 'almacenero' THEN
            -- Validar que se proporcione almacén para almaceneros
            IF p_almacen_id IS NULL THEN
                -- Buscar el primer almacén disponible de la tienda
                SELECT id INTO p_almacen_id 
                FROM app_dat_almacen 
                WHERE id_tienda = p_id_tienda 
                LIMIT 1;
                
                IF p_almacen_id IS NULL THEN
                    RAISE EXCEPTION 'No hay almacenes disponibles en la tienda para asignar al almacenero';
                END IF;
            END IF;
            
            INSERT INTO app_dat_almacenero (
                uuid,
                id_almacen,
                id_trabajador,
                created_at
            ) VALUES (
                p_usuario_uuid,
                p_almacen_id,
                nuevo_trabajador_id,
                NOW()
            );
            resultado := jsonb_set(resultado, '{rol_especifico}', '"almacenero"');
            resultado := jsonb_set(resultado, '{almacen_asignado}', to_jsonb(p_almacen_id));
    END CASE;
    
    RETURN jsonb_build_object(
        'success', true,
        'message', 'Trabajador creado correctamente',
        'data', resultado
    );
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Error al crear trabajador: ' || SQLERRM,
            'error_code', SQLSTATE
        );
END;
$$;

-- =====================================================
-- 3. FUNCIÓN PARA ELIMINAR UN TRABAJADOR COMPLETO
-- =====================================================
CREATE OR REPLACE FUNCTION fn_eliminar_trabajador_completo(
    p_trabajador_id bigint,
    p_id_tienda bigint
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    trabajador_existe boolean := false;
    tipo_rol_actual character varying;
    usuario_uuid uuid;
    operaciones_count integer := 0;
    turnos_count integer := 0;
    entregas_count integer := 0;
    pagos_count integer := 0;
    pre_asignaciones_count integer := 0;
BEGIN
    -- Verificar que el trabajador existe y pertenece a la tienda
    SELECT EXISTS(
        SELECT 1 FROM app_dat_trabajadores 
        WHERE id = p_trabajador_id AND id_tienda = p_id_tienda
    ) INTO trabajador_existe;
    
    IF NOT trabajador_existe THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'El trabajador no existe o no pertenece a esta tienda'
        );
    END IF;
    
    -- Obtener el UUID del usuario desde las tablas de roles
    SELECT COALESCE(
        (SELECT uuid FROM app_dat_gerente WHERE id_trabajador = p_trabajador_id),
        (SELECT uuid FROM app_dat_supervisor WHERE id_trabajador = p_trabajador_id),
        (SELECT uuid FROM app_dat_vendedor WHERE id_trabajador = p_trabajador_id),
        (SELECT uuid FROM app_dat_almacenero WHERE id_trabajador = p_trabajador_id)
    ) INTO usuario_uuid;
    
    -- Si tiene UUID, verificar operaciones en las tablas que lo usan
    IF usuario_uuid IS NOT NULL THEN
        -- Verificar operaciones en app_dat_operaciones
        SELECT COUNT(*) INTO operaciones_count
        FROM app_dat_operaciones
        WHERE uuid = usuario_uuid;
        
        -- Verificar turnos de caja (creado_por o cerrado_por)
        SELECT COUNT(*) INTO turnos_count
        FROM app_dat_caja_turno
        WHERE creado_por = usuario_uuid OR cerrado_por = usuario_uuid;
        
        -- Verificar entregas parciales (no tiene UUID directo, pero se relaciona con turno)
        -- No es necesario verificar ya que depende de turno
        
        -- Verificar pagos de venta
        SELECT COUNT(*) INTO pagos_count
        FROM app_dat_pago_venta
        WHERE creado_por = usuario_uuid;
        
        -- Verificar pre-asignaciones
        SELECT COUNT(*) INTO pre_asignaciones_count
        FROM app_dat_pre_asignaciones
        WHERE creado_por = usuario_uuid OR confirmado_por = usuario_uuid;
        
        -- Si tiene operaciones, no permitir eliminación
        IF operaciones_count > 0 OR turnos_count > 0 OR pagos_count > 0 OR pre_asignaciones_count > 0 THEN
            RETURN jsonb_build_object(
                'success', false,
                'message', 'No se puede eliminar el trabajador porque tiene operaciones registradas',
                'data', jsonb_build_object(
                    'operaciones', operaciones_count,
                    'turnos_caja', turnos_count,
                    'pagos', pagos_count,
                    'pre_asignaciones', pre_asignaciones_count
                )
            );
        END IF;
    END IF;
    
    -- Determinar el tipo de rol actual para eliminar de la tabla específica
    SELECT 
        CASE 
            WHEN g.id IS NOT NULL THEN 'gerente'
            WHEN s.id IS NOT NULL THEN 'supervisor'
            WHEN v.id IS NOT NULL THEN 'vendedor'
            WHEN a.id IS NOT NULL THEN 'almacenero'
            ELSE 'sin_rol'
        END
    INTO tipo_rol_actual
    FROM app_dat_trabajadores t
    LEFT JOIN app_dat_gerente g ON t.id = g.id_trabajador
    LEFT JOIN app_dat_supervisor s ON t.id = s.id_trabajador
    LEFT JOIN app_dat_vendedor v ON t.id = v.id_trabajador
    LEFT JOIN app_dat_almacenero a ON t.id = a.id_trabajador
    WHERE t.id = p_trabajador_id;
    
    -- Eliminar de la tabla específica según el rol
    CASE tipo_rol_actual
        WHEN 'gerente' THEN
            DELETE FROM app_dat_gerente WHERE id_trabajador = p_trabajador_id;
        WHEN 'supervisor' THEN
            DELETE FROM app_dat_supervisor WHERE id_trabajador = p_trabajador_id;
        WHEN 'vendedor' THEN
            DELETE FROM app_dat_vendedor WHERE id_trabajador = p_trabajador_id;
        WHEN 'almacenero' THEN
            DELETE FROM app_dat_almacenero WHERE id_trabajador = p_trabajador_id;
    END CASE;
    
    -- Eliminar el trabajador base
    DELETE FROM app_dat_trabajadores WHERE id = p_trabajador_id;
    
    RETURN jsonb_build_object(
        'success', true,
        'message', 'Trabajador eliminado correctamente',
        'data', jsonb_build_object(
            'trabajador_id', p_trabajador_id,
            'rol_eliminado', tipo_rol_actual
        )
    );
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Error al eliminar trabajador: ' || SQLERRM,
            'error_code', SQLSTATE
        );
END;
$$;

-- =====================================================
-- 4. FUNCIÓN PARA EDITAR UN TRABAJADOR COMPLETO
-- =====================================================
CREATE OR REPLACE FUNCTION fn_editar_trabajador_completo(
    p_trabajador_id bigint,
    p_id_tienda bigint,
    p_nombres character varying DEFAULT NULL,
    p_apellidos character varying DEFAULT NULL,
    p_nuevo_tipo_rol character varying DEFAULT NULL, -- Si se cambia el rol
    p_nuevo_usuario_uuid uuid DEFAULT NULL,
    p_nuevo_tpv_id bigint DEFAULT NULL, -- Para vendedores
    p_nuevo_almacen_id bigint DEFAULT NULL, -- Para almaceneros
    p_nuevo_numero_confirmacion character varying DEFAULT NULL -- Para vendedores
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    trabajador_existe boolean := false;
    tipo_rol_actual character varying;
    nuevo_rol_id bigint;
    uuid_actual uuid;
    resultado jsonb := '{}'::jsonb;
BEGIN
    -- Verificar que el trabajador existe y pertenece a la tienda
    SELECT EXISTS(
        SELECT 1 FROM app_dat_trabajadores 
        WHERE id = p_trabajador_id AND id_tienda = p_id_tienda
    ) INTO trabajador_existe;
    
    IF NOT trabajador_existe THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'El trabajador no existe o no pertenece a esta tienda'
        );
    END IF;
    
    -- Obtener el tipo de rol actual y UUID
    SELECT 
        CASE 
            WHEN g.id IS NOT NULL THEN 'gerente'
            WHEN s.id IS NOT NULL THEN 'supervisor'
            WHEN v.id IS NOT NULL THEN 'vendedor'
            WHEN a.id IS NOT NULL THEN 'almacenero'
            ELSE 'sin_rol'
        END,
        COALESCE(g.uuid, s.uuid, v.uuid, a.uuid)
    INTO tipo_rol_actual, uuid_actual
    FROM app_dat_trabajadores t
    LEFT JOIN app_dat_gerente g ON t.id = g.id_trabajador
    LEFT JOIN app_dat_supervisor s ON t.id = s.id_trabajador
    LEFT JOIN app_dat_vendedor v ON t.id = v.id_trabajador
    LEFT JOIN app_dat_almacenero a ON t.id = a.id_trabajador
    WHERE t.id = p_trabajador_id;
    
    -- Actualizar datos básicos del trabajador si se proporcionan
    UPDATE app_dat_trabajadores 
    SET 
        nombres = COALESCE(p_nombres, nombres),
        apellidos = COALESCE(p_apellidos, apellidos)
    WHERE id = p_trabajador_id;
    
    -- Si se cambia el rol, manejar la transición
    IF p_nuevo_tipo_rol IS NOT NULL AND p_nuevo_tipo_rol != tipo_rol_actual THEN
        -- Validar que el nuevo tipo de rol sea válido
        IF p_nuevo_tipo_rol NOT IN ('gerente', 'supervisor', 'vendedor', 'almacenero') THEN
            RETURN jsonb_build_object(
                'success', false,
                'message', 'Tipo de rol inválido. Debe ser: gerente, supervisor, vendedor o almacenero'
            );
        END IF;
        
        -- Obtener o crear el nuevo rol
        SELECT id INTO nuevo_rol_id 
        FROM seg_roll 
        WHERE denominacion = p_nuevo_tipo_rol AND id_tienda = p_id_tienda
        LIMIT 1;
        
        IF nuevo_rol_id IS NULL THEN
            INSERT INTO seg_roll (denominacion, descripcion, id_tienda, created_at)
            VALUES (
                p_nuevo_tipo_rol,
                'Rol ' || p_nuevo_tipo_rol || ' creado automáticamente',
                p_id_tienda,
                NOW()
            ) RETURNING id INTO nuevo_rol_id;
        END IF;
        
        -- Actualizar el rol en la tabla trabajadores
        UPDATE app_dat_trabajadores 
        SET id_roll = nuevo_rol_id 
        WHERE id = p_trabajador_id;
        
        -- Eliminar del rol anterior
        CASE tipo_rol_actual
            WHEN 'gerente' THEN
                DELETE FROM app_dat_gerente WHERE id_trabajador = p_trabajador_id;
            WHEN 'supervisor' THEN
                DELETE FROM app_dat_supervisor WHERE id_trabajador = p_trabajador_id;
            WHEN 'vendedor' THEN
                DELETE FROM app_dat_vendedor WHERE id_trabajador = p_trabajador_id;
            WHEN 'almacenero' THEN
                DELETE FROM app_dat_almacenero WHERE id_trabajador = p_trabajador_id;
        END CASE;
        
        -- Insertar en el nuevo rol
        CASE p_nuevo_tipo_rol
            WHEN 'gerente' THEN
                INSERT INTO app_dat_gerente (
                    uuid,
                    id_tienda,
                    id_trabajador,
                    created_at
                ) VALUES (
                    COALESCE(p_nuevo_usuario_uuid, uuid_actual),
                    p_id_tienda,
                    p_trabajador_id,
                    NOW()
                );
                
            WHEN 'supervisor' THEN
                INSERT INTO app_dat_supervisor (
                    uuid,
                    id_tienda,
                    id_trabajador,
                    created_at
                ) VALUES (
                    COALESCE(p_nuevo_usuario_uuid, uuid_actual),
                    p_id_tienda,
                    p_trabajador_id,
                    NOW()
                );
                
            WHEN 'vendedor' THEN
                -- Validar TPV
                IF p_nuevo_tpv_id IS NULL THEN
                    SELECT id INTO p_nuevo_tpv_id 
                    FROM app_dat_tpv 
                    WHERE id_tienda = p_id_tienda 
                    LIMIT 1;
                END IF;
                
                INSERT INTO app_dat_vendedor (
                    uuid,
                    id_tpv,
                    id_trabajador,
                    numero_confirmacion,
                    created_at
                ) VALUES (
                    COALESCE(p_nuevo_usuario_uuid, uuid_actual),
                    p_nuevo_tpv_id,
                    p_trabajador_id,
                    p_nuevo_numero_confirmacion,
                    NOW()
                );
                
            WHEN 'almacenero' THEN
                -- Validar almacén
                IF p_nuevo_almacen_id IS NULL THEN
                    SELECT id INTO p_nuevo_almacen_id 
                    FROM app_dat_almacen 
                    WHERE id_tienda = p_id_tienda 
                    LIMIT 1;
                END IF;
                
                INSERT INTO app_dat_almacenero (
                    uuid,
                    id_almacen,
                    id_trabajador,
                    created_at
                ) VALUES (
                    COALESCE(p_nuevo_usuario_uuid, uuid_actual),
                    p_nuevo_almacen_id,
                    p_trabajador_id,
                    NOW()
                );
        END CASE;
        
        resultado := jsonb_set(resultado, '{rol_cambiado}', 'true');
        resultado := jsonb_set(resultado, '{rol_anterior}', to_jsonb(tipo_rol_actual));
        resultado := jsonb_set(resultado, '{rol_nuevo}', to_jsonb(p_nuevo_tipo_rol));
        
    ELSE
        -- Solo actualizar datos específicos del rol actual
        CASE tipo_rol_actual
            WHEN 'gerente' THEN
                UPDATE app_dat_gerente 
                SET uuid = COALESCE(p_nuevo_usuario_uuid, uuid)
                WHERE id_trabajador = p_trabajador_id;
                
            WHEN 'supervisor' THEN
                UPDATE app_dat_supervisor 
                SET uuid = COALESCE(p_nuevo_usuario_uuid, uuid)
                WHERE id_trabajador = p_trabajador_id;
                
            WHEN 'vendedor' THEN
                UPDATE app_dat_vendedor 
                SET 
                    uuid = COALESCE(p_nuevo_usuario_uuid, uuid),
                    id_tpv = COALESCE(p_nuevo_tpv_id, id_tpv),
                    numero_confirmacion = COALESCE(p_nuevo_numero_confirmacion, numero_confirmacion)
                WHERE id_trabajador = p_trabajador_id;
                
            WHEN 'almacenero' THEN
                UPDATE app_dat_almacenero 
                SET 
                    uuid = COALESCE(p_nuevo_usuario_uuid, uuid),
                    id_almacen = COALESCE(p_nuevo_almacen_id, id_almacen)
                WHERE id_trabajador = p_trabajador_id;
        END CASE;
        
        resultado := jsonb_set(resultado, '{rol_cambiado}', 'false');
    END IF;
    
    resultado := jsonb_set(resultado, '{trabajador_id}', to_jsonb(p_trabajador_id));
    
    RETURN jsonb_build_object(
        'success', true,
        'message', 'Trabajador actualizado correctamente',
        'data', resultado
    );
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Error al actualizar trabajador: ' || SQLERRM,
            'error_code', SQLSTATE
        );
END;
$$;

-- =====================================================
-- EJEMPLOS DE USO DE LAS FUNCIONES
-- =====================================================

/*
-- 1. Listar trabajadores de una tienda (solo gerentes y supervisores pueden hacerlo)
SELECT fn_listar_trabajadores_tienda(1, 'uuid-del-gerente-o-supervisor');

-- 2. Insertar un trabajador completo
-- Gerente
SELECT fn_insertar_trabajador_completo(
    1, -- id_tienda
    'Juan', -- nombres
    'Pérez', -- apellidos
    'gerente', -- tipo_rol
    'uuid-del-usuario'::uuid -- usuario_uuid
);

-- Vendedor
SELECT fn_insertar_trabajador_completo(
    1, -- id_tienda
    'María', -- nombres
    'González', -- apellidos
    'vendedor', -- tipo_rol
    'uuid-del-usuario'::uuid, -- usuario_uuid
    1, -- tpv_id
    NULL, -- almacen_id (no aplica para vendedor)
    'CONF123' -- numero_confirmacion
);

-- Almacenero
SELECT fn_insertar_trabajador_completo(
    1, -- id_tienda
    'Carlos', -- nombres
    'López', -- apellidos
    'almacenero', -- tipo_rol
    'uuid-del-usuario'::uuid, -- usuario_uuid
    NULL, -- tpv_id (no aplica para almacenero)
    1 -- almacen_id
);

-- 3. Eliminar un trabajador
SELECT fn_eliminar_trabajador_completo(1, 1); -- trabajador_id, id_tienda

-- 4. Editar un trabajador (cambiar solo nombres y apellidos)
SELECT fn_editar_trabajador_completo(
    1, -- trabajador_id
    1, -- id_tienda
    'Juan Carlos', -- nuevos nombres
    'Pérez García' -- nuevos apellidos
);

-- 5. Editar un trabajador (cambiar rol de vendedor a supervisor)
SELECT fn_editar_trabajador_completo(
    1, -- trabajador_id
    1, -- id_tienda
    NULL, -- nombres (no cambiar)
    NULL, -- apellidos (no cambiar)
    'supervisor', -- nuevo_tipo_rol
    'nuevo-uuid'::uuid -- nuevo_usuario_uuid
);
*/
