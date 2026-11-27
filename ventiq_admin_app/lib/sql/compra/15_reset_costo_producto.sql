-- ============================================================================
-- 15_reset_costo_producto.sql — reset MANUAL del costo de referencia
--
-- Entorno: `newa` (qhprswhhfasrikhawjoz). NO aplicar en main.
-- Fecha: 2026-11-26 · Plan: docs/planes/fondo-inversion/15-plan-compras-costos.md
--
-- Decisión del dueño: no se recostea nada automáticamente. Si un producto quedó
-- con un promedio absurdo (los casos 2, 3, 10 y 18), el dueño/gerente puede
-- reiniciarlo a partir de su ÚLTIMA recepción, con motivo y rastro.
--
-- No toca ventas, COGS, recepciones ni movimientos. Solo:
--   · `app_dat_producto_presentacion.precio_promedio` (base + derivadas),
--   · `app_dat_producto_costo.monto_promedio_usd` por concepto,
--   · deja fila en `app_hist_reset_costo`.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.app_hist_reset_costo (
    id                bigserial PRIMARY KEY,
    id_producto       bigint NOT NULL REFERENCES public.app_dat_producto(id) ON DELETE CASCADE,
    id_tienda         bigint NOT NULL REFERENCES public.app_dat_tienda(id),
    promedio_anterior numeric,
    promedio_nuevo    numeric,
    motivo            text NOT NULL,
    created_by        uuid,
    created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_hist_reset_costo_producto
    ON public.app_hist_reset_costo (id_producto, created_at DESC);

ALTER TABLE public.app_hist_reset_costo ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS app_hist_reset_costo_select ON public.app_hist_reset_costo;
CREATE POLICY app_hist_reset_costo_select
    ON public.app_hist_reset_costo
    FOR SELECT TO authenticated
    USING (public.fn_user_can_access_tienda(id_tienda));

REVOKE ALL ON public.app_hist_reset_costo FROM anon;
GRANT SELECT ON public.app_hist_reset_costo TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_reset_costo_promedio_producto(
    p_id_producto bigint,
    p_motivo text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_tienda     bigint;
    v_r          record;
    v_prev       numeric;
    v_extras     numeric := 0;
    v_unit       numeric;
    v_c          record;
    v_unit_tipo  numeric;
    v_hist       bigint;
BEGIN
    IF btrim(COALESCE(p_motivo, '')) = '' THEN
        RAISE EXCEPTION 'Indique el motivo del reinicio de costo' USING ERRCODE = '22023';
    END IF;

    SELECT id_tienda INTO v_tienda FROM public.app_dat_producto WHERE id = p_id_producto;
    IF v_tienda IS NULL THEN
        RAISE EXCEPTION 'Producto % no encontrado', p_id_producto USING ERRCODE = 'P0002';
    END IF;

    IF auth.uid() IS NOT NULL
       AND NOT (COALESCE(public.fn_user_is_gerente_or_superadmin(v_tienda), false)
                OR COALESCE(public.fn_user_is_dueno(v_tienda), false)) THEN
        RAISE EXCEPTION 'Solo dueño, gerente o superadmin de la tienda % puede reiniciar el costo', v_tienda
            USING ERRCODE = '42501';
    END IF;

    SELECT rp.id, rp.id_operacion, rp.cantidad, rp.precio_unitario
      INTO v_r
      FROM public.app_dat_recepcion_productos rp
     WHERE rp.id_producto = p_id_producto
     ORDER BY rp.id DESC
     LIMIT 1;

    IF v_r.id IS NULL THEN
        RAISE EXCEPTION 'El producto % no tiene recepciones de las que partir', p_id_producto
            USING ERRCODE = 'P0002';
    END IF;
    IF COALESCE(v_r.cantidad, 0) <= 0 THEN
        RAISE EXCEPTION 'La última recepción del producto % no tiene cantidad válida', p_id_producto
            USING ERRCODE = '22023';
    END IF;

    SELECT COALESCE(sum(c.monto_usd), 0) INTO v_extras
      FROM public.app_dat_recepcion_producto_costo c
     WHERE c.id_recepcion_producto = v_r.id
       AND c.revertido_at IS NULL;

    v_unit := COALESCE(v_r.precio_unitario, 0) + (v_extras / v_r.cantidad);

    SELECT pp.precio_promedio::numeric INTO v_prev
      FROM public.app_dat_producto_presentacion pp
      JOIN public.fn_presentaciones_producto(p_id_producto) f
        ON f.id_presentacion = pp.id
     WHERE f.es_base
     ORDER BY pp.id
     LIMIT 1;

    -- Base y derivadas en una sola pasada, con el factor de la RPC (no con el
    -- flag `es_base` de la tabla, que en algunos productos está desalineado).
    UPDATE public.app_dat_producto_presentacion pp
       SET precio_promedio = (v_unit * COALESCE(f.factor_rel, 1))::real
      FROM public.fn_presentaciones_producto(p_id_producto) f
     WHERE f.id_presentacion = pp.id;

    -- Costo por concepto: el unitario de la última recepción.
    FOR v_c IN
        SELECT c.id_tipo_costo, sum(c.monto_usd) AS total
          FROM public.app_dat_recepcion_producto_costo c
         WHERE c.id_recepcion_producto = v_r.id
           AND c.revertido_at IS NULL
         GROUP BY c.id_tipo_costo
    LOOP
        v_unit_tipo := v_c.total / v_r.cantidad;
        INSERT INTO public.app_dat_producto_costo
            (id_producto, id_tipo_costo, monto_usd, monto_promedio_usd, activo)
        VALUES
            (p_id_producto, v_c.id_tipo_costo, v_unit_tipo, v_unit_tipo, true)
        ON CONFLICT (id_producto, id_tipo_costo)
        DO UPDATE SET
            monto_usd = EXCLUDED.monto_usd,
            monto_promedio_usd = EXCLUDED.monto_promedio_usd;
    END LOOP;

    INSERT INTO public.app_hist_reset_costo
        (id_producto, id_tienda, promedio_anterior, promedio_nuevo, motivo, created_by)
    VALUES
        (p_id_producto, v_tienda, v_prev, v_unit, btrim(p_motivo), auth.uid())
    RETURNING id INTO v_hist;

    RETURN jsonb_build_object(
        'status', 'ok',
        'id_producto', p_id_producto,
        'promedio_anterior', v_prev,
        'promedio_nuevo', v_unit,
        'desde_recepcion', v_r.id,
        'id_operacion', v_r.id_operacion,
        'historial_id', v_hist);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_reset_costo_promedio_producto(bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_reset_costo_promedio_producto(bigint, text)
    TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
