-- ============================================================================
-- 13a_vincular_recepcion.sql — base recibida, atribución de líneas y origen
--
-- Entorno: `newa` (qhprswhhfasrikhawjoz). NO aplicar en main.
-- Fecha: 2026-11-26 · Plan: docs/planes/fondo-inversion/15-plan-compras-costos.md
--
-- Cambios:
--   1. `fn_fdi_compra_vincular_recepcion`:
--      · si `p_base_importadora` viene NULL/0, la calcula con el VALOR RECIBIDO
--        (Σ cantidad_recibida × costo de la línea de compra);
--      · escribe `monto_valorizado` del vínculo (antes quedaba en 0);
--      · rellena `fdi_dat_compra_recepcion_linea.id_recepcion_producto`;
--      · valida reembolso ≤ bruto;
--      · RECHAZA `origen_pago = 'fondo'` (decisión del dueño, 2026-11-26).
--   2. `fn_fdi_compra_recepcion_bases` devuelve `cantidad_base` y usa el costo
--      de la línea vinculada (nunca `costo_real`, que ya trae capitalización).
--
-- No recalcula compras ni recepciones existentes.
-- ============================================================================

-- ── 1. Bases de reparto (cantidad base + costo de factura) ─────────────────
DROP FUNCTION IF EXISTS public.fn_fdi_compra_recepcion_bases(bigint);

