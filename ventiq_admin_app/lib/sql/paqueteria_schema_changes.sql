-- ============================================================================
-- Cambios de esquema para soportar órdenes de paquetería
-- Correr una sola vez en Supabase (SQL editor).
-- ============================================================================

-- 1) Columna `paqueteria` en carnavalapp."Orders"
--    Guarda el JSONB con remitente, destinatario y datos del paquete.
ALTER TABLE carnavalapp."Orders"
    ADD COLUMN IF NOT EXISTS paqueteria JSONB;

COMMENT ON COLUMN carnavalapp."Orders".paqueteria IS
    'JSON con {remitente, destinatario, paquete} para órdenes de paquetería.';


-- 2) Nueva tabla public.paqueteria_ordenes
--    Guarda el número de paquete, descripción y foto opcional, ligada a la
--    operación de Inventtia (`app_dat_operaciones`) que el trigger crea al
--    insertar el OrderDetail en Carnaval.
CREATE TABLE IF NOT EXISTS public.paqueteria_ordenes (
    id                BIGSERIAL PRIMARY KEY,
    id_operacion      BIGINT      NOT NULL REFERENCES public.app_dat_operaciones(id) ON DELETE CASCADE,
    id_orden_carnaval BIGINT               REFERENCES carnavalapp."Orders"(id)       ON DELETE SET NULL,
    numero_paquete    TEXT        NOT NULL,
    descripcion       TEXT,
    foto_url          TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.paqueteria_ordenes IS
    'Información específica de envíos de paquetería asociada a una operación de venta.';

CREATE INDEX IF NOT EXISTS idx_paqueteria_ordenes_operacion
    ON public.paqueteria_ordenes (id_operacion);

CREATE INDEX IF NOT EXISTS idx_paqueteria_ordenes_orden_carnaval
    ON public.paqueteria_ordenes (id_orden_carnaval);
