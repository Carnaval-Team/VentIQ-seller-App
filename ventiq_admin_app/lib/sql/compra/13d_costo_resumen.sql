-- ============================================================================
-- 13d_costo_resumen.sql — resumen del aterrizaje sin doble conteo
--
-- Entorno: `newa` (qhprswhhfasrikhawjoz). NO aplicar en main.
-- Fecha: 2026-11-26 · Plan: docs/planes/fondo-inversion/15-plan-compras-costos.md
--
-- Qué corrige:
--   · `valor_vinculado` = valor REALMENTE recibido (monto_valorizado), no la
--     suma de bases declaradas (que podía ser 2× la compra).
--   · bruto / reembolso / neto de importadora por separado.
--   · `ajustes_aplicados` = filas de costo con `id_ajuste` (lo que de verdad se
--     capitalizó), no una regla proporcional de pantalla.
--   · `costo_factura_unit` = precio de la línea (no `costo_real`, que ya trae
--     la capitalización) y `costo_aterrizado_unit` = factura + adicionales/u.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_fdi_compra_costo_resumen(p_id_compra bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_c           record;
    v_valor       numeric := 0;
    v_cargo       numeric := 0;
    v_bruto       numeric := 0;
    v_reemb       numeric := 0;
    v_pct_decl    numeric;
    v_esperado    numeric;
    v_ajustes     numeric := 0;
    v_pedido      numeric := 0;
    v_recibido    numeric := 0;
    v_pct_rec     numeric := 0;
    v_aj_aplicado numeric := 0;
    v_vinculos    jsonb := '[]'::jsonb;
    v_lineas      jsonb := '[]'::jsonb;
BEGIN
    SELECT * INTO v_c FROM public.fdi_dat_compra WHERE id = p_id_compra;
    IF v_c.id IS NULL THEN
        RAISE EXCEPTION 'Compra % no encontrada', p_id_compra USING ERRCODE = 'P0002';
    END IF;
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_can_access_tienda(v_c.id_tienda), false) THEN
        RAISE EXCEPTION 'Sin acceso a la compra %', p_id_compra USING ERRCODE = '42501';
    END IF;

    -- Valor recibido: el escrito en el vínculo; si es 0 (legado), se reconstruye
    -- desde las líneas atribuidas.
    SELECT COALESCE(sum(
               CASE WHEN COALESCE(r.monto_valorizado, 0) > 0
                    THEN r.monto_valorizado
                    ELSE COALESCE((SELECT sum(rl.cantidad_recibida * COALESCE(rl.costo_unitario_aplicado, 0))
                                     FROM public.fdi_dat_compra_recepcion_linea rl
                                    WHERE rl.id_compra_recepcion = r.id), 0)
               END), 0),
           COALESCE(sum(r.monto_importadora), 0),
           COALESCE(sum(r.monto_bruto_importadora), 0),
           COALESCE(sum(r.reembolso_importadora), 0)
      INTO v_valor, v_cargo, v_bruto, v_reemb
      FROM public.fdi_dat_compra_recepcion r
     WHERE r.id_compra = p_id_compra;

    -- % declarado en la compra (ajuste de tipo Importadora con base %).
    SELECT max(a.valor) INTO v_pct_decl
      FROM public.fdi_dat_compra_ajuste a
      JOIN public.app_cont_tipo_costo t ON t.id = a.id_tipo_costo
     WHERE a.id_compra = p_id_compra
       AND lower(btrim(t.denominacion)) = 'importadora'
       AND a.base = 'porcentaje';

    IF v_pct_decl IS NOT NULL THEN
        v_esperado := round(v_valor * v_pct_decl / 100, 2);
    END IF;

    -- Ajustes que capitalizan y NO son la importadora (esa va por su vínculo).
    SELECT COALESCE(sum(a.monto_capitalizado), 0) INTO v_ajustes
      FROM public.fdi_dat_compra_ajuste a
      LEFT JOIN public.app_cont_tipo_costo t ON t.id = a.id_tipo_costo
     WHERE a.id_compra = p_id_compra
       AND a.afecta_inventario IS TRUE
       AND (t.id IS NULL OR lower(btrim(t.denominacion)) <> 'importadora');

    -- Lo realmente capitalizado por ajustes en las recepciones de esta compra.
    SELECT COALESCE(sum(c.monto_usd), 0) INTO v_aj_aplicado
      FROM public.app_dat_recepcion_producto_costo c
      JOIN public.fdi_dat_compra_recepcion r ON r.id = c.id_compra_recepcion
     WHERE r.id_compra = p_id_compra
       AND c.id_ajuste IS NOT NULL
       AND c.revertido_at IS NULL;

    -- Avance por unidades.
    SELECT COALESCE(sum(l.cantidad), 0),
           COALESCE(sum(LEAST(
               COALESCE((SELECT sum(rl.cantidad_recibida)
                          FROM public.fdi_dat_compra_recepcion_linea rl
                         WHERE rl.id_compra_linea = l.id), 0),
               l.cantidad)), 0)
      INTO v_pedido, v_recibido
      FROM public.fdi_dat_compra_linea l
     WHERE l.id_compra = p_id_compra;

    IF v_pedido > 0 THEN
        v_pct_rec := round(v_recibido / v_pedido, 6);
    END IF;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'id_compra_recepcion', r.id,
               'id_operacion', r.id_operacion,
               'valor_recibido', COALESCE(NULLIF(r.monto_valorizado, 0), (SELECT sum(rl.cantidad_recibida * COALESCE(rl.costo_unitario_aplicado, 0)) FROM public.fdi_dat_compra_recepcion_linea rl WHERE rl.id_compra_recepcion = r.id), 0),
               'base_importadora', r.base_importadora,
               'monto_importadora', r.monto_importadora,
               'monto_bruto_importadora', r.monto_bruto_importadora,
               'pct_importadora', r.pct_importadora,
               'reembolso_importadora', r.reembolso_importadora,
               'origen_pago', r.origen_pago,
               'moneda', r.moneda,
               'tasa_usd_aplicada', r.tasa_usd_aplicada,
               'confirmada_con_exceso', r.confirmada_con_exceso,
               'filas_costo', (SELECT count(*)
                                 FROM public.app_dat_recepcion_producto_costo c
                                WHERE c.id_compra_recepcion = r.id
                                  AND c.revertido_at IS NULL),
               'filas_revertidas', (SELECT count(*)
                                      FROM public.app_dat_recepcion_producto_costo c
                                     WHERE c.id_compra_recepcion = r.id
                                       AND c.revertido_at IS NOT NULL),
               'estado_operacion', (SELECT e.estado
                                      FROM public.app_dat_estado_operacion e
                                     WHERE e.id_operacion = r.id_operacion
                                     ORDER BY e.id DESC
                                     LIMIT 1)
           ) ORDER BY r.id), '[]'::jsonb)
      INTO v_vinculos
      FROM public.fdi_dat_compra_recepcion r
     WHERE r.id_compra = p_id_compra;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'id_recepcion_producto', x.id,
               'id_operacion', x.id_operacion,
               'id_producto', x.id_producto,
               'producto', x.producto,
               'cantidad', x.cantidad,
               'costo_factura_unit', x.costo_factura,
               'costos_total_usd', x.costos_usd,
               'costos_total_moneda', x.costos_moneda,
               'tasa_usd', x.tasa,
               'costo_aterrizado_unit', x.aterrizado,
               'precio_venta_cup', (SELECT v.precio_venta_cup
                                        FROM public.app_v_precio_venta_base_vigente v
                                       WHERE v.id_producto = x.id_producto
                                         AND v.id_variante IS NULL
                                       ORDER BY v.id DESC
                                       LIMIT 1),
               'costo_aterrizado_cup', CASE WHEN v_c.moneda_total = 'USD'
                    THEN round(x.aterrizado * public.fn_fdi_tasa_cup_por_usd_tienda(v_c.id_tienda), 2)
                    ELSE x.aterrizado END,
               'conceptos', (SELECT COALESCE(jsonb_agg(jsonb_build_object('denominacion', t.denominacion, 'monto', c.monto_usd) ORDER BY c.id), '[]'::jsonb)
                                 FROM public.app_dat_recepcion_producto_costo c
                                 LEFT JOIN public.app_cont_tipo_costo t ON t.id = c.id_tipo_costo
                                WHERE c.id_recepcion_producto = x.id
                                  AND c.revertido_at IS NULL
                                  AND c.id_compra_recepcion IN (SELECT r3.id FROM public.fdi_dat_compra_recepcion r3 WHERE r3.id_compra = p_id_compra))
           ) ORDER BY x.id), '[]'::jsonb)
      INTO v_lineas
      FROM (
            SELECT rp.id,
                   rp.id_operacion,
                   rp.id_producto,
                   pr.denominacion AS producto,
                   rp.cantidad,
                   COALESCE(crl.costo_unitario_aplicado, rp.precio_unitario, 0) AS costo_factura,
                   COALESCE(cs.total, 0) AS costos_usd,
                   round(COALESCE(cs.total, 0) * tr.tasa, 2) AS costos_moneda,
                   tr.tasa,
                   round(COALESCE(crl.costo_unitario_aplicado, rp.precio_unitario, 0)
                         + COALESCE(cs.total, 0) / NULLIF(rp.cantidad, 0), 4) AS aterrizado
              FROM public.app_dat_recepcion_productos rp
              JOIN public.app_dat_producto pr ON pr.id = rp.id_producto
              LEFT JOIN LATERAL (
                    SELECT crl2.costo_unitario_aplicado
                      FROM public.fdi_dat_compra_recepcion_linea crl2
                      JOIN public.fdi_dat_compra_recepcion r2 ON r2.id = crl2.id_compra_recepcion
                     WHERE crl2.id_recepcion_producto = rp.id
                       AND r2.id_compra = p_id_compra
                     ORDER BY crl2.id
                     LIMIT 1
                   ) crl ON true
              LEFT JOIN LATERAL (
                    SELECT sum(c.monto_usd) AS total
                      FROM public.app_dat_recepcion_producto_costo c
                     WHERE c.id_recepcion_producto = rp.id
                       AND c.revertido_at IS NULL
                       AND c.id_compra_recepcion IN (
                            SELECT r3.id FROM public.fdi_dat_compra_recepcion r3
                             WHERE r3.id_compra = p_id_compra)
                   ) cs ON true
              LEFT JOIN LATERAL (
                    SELECT COALESCE(
                        (SELECT r.tasa_usd_aplicada
                           FROM public.fdi_dat_compra_recepcion r
                          WHERE r.id_operacion = rp.id_operacion
                            AND r.id_compra = p_id_compra
                          ORDER BY r.id
                          LIMIT 1),
                        (SELECT o.tasa_cambio_aplicada
                           FROM public.app_dat_operacion_recepcion o
                          WHERE o.id_operacion = rp.id_operacion),
                        1) AS tasa
                   ) tr ON true
             WHERE rp.id_operacion IN (
                       SELECT r.id_operacion FROM public.fdi_dat_compra_recepcion r
                        WHERE r.id_compra = p_id_compra)
           ) x;

    RETURN jsonb_build_object(
        'id_compra', p_id_compra,
        'estado', v_c.estado,
        'moneda', v_c.moneda_total,
        'total_mercancia', v_c.total_mercancia,
        'total_ajustes', v_c.total_ajustes,
        'valor_vinculado', v_valor,
        'valor_recibido', v_valor,
        'cargo_importadora', v_cargo,
        'cargo_bruto_importadora', v_bruto,
        'reembolso_importadora', v_reemb,
        'pct_importadora_declarado', v_pct_decl,
        'pct_importadora_efectivo',
            CASE WHEN v_valor > 0 THEN round(v_bruto / v_valor * 100, 4) END,
        'cargo_esperado', v_esperado,
        'desvio_importadora',
            CASE WHEN v_esperado IS NOT NULL THEN round(v_cargo - v_esperado, 2) END,
        'ajustes_globales', v_ajustes,
        'pedido_cantidad', v_pedido,
        'recibido_cantidad', v_recibido,
        'pct_recibido', v_pct_rec,
        'ajustes_aplicados', v_aj_aplicado,
        'ajustes_por_asignar', round(v_ajustes - v_aj_aplicado, 2),
        'total_aterrizado', round(v_valor + v_cargo + v_aj_aplicado, 2),
        'vinculos', v_vinculos,
        'lineas', v_lineas);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_fdi_compra_costo_resumen(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_compra_costo_resumen(bigint)
    TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
