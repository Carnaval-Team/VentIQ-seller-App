-- Script optimizado para Supabase
-- Corrige presentaciones faltantes en inventario

-- Paso 1: Crear función temporal para el proceso
CREATE OR REPLACE FUNCTION fix_inventario_presentaciones()
RETURNS TABLE(
    presentaciones_creadas INT,
    registros_actualizados INT,
    mensaje TEXT
) 
LANGUAGE plpgsql
AS $$
DECLARE
    producto_record RECORD;
    presentacion_base_id BIGINT;
    v_presentaciones_creadas INT := 0;
    v_registros_actualizados INT := 0;
    v_rows_affected INT;
BEGIN
    -- Iterar sobre cada producto único en inventario que tiene id_presentacion NULL
    FOR producto_record IN 
        SELECT DISTINCT id_producto 
        FROM app_dat_inventario_productos 
        WHERE id_presentacion IS NULL
    LOOP
        -- Buscar si existe una presentación base para este producto
        SELECT id INTO presentacion_base_id
        FROM app_dat_producto_presentacion
        WHERE id_producto = producto_record.id_producto
          AND id_presentacion = 1
          AND cantidad = 1
          AND es_base = true
        LIMIT 1;
        
        -- Si no existe la presentación base, crearla
        IF presentacion_base_id IS NULL THEN
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
            
            v_presentaciones_creadas := v_presentaciones_creadas + 1;
        END IF;
        
        -- Actualizar todos los registros de inventario de este producto
        UPDATE app_dat_inventario_productos
        SET id_presentacion = presentacion_base_id
        WHERE id_producto = producto_record.id_producto
          AND id_presentacion IS NULL;
        
        GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
        v_registros_actualizados := v_registros_actualizados + v_rows_affected;
    END LOOP;
    
    RETURN QUERY SELECT 
        v_presentaciones_creadas,
        v_registros_actualizados,
        format('✅ Proceso completado: %s presentaciones creadas, %s registros actualizados', 
               v_presentaciones_creadas, v_registros_actualizados)::TEXT;
END;
$$;

-- Paso 2: Ejecutar la función
SELECT * FROM fix_inventario_presentaciones();

-- Paso 3: Verificar resultados
SELECT 
    COUNT(*) as registros_sin_presentacion
FROM app_dat_inventario_productos
WHERE id_presentacion IS NULL;

-- Paso 4: Limpiar (opcional - comentado por seguridad)
-- DROP FUNCTION IF EXISTS fix_inventario_presentaciones();
