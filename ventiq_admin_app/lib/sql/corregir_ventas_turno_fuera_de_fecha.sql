-- ============================================================================
-- Turno abierto: pasar las ventas que faltan y luego corregir hora y precio
-- ============================================================================
-- Orden. El turno NO se cierra antes.
--
--   1. El vendedor que abrió el turno registra en el TPV las ventas que no
--      llegaron a pasar. Tiene que completarlas (estado 2) y cobrarlas.
--      Eso lo hace la app, con fn_registrar_venta_v3 (o mesa_v3 / offline_v4)
--      y fn_registrar_pago_venta_v3. Ahí se descuenta el inventario, se crean
--      las líneas y los pagos. Este script no inserta ventas.
--   2. Con los id de esas operaciones ya creadas, este script:
--        - pone la hora real (p_fecha_hora) en la operación, la cabecera,
--          las líneas, los pagos y el estado;
--        - cambia precios e importes al catálogo vigente ese día;
--        - reparte el nuevo total entre los pagos que el vendedor acaba de
--          registrar, sin cambiar moneda ni tasa.
--   3. Después de aplicar y revisar, ahí sí se puede cerrar el turno.
--      El esperado se calcula al cierre con las fechas y montos ya corregidos.
--
-- El turno tiene que seguir abierto (fecha_cierre nula). Si ya está cerrado,
-- el script no corre: no reescribe un arqueo cerrado.
--
-- p_fecha_hora es la hora real de esas ventas, en la zona America/Havana.
-- Tiene que caer entre la apertura del turno y ahora. Las operaciones se
-- colocan en esa hora, separadas un milisegundo para conservar el orden.
-- La vigencia del precio es por fecha (fecha_desde / fecha_hasta, id mayor),
-- la misma regla que app_v_precio_venta_vigente, usando el día de esa hora.
--
-- Lo que se reescribe, que es lo que el TPV dejó al guardar:
--   app_dat_operaciones.created_at
--   app_dat_operacion_venta.created_at, importe_total,
--     precio_con_descuento_total (si ya tenía valor), id_turno_apertura
--   app_dat_extraccion_productos.precio_unitario, importe, importe_real,
--     precio_oficial_venta (si ya tenía valor), created_at
--   app_dat_pago_venta.monto, importe_sin_descuento, fecha_pago, created_at
--   app_dat_estado_operacion.created_at
--
-- No se toca inventario, lotes, ingredientes, conversiones ni el efectivo
-- contado. El descuento de stock queda en la hora en que el vendedor pasó
-- la venta. La marca contabilizada tampoco se cambia.
--
-- Precio. En una venta el precio_unitario ya es precio de catálogo × factor
-- de la presentación. El importe es precio × cantidad.
--   - Si la línea coincide con el catálogo de hoy (lo que cobró el TPV al
--     pasarla), se sustituye por el catálogo del día de p_fecha_hora.
--   - Si no coincide (precio acordado o promoción), se conserva la proporción.
--   - Una línea en 0 se deja en 0.
--
-- Uso
--   1. El vendedor pasa las ventas con el turno abierto.
--   2. Rellena turno, operaciones y la hora real. Deja p_aplicar en false.
--   3. Revisa precio_despues, importe_despues y created_at_despues.
--   4. Cambia false por true y vuelve a ejecutar.
-- ============================================================================

DROP FUNCTION IF EXISTS pg_temp.corregir_ventas_turno(bigint, bigint[], boolean, boolean);
DROP FUNCTION IF EXISTS pg_temp.corregir_ventas_turno(bigint, bigint[], timestamptz, boolean);

