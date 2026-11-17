BEGIN;

-- BORRADOR MC-022. NO EJECUTAR en main.
-- Agrega el contrato producto-v1 a la venta y a la extracción.
-- Las filas viejas quedan con la versión vacía. No reescribe importes.

SET LOCAL app.m01_r12_extraccion_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r12_extraccion_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador MC-022: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF to_regclass('public.app_dat_extraccion_productos') IS NULL
       OR to_regclass('public.app_dat_operacion_venta') IS NULL
       OR to_regclass('public.app_dat_politica_moneda_revision') IS NULL
       OR to_regclass('public.app_dat_politica_moneda_constancia') IS NULL
       OR to_regclass('public.app_nom_medio_pago') IS NULL THEN
        RAISE EXCEPTION 'Falta la venta, la revision o el catalogo de medios';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'app_dat_extraccion_productos'
          AND column_name = 'version_monetaria'
    ) THEN
        RAISE EXCEPTION 'La extraccion ya tiene version monetaria';
    END IF;
END;
$preflight$;

ALTER TABLE public.app_dat_operacion_venta
    ADD COLUMN version_monetaria text,
    ADD COLUMN id_revision_politica bigint,
    ADD COLUMN id_constancia_politica bigint;

ALTER TABLE public.app_dat_operacion_venta
    ADD CONSTRAINT m01_venta_version_conocida
    CHECK (version_monetaria IS NULL OR version_monetaria = 'producto-v1'),
    ADD CONSTRAINT m01_venta_v1_politica
    CHECK (
        version_monetaria IS DISTINCT FROM 'producto-v1'
        OR (id_revision_politica IS NOT NULL AND id_constancia_politica IS NOT NULL)
    ),
    ADD CONSTRAINT app_dat_operacion_venta_id_revision_politica_fkey
    FOREIGN KEY (id_revision_politica)
    REFERENCES public.app_dat_politica_moneda_revision (id),
    ADD CONSTRAINT app_dat_operacion_venta_id_constancia_politica_fkey
    FOREIGN KEY (id_constancia_politica)
    REFERENCES public.app_dat_politica_moneda_constancia (id);

ALTER TABLE public.app_dat_extraccion_productos
    ADD COLUMN version_monetaria text,
    ADD COLUMN id_linea_cliente uuid,
    ADD COLUMN moneda_venta text,
    ADD COLUMN id_medio_pago_seleccionado smallint,
    ADD COLUMN seleccion_pendiente boolean NOT NULL DEFAULT false,
    ADD COLUMN precio_unitario_nativo numeric,
    ADD COLUMN descuento_manual_unitario_nativo numeric,
    ADD COLUMN precio_unitario_neto_nativo numeric,
    ADD COLUMN importe_bruto_nativo numeric,
    ADD COLUMN importe_neto_nativo numeric,
    ADD COLUMN tasa_cambio_cup numeric,
    ADD COLUMN importe_bruto_cup_equivalente numeric,
    ADD COLUMN importe_neto_cup_equivalente numeric,
    ADD COLUMN snapshot_precio jsonb,
    ADD COLUMN snapshot_descuentos jsonb,
    ADD COLUMN snapshot_tasa jsonb;

ALTER TABLE public.app_dat_extraccion_productos
    ADD CONSTRAINT app_dat_extraccion_productos_id_medio_pago_seleccionado_fkey
    FOREIGN KEY (id_medio_pago_seleccionado)
    REFERENCES public.app_nom_medio_pago (id),
    ADD CONSTRAINT m01_extraccion_v1_completa
    CHECK (
        version_monetaria IS NULL
        OR (
            version_monetaria = 'producto-v1'
            AND id_linea_cliente IS NOT NULL
            AND moneda_venta IN ('CUP', 'USD')
            AND precio_unitario_nativo = precio_unitario_nativo
            AND precio_unitario_nativo > 0
            AND descuento_manual_unitario_nativo = descuento_manual_unitario_nativo
            AND descuento_manual_unitario_nativo >= 0
            AND precio_unitario_neto_nativo = precio_unitario_neto_nativo
            AND precio_unitario_neto_nativo >= 0
            AND importe_bruto_nativo = importe_bruto_nativo
            AND importe_bruto_nativo >= 0
            AND importe_neto_nativo = importe_neto_nativo
            AND importe_neto_nativo >= 0
            AND tasa_cambio_cup = tasa_cambio_cup
            AND tasa_cambio_cup > 0
            AND importe_bruto_cup_equivalente = importe_bruto_cup_equivalente
            AND importe_bruto_cup_equivalente >= 0
            AND importe_neto_cup_equivalente = importe_neto_cup_equivalente
            AND importe_neto_cup_equivalente >= 0
            AND (
                (moneda_venta = 'CUP' AND tasa_cambio_cup = 1)
                OR moneda_venta = 'USD'
            )
            AND (
                (seleccion_pendiente AND id_medio_pago_seleccionado IS NULL)
                OR (NOT seleccion_pendiente AND id_medio_pago_seleccionado IS NOT NULL)
            )
            AND snapshot_precio IS NOT NULL
            AND snapshot_descuentos IS NOT NULL
            AND snapshot_tasa IS NOT NULL
        )
    );

CREATE UNIQUE INDEX m01_extraccion_linea_cliente
    ON public.app_dat_extraccion_productos (id_operacion, id_linea_cliente)
    WHERE id_linea_cliente IS NOT NULL;

CREATE OR REPLACE FUNCTION public.fn_m01_venta_v1_exigir_uuid()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
    IF NEW.version_monetaria IS NULL THEN
        RETURN NEW;
    END IF;
    IF NEW.version_monetaria IS DISTINCT FROM 'producto-v1' THEN
        RAISE EXCEPTION 'Version monetaria no admitida' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM public.app_dat_operaciones o
        WHERE o.id = NEW.id_operacion
          AND o.uuid IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'producto-v1 exige el uuid de la operacion'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS m01_venta_v1_uuid ON public.app_dat_operacion_venta;
CREATE TRIGGER m01_venta_v1_uuid
    BEFORE INSERT OR UPDATE OF version_monetaria, id_operacion
    ON public.app_dat_operacion_venta
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_m01_venta_v1_exigir_uuid();

COMMIT;
