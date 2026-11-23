-- ============================================================================
-- 06d_ajustes_por_financiar.sql — Fase 6d: costo que llega después de pagar
--
-- REQUIERE: 04 (liquidación) y 06c aplicados.
--
-- Regla del plan: un costo que llega **después de pagar la compra** no cambia
-- `total_financiado`; se financia con **su propia reserva y su propio pago** y
-- deja un documento de ajuste que actualiza la valoración.
--
-- Qué añade:
--   1. `total_financiado` deja de recalcularse cuando la compra ya no está en
--      `creada`. El recálculo sigue actualizando `total_mercancia`,
--      `total_ajustes` y `costo_aterrizado` (que sí crece con documentos).
--   2. Columnas de trazabilidad: `id_ajuste` en la reserva, en el pago y en la
--      fila de costo; `idempotency_key` en el ajuste.
--   3. `fn_fdi_compra_ajuste_agregar(...)`: agrega un ajuste a una compra ya
--      pagada y lo deja en `por_financiar` (no toca `total_financiado`).
--   4. `fn_fdi_compra_ajuste_financiar(...)`: cubre el ajuste desde una o
--      varias fuentes del fondo (reserva + pago + movimiento), escribe el
--      costo repartido por valor sobre lo recibido, actualiza el costo unitario
--      del producto y deja el documento en el historial.
--
-- LÍMITES DECLARADOS (no se inventan):
--   · Solo se financia cuando la compra está **completada** (todo recibido).
--     Con entrega parcial el reparto quedaría por asignar y haría falta llevar
--     el acumulado aplicado por ajuste: fuera de esta fase.
--   · Solo `origen_pago = 'fondo'`. Un costo de wallet/externo capitaliza sin
--     desembolso, pero su documento de ajuste tardío no está implementado.
--   · La valoración se actualiza sumando al `precio_promedio` del producto el
--     costo unitario del ajuste (`monto / unidades recibidas`). No se reejecuta
--     `_v2` (volvería a ponderar la recepción entera y duplicaría el costo).
--     El costo de lo ya vendido no se reexpresa (COGS histórico).
--
-- ROLLBACK: 06d_ajustes_por_financiar_rollback.sql
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 0) Preflight
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_falta text := '';
BEGIN
    IF to_regclass('public.fdi_dat_compra_ajuste') IS NULL THEN
        v_falta := v_falta || ' fdi_dat_compra_ajuste;';
    END IF;
    IF to_regclass('public.fdi_dat_compra_reserva') IS NULL THEN
        v_falta := v_falta || ' fdi_dat_compra_reserva;';
    END IF;
    IF to_regclass('public.fdi_dat_compra_pago') IS NULL THEN
        v_falta := v_falta || ' fdi_dat_compra_pago;';
    END IF;
    IF to_regclass('public.app_dat_recepcion_producto_costo') IS NULL THEN
        v_falta := v_falta || ' app_dat_recepcion_producto_costo;';
    END IF;
    IF v_falta <> '' THEN
        RAISE EXCEPTION '06d: faltan tablas:%.', v_falta USING ERRCODE = '42P01';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='app_dat_recepcion_producto_costo'
                      AND column_name='id_compra_recepcion') THEN
        RAISE EXCEPTION '06d: falta 06b (id_compra_recepcion en el costo).' USING ERRCODE = '42P01';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='app_dat_recepcion_producto_costo'
                      AND column_name='revertido_at') THEN
        RAISE EXCEPTION '06d: falta 06c (columnas de reversa).' USING ERRCODE = '42P01';
    END IF;
    IF to_regprocedure('public.fn_fdi_compra_recepcion_bases(bigint)') IS NULL THEN
        RAISE EXCEPTION '06d: falta fn_fdi_compra_recepcion_bases(bigint).' USING ERRCODE = 'P0002';
    END IF;
    IF to_regprocedure('public.fn_fdi_compra_recalcular(bigint)') IS NULL THEN
        RAISE EXCEPTION '06d: falta fn_fdi_compra_recalcular(bigint).' USING ERRCODE = 'P0002';
    END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1) `total_financiado` inmutable tras reservar
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_compra_recalcular(p_id_compra bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_merc   numeric;
    v_aj_tot numeric;
    v_aj_fin numeric;
    v_estado text;
BEGIN
    SELECT estado INTO v_estado FROM public.fdi_dat_compra WHERE id = p_id_compra;

    SELECT COALESCE(sum(costo_linea), 0) INTO v_merc
    FROM public.fdi_dat_compra_linea WHERE id_compra = p_id_compra;

    SELECT COALESCE(sum(monto_capitalizado), 0),
           COALESCE(sum(monto_capitalizado) FILTER (WHERE origen_pago = 'fondo'), 0)
      INTO v_aj_tot, v_aj_fin
    FROM public.fdi_dat_compra_ajuste WHERE id_compra = p_id_compra;

    UPDATE public.fdi_dat_compra
       SET total_mercancia  = v_merc,
           total_ajustes    = v_aj_tot,
           -- El dinero comprometido se congela al salir de 'creada'. Los
           -- ajustes posteriores se financian por su cuenta (06d).
           total_financiado = CASE WHEN v_estado = 'creada'
                                   THEN v_merc + v_aj_fin
                                   ELSE total_financiado END,
           costo_aterrizado = v_merc + v_aj_tot,
           updated_at       = now()
     WHERE id = p_id_compra;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2) Trazabilidad del ajuste
