-- Solo lectura. Ejecutar despues del script 39.
SELECT
    to_regclass('public.app_dat_operacion_venta') IS NOT NULL AS venta,
    EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'm01_venta_legacy_con_flag'
          AND NOT tgisinternal
    ) AS guarda,
    (
        SELECT c.permitir_moneda_por_producto
        FROM public.app_dat_configuracion_tienda c
        WHERE c.permitir_moneda_por_producto IS TRUE
        LIMIT 1
    ) IS NULL AS flag_apagado;
