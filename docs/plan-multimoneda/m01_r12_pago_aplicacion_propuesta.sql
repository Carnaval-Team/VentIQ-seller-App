BEGIN;

-- BORRADOR MC-023. NO EJECUTAR en main.
-- Atribuye un pago real a una línea y a su tasa. No crea otro ingreso
-- y no reescribe app_dat_pago_venta ni la extracción.

SET LOCAL app.m01_r12_aplicacion_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r12_aplicacion_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador MC-023: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF to_regclass('public.app_dat_pago_aplicacion') IS NOT NULL THEN
        RAISE EXCEPTION 'La atribucion de pago ya existe';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'app_dat_extraccion_productos'
          AND column_name = 'moneda_venta'
    ) THEN
        RAISE EXCEPTION 'Falta la moneda de la extraccion';
    END IF;
    IF to_regprocedure('public.fn_config_tienda_puede_leer(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta la lectura por tienda';
    END IF;
END;
$preflight$;

CREATE TABLE public.app_dat_pago_aplicacion (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_pago bigint NOT NULL REFERENCES public.app_dat_pago_venta (id),
    id_extraccion bigint NOT NULL REFERENCES public.app_dat_extraccion_productos (id),
    id_linea_cliente uuid NOT NULL,
    moneda text NOT NULL,
    monto_nativo numeric NOT NULL,
    tasa_cambio_cup numeric NOT NULL,
    importe_cup_equivalente numeric NOT NULL,
    CONSTRAINT m01_pago_aplicacion_unica UNIQUE (id_pago, id_extraccion),
    CONSTRAINT m01_pago_aplicacion_importes CHECK (
        moneda IN ('CUP', 'USD')
        AND monto_nativo = monto_nativo
        AND monto_nativo > 0
        AND tasa_cambio_cup = tasa_cambio_cup
        AND tasa_cambio_cup > 0
        AND importe_cup_equivalente = importe_cup_equivalente
        AND importe_cup_equivalente >= 0
        AND ((moneda = 'CUP' AND tasa_cambio_cup = 1) OR moneda = 'USD')
    )
);

CREATE INDEX m01_pago_aplicacion_extraccion
    ON public.app_dat_pago_aplicacion (id_extraccion);

ALTER TABLE public.app_dat_pago_aplicacion ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_dat_pago_aplicacion FORCE ROW LEVEL SECURITY;

CREATE POLICY app_dat_pago_aplicacion_select
    ON public.app_dat_pago_aplicacion
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.app_dat_pago_venta p
            JOIN public.app_dat_operaciones o ON o.id = p.id_operacion_venta
            WHERE p.id = id_pago
              AND public.fn_config_tienda_puede_leer(o.id_tienda)
        )
    );

CREATE POLICY app_dat_pago_aplicacion_insert
    ON public.app_dat_pago_aplicacion
    FOR INSERT
    TO authenticated
    WITH CHECK (false);

CREATE POLICY app_dat_pago_aplicacion_update
    ON public.app_dat_pago_aplicacion
    FOR UPDATE
    TO authenticated
    USING (false)
    WITH CHECK (false);

CREATE POLICY app_dat_pago_aplicacion_delete
    ON public.app_dat_pago_aplicacion
    FOR DELETE
    TO authenticated
    USING (false);

REVOKE ALL ON TABLE public.app_dat_pago_aplicacion FROM PUBLIC;
REVOKE ALL ON TABLE public.app_dat_pago_aplicacion FROM anon;
GRANT SELECT ON TABLE public.app_dat_pago_aplicacion TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_m01_pago_aplicacion_validar()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
DECLARE
    v_version text;
    v_moneda text;
    v_tasa numeric;
    v_operacion bigint;
    v_pago_moneda text;
    v_pago_operacion bigint;
BEGIN
    SELECT e.version_monetaria, e.moneda_venta, e.tasa_cambio_cup, e.id_operacion,
           p.moneda, p.id_operacion_venta
      INTO v_version, v_moneda, v_tasa, v_operacion, v_pago_moneda, v_pago_operacion
      FROM public.app_dat_extraccion_productos e
      JOIN public.app_dat_pago_venta p ON p.id = NEW.id_pago
     WHERE e.id = NEW.id_extraccion;
    IF NOT FOUND OR v_version IS DISTINCT FROM 'producto-v1' THEN
        RAISE EXCEPTION 'La atribucion exige una linea producto-v1 de la misma venta'
            USING ERRCODE = '23514';
    END IF;
    IF v_operacion IS DISTINCT FROM v_pago_operacion
       OR v_moneda IS DISTINCT FROM NEW.moneda
       OR v_pago_moneda IS DISTINCT FROM NEW.moneda
       OR v_tasa IS DISTINCT FROM NEW.tasa_cambio_cup
       OR NEW.id_linea_cliente IS NULL THEN
        RAISE EXCEPTION 'La atribucion no cruza moneda, tasa ni venta'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS m01_pago_aplicacion_validar ON public.app_dat_pago_aplicacion;
CREATE TRIGGER m01_pago_aplicacion_validar
    BEFORE INSERT OR UPDATE
    ON public.app_dat_pago_aplicacion
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_m01_pago_aplicacion_validar();

COMMIT;
