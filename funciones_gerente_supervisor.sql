-- =====================================================
-- FUNCIONES PARA CREAR GERENTE Y SUPERVISOR
-- =====================================================
-- Basado en la estructura de base de datos de VentIQ
-- Tablas involucradas:
-- - app_dat_trabajadores (trabajador base)
-- - app_dat_gerente (datos específicos del gerente)
-- - app_dat_supervisor (datos específicos del supervisor)
-- - seg_roll (roles del sistema)
-- =====================================================

-- =====================================================
-- FUNCIÓN: fn_crear_gerente
-- =====================================================
-- Crea un gerente para una tienda específica
-- Parámetros:
--   p_id_tienda: ID de la tienda
--   p_uuid: UUID del usuario de auth.users
--   p_id_trabajador: ID del trabajador base
-- Retorna: JSON con resultado de la operación
-- =====================================================

CREATE OR REPLACE FUNCTION fn_crear_gerente(
    p_id_tienda BIGINT,
    p_uuid UUID,
    p_id_trabajador BIGINT
)
RETURNS JSON AS $$
DECLARE
    v_gerente_id BIGINT;
    v_trabajador_exists BOOLEAN := FALSE;
    v_gerente_exists BOOLEAN := FALSE;
    v_tienda_exists BOOLEAN := FALSE;
    v_user_exists BOOLEAN := FALSE;
