BEGIN;

-- BORRADOR MC-007. NO EJECUTAR en main.
-- Emite una entrega de política al usuario autenticado y a su dispositivo,
-- ligada a una revisión ya publicada y a la ventana de licencia existente.
-- No alarga esa ventana, no acepta la hora del dispositivo y no copia precios.

SET LOCAL app.m01_r07_constancia_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r07_constancia_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador MC-007: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF to_regclass('public.app_dat_politica_moneda_revision') IS NULL
       OR to_regprocedure('public.fn_m01_publicar_revision_politica(bigint)') IS NULL
       OR to_regprocedure('public.fn_config_tienda_puede_leer(bigint)') IS NULL
       OR to_regclass('public.app_suscripciones') IS NULL
       OR to_regclass('public.app_dat_configuracion_tienda') IS NULL THEN
        RAISE EXCEPTION 'Falta la revision de politica o la licencia de la tienda';
    END IF;
    IF to_regclass('public.app_dat_politica_moneda_constancia') IS NOT NULL THEN
        RAISE EXCEPTION 'La entrega de politica M01 ya existe';
    END IF;
END;
$preflight$;

CREATE TABLE public.app_dat_politica_moneda_constancia (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_tienda bigint NOT NULL,
    id_revision bigint NOT NULL REFERENCES public.app_dat_politica_moneda_revision (id),
    uuid_sujeto uuid NOT NULL,
    dispositivo text NOT NULL,
    emitido_en timestamptz NOT NULL DEFAULT pg_catalog.now(),
    dias_max_observado integer NOT NULL,
    permitir_offline_observado boolean NOT NULL,
    fecha_fin_observada timestamptz,
    id_plan_observado smallint,
    huella jsonb NOT NULL,
    CONSTRAINT m01_constancia_dispositivo_forma CHECK (dispositivo ~ '^[A-Za-z0-9_.:-]{1,120}$'),
    CONSTRAINT m01_constancia_huella_objeto CHECK (jsonb_typeof(huella) = 'object'),
    CONSTRAINT m01_constancia_dias_no_negativos CHECK (dias_max_observado >= 0)
);

CREATE INDEX m01_constancia_sujeto_revision
    ON public.app_dat_politica_moneda_constancia (uuid_sujeto, id_tienda, dispositivo, id_revision);

ALTER TABLE public.app_dat_politica_moneda_constancia ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_dat_politica_moneda_constancia FORCE ROW LEVEL SECURITY;

CREATE POLICY m01_constancia_leer
    ON public.app_dat_politica_moneda_constancia
    FOR SELECT TO authenticated
    USING (uuid_sujeto = auth.uid());

REVOKE ALL ON TABLE public.app_dat_politica_moneda_constancia FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.app_dat_politica_moneda_constancia TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_m01_constancia_bloquear()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
    IF TG_OP = 'INSERT'
       AND current_setting('app.m01_constancia_emitir', true) = 'yes' THEN
        RETURN NEW;
    END IF;
    RAISE EXCEPTION 'La entrega de politica no se edita' USING ERRCODE = '42501';
END;
$function$;

CREATE TRIGGER m01_constancia_solo_servidor
    BEFORE INSERT ON public.app_dat_politica_moneda_constancia
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_m01_constancia_bloquear();

CREATE TRIGGER m01_constancia_no_editar
    BEFORE UPDATE OR DELETE ON public.app_dat_politica_moneda_constancia
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_m01_constancia_bloquear();

