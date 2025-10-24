-- =====================================================
-- TRIGGER: NOTIFICAR PRODUCTO AGOTADO
-- =====================================================
-- Notifica a vendedores, supervisores, gerentes y almaceneros
-- cuando un producto se agota (cantidad_final = 0 y cantidad_inicial > 0)
-- =====================================================

-- Función para notificar producto agotado
CREATE OR REPLACE FUNCTION fn_notificar_producto_agotado()
RETURNS TRIGGER AS $$
DECLARE
    v_id_tienda BIGINT;
    v_id_almacen BIGINT;
    v_producto_nombre VARCHAR;
    v_variante_nombre VARCHAR := '';
    v_opcion_nombre VARCHAR := '';
    v_ubicacion_nombre VARCHAR := '';
    v_almacen_nombre VARCHAR := '';
    v_mensaje TEXT;
    v_data JSONB;
    v_user_uuid UUID;
BEGIN
    -- Solo procesar si cantidad_final es 0 y cantidad_inicial es mayor que 0
    IF NEW.cantidad_final = 0 AND NEW.cantidad_inicial > 0 THEN
        
        -- Obtener información del producto y tienda
        SELECT 
            p.denominacion,
            p.id_tienda
        INTO 
            v_producto_nombre,
            v_id_tienda
        FROM app_dat_producto p
        WHERE p.id = NEW.id_producto;
        
        -- Obtener nombre de variante si existe
        IF NEW.id_variante IS NOT NULL THEN
            SELECT 
                a.denominacion
            INTO 
                v_variante_nombre
            FROM app_dat_variantes v
            JOIN app_dat_atributos a ON v.id_atributo = a.id
            WHERE v.id = NEW.id_variante;
            
            v_variante_nombre := ' - ' || v_variante_nombre;
        END IF;
        
        -- Obtener nombre de opción de variante si existe
        IF NEW.id_opcion_variante IS NOT NULL THEN
            SELECT 
                valor
            INTO 
                v_opcion_nombre
            FROM app_dat_atributo_opcion
            WHERE id = NEW.id_opcion_variante;
            
            v_opcion_nombre := ': ' || v_opcion_nombre;
        END IF;
        
        -- Obtener ubicación y almacén
        IF NEW.id_ubicacion IS NOT NULL THEN
            SELECT 
                la.denominacion,
                la.id_almacen,
                a.denominacion
            INTO 
                v_ubicacion_nombre,
                v_id_almacen,
                v_almacen_nombre
            FROM app_dat_layout_almacen la
            JOIN app_dat_almacen a ON la.id_almacen = a.id
            WHERE la.id = NEW.id_ubicacion;
            
            v_ubicacion_nombre := ' en ' || v_ubicacion_nombre;
            v_almacen_nombre := ' (Almacén: ' || v_almacen_nombre || ')';
        END IF;
        
        -- Construir mensaje
        v_mensaje := 'El producto "' || v_producto_nombre || v_variante_nombre || v_opcion_nombre || 
                     '" se ha agotado completamente' || v_ubicacion_nombre || v_almacen_nombre;
        
        -- Construir data JSON
        v_data := jsonb_build_object(
            'id_producto', NEW.id_producto,
            'id_variante', NEW.id_variante,
            'id_opcion_variante', NEW.id_opcion_variante,
            'id_ubicacion', NEW.id_ubicacion,
            'id_almacen', v_id_almacen,
            'producto_nombre', v_producto_nombre,
            'cantidad_anterior', NEW.cantidad_inicial
        );
        
        -- ===================================
        -- NOTIFICAR A VENDEDORES
        -- ===================================
        -- Obtener vendedores a través de TPV de la tienda
        FOR v_user_uuid IN
            SELECT DISTINCT v.uuid
            FROM app_dat_vendedor v
            JOIN app_dat_tpv tpv ON v.id_tpv = tpv.id
            WHERE tpv.id_tienda = v_id_tienda
              AND v.uuid IS NOT NULL
        LOOP
            PERFORM fn_crear_notificacion(
                v_user_uuid,
                'inventario',
                '⚠️ Producto Agotado',
                v_mensaje,
                v_data,
                'alta'
            );
        END LOOP;
        
        -- ===================================
        -- NOTIFICAR A SUPERVISORES
        -- ===================================
        FOR v_user_uuid IN
            SELECT DISTINCT uuid
            FROM app_dat_supervisor
            WHERE id_tienda = v_id_tienda
              AND uuid IS NOT NULL
        LOOP
            PERFORM fn_crear_notificacion(
                v_user_uuid,
                'inventario',
                '⚠️ Producto Agotado',
                v_mensaje,
                v_data,
                'alta'
            );
        END LOOP;
        
        -- ===================================
        -- NOTIFICAR A GERENTES
        -- ===================================
        FOR v_user_uuid IN
            SELECT DISTINCT uuid
            FROM app_dat_gerente
            WHERE id_tienda = v_id_tienda
              AND uuid IS NOT NULL
        LOOP
            PERFORM fn_crear_notificacion(
                v_user_uuid,
                'inventario',
                '⚠️ Producto Agotado',
                v_mensaje,
                v_data,
                'alta'
            );
        END LOOP;
        
        -- ===================================
        -- NOTIFICAR A ALMACENEROS
        -- ===================================
        -- Solo notificar a almaceneros del almacén específico donde se agotó
        IF v_id_almacen IS NOT NULL THEN
            FOR v_user_uuid IN
                SELECT DISTINCT uuid
                FROM app_dat_almacenero
                WHERE id_almacen = v_id_almacen
                  AND uuid IS NOT NULL
            LOOP
                PERFORM fn_crear_notificacion(
                    v_user_uuid,
                    'inventario',
                    '⚠️ Producto Agotado',
                    v_mensaje,
                    v_data,
                    'urgente'  -- Urgente para almaceneros
                );
            END LOOP;
        END IF;
        
        -- Log para debugging
        RAISE NOTICE 'Notificaciones enviadas para producto agotado: % (ID: %)', v_producto_nombre, NEW.id_producto;
        
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Crear trigger AFTER UPDATE en app_dat_inventario_productos
DROP TRIGGER IF EXISTS trg_notificar_producto_agotado ON app_dat_inventario_productos;

CREATE TRIGGER trg_notificar_producto_agotado
    AFTER UPDATE OF cantidad_final ON app_dat_inventario_productos
    FOR EACH ROW
    WHEN (NEW.cantidad_final = 0 AND NEW.cantidad_inicial > 0)
    EXECUTE FUNCTION fn_notificar_producto_agotado();

-- Comentarios
COMMENT ON FUNCTION fn_notificar_producto_agotado() IS 
'Función que notifica a vendedores, supervisores, gerentes y almaceneros cuando un producto se agota completamente';

COMMENT ON TRIGGER trg_notificar_producto_agotado ON app_dat_inventario_productos IS 
'Trigger que ejecuta notificaciones cuando cantidad_final llega a 0 desde una cantidad_inicial mayor a 0';

-- =====================================================
-- PRUEBA DEL TRIGGER
-- =====================================================
-- Para probar, actualiza un registro de inventario:
/*
UPDATE app_dat_inventario_productos
SET cantidad_final = 0
WHERE id = <ID_DEL_REGISTRO>
  AND cantidad_inicial > 0;

-- Verificar notificaciones creadas:
SELECT * FROM app_dat_notificaciones
WHERE tipo = 'inventario'
  AND titulo LIKE '%Producto Agotado%'
ORDER BY created_at DESC
LIMIT 10;
*/
