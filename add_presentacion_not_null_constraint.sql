-- Script para agregar constraint NOT NULL a id_presentacion
-- IMPORTANTE: Ejecutar DESPUÉS de fix_inventario_presentaciones.sql

-- Verificar que no hay registros con id_presentacion NULL antes de agregar constraint
DO $$
DECLARE
    registros_null INT;
BEGIN
    SELECT COUNT(*) INTO registros_null
    FROM app_dat_inventario_productos
    WHERE id_presentacion IS NULL;
    
    IF registros_null > 0 THEN
        RAISE EXCEPTION '❌ Aún hay % registros con id_presentacion NULL. Ejecuta primero fix_inventario_presentaciones.sql', registros_null;
    ELSE
        RAISE NOTICE '✅ Todos los registros tienen id_presentacion asignado';
        RAISE NOTICE '✅ Procediendo a agregar constraint NOT NULL...';
    END IF;
END $$;

-- Agregar constraint NOT NULL a id_presentacion
ALTER TABLE app_dat_inventario_productos 
ALTER COLUMN id_presentacion SET NOT NULL;

RAISE NOTICE '✅ ========================================';
RAISE NOTICE '✅ Constraint NOT NULL agregado exitosamente';
RAISE NOTICE '✅ La columna id_presentacion ahora es obligatoria';
RAISE NOTICE '✅ ========================================';
