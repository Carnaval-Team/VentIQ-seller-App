-- Trigger para sincronizar precios de app_dat_precio_venta a carnavalapp.Productos
-- Cuando se actualiza el precio de venta de un producto, busca el producto en app_dat_producto
-- y actualiza los precios en carnavalapp.Productos usando id_vendedor_app

-- Primero, crear la función que se ejecutará cuando se active el trigger
CREATE OR REPLACE FUNCTION sync_price_to_carnaval()
RETURNS TRIGGER AS $$
DECLARE
    v_id_vendedor_app INTEGER;
    v_base_price NUMERIC;
    v_precio_descuento INTEGER;
    v_precio_oficial NUMERIC;
BEGIN
    -- Solo procesar si es un INSERT o UPDATE
    IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
        -- Obtener el id_vendedor_app del producto
        SELECT id_vendedor_app 
        INTO v_id_vendedor_app
        FROM public.app_dat_producto
        WHERE id = NEW.id_producto;

        -- Solo continuar si id_vendedor_app no es NULL
        IF v_id_vendedor_app IS NOT NULL THEN
            -- Obtener el precio base (precio_venta_cup del nuevo registro)
            v_base_price := NEW.precio_venta_cup;

            -- Calcular precios con markup:
            -- precio_descuento = basePrice + 5.35% (redondeado a entero)
            -- price (oficial) = basePrice + 11%
            v_precio_descuento := ROUND(v_base_price * 1.0535);
            v_precio_oficial := v_base_price * 1.11;

            -- Actualizar los precios en carnavalapp.Productos
            UPDATE carnavalapp."Productos"
            SET 
                price = v_precio_oficial,
                precio_descuento = v_precio_descuento,
                updated_at = NOW()
            WHERE id = v_id_vendedor_app;

            RAISE NOTICE 'Precios actualizados en Carnaval para producto ID %: precio_oficial=%, precio_descuento=%', 
                v_id_vendedor_app, v_precio_oficial, v_precio_descuento;
        ELSE
            RAISE NOTICE 'Producto ID % no tiene id_vendedor_app, no se sincroniza con Carnaval', NEW.id_producto;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Eliminar el trigger si ya existe
DROP TRIGGER IF EXISTS trigger_sync_price_to_carnaval ON public.app_dat_precio_venta;

-- Crear el trigger que se ejecuta AFTER INSERT OR UPDATE
-- Se ejecuta después de insertar o actualizar un registro en app_dat_precio_venta
CREATE TRIGGER trigger_sync_price_to_carnaval
    AFTER INSERT OR UPDATE ON public.app_dat_precio_venta
    FOR EACH ROW
    EXECUTE FUNCTION sync_price_to_carnaval();

-- Comentario explicativo
COMMENT ON TRIGGER trigger_sync_price_to_carnaval ON public.app_dat_precio_venta IS 
'Sincroniza automáticamente los precios de productos a carnavalapp.Productos cuando se actualiza app_dat_precio_venta. 
Aplica markup de 5.35% para precio_descuento (redondeado) y 11% para price (oficial).';
