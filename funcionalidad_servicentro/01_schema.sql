-- ============================================================================
-- 01 · Fase 1 · Schema modo servicentro
-- ============================================================================
-- Proyecto Supabase: vsieeihstajlrdvpuooh
-- Aplicar en: SQL Editor / MCP. Idempotente.
-- Plan: docs/PLAN_SERVICENTRO.md
--
-- CONTENIDO
--   1.1  app_dat_producto.es_combustible
--   1.2  app_dat_configuracion_tienda.modo_servicentro
--   1.3  app_dat_configuracion_tienda.servicentro_columnas
--   1.4  tabla app_dat_servicentro_producto + RLS + policies (inmediato)
--   1.5  trigger: modos excluyentes (servicentro vs restaurante/cocina)
--   1.6  trigger: producto de la lista debe ser combustible de la misma tienda
--
-- REGLA: tablas nuevas SIEMPRE con ENABLE ROW LEVEL SECURITY + policies
--        en el mismo bloque que el CREATE TABLE (no dejarlo para después).
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1.1 Flag de producto combustible
-- ----------------------------------------------------------------------------
ALTER TABLE public.app_dat_producto
    ADD COLUMN IF NOT EXISTS es_combustible boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.app_dat_producto.es_combustible
    IS 'Si true, el producto puede seleccionarse como combustible en la config de modo servicentro de la tienda.';

CREATE INDEX IF NOT EXISTS idx_producto_tienda_es_combustible
    ON public.app_dat_producto (id_tienda)
    WHERE es_combustible = true AND deleted_at IS NULL;


-- ----------------------------------------------------------------------------
-- 1.2 / 1.3 Config de tienda: modo + columnas del grid
-- ----------------------------------------------------------------------------
ALTER TABLE public.app_dat_configuracion_tienda
    ADD COLUMN IF NOT EXISTS modo_servicentro boolean NOT NULL DEFAULT false;

ALTER TABLE public.app_dat_configuracion_tienda
    ADD COLUMN IF NOT EXISTS servicentro_columnas smallint NOT NULL DEFAULT 2;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
          FROM pg_constraint
         WHERE conname = 'app_dat_configuracion_tienda_servicentro_columnas_check'
    ) THEN
        ALTER TABLE public.app_dat_configuracion_tienda
            ADD CONSTRAINT app_dat_configuracion_tienda_servicentro_columnas_check
            CHECK (servicentro_columnas BETWEEN 1 AND 4);
    END IF;
END$$;

COMMENT ON COLUMN public.app_dat_configuracion_tienda.modo_servicentro
    IS 'Si true, el TPV opera en modo servicentro: solo venta de combustibles con UI de cartas. Excluyente con modo_restaurante / cocina_activa.';

COMMENT ON COLUMN public.app_dat_configuracion_tienda.servicentro_columnas
    IS 'Cantidad de columnas del grid de combustibles en el vendedor (1–4). Default 2.';


-- ----------------------------------------------------------------------------
-- 1.4 Tabla + RLS (RLS va pegado al CREATE — no omitir)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_dat_servicentro_producto
(
    id           bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_tienda    bigint      NOT NULL,
    id_producto  bigint      NOT NULL,
    orden        smallint    NOT NULL DEFAULT 0,
    color        text        NOT NULL DEFAULT '#64748B',
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT app_dat_servicentro_producto_id_tienda_fkey
        FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda (id) ON DELETE CASCADE,
    CONSTRAINT app_dat_servicentro_producto_id_producto_fkey
        FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto (id) ON DELETE CASCADE,
    CONSTRAINT app_dat_servicentro_producto_tienda_producto_unique
        UNIQUE (id_tienda, id_producto),
    CONSTRAINT app_dat_servicentro_producto_color_hex_check
        CHECK (color ~ '^#[0-9A-Fa-f]{6}$')
);

-- RLS inmediato (obligatorio en toda tabla nueva)
ALTER TABLE public.app_dat_servicentro_producto ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_servicentro_producto_tienda_orden
    ON public.app_dat_servicentro_producto (id_tienda, orden);

COMMENT ON TABLE public.app_dat_servicentro_producto
    IS 'Combustibles habilitados por tienda para modo servicentro: orden de visualización y color de carta en el TPV. RLS obligatorio.';

COMMENT ON COLUMN public.app_dat_servicentro_producto.orden
    IS 'Orden de aparición en el grid del vendedor (menor primero).';

COMMENT ON COLUMN public.app_dat_servicentro_producto.color
    IS 'Color de la carta en hex #RRGGBB (por tienda).';

REVOKE ALL ON public.app_dat_servicentro_producto FROM PUBLIC;
REVOKE ALL ON public.app_dat_servicentro_producto FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE
    ON public.app_dat_servicentro_producto
    TO authenticated;

