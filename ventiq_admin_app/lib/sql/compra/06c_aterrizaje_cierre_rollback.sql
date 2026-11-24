-- ============================================================================
-- 06c_aterrizaje_cierre_rollback.sql — reversa de la fase 6c
--
-- REQUIERE: 06c_aterrizaje_cierre.sql aplicado.
--
-- Qué deshace:
--   0. La reversa de costo al cancelar: trigger, `trg_fdi_estado_revertir_costo`,
--      `fn_fdi_recepcion_revertir_costo`, las 4 columnas de reversa, su CHECK
--      y su índice. Y devuelve `_v2` a su cuerpo anterior (sin el filtro de
--      revertidas).
--   1. `fn_cont_tipo_costo_eliminar(bigint)`
--   2. `fn_cont_tipo_costo_guardar(bigint, text, text, boolean)`
--   3. `fn_fdi_exigir_superadmin()`
--   4. `fn_fdi_compra_costo_resumen(bigint)`
--   5. Restaura la política y los GRANT que tenía `app_cont_tipo_costo` antes
--      de 06c: `FOR ALL` a `authenticated` con `USING true` y `GRANT ALL` a
--      `anon` y `authenticated`. **Eso reabre el agujero** que 06c cerró
--      (cualquier usuario autenticado podía escribir el nomenclador por
--      PostgREST); se restaura porque un rollback debe dejar la base como
--      estaba, y el aviso queda aquí y en la bitácora del plan.
--
-- Qué NO restaura, a propósito:
--   · `fn_actualizar_precio_promedio_recepcion_v3(bigint, jsonb)`. Era código
--     muerto (0 referencias en el cliente) y su cuerpo queda en el commit
--     anterior de la rama. Restaurarla obligaría a mantener viva una función
--     que pondera mal.
--
-- Es transaccional: o sale todo o no sale nada.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Reversa: trigger, funciones y columnas
--
--    Primero se devuelve `_v2` a su cuerpo anterior (sin el filtro de
--    revertidas), porque si no quedaría leyendo columnas que se retiran.
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_fdi_estado_revertir_costo ON public.app_dat_estado_operacion;
DROP FUNCTION IF EXISTS public.trg_fdi_estado_revertir_costo();
DROP FUNCTION IF EXISTS public.fn_fdi_recepcion_revertir_costo(bigint, bigint, uuid, text);

DO $$
DECLARE
    v_def text;
    v_new text;
    v_n   integer;
BEGIN
    SELECT pg_get_functiondef('public.fn_actualizar_precio_promedio_recepcion_v2(bigint,jsonb)'::regprocedure)
      INTO v_def;

    v_new := replace(v_def, ' AND rpc.revertido_at IS NULL', '');
    v_new := replace(v_new, ' AND x.revertido_at IS NULL', '');

    SELECT count(*) INTO v_n FROM regexp_matches(v_new, 'revertido_at', 'g');
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'Rollback 06c: _v2 sigue mencionando revertido_at (% veces); no se retiran las columnas.', v_n;
    END IF;

    EXECUTE v_new;
END;
$$;

ALTER TABLE public.app_dat_recepcion_producto_costo
    DROP CONSTRAINT IF EXISTS chk_recepcion_costo_reversa_motivo;

DROP INDEX IF EXISTS public.idx_recepcion_producto_costo_vigente;

ALTER TABLE public.app_dat_recepcion_producto_costo
    DROP COLUMN IF EXISTS id_estado_reversa,
    DROP COLUMN IF EXISTS motivo_reversa,
    DROP COLUMN IF EXISTS revertido_por,
    DROP COLUMN IF EXISTS revertido_at;

-- ---------------------------------------------------------------------------
-- 2) Retirar las funciones de 06c (dependientes primero)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.fn_cont_tipo_costo_eliminar(bigint);
DROP FUNCTION IF EXISTS public.fn_cont_tipo_costo_guardar(bigint, text, text, boolean);
DROP FUNCTION IF EXISTS public.fn_fdi_exigir_superadmin();
DROP FUNCTION IF EXISTS public.fn_fdi_compra_costo_resumen(bigint);

