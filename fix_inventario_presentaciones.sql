-- Script para corregir presentaciones faltantes en inventario
-- Busca productos en inventario sin presentación (id_presentacion IS NULL)
-- y les asigna o crea una presentación base

DO $$
DECLARE
    producto_record RECORD;
    presentacion_base_id BIGINT;
    productos_actualizados INT := 0;
    presentaciones_creadas INT := 0;
    filas_afectadas INT;
BEGIN
    RAISE NOTICE '🔍 Iniciando corrección de presentaciones en inventario...';
    
    -- Iterar sobre cada producto único en inventario que tiene id_presentacion NULL
    FOR producto_record IN 
        SELECT DISTINCT id_producto 
        FROM app_dat_inventario_productos 
        WHERE id_presentacion IS NULL
    LOOP
        RAISE NOTICE '📦 Procesando producto ID: %', producto_record.id_producto;
        
        -- Buscar si existe una presentación base para este producto
        -- (id_presentacion = 1, cantidad = 1.0, es_base = true)
        SELECT id INTO presentacion_base_id
        FROM app_dat_producto_presentacion
        WHERE id_producto = producto_record.id_producto
          AND id_presentacion = 1
          AND cantidad = 1.0
          AND es_base = true
        LIMIT 1;
        
        -- Si no existe la presentación base, crearla
        IF presentacion_base_id IS NULL THEN
            RAISE NOTICE '➕ Creando presentación base para producto ID: %', producto_record.id_producto;
            
            INSERT INTO app_dat_producto_presentacion (
                id_producto,
                id_presentacion,
                cantidad,
                es_base
            ) VALUES (
                producto_record.id_producto,
                1,
                1,
                true
            )
            RETURNING id INTO presentacion_base_id;
            
            presentaciones_creadas := presentaciones_creadas + 1;
            RAISE NOTICE '✅ Presentación base creada con ID: %', presentacion_base_id;
        ELSE
            RAISE NOTICE '✓ Presentación base ya existe con ID: %', presentacion_base_id;
        END IF;
        
        -- Actualizar todos los registros de inventario de este producto que tienen id_presentacion NULL
        UPDATE app_dat_inventario_productos
        SET id_presentacion = presentacion_base_id
        WHERE id_producto = producto_record.id_producto
          AND id_presentacion IS NULL;
        
        GET DIAGNOSTICS filas_afectadas = ROW_COUNT;
        productos_actualizados := productos_actualizados + filas_afectadas;
        
        RAISE NOTICE '📝 Registros de inventario actualizados para producto ID %: %', 
                     producto_record.id_producto, filas_afectadas;
    END LOOP;
    
    RAISE NOTICE '';
    RAISE NOTICE '✅ ========================================';
    RAISE NOTICE '✅ Proceso completado exitosamente';
    RAISE NOTICE '✅ Presentaciones base creadas: %', presentaciones_creadas;
    RAISE NOTICE '✅ Registros de inventario actualizados: %', productos_actualizados;
    RAISE NOTICE '✅ ========================================';
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '❌ Error durante el proceso: %', SQLERRM;
        RAISE EXCEPTION 'Error: %', SQLERRM;
END $$;

-- Verificación final: Contar cuántos registros aún tienen id_presentacion NULL
DO $$
DECLARE
    registros_pendientes INT;
BEGIN
    SELECT COUNT(*) INTO registros_pendientes
    FROM app_dat_inventario_productos
    WHERE id_presentacion IS NULL;
    
    IF registros_pendientes > 0 THEN
        RAISE NOTICE '⚠️  Aún quedan % registros con id_presentacion NULL', registros_pendientes;
    ELSE
        RAISE NOTICE '✅ Todos los registros de inventario tienen presentación asignada';
    END IF;
END $$;
