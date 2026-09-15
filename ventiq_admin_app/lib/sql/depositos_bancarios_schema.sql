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
-- 3. TIPOS DE EXTRACCIÓN
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.dep_nom_tipo_extraccion (
    id            BIGSERIAL    PRIMARY KEY,
    denominacion  TEXT         NOT NULL UNIQUE,
    descripcion   TEXT,
    color         TEXT         DEFAULT '#607D8B',
    orden         INTEGER      NOT NULL DEFAULT 0,
    activo        BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dep_nom_tipo_extraccion_orden
    ON public.dep_nom_tipo_extraccion (orden);

INSERT INTO public.dep_nom_tipo_extraccion (denominacion, descripcion, color, orden, activo)
VALUES
    ('Depósito bancario', 'Extracción destinada a un depósito en una cuenta bancaria', '#2196F3', 1, TRUE),
    ('Pago a proveedor',  'Extracción para pagar a un proveedor',                    '#FF9800', 2, TRUE),
    ('Gasto operativo',   'Extracción para gastos de funcionamiento',                '#9C27B0', 3, TRUE),
    ('Otro',              'Otro tipo de extracción de caja',                         '#607D8B', 4, TRUE)
ON CONFLICT DO NOTHING;


-- ============================================================================
-- 4. ESTADOS DE DEPÓSITO
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

ALTER TABLE public.dep_dat_banco
    ADD COLUMN IF NOT EXISTS es_predeterminada_fondo_caja BOOLEAN NOT NULL DEFAULT FALSE;

CREATE UNIQUE INDEX IF NOT EXISTS uq_dep_dat_banco_predeterminada_tienda
    ON public.dep_dat_banco (idtienda)
    WHERE es_predeterminada_fondo_caja = TRUE;

ALTER TABLE public.dep_dat_recarga_saldo
    ADD COLUMN IF NOT EXISTS id_egreso_origen BIGINT;

CREATE UNIQUE INDEX IF NOT EXISTS uq_dep_recarga_egreso_origen
    ON public.dep_dat_recarga_saldo (id_egreso_origen)
    WHERE id_egreso_origen IS NOT NULL;


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
-- 8. EXTRACCIONES DE FONDO DE CAJA
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
    id_tipo_extraccion   BIGINT        REFERENCES public.dep_nom_tipo_extraccion(id),
    created_at           TIMESTAMPTZ   NOT NULL DEFAULT now()
);