-- Helpers para policies (boolean, aptos para RLS)
CREATE OR REPLACE FUNCTION public.fn_user_can_read_tienda(p_id_tienda bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
  SELECT EXISTS (
      SELECT 1 FROM public.app_dat_gerente g
       WHERE g.uuid = auth.uid() AND g.id_tienda = p_id_tienda
  ) OR EXISTS (
      SELECT 1 FROM public.app_dat_supervisor s
       WHERE s.uuid = auth.uid() AND s.id_tienda = p_id_tienda
  ) OR EXISTS (
      SELECT 1 FROM public.auditor a
       WHERE a.uuid = auth.uid() AND a.id_tienda = p_id_tienda
  ) OR EXISTS (
      SELECT 1
        FROM public.app_dat_vendedor v
        JOIN public.app_dat_tpv tpv ON tpv.id = v.id_tpv
       WHERE v.uuid = auth.uid() AND tpv.id_tienda = p_id_tienda
  ) OR EXISTS (
      SELECT 1
        FROM public.app_dat_almacenero al
        JOIN public.app_dat_almacen am ON am.id = al.id_almacen
       WHERE al.uuid = auth.uid() AND am.id_tienda = p_id_tienda
  ) OR EXISTS (
      SELECT 1
        FROM public.app_dat_jefe_cocina jc
        JOIN public.app_dat_cocina c ON c.id = jc.id_cocina
       WHERE jc.uuid = auth.uid()
         AND c.id_tienda = p_id_tienda
         AND c.deleted_at IS NULL
  ) OR EXISTS (
      SELECT 1 FROM public.app_dat_superadmin sa
       WHERE sa.uuid = auth.uid() AND COALESCE(sa.activo, true) = true
  );
$function$;

GRANT EXECUTE ON FUNCTION public.fn_user_can_read_tienda(bigint)
    TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_user_is_gerente_or_superadmin(p_id_tienda bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
  SELECT EXISTS (
      SELECT 1 FROM public.app_dat_gerente g
       WHERE g.uuid = auth.uid() AND g.id_tienda = p_id_tienda
  ) OR EXISTS (
      SELECT 1 FROM public.app_dat_superadmin sa
       WHERE sa.uuid = auth.uid() AND COALESCE(sa.activo, true) = true
  );
$function$;

GRANT EXECUTE ON FUNCTION public.fn_user_is_gerente_or_superadmin(bigint)
    TO authenticated, service_role;

DROP POLICY IF EXISTS servicentro_producto_select
    ON public.app_dat_servicentro_producto;
DROP POLICY IF EXISTS servicentro_producto_insert
    ON public.app_dat_servicentro_producto;
DROP POLICY IF EXISTS servicentro_producto_update
    ON public.app_dat_servicentro_producto;
DROP POLICY IF EXISTS servicentro_producto_delete
    ON public.app_dat_servicentro_producto;

-- Lectura: quien tenga acceso a la tienda (incluye vendedor)
CREATE POLICY servicentro_producto_select
    ON public.app_dat_servicentro_producto
    FOR SELECT
    TO authenticated
    USING (public.fn_user_can_read_tienda(id_tienda));

-- Escritura: solo gerente de la tienda o superadmin
CREATE POLICY servicentro_producto_insert
    ON public.app_dat_servicentro_producto
    FOR INSERT
    TO authenticated
    WITH CHECK (public.fn_user_is_gerente_or_superadmin(id_tienda));

CREATE POLICY servicentro_producto_update
    ON public.app_dat_servicentro_producto
    FOR UPDATE
    TO authenticated
    USING (public.fn_user_is_gerente_or_superadmin(id_tienda))
    WITH CHECK (public.fn_user_is_gerente_or_superadmin(id_tienda));

CREATE POLICY servicentro_producto_delete
    ON public.app_dat_servicentro_producto
    FOR DELETE
    TO authenticated
    USING (public.fn_user_is_gerente_or_superadmin(id_tienda));


-- ----------------------------------------------------------------------------
-- 1.5 Trigger: modos de operación excluyentes
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_trg_config_tienda_modos_excluyentes()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF COALESCE(NEW.modo_servicentro, false)
       AND (COALESCE(NEW.modo_restaurante, false) OR COALESCE(NEW.cocina_activa, false))
    THEN
        RAISE EXCEPTION
            'MODO_EXCLUYENTE: No se puede activar modo_servicentro si modo_restaurante o cocina_activa están activos (o viceversa).'
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_config_tienda_modos_excluyentes
    ON public.app_dat_configuracion_tienda;

CREATE TRIGGER trg_config_tienda_modos_excluyentes
    BEFORE INSERT OR UPDATE OF modo_servicentro, modo_restaurante, cocina_activa
    ON public.app_dat_configuracion_tienda
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_trg_config_tienda_modos_excluyentes();


-- ----------------------------------------------------------------------------
-- 1.6 Trigger: producto debe ser combustible de la misma tienda
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_trg_servicentro_producto_valido()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id_tienda_prod bigint;
    v_es_combustible boolean;
    v_deleted_at     timestamp;
BEGIN
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

    IF v_id_tienda_prod IS DISTINCT FROM NEW.id_tienda THEN
        RAISE EXCEPTION
            'SERVICENTRO_PRODUCTO_INVALIDO: el producto % pertenece a la tienda %, no a %',
            NEW.id_producto, v_id_tienda_prod, NEW.id_tienda
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
    BEFORE INSERT OR UPDATE OF id_tienda, id_producto
    ON public.app_dat_servicentro_producto
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_trg_servicentro_producto_valido();
