-- ============================================================================
-- 10_costos_tienda.sql — Conceptos de costo POR TIENDA
--
-- Entorno: `newa` (qhprswhhfasrikhawjoz). NO aplicar en main.
-- Fecha: 2026-11-26 · Plan: docs/planes/fondo-inversion/15-plan-compras-costos.md
--
-- Qué hace
--   1. `app_cont_tipo_costo.id_tienda` (NULL = global; con tienda = propio).
--      No reescribe ninguna fila: los 4 conceptos sembrados siguen globales.
--   2. Índice único por ámbito + denominación normalizada.
--   3. `fn_cont_tipo_costo_guardar` / `_eliminar` con ámbito:
--        · global  → solo superadmin
--        · tienda  → dueño, gerente de esa tienda o superadmin
--      Se borra la firma vieja (4 args) para no dejar overload.
--
-- No toca datos financieros ni compras. Es aditivo y reversible
-- (10_costos_tienda_rollback.sql).
-- ============================================================================

-- ── 1. Ámbito ───────────────────────────────────────────────────────────────
ALTER TABLE public.app_cont_tipo_costo
    ADD COLUMN IF NOT EXISTS id_tienda bigint;

ALTER TABLE public.app_cont_tipo_costo
    DROP CONSTRAINT IF EXISTS app_cont_tipo_costo_id_tienda_fkey;

ALTER TABLE public.app_cont_tipo_costo
    ADD CONSTRAINT app_cont_tipo_costo_id_tienda_fkey
    FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id);

COMMENT ON COLUMN public.app_cont_tipo_costo.id_tienda IS
    'NULL = concepto global de la suite; con id = concepto propio de esa tienda.';

CREATE UNIQUE INDEX IF NOT EXISTS ux_cont_tipo_costo_ambito_denom
    ON public.app_cont_tipo_costo (
        COALESCE(id_tienda, 0),
        lower(btrim(denominacion))
    );

-- ── 2. Guardar (crear/editar) con ámbito ───────────────────────────────────
DROP FUNCTION IF EXISTS public.fn_cont_tipo_costo_guardar(bigint, text, text, boolean);

