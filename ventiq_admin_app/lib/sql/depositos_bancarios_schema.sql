-- ============================================================================
-- Esquema: Depósitos Bancarios
-- Independiente de Importadora (imp_*) y Pago a Proveedores (prv_*).
-- Incluye gestión de bancos y de monedas.
-- Saldo por tienda + banco. Sin saldo negativo.
-- Ejecutar en el SQL Editor de Supabase.
-- ============================================================================


-- ============================================================================
-- 1. NOMENCLADOR DE MONEDAS (gestión del módulo)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.dep_nom_moneda (
    id            BIGSERIAL    PRIMARY KEY,
    codigo        TEXT         NOT NULL UNIQUE,
    denominacion  TEXT         NOT NULL,
    simbolo       TEXT         NOT NULL DEFAULT '$',
    activo        BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.dep_nom_moneda IS 'Monedas gestionables para Depósitos Bancarios.';

INSERT INTO public.dep_nom_moneda (codigo, denominacion, simbolo, activo)
VALUES
    ('USD', 'Dólar estadounidense', '$', TRUE),
    ('CUP', 'Peso cubano', '$', TRUE),
    ('EUR', 'Euro', '€', TRUE)
ON CONFLICT (codigo) DO NOTHING;


-- ============================================================================
-- 2. BANCOS (catálogo nuevo por tienda)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.dep_dat_banco (
    id            BIGSERIAL    PRIMARY KEY,
    idtienda      INTEGER      NOT NULL,
    denominacion  TEXT         NOT NULL,
    id_moneda     BIGINT       NOT NULL REFERENCES public.dep_nom_moneda(id),
    activo        BOOLEAN      NOT NULL DEFAULT TRUE,
    observacion   TEXT,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.dep_dat_banco IS
  'Bancos/cuentas gestionados por tienda para Depósitos Bancarios.';

CREATE INDEX IF NOT EXISTS idx_dep_dat_banco_tienda
    ON public.dep_dat_banco (idtienda, activo);


-- ============================================================================
-- 3. ESTADOS DE DEPÓSITO
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.dep_nom_estado_deposito (
    id            BIGSERIAL    PRIMARY KEY,
    denominacion  TEXT         NOT NULL,
    descripcion   TEXT,
    color         TEXT         DEFAULT '#2196F3',
    orden         INTEGER      NOT NULL DEFAULT 0,
    activo        BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dep_nom_estado_deposito_orden
    ON public.dep_nom_estado_deposito (orden);

INSERT INTO public.dep_nom_estado_deposito (denominacion, descripcion, color, orden, activo)
VALUES
    ('Registrado',   'Depósito registrado pendiente de confirmación', '#FF9800', 1, TRUE),
    ('Confirmado',   'Depósito confirmado por el banco',              '#2196F3', 2, TRUE),
    ('En Proceso',   'Depósito en proceso de acreditación',           '#9C27B0', 3, TRUE),
    ('Finalizado',   'Depósito acreditado / finalizado',              '#4CAF50', 4, TRUE)
ON CONFLICT DO NOTHING;


-- ============================================================================
-- 4. SALDO POR TIENDA + BANCO
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.dep_dat_saldo (
    id                BIGSERIAL     PRIMARY KEY,
    idtienda          INTEGER       NOT NULL,
    id_banco          BIGINT        NOT NULL REFERENCES public.dep_dat_banco(id),
    saldo_disponible  NUMERIC(14,2) NOT NULL DEFAULT 0.00
                          CHECK (saldo_disponible >= 0),
    updated_at        TIMESTAMPTZ   NOT NULL DEFAULT now(),
    UNIQUE (idtienda, id_banco)
);

CREATE INDEX IF NOT EXISTS idx_dep_dat_saldo_tienda_banco
    ON public.dep_dat_saldo (idtienda, id_banco);


-- ============================================================================
-- 5. RECARGAS
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.dep_dat_recarga_saldo (
    id           BIGSERIAL     PRIMARY KEY,
    idtienda     INTEGER       NOT NULL,
    id_banco     BIGINT        NOT NULL REFERENCES public.dep_dat_banco(id),
    monto        NUMERIC(14,2) NOT NULL CHECK (monto > 0),
    fecha_pago   DATE          NOT NULL,
    observacion  TEXT,
    created_at   TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dep_dat_recarga_saldo_tienda_banco
    ON public.dep_dat_recarga_saldo (idtienda, id_banco, created_at DESC);


-- ============================================================================
-- 6. HISTORIAL DE SALDO
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.dep_hist_saldo (
    id               BIGSERIAL     PRIMARY KEY,
    idtienda         INTEGER       NOT NULL,
    id_banco         BIGINT        NOT NULL REFERENCES public.dep_dat_banco(id),
    monto_anterior   NUMERIC(14,2) NOT NULL,
    monto_nuevo      NUMERIC(14,2) NOT NULL,
    diferencia       NUMERIC(14,2) NOT NULL,
    tipo_operacion   TEXT          NOT NULL,  -- recarga | descuento_deposito | ajuste_deposito
    referencia       TEXT,
    id_recarga       BIGINT        REFERENCES public.dep_dat_recarga_saldo(id) ON DELETE SET NULL,
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dep_hist_saldo_tienda_banco
    ON public.dep_hist_saldo (idtienda, id_banco, created_at DESC);


-- ============================================================================
-- 7. DEPÓSITOS
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.dep_dat_deposito (
    id                   BIGSERIAL     PRIMARY KEY,
    idtienda             INTEGER       NOT NULL,
    id_banco             BIGINT        NOT NULL REFERENCES public.dep_dat_banco(id),
    numero_deposito      TEXT          NOT NULL,
    valor                NUMERIC(14,2) NOT NULL CHECK (valor > 0),
    fecha_procesamiento  DATE          NOT NULL,
    foto_url             TEXT,
    id_estado            BIGINT        NOT NULL REFERENCES public.dep_nom_estado_deposito(id),
    created_at           TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dep_dat_deposito_tienda_banco
    ON public.dep_dat_deposito (idtienda, id_banco, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_dep_dat_deposito_estado
    ON public.dep_dat_deposito (id_estado);


-- ============================================================================
-- 8. HISTORIAL DE ESTADOS
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.dep_hist_estado_deposito (
    id                  BIGSERIAL    PRIMARY KEY,
    id_deposito         BIGINT       NOT NULL REFERENCES public.dep_dat_deposito(id) ON DELETE CASCADE,
    id_estado_anterior  BIGINT       NOT NULL REFERENCES public.dep_nom_estado_deposito(id),
    id_estado_nuevo     BIGINT       NOT NULL REFERENCES public.dep_nom_estado_deposito(id),
    observacion         TEXT,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dep_hist_estado_deposito_dep
    ON public.dep_hist_estado_deposito (id_deposito, created_at DESC);


-- ============================================================================
-- 9. FOTOS DE DEPÓSITO
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.dep_dat_deposito_foto (
    id              BIGSERIAL    PRIMARY KEY,
    id_deposito     BIGINT       NOT NULL REFERENCES public.dep_dat_deposito(id) ON DELETE CASCADE,
    foto_url        TEXT         NOT NULL,
    numero_pagina   INTEGER      NOT NULL DEFAULT 1,
    nombre_archivo  TEXT,
    mime_type       TEXT         DEFAULT 'image/jpeg',
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dep_dat_deposito_foto_dep
    ON public.dep_dat_deposito_foto (id_deposito, numero_pagina ASC);


-- ============================================================================
-- 10. RLS
-- ============================================================================

ALTER TABLE public.dep_nom_moneda            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dep_dat_banco             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dep_nom_estado_deposito   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dep_dat_saldo             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dep_dat_recarga_saldo     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dep_hist_saldo            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dep_dat_deposito          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dep_hist_estado_deposito  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dep_dat_deposito_foto     ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "Acceso autenticado - dep_nom_moneda"
    ON public.dep_nom_moneda FOR ALL TO authenticated USING (TRUE) WITH CHECK (TRUE);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "Acceso autenticado - dep_dat_banco"
    ON public.dep_dat_banco FOR ALL TO authenticated USING (TRUE) WITH CHECK (TRUE);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "Acceso autenticado - dep_nom_estado_deposito"
    ON public.dep_nom_estado_deposito FOR ALL TO authenticated USING (TRUE) WITH CHECK (TRUE);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "Acceso autenticado - dep_dat_saldo"
    ON public.dep_dat_saldo FOR ALL TO authenticated USING (TRUE) WITH CHECK (TRUE);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "Acceso autenticado - dep_dat_recarga_saldo"
    ON public.dep_dat_recarga_saldo FOR ALL TO authenticated USING (TRUE) WITH CHECK (TRUE);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "Acceso autenticado - dep_hist_saldo"
    ON public.dep_hist_saldo FOR ALL TO authenticated USING (TRUE) WITH CHECK (TRUE);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "Acceso autenticado - dep_dat_deposito"
    ON public.dep_dat_deposito FOR ALL TO authenticated USING (TRUE) WITH CHECK (TRUE);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "Acceso autenticado - dep_hist_estado_deposito"
    ON public.dep_hist_estado_deposito FOR ALL TO authenticated USING (TRUE) WITH CHECK (TRUE);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "Acceso autenticado - dep_dat_deposito_foto"
    ON public.dep_dat_deposito_foto FOR ALL TO authenticated USING (TRUE) WITH CHECK (TRUE);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
