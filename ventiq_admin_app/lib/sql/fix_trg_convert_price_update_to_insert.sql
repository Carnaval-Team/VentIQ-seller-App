-- =============================================================================
-- FIX: trg_convert_price_update_to_insert
-- =============================================================================
--
-- Problemas encontrados:
--
--   1. fecha_desde del INSERT usaba NEW.fecha_hasta en vez de NEW.fecha_desde.
--      Esto hacia que la nueva fila de precio se creara con la fecha de fin
--      como fecha de inicio.
--
--   2. created_at copiaba el valor del registro anterior (NEW.created_at viene
--      del OLD en un UPDATE). Debe ser siempre NOW() porque es un registro nuevo.
--
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.trg_convert_price_update_to_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    -- Si los campos de precio NO han cambiado (ej. solo se actualiza fecha_hasta
    -- u otros campos), permitir el update normalmente.
    IF (NEW.precio_venta_cup IS NOT DISTINCT FROM OLD.precio_venta_cup) AND
       (NEW.precio_venta_usd IS NOT DISTINCT FROM OLD.precio_venta_usd) AND
       (NEW.precio_descuento IS NOT DISTINCT FROM OLD.precio_descuento) THEN
        RETURN NEW;
    END IF;

    -- Si se intenta actualizar el precio:
    -- 1. Cerrar la fila anterior (poner fecha_hasta si estaba activa)
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
        COALESCE(NEW.fecha_desde, CURRENT_DATE),  -- FIX: era NEW.fecha_hasta
        NULL,
        NOW()                                       -- FIX: era COALESCE(NEW.created_at, NOW())
    );

    -- 3. Cancelar el UPDATE original para no sobrescribir el registro antiguo
    RETURN NULL;
END;
$function$;

NOTIFY pgrst, 'reload schema';

COMMIT;