CREATE OR REPLACE FUNCTION public.fn_cont_tipo_costo_guardar(
    p_id              bigint  DEFAULT NULL,
    p_denominacion    text    DEFAULT NULL,
    p_descripcion     text    DEFAULT NULL,
    p_afecta_margen   boolean DEFAULT true,
    p_id_tienda       bigint  DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_nombre  text := btrim(COALESCE(p_denominacion, ''));
    v_desc    text := NULLIF(btrim(COALESCE(p_descripcion, '')), '');
    v_prev    record;
    v_id      bigint;
    v_tienda  bigint := p_id_tienda;
BEGIN
    IF v_nombre = '' THEN
        RAISE EXCEPTION 'La denominación del concepto es obligatoria' USING ERRCODE = '22023';
    END IF;
    IF length(v_nombre) > 80 THEN
        RAISE EXCEPTION 'La denominación no puede pasar de 80 caracteres' USING ERRCODE = '22023';
    END IF;

    IF p_id IS NOT NULL THEN
        SELECT * INTO v_prev FROM public.app_cont_tipo_costo WHERE id = p_id FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Concepto de costo % no encontrado', p_id USING ERRCODE = 'P0002';
        END IF;
        -- Un concepto no cambia de ámbito: global ↔ tienda rompería el reparto
        -- que resuelve «Importadora» primero por tienda y luego global.
        IF v_tienda IS NOT NULL AND v_tienda IS DISTINCT FROM v_prev.id_tienda THEN
            RAISE EXCEPTION 'Un concepto de costo no cambia de ámbito (global ↔ tienda)'
                USING ERRCODE = '22023';
        END IF;
        v_tienda := v_prev.id_tienda;

        -- El aterrizaje resuelve este tipo por denominación: renombrarlo
        -- rompería el reparto con P0002 sin que nadie lo relacione.
        IF lower(btrim(v_prev.denominacion)) = 'importadora'
           AND lower(v_nombre) <> 'importadora' THEN
            RAISE EXCEPTION 'El concepto Importadora se resuelve por nombre en el aterrizaje: no se puede renombrar'
                USING ERRCODE = '22023';
        END IF;
    END IF;

    -- ── Permisos por ámbito ────────────────────────────────────────────────
    IF v_tienda IS NULL THEN
        PERFORM public.fn_fdi_exigir_superadmin();
    ELSE
        IF NOT EXISTS (SELECT 1 FROM public.app_dat_tienda t WHERE t.id = v_tienda) THEN
            RAISE EXCEPTION 'La tienda % no existe', v_tienda USING ERRCODE = 'P0002';
        END IF;
        IF auth.uid() IS NOT NULL
           AND NOT (COALESCE(public.fn_user_is_gerente_or_superadmin(v_tienda), false)
                    OR COALESCE(public.fn_user_is_dueno(v_tienda), false)) THEN
            RAISE EXCEPTION 'Solo dueño, gerente o superadmin de la tienda % puede gestionar sus conceptos de costo', v_tienda
                USING ERRCODE = '42501';
        END IF;
    END IF;

    IF EXISTS (SELECT 1 FROM public.app_cont_tipo_costo t
                WHERE COALESCE(t.id_tienda, 0) = COALESCE(v_tienda, 0)
                  AND lower(btrim(t.denominacion)) = lower(v_nombre)
                  AND (p_id IS NULL OR t.id <> p_id)) THEN
        RAISE EXCEPTION 'Ya existe un concepto con la denominación % en ese ámbito', v_nombre
            USING ERRCODE = '22023';
    END IF;

    IF p_id IS NULL THEN
        -- naturaleza 1 = Gasto (app_nom_naturaleza_costo). Un costo adicional
        -- nunca es ingreso; no se acepta por parámetro para no inventarlo.
        INSERT INTO public.app_cont_tipo_costo
            (denominacion, descripcion, naturaleza, afecta_margen, id_tienda)
        VALUES (v_nombre, v_desc, 1, COALESCE(p_afecta_margen, true), v_tienda)
        RETURNING id INTO v_id;
    ELSE
        UPDATE public.app_cont_tipo_costo
           SET denominacion  = v_nombre,
               descripcion   = v_desc,
               afecta_margen = COALESCE(p_afecta_margen, afecta_margen)
         WHERE id = p_id;
        v_id := p_id;
    END IF;

    RETURN jsonb_build_object(
        'status', 'ok',
        'id', v_id,
        'id_tienda', v_tienda,
        'denominacion', v_nombre,
        'creado', p_id IS NULL);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_cont_tipo_costo_guardar(bigint, text, text, boolean, bigint)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_cont_tipo_costo_guardar(bigint, text, text, boolean, bigint)
    TO authenticated, service_role;

-- ── 3. Eliminar con ámbito ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_cont_tipo_costo_eliminar(p_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tipo  record;
    v_refs  bigint;
BEGIN
    SELECT * INTO v_tipo FROM public.app_cont_tipo_costo WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Concepto de costo % no encontrado', p_id USING ERRCODE = 'P0002';
    END IF;

    IF v_tipo.id_tienda IS NULL THEN
        PERFORM public.fn_fdi_exigir_superadmin();
    ELSIF auth.uid() IS NOT NULL
          AND NOT (COALESCE(public.fn_user_is_gerente_or_superadmin(v_tipo.id_tienda), false)
                   OR COALESCE(public.fn_user_is_dueno(v_tipo.id_tienda), false)) THEN
        RAISE EXCEPTION 'Solo dueño, gerente o superadmin de la tienda % puede eliminar sus conceptos de costo', v_tipo.id_tienda
            USING ERRCODE = '42501';
    END IF;

    IF lower(btrim(v_tipo.denominacion)) = 'importadora' THEN
        RAISE EXCEPTION 'El concepto Importadora no se puede eliminar: el aterrizaje lo resuelve por nombre'
            USING ERRCODE = '22023';
    END IF;

    SELECT (SELECT count(*) FROM public.app_dat_recepcion_producto_costo WHERE id_tipo_costo = p_id)
         + (SELECT count(*) FROM public.app_dat_producto_costo         WHERE id_tipo_costo = p_id)
         + (SELECT count(*) FROM public.fdi_dat_compra_ajuste          WHERE id_tipo_costo = p_id)
      INTO v_refs;

    IF v_refs > 0 THEN
        RAISE EXCEPTION 'El concepto % está en uso (% referencia(s)); no se elimina', v_tipo.denominacion, v_refs
            USING ERRCODE = '22023';
    END IF;

    DELETE FROM public.app_cont_tipo_costo WHERE id = p_id;

    RETURN jsonb_build_object('status', 'ok', 'id', p_id, 'eliminado', true);
EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE EXCEPTION 'El concepto % está en uso y no se puede eliminar', v_tipo.denominacion
            USING ERRCODE = '22023';
END;
$$;

REVOKE ALL ON FUNCTION public.fn_cont_tipo_costo_eliminar(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_cont_tipo_costo_eliminar(bigint) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
