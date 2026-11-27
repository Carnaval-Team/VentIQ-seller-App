-- ============================================================================
-- 13b_repartir_aterrizaje.sql — reparto correcto del aterrizaje
--
-- Entorno: `newa` (qhprswhhfasrikhawjoz). NO aplicar en main.
-- Fecha: 2026-11-26 · Plan: docs/planes/fondo-inversion/15-plan-compras-costos.md
--
-- Reglas (D1/D3/D4 del plan):
--   · `monto_usd` = importe TOTAL de la línea. El unitario se deriva.
--   · Importadora: se reparte por VALOR (es un % del valor recibido).
--   · Ajustes globales que capitalizan: se reparten por CANTIDAD BASE, y la
--     porción del vínculo es `monto_capitalizado × cantidad_recibida / comprada`.
--   · Reejecutar un vínculo borra y reescribe SOLO sus filas (idempotente).
--   · `origen_pago = 'fondo'` se rechaza: el fondo no paga el cargo aquí.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_fdi_compra_repartir_aterrizaje(
    p_id_compra_recepcion bigint,
    p_tasa_usd numeric DEFAULT NULL::numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_link         record;
    v_op_moneda    character varying;
    v_op_tasa      numeric;
    v_moneda_op    text;
    v_moneda_link  text;
    v_tasa         numeric;
    v_tasa_origen  text;
    v_tasa_forzada boolean := false;
    v_id_tipo      bigint;
    v_cargo_usd    numeric;
    v_lineas       integer;
    v_base_total   numeric;
    v_borradas     integer := 0;
    v_insertadas   integer := 0;
    v_suma         numeric;
    v_filas        integer;
    v_qty_total    numeric;
    v_qty_link     numeric;
    v_aj           record;
    v_share        numeric;
    v_aj_total     numeric := 0;
    v_aj_count     integer := 0;
    v_aj_suma      numeric;
    v_status       text := 'ok';
BEGIN
    SELECT r.id, r.id_compra, r.id_operacion, r.id_tienda,
           r.monto_importadora, r.reembolso_importadora, r.monto_bruto_importadora,
           r.origen_pago, r.moneda
      INTO v_link
      FROM public.fdi_dat_compra_recepcion r
     WHERE r.id = p_id_compra_recepcion
       FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION '13b: vínculo compra↔recepción % no encontrado', p_id_compra_recepcion
            USING ERRCODE = 'P0002';
    END IF;

    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_is_gerente_or_superadmin(v_link.id_tienda), false) THEN
        RAISE EXCEPTION '13b: sólo gerente o superadmin pueden aterrizar el costo de la recepción %', v_link.id_operacion
            USING ERRCODE = '42501';
    END IF;

    SELECT o.moneda_factura, o.tasa_cambio_aplicada
      INTO v_op_moneda, v_op_tasa
      FROM public.app_dat_operacion_recepcion o
     WHERE o.id_operacion = v_link.id_operacion;

    IF NOT FOUND THEN
        RAISE EXCEPTION '13b: la operación % no tiene fila en app_dat_operacion_recepcion', v_link.id_operacion
            USING ERRCODE = 'P0002';
    END IF;

    v_moneda_op   := upper(btrim(COALESCE(v_op_moneda, '')));
    v_moneda_link := upper(btrim(COALESCE(v_link.moneda, '')));

    IF v_moneda_link <> '' AND v_moneda_op <> ''
       AND v_moneda_link IS DISTINCT FROM v_moneda_op THEN
        RAISE EXCEPTION '13b: la moneda del vínculo (%) no coincide con la de la operación % (%)',
            v_moneda_link, v_link.id_operacion, v_moneda_op
            USING ERRCODE = '22023';
    END IF;

    IF v_link.origen_pago NOT IN ('wallet_importadora', 'externo') THEN
        RAISE EXCEPTION '13b: origen_pago «%» no capitaliza en la recepción. Use wallet_importadora, externo o declare el cargo como ajuste de la compra.',
            COALESCE(v_link.origen_pago, 'NULL')
            USING ERRCODE = '22023';
    END IF;

    IF p_tasa_usd IS NOT NULL THEN
        IF NOT (p_tasa_usd > 0) OR p_tasa_usd >= 'Infinity'::numeric THEN
            RAISE EXCEPTION '13b: p_tasa_usd debe ser un número finito > 0 (recibido: %)', p_tasa_usd
                USING ERRCODE = '22023';
        END IF;
        v_tasa := p_tasa_usd;
        v_tasa_origen := 'parametro';
    ELSIF v_op_tasa IS NOT NULL THEN
        v_tasa := v_op_tasa;
        v_tasa_origen := 'operacion';
    END IF;

    IF v_moneda_op = 'USD' THEN
        IF v_tasa IS NOT NULL AND v_tasa <> 1 THEN
            v_tasa_forzada := true;
        END IF;
        IF v_tasa IS NULL THEN
            v_tasa_origen := 'moneda_usd';
        END IF;
        v_tasa := 1;
    END IF;

    IF v_tasa IS NULL OR v_tasa <= 0 THEN
        RAISE EXCEPTION '13b: la operación % no tiene tasa registrada y su moneda es %; registre la tasa o pase p_tasa_usd.',
            v_link.id_operacion, COALESCE(v_op_moneda, 'NULL')
            USING ERRCODE = '22023';
    END IF;

    UPDATE public.app_dat_operacion_recepcion
       SET tasa_cambio_aplicada = v_tasa,
           fecha_tasa_aplicada  = CASE
               WHEN tasa_cambio_aplicada IS DISTINCT FROM v_tasa
                   THEN now() AT TIME ZONE 'UTC'
               ELSE COALESCE(fecha_tasa_aplicada, now() AT TIME ZONE 'UTC')
           END
     WHERE id_operacion = v_link.id_operacion;

    UPDATE public.fdi_dat_compra_recepcion
       SET tasa_usd_aplicada = v_tasa
     WHERE id = p_id_compra_recepcion;

    -- Tipo «Importadora»: primero el de la tienda, luego el global.
    SELECT t.id INTO v_id_tipo
      FROM public.app_cont_tipo_costo t
     WHERE lower(btrim(t.denominacion)) = 'importadora'
       AND (t.id_tienda = v_link.id_tienda OR t.id_tienda IS NULL)
     ORDER BY (t.id_tienda IS NULL), t.id
     LIMIT 1;

    IF v_id_tipo IS NULL THEN
        RAISE EXCEPTION '13b: no hay tipo de costo Importadora (ni de la tienda % ni global).', v_link.id_tienda
            USING ERRCODE = 'P0002';
    END IF;

    v_cargo_usd := round(v_link.monto_importadora / v_tasa, 2);

    SELECT COALESCE(sum(l.cantidad), 0) INTO v_qty_total
      FROM public.fdi_dat_compra_linea l
     WHERE l.id_compra = v_link.id_compra;

    SELECT COALESCE(sum(rl.cantidad_recibida), 0) INTO v_qty_link
      FROM public.fdi_dat_compra_recepcion_linea rl
     WHERE rl.id_compra_recepcion = p_id_compra_recepcion;

    -- Reemplazo idempotente: solo las filas de ESTE vínculo. Las que capturó la
    -- recepción por línea (id_compra_recepcion NULL) no se tocan.
    DELETE FROM public.app_dat_recepcion_producto_costo c
     WHERE c.id_compra_recepcion = p_id_compra_recepcion
       AND c.revertido_at IS NULL;
    GET DIAGNOSTICS v_borradas = ROW_COUNT;

    SELECT count(*), COALESCE(sum(b.base), 0)
      INTO v_lineas, v_base_total
      FROM public.fn_fdi_compra_recepcion_bases(p_id_compra_recepcion) b;

    IF v_lineas = 0 THEN
        RAISE EXCEPTION '13b: la recepción % no tiene líneas; no hay entre qué repartir.', v_link.id_operacion
            USING ERRCODE = 'P0002';
    END IF;

    -- ── Importadora: por valor ─────────────────────────────────────────────
    IF v_cargo_usd > 0 THEN
        IF v_base_total <= 0 THEN
            RAISE EXCEPTION '13b: no se puede repartir la importadora: base total % en la recepción %.',
                v_base_total, v_link.id_operacion
                USING ERRCODE = '22023';
        END IF;

        INSERT INTO public.app_dat_recepcion_producto_costo
            (id_recepcion_producto, id_tipo_costo, monto_usd, monto_promedio_anterior,
             id_compra_recepcion)
        WITH bases AS (
            SELECT b.id_recepcion_producto, b.id_producto, b.base
              FROM public.fn_fdi_compra_recepcion_bases(p_id_compra_recepcion) b
        ),
        tot AS (SELECT COALESCE(sum(b.base), 0) AS base_total FROM bases b),
        destino AS (
            SELECT b.id_recepcion_producto
              FROM bases b
             ORDER BY b.base DESC, b.id_recepcion_producto ASC
             LIMIT 1
        ),
        prorr AS (
            SELECT b.id_recepcion_producto,
                   b.id_producto,
                   round(v_cargo_usd * b.base / NULLIF(t.base_total, 0), 2) AS monto
              FROM bases b CROSS JOIN tot t
        ),
        residuo AS (
            SELECT v_cargo_usd - COALESCE(sum(p.monto), 0) AS r FROM prorr p
        )
        SELECT p.id_recepcion_producto,
               v_id_tipo,
               p.monto + CASE WHEN p.id_recepcion_producto = (SELECT d.id_recepcion_producto FROM destino d)
                              THEN (SELECT r FROM residuo) ELSE 0 END,
               COALESCE((SELECT pc.monto_promedio_usd
                           FROM public.app_dat_producto_costo pc
                          WHERE pc.id_producto = p.id_producto
                            AND pc.id_tipo_costo = v_id_tipo), 0),
               p_id_compra_recepcion
          FROM prorr p;

        GET DIAGNOSTICS v_insertadas = ROW_COUNT;

        SELECT count(*), COALESCE(sum(c.monto_usd), 0)
          INTO v_filas, v_suma
          FROM public.app_dat_recepcion_producto_costo c
         WHERE c.id_compra_recepcion = p_id_compra_recepcion
           AND c.id_tipo_costo = v_id_tipo
           AND c.revertido_at IS NULL;

        IF v_filas <> v_lineas OR abs(v_suma - v_cargo_usd) >= 0.005 THEN
            RAISE EXCEPTION '13b: importadora descuadrada en la recepción %: % filas / Σ %, cargo %.',
                v_link.id_operacion, v_filas, v_suma, v_cargo_usd
                USING ERRCODE = 'P0001';
        END IF;
    END IF;

    -- ── Ajustes globales que capitalizan: por cantidad base ────────────────
    FOR v_aj IN
        SELECT a.id, a.id_tipo_costo, a.monto_capitalizado
          FROM public.fdi_dat_compra_ajuste a
         WHERE a.id_compra = v_link.id_compra
           AND a.afecta_inventario IS TRUE
           AND a.monto_capitalizado > 0
         ORDER BY a.id
    LOOP
        IF v_aj.id_tipo_costo IS NULL THEN
            RAISE EXCEPTION '13b: el ajuste % no tiene concepto de costo; clasifíquelo antes de aterrizar.', v_aj.id
                USING ERRCODE = '22023';
        END IF;

        v_share := CASE WHEN v_qty_total > 0
                        THEN round(v_aj.monto_capitalizado * (v_qty_link / v_qty_total), 2)
                        ELSE 0 END;

        IF v_share <= 0 THEN
            CONTINUE;
        END IF;

        INSERT INTO public.app_dat_recepcion_producto_costo
            (id_recepcion_producto, id_tipo_costo, monto_usd, monto_promedio_anterior,
             id_compra_recepcion, id_ajuste)
        WITH bases AS (
            SELECT b.id_recepcion_producto, b.id_producto, b.cantidad_base
              FROM public.fn_fdi_compra_recepcion_bases(p_id_compra_recepcion) b
        ),
        tot AS (SELECT COALESCE(sum(b.cantidad_base), 0) AS qty_total FROM bases b),
        destino AS (
            SELECT b.id_recepcion_producto
              FROM bases b
             ORDER BY b.cantidad_base DESC, b.id_recepcion_producto ASC
             LIMIT 1
        ),
        prorr AS (
            SELECT b.id_recepcion_producto,
                   b.id_producto,
                   round(v_share * b.cantidad_base / NULLIF(t.qty_total, 0), 2) AS monto
              FROM bases b CROSS JOIN tot t
        ),
        residuo AS (
            SELECT v_share - COALESCE(sum(p.monto), 0) AS r FROM prorr p
        )
        SELECT p.id_recepcion_producto,
               v_aj.id_tipo_costo,
               p.monto + CASE WHEN p.id_recepcion_producto = (SELECT d.id_recepcion_producto FROM destino d)
                              THEN (SELECT r FROM residuo) ELSE 0 END,
               COALESCE((SELECT pc.monto_promedio_usd
                           FROM public.app_dat_producto_costo pc
                          WHERE pc.id_producto = p.id_producto
                            AND pc.id_tipo_costo = v_aj.id_tipo_costo), 0),
               p_id_compra_recepcion,
               v_aj.id
          FROM prorr p;

        SELECT COALESCE(sum(c.monto_usd), 0) INTO v_aj_suma
          FROM public.app_dat_recepcion_producto_costo c
         WHERE c.id_compra_recepcion = p_id_compra_recepcion
           AND c.id_ajuste = v_aj.id
           AND c.revertido_at IS NULL;

        IF abs(v_aj_suma - v_share) >= 0.005 THEN
            RAISE EXCEPTION '13b: el ajuste % descuadra en la recepción %: Σ % vs %',
                v_aj.id, v_link.id_operacion, v_aj_suma, v_share
                USING ERRCODE = 'P0001';
        END IF;

        v_aj_total := v_aj_total + v_share;
        v_aj_count := v_aj_count + 1;
    END LOOP;

    IF v_cargo_usd = 0 AND v_aj_count = 0 THEN
        v_status := 'sin_cargo';
    END IF;

    RETURN jsonb_build_object(
        'status', v_status,
        'capitaliza', v_aj_count > 0 OR v_cargo_usd > 0,
        'id_compra_recepcion', p_id_compra_recepcion,
        'id_compra', v_link.id_compra,
        'id_operacion', v_link.id_operacion,
        'origen_pago', v_link.origen_pago,
        'moneda_operacion', v_moneda_op,
        'moneda_vinculo', v_moneda_link,
        'tasa_usd', v_tasa,
        'tasa_origen', v_tasa_origen,
        'tasa_forzada_usd', v_tasa_forzada,
        'monto_importadora', v_link.monto_importadora,
        'monto_bruto_importadora', v_link.monto_bruto_importadora,
        'reembolso_importadora', v_link.reembolso_importadora,
        'cargo_usd', v_cargo_usd,
        'id_tipo_costo_importadora', v_id_tipo,
        'lineas', v_lineas,
        'base_total', v_base_total,
        'filas_borradas', v_borradas,
        'filas_insertadas', v_insertadas,
        'cargo_filas', v_filas,
        'cargo_suma', v_suma,
        'ajustes_cantidad', v_aj_count,
        'ajustes_aplicados', v_aj_total);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_fdi_compra_repartir_aterrizaje(bigint, numeric)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_compra_repartir_aterrizaje(bigint, numeric)
    TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
