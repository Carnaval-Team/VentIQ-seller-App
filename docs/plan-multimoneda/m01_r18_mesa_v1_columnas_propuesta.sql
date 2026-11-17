BEGIN;

-- BORRADOR MC-039. NO EJECUTAR en main.
-- La cuenta y cada linea pueden guardar la version y el snapshot.
-- Una fila vieja sigue con esos campos vacios. No se rellena historia.
-- app_dat_mesa_cuenta_abierta y app_dat_mesa_cuenta_item siguen sin RLS:
-- la impresora las lee directo y hoy no tienen policies. Encender RLS aqui
-- bloquearia el restaurante. Las tablas nuevas de este script si lo tienen.

SET LOCAL app.m01_r18_mesa_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r18_mesa_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador MC-039: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF to_regclass('public.app_dat_mesa_cuenta_item') IS NULL THEN
        RAISE EXCEPTION 'Falta la cuenta de mesa';
    END IF;
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'app_dat_mesa_cuenta_item'
          AND column_name = 'version_monetaria'
    ) OR to_regclass('public.app_dat_mesa_v1_idempotencia') IS NOT NULL THEN
        RAISE EXCEPTION 'La mesa v1 ya tiene columnas o su clave';
    END IF;
END;
$preflight$;

ALTER TABLE public.app_dat_mesa_cuenta_abierta
    ADD COLUMN version_monetaria text,
    ADD COLUMN id_revision_politica bigint,
    ADD COLUMN id_constancia_politica bigint;

ALTER TABLE public.app_dat_mesa_cuenta_abierta
    ADD CONSTRAINT m01_mesa_version_v1 CHECK (
        version_monetaria IS NULL
        OR (
            version_monetaria = 'producto-v1'
            AND id_revision_politica IS NOT NULL
            AND id_constancia_politica IS NOT NULL
        )
    );

ALTER TABLE public.app_dat_mesa_cuenta_item
    ADD COLUMN version_monetaria text,
    ADD COLUMN id_linea_cliente uuid,
    ADD COLUMN moneda_venta text,
    ADD COLUMN seleccion_pendiente boolean,
    ADD COLUMN precio_unitario_nativo numeric,
    ADD COLUMN descuento_manual_unitario_nativo numeric,
    ADD COLUMN importe_neto_nativo numeric,
    ADD COLUMN tasa_cambio_cup numeric,
    ADD COLUMN importe_neto_cup_equivalente numeric,
    ADD COLUMN snapshot_precio jsonb,
    ADD COLUMN snapshot_tasa jsonb,
    ADD COLUMN snapshot_ajustes jsonb;

ALTER TABLE public.app_dat_mesa_cuenta_item
    ADD CONSTRAINT m01_mesa_item_version_v1 CHECK (
        (version_monetaria IS NULL AND id_linea_cliente IS NULL AND moneda_venta IS NULL)
        OR (
            version_monetaria = 'producto-v1'
            AND id_linea_cliente IS NOT NULL
            AND moneda_venta IN ('CUP', 'USD')
            AND importe_neto_nativo IS NOT NULL
            AND snapshot_precio IS NOT NULL
        )
    );

CREATE UNIQUE INDEX m01_mesa_item_linea_cliente
    ON public.app_dat_mesa_cuenta_item (id_linea_cliente)
    WHERE id_linea_cliente IS NOT NULL;

CREATE TABLE public.app_dat_mesa_v1_idempotencia (
    client_uuid uuid PRIMARY KEY,
    tipo text NOT NULL,
    uuid_usuario uuid NOT NULL,
    id_tienda bigint NOT NULL,
    id_cuenta bigint,
    id_item bigint,
    id_operacion bigint,
    solicitud jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT pg_catalog.now()
);

ALTER TABLE public.app_dat_mesa_v1_idempotencia ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_dat_mesa_v1_idempotencia FORCE ROW LEVEL SECURITY;

CREATE POLICY app_dat_mesa_v1_idempotencia_select
    ON public.app_dat_mesa_v1_idempotencia
    FOR SELECT TO authenticated
    USING (public.fn_config_tienda_puede_leer(id_tienda));

CREATE POLICY app_dat_mesa_v1_idempotencia_sin_escritura
    ON public.app_dat_mesa_v1_idempotencia
    FOR ALL TO authenticated
    USING (false)
    WITH CHECK (false);

CREATE TABLE public.app_dat_mesa_linea_v1_historial (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_tienda bigint NOT NULL,
    id_cuenta bigint NOT NULL,
    id_item bigint NOT NULL,
    id_linea_cliente uuid NOT NULL,
    moneda_venta text NOT NULL,
    importe_neto_nativo numeric NOT NULL,
    snapshot_precio jsonb NOT NULL,
    motivo text,
    created_at timestamptz NOT NULL DEFAULT pg_catalog.now()
);

ALTER TABLE public.app_dat_mesa_linea_v1_historial ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_dat_mesa_linea_v1_historial FORCE ROW LEVEL SECURITY;

CREATE POLICY app_dat_mesa_linea_v1_historial_select
    ON public.app_dat_mesa_linea_v1_historial
    FOR SELECT TO authenticated
    USING (public.fn_config_tienda_puede_leer(id_tienda));

CREATE POLICY app_dat_mesa_linea_v1_historial_sin_escritura
    ON public.app_dat_mesa_linea_v1_historial
    FOR ALL TO authenticated
    USING (false)
    WITH CHECK (false);

COMMIT;
