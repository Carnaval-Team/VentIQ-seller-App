BEGIN;

-- BORRADOR MC-006. NO EJECUTAR en main.
-- Añade permitir_moneda_por_producto en false y una revisión inmutable
-- del snapshot flag/forzado/monedas. El cliente no edita el historial.
-- Encender el flag queda rechazado hasta MC-009. No emite entregas al dispositivo.

SET LOCAL app.m01_r06_politica_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r06_politica_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador MC-006: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF to_regprocedure('public.fn_config_tienda_puede_leer(bigint)') IS NULL
       OR to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Faltan los helpers de configuracion de tienda';
    END IF;
    IF to_regclass('public.app_dat_configuracion_tienda') IS NULL
       OR to_regclass('public.app_dat_tienda_moneda') IS NULL THEN
        RAISE EXCEPTION 'Faltan la configuracion o las monedas de la tienda';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'public.app_dat_configuracion_tienda'::regclass
          AND attname = 'permitir_moneda_por_producto'
          AND NOT attisdropped
    ) OR to_regclass('public.app_dat_politica_moneda_revision') IS NOT NULL THEN
        RAISE EXCEPTION 'La revision de politica M01 ya existe';
    END IF;
END;
$preflight$;

ALTER TABLE public.app_dat_configuracion_tienda
    ADD COLUMN permitir_moneda_por_producto boolean NOT NULL DEFAULT false;

ALTER TABLE public.app_dat_configuracion_tienda
    ADD CONSTRAINT m01_politica_flag_apagada
    CHECK (permitir_moneda_por_producto = false);

CREATE TABLE public.app_dat_politica_moneda_revision (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_tienda bigint NOT NULL,
    numero integer NOT NULL,
    permitir_moneda_por_producto boolean NOT NULL,
    forzar_moneda_venta boolean NOT NULL,
    moneda_venta_forzada text,
    monedas_habilitadas jsonb NOT NULL,
    uuid_actor uuid,
    created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    CONSTRAINT m01_politica_revision_numero_positivo CHECK (numero > 0),
    CONSTRAINT m01_politica_revision_flag_apagada CHECK (permitir_moneda_por_producto = false),
    CONSTRAINT m01_politica_revision_monedas_lista CHECK (jsonb_typeof(monedas_habilitadas) = 'array'),
    CONSTRAINT m01_politica_revision_tienda_numero UNIQUE (id_tienda, numero)
);

ALTER TABLE public.app_dat_politica_moneda_revision ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_dat_politica_moneda_revision FORCE ROW LEVEL SECURITY;

CREATE POLICY m01_politica_revision_leer
    ON public.app_dat_politica_moneda_revision
    FOR SELECT TO authenticated
    USING (public.fn_config_tienda_puede_leer(id_tienda));

REVOKE ALL ON TABLE public.app_dat_politica_moneda_revision FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.app_dat_politica_moneda_revision TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_m01_politica_revision_bloquear()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF current_setting('app.m01_politica_publicar', true) IS DISTINCT FROM 'yes' THEN
            RAISE EXCEPTION 'La revision de politica no se edita' USING ERRCODE = '42501';
        END IF;
        RETURN NEW;
    END IF;
    RAISE EXCEPTION 'La revision de politica no se edita' USING ERRCODE = '42501';
END;
$function$;

CREATE TRIGGER m01_politica_revision_solo_servidor
    BEFORE INSERT ON public.app_dat_politica_moneda_revision
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_m01_politica_revision_bloquear();

