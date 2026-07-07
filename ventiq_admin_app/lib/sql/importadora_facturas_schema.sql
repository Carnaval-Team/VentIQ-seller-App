-- ============================================================================
-- Esquema: Gestión de Pagos a Importadora
-- Ejecutar una sola vez en el SQL Editor de Supabase.
-- ============================================================================


-- ============================================================================
-- 1. NOMENCLADOR DE ESTADOS DE FACTURA
--    Tabla maestra de estados (Procesando, Pagado, En Recogida, Finalizado…)
--    No depende de ninguna tienda: es global/compartido.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.imp_nom_estado_factura (
    id            BIGSERIAL    PRIMARY KEY,
    denominacion  TEXT         NOT NULL,
    descripcion   TEXT,
    color         TEXT         DEFAULT '#2196F3',  -- hex, ej. '#FF9800'
    orden         INTEGER      NOT NULL DEFAULT 0,
    activo        BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
);

COMMENT ON TABLE  public.imp_nom_estado_factura               IS 'Nomenclador de estados para facturas de importadora.';
COMMENT ON COLUMN public.imp_nom_estado_factura.color         IS 'Color hex del estado para visualización en la app, ej. #FF9800.';
COMMENT ON COLUMN public.imp_nom_estado_factura.orden         IS 'Orden de presentación; el estado con menor orden es el inicial al crear una factura.';

-- Índice para ordenar por orden de presentación
CREATE INDEX IF NOT EXISTS idx_imp_nom_estado_factura_orden
    ON public.imp_nom_estado_factura (orden);

-- Estados estándar iniciales (idempotente: no falla si ya existen)
INSERT INTO public.imp_nom_estado_factura (denominacion, descripcion, color, orden, activo)
VALUES
    ('Procesando por Proveedor', 'La factura está siendo procesada por el proveedor', '#FF9800', 1, TRUE),
    ('Pagado a Importadora',     'El pago ha sido realizado a la importadora',         '#2196F3', 2, TRUE),
    ('En Recogida',              'La mercancía está en proceso de recogida',            '#9C27B0', 3, TRUE),
    ('Finalizado',               'El proceso ha finalizado exitosamente',               '#4CAF50', 4, TRUE)
ON CONFLICT DO NOTHING;


-- ============================================================================
-- 2. SALDO DISPONIBLE POR TIENDA
--    Un registro por tienda con el saldo actual (se actualiza con UPSERT).
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.imp_dat_saldo (
    id                BIGSERIAL    PRIMARY KEY,
    idtienda          INTEGER      NOT NULL UNIQUE,   -- FK lógica a app_dat_tienda
    saldo_disponible  NUMERIC(14,2) NOT NULL DEFAULT 0.00,
    updated_at        TIMESTAMPTZ  NOT NULL DEFAULT now()
);

COMMENT ON TABLE  public.imp_dat_saldo                  IS 'Saldo disponible actual para pagos a importadora, uno por tienda.';
COMMENT ON COLUMN public.imp_dat_saldo.idtienda         IS 'ID de la tienda (app_dat_tienda.id).';
COMMENT ON COLUMN public.imp_dat_saldo.saldo_disponible IS 'Saldo actual en USD. Se actualiza en cada recarga o creación de factura.';

CREATE INDEX IF NOT EXISTS idx_imp_dat_saldo_tienda
    ON public.imp_dat_saldo (idtienda);


-- ============================================================================
-- 3. RECARGAS DE SALDO
--    Histórico de cada operación de recarga realizada.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.imp_dat_recarga_saldo (
    id           BIGSERIAL    PRIMARY KEY,
    idtienda     INTEGER      NOT NULL,
    monto        NUMERIC(14,2) NOT NULL CHECK (monto > 0),
    fecha_pago   DATE         NOT NULL,
    observacion  TEXT,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now()
);

COMMENT ON TABLE  public.imp_dat_recarga_saldo             IS 'Historial de recargas de saldo para pagos a importadora.';
COMMENT ON COLUMN public.imp_dat_recarga_saldo.fecha_pago  IS 'Fecha en que se realizó el pago bancario/transferencia.';

CREATE INDEX IF NOT EXISTS idx_imp_dat_recarga_saldo_tienda
    ON public.imp_dat_recarga_saldo (idtienda, created_at DESC);


-- ============================================================================
-- 4. HISTORIAL DE MOVIMIENTOS DE SALDO
--    Auditoría completa de cada cambio en el saldo (recargas y descuentos).
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.imp_hist_saldo (
    id               BIGSERIAL    PRIMARY KEY,
    idtienda         INTEGER      NOT NULL,
    monto_anterior   NUMERIC(14,2) NOT NULL,
    monto_nuevo      NUMERIC(14,2) NOT NULL,
    diferencia       NUMERIC(14,2) NOT NULL,          -- positivo = recarga, negativo = descuento
    tipo_operacion   TEXT         NOT NULL,            -- 'recarga' | 'descuento_factura'
    referencia       TEXT,                             -- descripción legible del movimiento
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now()
);

