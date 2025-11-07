-- Script para agregar el campo maneja_inventario a la tabla app_dat_configuracion_tienda
-- Este script es idempotente (se puede ejecutar múltiples veces sin causar errores)

-- Agregar la columna maneja_inventario si no existe
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'app_dat_configuracion_tienda' 
        AND column_name = 'maneja_inventario'
    ) THEN
        ALTER TABLE public.app_dat_configuracion_tienda 
        ADD COLUMN maneja_inventario boolean NULL DEFAULT false;
        
        RAISE NOTICE 'Columna maneja_inventario agregada exitosamente';
    ELSE
        RAISE NOTICE 'La columna maneja_inventario ya existe';
    END IF;
END $$;

-- Actualizar registros existentes que tengan NULL a false (valor por defecto)
UPDATE public.app_dat_configuracion_tienda 
SET maneja_inventario = false 
WHERE maneja_inventario IS NULL;

-- Comentario de la columna para documentación
COMMENT ON COLUMN public.app_dat_configuracion_tienda.maneja_inventario IS 
'Indica si los vendedores deben hacer control de inventario al abrir y cerrar turno. true = control activo, false = sin control';

-- Verificar el resultado
SELECT 
    column_name, 
    data_type, 
    is_nullable, 
    column_default
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'app_dat_configuracion_tienda'
AND column_name = 'maneja_inventario';
