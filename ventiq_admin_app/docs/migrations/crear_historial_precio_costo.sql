-- =============================================================================
-- Historial de precios de costo (app_dat_precio_costo)
--
-- Problema: app_dat_producto_presentacion.precio_promedio (costo USD) se
-- sobrescribe en cada recepción / devolución / edición manual / consignación,
-- por lo que los reportes de ventas valoran las ventas antiguas con el costo
-- ACTUAL y falsean la ganancia real.
--
-- Solución: tabla de historial append-only alimentada por un trigger sobre
-- app_dat_producto_presentacion. Captura TODOS los caminos de escritura
-- (fn_actualizar_precio_promedio, bulk_update_precios_costo, devoluciones,
-- consignación, ediciones manuales) sin modificar cada RPC.
--
-- Patrón de consulta (igual que tasa_cambio_extraoficial en los reportes):
--   costo vigente en una fecha = último registro con created_at::DATE <= fecha
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Tabla de historial
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_dat_precio_costo (
    id                    BIGINT GENERATED ALWAYS AS IDENTITY NOT NULL,
    id_producto           BIGINT,
    id_presentacion       BIGINT NOT NULL,          -- FK a app_dat_producto_presentacion.id
    precio_costo_usd      NUMERIC NOT NULL,          -- nuevo costo (precio_promedio) en USD
    precio_costo_anterior NUMERIC,                   -- costo anterior (NULL en inserts/backfill)
    origen                TEXT NOT NULL DEFAULT 'trigger',  -- insert | update | backfill
    created_at            TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT app_dat_precio_costo_pkey PRIMARY KEY (id),
    CONSTRAINT app_dat_precio_costo_id_producto_fkey
        FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
    CONSTRAINT app_dat_precio_costo_id_presentacion_fkey
        FOREIGN KEY (id_presentacion) REFERENCES public.app_dat_producto_presentacion(id)
);

-- Índice para la búsqueda "costo vigente en fecha X"
CREATE INDEX IF NOT EXISTS idx_precio_costo_presentacion_fecha
    ON public.app_dat_precio_costo (id_presentacion, created_at DESC);

-- RLS (misma política permisiva que app_dat_precio_venta)
ALTER TABLE public.app_dat_precio_costo ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "contact policy" ON public.app_dat_precio_costo;
CREATE POLICY "contact policy" ON public.app_dat_precio_costo
    FOR ALL USING (true) WITH CHECK (true);

GRANT SELECT, INSERT ON public.app_dat_precio_costo TO authenticated;
GRANT ALL ON public.app_dat_precio_costo TO service_role;

-- -----------------------------------------------------------------------------
-- 2. Trigger: registra cada cambio de precio_promedio
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_trg_registrar_precio_costo()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.precio_promedio IS NOT NULL AND NEW.precio_promedio > 0 THEN
            INSERT INTO public.app_dat_precio_costo
                (id_producto, id_presentacion, precio_costo_usd, precio_costo_anterior, origen)
            VALUES
                (NEW.id_producto, NEW.id, NEW.precio_promedio, NULL, 'insert');
        END IF;
    ELSIF NEW.precio_promedio IS DISTINCT FROM OLD.precio_promedio
          AND NEW.precio_promedio IS NOT NULL
          AND NEW.precio_promedio > 0 THEN
        INSERT INTO public.app_dat_precio_costo
            (id_producto, id_presentacion, precio_costo_usd, precio_costo_anterior, origen)
        VALUES
            (NEW.id_producto, NEW.id, NEW.precio_promedio, OLD.precio_promedio, 'update');
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_registrar_precio_costo ON public.app_dat_producto_presentacion;
CREATE TRIGGER trg_registrar_precio_costo
    AFTER INSERT OR UPDATE OF precio_promedio
    ON public.app_dat_producto_presentacion
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_trg_registrar_precio_costo();

-- -----------------------------------------------------------------------------
-- 3. Backfill: sembrar el historial con los costos actuales.
--    Se usa la fecha de creación de la presentación como fecha_desde efectiva,
--    de modo que las ventas anteriores al primer cambio real de costo sigan
--    valorándose con el costo actual (mismo comportamiento que hoy).
-- -----------------------------------------------------------------------------
INSERT INTO public.app_dat_precio_costo
    (id_producto, id_presentacion, precio_costo_usd, precio_costo_anterior, origen, created_at)
SELECT
    pp.id_producto,
    pp.id,
    pp.precio_promedio,
    NULL,
    'backfill',
    pp.created_at
FROM public.app_dat_producto_presentacion pp
WHERE pp.precio_promedio IS NOT NULL
  AND pp.precio_promedio > 0
  AND NOT EXISTS (
        SELECT 1 FROM public.app_dat_precio_costo pc
        WHERE pc.id_presentacion = pp.id
      );
