BEGIN;

-- BORRADOR MC-010. NO EJECUTAR en main.
-- Añade USD opcional al precio de TPV. El CUP sigue obligatorio y positivo.
-- No habilita un precio solo en USD. El producto y el TPV tienen que ser
-- de la misma tienda. anon deja de escribir la tabla.

SET LOCAL app.m01_r10_precio_tpv_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r10_precio_tpv_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador MC-010: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF to_regclass('public.app_dat_precio_tpv') IS NULL
       OR to_regclass('public.app_dat_tpv') IS NULL
       OR to_regclass('public.app_dat_producto') IS NULL
       OR to_regprocedure('public.fn_config_tienda_puede_leer(bigint)') IS NULL
       OR to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta el precio de TPV o el acceso por tienda';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'public.app_dat_precio_tpv'::regclass
          AND attname = 'precio_venta_usd'
          AND NOT attisdropped
    ) OR to_regprocedure('public.fn_m01_tienda_de_tpv(bigint)') IS NOT NULL THEN
        RAISE EXCEPTION 'El USD de precio TPV ya existe';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.app_dat_precio_tpv
        WHERE precio_venta_cup IS NULL OR precio_venta_cup <= 0
    ) THEN
        RAISE EXCEPTION 'Hay precios TPV sin CUP positivo; no se añade el USD';
    END IF;
END;
$preflight$;

ALTER TABLE public.app_dat_precio_tpv
    ADD COLUMN precio_venta_usd numeric;

ALTER TABLE public.app_dat_precio_tpv
    ADD CONSTRAINT m01_precio_tpv_cup_obligatorio
    CHECK (
        precio_venta_cup IS NOT NULL
        AND precio_venta_cup > 0
        AND precio_venta_cup <> 'NaN'::numeric
    );

ALTER TABLE public.app_dat_precio_tpv
    ADD CONSTRAINT m01_precio_tpv_usd_opcional
    CHECK (
        precio_venta_usd IS NULL
        OR (
            precio_venta_usd > 0
            AND precio_venta_usd <> 'NaN'::numeric
        )
    );

CREATE OR REPLACE FUNCTION public.fn_m01_tienda_de_tpv(p_id_tpv bigint)
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
    SELECT t.id_tienda
    FROM public.app_dat_tpv t
    WHERE t.id = p_id_tpv;
$function$;

CREATE OR REPLACE FUNCTION public.fn_m01_tienda_precio_tpv(
    p_id_tpv bigint,
    p_id_producto bigint
)
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
    SELECT t.id_tienda
    FROM public.app_dat_tpv t
    JOIN public.app_dat_producto p ON p.id = p_id_producto
    WHERE t.id = p_id_tpv
      AND p.id_tienda = t.id_tienda
      AND p.deleted_at IS NULL;
$function$;

ALTER TABLE public.app_dat_precio_tpv ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_dat_precio_tpv FORCE ROW LEVEL SECURITY;

CREATE POLICY m01_precio_tpv_leer
    ON public.app_dat_precio_tpv
    FOR SELECT TO authenticated
    USING (
        public.fn_config_tienda_puede_leer(public.fn_m01_tienda_de_tpv(id_tpv))
    );

CREATE POLICY m01_precio_tpv_insertar
    ON public.app_dat_precio_tpv
    FOR INSERT TO authenticated
    WITH CHECK (
        public.fn_m01_tienda_precio_tpv(id_tpv, id_producto) IS NOT NULL
        AND public.fn_config_tienda_puede_escribir(
            public.fn_m01_tienda_precio_tpv(id_tpv, id_producto)
        )
    );

CREATE POLICY m01_precio_tpv_actualizar
    ON public.app_dat_precio_tpv
    FOR UPDATE TO authenticated
    USING (
        public.fn_config_tienda_puede_escribir(public.fn_m01_tienda_de_tpv(id_tpv))
    )
    WITH CHECK (
        public.fn_m01_tienda_precio_tpv(id_tpv, id_producto) IS NOT NULL
        AND public.fn_config_tienda_puede_escribir(
            public.fn_m01_tienda_precio_tpv(id_tpv, id_producto)
        )
    );

CREATE POLICY m01_precio_tpv_borrar
    ON public.app_dat_precio_tpv
    FOR DELETE TO authenticated
    USING (
        public.fn_config_tienda_puede_escribir(public.fn_m01_tienda_de_tpv(id_tpv))
    );

REVOKE ALL ON TABLE public.app_dat_precio_tpv FROM anon;
REVOKE TRUNCATE, TRIGGER, REFERENCES ON TABLE public.app_dat_precio_tpv FROM authenticated;

REVOKE ALL ON FUNCTION public.fn_m01_tienda_de_tpv(bigint) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_m01_tienda_precio_tpv(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_tienda_de_tpv(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_m01_tienda_precio_tpv(bigint, bigint) TO authenticated;

COMMIT;