CREATE TRIGGER m01_politica_revision_no_editar
    BEFORE UPDATE OR DELETE ON public.app_dat_politica_moneda_revision
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_m01_politica_revision_bloquear();

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
    IF v_flag IS DISTINCT FROM false THEN
        RAISE EXCEPTION 'Activacion de moneda por producto no autorizada' USING ERRCODE = '42501';
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
        p_id_tienda, COALESCE(v_numero, 0) + 1, false, v_forzar,
        v_forzada, v_monedas, v_actor
    )
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_m01_politica_capturar_revision()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_tienda bigint;
BEGIN
    IF TG_OP = 'INSERT' THEN
        FOR v_tienda IN SELECT DISTINCT n.id_tienda FROM nueva n LOOP
            PERFORM public.fn_m01_politica_insertar_revision(v_tienda);
        END LOOP;
    ELSIF TG_OP = 'DELETE' THEN
        FOR v_tienda IN SELECT DISTINCT v.id_tienda FROM vieja v LOOP
            PERFORM public.fn_m01_politica_insertar_revision(v_tienda);
        END LOOP;
    ELSE
        FOR v_tienda IN
            SELECT n.id_tienda FROM nueva n
            UNION
            SELECT v.id_tienda FROM vieja v
        LOOP
            PERFORM public.fn_m01_politica_insertar_revision(v_tienda);
        END LOOP;
    END IF;
    RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_m01_politica_guardar_flag()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
    IF NEW.permitir_moneda_por_producto IS DISTINCT FROM OLD.permitir_moneda_por_producto THEN
        IF current_setting('app.m01_politica_flag_autorizada', true) IS DISTINCT FROM 'yes'
           OR NEW.permitir_moneda_por_producto IS DISTINCT FROM false THEN
            RAISE EXCEPTION 'Activacion de moneda por producto no autorizada' USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE TRIGGER m01_politica_flag_solo_publicacion
    BEFORE UPDATE OF permitir_moneda_por_producto
    ON public.app_dat_configuracion_tienda
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_m01_politica_guardar_flag();

CREATE OR REPLACE FUNCTION public.fn_m01_politica_config_fila()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
    PERFORM public.fn_m01_politica_insertar_revision(NEW.id_tienda);
    RETURN NULL;
END;
$function$;

CREATE TRIGGER m01_politica_config_revision
    AFTER UPDATE OF permitir_moneda_por_producto, forzar_moneda_venta, moneda_venta_forzada
    ON public.app_dat_configuracion_tienda
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_m01_politica_config_fila();

CREATE TRIGGER m01_politica_moneda_revision_ins
    AFTER INSERT ON public.app_dat_tienda_moneda
    REFERENCING NEW TABLE AS nueva
    FOR EACH STATEMENT
    EXECUTE FUNCTION public.fn_m01_politica_capturar_revision();

CREATE TRIGGER m01_politica_moneda_revision_upd
    AFTER UPDATE ON public.app_dat_tienda_moneda
    REFERENCING NEW TABLE AS nueva OLD TABLE AS vieja
    FOR EACH STATEMENT
    EXECUTE FUNCTION public.fn_m01_politica_capturar_revision();

CREATE TRIGGER m01_politica_moneda_revision_del
    AFTER DELETE ON public.app_dat_tienda_moneda
    REFERENCING OLD TABLE AS vieja
    FOR EACH STATEMENT
    EXECUTE FUNCTION public.fn_m01_politica_capturar_revision();

CREATE OR REPLACE FUNCTION public.fn_m01_publicar_revision_politica(p_id_tienda bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_antes integer;
    v_despues integer;
    v_id bigint;
    v_numero integer;
BEGIN
    IF v_actor IS NULL OR p_id_tienda IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF public.fn_config_tienda_puede_escribir(p_id_tienda) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    PERFORM 1
    FROM public.app_dat_configuracion_tienda
    WHERE id_tienda = p_id_tienda
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    SELECT count(*) INTO v_antes
    FROM public.app_dat_politica_moneda_revision
    WHERE id_tienda = p_id_tienda;
    PERFORM set_config('app.m01_politica_flag_autorizada', 'yes', true);
    UPDATE public.app_dat_configuracion_tienda
    SET permitir_moneda_por_producto = false
    WHERE id_tienda = p_id_tienda;
    SELECT count(*) INTO v_despues
    FROM public.app_dat_politica_moneda_revision
    WHERE id_tienda = p_id_tienda;
    SELECT r.id, r.numero INTO v_id, v_numero
    FROM public.app_dat_politica_moneda_revision r
    WHERE r.id_tienda = p_id_tienda
    ORDER BY r.numero DESC
    LIMIT 1;
    RETURN jsonb_build_object(
        'success', true,
        'id_revision', v_id,
        'numero', v_numero,
        'idempotent', v_despues = v_antes
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_m01_politica_revision_bloquear() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_m01_politica_insertar_revision(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_m01_politica_capturar_revision() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_m01_politica_config_fila() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_m01_politica_guardar_flag() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_m01_publicar_revision_politica(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_publicar_revision_politica(bigint) TO authenticated;

COMMIT;