COMMENT ON TABLE  public.imp_hist_saldo                  IS 'Auditoría de todos los cambios en el saldo por tienda.';
COMMENT ON COLUMN public.imp_hist_saldo.tipo_operacion   IS 'Tipo: recarga | descuento_factura.';
COMMENT ON COLUMN public.imp_hist_saldo.diferencia       IS 'Positivo = ingreso, negativo = egreso.';

CREATE INDEX IF NOT EXISTS idx_imp_hist_saldo_tienda
    ON public.imp_hist_saldo (idtienda, created_at DESC);


-- ============================================================================
-- 5. FACTURAS DE IMPORTADORA
--    Registro de cada factura con su estado actual.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.imp_dat_factura (
    id                   BIGSERIAL    PRIMARY KEY,
    idtienda             INTEGER      NOT NULL,
    numero_factura       TEXT         NOT NULL,
    valor                NUMERIC(14,2) NOT NULL CHECK (valor > 0),
    fecha_procesamiento  DATE         NOT NULL,
    foto_url             TEXT,                         -- URL en Supabase Storage u otro proveedor
    id_estado            BIGINT       NOT NULL REFERENCES public.imp_nom_estado_factura(id),
    created_at           TIMESTAMPTZ  NOT NULL DEFAULT now()
);

COMMENT ON TABLE  public.imp_dat_factura                      IS 'Facturas emitidas a la importadora por tienda.';
COMMENT ON COLUMN public.imp_dat_factura.numero_factura       IS 'Número/código identificador de la factura.';
COMMENT ON COLUMN public.imp_dat_factura.valor                IS 'Valor de la factura en USD. Se descuenta del saldo al crear.';
COMMENT ON COLUMN public.imp_dat_factura.fecha_procesamiento  IS 'Fecha en que se procesa la factura.';
COMMENT ON COLUMN public.imp_dat_factura.foto_url             IS 'URL de la fotografía/escaneo de la factura (opcional).';
COMMENT ON COLUMN public.imp_dat_factura.id_estado            IS 'Estado actual de la factura (FK a imp_nom_estado_factura).';

CREATE INDEX IF NOT EXISTS idx_imp_dat_factura_tienda
    ON public.imp_dat_factura (idtienda, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_imp_dat_factura_estado
    ON public.imp_dat_factura (id_estado);


-- ============================================================================
-- 6. HISTORIAL DE ESTADOS DE FACTURA
--    Auditoría de cada cambio de estado en una factura.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.imp_hist_estado_factura (
    id                  BIGSERIAL    PRIMARY KEY,
    id_factura          BIGINT       NOT NULL REFERENCES public.imp_dat_factura(id) ON DELETE CASCADE,
    id_estado_anterior  BIGINT       NOT NULL REFERENCES public.imp_nom_estado_factura(id),
    id_estado_nuevo     BIGINT       NOT NULL REFERENCES public.imp_nom_estado_factura(id),
    observacion         TEXT,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now()
);

COMMENT ON TABLE  public.imp_hist_estado_factura                 IS 'Historial de cambios de estado de cada factura de importadora.';
COMMENT ON COLUMN public.imp_hist_estado_factura.id_factura      IS 'Factura a la que pertenece el cambio de estado.';
COMMENT ON COLUMN public.imp_hist_estado_factura.observacion     IS 'Nota opcional al cambiar el estado.';

CREATE INDEX IF NOT EXISTS idx_imp_hist_estado_factura_factura
    ON public.imp_hist_estado_factura (id_factura, created_at DESC);


-- ============================================================================
-- 7. ROW LEVEL SECURITY (RLS)
--    Habilitar RLS en todas las tablas. Las políticas permiten acceso
--    autenticado completo; ajusta según tus necesidades de permisos.
-- ============================================================================

ALTER TABLE public.imp_nom_estado_factura  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.imp_dat_saldo           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.imp_dat_recarga_saldo   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.imp_hist_saldo          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.imp_dat_factura         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.imp_hist_estado_factura ENABLE ROW LEVEL SECURITY;

-- Política: usuarios autenticados tienen acceso total
CREATE POLICY "Acceso autenticado - imp_nom_estado_factura"
    ON public.imp_nom_estado_factura FOR ALL
    TO authenticated USING (TRUE) WITH CHECK (TRUE);

CREATE POLICY "Acceso autenticado - imp_dat_saldo"
    ON public.imp_dat_saldo FOR ALL
    TO authenticated USING (TRUE) WITH CHECK (TRUE);

CREATE POLICY "Acceso autenticado - imp_dat_recarga_saldo"
    ON public.imp_dat_recarga_saldo FOR ALL
    TO authenticated USING (TRUE) WITH CHECK (TRUE);

CREATE POLICY "Acceso autenticado - imp_hist_saldo"
    ON public.imp_hist_saldo FOR ALL
    TO authenticated USING (TRUE) WITH CHECK (TRUE);

CREATE POLICY "Acceso autenticado - imp_dat_factura"
    ON public.imp_dat_factura FOR ALL
    TO authenticated USING (TRUE) WITH CHECK (TRUE);

CREATE POLICY "Acceso autenticado - imp_hist_estado_factura"
    ON public.imp_hist_estado_factura FOR ALL
    TO authenticated USING (TRUE) WITH CHECK (TRUE);
