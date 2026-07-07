-- ============================================================================
-- Tabla informativa: equivalencia de cantidades por presentación y producto
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.app_inf_presentacion_producto (
  id              BIGINT GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_producto     BIGINT NOT NULL,
  id_presentacion BIGINT NOT NULL,
  cantidad        NUMERIC NOT NULL CHECK (cantidad > 0),
  observaciones   TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT app_inf_presentacion_producto_pkey PRIMARY KEY (id),
  CONSTRAINT app_inf_presentacion_producto_id_producto_fkey
    FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id) ON DELETE CASCADE,
  CONSTRAINT app_inf_presentacion_producto_id_presentacion_fkey
    FOREIGN KEY (id_presentacion) REFERENCES public.app_nom_presentacion(id),
  CONSTRAINT app_inf_presentacion_producto_unique
    UNIQUE (id_producto, id_presentacion)
);

CREATE INDEX IF NOT EXISTS idx_app_inf_presentacion_producto_producto
  ON public.app_inf_presentacion_producto (id_producto);

COMMENT ON TABLE public.app_inf_presentacion_producto IS
  'Equivalencia informativa: cuántas unidades base representa cada presentación para un producto.';
COMMENT ON COLUMN public.app_inf_presentacion_producto.cantidad IS
  'Cantidad de unidades de la presentación base equivalente en esta presentación.';

-- Trigger updated_at
CREATE OR REPLACE FUNCTION public.trg_app_inf_presentacion_producto_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_app_inf_presentacion_producto_updated_at
  ON public.app_inf_presentacion_producto;

CREATE TRIGGER trg_app_inf_presentacion_producto_updated_at
  BEFORE UPDATE ON public.app_inf_presentacion_producto
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_app_inf_presentacion_producto_updated_at();

-- RLS (mismo criterio que productos por tienda)
ALTER TABLE public.app_inf_presentacion_producto ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS app_inf_presentacion_producto_select ON public.app_inf_presentacion_producto;
DROP POLICY IF EXISTS app_inf_presentacion_producto_insert ON public.app_inf_presentacion_producto;
DROP POLICY IF EXISTS app_inf_presentacion_producto_update ON public.app_inf_presentacion_producto;
DROP POLICY IF EXISTS app_inf_presentacion_producto_delete ON public.app_inf_presentacion_producto;

CREATE POLICY app_inf_presentacion_producto_select ON public.app_inf_presentacion_producto
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM app_dat_producto p
      WHERE p.id = app_inf_presentacion_producto.id_producto
    )
  );

CREATE POLICY app_inf_presentacion_producto_insert ON public.app_inf_presentacion_producto
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM app_dat_producto p
      WHERE p.id = app_inf_presentacion_producto.id_producto
    )
  );

CREATE POLICY app_inf_presentacion_producto_update ON public.app_inf_presentacion_producto
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM app_dat_producto p
      WHERE p.id = app_inf_presentacion_producto.id_producto
    )
  );

CREATE POLICY app_inf_presentacion_producto_delete ON public.app_inf_presentacion_producto
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM app_dat_producto p
      WHERE p.id = app_inf_presentacion_producto.id_producto
    )
  );
