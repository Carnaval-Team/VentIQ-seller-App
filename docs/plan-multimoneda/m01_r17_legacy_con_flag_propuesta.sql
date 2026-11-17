BEGIN;

-- BORRADOR MC-037. NO EJECUTAR en main.
-- Una venta nueva sin version no entra cuando la tienda tiene el flag
-- encendido. Las filas ya guardadas no se reescriben ni se borran.
-- Hoy el flag sigue apagado, así que las ventas actuales siguen pasando.

SET LOCAL app.m01_r17_legacy_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r17_legacy_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador MC-037: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF to_regclass('public.app_dat_operacion_venta') IS NULL
       OR NOT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = 'app_dat_configuracion_tienda'
              AND column_name = 'permitir_moneda_por_producto'
       ) THEN
        RAISE EXCEPTION 'Falta la venta o el flag de moneda por producto';
    END IF;
    IF to_regprocedure('public.fn_m01_venta_legacy_con_flag()') IS NOT NULL THEN
        RAISE EXCEPTION 'La guarda de venta legacy ya existe';
    END IF;
END;
$preflight$;

CREATE FUNCTION public.fn_m01_venta_legacy_con_flag()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_flag boolean;
BEGIN
    IF NEW.version_monetaria IS NOT NULL THEN
        RETURN NEW;
    END IF;
    SELECT c.permitir_moneda_por_producto INTO v_flag
    FROM public.app_dat_operaciones o
    JOIN public.app_dat_configuracion_tienda c ON c.id_tienda = o.id_tienda
    WHERE o.id = NEW.id_operacion;
    IF v_flag IS TRUE THEN
        RAISE EXCEPTION 'Una venta nueva no puede omitir el contrato de moneda'
            USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS m01_venta_legacy_con_flag ON public.app_dat_operacion_venta;
CREATE TRIGGER m01_venta_legacy_con_flag
    BEFORE INSERT ON public.app_dat_operacion_venta
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_m01_venta_legacy_con_flag();

REVOKE ALL ON FUNCTION public.fn_m01_venta_legacy_con_flag() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_m01_venta_legacy_con_flag() TO authenticated;

COMMIT;