CREATE FUNCTION pg_temp.corregir_ventas_turno(
  p_id_turno bigint,
  p_operaciones bigint[],
  p_fecha_hora timestamptz,
  p_aplicar boolean
)
RETURNS TABLE (
  id_operacion bigint,
  id_extraccion bigint,
  producto text,
  cantidad numeric,
  factor_rel numeric,
  criterio text,
  precio_antes numeric,
  precio_catalogo_dia_venta numeric,
  precio_catalogo_dia_turno numeric,
  precio_despues numeric,
  importe_antes numeric,
  importe_despues numeric,
  created_at_antes timestamptz,
  created_at_despues timestamptz,
  importe_operacion_antes numeric,
  importe_operacion_despues numeric,
  pagos_cup_antes numeric,
  pagos_cup_despues numeric,
  entra_en_arqueo boolean,
  aviso text
)
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $fn$
DECLARE
  c_tz constant text := 'America/Havana';
  c_tol constant numeric := 0.05;
  v_tpv bigint;
  v_tienda bigint;
  v_apertura timestamptz;
  v_cierre timestamptz;
  v_creador uuid;
  v_dia_turno date;
  v_id bigint;
  v_op record;
  v_estado smallint;
  v_otro bigint;
  v_dia_venta date;
  v_fin timestamptz;
  v_nuevo timestamptz;
  v_delta interval;
  v_seq int := 0;
  v_linea record;
  v_factor numeric;
  v_cup_turno numeric;
  v_cup_venta numeric;
  v_cat_turno numeric;
  v_cat_venta numeric;
  v_precio_nuevo numeric;
  v_criterio text;
  v_bloqueo text;
  v_old_total numeric;
  v_new_total numeric;
  v_old_cup numeric;
  v_pago record;
  v_resto numeric;
  v_nuevo_monto numeric;
  v_tasa numeric;
  v_aviso text;
  v_entra boolean;
  v_hay_bloqueo boolean := false;