-- ---------------------------------------------------------------------------
ALTER TABLE public.fdi_dat_compra_ajuste
    ADD COLUMN IF NOT EXISTS idempotency_key uuid;

CREATE UNIQUE INDEX IF NOT EXISTS idx_fdi_ajuste_idem
    ON public.fdi_dat_compra_ajuste (idempotency_key)
    WHERE idempotency_key IS NOT NULL;

ALTER TABLE public.fdi_dat_compra_reserva
    ADD COLUMN IF NOT EXISTS id_ajuste bigint REFERENCES public.fdi_dat_compra_ajuste(id);

ALTER TABLE public.fdi_dat_compra_pago
    ADD COLUMN IF NOT EXISTS id_ajuste bigint REFERENCES public.fdi_dat_compra_ajuste(id);

ALTER TABLE public.app_dat_recepcion_producto_costo
    ADD COLUMN IF NOT EXISTS id_ajuste bigint REFERENCES public.fdi_dat_compra_ajuste(id);

CREATE INDEX IF NOT EXISTS idx_fdi_reserva_ajuste
    ON public.fdi_dat_compra_reserva (id_ajuste)
    WHERE id_ajuste IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_recepcion_producto_costo_ajuste
    ON public.app_dat_recepcion_producto_costo (id_ajuste)
    WHERE id_ajuste IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 3) Agregar el ajuste a una compra ya pagada
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_compra_ajuste_agregar(
    p_id_compra       bigint,
    p_id_tipo_costo   bigint,
    p_base            text    DEFAULT 'global',
    p_valor           numeric DEFAULT NULL,
    p_reparto         text    DEFAULT 'valor',
    p_afecta_inventario boolean DEFAULT true,
    p_idempotency_key uuid    DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_c      record;
    v_id     bigint;
    v_existe bigint;
    v_cant   numeric;
    v_monto  numeric;
BEGIN
    IF p_idempotency_key IS NOT NULL THEN
        SELECT id INTO v_existe FROM public.fdi_dat_compra_ajuste
         WHERE idempotency_key = p_idempotency_key;
        IF FOUND THEN
            RETURN jsonb_build_object('status', 'ok', 'id_ajuste', v_existe, 'duplicada', true);
        END IF;
    END IF;

    SELECT * INTO v_c FROM public.fdi_dat_compra WHERE id = p_id_compra FOR UPDATE;
    IF v_c.id IS NULL THEN
        RAISE EXCEPTION 'Compra % no encontrada', p_id_compra USING ERRCODE = 'P0002';
    END IF;
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_is_gerente_or_superadmin(v_c.id_tienda), false) THEN
        RAISE EXCEPTION 'Solo gerente o superadmin' USING ERRCODE = '42501';
    END IF;
    IF v_c.estado NOT IN ('pagada', 'entrega_parcial', 'completada') THEN
        RAISE EXCEPTION 'El ajuste posterior al pago requiere una compra pagada (actual: %)', v_c.estado
            USING ERRCODE = '22023';
    END IF;
    IF p_base NOT IN ('global', 'porcentaje', 'unidad') THEN
        RAISE EXCEPTION 'Base de ajuste inválida: %', p_base USING ERRCODE = '22023';
    END IF;
    IF p_reparto NOT IN ('valor', 'peso', 'cantidad') THEN
        RAISE EXCEPTION 'Reparto inválido: %', p_reparto USING ERRCODE = '22023';
    END IF;
    IF p_valor IS NULL OR p_valor <= 0 THEN
        RAISE EXCEPTION 'El valor del ajuste debe ser > 0' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.app_cont_tipo_costo WHERE id = p_id_tipo_costo) THEN
        RAISE EXCEPTION 'El tipo de costo % no existe', p_id_tipo_costo USING ERRCODE = 'P0002';
    END IF;

    SELECT COALESCE(sum(cantidad), 0) INTO v_cant
      FROM public.fdi_dat_compra_linea WHERE id_compra = p_id_compra;

    v_monto := CASE p_base
                 WHEN 'porcentaje' THEN round(v_c.total_mercancia * p_valor / 100, 2)
                 WHEN 'unidad'     THEN round(p_valor * v_cant, 2)
                 ELSE round(p_valor, 2)
               END;

    INSERT INTO public.fdi_dat_compra_ajuste (
        id_compra, id_tienda, id_tipo_costo, base, valor, reparto,
        monto_capitalizado, afecta_inventario, origen_pago, estado, idempotency_key
    ) VALUES (
        p_id_compra, v_c.id_tienda, p_id_tipo_costo, p_base, p_valor, p_reparto,
        v_monto, COALESCE(p_afecta_inventario, true), 'fondo', 'por_financiar', p_idempotency_key
    ) RETURNING id INTO v_id;

    PERFORM public.fn_fdi_compra_recalcular(p_id_compra);

    INSERT INTO public.fdi_hist_estado_compra
        (id_compra, id_tienda, estado_anterior, estado_nuevo, origen, motivo, created_by)
    VALUES (p_id_compra, v_c.id_tienda, v_c.estado, v_c.estado, 'automatico',
            format('Ajuste de costo #%s agregado por %s %s · queda por financiar',
                   v_id, v_monto, v_c.moneda_total), auth.uid());

    RETURN jsonb_build_object(
        'status', 'ok',
        'id_ajuste', v_id,
        'id_compra', p_id_compra,
        'monto_capitalizado', v_monto,
        'estado', 'por_financiar',
        'total_financiado', v_c.total_financiado);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fdi_compra_ajuste_agregar(bigint, bigint, text, numeric, text, boolean, uuid)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_compra_ajuste_agregar(bigint, bigint, text, numeric, text, boolean, uuid)
    TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4) Financiar el ajuste: reserva + pago propios, reparto y valoración
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_compra_ajuste_financiar(
    p_id_ajuste    bigint,
    p_fuentes      jsonb,
    p_idempotency_key uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_aj        record;
    v_c         record;
    v_fuente    jsonb;
    v_saldo     numeric;
    v_cubierto  numeric := 0;
    v_n_fuentes integer := 0;
    v_base_tot  numeric := 0;
    v_bases     integer := 0;
    v_filas     integer := 0;
    v_mov       bigint;
    v_res_id    bigint;
    v_r         record;
    v_base      bigint;
    v_delta     numeric;
BEGIN
    SELECT * INTO v_aj FROM public.fdi_dat_compra_ajuste WHERE id = p_id_ajuste FOR UPDATE;
    IF v_aj.id IS NULL THEN
        RAISE EXCEPTION 'Ajuste % no encontrado', p_id_ajuste USING ERRCODE = 'P0002';
    END IF;

    IF v_aj.estado = 'financiado' THEN
        RETURN jsonb_build_object('status', 'ok', 'duplicada', true,
                                  'id_ajuste', p_id_ajuste, 'id_compra', v_aj.id_compra);
    END IF;
    IF v_aj.estado <> 'por_financiar' THEN
        RAISE EXCEPTION 'El ajuste % no está por financiar (estado: %)', p_id_ajuste, v_aj.estado
            USING ERRCODE = '22023';
    END IF;
    IF v_aj.origen_pago <> 'fondo' THEN
        RAISE EXCEPTION 'Solo se financia un ajuste con origen de pago fondo (actual: %)', v_aj.origen_pago
            USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_c FROM public.fdi_dat_compra WHERE id = v_aj.id_compra FOR UPDATE;
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_is_gerente_or_superadmin(v_c.id_tienda), false) THEN
        RAISE EXCEPTION 'Solo gerente o superadmin' USING ERRCODE = '42501';
    END IF;
    IF v_c.estado <> 'completada' THEN
        RAISE EXCEPTION 'Complete la recepción de la compra antes de financiar el ajuste (estado: %). Con entrega parcial el reparto quedaría por asignar.', v_c.estado
            USING ERRCODE = '22023';
    END IF;
    IF v_aj.monto_capitalizado IS NULL OR v_aj.monto_capitalizado <= 0 THEN
        RAISE EXCEPTION 'El ajuste % no tiene importe que financiar', p_id_ajuste
            USING ERRCODE = '22023';
    END IF;
    IF p_fuentes IS NULL OR jsonb_typeof(p_fuentes) <> 'array'
       OR jsonb_array_length(p_fuentes) = 0 THEN
        RAISE EXCEPTION 'Indique al menos una fuente del fondo' USING ERRCODE = '22023';
    END IF;

    -- 1) Validar fuentes: cubren el importe exacto y tienen saldo.
    FOR v_fuente IN SELECT * FROM jsonb_array_elements(p_fuentes) LOOP
        IF NULLIF(v_fuente->>'id_cuenta', '') IS NULL
           OR NULLIF(v_fuente->>'id_medio_pago', '') IS NULL
           OR NULLIF(btrim(v_fuente->>'moneda'), '') IS NULL
           OR NULLIF(v_fuente->>'monto', '') IS NULL
           OR NULLIF(v_fuente->>'tasa', '') IS NULL THEN
            RAISE EXCEPTION 'Cada fuente necesita id_cuenta, id_medio_pago, moneda, monto y tasa'
                USING ERRCODE = '22023';
        END IF;
        IF (v_fuente->>'monto')::numeric <= 0
           OR (v_fuente->>'monto')::numeric <> round((v_fuente->>'monto')::numeric, 2)
           OR (v_fuente->>'tasa')::numeric <= 0 THEN
            RAISE EXCEPTION 'Monto (dos decimales) y tasa positivos en cada fuente' USING ERRCODE = '22023';
        END IF;

        SELECT s.saldo INTO v_saldo
          FROM public.fdi_dat_saldo s
          JOIN public.fdi_dat_cuenta c ON c.id = s.id_cuenta
          JOIN public.fdi_dat_concepto co ON co.id = c.id_concepto
          JOIN public.app_nom_medio_pago mp ON mp.id = s.id_medio_pago
         WHERE s.id_tienda = v_c.id_tienda AND c.id_tienda = v_c.id_tienda
           AND co.id_tienda = v_c.id_tienda AND c.activo AND co.activo AND mp.es_activo
           AND s.id_cuenta = (v_fuente->>'id_cuenta')::bigint
           AND s.id_medio_pago = (v_fuente->>'id_medio_pago')::smallint
           AND s.moneda = v_fuente->>'moneda'
         FOR UPDATE OF s;
        IF NOT FOUND OR v_saldo < (v_fuente->>'monto')::numeric THEN
            RAISE EXCEPTION 'Saldo insuficiente o fuente inactiva para el ajuste %', p_id_ajuste
                USING ERRCODE = 'P0002';
        END IF;

        v_cubierto := v_cubierto + round((v_fuente->>'monto')::numeric * (v_fuente->>'tasa')::numeric, 2);
        v_n_fuentes := v_n_fuentes + 1;
    END LOOP;

    IF v_cubierto <> v_aj.monto_capitalizado THEN
        RAISE EXCEPTION 'Las fuentes cubren % y el ajuste necesita %', v_cubierto, v_aj.monto_capitalizado
            USING ERRCODE = '22023';
    END IF;

    -- 2) Reserva propia por fuente, consumida y pagada en el acto.
    FOR v_fuente IN SELECT * FROM jsonb_array_elements(p_fuentes) LOOP
        INSERT INTO public.fdi_dat_compra_reserva (
            id_compra, id_tienda, id_cuenta, id_medio_pago, moneda, monto,
            tasa_a_total, monto_eq_total, estado, id_ajuste, idempotency_key, created_by
        ) VALUES (
            v_c.id, v_c.id_tienda,
            (v_fuente->>'id_cuenta')::bigint, (v_fuente->>'id_medio_pago')::smallint,
            v_fuente->>'moneda', (v_fuente->>'monto')::numeric,
            (v_fuente->>'tasa')::numeric,
            round((v_fuente->>'monto')::numeric * (v_fuente->>'tasa')::numeric, 2),
            'activa', p_id_ajuste, p_idempotency_key, auth.uid()
        ) RETURNING id INTO v_res_id;

        v_mov := public._fdi_aplicar_movimiento(
            v_c.id_tienda,
            (v_fuente->>'id_cuenta')::bigint,
            (v_fuente->>'id_medio_pago')::smallint,
            v_fuente->>'moneda',
            -(v_fuente->>'monto')::numeric,
            'pago_compra',
            p_observacion := format('Ajuste de costo #%s de la compra #%s', p_id_ajuste, v_c.numero_compra),
            p_id_compra   := v_c.id,
            p_tasa        := (v_fuente->>'tasa')::numeric);

        UPDATE public.fdi_dat_compra_reserva
           SET estado = 'consumida', id_movimiento = v_mov, updated_at = now()
         WHERE id = v_res_id;

        INSERT INTO public.fdi_dat_compra_pago (
            id_compra, id_tienda, id_cuenta, id_medio_pago, moneda,
            monto, tasa_a_total, monto_eq_total, origen, id_movimiento,
            id_ajuste, idempotency_key, created_by
        ) VALUES (
            v_c.id, v_c.id_tienda,
            (v_fuente->>'id_cuenta')::bigint, (v_fuente->>'id_medio_pago')::smallint,
            v_fuente->>'moneda',
            (v_fuente->>'monto')::numeric, (v_fuente->>'tasa')::numeric,
            round((v_fuente->>'monto')::numeric * (v_fuente->>'tasa')::numeric, 2),
            'fondo', v_mov, p_id_ajuste, p_idempotency_key, auth.uid()
        );
    END LOOP;

    -- 3) Reparto por valor sobre lo recibido (todas las recepciones vivas de la
    --    compra), con el residuo a la línea de mayor base.
    SELECT count(*), COALESCE(sum(base), 0) INTO v_bases, v_base_tot
      FROM (
        SELECT b.id_recepcion_producto, b.base
          FROM public.fdi_dat_compra_recepcion r
          CROSS JOIN LATERAL public.fn_fdi_compra_recepcion_bases(r.id) b
         WHERE r.id_compra = v_c.id
      ) x;

    IF v_bases = 0 OR v_base_tot <= 0 THEN
        RAISE EXCEPTION 'La compra % no tiene líneas recibidas con base para repartir el ajuste %',
            v_c.id, p_id_ajuste USING ERRCODE = '22023';
    END IF;

    WITH bases AS (
        SELECT r.id AS id_link, b.id_recepcion_producto, b.id_producto, b.base
          FROM public.fdi_dat_compra_recepcion r
          CROSS JOIN LATERAL public.fn_fdi_compra_recepcion_bases(r.id) b
         WHERE r.id_compra = v_c.id
    ),
    tot AS (SELECT COALESCE(sum(base), 0) AS total FROM bases),
    prorr AS (
        SELECT b.id_link, b.id_recepcion_producto, b.id_producto,
               round(v_aj.monto_capitalizado * b.base / NULLIF(t.total, 0), 2) AS monto
          FROM bases b CROSS JOIN tot t
    ),
    destino AS (
        SELECT id_recepcion_producto FROM bases
         ORDER BY base DESC, id_recepcion_producto ASC LIMIT 1
    ),
    residuo AS (SELECT v_aj.monto_capitalizado - COALESCE(sum(monto), 0) AS r FROM prorr)
    INSERT INTO public.app_dat_recepcion_producto_costo (
        id_recepcion_producto, id_tipo_costo, monto_usd,
        monto_promedio_anterior, id_compra_recepcion, id_ajuste
    )
    SELECT p.id_recepcion_producto,
           v_aj.id_tipo_costo,
           p.monto + CASE WHEN p.id_recepcion_producto = (SELECT id_recepcion_producto FROM destino)
                          THEN (SELECT r FROM residuo) ELSE 0 END,
           COALESCE((SELECT pc.monto_promedio_usd
                       FROM public.app_dat_producto_costo pc
                      WHERE pc.id_producto = p.id_producto
                        AND pc.id_tipo_costo = v_aj.id_tipo_costo), 0),
           p.id_link,
           p_id_ajuste
      FROM prorr p;

    GET DIAGNOSTICS v_filas = ROW_COUNT;

    -- 4) Valoración: el costo unitario del producto sube monto/unidades.
    FOR v_r IN
        SELECT c.monto_usd, rp.id_producto, rp.id_presentacion, rp.cantidad,
               COALESCE((SELECT f.factor_rel
                           FROM public.fn_presentaciones_producto(rp.id_producto) f
                          WHERE f.id_presentacion = rp.id_presentacion), 1) AS factor
          FROM public.app_dat_recepcion_producto_costo c
          JOIN public.app_dat_recepcion_productos rp ON rp.id = c.id_recepcion_producto
         WHERE c.id_ajuste = p_id_ajuste
    LOOP
        IF v_r.cantidad IS NULL OR v_r.cantidad <= 0 THEN
            CONTINUE;
        END IF;
        v_delta := round(v_r.monto_usd / (v_r.cantidad * COALESCE(v_r.factor, 1)), 6);
        IF v_delta = 0 THEN
            CONTINUE;
        END IF;

        SELECT f.id_presentacion INTO v_base
          FROM public.fn_presentaciones_producto(v_r.id_producto) f
         WHERE f.es_base LIMIT 1;
        IF v_base IS NULL THEN
            CONTINUE;
        END IF;

        UPDATE public.app_dat_producto_presentacion
           SET precio_promedio = COALESCE(precio_promedio, 0) + v_delta
         WHERE id = v_base;

        UPDATE public.app_dat_producto_presentacion pp
           SET precio_promedio = (SELECT COALESCE(ppb.precio_promedio, 0)
                                    FROM public.app_dat_producto_presentacion ppb
                                   WHERE ppb.id = v_base) * f.factor_rel
          FROM public.fn_presentaciones_producto(v_r.id_producto) f
         WHERE f.id_presentacion = pp.id
           AND pp.id_producto = v_r.id_producto;
    END LOOP;

    UPDATE public.fdi_dat_compra_ajuste
       SET estado = 'financiado'
     WHERE id = p_id_ajuste;

    INSERT INTO public.fdi_hist_estado_compra
        (id_compra, id_tienda, estado_anterior, estado_nuevo, origen, motivo, created_by)
    VALUES (v_c.id, v_c.id_tienda, v_c.estado, v_c.estado, 'automatico',
            format('Ajuste de costo #%s financiado: %s %s desde %s fuente(s), repartido en %s línea(s)',
                   p_id_ajuste, v_aj.monto_capitalizado, v_c.moneda_total, v_n_fuentes, v_filas),
            auth.uid());

    RETURN jsonb_build_object(
        'status', 'ok',
        'id_ajuste', p_id_ajuste,
        'id_compra', v_c.id,
        'financiado', v_aj.monto_capitalizado,
        'fuentes', v_n_fuentes,
        'filas_costo', v_filas,
        'estado', 'financiado');
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fdi_compra_ajuste_financiar(bigint, jsonb, uuid)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_compra_ajuste_financiar(bigint, jsonb, uuid)
    TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5) Verificación del script
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v integer;
BEGIN
    IF to_regprocedure('public.fn_fdi_compra_ajuste_agregar(bigint,bigint,text,numeric,text,boolean,uuid)') IS NULL THEN
        RAISE EXCEPTION '06d: no se creó fn_fdi_compra_ajuste_agregar(...)';
    END IF;
    IF to_regprocedure('public.fn_fdi_compra_ajuste_financiar(bigint,jsonb,uuid)') IS NULL THEN
        RAISE EXCEPTION '06d: no se creó fn_fdi_compra_ajuste_financiar(...)';
    END IF;

    SELECT count(*) INTO v FROM pg_proc p
     WHERE p.oid IN (to_regprocedure('public.fn_fdi_compra_ajuste_agregar(bigint,bigint,text,numeric,text,boolean,uuid)'),
                     to_regprocedure('public.fn_fdi_compra_ajuste_financiar(bigint,jsonb,uuid)'))
       AND p.prosecdef;
    IF v <> 2 THEN
        RAISE EXCEPTION '06d: las 2 RPC deben ser SECURITY DEFINER (% de 2)', v;
    END IF;

    SELECT count(*) INTO v FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'fdi_dat_compra_ajuste'
       AND column_name = 'idempotency_key';
    IF v <> 1 THEN
        RAISE EXCEPTION '06d: falta fdi_dat_compra_ajuste.idempotency_key';
    END IF;

    SELECT count(*) INTO v FROM information_schema.columns
     WHERE table_schema = 'public'
       AND ((table_name = 'fdi_dat_compra_reserva' AND column_name = 'id_ajuste')
         OR (table_name = 'fdi_dat_compra_pago' AND column_name = 'id_ajuste')
         OR (table_name = 'app_dat_recepcion_producto_costo' AND column_name = 'id_ajuste'));
    IF v <> 3 THEN
        RAISE EXCEPTION '06d: faltan columnas id_ajuste (% de 3)', v;
    END IF;

    -- El recálculo ya no mueve total_financiado fuera de 'creada'.
    SELECT count(*) INTO v FROM pg_proc p
     WHERE p.oid = 'public.fn_fdi_compra_recalcular(bigint)'::regprocedure
       AND position('v_estado = ''creada''' in p.prosrc) > 0;
    IF v <> 1 THEN
        RAISE EXCEPTION '06d: fn_fdi_compra_recalcular no quedó con el congelamiento de total_financiado';
    END IF;

    RAISE NOTICE '06d aplicado: total_financiado inmutable, ajustes por_financiar con reserva y pago propios y documento de costo.';
END;
$$;

COMMIT;