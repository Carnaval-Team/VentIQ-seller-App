-- Función para inicializar inventario de productos faltantes en un almacén
-- Busca productos que no tienen operaciones de inventario en la primera ubicación del almacén
-- y les crea una operación inicial con cantidad 0
-- También busca o crea la relación producto_presentacion con presentación ID 1 para cada producto

CREATE OR REPLACE FUNCTION fn_inicializar_inventario_productos_faltantes(
    p_id_almacen BIGINT,
    p_uuid_usuario UUID DEFAULT NULL
)
RETURNS TABLE (
    success BOOLEAN,
    productos_procesados INTEGER,
    productos_insertados INTEGER,
    message TEXT,
    detalles JSONB
) 
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_tienda BIGINT;
    v_primera_ubicacion BIGINT;
    v_id_tipo_operacion_inicial BIGINT;
    v_productos_sin_inventario INTEGER := 0;
    v_productos_insertados INTEGER := 0;
    v_productos_procesados INTEGER := 0;
    v_detalles JSONB := '[]'::jsonb;
    v_producto RECORD;
    v_nueva_operacion BIGINT;
    v_nuevo_inventario BIGINT;
    v_id_producto_presentacion BIGINT;
    v_success BOOLEAN := TRUE;
    v_message TEXT := '';
BEGIN
    -- Validar que el almacén existe y obtener la tienda
    SELECT a.id_tienda INTO v_id_tienda
    FROM app_dat_almacen a
    WHERE a.id = p_id_almacen AND a.deleted_at IS NULL;
    
    IF v_id_tienda IS NULL THEN
        RAISE EXCEPTION 'Almacén con ID % no encontrado o está eliminado', p_id_almacen;
    END IF;
    
    -- Obtener la primera ubicación del almacén (layout principal)
    SELECT la.id INTO v_primera_ubicacion
    FROM app_dat_layout_almacen la
    WHERE la.id_almacen = p_id_almacen 
      AND la.deleted_at IS NULL
      AND la.id_layout_padre IS NULL  -- Primera ubicación (sin padre)
    ORDER BY la.id ASC
    LIMIT 1;
    
    IF v_primera_ubicacion IS NULL THEN
        RAISE EXCEPTION 'No se encontró una ubicación principal para el almacén con ID %', p_id_almacen;
    END IF;
    
    -- Obtener el tipo de operación para "Inventario Inicial" o similar
    -- Asumiendo que existe un tipo de operación con ID 8 para inventario inicial
    -- Si no existe, usar el tipo de operación de "Ajuste de Inventario" (ID 3)
    SELECT id INTO v_id_tipo_operacion_inicial
    FROM app_nom_tipo_operacion
    WHERE denominacion ILIKE '%inicial%' OR denominacion ILIKE '%ajuste%'
    ORDER BY CASE 
        WHEN denominacion ILIKE '%inicial%' THEN 1
        WHEN denominacion ILIKE '%ajuste%' THEN 2
        ELSE 3
    END
    LIMIT 1;
    
    IF v_id_tipo_operacion_inicial IS NULL THEN
        -- Si no existe, usar ID 3 por defecto (Ajuste de Inventario según el contexto)
        v_id_tipo_operacion_inicial := 3;
    END IF;
    
    -- Buscar productos que no tienen operaciones de inventario en la primera ubicación
    FOR v_producto IN
        SELECT 
            p.id,
            p.denominacion,
            p.sku
        FROM app_dat_producto p
        WHERE p.id_tienda = v_id_tienda
          AND p.deleted_at IS NULL
          AND p.es_inventariable = true
          AND NOT EXISTS (
              SELECT 1 
              FROM app_dat_inventario_productos ip
              WHERE ip.id_producto = p.id
                AND ip.id_ubicacion = v_primera_ubicacion
          )
        ORDER BY p.denominacion
    LOOP
        v_productos_procesados := v_productos_procesados + 1;
        
        BEGIN
            -- Buscar o crear la relación producto_presentacion con presentación ID 1
            SELECT pp.id INTO v_id_producto_presentacion
            FROM app_dat_producto_presentacion pp
            WHERE pp.id_producto = v_producto.id 
              AND pp.id_presentacion = 1;
            
            -- Si no existe la relación, crearla
            IF v_id_producto_presentacion IS NULL THEN
                INSERT INTO app_dat_producto_presentacion (
                    id_producto,
                    id_presentacion,
                    created_at
                ) VALUES (
                    v_producto.id,
                    1,  -- Presentación ID 1
                    NOW()
                ) RETURNING id INTO v_id_producto_presentacion;
            END IF;
            
            -- Crear una nueva operación
            INSERT INTO app_dat_operaciones (
                id_tipo_operacion,
                uuid,
                id_tienda,
                observaciones,
                created_at
            ) VALUES (
                v_id_tipo_operacion_inicial,
                p_uuid_usuario,
                v_id_tienda,
                'Inicialización automática de inventario - Producto: ' || v_producto.denominacion,
                NOW()
            ) RETURNING id INTO v_nueva_operacion;
            
            -- Crear el registro de inventario inicial
            INSERT INTO app_dat_inventario_productos (
                id_producto,
                id_variante,
                id_opcion_variante,
                id_ubicacion,
                id_presentacion,
                cantidad_inicial,
                cantidad_final,
                sku_producto,
                sku_ubicacion,
                origen_cambio,
                created_at
            ) VALUES (
                v_producto.id,
                NULL,  -- Sin variante específica
                NULL,  -- Sin opción de variante
                v_primera_ubicacion,
                v_id_producto_presentacion,  -- Sin presentación específica
                0,     -- Cantidad inicial 0
                0,     -- Cantidad final 0
                v_producto.sku,
                (SELECT sku_codigo FROM app_dat_layout_almacen WHERE id = v_primera_ubicacion),
                2,     -- Origen de cambio 2 (según especificación)
                NOW()
            ) RETURNING id INTO v_nuevo_inventario;
            
            v_productos_insertados := v_productos_insertados + 1;
            
            -- Agregar detalles del producto procesado
            v_detalles := v_detalles || jsonb_build_object(
                'producto_id', v_producto.id,
                'producto_nombre', v_producto.denominacion,
                'producto_sku', v_producto.sku,
                'operacion_id', v_nueva_operacion,
                'inventario_id', v_nuevo_inventario,
                'ubicacion_id', v_primera_ubicacion,
                'producto_presentacion_id', v_id_producto_presentacion,
                'presentacion_id', 1,
                'estado', 'insertado'
            );
            
        EXCEPTION WHEN OTHERS THEN
            -- En caso de error, agregar a los detalles pero continuar
            v_detalles := v_detalles || jsonb_build_object(
                'producto_id', v_producto.id,
                'producto_nombre', v_producto.denominacion,
                'producto_sku', v_producto.sku,
                'error', SQLERRM,
                'estado', 'error'
            );
        END;
    END LOOP;
    
    -- Generar mensaje descriptivo
    IF v_productos_procesados = 0 THEN
        v_message := 'No se encontraron productos sin inventario en este almacén. Todos los productos ya tienen registros de inventario.';
    ELSIF v_productos_insertados = 0 THEN
        v_message := FORMAT('Se procesaron %s productos pero no se pudo insertar ningún registro de inventario. Revisa los errores en los detalles.', v_productos_procesados);
        v_success := FALSE;
    ELSIF v_productos_insertados = v_productos_procesados THEN
        v_message := FORMAT('¡Inicialización completada exitosamente! Se procesaron %s productos y se crearon %s registros de inventario inicial.', v_productos_procesados, v_productos_insertados);
    ELSE
        v_message := FORMAT('Inicialización parcialmente completada. Se procesaron %s productos, se insertaron %s registros exitosamente y %s tuvieron errores.', 
                          v_productos_procesados, v_productos_insertados, (v_productos_procesados - v_productos_insertados));
    END IF;

    -- Retornar resultados
    RETURN QUERY SELECT 
        v_success,
        v_productos_procesados,
        v_productos_insertados,
        v_message,
        v_detalles;
        
