-- Función para eliminar un producto completo y todos sus datos relacionados
-- Maneja las dependencias en el orden correcto para evitar errores de foreign key

CREATE OR REPLACE FUNCTION eliminar_producto_completo(
    p_id_producto BIGINT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSON;
    v_producto_existe BOOLEAN := FALSE;
    v_nombre_producto VARCHAR;
    v_registros_eliminados INTEGER := 0;
    v_tablas_afectadas TEXT[] := ARRAY[]::TEXT[];
    v_count INTEGER;
BEGIN
    -- Verificar si el producto existe
    SELECT EXISTS(SELECT 1 FROM app_dat_producto WHERE id = p_id_producto), 
           denominacion
    INTO v_producto_existe, v_nombre_producto
    FROM app_dat_producto 
    WHERE id = p_id_producto;
    
    IF NOT v_producto_existe THEN
        RETURN json_build_object(
            'success', false,
            'message', 'El producto con ID ' || p_id_producto || ' no existe',
            'producto_id', p_id_producto
        );
    END IF;

    -- Iniciar transacción
    BEGIN
        -- 1. Eliminar registros de tablas dependientes (en orden de dependencias)
        
        -- Tablas de marketing y promociones
        DELETE FROM app_mkt_promocion_productos WHERE id_producto = p_id_producto;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            v_registros_eliminados := v_registros_eliminados + v_count;
            v_tablas_afectadas := array_append(v_tablas_afectadas, 'app_mkt_promocion_productos (' || v_count || ')');
        END IF;

        -- Tablas de restaurante (si aplica)
        DELETE FROM app_rest_recetas WHERE id_producto_inventario = p_id_producto;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            v_registros_eliminados := v_registros_eliminados + v_count;
            v_tablas_afectadas := array_append(v_tablas_afectadas, 'app_rest_recetas (' || v_count || ')');
        END IF;

        DELETE FROM app_rest_modificaciones WHERE id_producto_inventario = p_id_producto;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            v_registros_eliminados := v_registros_eliminados + v_count;
            v_tablas_afectadas := array_append(v_tablas_afectadas, 'app_rest_modificaciones (' || v_count || ')');
        END IF;

        -- Tablas de inventario y movimientos
        DELETE FROM app_dat_inventario_productos WHERE id_producto = p_id_producto;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            v_registros_eliminados := v_registros_eliminados + v_count;
            v_tablas_afectadas := array_append(v_tablas_afectadas, 'app_dat_inventario_productos (' || v_count || ')');
        END IF;

        DELETE FROM app_dat_extraccion_productos WHERE id_producto = p_id_producto;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            v_registros_eliminados := v_registros_eliminados + v_count;
            v_tablas_afectadas := array_append(v_tablas_afectadas, 'app_dat_extraccion_productos (' || v_count || ')');
        END IF;

        DELETE FROM app_dat_recepcion_productos WHERE id_producto = p_id_producto;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            v_registros_eliminados := v_registros_eliminados + v_count;
            v_tablas_afectadas := array_append(v_tablas_afectadas, 'app_dat_recepcion_productos (' || v_count || ')');
        END IF;

        DELETE FROM app_dat_control_productos WHERE id_producto = p_id_producto;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            v_registros_eliminados := v_registros_eliminados + v_count;
            v_tablas_afectadas := array_append(v_tablas_afectadas, 'app_dat_control_productos (' || v_count || ')');
        END IF;

        DELETE FROM app_dat_ajuste_inventario WHERE id_producto = p_id_producto;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            v_registros_eliminados := v_registros_eliminados + v_count;
            v_tablas_afectadas := array_append(v_tablas_afectadas, 'app_dat_ajuste_inventario (' || v_count || ')');
        END IF;

        -- Tablas de pre-asignaciones
        DELETE FROM app_dat_pre_asignaciones WHERE id_producto = p_id_producto;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            v_registros_eliminados := v_registros_eliminados + v_count;
            v_tablas_afectadas := array_append(v_tablas_afectadas, 'app_dat_pre_asignaciones (' || v_count || ')');
        END IF;

        -- Tablas de garantías
        DELETE FROM app_dat_garantia_venta WHERE id_producto = p_id_producto;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            v_registros_eliminados := v_registros_eliminados + v_count;
            v_tablas_afectadas := array_append(v_tablas_afectadas, 'app_dat_garantia_venta (' || v_count || ')');
        END IF;

        DELETE FROM app_dat_producto_garantia WHERE id_producto = p_id_producto;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            v_registros_eliminados := v_registros_eliminados + v_count;
            v_tablas_afectadas := array_append(v_tablas_afectadas, 'app_dat_producto_garantia (' || v_count || ')');
        END IF;

        -- Tablas de códigos de barras
        DELETE FROM app_dat_codigos_barras WHERE id_producto = p_id_producto;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            v_registros_eliminados := v_registros_eliminados + v_count;
            v_tablas_afectadas := array_append(v_tablas_afectadas, 'app_dat_codigos_barras (' || v_count || ')');
        END IF;

        -- Tablas de precios
        DELETE FROM app_dat_precio_venta WHERE id_producto = p_id_producto;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            v_registros_eliminados := v_registros_eliminados + v_count;
            v_tablas_afectadas := array_append(v_tablas_afectadas, 'app_dat_precio_venta (' || v_count || ')');
        END IF;

        -- Tablas de almacén
        DELETE FROM app_dat_almacen_limites WHERE id_producto = p_id_producto;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            v_registros_eliminados := v_registros_eliminados + v_count;
            v_tablas_afectadas := array_append(v_tablas_afectadas, 'app_dat_almacen_limites (' || v_count || ')');
        END IF;

        -- Tablas de clasificación ABC
        DELETE FROM app_dat_producto_abc WHERE id_producto = p_id_producto;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            v_registros_eliminados := v_registros_eliminados + v_count;
            v_tablas_afectadas := array_append(v_tablas_afectadas, 'app_dat_producto_abc (' || v_count || ')');
        END IF;

        -- Tablas de etiquetas y multimedias
        DELETE FROM app_dat_producto_etiquetas WHERE id_producto = p_id_producto;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            v_registros_eliminados := v_registros_eliminados + v_count;
            v_tablas_afectadas := array_append(v_tablas_afectadas, 'app_dat_producto_etiquetas (' || v_count || ')');
        END IF;

        DELETE FROM app_dat_producto_multimedias WHERE id_producto = p_id_producto;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            v_registros_eliminados := v_registros_eliminados + v_count;
            v_tablas_afectadas := array_append(v_tablas_afectadas, 'app_dat_producto_multimedias (' || v_count || ')');
        END IF;

        -- Tablas de presentaciones (eliminar presentaciones huérfanas)
        DELETE FROM app_dat_producto_presentacion WHERE id_producto = p_id_producto;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            v_registros_eliminados := v_registros_eliminados + v_count;
            v_tablas_afectadas := array_append(v_tablas_afectadas, 'app_dat_producto_presentacion (' || v_count || ')');
        END IF;

        -- Tablas de subcategorías
        DELETE FROM app_dat_productos_subcategorias WHERE id_producto = p_id_producto;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            v_registros_eliminados := v_registros_eliminados + v_count;
            v_tablas_afectadas := array_append(v_tablas_afectadas, 'app_dat_productos_subcategorias (' || v_count || ')');
        END IF;

        -- Tablas de contabilidad
        DELETE FROM app_cont_margen_comercial WHERE id_producto = p_id_producto;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            v_registros_eliminados := v_registros_eliminados + v_count;
            v_tablas_afectadas := array_append(v_tablas_afectadas, 'app_cont_margen_comercial (' || v_count || ')');
        END IF;

        DELETE FROM app_cont_asignacion_costos WHERE id_producto = p_id_producto;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            v_registros_eliminados := v_registros_eliminados + v_count;
            v_tablas_afectadas := array_append(v_tablas_afectadas, 'app_cont_asignacion_costos (' || v_count || ')');
        END IF;

        -- 2. Finalmente, eliminar el producto principal
        DELETE FROM app_dat_producto WHERE id = p_id_producto;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            v_registros_eliminados := v_registros_eliminados + v_count;
            v_tablas_afectadas := array_append(v_tablas_afectadas, 'app_dat_producto (' || v_count || ')');
        END IF;

        -- Construir respuesta de éxito
        v_result := json_build_object(
            'success', true,
            'message', 'Producto "' || v_nombre_producto || '" eliminado exitosamente',
            'producto_id', p_id_producto,
            'nombre_producto', v_nombre_producto,
            'total_registros_eliminados', v_registros_eliminados,
            'tablas_afectadas', v_tablas_afectadas,
            'timestamp', NOW()
        );

        RETURN v_result;

    EXCEPTION
        WHEN OTHERS THEN
            -- En caso de error, hacer rollback automático
            RAISE EXCEPTION 'Error al eliminar producto: %', SQLERRM;
    END;

END;
$$;

-- Comentarios sobre el uso:
-- CALL eliminar_producto_completo(123);
-- 
-- Esta función:
-- 1. Verifica que el producto exista
-- 2. Elimina todos los registros relacionados en orden correcto
-- 3. Elimina el producto principal
-- 4. Retorna un JSON con detalles de la operación
-- 5. Maneja errores con rollback automático
--
-- IMPORTANTE: Esta operación es IRREVERSIBLE. Asegúrate de hacer backup antes de usar.
