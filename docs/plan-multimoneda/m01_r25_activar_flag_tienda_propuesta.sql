BEGIN;

-- El administrador de la tienda puede guardar el flag en true.
-- El vendedor solo vende en una moneda cuyo precio ya está configurado.
-- No enciende ninguna tienda: solo deja que el interruptor se guarde.

SET LOCAL app.m01_r25_activar_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r25_activar_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador: NO EJECUTAR sin revision en newa';
    END IF;
    IF to_regprocedure('public.fn_m01_fijar_moneda_por_producto(bigint,boolean)') IS NULL
       OR to_regprocedure('public.fn_m01_registrar_venta_v1(jsonb)') IS NULL THEN
        RAISE EXCEPTION 'Falta el interruptor o el registro de venta v1';
    END IF;
END;
$preflight$;

ALTER TABLE public.app_dat_configuracion_tienda
    DROP CONSTRAINT IF EXISTS m01_politica_flag_apagada;

ALTER TABLE public.app_dat_politica_moneda_revision
    DROP CONSTRAINT IF EXISTS m01_politica_revision_flag_apagada;

CREATE OR REPLACE FUNCTION public.fn_m01_politica_guardar_flag()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
    IF NEW.permitir_moneda_por_producto IS DISTINCT FROM OLD.permitir_moneda_por_producto
       AND current_setting('app.m01_politica_flag_autorizada', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Activacion de moneda por producto no autorizada' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_m01_politica_insertar_revision(p_id_tienda bigint)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_flag boolean;
    v_forzar boolean;
    v_forzada text;
    v_monedas jsonb;
    v_id bigint;
    v_numero integer;
    v_igual boolean;
BEGIN
    IF p_id_tienda IS NULL THEN
        RETURN NULL;
    END IF;
    IF v_actor IS NULL AND current_user <> 'postgres' THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended('m01-politica:' || p_id_tienda::text, 0));
    SELECT c.permitir_moneda_por_producto,
           c.forzar_moneda_venta,
           NULLIF(pg_catalog.btrim(c.moneda_venta_forzada::text), '')
      INTO v_flag, v_forzar, v_forzada
    FROM public.app_dat_configuracion_tienda c
    WHERE c.id_tienda = p_id_tienda
    FOR UPDATE;
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;
    SELECT COALESCE(jsonb_agg(pg_catalog.btrim(m.moneda::text) ORDER BY m.orden, m.moneda), '[]'::jsonb)
      INTO v_monedas
    FROM public.app_dat_tienda_moneda m
    WHERE m.id_tienda = p_id_tienda
      AND m.activo IS TRUE;
    SELECT r.id, r.numero,
           r.permitir_moneda_por_producto IS NOT DISTINCT FROM v_flag
           AND r.forzar_moneda_venta IS NOT DISTINCT FROM v_forzar
           AND r.moneda_venta_forzada IS NOT DISTINCT FROM v_forzada
           AND r.monedas_habilitadas IS NOT DISTINCT FROM v_monedas
      INTO v_id, v_numero, v_igual
    FROM public.app_dat_politica_moneda_revision r
    WHERE r.id_tienda = p_id_tienda
    ORDER BY r.numero DESC
    LIMIT 1
    FOR UPDATE;
    IF v_igual THEN
        RETURN v_id;
    END IF;
    PERFORM set_config('app.m01_politica_publicar', 'yes', true);
    INSERT INTO public.app_dat_politica_moneda_revision (
        id_tienda, numero, permitir_moneda_por_producto, forzar_moneda_venta,
        moneda_venta_forzada, monedas_habilitadas, uuid_actor
    ) VALUES (
        p_id_tienda, COALESCE(v_numero, 0) + 1, v_flag, v_forzar,
        v_forzada, v_monedas, v_actor
    )
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_m01_publicar_revision_politica(p_id_tienda bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_id bigint;
BEGIN
    IF v_actor IS NULL OR p_id_tienda IS NULL
       OR public.fn_config_tienda_puede_escribir(p_id_tienda) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_id := public.fn_m01_politica_insertar_revision(p_id_tienda);
    RETURN jsonb_build_object('success', true, 'id_revision', v_id);
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
    IF auth.uid() IS NULL OR p_id_tienda IS NULL OR p_activar IS NULL
       OR public.fn_config_tienda_puede_escribir(p_id_tienda) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF p_activar IS TRUE
       AND to_regprocedure('public.fn_m01_registrar_venta_v1(jsonb)') IS NULL THEN
        RAISE EXCEPTION 'Activacion de moneda por producto no autorizada' USING ERRCODE = '42501';
    END IF;
    PERFORM set_config('app.m01_politica_flag_autorizada', 'yes', true);
    UPDATE public.app_dat_configuracion_tienda
    SET permitir_moneda_por_producto = p_activar
    WHERE id_tienda = p_id_tienda;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    RETURN jsonb_build_object(
        'success', true,
        'permitir_moneda_por_producto', p_activar
    );
END;
$function$;

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
    v_puede boolean;
BEGIN
    IF v_actor IS NULL OR p_id_tienda IS NULL
       OR public.fn_config_tienda_puede_leer(p_id_tienda) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    SELECT c.permitir_moneda_por_producto INTO v_flag
    FROM public.app_dat_configuracion_tienda c
    WHERE c.id_tienda = p_id_tienda;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_puede := to_regprocedure('public.fn_m01_registrar_venta_v1(jsonb)') IS NOT NULL;
    RETURN jsonb_build_object(
        'success', true,
        'permitir_moneda_por_producto', v_flag,
        'activacion_permitida', v_puede,
        'motivo', CASE WHEN v_puede THEN NULL ELSE 'falta el registro de venta v1' END
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_m01_fijar_moneda_por_producto(bigint, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_m01_estado_capacidad_moneda(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_fijar_moneda_por_producto(bigint, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_m01_estado_capacidad_moneda(bigint) TO authenticated;

COMMIT;