ALTER TABLE public.dep_dat_deposito
    ADD COLUMN IF NOT EXISTS id_tipo_extraccion BIGINT;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'dep_dat_deposito_id_tipo_extraccion_fkey'
          AND conrelid = 'public.dep_dat_deposito'::regclass
    ) THEN
        ALTER TABLE public.dep_dat_deposito
            ADD CONSTRAINT dep_dat_deposito_id_tipo_extraccion_fkey
            FOREIGN KEY (id_tipo_extraccion)
            REFERENCES public.dep_nom_tipo_extraccion(id);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_dep_dat_deposito_tipo_extraccion
    ON public.dep_dat_deposito (id_tipo_extraccion);

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
-- 10. FUNCIONES ATÓMICAS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.dep_establecer_banco_predeterminado(
    p_idtienda INTEGER,
    p_id_banco BIGINT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.dep_dat_banco
        WHERE id = p_id_banco AND idtienda = p_idtienda AND activo = TRUE
    ) THEN
        RAISE EXCEPTION 'La cuenta no existe, está inactiva o no pertenece a la tienda';
    END IF;

    UPDATE public.dep_dat_banco
    SET es_predeterminada_fondo_caja = (id = p_id_banco), updated_at = now()
    WHERE idtienda = p_idtienda
      AND (es_predeterminada_fondo_caja = TRUE OR id = p_id_banco);
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_registrar_egreso_fondo_caja(
    p_client_uuid UUID,
    p_idtienda INTEGER,
    p_id_turno BIGINT,
    p_monto_entrega NUMERIC,
    p_nombre_recibe CHARACTER VARYING,
    p_nombre_autoriza CHARACTER VARYING,
    p_motivo_entrega TEXT,
    p_id_medio_pago SMALLINT DEFAULT NULL,
    p_uuid_usuario UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
    v_id_egreso BIGINT;
    v_id_banco BIGINT;
    v_id_recarga BIGINT;
    v_saldo_anterior NUMERIC(14,2);
    v_saldo_nuevo NUMERIC(14,2);
BEGIN
    IF p_monto_entrega IS NULL OR p_monto_entrega <= 0 THEN
        RAISE EXCEPTION 'El monto del egreso debe ser mayor que cero';
    END IF;

    SELECT id INTO v_id_banco
    FROM public.dep_dat_banco
    WHERE idtienda = p_idtienda
      AND activo = TRUE
      AND es_predeterminada_fondo_caja = TRUE;

    IF v_id_banco IS NULL THEN
        RAISE EXCEPTION 'La tienda no tiene una cuenta predeterminada activa de Fondo de Caja';
    END IF;

    PERFORM pg_advisory_xact_lock(
        hashtextextended(p_idtienda::TEXT || ':' || v_id_banco::TEXT, 0)
    );

    v_result := public.fn_registrar_egreso_offline(
        p_client_uuid := p_client_uuid,
        p_id_turno := p_id_turno,
        p_monto_entrega := p_monto_entrega,
        p_nombre_recibe := p_nombre_recibe,
        p_nombre_autoriza := p_nombre_autoriza,
        p_motivo_entrega := p_motivo_entrega,
        p_id_medio_pago := p_id_medio_pago,
        p_uuid_usuario := p_uuid_usuario
    );

    IF v_result IS NULL OR COALESCE((v_result->>'success')::BOOLEAN, FALSE) = FALSE THEN
        RAISE EXCEPTION 'No se pudo registrar el egreso: %', COALESCE(v_result->>'message', 'error desconocido');
    END IF;

    v_id_egreso := NULLIF(v_result->>'egreso_id', '')::BIGINT;
    IF v_id_egreso IS NULL THEN
        RAISE EXCEPTION 'El registro del egreso no devolvió su identificador';
    END IF;

    SELECT id INTO v_id_recarga
    FROM public.dep_dat_recarga_saldo
    WHERE id_egreso_origen = v_id_egreso;

    IF v_id_recarga IS NULL THEN
        INSERT INTO public.dep_dat_saldo (idtienda, id_banco, saldo_disponible, updated_at)
        VALUES (p_idtienda, v_id_banco, 0, now())
        ON CONFLICT (idtienda, id_banco) DO NOTHING;

        SELECT saldo_disponible INTO v_saldo_anterior
        FROM public.dep_dat_saldo
        WHERE idtienda = p_idtienda AND id_banco = v_id_banco
        FOR UPDATE;

        v_saldo_nuevo := v_saldo_anterior + p_monto_entrega;

        INSERT INTO public.dep_dat_recarga_saldo (
            idtienda, id_banco, monto, fecha_pago, observacion,
            created_at, id_egreso_origen
        ) VALUES (
            p_idtienda, v_id_banco, p_monto_entrega, CURRENT_DATE,
            'Ingreso desde egreso #' || v_id_egreso || ': ' || p_motivo_entrega,
            now(), v_id_egreso
        ) RETURNING id INTO v_id_recarga;

        UPDATE public.dep_dat_saldo
        SET saldo_disponible = v_saldo_nuevo, updated_at = now()
        WHERE idtienda = p_idtienda AND id_banco = v_id_banco;

        INSERT INTO public.dep_hist_saldo (
            idtienda, id_banco, monto_anterior, monto_nuevo, diferencia,
            tipo_operacion, referencia, id_recarga, created_at
        ) VALUES (
            p_idtienda, v_id_banco, v_saldo_anterior, v_saldo_nuevo,
            p_monto_entrega, 'recarga_egreso',
            'Egreso de caja #' || v_id_egreso, v_id_recarga, now()
        );
    END IF;

    RETURN v_result || jsonb_build_object(
        'recarga_id', v_id_recarga,
        'fondo_caja_aplicado', TRUE,
        'id_banco', v_id_banco
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.dep_establecer_banco_predeterminado(INTEGER, BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_registrar_egreso_fondo_caja(UUID, INTEGER, BIGINT, NUMERIC, CHARACTER VARYING, CHARACTER VARYING, TEXT, SMALLINT, UUID) TO authenticated;


-- ============================================================================
-- 11. RLS
-- ============================================================================

ALTER TABLE public.dep_nom_moneda            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dep_dat_banco             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dep_nom_estado_deposito   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dep_nom_tipo_extraccion   ENABLE ROW LEVEL SECURITY;
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
  CREATE POLICY "Acceso autenticado - dep_nom_tipo_extraccion"
    ON public.dep_nom_tipo_extraccion FOR ALL TO authenticated USING (TRUE) WITH CHECK (TRUE);
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

NOTIFY pgrst, 'reload schema';
