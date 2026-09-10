-- ============================================================================
-- Esquema: Pago a Proveedores
-- Independiente de Pagos a Importadora (imp_*).
-- Saldo por tienda + proveedor (app_dat_proveedor). Sin saldo negativo.
-- Ejecutar en el SQL Editor de Supabase.
-- ============================================================================


-- ============================================================================
-- 1. NOMENCLADOR DE MONEDAS (gestión por módulo)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.prv_nom_moneda (
    id            BIGSERIAL    PRIMARY KEY,
    codigo        TEXT         NOT NULL UNIQUE,  -- USD, CUP, EUR…
    denominacion  TEXT         NOT NULL,
    simbolo       TEXT         NOT NULL DEFAULT '$',
    activo        BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.prv_nom_moneda IS 'Monedas gestionables para Pago a Proveedores.';

INSERT INTO public.prv_nom_moneda (codigo, denominacion, simbolo, activo)
VALUES
    ('USD', 'Dólar estadounidense', '$', TRUE),
    ('CUP', 'Peso cubano', '$', TRUE),
    ('EUR', 'Euro', '€', TRUE)
ON CONFLICT (codigo) DO NOTHING;


-- ============================================================================
-- 2. MONEDA ASIGNADA POR PROVEEDOR (por tienda)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.prv_dat_proveedor_config (
    id            BIGSERIAL    PRIMARY KEY,
    idtienda      INTEGER      NOT NULL,
    id_proveedor  BIGINT       NOT NULL REFERENCES public.app_dat_proveedor(id),
    id_moneda     BIGINT       NOT NULL REFERENCES public.prv_nom_moneda(id),
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    UNIQUE (idtienda, id_proveedor)
);

COMMENT ON TABLE public.prv_dat_proveedor_config IS
  'Configuración de moneda por proveedor en Pago a Proveedores.';

CREATE INDEX IF NOT EXISTS idx_prv_dat_proveedor_config_tienda
    ON public.prv_dat_proveedor_config (idtienda);


-- ============================================================================
-- 3. ESTADOS DE FACTURA
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.prv_nom_estado_factura (
    id            BIGSERIAL    PRIMARY KEY,
    denominacion  TEXT         NOT NULL,
    descripcion   TEXT,
    color         TEXT         DEFAULT '#2196F3',
    orden         INTEGER      NOT NULL DEFAULT 0,
    activo        BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_prv_nom_estado_factura_orden
    ON public.prv_nom_estado_factura (orden);

INSERT INTO public.prv_nom_estado_factura (denominacion, descripcion, color, orden, activo)
VALUES
    ('Procesando por Proveedor', 'La factura está siendo procesada por el proveedor', '#FF9800', 1, TRUE),
    ('Pagado a Proveedor',       'El pago ha sido realizado al proveedor',           '#2196F3', 2, TRUE),
    ('En Recogida',              'La mercancía está en proceso de recogida',         '#9C27B0', 3, TRUE),
    ('Finalizado',               'El proceso ha finalizado exitosamente',            '#4CAF50', 4, TRUE)
ON CONFLICT DO NOTHING;


-- ============================================================================
-- 4. SALDO POR TIENDA + PROVEEDOR
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.prv_dat_saldo (
    id                BIGSERIAL     PRIMARY KEY,
    idtienda          INTEGER       NOT NULL,
    id_proveedor      BIGINT        NOT NULL REFERENCES public.app_dat_proveedor(id),
    saldo_disponible  NUMERIC(14,2) NOT NULL DEFAULT 0.00
                          CHECK (saldo_disponible >= 0),
    updated_at        TIMESTAMPTZ   NOT NULL DEFAULT now(),
    UNIQUE (idtienda, id_proveedor)
);

CREATE INDEX IF NOT EXISTS idx_prv_dat_saldo_tienda_prov
    ON public.prv_dat_saldo (idtienda, id_proveedor);


-- ============================================================================
-- 5. RECARGAS
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.prv_dat_recarga_saldo (
    id            BIGSERIAL     PRIMARY KEY,
    idtienda      INTEGER       NOT NULL,
    id_proveedor  BIGINT        NOT NULL REFERENCES public.app_dat_proveedor(id),
    monto         NUMERIC(14,2) NOT NULL CHECK (monto > 0),
    fecha_pago    DATE          NOT NULL,
    observacion   TEXT,
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_prv_dat_recarga_saldo_tienda_prov
    ON public.prv_dat_recarga_saldo (idtienda, id_proveedor, created_at DESC);


-- ============================================================================
-- 6. HISTORIAL DE SALDO
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.prv_hist_saldo (
    id               BIGSERIAL     PRIMARY KEY,
    idtienda         INTEGER       NOT NULL,
    id_proveedor     BIGINT        NOT NULL REFERENCES public.app_dat_proveedor(id),
    monto_anterior   NUMERIC(14,2) NOT NULL,
    monto_nuevo      NUMERIC(14,2) NOT NULL,
    diferencia       NUMERIC(14,2) NOT NULL,
    tipo_operacion   TEXT          NOT NULL,  -- recarga | descuento_factura | ajuste_factura
    referencia       TEXT,
    id_recarga       BIGINT        REFERENCES public.prv_dat_recarga_saldo(id) ON DELETE SET NULL,
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_prv_hist_saldo_tienda_prov
    ON public.prv_hist_saldo (idtienda, id_proveedor, created_at DESC);


-- ============================================================================
-- 7. FACTURAS
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.prv_dat_factura (
    id                   BIGSERIAL     PRIMARY KEY,
    idtienda             INTEGER       NOT NULL,
    id_proveedor         BIGINT        NOT NULL REFERENCES public.app_dat_proveedor(id),
    numero_factura       TEXT          NOT NULL,
    valor                NUMERIC(14,2) NOT NULL CHECK (valor > 0),
    fecha_procesamiento  DATE          NOT NULL,
    foto_url             TEXT,
    id_estado            BIGINT        NOT NULL REFERENCES public.prv_nom_estado_factura(id),
    created_at           TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_prv_dat_factura_tienda_prov
    ON public.prv_dat_factura (idtienda, id_proveedor, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_prv_dat_factura_estado
    ON public.prv_dat_factura (id_estado);


-- ============================================================================
-- 8. HISTORIAL DE ESTADOS
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.prv_hist_estado_factura (
    id                  BIGSERIAL    PRIMARY KEY,
    id_factura          BIGINT       NOT NULL REFERENCES public.prv_dat_factura(id) ON DELETE CASCADE,
    id_estado_anterior  BIGINT       NOT NULL REFERENCES public.prv_nom_estado_factura(id),
    id_estado_nuevo     BIGINT       NOT NULL REFERENCES public.prv_nom_estado_factura(id),
    observacion         TEXT,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_prv_hist_estado_factura_factura
    ON public.prv_hist_estado_factura (id_factura, created_at DESC);


-- ============================================================================
-- 9. FOTOS DE FACTURA
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.prv_dat_factura_foto (
    id              BIGSERIAL    PRIMARY KEY,
    id_factura      BIGINT       NOT NULL REFERENCES public.prv_dat_factura(id) ON DELETE CASCADE,
    foto_url        TEXT         NOT NULL,
    numero_pagina   INTEGER      NOT NULL DEFAULT 1,
    nombre_archivo  TEXT,
    mime_type       TEXT         DEFAULT 'image/jpeg',
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_prv_dat_factura_foto_factura
    ON public.prv_dat_factura_foto (id_factura, numero_pagina ASC);


-- ============================================================================
-- 10. RLS
-- ============================================================================

ALTER TABLE public.prv_nom_moneda              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prv_dat_proveedor_config    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prv_nom_estado_factura      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prv_dat_saldo               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prv_dat_recarga_saldo       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prv_hist_saldo              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prv_dat_factura             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prv_hist_estado_factura     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prv_dat_factura_foto        ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "Acceso autenticado - prv_nom_moneda"
    ON public.prv_nom_moneda FOR ALL TO authenticated USING (TRUE) WITH CHECK (TRUE);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "Acceso autenticado - prv_dat_proveedor_config"
    ON public.prv_dat_proveedor_config FOR ALL TO authenticated USING (TRUE) WITH CHECK (TRUE);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "Acceso autenticado - prv_nom_estado_factura"
    ON public.prv_nom_estado_factura FOR ALL TO authenticated USING (TRUE) WITH CHECK (TRUE);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "Acceso autenticado - prv_dat_saldo"
    ON public.prv_dat_saldo FOR ALL TO authenticated USING (TRUE) WITH CHECK (TRUE);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "Acceso autenticado - prv_dat_recarga_saldo"
    ON public.prv_dat_recarga_saldo FOR ALL TO authenticated USING (TRUE) WITH CHECK (TRUE);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "Acceso autenticado - prv_hist_saldo"
    ON public.prv_hist_saldo FOR ALL TO authenticated USING (TRUE) WITH CHECK (TRUE);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "Acceso autenticado - prv_dat_factura"
    ON public.prv_dat_factura FOR ALL TO authenticated USING (TRUE) WITH CHECK (TRUE);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "Acceso autenticado - prv_hist_estado_factura"
    ON public.prv_hist_estado_factura FOR ALL TO authenticated USING (TRUE) WITH CHECK (TRUE);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "Acceso autenticado - prv_dat_factura_foto"
    ON public.prv_dat_factura_foto FOR ALL TO authenticated USING (TRUE) WITH CHECK (TRUE);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
