-- ============================================================================
-- Fase 1 (aditivo): solo tablas nuevas de costos + RLS
-- ============================================================================
-- Extraído de costos_adicionales_producto.sql §§1–2.
-- NO incluye: DROP EXPRESSION de costo_real, trigger en
-- app_dat_recepcion_productos, ni CREATE OR REPLACE de
-- fn_actualizar_precio_promedio_recepcion_v2 (eso toca el
-- nombre que usa el cliente publicado → Fase 3 / _m01).
-- El precio nuevo va en promocion_m01/06 (*_v2_m01).
-- ============================================================================

BEGIN;

-- ────────────────────────────────────────────────────────────────────────────
-- 1. Relación producto ↔ concepto de costo
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.app_dat_producto_costo (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_producto bigint NOT NULL REFERENCES public.app_dat_producto(id) ON DELETE CASCADE,
  id_tipo_costo bigint NOT NULL REFERENCES public.app_cont_tipo_costo(id),
  monto_usd numeric NOT NULL DEFAULT 0,
  monto_promedio_usd numeric NOT NULL DEFAULT 0,
  activo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id_producto, id_tipo_costo)
);

ALTER TABLE public.app_dat_producto_costo ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS app_dat_producto_costo_select ON public.app_dat_producto_costo;
CREATE POLICY app_dat_producto_costo_select ON public.app_dat_producto_costo
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.app_dat_producto p
      WHERE p.id = app_dat_producto_costo.id_producto
        AND public.fn_user_can_access_tienda(p.id_tienda)
    )
  );

DROP POLICY IF EXISTS app_dat_producto_costo_insert ON public.app_dat_producto_costo;
CREATE POLICY app_dat_producto_costo_insert ON public.app_dat_producto_costo
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.app_dat_producto p
      WHERE p.id = app_dat_producto_costo.id_producto
        AND public.fn_user_is_gerente_or_superadmin(p.id_tienda)
    )
  );

DROP POLICY IF EXISTS app_dat_producto_costo_update ON public.app_dat_producto_costo;
CREATE POLICY app_dat_producto_costo_update ON public.app_dat_producto_costo
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.app_dat_producto p
      WHERE p.id = app_dat_producto_costo.id_producto
        AND public.fn_user_is_gerente_or_superadmin(p.id_tienda)
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.app_dat_producto p
      WHERE p.id = app_dat_producto_costo.id_producto
        AND public.fn_user_is_gerente_or_superadmin(p.id_tienda)
    )
  );

DROP POLICY IF EXISTS app_dat_producto_costo_delete ON public.app_dat_producto_costo;
CREATE POLICY app_dat_producto_costo_delete ON public.app_dat_producto_costo
  FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.app_dat_producto p
      WHERE p.id = app_dat_producto_costo.id_producto
        AND public.fn_user_is_gerente_or_superadmin(p.id_tienda)
    )
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.app_dat_producto_costo TO authenticated;
GRANT ALL ON public.app_dat_producto_costo TO service_role;

-- ────────────────────────────────────────────────────────────────────────────
-- 2. Auditoría de costo aplicado por línea de recepción
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.app_dat_recepcion_producto_costo (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_recepcion_producto bigint NOT NULL
    REFERENCES public.app_dat_recepcion_productos(id) ON DELETE CASCADE,
  id_tipo_costo bigint NOT NULL REFERENCES public.app_cont_tipo_costo(id),
  monto_usd numeric NOT NULL,
  monto_promedio_anterior numeric NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_recepcion_producto_costo_rp
  ON public.app_dat_recepcion_producto_costo (id_recepcion_producto);

ALTER TABLE public.app_dat_recepcion_producto_costo ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS app_dat_recepcion_producto_costo_select
  ON public.app_dat_recepcion_producto_costo;
CREATE POLICY app_dat_recepcion_producto_costo_select
  ON public.app_dat_recepcion_producto_costo
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.app_dat_recepcion_productos rp
      JOIN public.app_dat_operaciones o ON o.id = rp.id_operacion
      WHERE rp.id = app_dat_recepcion_producto_costo.id_recepcion_producto
        AND public.fn_user_can_access_tienda(o.id_tienda)
    )
  );

DROP POLICY IF EXISTS app_dat_recepcion_producto_costo_insert
  ON public.app_dat_recepcion_producto_costo;
CREATE POLICY app_dat_recepcion_producto_costo_insert
  ON public.app_dat_recepcion_producto_costo
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.app_dat_recepcion_productos rp
      JOIN public.app_dat_operaciones o ON o.id = rp.id_operacion
      WHERE rp.id = app_dat_recepcion_producto_costo.id_recepcion_producto
        AND public.fn_user_can_access_tienda(o.id_tienda)
    )
  );

DROP POLICY IF EXISTS app_dat_recepcion_producto_costo_update
  ON public.app_dat_recepcion_producto_costo;
CREATE POLICY app_dat_recepcion_producto_costo_update
  ON public.app_dat_recepcion_producto_costo
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.app_dat_recepcion_productos rp
      JOIN public.app_dat_operaciones o ON o.id = rp.id_operacion
      WHERE rp.id = app_dat_recepcion_producto_costo.id_recepcion_producto
        AND public.fn_user_is_gerente_or_superadmin(o.id_tienda)
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.app_dat_recepcion_productos rp
      JOIN public.app_dat_operaciones o ON o.id = rp.id_operacion
      WHERE rp.id = app_dat_recepcion_producto_costo.id_recepcion_producto
        AND public.fn_user_is_gerente_or_superadmin(o.id_tienda)
    )
  );

DROP POLICY IF EXISTS app_dat_recepcion_producto_costo_delete
  ON public.app_dat_recepcion_producto_costo;
CREATE POLICY app_dat_recepcion_producto_costo_delete
  ON public.app_dat_recepcion_producto_costo
  FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.app_dat_recepcion_productos rp
      JOIN public.app_dat_operaciones o ON o.id = rp.id_operacion
      WHERE rp.id = app_dat_recepcion_producto_costo.id_recepcion_producto
        AND public.fn_user_is_gerente_or_superadmin(o.id_tienda)
    )
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.app_dat_recepcion_producto_costo TO authenticated;
GRANT ALL ON public.app_dat_recepcion_producto_costo TO service_role;

COMMIT;
