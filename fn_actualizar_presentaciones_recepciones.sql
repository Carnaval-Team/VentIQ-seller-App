-- Función para actualizar presentaciones faltantes en operaciones de recepción
-- Busca productos de una tienda y verifica sus recepciones, asignando la primera presentación disponible si falta

CREATE OR REPLACE FUNCTION fn_actualizar_presentaciones_recepciones(
    p_id_tienda BIGINT
)
RETURNS TABLE (
    id_recepcion BIGINT,
    id_producto BIGINT,
    nombre_producto VARCHAR,
    sku_producto VARCHAR,
    presentacion_anterior BIGINT,
    presentacion_nueva BIGINT,
    nombre_presentacion_nueva VARCHAR,
    actualizado BOOLEAN
) 
LANGUAGE plpgsql
AS $$
DECLARE
    rec_producto RECORD;
    rec_recepcion RECORD;
    primera_presentacion RECORD;
    registros_actualizados INTEGER := 0;
BEGIN
    RAISE NOTICE '🔍 Iniciando actualización de presentaciones en recepciones para tienda ID: %', p_id_tienda;

    -- Iterar sobre todos los productos de la tienda especificada
    FOR rec_producto IN 
        SELECT 
            p.id,
            p.denominacion,
            p.sku,
            p.es_vendible,
            p.es_comprable,
            p.deleted_at
        FROM app_dat_producto p
        WHERE p.id_tienda = p_id_tienda
          AND p.deleted_at IS NULL
          AND p.es_comprable = true
        ORDER BY p.denominacion
    LOOP
        RAISE NOTICE '📦 Procesando producto: % (ID: %)', rec_producto.denominacion, rec_producto.id;
        
        -- Buscar todas las recepciones de este producto que no tienen presentación
        FOR rec_recepcion IN
            SELECT 
                rp.id,
                rp.id_operacion,
                rp.id_producto,
                rp.id_presentacion,
                rp.cantidad,
                o.created_at as fecha_operacion
            FROM app_dat_recepcion_productos rp
            INNER JOIN app_dat_operaciones o ON rp.id_operacion = o.id
            WHERE rp.id_producto = rec_producto.id
              AND o.id_tienda = p_id_tienda
              AND rp.id_presentacion IS NULL
            ORDER BY o.created_at DESC
        LOOP
            -- Buscar la primera presentación disponible para este producto
            SELECT 
                pp.id,
                pp.id_presentacion,
                np.denominacion as nombre_presentacion,
                pp.es_base
            INTO primera_presentacion
            FROM app_dat_producto_presentacion pp
            INNER JOIN app_nom_presentacion np ON pp.id_presentacion = np.id
            WHERE pp.id_producto = rec_producto.id
            ORDER BY pp.es_base DESC, pp.id ASC
            LIMIT 1;

            -- Si encontramos una presentación, actualizar la recepción
            IF primera_presentacion.id IS NOT NULL THEN
                RAISE NOTICE '✅ Actualizando recepción ID: % con presentación: %', 
                            rec_recepcion.id, primera_presentacion.nombre_presentacion;
                
                -- Actualizar la recepción con la presentación encontrada
                UPDATE app_dat_recepcion_productos 
                SET id_presentacion = primera_presentacion.id
                WHERE id = rec_recepcion.id;

                -- Retornar resultado usando RETURN NEXT
                id_recepcion := rec_recepcion.id;
                id_producto := rec_producto.id;
                nombre_producto := rec_producto.denominacion;
                sku_producto := rec_producto.sku;
                presentacion_anterior := rec_recepcion.id_presentacion; -- NULL
                presentacion_nueva := primera_presentacion.id;
                nombre_presentacion_nueva := primera_presentacion.nombre_presentacion;
                actualizado := true;
                
                RETURN NEXT;
                registros_actualizados := registros_actualizados + 1;
            ELSE
                RAISE NOTICE '⚠️  No se encontró presentación disponible para recepción ID: %', rec_recepcion.id;
                
                -- No se encontró presentación disponible - retornar registro sin actualizar
                id_recepcion := rec_recepcion.id;
                id_producto := rec_producto.id;
                nombre_producto := rec_producto.denominacion;
                sku_producto := rec_producto.sku;
                presentacion_anterior := rec_recepcion.id_presentacion; -- NULL
                presentacion_nueva := NULL;
                nombre_presentacion_nueva := 'SIN PRESENTACIÓN DISPONIBLE';
                actualizado := false;
                
                RETURN NEXT;
            END IF;
        END LOOP;
    END LOOP;

    -- Log final de la operación
    RAISE NOTICE '';
    RAISE NOTICE '✅ ========================================';
    RAISE NOTICE '✅ Función ejecutada exitosamente';
    RAISE NOTICE '✅ Registros actualizados: %', registros_actualizados;
    RAISE NOTICE '✅ ========================================';
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '❌ Error durante el proceso: %', SQLERRM;
        RAISE EXCEPTION 'Error en fn_actualizar_presentaciones_recepciones: %', SQLERRM;
END;
$$;

-- Comentarios sobre la función:
-- 1. Busca todos los productos comprables y activos de la tienda especificada
-- 2. Para cada producto, encuentra las recepciones que no tienen presentación asignada
-- 3. Busca la primera presentación disponible del producto (priorizando la presentación base)
-- 4. Actualiza la recepción con la presentación encontrada
-- 5. Retorna un detalle de todas las operaciones realizadas

-- Ejemplos de uso:
-- Para actualizar todas las recepciones de la tienda 1:
-- SELECT * FROM fn_actualizar_presentaciones_recepciones(1);

-- Para ver solo las actualizaciones exitosas:
-- SELECT * FROM fn_actualizar_presentaciones_recepciones(1) WHERE actualizado = true;

-- Para contar cuántas recepciones se actualizaron:
-- SELECT COUNT(*) as total_actualizados FROM fn_actualizar_presentaciones_recepciones(1) WHERE actualizado = true;
