BEGIN;

-- BORRADOR MC-009. NO EJECUTAR en main.
-- Confirma que la política publicada existe y deja el flag en false.
-- Pedir activarlo se rechaza: todavía no existe el registro de venta v1.

SET LOCAL app.m01_r09_capacidad_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r09_capacidad_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador MC-009: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF to_regclass('public.app_dat_politica_moneda_revision') IS NULL
       OR to_regclass('public.app_dat_politica_moneda_constancia') IS NULL
       OR to_regprocedure('public.fn_m01_publicar_revision_politica(bigint)') IS NULL
       OR to_regprocedure('public.fn_config_tienda_puede_leer(bigint)') IS NULL
       OR to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta la revision, la entrega o la publicacion de politica';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM pg_attribute
        WHERE attrelid = 'public.app_dat_configuracion_tienda'::regclass
          AND attname = 'permitir_moneda_por_producto'
          AND atttypid = 'boolean'::regtype
          AND attnotnull
          AND NOT attisdropped
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'm01_politica_flag_apagada'
          AND conrelid = 'public.app_dat_configuracion_tienda'::regclass
    ) THEN
        RAISE EXCEPTION 'Definicion desconocida del flag de moneda por producto';
    END IF;
    IF to_regprocedure('public.fn_m01_fijar_moneda_por_producto(bigint,boolean)') IS NOT NULL THEN
        RAISE EXCEPTION 'La capacidad M01 de politica ya existe';
    END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.fn_m01_estado_capacidad_moneda(p_id_tienda bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_flag boolean;
BEGIN
    IF v_actor IS NULL OR p_id_tienda IS NULL
       OR public.fn_config_tienda_puede_leer(p_id_tienda) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    SELECT c.permitir_moneda_por_producto INTO v_flag
    FROM public.app_dat_configuracion_tienda c
    WHERE c.id_tienda = p_id_tienda;
    IF NOT FOUND OR v_flag IS DISTINCT FROM false THEN
        RAISE EXCEPTION 'Definicion desconocida del flag de moneda por producto'
            USING ERRCODE = '42501';
    END IF;
    RETURN jsonb_build_object(
        'success', true,
        'permitir_moneda_por_producto', false,
        'activacion_permitida', false,
        'motivo', 'falta el registro de venta v1'
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_m01_fijar_moneda_por_producto(
    p_id_tienda bigint,
    p_activar boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
    IF auth.uid() IS NULL OR p_id_tienda IS NULL OR p_activar IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF p_activar IS DISTINCT FROM false THEN
        RAISE EXCEPTION 'Activacion de moneda por producto no autorizada'
            USING ERRCODE = '42501';
    END IF;
    RETURN public.fn_m01_publicar_revision_politica(p_id_tienda);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_m01_estado_capacidad_moneda(bigint) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_m01_fijar_moneda_por_producto(bigint, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_estado_capacidad_moneda(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_m01_fijar_moneda_por_producto(bigint, boolean) TO authenticated;

COMMIT;
