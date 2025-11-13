-- =====================================================
-- MODIFICAR CONSTRAINT DE INVENTARIO CONDICIONAL
-- =====================================================
-- Este script modifica la constraint de cantidad_final para que sea condicional
-- basada en la configuración permite_vender_aun_sin_disponibilidad de la tienda
-- 
-- Si permite_vender_aun_sin_disponibilidad = true: Permite cantidades negativas
-- Si permite_vender_aun_sin_disponibilidad = false: Requiere cantidades >= 0
-- =====================================================

-- 1. ELIMINAR LA CONSTRAINT ACTUAL
-- =====================================================
ALTER TABLE public.app_dat_inventario_productos 
DROP CONSTRAINT IF EXISTS chk_cantidad_final_non_negative;

-- 2. CREAR FUNCIÓN PARA VALIDAR CANTIDAD FINAL
-- =====================================================
-- Función que determina si una cantidad final es válida según la configuración de la tienda
CREATE OR REPLACE FUNCTION fn_validar_cantidad_final_inventario(
    p_id_producto bigint,
    p_cantidad_final numeric
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_permite_negativo boolean := false;
BEGIN
    -- Si cantidad_final es null, siempre es válido
    IF p_cantidad_final IS NULL THEN
        RETURN true;
    END IF;
    
    -- Obtener configuración de la tienda
    SELECT COALESCE(ct.permite_vender_aun_sin_disponibilidad, false)
    INTO v_permite_negativo
    FROM app_dat_producto p
    INNER JOIN app_dat_configuracion_tienda ct ON p.id_tienda = ct.id_tienda
    WHERE p.id = p_id_producto;
    
    -- Si no se encuentra configuración, por defecto no permite negativo
    v_permite_negativo := COALESCE(v_permite_negativo, false);
    
    -- Si permite negativo, cualquier cantidad es válida
    IF v_permite_negativo = true THEN
        RETURN true;
    END IF;
    
    -- Si no permite negativo, cantidad debe ser >= 0
    RETURN p_cantidad_final >= 0;
END;
$$;

-- 3. CREAR NUEVA CONSTRAINT USANDO LA FUNCIÓN
-- =====================================================
-- Esta constraint usa la función para validar la cantidad final
ALTER TABLE public.app_dat_inventario_productos 
ADD CONSTRAINT chk_cantidad_final_conditional CHECK (
    fn_validar_cantidad_final_inventario(id_producto, cantidad_final) = true
);

-- 4. CREAR ÍNDICE PARA OPTIMIZAR LA CONSTRAINT
-- =====================================================
-- Índice para mejorar el rendimiento de la constraint
CREATE INDEX IF NOT EXISTS idx_producto_tienda_config_inventario 
ON public.app_dat_producto (id, id_tienda) 
TABLESPACE pg_default;

-- 5. COMENTARIOS PARA DOCUMENTACIÓN
-- =====================================================
COMMENT ON CONSTRAINT chk_cantidad_final_conditional ON public.app_dat_inventario_productos IS 
'Constraint condicional: permite cantidades negativas si la tienda tiene permite_vender_aun_sin_disponibilidad=true, caso contrario requiere cantidad_final >= 0';

-- 6. VERIFICAR LA CONSTRAINT
-- =====================================================
-- Query para verificar que la constraint se aplicó correctamente
SELECT 
    conname as constraint_name,
    contype as constraint_type,
    pg_get_constraintdef(oid) as constraint_definition
FROM pg_constraint 
WHERE conrelid = 'public.app_dat_inventario_productos'::regclass
AND conname = 'chk_cantidad_final_conditional';

-- 7. EJEMPLOS DE PRUEBA
-- =====================================================
-- Estas queries te ayudan a probar la constraint

-- Ejemplo 1: Verificar configuración de una tienda específica
/*
SELECT 
    t.id as tienda_id,
    t.denominacion as tienda_nombre,
    ct.permite_vender_aun_sin_disponibilidad
FROM app_dat_tienda t
LEFT JOIN app_dat_configuracion_tienda ct ON t.id = ct.id_tienda
WHERE t.id = 11; -- Reemplaza con el ID de tu tienda
*/

-- Ejemplo 2: Probar inserción con cantidad negativa (debe funcionar si permite_vender_aun_sin_disponibilidad = true)
/*
-- NOTA: Solo ejecutar después de verificar la configuración de la tienda
INSERT INTO app_dat_inventario_productos (
    id_producto, 
    id_presentacion, 
    cantidad_inicial, 
    cantidad_final, 
    origen_cambio
) VALUES (
    123, -- ID de producto existente
    1,   -- ID de presentación existente
    10,  -- cantidad inicial
    -5,  -- cantidad final NEGATIVA
    1    -- origen del cambio
);
*/

-- 8. FUNCIÓN AUXILIAR PARA VERIFICAR CONSTRAINT
-- =====================================================
-- Función que te permite verificar si un producto puede tener cantidades negativas
CREATE OR REPLACE FUNCTION fn_puede_tener_cantidad_negativa(p_id_producto bigint)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
    v_permite_negativo boolean := false;
BEGIN
    SELECT ct.permite_vender_aun_sin_disponibilidad
    INTO v_permite_negativo
    FROM app_dat_producto p
    INNER JOIN app_dat_configuracion_tienda ct ON p.id_tienda = ct.id_tienda
    WHERE p.id = p_id_producto;
    
    RETURN COALESCE(v_permite_negativo, false);
END;
$$;

-- Ejemplo de uso de la función:
-- SELECT fn_puede_tener_cantidad_negativa(123); -- Reemplaza 123 con ID real

-- 9. LOGGING Y MONITOREO
-- =====================================================
COMMENT ON FUNCTION fn_puede_tener_cantidad_negativa(bigint) IS 
'Función auxiliar que verifica si un producto puede tener cantidades negativas basado en la configuración de su tienda';

-- =====================================================
-- INSTRUCCIONES DE USO:
-- =====================================================
-- 1. Ejecuta este script en tu base de datos
-- 2. Verifica que la constraint se creó correctamente con la query del paso 5
-- 3. Prueba con productos de tiendas que tengan diferentes configuraciones
-- 4. Usa la función fn_puede_tener_cantidad_negativa() para verificar comportamiento
-- 
-- COMPORTAMIENTO ESPERADO:
-- - Tienda con permite_vender_aun_sin_disponibilidad = true: Acepta cantidades negativas
-- - Tienda con permite_vender_aun_sin_disponibilidad = false: Rechaza cantidades negativas
-- - Si no existe configuración: Por defecto rechaza cantidades negativas (false)
-- =====================================================

PRINT 'Constraint condicional aplicada exitosamente';
PRINT 'La tabla app_dat_inventario_productos ahora permite cantidades negativas';
PRINT 'solo si la tienda tiene permite_vender_aun_sin_disponibilidad = true';
