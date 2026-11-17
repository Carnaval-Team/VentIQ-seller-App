WITH fixture (
    id, currency, q, p, auto_kind, auto_value, manual_unit, rate,
    unit_expected, gross_expected, subtotal_expected, manual_expected,
    net_expected, cup_expected, delta_expected
) AS (
    VALUES
    ('manual_cup_unit','CUP','3','100','none','0','10','1','90','300.00','300.00','30','270.00','270.00','0'),
    ('percent_usd_line_rounding','USD','3','1.05','discount_percent','10','0','400','0.945','3.15','2.84','0','2.84','1136.00','0.005'),
    ('percent_cup','CUP','3','100','discount_percent','10','0','1','90','300.00','270.00','0','270.00','270.00','0'),
    ('usd_native_independent','USD','2','5','none','0','0','400','5','10.00','10.00','0','10.00','4000.00','0'),
    ('manual_usd_unit','USD','3','2.5','none','0','0.1','420','2.4','7.50','7.50','0.3','7.20','3024.00','0'),
    ('half_cent_up','USD','1','0.105','none','0','0','400','0.105','0.11','0.11','0','0.11','44.00','0.005'),
    ('fractional_quantity','CUP','0.125','10','none','0','0','1','10','1.25','1.25','0','1.25','1.25','0'),
    ('fixed_auto_cup_then_manual','CUP','2','100','discount_unit','5','10','1','85','200.00','190.00','20','170.00','170.00','0'),
    ('fixed_auto_usd_then_manual','USD','2','5','discount_unit','0.25','0.1','400','4.65','10.00','9.50','0.2','9.30','3720.00','0'),
    ('percent_surcharge_usd','USD','3','1.05','surcharge_percent','10','0','400','1.155','3.15','3.47','0','3.47','1388.00','0.005'),
    ('fixed_surcharge_then_manual','CUP','3','100','surcharge_unit','5','10','1','95','300.00','315.00','30','285.00','285.00','0'),
    ('authorized_zero_net','CUP','3','100','none','0','100','1','0','300.00','300.00','300','0.00','0.00','0'),
    ('tiny_usd_line','USD','1','0.005','none','0','0','400','0.005','0.01','0.01','0','0.01','4.00','0.005'),
    ('rounding_delta_negative','USD','1','0.104','none','0','0','400','0.104','0.10','0.10','0','0.10','40.00','-0.004')
), normalized AS (
    SELECT fixture.*, q::numeric AS quantity, p::numeric AS unit_price,
           auto_value::numeric AS automatic_value,
           manual_unit::numeric AS manual_discount, rate::numeric AS rate_cup
    FROM fixture
), automatic AS (
    SELECT normalized.*,
           CASE auto_kind
               WHEN 'none' THEN unit_price
               WHEN 'discount_percent' THEN unit_price * (1 - automatic_value / 100)
               WHEN 'discount_unit' THEN unit_price - automatic_value
               WHEN 'surcharge_percent' THEN unit_price * (1 + automatic_value / 100)
               WHEN 'surcharge_unit' THEN unit_price + automatic_value
           END AS unit_before_manual
    FROM normalized
), calculated AS (
    SELECT automatic.*, unit_before_manual - manual_discount AS unit_net
    FROM automatic
), fixed AS (
    SELECT calculated.*, round(quantity * unit_price, 2) AS line_gross,
           round(quantity * unit_before_manual, 2) AS subtotal_before_manual,
           quantity * manual_discount AS manual_nominal,
           round(quantity * unit_net, 2) AS line_net
    FROM calculated
)
SELECT id, currency, line_net, round(line_net * rate_cup, 2) AS cup_net,
       unit_net = unit_expected::numeric
       AND line_gross = gross_expected::numeric
       AND subtotal_before_manual = subtotal_expected::numeric
       AND manual_nominal = manual_expected::numeric
       AND line_net = net_expected::numeric
       AND round(line_net * rate_cup, 2) = cup_expected::numeric
       AND line_net - quantity * unit_net = delta_expected::numeric AS passed
FROM fixed
ORDER BY id;
