DO $test$
DECLARE
    v_count bigint;
    v_total numeric;
BEGIN
    SELECT count(*), sum(m.cantidad)
    INTO v_count, v_total
    FROM public.get_product_movements_v5(8896, NULL, NULL, NULL, NULL, 0, 100000) m
    WHERE m.id_operacion = 180687;
    IF v_count <> 2 OR v_total IS DISTINCT FROM 9::numeric THEN
        RAISE EXCEPTION 'Regresión operación 180687: filas %, cantidad %', v_count, v_total;
    END IF;

    SELECT count(*) INTO v_count
    FROM public.get_product_movements_v5(8896, NULL, NULL, NULL, NULL, 0, 100000) m
    JOIN public.app_dat_inventario_productos inv ON inv.id = m.id
    WHERE m.id_operacion = 180687
      AND m.cantidad = abs(inv.cantidad_final - inv.cantidad_inicial)
      AND m.fecha = inv.created_at
      AND m.cantidad_inicial = inv.cantidad_inicial
      AND m.cantidad_final = inv.cantidad_final
      AND m.cantidad_orden = 9
      AND (
        (m.id = 453919 AND m.cantidad = 8 AND m.cantidad_final = 156
          AND m.movimiento_etiqueta = 'Agregado a orden')
        OR
        (m.id = 456326 AND m.cantidad = 1 AND m.cantidad_final = 155
          AND m.movimiento_etiqueta = 'Aumento de cantidad'
          AND m.motivo_modificacion = 'Cantidad modificada de 8.0 a 9.0')
      );
    IF v_count <> 2 THEN
        RAISE EXCEPTION 'Cantidad, fecha, saldo o evidencia incorrectos: % filas válidas', v_count;
    END IF;

    SELECT count(*) INTO v_count
    FROM public.get_product_movements_v5(8896, '2026-10-30', '2026-10-30', NULL, NULL, 0, 100000) m
    WHERE m.id = 456326 AND m.fecha::date = '2026-10-30';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'El filtro debe incluir la modificación en su fecha real';
    END IF;

    SELECT count(*) INTO v_count
    FROM public.get_product_movements_v5(8896, NULL, NULL, NULL, NULL, 0, 100000) m
    FULL JOIN public.get_product_movements_v4(8896, NULL, NULL, NULL, NULL, 0, 100000) old
      ON old.id = m.id AND old.tipo_movimiento = m.tipo_movimiento
    WHERE m.id IS NULL OR old.id IS NULL
       OR m.cantidad_inicial IS DISTINCT FROM old.cantidad_inicial
       OR m.cantidad_final IS DISTINCT FROM old.cantidad_final
       OR m.total_count IS DISTINCT FROM old.total_count
       OR (m.tipo_movimiento <> 'Extracción' AND
           (m.cantidad IS DISTINCT FROM old.cantidad OR m.fecha IS DISTINCT FROM old.fecha));
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'Se alteraron filas, saldos o movimientos fuera del alcance';
    END IF;
END;
$test$;
