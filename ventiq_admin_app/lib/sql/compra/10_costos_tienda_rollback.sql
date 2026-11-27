-- ============================================================================
-- 10_costos_tienda_rollback.sql — revierte 10_costos_tienda.sql
--
-- Devuelve el nomenclador al estado de 06c: global, sin `id_tienda`, con las
-- funciones de 4 argumentos y permiso solo de superadmin.
--
-- Guarda: si ya hay conceptos con tienda, NO borra nada; falla y pide decidir
-- qué hacer con ellos (no se destruyen datos por un rollback).
-- ============================================================================

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM public.app_cont_tipo_costo WHERE id_tienda IS NOT NULL) THEN
        RAISE EXCEPTION 'Hay conceptos de costo con tienda; elimínelos o muévalos antes del rollback'
            USING ERRCODE = '22023';
    END IF;
END;
$$;

DROP FUNCTION IF EXISTS public.fn_cont_tipo_costo_guardar(bigint, text, text, boolean, bigint);

CREATE OR REPLACE FUNCTION public.fn_cont_tipo_costo_guardar(
    p_id              bigint  DEFAULT NULL,
    p_denominacion    text    DEFAULT NULL,
    p_descripcion     text    DEFAULT NULL,
    p_afecta_margen   boolean DEFAULT true
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
BEGIN
    PERFORM public.fn_fdi_exigir_superadmin();

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
        IF lower(btrim(v_prev.denominacion)) = 'importadora'
           AND lower(v_nombre) <> 'importadora' THEN
            RAISE EXCEPTION 'El concepto Importadora se resuelve por nombre en el aterrizaje: no se puede renombrar'
                USING ERRCODE = '22023';
        END IF;
    END IF;

    IF EXISTS (SELECT 1 FROM public.app_cont_tipo_costo t
                WHERE lower(btrim(t.denominacion)) = lower(v_nombre)
                  AND (p_id IS NULL OR t.id <> p_id)) THEN
        RAISE EXCEPTION 'Ya existe un concepto con la denominación %', v_nombre
            USING ERRCODE = '22023';
    END IF;

    IF p_id IS NULL THEN
        INSERT INTO public.app_cont_tipo_costo (denominacion, descripcion, naturaleza, afecta_margen)
        VALUES (v_nombre, v_desc, 1, COALESCE(p_afecta_margen, true))
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
        'denominacion', v_nombre,
        'creado', p_id IS NULL);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_cont_tipo_costo_guardar(bigint, text, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_cont_tipo_costo_guardar(bigint, text, text, boolean)
    TO authenticated, service_role;

-- `fn_cont_tipo_costo_eliminar` no cambia de firma; basta devolver la guarda
-- de superadmin (sin ámbito de tienda).
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
    PERFORM public.fn_fdi_exigir_superadmin();

    SELECT * INTO v_tipo FROM public.app_cont_tipo_costo WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Concepto de costo % no encontrado', p_id USING ERRCODE = 'P0002';
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

DROP INDEX IF EXISTS public.ux_cont_tipo_costo_ambito_denom;
ALTER TABLE public.app_cont_tipo_costo DROP CONSTRAINT IF EXISTS app_cont_tipo_costo_id_tienda_fkey;
ALTER TABLE public.app_cont_tipo_costo DROP COLUMN IF EXISTS id_tienda;

NOTIFY pgrst, 'reload schema';
