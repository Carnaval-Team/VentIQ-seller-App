-- ============================================================
-- Migración / Script: Trigger para convertir UPDATE de precios en INSERT (Versionado Histórico)
-- Tabla: public.app_dat_precio_venta
-- Propósito: Cuando se intente actualizar el precio (precio_venta_cup,
-- precio_venta_usd, precio_descuento), en lugar de sobrescribir la fila
-- existente, se cierra la fila anterior y se inserta un nuevo registro
-- de precio. Las actualizaciones puras de metadatos (como fecha_hasta)
-- se permiten normalmente.
-- ============================================================

CREATE OR REPLACE FUNCTION public.trg_convert_price_update_to_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Si los campos de precio NO han cambiado (ej. solo se actualiza fecha_hasta u otros campos),
    -- permitir el update normalmente.
    IF (NEW.precio_venta_cup IS NOT DISTINCT FROM OLD.precio_venta_cup) AND
       (NEW.precio_venta_usd IS NOT DISTINCT FROM OLD.precio_venta_usd) AND
       (NEW.precio_descuento IS NOT DISTINCT FROM OLD.precio_descuento) THEN
        RETURN NEW;
    END IF;

    -- Si se intenta actualizar el precio:
    -- 1. Asegurar que la fila anterior tenga fecha_hasta cerrada si estaba activa
    UPDATE public.app_dat_precio_venta
    SET fecha_hasta = COALESCE(NEW.fecha_desde, CURRENT_DATE) - INTERVAL '1 day'
    WHERE id = OLD.id
      AND fecha_hasta IS NULL;

    -- 2. Insertar la nueva fila con los nuevos precios
    INSERT INTO public.app_dat_precio_venta (
        id_producto,
        id_variante,
        precio_venta_cup,
        precio_descuento,
        precio_venta_usd,
        fecha_desde,
        fecha_hasta,
        created_at
    ) VALUES (
        OLD.id_producto,
        COALESCE(NEW.id_variante, OLD.id_variante),
        NEW.precio_venta_cup,
        NEW.precio_descuento,
        NEW.precio_venta_usd,
        COALESCE(NEW.fecha_desde, CURRENT_DATE),
        NEW.fecha_hasta,
        COALESCE(NEW.created_at, NOW())
    );

    -- 3. Cancelar el UPDATE original de la fila vieja para evitar sobrescritura en el registro antiguo
    RETURN NULL;
END;
$$;

-- Eliminar trigger previo si existía para evitar duplicados
DROP TRIGGER IF EXISTS trg_price_update_to_insert ON public.app_dat_precio_venta;

-- Crear el trigger BEFORE UPDATE
CREATE TRIGGER trg_price_update_to_insert
BEFORE UPDATE ON public.app_dat_precio_venta
FOR EACH ROW
EXECUTE FUNCTION public.trg_convert_price_update_to_insert();

COMMENT ON FUNCTION public.trg_convert_price_update_to_insert() IS
'Convierte automáticamente cualquier UPDATE de precio en app_dat_precio_venta en un INSERT (versionado histórico), cerrando la vigencia anterior.';
