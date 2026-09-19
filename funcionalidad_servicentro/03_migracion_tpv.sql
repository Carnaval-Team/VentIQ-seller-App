-- ============================================================================
-- 03 · Migración: servicentro por TPV (no por tienda)
-- ============================================================================
-- Proyecto Supabase: vsieeihstajlrdvpuooh
-- Idempotente. Aplicar en SQL Editor.
-- Plan: docs/PLAN_SERVICENTRO.md (modo / columnas / lista por TPV).
--
-- CONTENIDO
--   3.1  Columnas en app_dat_tpv
--   3.2  Migrar flags desde configuracion_tienda → todos los TPV de esa tienda
--   3.3  app_dat_servicentro_producto: id_tpv (reemplaza id_tienda)
--   3.4  Quitar flags de configuracion_tienda + trigger de exclusión tienda
--   3.5  RLS policies actualizadas (vía tpv → tienda)
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 3.1 Flags en TPV
-- ----------------------------------------------------------------------------
ALTER TABLE public.app_dat_tpv
    ADD COLUMN IF NOT EXISTS modo_servicentro boolean NOT NULL DEFAULT false;

ALTER TABLE public.app_dat_tpv
    ADD COLUMN IF NOT EXISTS servicentro_columnas smallint NOT NULL DEFAULT 2;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conname = 'app_dat_tpv_servicentro_columnas_check'
    ) THEN
        ALTER TABLE public.app_dat_tpv
            ADD CONSTRAINT app_dat_tpv_servicentro_columnas_check
            CHECK (servicentro_columnas BETWEEN 1 AND 4);
    END IF;
END$$;

COMMENT ON COLUMN public.app_dat_tpv.modo_servicentro
    IS 'Si true, este TPV opera en modo servicentro (solo combustibles). Independiente de otros TPV de la misma tienda.';

COMMENT ON COLUMN public.app_dat_tpv.servicentro_columnas
    IS 'Columnas del grid de combustibles en este TPV (1–4).';


-- ----------------------------------------------------------------------------
-- 3.2 Migrar modo/columnas de tienda → TPVs de esa tienda
-- ----------------------------------------------------------------------------
UPDATE public.app_dat_tpv tpv
   SET modo_servicentro = true,
       servicentro_columnas = COALESCE(ct.servicentro_columnas, 2)
  FROM public.app_dat_configuracion_tienda ct
 WHERE ct.id_tienda = tpv.id_tienda
   AND COALESCE(ct.modo_servicentro, false) = true;


-- ----------------------------------------------------------------------------
-- 3.3 Lista de combustibles por TPV
-- ----------------------------------------------------------------------------
ALTER TABLE public.app_dat_servicentro_producto
    ADD COLUMN IF NOT EXISTS id_tpv bigint;

-- Quitar UNIQUE por tienda ANTES de clonar (varios TPV comparten tienda)
ALTER TABLE public.app_dat_servicentro_producto
    DROP CONSTRAINT IF EXISTS app_dat_servicentro_producto_tienda_producto_unique;

-- Si había filas por tienda, clonarlas a cada TPV de esa tienda
INSERT INTO public.app_dat_servicentro_producto (id_tienda, id_tpv, id_producto, orden, color)
SELECT sp.id_tienda, tpv.id, sp.id_producto, sp.orden, sp.color
  FROM public.app_dat_servicentro_producto sp
  JOIN public.app_dat_tpv tpv ON tpv.id_tienda = sp.id_tienda
 WHERE sp.id_tpv IS NULL;

-- Borrar filas huérfanas sin TPV (las originales sin id_tpv)
DELETE FROM public.app_dat_servicentro_producto WHERE id_tpv IS NULL;

-- FK + NOT NULL
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conname = 'app_dat_servicentro_producto_id_tpv_fkey'
    ) THEN
        ALTER TABLE public.app_dat_servicentro_producto
            ADD CONSTRAINT app_dat_servicentro_producto_id_tpv_fkey
            FOREIGN KEY (id_tpv) REFERENCES public.app_dat_tpv (id) ON DELETE CASCADE;
    END IF;
END$$;

ALTER TABLE public.app_dat_servicentro_producto
    ALTER COLUMN id_tpv SET NOT NULL;

-- Mantener id_tienda rellenado desde el TPV (denormalizado para RLS/consultas)
UPDATE public.app_dat_servicentro_producto sp
   SET id_tienda = tpv.id_tienda
  FROM public.app_dat_tpv tpv
 WHERE tpv.id = sp.id_tpv
   AND sp.id_tienda IS DISTINCT FROM tpv.id_tienda;