CREATE OR REPLACE FUNCTION public.fn_fdi_compra_recepcion_bases(p_id_compra_recepcion bigint)
RETURNS TABLE(
    id_recepcion_producto bigint,
    id_producto bigint,
    cantidad numeric,
    cantidad_base numeric,
    costo_unitario numeric,
    base numeric,
    origen_costo text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_id_operacion bigint;
    v_vinculos     integer;
    v_ids          bigint[];
BEGIN
    SELECT r.id_operacion INTO v_id_operacion
      FROM public.fdi_dat_compra_recepcion r
     WHERE r.id = p_id_compra_recepcion;

    IF NOT FOUND THEN
        RAISE EXCEPTION '13a: vínculo compra↔recepción % no encontrado', p_id_compra_recepcion
            USING ERRCODE = 'P0002';
    END IF;

    SELECT count(*) INTO v_vinculos
      FROM public.fdi_dat_compra_recepcion r
     WHERE r.id_operacion = v_id_operacion;

    SELECT array_agg(x.id_rp) INTO v_ids
      FROM (
            SELECT crl.id_recepcion_producto AS id_rp
              FROM public.fdi_dat_compra_recepcion_linea crl
             WHERE crl.id_compra_recepcion = p_id_compra_recepcion
               AND crl.id_recepcion_producto IS NOT NULL
            UNION
            SELECT c.id_recepcion_producto
              FROM public.app_dat_recepcion_producto_costo c
             WHERE c.id_compra_recepcion = p_id_compra_recepcion
           ) x;

    IF v_vinculos > 1 AND COALESCE(array_length(v_ids, 1), 0) = 0 THEN
        RAISE EXCEPTION '13a: la recepción % cubre % compras y el vínculo % no tiene líneas atribuidas; no se puede repartir sin adivinar.',
            v_id_operacion, v_vinculos, p_id_compra_recepcion
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    WITH linea AS (
        SELECT rp.id              AS id_rp,
               rp.id_producto     AS id_prod,
               rp.cantidad        AS cant,
               COALESCE(fr.factor, 1) AS factor,
               (SELECT crl.costo_unitario_aplicado
                  FROM public.fdi_dat_compra_recepcion_linea crl
                 WHERE crl.id_compra_recepcion = p_id_compra_recepcion
                   AND crl.id_recepcion_producto = rp.id
                 ORDER BY crl.id
                 LIMIT 1)         AS costo_explicito,
               (SELECT CASE WHEN count(*) = 1
                            THEN min(crl.costo_unitario_aplicado) END
                  FROM public.fdi_dat_compra_recepcion_linea crl
                  JOIN public.fdi_dat_compra_linea cl ON cl.id = crl.id_compra_linea
                 WHERE crl.id_compra_recepcion = p_id_compra_recepcion
                   AND cl.id_producto = rp.id_producto
                   AND cl.id_variante IS NOT DISTINCT FROM rp.id_variante) AS costo_unico,
               rp.precio_unitario AS precio
          FROM public.app_dat_recepcion_productos rp
          LEFT JOIN LATERAL (
                SELECT COALESCE(f.factor_rel, 1) AS factor
                  FROM public.app_dat_producto_presentacion pp
                  LEFT JOIN LATERAL public.fn_presentaciones_producto(pp.id_producto) f
                         ON f.id_presentacion = pp.id
                 WHERE pp.id = rp.id_presentacion
                 LIMIT 1
          ) fr ON true
         WHERE rp.id_operacion = v_id_operacion
           AND (v_vinculos = 1 OR rp.id = ANY(COALESCE(v_ids, '{}'::bigint[])))
    ),
    resuelto AS (
        SELECT li.id_rp,
               li.id_prod,
               li.cant,
               li.cant * COALESCE(li.factor, 1) AS cant_base,
               COALESCE(li.costo_explicito, li.costo_unico, li.precio, 0) AS costo,
               CASE WHEN li.costo_explicito IS NOT NULL THEN 'compra_linea_vinculada'
                    WHEN li.costo_unico     IS NOT NULL THEN 'compra_linea_unica'
                    WHEN li.precio          IS NOT NULL THEN 'precio_unitario'
                    ELSE 'ninguno' END                                  AS origen
          FROM linea li
    )
    SELECT res.id_rp,
           res.id_prod,
           res.cant,
           res.cant_base,
           res.costo,
           round(res.cant * res.costo, 6),
           res.origen
      FROM resuelto res
     ORDER BY res.id_rp;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_fdi_compra_recepcion_bases(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_compra_recepcion_bases(bigint)
    TO authenticated, service_role;

-- ── 2. Vincular recepción ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_fdi_compra_vincular_recepcion(
    p_id_operacion bigint,
    p_id_compra bigint,
    p_lineas jsonb,
    p_confirmar_exceso boolean DEFAULT false,
    p_pct_importadora numeric DEFAULT 0,
    p_base_importadora numeric DEFAULT 0,
    p_reembolso_importadora numeric DEFAULT 0,
    p_origen_pago text DEFAULT 'wallet_importadora'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_c record; v_op_tienda bigint; v_linea jsonb; v_l record;
    v_pend numeric; v_recibido numeric; v_link bigint; v_pend_total numeric := 0;
    v_nuevo text; v_pct numeric := COALESCE(p_pct_importadora, 0);
    v_base numeric := COALESCE(p_base_importadora, 0);
    v_reemb numeric := COALESCE(p_reembolso_importadora, 0);
    v_bruto numeric; v_monto numeric; v_lineas_ok integer := 0;
BEGIN
    SELECT * INTO v_c FROM public.fdi_dat_compra WHERE id = p_id_compra FOR UPDATE;
    IF v_c.id IS NULL THEN RAISE EXCEPTION 'Compra % no encontrada', p_id_compra USING ERRCODE = 'P0002'; END IF;
    IF auth.uid() IS NOT NULL AND NOT COALESCE(public.fn_user_is_gerente_or_superadmin(v_c.id_tienda), false) THEN
        RAISE EXCEPTION 'Solo gerente o superadmin' USING ERRCODE = '42501'; END IF;
    IF v_c.estado NOT IN ('reservada','pagada','entrega_parcial') THEN
        RAISE EXCEPTION 'No se recibe una compra en estado %', v_c.estado USING ERRCODE = '22023'; END IF;

    SELECT id_tienda INTO v_op_tienda FROM public.app_dat_operaciones WHERE id = p_id_operacion;
    IF v_op_tienda IS NULL OR v_op_tienda <> v_c.id_tienda THEN
        RAISE EXCEPTION 'La recepción % no pertenece a la tienda de la compra', p_id_operacion USING ERRCODE = 'P0002'; END IF;
    IF EXISTS (SELECT 1 FROM public.fdi_dat_compra_recepcion WHERE id_operacion = p_id_operacion) THEN
        RAISE EXCEPTION 'La recepción % ya está vinculada a una compra', p_id_operacion USING ERRCODE = '22023'; END IF;
    IF p_lineas IS NULL OR jsonb_typeof(p_lineas) IS DISTINCT FROM 'array' OR jsonb_array_length(p_lineas) = 0 THEN
        RAISE EXCEPTION 'Indique las líneas recibidas' USING ERRCODE = '22023'; END IF;
    IF v_pct < 0 OR v_pct > 100 THEN
        RAISE EXCEPTION 'El porcentaje de importadora debe estar en [0, 100]' USING ERRCODE = '22023'; END IF;
    IF v_reemb < 0 THEN RAISE EXCEPTION 'El reembolso no puede ser negativo' USING ERRCODE = '22023'; END IF;
    IF p_origen_pago NOT IN ('wallet_importadora','wallet_proveedor','externo') THEN
        -- Decisión del dueño: el cargo de la recepción no se declara «fondo».
        -- El fondo ya pagó `total_financiado`; si debe pagar este cargo, va como
        -- ajuste posterior financiable desde el detalle de la compra.
        RAISE EXCEPTION 'Origen de pago «fondo» no se admite en la recepción: use wallet_importadora o externo, o declare el cargo como ajuste de la compra'
            USING ERRCODE = '22023';
    END IF;

    -- Base: si no viene, es el valor realmente recibido de la factura.
    IF v_base <= 0 THEN
        FOR v_linea IN SELECT * FROM jsonb_array_elements(p_lineas) LOOP
            SELECT l.id, l.costo_unitario INTO v_l
              FROM public.fdi_dat_compra_linea l
             WHERE l.id = (v_linea->>'id_compra_linea')::bigint AND l.id_compra = p_id_compra;
            IF v_l.id IS NULL THEN
                RAISE EXCEPTION 'La línea % no pertenece a la compra', v_linea->>'id_compra_linea' USING ERRCODE = '22023';
            END IF;
            v_base := v_base + round((v_linea->>'cantidad_recibida')::numeric * COALESCE(v_l.costo_unitario, 0), 2);
        END LOOP;
    END IF;

    v_bruto := round(v_base * v_pct / 100, 2);
    IF v_reemb > v_bruto THEN
        RAISE EXCEPTION 'El reembolso (%) supera el cargo bruto de importadora (%)', v_reemb, v_bruto
            USING ERRCODE = '22023';
    END IF;
    v_monto := v_bruto - v_reemb;

    INSERT INTO public.fdi_dat_compra_recepcion (id_compra, id_tienda, id_operacion, monto_valorizado,
        moneda, tasa_a_base, pct_importadora, base_importadora, monto_importadora,
        reembolso_importadora, origen_pago, created_by)
    VALUES (p_id_compra, v_c.id_tienda, p_id_operacion, v_base, v_c.moneda_total, 1,
        v_pct, v_base, v_monto, v_reemb, p_origen_pago, auth.uid())
    RETURNING id INTO v_link;

    FOR v_linea IN SELECT * FROM jsonb_array_elements(p_lineas) LOOP
        SELECT l.id, l.id_producto, l.cantidad INTO v_l
        FROM public.fdi_dat_compra_linea l
        WHERE l.id = (v_linea->>'id_compra_linea')::bigint AND l.id_compra = p_id_compra;
        IF v_l.id IS NULL THEN
            RAISE EXCEPTION 'La línea % no pertenece a la compra', v_linea->>'id_compra_linea' USING ERRCODE = '22023'; END IF;

        v_recibido := (v_linea->>'cantidad_recibida')::numeric;
        IF v_recibido IS NULL OR v_recibido <= 0 THEN
            RAISE EXCEPTION 'Cantidad recibida inválida en la línea %', v_l.id USING ERRCODE = '22023'; END IF;

        SELECT COALESCE(sum(rl.cantidad_recibida), 0) INTO v_pend
        FROM public.fdi_dat_compra_recepcion_linea rl WHERE rl.id_compra_linea = v_l.id;
        v_pend := v_l.cantidad - v_pend;

        IF v_recibido > v_pend AND NOT p_confirmar_exceso THEN
            RAISE EXCEPTION 'La línea % tiene pendiente % y se intentan recibir %. Confirma el exceso si es intencionado.',
                v_l.id, v_pend, v_recibido USING ERRCODE = '22023'; END IF;

        INSERT INTO public.fdi_dat_compra_recepcion_linea (id_compra_recepcion, id_tienda,
            id_compra_linea, cantidad_recibida, costo_unitario_aplicado)
        VALUES (v_link, v_c.id_tienda, v_l.id, v_recibido,
            (SELECT costo_unitario FROM public.fdi_dat_compra_linea WHERE id = v_l.id));
        v_lineas_ok := v_lineas_ok + 1;
    END LOOP;

    -- Atribución explícita: cada línea del vínculo apunta a su línea real de
    -- recepción. Sin esto el reparto de la segunda recepción no sabe de quién
    -- es cada costo.
    UPDATE public.fdi_dat_compra_recepcion_linea crl
       SET id_recepcion_producto = (
            SELECT rp.id
              FROM public.app_dat_recepcion_productos rp
              JOIN public.fdi_dat_compra_linea cl ON cl.id = crl.id_compra_linea
             WHERE rp.id_operacion = p_id_operacion
               AND rp.id_producto = cl.id_producto
               AND rp.id_variante IS NOT DISTINCT FROM cl.id_variante
             ORDER BY rp.id
             LIMIT 1)
     WHERE crl.id_compra_recepcion = v_link;

    -- El valor recibido queda escrito en el vínculo (el detalle lo mostraba 0).
    UPDATE public.fdi_dat_compra_recepcion
       SET monto_valorizado = v_base
     WHERE id = v_link;

    SELECT COALESCE(sum(GREATEST(l.cantidad - COALESCE((
                SELECT sum(rl.cantidad_recibida) FROM public.fdi_dat_compra_recepcion_linea rl
                WHERE rl.id_compra_linea = l.id), 0), 0)), 0)
      INTO v_pend_total
    FROM public.fdi_dat_compra_linea l WHERE l.id_compra = p_id_compra;

    v_nuevo := CASE WHEN v_pend_total <= 0 THEN 'completada' ELSE 'entrega_parcial' END;

    UPDATE public.fdi_dat_compra SET estado = v_nuevo, updated_at = now() WHERE id = p_id_compra;

    INSERT INTO public.fdi_hist_estado_compra (id_compra, id_tienda, estado_anterior, estado_nuevo,
        origen, motivo, created_by)
    VALUES (p_id_compra, v_c.id_tienda, v_c.estado, v_nuevo, 'automatico',
        'Recepción ' || p_id_operacion, auth.uid());

    RETURN jsonb_build_object('status','ok','id_compra',p_id_compra,'id_operacion',p_id_operacion,
        'estado',v_nuevo,'pendiente_total',v_pend_total,'id_compra_recepcion',v_link,
        'base_importadora',v_base,'monto_bruto_importadora',v_bruto,
        'reembolso_importadora',v_reemb,'cargo_importadora',v_monto,
        'lineas',v_lineas_ok);
END; $function$;

REVOKE ALL ON FUNCTION public.fn_fdi_compra_vincular_recepcion(bigint,bigint,jsonb,boolean,numeric,numeric,numeric,text)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_compra_vincular_recepcion(bigint,bigint,jsonb,boolean,numeric,numeric,numeric,text)
    TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