BEGIN
    -- Log de inicio
    RAISE NOTICE '🔧 Iniciando creación de gerente para tienda: %, UUID: %, Trabajador: %', 
        p_id_tienda, p_uuid, p_id_trabajador;

    -- Validar que la tienda existe
    SELECT EXISTS(
        SELECT 1 FROM app_dat_tienda WHERE id = p_id_tienda
    ) INTO v_tienda_exists;
    
    IF NOT v_tienda_exists THEN
        RAISE NOTICE '❌ Error: La tienda con ID % no existe', p_id_tienda;
        RETURN json_build_object(
            'success', false,
            'message', 'La tienda especificada no existe',
            'error_code', 'TIENDA_NOT_FOUND'
        );
    END IF;

    -- Validar que el usuario existe en auth.users
    SELECT EXISTS(
        SELECT 1 FROM auth.users WHERE id = p_uuid
    ) INTO v_user_exists;
    
    IF NOT v_user_exists THEN
        RAISE NOTICE '❌ Error: El usuario con UUID % no existe en auth.users', p_uuid;
        RETURN json_build_object(
            'success', false,
            'message', 'El usuario especificado no existe',
            'error_code', 'USER_NOT_FOUND'
        );
    END IF;

    -- Validar que el trabajador existe y pertenece a la tienda
    SELECT EXISTS(
        SELECT 1 FROM app_dat_trabajadores 
        WHERE id = p_id_trabajador AND id_tienda = p_id_tienda
    ) INTO v_trabajador_exists;
    
    IF NOT v_trabajador_exists THEN
        RAISE NOTICE '❌ Error: El trabajador con ID % no existe o no pertenece a la tienda %', 
            p_id_trabajador, p_id_tienda;
        RETURN json_build_object(
            'success', false,
            'message', 'El trabajador especificado no existe o no pertenece a la tienda',
            'error_code', 'TRABAJADOR_NOT_FOUND'
        );
    END IF;

    -- Verificar si ya existe un gerente con este UUID en esta tienda
    SELECT EXISTS(
        SELECT 1 FROM app_dat_gerente 
        WHERE uuid = p_uuid AND id_tienda = p_id_tienda
    ) INTO v_gerente_exists;
    
    IF v_gerente_exists THEN
        RAISE NOTICE '⚠️ Advertencia: Ya existe un gerente con UUID % en la tienda %', 
            p_uuid, p_id_tienda;
        RETURN json_build_object(
            'success', false,
            'message', 'Ya existe un gerente con este usuario en la tienda',
            'error_code', 'GERENTE_ALREADY_EXISTS'
        );
    END IF;

    -- Crear el gerente
    INSERT INTO app_dat_gerente (uuid, id_tienda, id_trabajador)
    VALUES (p_uuid, p_id_tienda, p_id_trabajador)
    RETURNING id INTO v_gerente_id;

    RAISE NOTICE '✅ Gerente creado exitosamente con ID: %', v_gerente_id;

    -- Retornar resultado exitoso
    RETURN json_build_object(
        'success', true,
        'message', 'Gerente creado exitosamente',
        'data', json_build_object(
            'gerente_id', v_gerente_id,
            'uuid', p_uuid,
            'id_tienda', p_id_tienda,
            'id_trabajador', p_id_trabajador,
            'created_at', NOW()
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '❌ Error inesperado al crear gerente: %', SQLERRM;
        RETURN json_build_object(
            'success', false,
            'message', 'Error interno al crear gerente',
            'error_code', 'INTERNAL_ERROR',
            'sql_error', SQLERRM
        );
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- FUNCIÓN: fn_crear_supervisor
-- =====================================================
-- Crea un supervisor para una tienda específica
-- Parámetros:
--   p_id_tienda: ID de la tienda
--   p_uuid: UUID del usuario de auth.users
--   p_id_trabajador: ID del trabajador base
-- Retorna: JSON con resultado de la operación
-- =====================================================

CREATE OR REPLACE FUNCTION fn_crear_supervisor(
    p_id_tienda BIGINT,
    p_uuid UUID,
    p_id_trabajador BIGINT
)
RETURNS JSON AS $$
DECLARE
    v_supervisor_id BIGINT;
    v_trabajador_exists BOOLEAN := FALSE;
    v_supervisor_exists BOOLEAN := FALSE;
    v_tienda_exists BOOLEAN := FALSE;
    v_user_exists BOOLEAN := FALSE;
BEGIN
    -- Log de inicio
    RAISE NOTICE '🔧 Iniciando creación de supervisor para tienda: %, UUID: %, Trabajador: %', 
        p_id_tienda, p_uuid, p_id_trabajador;

    -- Validar que la tienda existe
    SELECT EXISTS(
        SELECT 1 FROM app_dat_tienda WHERE id = p_id_tienda
    ) INTO v_tienda_exists;
    
    IF NOT v_tienda_exists THEN
        RAISE NOTICE '❌ Error: La tienda con ID % no existe', p_id_tienda;
        RETURN json_build_object(
            'success', false,
            'message', 'La tienda especificada no existe',
            'error_code', 'TIENDA_NOT_FOUND'
        );
    END IF;

    -- Validar que el usuario existe en auth.users
    SELECT EXISTS(
        SELECT 1 FROM auth.users WHERE id = p_uuid
    ) INTO v_user_exists;
    
    IF NOT v_user_exists THEN
        RAISE NOTICE '❌ Error: El usuario con UUID % no existe en auth.users', p_uuid;
        RETURN json_build_object(
            'success', false,
            'message', 'El usuario especificado no existe',
            'error_code', 'USER_NOT_FOUND'
        );
    END IF;

    -- Validar que el trabajador existe y pertenece a la tienda
    SELECT EXISTS(
        SELECT 1 FROM app_dat_trabajadores 
        WHERE id = p_id_trabajador AND id_tienda = p_id_tienda
    ) INTO v_trabajador_exists;
    
    IF NOT v_trabajador_exists THEN
        RAISE NOTICE '❌ Error: El trabajador con ID % no existe o no pertenece a la tienda %', 
            p_id_trabajador, p_id_tienda;
        RETURN json_build_object(
            'success', false,
            'message', 'El trabajador especificado no existe o no pertenece a la tienda',
            'error_code', 'TRABAJADOR_NOT_FOUND'
        );
    END IF;

    -- Verificar si ya existe un supervisor con este UUID en esta tienda
    SELECT EXISTS(
        SELECT 1 FROM app_dat_supervisor 
        WHERE uuid = p_uuid AND id_tienda = p_id_tienda
    ) INTO v_supervisor_exists;
    
    IF v_supervisor_exists THEN
        RAISE NOTICE '⚠️ Advertencia: Ya existe un supervisor con UUID % en la tienda %', 
            p_uuid, p_id_tienda;
        RETURN json_build_object(
            'success', false,
            'message', 'Ya existe un supervisor con este usuario en la tienda',
            'error_code', 'SUPERVISOR_ALREADY_EXISTS'
        );
    END IF;

    -- Crear el supervisor
    INSERT INTO app_dat_supervisor (uuid, id_tienda, id_trabajador)
    VALUES (p_uuid, p_id_tienda, p_id_trabajador)
    RETURNING id INTO v_supervisor_id;

    RAISE NOTICE '✅ Supervisor creado exitosamente con ID: %', v_supervisor_id;

    -- Retornar resultado exitoso
    RETURN json_build_object(
        'success', true,
        'message', 'Supervisor creado exitosamente',
        'data', json_build_object(
            'supervisor_id', v_supervisor_id,
            'uuid', p_uuid,
            'id_tienda', p_id_tienda,
            'id_trabajador', p_id_trabajador,
            'created_at', NOW()
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '❌ Error inesperado al crear supervisor: %', SQLERRM;
        RETURN json_build_object(
            'success', false,
            'message', 'Error interno al crear supervisor',
            'error_code', 'INTERNAL_ERROR',
            'sql_error', SQLERRM
        );
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- FUNCIÓN: fn_crear_gerente_completo
-- =====================================================
-- Crea un gerente completo (trabajador + gerente) en una sola operación
-- Parámetros:
--   p_id_tienda: ID de la tienda
--   p_uuid: UUID del usuario de auth.users
--   p_nombres: Nombres del trabajador
--   p_apellidos: Apellidos del trabajador
--   p_id_roll: ID del rol (opcional, se busca automáticamente)
-- Retorna: JSON con resultado de la operación
-- =====================================================

CREATE OR REPLACE FUNCTION fn_crear_gerente_completo(
    p_id_tienda BIGINT,
    p_uuid UUID,
    p_nombres VARCHAR,
    p_apellidos VARCHAR,
    p_id_roll BIGINT DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
    v_trabajador_id BIGINT;
    v_gerente_id BIGINT;
    v_roll_id BIGINT;
    v_tienda_exists BOOLEAN := FALSE;
    v_user_exists BOOLEAN := FALSE;
BEGIN
    -- Log de inicio
    RAISE NOTICE '🔧 Iniciando creación de gerente completo para tienda: %, UUID: %', 
        p_id_tienda, p_uuid;

    -- Validaciones básicas
    SELECT EXISTS(SELECT 1 FROM app_dat_tienda WHERE id = p_id_tienda) INTO v_tienda_exists;
    SELECT EXISTS(SELECT 1 FROM auth.users WHERE id = p_uuid) INTO v_user_exists;
    
    IF NOT v_tienda_exists THEN
        RETURN json_build_object('success', false, 'message', 'Tienda no encontrada', 'error_code', 'TIENDA_NOT_FOUND');
    END IF;
    
    IF NOT v_user_exists THEN
        RETURN json_build_object('success', false, 'message', 'Usuario no encontrado', 'error_code', 'USER_NOT_FOUND');
    END IF;

    -- Obtener o crear rol de gerente
    IF p_id_roll IS NULL THEN
        SELECT id INTO v_roll_id FROM seg_roll WHERE denominacion ILIKE '%gerente%' LIMIT 1;
        IF v_roll_id IS NULL THEN
            INSERT INTO seg_roll (denominacion, descripcion) 
            VALUES ('Gerente', 'Rol de gerente de tienda') 
            RETURNING id INTO v_roll_id;
        END IF;
    ELSE
        v_roll_id := p_id_roll;
    END IF;

    -- Crear trabajador
    INSERT INTO app_dat_trabajadores (id_tienda, id_roll, nombres, apellidos)
    VALUES (p_id_tienda, v_roll_id, p_nombres, p_apellidos)
    RETURNING id INTO v_trabajador_id;

    -- Crear gerente
    INSERT INTO app_dat_gerente (uuid, id_tienda, id_trabajador)
    VALUES (p_uuid, p_id_tienda, v_trabajador_id)
    RETURNING id INTO v_gerente_id;

    RAISE NOTICE '✅ Gerente completo creado - Trabajador ID: %, Gerente ID: %', 
        v_trabajador_id, v_gerente_id;

    RETURN json_build_object(
        'success', true,
        'message', 'Gerente completo creado exitosamente',
        'data', json_build_object(
            'trabajador_id', v_trabajador_id,
            'gerente_id', v_gerente_id,
            'uuid', p_uuid,
            'id_tienda', p_id_tienda,
            'nombres', p_nombres,
            'apellidos', p_apellidos,
            'id_roll', v_roll_id
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '❌ Error al crear gerente completo: %', SQLERRM;
        RETURN json_build_object(
            'success', false,
            'message', 'Error interno al crear gerente completo',
            'error_code', 'INTERNAL_ERROR',
            'sql_error', SQLERRM
        );
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- FUNCIÓN: fn_crear_supervisor_completo
-- =====================================================
-- Crea un supervisor completo (trabajador + supervisor) en una sola operación
-- Parámetros:
--   p_id_tienda: ID de la tienda
--   p_uuid: UUID del usuario de auth.users
--   p_nombres: Nombres del trabajador
--   p_apellidos: Apellidos del trabajador
--   p_id_roll: ID del rol (opcional, se busca automáticamente)
-- Retorna: JSON con resultado de la operación
-- =====================================================

CREATE OR REPLACE FUNCTION fn_crear_supervisor_completo(
    p_id_tienda BIGINT,
    p_uuid UUID,
    p_nombres VARCHAR,
    p_apellidos VARCHAR,
    p_id_roll BIGINT DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
    v_trabajador_id BIGINT;
    v_supervisor_id BIGINT;
    v_roll_id BIGINT;
    v_tienda_exists BOOLEAN := FALSE;
    v_user_exists BOOLEAN := FALSE;
BEGIN
    -- Log de inicio
    RAISE NOTICE '🔧 Iniciando creación de supervisor completo para tienda: %, UUID: %', 
        p_id_tienda, p_uuid;

    -- Validaciones básicas
    SELECT EXISTS(SELECT 1 FROM app_dat_tienda WHERE id = p_id_tienda) INTO v_tienda_exists;
    SELECT EXISTS(SELECT 1 FROM auth.users WHERE id = p_uuid) INTO v_user_exists;
    
    IF NOT v_tienda_exists THEN
        RETURN json_build_object('success', false, 'message', 'Tienda no encontrada', 'error_code', 'TIENDA_NOT_FOUND');
    END IF;
    
    IF NOT v_user_exists THEN
        RETURN json_build_object('success', false, 'message', 'Usuario no encontrado', 'error_code', 'USER_NOT_FOUND');
    END IF;

    -- Obtener o crear rol de supervisor
    IF p_id_roll IS NULL THEN
        SELECT id INTO v_roll_id FROM seg_roll WHERE denominacion ILIKE '%supervisor%' LIMIT 1;
        IF v_roll_id IS NULL THEN
            INSERT INTO seg_roll (denominacion, descripcion) 
            VALUES ('Supervisor', 'Rol de supervisor de tienda') 
            RETURNING id INTO v_roll_id;
        END IF;
    ELSE
        v_roll_id := p_id_roll;
    END IF;

    -- Crear trabajador
    INSERT INTO app_dat_trabajadores (id_tienda, id_roll, nombres, apellidos)
    VALUES (p_id_tienda, v_roll_id, p_nombres, p_apellidos)
    RETURNING id INTO v_trabajador_id;

    -- Crear supervisor
    INSERT INTO app_dat_supervisor (uuid, id_tienda, id_trabajador)
    VALUES (p_uuid, p_id_tienda, v_trabajador_id)
    RETURNING id INTO v_supervisor_id;

    RAISE NOTICE '✅ Supervisor completo creado - Trabajador ID: %, Supervisor ID: %', 
        v_trabajador_id, v_supervisor_id;

    RETURN json_build_object(
        'success', true,
        'message', 'Supervisor completo creado exitosamente',
        'data', json_build_object(
            'trabajador_id', v_trabajador_id,
            'supervisor_id', v_supervisor_id,
            'uuid', p_uuid,
            'id_tienda', p_id_tienda,
            'nombres', p_nombres,
            'apellidos', p_apellidos,
            'id_roll', v_roll_id
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '❌ Error al crear supervisor completo: %', SQLERRM;
        RETURN json_build_object(
            'success', false,
            'message', 'Error interno al crear supervisor completo',
            'error_code', 'INTERNAL_ERROR',
            'sql_error', SQLERRM
        );
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- EJEMPLOS DE USO
-- =====================================================

/*
-- Ejemplo 1: Crear gerente con trabajador existente
SELECT fn_crear_gerente(
    1,  -- id_tienda
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'::UUID,  -- uuid
    5   -- id_trabajador
);

-- Ejemplo 2: Crear supervisor con trabajador existente
SELECT fn_crear_supervisor(
    1,  -- id_tienda
    'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a12'::UUID,  -- uuid
    6   -- id_trabajador
);

-- Ejemplo 3: Crear gerente completo (trabajador + gerente)
SELECT fn_crear_gerente_completo(
    1,  -- id_tienda
    'c0eebc99-9c0b-4ef8-bb6d-6bb9bd380a13'::UUID,  -- uuid
    'Juan Carlos',  -- nombres
    'Pérez García'  -- apellidos
);

-- Ejemplo 4: Crear supervisor completo (trabajador + supervisor)
SELECT fn_crear_supervisor_completo(
    1,  -- id_tienda
    'd0eebc99-9c0b-4ef8-bb6d-6bb9bd380a14'::UUID,  -- uuid
    'María Elena',  -- nombres
    'González López'  -- apellidos
);
*/

-- =====================================================
-- COMENTARIOS Y NOTAS
-- =====================================================

/*
ESTRUCTURA DE TABLAS UTILIZADAS:

1. app_dat_trabajadores:
   - id (PK)
   - id_tienda (FK)
   - id_roll (FK)
   - nombres
   - apellidos
   - created_at

2. app_dat_gerente:
   - id (PK)
   - uuid (FK auth.users)
   - id_tienda (FK)
   - id_trabajador (FK)
   - created_at

3. app_dat_supervisor:
   - id (PK)
   - uuid (FK auth.users)
   - id_tienda (FK)
   - id_trabajador (FK)
   - created_at

4. seg_roll:
   - id (PK)
   - denominacion
   - descripcion

VALIDACIONES IMPLEMENTADAS:
- Existencia de tienda
- Existencia de usuario en auth.users
- Existencia de trabajador (para funciones básicas)
- No duplicación de gerente/supervisor por UUID y tienda
- Relación correcta trabajador-tienda

FUNCIONES DISPONIBLES:
1. fn_crear_gerente(): Crea gerente con trabajador existente
2. fn_crear_supervisor(): Crea supervisor con trabajador existente
3. fn_crear_gerente_completo(): Crea trabajador + gerente en una operación
4. fn_crear_supervisor_completo(): Crea trabajador + supervisor en una operación

RETORNO:
Todas las funciones retornan JSON con:
- success: boolean
- message: string
- data: object (en caso de éxito)
- error_code: string (en caso de error)
- sql_error: string (en caso de error SQL)
*/
