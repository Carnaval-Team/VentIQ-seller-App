-- ============================================================================
-- H9: fn_m01_venta_v1_pago_directo no debe leer NEW.version_monetaria
--     cuando el trigger corre sobre app_dat_pago_venta
-- ============================================================================
-- plpgsql evalúa NEW.campo aunque el AND anterior sea falso; al INSERT en
-- pago_venta revienta con 42703. IF anidados por TG_TABLE_NAME.
--
-- newa: aplicar ya. main: va con R15 / triggers M01 en el pase (no promover
-- R15 sin este cuerpo).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_m01_venta_v1_pago_directo()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $function$
BEGIN
    IF pg_catalog.current_setting('app.m01_venta_v1_interna', true) = 'yes' THEN
        RETURN NEW;
    END IF;

    IF TG_TABLE_NAME = 'app_dat_pago_venta' THEN
        IF EXISTS (
            SELECT 1 FROM public.app_dat_operacion_venta v
            WHERE v.id_operacion = NEW.id_operacion_venta
              AND v.version_monetaria = 'producto-v1'
        ) THEN
            RAISE EXCEPTION 'El cobro producto-v1 no se escribe directo'
                USING ERRCODE = '42501';
        END IF;
    ELSIF TG_TABLE_NAME = 'app_dat_operacion_venta' THEN
        IF NEW.version_monetaria = 'producto-v1'
           AND OLD.es_pagada IS DISTINCT FROM NEW.es_pagada THEN
            RAISE EXCEPTION 'El estado de cobro producto-v1 no se escribe directo'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    RETURN NEW;
END;
$function$;
