-- Solo lectura. Ejecutar despues de los scripts 34 a 37.
WITH casos (
    id, moneda, cantidad, precio, tipo, valor, manual, tasa, neto, cup
) AS (
    VALUES
    ('manual_cup_unit','CUP','3','100','none','0','10','1', 270.00, 270.00),
    ('percent_usd_line_rounding','USD','3','1.05','discount_percent','10','0','400', 2.84, 1136.00),
    ('percent_cup','CUP','3','100','discount_percent','10','0','1', 270.00, 270.00),
    ('usd_native_independent','USD','2','5','none','0','0','400', 10.00, 4000.00),
    ('manual_usd_unit','USD','3','2.5','none','0','0.1','420', 7.20, 3024.00),
    ('half_cent_up','USD','1','0.105','none','0','0','400', 0.11, 44.00),
    ('fractional_quantity','CUP','0.125','10','none','0','0','1', 1.25, 1.25),
    ('fixed_auto_cup_then_manual','CUP','2','100','discount_unit','5','10','1', 170.00, 170.00),
    ('fixed_auto_usd_then_manual','USD','2','5','discount_unit','0.25','0.1','400', 9.30, 3720.00),
    ('percent_surcharge_usd','USD','3','1.05','surcharge_percent','10','0','400', 3.47, 1388.00),
    ('fixed_surcharge_then_manual','CUP','3','100','surcharge_unit','5','10','1', 285.00, 285.00),
    ('authorized_zero_net','CUP','3','100','none','0','100','1', 0.00, 0.00),
    ('tiny_usd_line','USD','1','0.005','none','0','0','400', 0.01, 4.00),
    ('rounding_delta_negative','USD','1','0.104','none','0','0','400', 0.10, 40.00)
), calculado AS (
    SELECT c.id,
           public.fn_m01_calcular_linea(jsonb_build_object(
               'currency', c.moneda,
               'quantity', c.cantidad,
               'unit_price', c.precio,
               'automatic_type', c.tipo,
               'automatic_value', c.valor,
               'manual_unit_discount', c.manual,
               'rate_cup', c.tasa
           )) AS resultado,
           c.neto, c.cup
    FROM casos c
)
SELECT
    count(*) FILTER (
        WHERE (resultado->>'line_net')::numeric = neto
          AND (resultado->>'cup_net')::numeric = cup
          AND resultado->>'status' = 'success'
    ) AS casos_ok,
    count(*) AS casos,
    to_regprocedure('public.fn_m01_registrar_venta_v1(jsonb)') IS NOT NULL AS alta,
    to_regprocedure('public.fn_m01_registrar_pagos_v1(jsonb)') IS NOT NULL AS pagos,
    to_regprocedure('public.fn_m01_ajustar_linea_v1(jsonb)') IS NOT NULL AS ajuste,
    has_function_privilege('anon', 'public.fn_m01_registrar_venta_v1(jsonb)', 'EXECUTE') AS anon_alta
FROM calculado;