EXCEPTION WHEN OTHERS THEN
    -- Capturar errores generales de la función
    v_success := FALSE;
    v_message := FORMAT('Error general en la función: %s', SQLERRM);
    v_detalles := jsonb_build_array(
        jsonb_build_object(
            'error_general', SQLERRM,
            'estado', 'error_critico'
        )
    );
    
    RETURN QUERY SELECT 
        v_success,
        v_productos_procesados,
        v_productos_insertados,
        v_message,
        v_detalles;
        
END;
$$;

-- Comentarios sobre valores necesarios para insertar la operación:
/*
VALORES REQUERIDOS PARA INSERTAR UNA OPERACIÓN DE INVENTARIO:

1. **app_dat_operaciones** (Operación principal):
   - id_tipo_operacion: BIGINT (Requerido) - Tipo de operación de inventario
   - uuid: UUID (Opcional) - Usuario que realiza la operación
   - id_tienda: BIGINT (Requerido) - ID de la tienda
   - observaciones: VARCHAR (Opcional) - Comentarios sobre la operación

2. **app_dat_inventario_productos** (Registro de inventario):
   - id_producto: BIGINT (Requerido) - ID del producto
   - id_ubicacion: BIGINT (Requerido) - ID de la ubicación en el almacén
   - id_presentacion: BIGINT (Requerido) - ID de la relación producto_presentacion
   - cantidad_inicial: NUMERIC (Requerido) - Cantidad inicial (0 en este caso)
   - cantidad_final: NUMERIC (Opcional) - Cantidad final (0 en este caso)
   - origen_cambio: SMALLINT (Requerido) - Valor 2 según especificación
   - sku_producto: VARCHAR (Opcional) - SKU del producto
   - sku_ubicacion: VARCHAR (Opcional) - SKU de la ubicación

3. **app_dat_producto_presentacion** (Relación producto-presentación):
   - id_producto: BIGINT (Requerido) - ID del producto
   - id_presentacion: BIGINT (Requerido) - ID de la presentación (siempre 1)
   - Se busca primero si existe, si no se crea automáticamente

VALORES ADICIONALES NECESARIOS:
- **p_uuid_usuario**: UUID del usuario que ejecuta la función (opcional)
- **Tipo de operación**: Se busca automáticamente un tipo "inicial" o "ajuste"
- **Primera ubicación**: Se obtiene automáticamente la primera ubicación del almacén

EJEMPLO DE USO:
SELECT * FROM fn_inicializar_inventario_productos_faltantes(
    p_id_almacen := 1,
    p_uuid_usuario := 'uuid-del-usuario'::uuid
);

FORMATO DE RESPUESTA:
La función retorna una tabla con los siguientes campos:
- success: BOOLEAN - Indica si la operación fue exitosa
- productos_procesados: INTEGER - Número total de productos evaluados
- productos_insertados: INTEGER - Número de productos con inventario creado exitosamente
- message: TEXT - Mensaje descriptivo del resultado de la operación
- detalles: JSONB - Array con detalles de cada producto procesado

EJEMPLOS DE MENSAJES:
- "No se encontraron productos sin inventario en este almacén..."
- "¡Inicialización completada exitosamente! Se procesaron X productos..."
- "Inicialización parcialmente completada. Se procesaron X productos..."
- "Error general en la función: [detalle del error]"
*/