CREATE OR REPLACE FUNCTION public.fn_m01_emitir_constancia_politica(
    p_id_tienda bigint,
    p_dispositivo text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_dispositivo text := pg_catalog.btrim(p_dispositivo);
    v_revision public.app_dat_politica_moneda_revision%ROWTYPE;
    v_huella jsonb;
    v_dias integer;
    v_offline boolean;
    v_fin timestamptz;
    v_plan smallint;
    v_id bigint;
    v_emitido timestamptz;
BEGIN
    IF v_actor IS NULL OR p_id_tienda IS NULL OR v_dispositivo IS NULL
       OR v_dispositivo !~ '^[A-Za-z0-9_.:-]{1,120}$' THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF public.fn_config_tienda_puede_leer(p_id_tienda) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended(
        'm01-constancia:' || v_actor::text || ':' || p_id_tienda::text || ':' || v_dispositivo,
        0
    ));
    SELECT * INTO v_revision
    FROM public.app_dat_politica_moneda_revision
    WHERE id_tienda = p_id_tienda
    ORDER BY numero DESC
    LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No hay revision de politica publicada' USING ERRCODE = '42501';
    END IF;
    v_huella := jsonb_build_object(
        'id_revision', v_revision.id,
        'numero', v_revision.numero,
        'permitir_moneda_por_producto', v_revision.permitir_moneda_por_producto,
        'forzar_moneda_venta', v_revision.forzar_moneda_venta,
        'moneda_venta_forzada', v_revision.moneda_venta_forzada,
        'monedas_habilitadas', v_revision.monedas_habilitadas
    );
    SELECT c.dias_max_sin_validar_licencia, c.permitir_modo_offline_completo
      INTO v_dias, v_offline
    FROM public.app_dat_configuracion_tienda c
    WHERE c.id_tienda = p_id_tienda;
    IF NOT FOUND OR v_dias IS NULL OR v_dias < 0 OR v_offline IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    SELECT s.fecha_fin, s.id_plan
      INTO v_fin, v_plan
    FROM public.app_suscripciones s
    WHERE s.id_tienda = p_id_tienda
      AND s.estado = 1
    ORDER BY s.fecha_fin DESC NULLS LAST
    LIMIT 1;
    SELECT k.id, k.emitido_en INTO v_id, v_emitido
    FROM public.app_dat_politica_moneda_constancia k
    WHERE k.uuid_sujeto = v_actor
      AND k.id_tienda = p_id_tienda
      AND k.dispositivo = v_dispositivo
      AND k.id_revision = v_revision.id
      AND k.huella = v_huella
      AND k.dias_max_observado = v_dias
      AND k.permitir_offline_observado = v_offline
      AND k.fecha_fin_observada IS NOT DISTINCT FROM v_fin
      AND k.id_plan_observado IS NOT DISTINCT FROM v_plan
    ORDER BY k.id DESC
    LIMIT 1;
    IF FOUND THEN
        RETURN jsonb_build_object(
            'success', true,
            'idempotent', true,
            'id_constancia', v_id,
            'id_revision', v_revision.id,
            'emitido_en', v_emitido,
            'huella', v_huella
        );
    END IF;
    PERFORM set_config('app.m01_constancia_emitir', 'yes', true);
    INSERT INTO public.app_dat_politica_moneda_constancia (
        id_tienda, id_revision, uuid_sujeto, dispositivo,
        dias_max_observado, permitir_offline_observado,
        fecha_fin_observada, id_plan_observado, huella
    ) VALUES (
        p_id_tienda, v_revision.id, v_actor, v_dispositivo,
        v_dias, v_offline, v_fin, v_plan, v_huella
    )
    RETURNING id, emitido_en INTO v_id, v_emitido;
    RETURN jsonb_build_object(
        'success', true,
        'idempotent', false,
        'id_constancia', v_id,
        'id_revision', v_revision.id,
        'emitido_en', v_emitido,
        'huella', v_huella
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_m01_validar_constancia_politica(
    p_id_constancia bigint,
    p_id_tienda bigint,
    p_dispositivo text,
    p_id_revision bigint,
    p_huella jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_dispositivo text := pg_catalog.btrim(p_dispositivo);
    v_row public.app_dat_politica_moneda_constancia%ROWTYPE;
    v_revision public.app_dat_politica_moneda_revision%ROWTYPE;
    v_servidor jsonb;
    v_offline boolean;
    v_fin timestamptz;
    v_usable boolean;
BEGIN
    IF v_actor IS NULL OR p_id_constancia IS NULL OR p_id_tienda IS NULL
       OR p_id_revision IS NULL OR p_huella IS NULL
       OR v_dispositivo IS NULL
       OR v_dispositivo !~ '^[A-Za-z0-9_.:-]{1,120}$' THEN
        RAISE EXCEPTION 'Constancia ajena o manipulada' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_row
    FROM public.app_dat_politica_moneda_constancia
    WHERE id = p_id_constancia;
    IF NOT FOUND
       OR v_row.uuid_sujeto IS DISTINCT FROM v_actor
       OR v_row.id_tienda IS DISTINCT FROM p_id_tienda
       OR v_row.dispositivo IS DISTINCT FROM v_dispositivo
       OR v_row.id_revision IS DISTINCT FROM p_id_revision
       OR v_row.huella IS DISTINCT FROM p_huella THEN
        RAISE EXCEPTION 'Constancia ajena o manipulada' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_revision
    FROM public.app_dat_politica_moneda_revision
    WHERE id = v_row.id_revision
      AND id_tienda = v_row.id_tienda;
    v_servidor := jsonb_build_object(
        'id_revision', v_revision.id,
        'numero', v_revision.numero,
        'permitir_moneda_por_producto', v_revision.permitir_moneda_por_producto,
        'forzar_moneda_venta', v_revision.forzar_moneda_venta,
        'moneda_venta_forzada', v_revision.moneda_venta_forzada,
        'monedas_habilitadas', v_revision.monedas_habilitadas
    );
    IF NOT FOUND OR v_row.huella IS DISTINCT FROM v_servidor THEN
        RAISE EXCEPTION 'Constancia ajena o manipulada' USING ERRCODE = '42501';
    END IF;
    SELECT c.permitir_modo_offline_completo INTO v_offline
    FROM public.app_dat_configuracion_tienda c
    WHERE c.id_tienda = v_row.id_tienda;
    SELECT s.fecha_fin INTO v_fin
    FROM public.app_suscripciones s
    WHERE s.id_tienda = v_row.id_tienda
      AND s.estado = 1
    ORDER BY s.fecha_fin DESC NULLS LAST
    LIMIT 1;
    v_usable := v_offline IS TRUE
        AND v_fin IS NOT NULL
        AND v_fin > pg_catalog.now();
    RETURN jsonb_build_object(
        'success', true,
        'autentica', true,
        'usable_offline', v_usable,
        'id_constancia', v_row.id,
        'id_revision', v_row.id_revision,
        'huella', v_row.huella
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_m01_constancia_bloquear() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_m01_emitir_constancia_politica(bigint, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_m01_validar_constancia_politica(bigint, bigint, text, bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_emitir_constancia_politica(bigint, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_m01_validar_constancia_politica(bigint, bigint, text, bigint, jsonb) TO authenticated;

COMMIT;