BEGIN
  IF p_id_turno IS NULL OR p_operaciones IS NULL OR cardinality(p_operaciones) = 0 THEN
    RAISE EXCEPTION 'Indica p_id_turno y al menos un id de operación';
  END IF;
  IF p_fecha_hora IS NULL THEN
    RAISE EXCEPTION 'Indica p_fecha_hora, la hora real de esas ventas';
  END IF;

  SELECT ct.id_tpv, tpv.id_tienda, ct.fecha_apertura, ct.fecha_cierre, ct.creado_por
    INTO v_tpv, v_tienda, v_apertura, v_cierre, v_creador
  FROM public.app_dat_caja_turno ct
  JOIN public.app_dat_tpv tpv ON tpv.id = ct.id_tpv
  WHERE ct.id = p_id_turno;

  IF v_tpv IS NULL THEN
    RAISE EXCEPTION 'No existe el turno %', p_id_turno;
  END IF;
  IF v_cierre IS NOT NULL THEN
    RAISE EXCEPTION 'El turno % está cerrado. El vendedor tiene que pasar las ventas con el turno abierto y esta corrección se corre antes de cerrarlo', p_id_turno;
  END IF;
  IF p_fecha_hora < v_apertura OR p_fecha_hora > clock_timestamp() THEN
    RAISE EXCEPTION 'La hora real % tiene que estar entre la apertura % y ahora', p_fecha_hora, v_apertura;
  END IF;

  v_dia_turno := (p_fecha_hora AT TIME ZONE c_tz)::date;
  v_fin := clock_timestamp();

  DROP TABLE IF EXISTS pg_temp._corr_op;
  DROP TABLE IF EXISTS pg_temp._corr_linea;
  DROP TABLE IF EXISTS pg_temp._corr_pago;

  CREATE TEMP TABLE _corr_op (
    id_operacion bigint PRIMARY KEY,
    created_at_antes timestamptz,
    created_at_despues timestamptz,
    importe_antes numeric,
    importe_despues numeric,
    descuento_antes numeric,
    pagos_cup_antes numeric,
    pagos_cup_despues numeric,
    entra_en_arqueo boolean,
    aviso text
  );

  CREATE TEMP TABLE _corr_linea (
    id_operacion bigint,
    id_extraccion bigint,
    id_producto bigint,
    producto text,
    cantidad numeric,
    factor_rel numeric,
    criterio text,
    precio_antes numeric,
    precio_catalogo_dia_venta numeric,
    precio_catalogo_dia_turno numeric,
    precio_despues numeric,
    importe_antes numeric,
    importe_despues numeric,
    importe_real_antes numeric,
    importe_real_despues numeric,
    oficial_antes numeric,
    oficial_despues numeric
  );

  CREATE TEMP TABLE _corr_pago (
    id bigint PRIMARY KEY,
    id_operacion bigint,
    monto_antes numeric,
    monto_despues numeric,
    tasa numeric,
    cup_antes numeric,
    cup_despues numeric
  );

  FOR v_id IN
    SELECT DISTINCT x FROM unnest(p_operaciones) AS t(x) ORDER BY 1
  LOOP
    v_seq := v_seq + 1;
    v_aviso := NULL;
    v_bloqueo := NULL;
    v_estado := NULL;
    v_otro := NULL;

    SELECT o.id AS id_operacion,
           o.created_at,
           o.uuid,
           o.id_tienda,
           o.contabilizada,
           o.id_tipo_operacion,
           ov.id_tpv,
           ov.importe_total,
           ov.precio_con_descuento_total,
           ov.es_pagada,
           ov.id_turno_apertura,
           lower(top.denominacion) AS tipo
      INTO v_op
    FROM public.app_dat_operaciones o
    LEFT JOIN public.app_dat_operacion_venta ov ON ov.id_operacion = o.id
    LEFT JOIN public.app_nom_tipo_operacion top ON top.id = o.id_tipo_operacion
    WHERE o.id = v_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'La operación % no existe', v_id;
    END IF;
    IF v_op.tipo IS DISTINCT FROM 'venta' OR v_op.id_tpv IS NULL THEN
      RAISE EXCEPTION 'La operación % no es una venta', v_id;
    END IF;
    IF v_op.id_tpv IS DISTINCT FROM v_tpv OR v_op.id_tienda IS DISTINCT FROM v_tienda THEN
      RAISE EXCEPTION 'La venta % no es del TPV % del turno %', v_id, v_tpv, p_id_turno;
    END IF;

    SELECT eo.estado
      INTO v_estado
    FROM public.app_dat_estado_operacion eo
    WHERE eo.id_operacion = v_id
    ORDER BY eo.id DESC
    LIMIT 1;

    IF v_estado IS DISTINCT FROM 2 THEN
      v_bloqueo := format('el último estado es %s; el arqueo solo suma estado 2 (completada)', COALESCE(v_estado::text, 'ninguno'));
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.app_dat_pago_venta pv
      WHERE pv.id_operacion_venta = v_id AND pv.id_liquidacion IS NOT NULL
    ) THEN
      v_bloqueo := concat_ws(' | ', v_bloqueo, 'tiene un pago ya liquidado');
    END IF;

    SELECT ct.id
      INTO v_otro
    FROM public.app_dat_caja_turno ct
    WHERE ct.id <> p_id_turno
      AND ct.id_tpv = v_tpv
      AND ct.fecha_cierre IS NOT NULL
      AND v_op.created_at >= ct.fecha_apertura
      AND v_op.created_at <= ct.fecha_cierre
    ORDER BY ct.id
    LIMIT 1;

    IF v_otro IS NOT NULL THEN
      v_bloqueo := concat_ws(' | ', v_bloqueo, format('su fecha actual cae en el turno cerrado %s', v_otro));
    END IF;

    v_dia_venta := (v_op.created_at AT TIME ZONE c_tz)::date;
    v_nuevo := p_fecha_hora + (v_seq * interval '1 millisecond');
    IF v_nuevo > v_fin THEN
      v_bloqueo := concat_ws(' | ', v_bloqueo, 'la hora real más el orden de la venta queda en el futuro');
    END IF;

    v_delta := v_nuevo - v_op.created_at;

    FOR v_linea IN
      SELECT ep.id, ep.id_producto, ep.id_variante, ep.id_presentacion,
             ep.cantidad, ep.precio_unitario, ep.importe, ep.importe_real,
             ep.precio_oficial_venta, p.denominacion
      FROM public.app_dat_extraccion_productos ep
      JOIN public.app_dat_producto p ON p.id = ep.id_producto
      WHERE ep.id_operacion = v_id
      ORDER BY ep.id
    LOOP
      SELECT f.factor_rel INTO v_factor
      FROM public.fn_presentaciones_producto(v_linea.id_producto) f
      WHERE f.id_presentacion = v_linea.id_presentacion;
      v_factor := COALESCE(NULLIF(v_factor, 0), 1);

      SELECT pv.precio_venta_cup INTO v_cup_turno
      FROM public.app_dat_precio_venta pv
      WHERE pv.id_producto = v_linea.id_producto
        AND pv.fecha_desde <= v_dia_turno
        AND (pv.fecha_hasta IS NULL OR pv.fecha_hasta >= v_dia_turno)
        AND (COALESCE(pv.id_variante, 0) = 0
             OR pv.id_variante IS NOT DISTINCT FROM NULLIF(v_linea.id_variante, 0))
      ORDER BY (COALESCE(pv.id_variante, 0) <> 0) DESC, pv.id DESC
      LIMIT 1;

      SELECT pv.precio_venta_cup INTO v_cup_venta
      FROM public.app_dat_precio_venta pv
      WHERE pv.id_producto = v_linea.id_producto
        AND pv.fecha_desde <= v_dia_venta
        AND (pv.fecha_hasta IS NULL OR pv.fecha_hasta >= v_dia_venta)
        AND (COALESCE(pv.id_variante, 0) = 0
             OR pv.id_variante IS NOT DISTINCT FROM NULLIF(v_linea.id_variante, 0))
      ORDER BY (COALESCE(pv.id_variante, 0) <> 0) DESC, pv.id DESC
      LIMIT 1;

      v_cat_turno := v_cup_turno * v_factor;
      v_cat_venta := v_cup_venta * v_factor;
      v_criterio := NULL;
      v_precio_nuevo := v_linea.precio_unitario;

      IF COALESCE(v_linea.precio_unitario, 0) = 0 THEN
        v_criterio := 'cero';
        v_precio_nuevo := 0;
      ELSIF v_cup_turno IS NULL THEN
        v_criterio := 'sin_precio_turno';
        v_bloqueo := concat_ws(' | ', v_bloqueo,
          format('producto %s sin precio vigente el %s', v_linea.id_producto, v_dia_turno));
      ELSIF abs(v_linea.precio_unitario - v_cat_turno) <= c_tol THEN
        v_criterio := 'ya_estaba';
        v_precio_nuevo := v_cat_turno;
      ELSIF v_cup_venta IS NOT NULL AND abs(v_linea.precio_unitario - v_cat_venta) <= c_tol THEN
        v_criterio := 'catalogo';
        v_precio_nuevo := v_cat_turno;
      ELSIF v_cup_venta IS NOT NULL AND v_cup_venta <> 0 THEN
        v_criterio := 'proporcion';
        v_precio_nuevo := v_linea.precio_unitario * v_cup_turno / v_cup_venta;
      ELSE
        v_criterio := 'sin_precio_dia_venta';
        v_bloqueo := concat_ws(' | ', v_bloqueo,
          format('producto %s sin precio de catálogo el %s y la línea no coincide con el del turno',
                 v_linea.id_producto, v_dia_venta));
      END IF;

      INSERT INTO _corr_linea VALUES (
        v_id, v_linea.id, v_linea.id_producto, v_linea.denominacion,
        v_linea.cantidad, v_factor, v_criterio,
        v_linea.precio_unitario, v_cat_venta, v_cat_turno, v_precio_nuevo,
        v_linea.importe, COALESCE(v_linea.cantidad, 0) * v_precio_nuevo,
        v_linea.importe_real,
        CASE
          WHEN v_linea.importe_real IS NULL THEN NULL
          WHEN v_linea.precio_unitario IS NULL OR v_linea.precio_unitario = 0 THEN v_linea.importe_real
          ELSE v_linea.importe_real * v_precio_nuevo / v_linea.precio_unitario
        END,
        v_linea.precio_oficial_venta,
        CASE
          WHEN v_linea.precio_oficial_venta IS NULL THEN NULL
          WHEN v_linea.precio_unitario IS NULL OR v_linea.precio_unitario = 0 THEN v_linea.precio_oficial_venta
          ELSE v_linea.precio_oficial_venta * v_precio_nuevo / v_linea.precio_unitario
        END
      );
    END LOOP;

    SELECT COALESCE(SUM(importe_antes), 0), COALESCE(SUM(importe_despues), 0)
      INTO v_old_total, v_new_total
    FROM _corr_linea
    WHERE id_operacion = v_id;

    SELECT COALESCE(SUM(pv.monto * COALESCE(pv.tasa_cambio, pv.tasa_usd, CASE WHEN upper(trim(pv.moneda)) = 'CUP' THEN 1 END)), 0)
      INTO v_old_cup
    FROM public.app_dat_pago_venta pv
    WHERE pv.id_operacion_venta = v_id;

    IF v_new_total > 0 AND v_old_cup = 0 AND v_op.es_pagada THEN
      v_bloqueo := concat_ws(' | ', v_bloqueo, 'está marcada pagada y no tiene pagos que escalar');
    ELSIF v_new_total > 0 AND v_old_cup = 0 AND NOT v_op.es_pagada THEN
      v_aviso := concat_ws(' | ', v_aviso, 'sin pagos: se corrige el total y no se crean cobros');
    ELSIF v_old_cup > 0 AND EXISTS (
      SELECT 1 FROM public.app_dat_pago_venta pv
      WHERE pv.id_operacion_venta = v_id
        AND (
          COALESCE(pv.tasa_cambio, pv.tasa_usd, CASE WHEN upper(trim(pv.moneda)) = 'CUP' THEN 1 END) IS NULL
          OR COALESCE(pv.tasa_cambio, pv.tasa_usd, CASE WHEN upper(trim(pv.moneda)) = 'CUP' THEN 1 END) <= 0
        )
    ) THEN
      v_bloqueo := concat_ws(' | ', v_bloqueo, 'un pago no tiene tasa válida');
    END IF;

    IF v_op.contabilizada THEN
      v_aviso := concat_ws(' | ', v_aviso, 'ya estaba contabilizada; la marca no se cambia');
    END IF;
    IF v_op.uuid IS DISTINCT FROM v_creador THEN
      v_aviso := concat_ws(' | ', v_aviso, 'el uuid de la venta no es el creador del turno: entra al reporte de productos del turno, no al efectivo esperado');
    END IF;

    v_entra := v_bloqueo IS NULL
      AND v_estado = 2
      AND v_op.uuid IS NOT DISTINCT FROM v_creador
      AND v_nuevo >= v_apertura
      AND v_nuevo <= v_fin;

    INSERT INTO _corr_op VALUES (
      v_id, v_op.created_at, v_nuevo, v_old_total, v_new_total,
      v_op.precio_con_descuento_total, v_old_cup,
      CASE WHEN v_old_cup = 0 THEN 0 ELSE v_new_total END,
      v_entra, concat_ws(' | ', v_bloqueo, v_aviso)
    );

    IF v_bloqueo IS NOT NULL THEN
      v_hay_bloqueo := true;
    END IF;

    IF v_old_cup > 0 AND v_bloqueo IS NULL THEN
      v_resto := v_new_total;
      FOR v_pago IN
        SELECT pv.id, pv.monto,
               COALESCE(pv.tasa_cambio, pv.tasa_usd, 1) AS tasa,
               pv.monto * COALESCE(pv.tasa_cambio, pv.tasa_usd, CASE WHEN upper(trim(pv.moneda)) = 'CUP' THEN 1 END) AS cup
        FROM public.app_dat_pago_venta pv
        WHERE pv.id_operacion_venta = v_id
        ORDER BY pv.id
      LOOP
        v_tasa := v_pago.tasa;
        IF v_pago.id = (SELECT MAX(id) FROM public.app_dat_pago_venta WHERE id_operacion_venta = v_id) THEN
          v_nuevo_monto := v_resto / v_tasa;
        ELSE
          v_nuevo_monto := round((v_pago.cup * v_new_total / v_old_cup) / v_tasa, 2);
          v_resto := v_resto - (v_nuevo_monto * v_tasa);
        END IF;
        INSERT INTO _corr_pago VALUES (
          v_pago.id, v_id, v_pago.monto, v_nuevo_monto, v_tasa, v_pago.cup, v_nuevo_monto * v_tasa
        );
      END LOOP;
    END IF;
  END LOOP;

  IF p_aplicar AND v_hay_bloqueo THEN
    RAISE EXCEPTION 'Hay ventas que no se pueden corregir. Ejecuta primero con p_aplicar = false y revisa la columna aviso';
  END IF;

  IF p_aplicar THEN
    FOR v_op IN SELECT * FROM _corr_op ORDER BY id_operacion
    LOOP
      PERFORM 1 FROM public.app_dat_operaciones WHERE id = v_op.id_operacion FOR UPDATE;

      UPDATE public.app_dat_extraccion_productos ep
      SET precio_unitario = l.precio_despues,
          importe = l.importe_despues,
          importe_real = l.importe_real_despues,
          precio_oficial_venta = l.oficial_despues,
          created_at = ep.created_at + (v_op.created_at_despues - v_op.created_at_antes)
      FROM _corr_linea l
      WHERE l.id_extraccion = ep.id
        AND l.id_operacion = v_op.id_operacion;

      UPDATE public.app_dat_operacion_venta ov
      SET importe_total = v_op.importe_despues,
          precio_con_descuento_total = CASE
            WHEN ov.precio_con_descuento_total IS NULL OR v_op.importe_antes = 0 THEN ov.precio_con_descuento_total
            ELSE ov.precio_con_descuento_total * v_op.importe_despues / v_op.importe_antes
          END,
          id_turno_apertura = p_id_turno,
          es_pagada = CASE
            WHEN v_op.pagos_cup_despues + 0.009 >= v_op.importe_despues THEN true
            ELSE ov.es_pagada
          END,
          created_at = v_op.created_at_despues
      WHERE ov.id_operacion = v_op.id_operacion;

      UPDATE public.app_dat_pago_venta pv
      SET monto = g.monto_despues,
          importe_sin_descuento = CASE
            WHEN pv.importe_sin_descuento IS NULL OR g.monto_antes = 0 THEN pv.importe_sin_descuento
            ELSE pv.importe_sin_descuento * g.monto_despues / g.monto_antes
          END,
          fecha_pago = pv.fecha_pago + (v_op.created_at_despues - v_op.created_at_antes),
          created_at = pv.created_at + (v_op.created_at_despues - v_op.created_at_antes)
      FROM _corr_pago g
      WHERE g.id = pv.id
        AND g.id_operacion = v_op.id_operacion;

      UPDATE public.app_dat_estado_operacion
      SET created_at = created_at + (v_op.created_at_despues - v_op.created_at_antes)
      WHERE id_operacion = v_op.id_operacion;

      UPDATE public.app_dat_operaciones
      SET created_at = v_op.created_at_despues
      WHERE id = v_op.id_operacion;
    END LOOP;
  END IF;

  RETURN QUERY
  SELECT l.id_operacion, l.id_extraccion, l.producto, l.cantidad, l.factor_rel, l.criterio,
         l.precio_antes, l.precio_catalogo_dia_venta, l.precio_catalogo_dia_turno, l.precio_despues,
         l.importe_antes, l.importe_despues,
         o.created_at_antes, o.created_at_despues,
         o.importe_antes, o.importe_despues, o.pagos_cup_antes, o.pagos_cup_despues,
         o.entra_en_arqueo, o.aviso
  FROM _corr_linea l
  JOIN _corr_op o ON o.id_operacion = l.id_operacion
  ORDER BY l.id_operacion, l.id_extraccion;
END;
$fn$;

-- 1) El vendedor pasa las ventas con el turno abierto y las completa.
-- 2) Rellena turno, ids y la hora real. false solo muestra el antes y el después.
-- 3) Si cuadra, cambia false por true. Cierra el turno después de aplicar.
SELECT * FROM pg_temp.corregir_ventas_turno(
  NULL::bigint,                         -- id de app_dat_caja_turno (abierto)
  ARRAY[]::bigint[],                    -- id de app_dat_operaciones que acaba de pasar el vendedor
  NULL::timestamptz,                    -- hora real, ej. timestamptz '2026-11-15 14:30:00-05'
  false                                 -- true aplica; false solo previsualiza
);
