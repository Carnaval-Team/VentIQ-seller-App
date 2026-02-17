-- =====================================================
-- TABLA: app_dat_almacenero
-- Descripción: Almacena la relación entre trabajadores y almacenes
-- =====================================================

CREATE TABLE IF NOT EXISTS public.app_dat_almacenero (
    id SERIAL PRIMARY KEY,
    id_trabajador INTEGER NOT NULL REFERENCES public.app_dat_trabajadores(id) ON DELETE CASCADE,
    id_almacen INTEGER NOT NULL REFERENCES public.app_dat_almacen(id) ON DELETE CASCADE,
    id_tienda INTEGER NOT NULL REFERENCES public.app_dat_tienda(id) ON DELETE CASCADE,
    estado SMALLINT DEFAULT 1, -- 1 = activo, 0 = inactivo
    created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITHOUT TIME ZONE DEFAULT NOW(),
    CONSTRAINT unique_almacenero_trabajador UNIQUE (id_trabajador, id_tienda)
);

-- Índices para mejorar rendimiento
CREATE INDEX IF NOT EXISTS idx_almacenero_trabajador ON public.app_dat_almacenero(id_trabajador);
CREATE INDEX IF NOT EXISTS idx_almacenero_almacen ON public.app_dat_almacenero(id_almacen);
CREATE INDEX IF NOT EXISTS idx_almacenero_tienda ON public.app_dat_almacenero(id_tienda);
CREATE INDEX IF NOT EXISTS idx_almacenero_estado ON public.app_dat_almacenero(estado);

-- Comentarios
COMMENT ON TABLE public.app_dat_almacenero IS 'Tabla que relaciona trabajadores con almacenes (rol almacenero)';
COMMENT ON COLUMN public.app_dat_almacenero.id_trabajador IS 'ID del trabajador';
COMMENT ON COLUMN public.app_dat_almacenero.id_almacen IS 'ID del almacén asignado';
COMMENT ON COLUMN public.app_dat_almacenero.id_tienda IS 'ID de la tienda';
COMMENT ON COLUMN public.app_dat_almacenero.estado IS '1 = activo, 0 = inactivo';

-- =====================================================
-- RPC: fn_crear_almacenero
-- Descripción: Crea un nuevo almacenero
-- =====================================================

CREATE OR REPLACE FUNCTION public.fn_crear_almacenero(
    p_id_trabajador INTEGER,
    p_id_almacen INTEGER,
    p_id_tienda INTEGER
)
RETURNS JSON
LANGUAGE plpgsql
AS $$
DECLARE
    v_almacenero_id INTEGER;
    v_result JSON;
BEGIN
    -- Validar que el trabajador existe
    IF NOT EXISTS (SELECT 1 FROM public.app_dat_trabajadores WHERE id = p_id_trabajador) THEN
        RETURN json_build_object(
            'success', false,
            'message', 'El trabajador no existe'
        );
    END IF;

    -- Validar que el almacén existe
    IF NOT EXISTS (SELECT 1 FROM public.app_dat_almacen WHERE id = p_id_almacen AND id_tienda = p_id_tienda) THEN
        RETURN json_build_object(
            'success', false,
            'message', 'El almacén no existe o no pertenece a la tienda'
        );
    END IF;

    -- Verificar si ya existe un almacenero para este trabajador
    IF EXISTS (SELECT 1 FROM public.app_dat_almacenero WHERE id_trabajador = p_id_trabajador AND id_tienda = p_id_tienda) THEN
        -- Actualizar el almacén asignado
        UPDATE public.app_dat_almacenero
        SET id_almacen = p_id_almacen,
            estado = 1,
            updated_at = NOW()
        WHERE id_trabajador = p_id_trabajador AND id_tienda = p_id_tienda
        RETURNING id INTO v_almacenero_id;
        
        RETURN json_build_object(
            'success', true,
            'message', 'Almacenero actualizado correctamente',
            'almacenero_id', v_almacenero_id
        );
    ELSE
        -- Insertar nuevo almacenero
        INSERT INTO public.app_dat_almacenero (id_trabajador, id_almacen, id_tienda, estado)
        VALUES (p_id_trabajador, p_id_almacen, p_id_tienda, 1)
        RETURNING id INTO v_almacenero_id;
        
        RETURN json_build_object(
            'success', true,
            'message', 'Almacenero creado correctamente',
            'almacenero_id', v_almacenero_id
        );
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Error al crear almacenero: ' || SQLERRM
        );
END;
$$;

-- =====================================================
-- RPC: fn_eliminar_almacenero
-- Descripción: Elimina (desactiva) un almacenero
-- =====================================================

CREATE OR REPLACE FUNCTION public.fn_eliminar_almacenero(
    p_id_trabajador INTEGER,
    p_id_tienda INTEGER
)
RETURNS JSON
LANGUAGE plpgsql
AS $$
BEGIN
    -- Desactivar el almacenero
    UPDATE public.app_dat_almacenero
    SET estado = 0,
        updated_at = NOW()
    WHERE id_trabajador = p_id_trabajador AND id_tienda = p_id_tienda;

    IF FOUND THEN
        RETURN json_build_object(
            'success', true,
            'message', 'Almacenero eliminado correctamente'
        );
    ELSE
        RETURN json_build_object(
            'success', false,
            'message', 'Almacenero no encontrado'
        );
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Error al eliminar almacenero: ' || SQLERRM
        );
END;
$$;

-- =====================================================
-- RPC: fn_obtener_almacen_almacenero
-- Descripción: Obtiene el almacén asignado a un almacenero
-- =====================================================

CREATE OR REPLACE FUNCTION public.fn_obtener_almacen_almacenero(
    p_id_trabajador INTEGER,
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
            'id_almacen', a.id_almacen,
            'almacen_denominacion', alm.denominacion,
            'almacen_direccion', alm.direccion,
            'almacen_ubicacion', alm.ubicacion
        )
    )
    INTO v_result
    FROM public.app_dat_almacenero a
    INNER JOIN public.app_dat_almacen alm ON a.id_almacen = alm.id
    WHERE a.id_trabajador = p_id_trabajador
      AND a.id_tienda = p_id_tienda
      AND a.estado = 1;

    IF v_result IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Almacenero no encontrado o inactivo'
        );
    END IF;

    RETURN v_result;

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Error al obtener almacén del almacenero: ' || SQLERRM
        );
END;
$$;