-- ---------------------------------------------------------------------------
-- 3) Restaurar la política y los permisos previos del catálogo
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS app_cont_tipo_costo_lectura ON public.app_cont_tipo_costo;
DROP POLICY IF EXISTS app_cont_tipo_costo_authenticated_all ON public.app_cont_tipo_costo;

CREATE POLICY app_cont_tipo_costo_authenticated_all
    ON public.app_cont_tipo_costo
    FOR ALL TO authenticated
    USING (true)
    WITH CHECK (true);

GRANT ALL ON public.app_cont_tipo_costo TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4) Verificación final
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v integer;
BEGIN
    IF to_regprocedure('public.fn_cont_tipo_costo_eliminar(bigint)') IS NOT NULL THEN
        RAISE EXCEPTION 'Rollback 06c: fn_cont_tipo_costo_eliminar sigue existiendo';
    END IF;
    IF to_regprocedure('public.fn_cont_tipo_costo_guardar(bigint,text,text,boolean)') IS NOT NULL THEN
        RAISE EXCEPTION 'Rollback 06c: fn_cont_tipo_costo_guardar sigue existiendo';
    END IF;
    IF to_regprocedure('public.fn_fdi_exigir_superadmin()') IS NOT NULL THEN
        RAISE EXCEPTION 'Rollback 06c: fn_fdi_exigir_superadmin sigue existiendo';
    END IF;
    IF to_regprocedure('public.fn_fdi_compra_costo_resumen(bigint)') IS NOT NULL THEN
        RAISE EXCEPTION 'Rollback 06c: fn_fdi_compra_costo_resumen sigue existiendo';
    END IF;
    IF to_regprocedure('public.fn_fdi_recepcion_revertir_costo(bigint,bigint,uuid,text)') IS NOT NULL THEN
        RAISE EXCEPTION 'Rollback 06c: fn_fdi_recepcion_revertir_costo sigue existiendo';
    END IF;

    SELECT count(*) INTO v FROM pg_trigger
     WHERE tgrelid = 'public.app_dat_estado_operacion'::regclass
       AND tgname = 'trg_fdi_estado_revertir_costo';
    IF v <> 0 THEN
        RAISE EXCEPTION 'Rollback 06c: el trigger de reversa sigue existiendo';
    END IF;

    SELECT count(*) INTO v FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'app_dat_recepcion_producto_costo'
       AND column_name IN ('revertido_at','revertido_por','motivo_reversa','id_estado_reversa');
    IF v <> 0 THEN
        RAISE EXCEPTION 'Rollback 06c: quedan % columnas de reversa', v;
    END IF;

    SELECT count(*) INTO v
      FROM pg_policy
     WHERE polrelid = 'public.app_cont_tipo_costo'::regclass
       AND polname = 'app_cont_tipo_costo_authenticated_all'
       AND polcmd = '*';
    IF v <> 1 THEN
        RAISE EXCEPTION 'Rollback 06c: no se restauró la política previa del catálogo (% de 1)', v;
    END IF;

    -- El catálogo y sus 4 tipos siguen ahí: 06c nunca los tocó.
    SELECT count(*) INTO v FROM public.app_cont_tipo_costo;
    IF v < 4 THEN
        RAISE EXCEPTION 'Rollback 06c: el catálogo perdió filas (% < 4)', v;
    END IF;

    -- `_v3` no se restaura (código muerto): se comprueba que sigue retirada.
    IF to_regprocedure('public.fn_actualizar_precio_promedio_recepcion_v3(bigint,jsonb)') IS NOT NULL THEN
        RAISE NOTICE 'Rollback 06c: _v3 reapareció por fuera de este script.';
    END IF;

    RAISE NOTICE 'Rollback 06c aplicado: reversa y RPCs retiradas, catálogo y política previa restaurados. _v3 NO se restaura (código muerto).';
END;
$$;

COMMIT;