-- UNIQUE por TPV + producto (el UNIQUE viejo ya se dropeó arriba)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conname = 'app_dat_servicentro_producto_tpv_producto_unique'
    ) THEN
        ALTER TABLE public.app_dat_servicentro_producto
            ADD CONSTRAINT app_dat_servicentro_producto_tpv_producto_unique
            UNIQUE (id_tpv, id_producto);
    END IF;
END$$;

CREATE INDEX IF NOT EXISTS idx_servicentro_producto_tpv_orden
    ON public.app_dat_servicentro_producto (id_tpv, orden);

-- Trigger: producto combustible de la misma tienda que el TPV
CREATE OR REPLACE FUNCTION public.fn_trg_servicentro_producto_valido()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id_tienda_tpv  bigint;
    v_id_tienda_prod bigint;
    v_es_combustible boolean;
    v_deleted_at     timestamp;
BEGIN
    SELECT tpv.id_tienda INTO v_id_tienda_tpv
      FROM public.app_dat_tpv tpv
     WHERE tpv.id = NEW.id_tpv;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SERVICENTRO_PRODUCTO_INVALIDO: el TPV % no existe', NEW.id_tpv
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    NEW.id_tienda := v_id_tienda_tpv;

    SELECT p.id_tienda, p.es_combustible, p.deleted_at
      INTO v_id_tienda_prod, v_es_combustible, v_deleted_at
      FROM public.app_dat_producto p
     WHERE p.id = NEW.id_producto;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SERVICENTRO_PRODUCTO_INVALIDO: el producto % no existe', NEW.id_producto
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    IF v_deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'SERVICENTRO_PRODUCTO_INVALIDO: el producto % está eliminado', NEW.id_producto
            USING ERRCODE = 'check_violation';
    END IF;

    IF v_id_tienda_prod IS DISTINCT FROM v_id_tienda_tpv THEN
        RAISE EXCEPTION
            'SERVICENTRO_PRODUCTO_INVALIDO: el producto % no pertenece a la tienda del TPV %',
            NEW.id_producto, NEW.id_tpv
            USING ERRCODE = 'check_violation';
    END IF;

    IF NOT COALESCE(v_es_combustible, false) THEN
        RAISE EXCEPTION
            'SERVICENTRO_PRODUCTO_INVALIDO: el producto % no tiene es_combustible = true',
            NEW.id_producto
            USING ERRCODE = 'check_violation';
    END IF;

    NEW.updated_at := now();
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_servicentro_producto_valido
    ON public.app_dat_servicentro_producto;

CREATE TRIGGER trg_servicentro_producto_valido
    BEFORE INSERT OR UPDATE OF id_tpv, id_producto, id_tienda
    ON public.app_dat_servicentro_producto
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_trg_servicentro_producto_valido();


-- ----------------------------------------------------------------------------
-- 3.4 Quitar modo a nivel tienda + trigger de exclusión con restaurante
-- ----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_config_tienda_modos_excluyentes
    ON public.app_dat_configuracion_tienda;

DROP FUNCTION IF EXISTS public.fn_trg_config_tienda_modos_excluyentes();

ALTER TABLE public.app_dat_configuracion_tienda
    DROP COLUMN IF EXISTS modo_servicentro;

ALTER TABLE public.app_dat_configuracion_tienda
    DROP COLUMN IF EXISTS servicentro_columnas;


-- ----------------------------------------------------------------------------
-- 3.5 RLS: policies usan id_tienda (sigue en la fila, derivado del TPV)
--     (ya existen; se recrean por claridad)
-- ----------------------------------------------------------------------------
ALTER TABLE public.app_dat_servicentro_producto ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS servicentro_producto_select ON public.app_dat_servicentro_producto;
DROP POLICY IF EXISTS servicentro_producto_insert ON public.app_dat_servicentro_producto;
DROP POLICY IF EXISTS servicentro_producto_update ON public.app_dat_servicentro_producto;
DROP POLICY IF EXISTS servicentro_producto_delete ON public.app_dat_servicentro_producto;

CREATE POLICY servicentro_producto_select
    ON public.app_dat_servicentro_producto
    FOR SELECT TO authenticated
    USING (public.fn_user_can_read_tienda(id_tienda));

CREATE POLICY servicentro_producto_insert
    ON public.app_dat_servicentro_producto
    FOR INSERT TO authenticated
    WITH CHECK (public.fn_user_is_gerente_or_superadmin(id_tienda));

CREATE POLICY servicentro_producto_update
    ON public.app_dat_servicentro_producto
    FOR UPDATE TO authenticated
    USING (public.fn_user_is_gerente_or_superadmin(id_tienda))
    WITH CHECK (public.fn_user_is_gerente_or_superadmin(id_tienda));

CREATE POLICY servicentro_producto_delete
    ON public.app_dat_servicentro_producto
    FOR DELETE TO authenticated
    USING (public.fn_user_is_gerente_or_superadmin(id_tienda));
