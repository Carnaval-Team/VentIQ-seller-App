BEGIN;

-- BORRADOR M01-R0i configuración de tienda. NO EJECUTAR.
-- El TPV cambia modo restaurante, impresora, tickets, copias y el
-- autocompletado del conteo. Solo quien puede escribir la tienda. El actor
-- es auth.uid(). El replay no vuelve a cambiar el valor. No crea columnas.

SET LOCAL app.m01_r0i_config_tienda_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r0i_config_tienda_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador R0i-config-tienda: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta fn_config_tienda_puede_escribir';
    END IF;
    IF to_regprocedure('public.fn_m01_actualizar_config_tienda(uuid,bigint,text,jsonb)') IS NOT NULL THEN
        RAISE EXCEPTION 'fn_m01_actualizar_config_tienda ya existe';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'public.app_dat_operacion_offline_idempotencia'::regclass
          AND attname = 'm01_solicitud' AND atttypid = 'jsonb'::regtype AND NOT attisdropped
    ) THEN
        RAISE EXCEPTION 'Falta la evidencia compartida de idempotencia';
    END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.fn_m01_actualizar_config_tienda(
    p_client_uuid uuid,
    p_id_tienda bigint,
    p_campo text,
    p_valor jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_request jsonb;
    v_existing public.app_dat_operacion_offline_idempotencia%ROWTYPE;
    v_bool boolean;
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL OR p_id_tienda IS NULL
       OR p_campo IS NULL OR p_valor IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF p_campo NOT IN (
        'modo_restaurante',
        'guardar_impresora_por_defecto',
        'autocompletar_cantidad_real_conteo',
        'tickets_a_imprimir',
        'copias_por_ticket'
    ) THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF p_campo IN (
        'modo_restaurante',
        'guardar_impresora_por_defecto',
        'autocompletar_cantidad_real_conteo'
    ) THEN
        IF jsonb_typeof(p_valor) <> 'boolean' THEN
            RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
        END IF;
        v_bool := (p_valor #>> '{}')::boolean;
    ELSIF p_campo = 'tickets_a_imprimir' THEN
        IF jsonb_typeof(p_valor) <> 'array'
           OR jsonb_array_length(p_valor) > 20
           OR EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_valor) e
                WHERE jsonb_typeof(e.value) <> 'string'
                   OR length(e.value #>> '{}') = 0
                   OR length(e.value #>> '{}') > 40
           ) THEN
            RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
        END IF;
    ELSE
        IF jsonb_typeof(p_valor) <> 'object'
           OR (SELECT count(*) FROM jsonb_object_keys(p_valor)) > 20
           OR EXISTS (
                SELECT 1 FROM jsonb_each(p_valor) e
                WHERE length(e.key) = 0
                   OR length(e.key) > 40
                   OR jsonb_typeof(e.value) <> 'number'
                   OR (e.value #>> '{}')::numeric < 0
                   OR (e.value #>> '{}')::numeric > 20
                   OR (e.value #>> '{}')::numeric <> trunc((e.value #>> '{}')::numeric)
           ) THEN
            RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
        END IF;
    END IF;

    v_request := jsonb_build_object(
        'version', 1, 'campo', p_campo, 'valor', p_valor
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));
    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'config_tienda'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
           OR v_existing.m01_id_tienda IS DISTINCT FROM p_id_tienda THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object('success', true, 'idempotent', true);
    END IF;

    IF public.fn_config_tienda_puede_escribir(p_id_tienda) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    IF p_campo = 'modo_restaurante' THEN
        INSERT INTO public.app_dat_configuracion_tienda (id_tienda, modo_restaurante)
        SELECT p_id_tienda, v_bool
        WHERE NOT EXISTS (
            SELECT 1 FROM public.app_dat_configuracion_tienda
            WHERE id_tienda = p_id_tienda
        );
        UPDATE public.app_dat_configuracion_tienda
        SET modo_restaurante = v_bool, updated_at = now()
        WHERE id_tienda = p_id_tienda;
    ELSIF p_campo = 'guardar_impresora_por_defecto' THEN
        INSERT INTO public.app_dat_configuracion_tienda (id_tienda, guardar_impresora_por_defecto)
        SELECT p_id_tienda, v_bool
        WHERE NOT EXISTS (
            SELECT 1 FROM public.app_dat_configuracion_tienda
            WHERE id_tienda = p_id_tienda
        );
        UPDATE public.app_dat_configuracion_tienda
        SET guardar_impresora_por_defecto = v_bool, updated_at = now()
        WHERE id_tienda = p_id_tienda;
    ELSIF p_campo = 'autocompletar_cantidad_real_conteo' THEN
        INSERT INTO public.app_dat_configuracion_tienda (id_tienda, autocompletar_cantidad_real_conteo)
        SELECT p_id_tienda, v_bool
        WHERE NOT EXISTS (
            SELECT 1 FROM public.app_dat_configuracion_tienda
            WHERE id_tienda = p_id_tienda
        );
        UPDATE public.app_dat_configuracion_tienda
        SET autocompletar_cantidad_real_conteo = v_bool, updated_at = now()
        WHERE id_tienda = p_id_tienda;
    ELSIF p_campo = 'tickets_a_imprimir' THEN
        INSERT INTO public.app_dat_configuracion_tienda (id_tienda, tickets_a_imprimir)
        SELECT p_id_tienda, p_valor
        WHERE NOT EXISTS (
            SELECT 1 FROM public.app_dat_configuracion_tienda
            WHERE id_tienda = p_id_tienda
        );
        UPDATE public.app_dat_configuracion_tienda
        SET tickets_a_imprimir = p_valor, updated_at = now()
        WHERE id_tienda = p_id_tienda;
    ELSE
        INSERT INTO public.app_dat_configuracion_tienda (id_tienda, copias_por_ticket)
        SELECT p_id_tienda, p_valor
        WHERE NOT EXISTS (
            SELECT 1 FROM public.app_dat_configuracion_tienda
            WHERE id_tienda = p_id_tienda
        );
        UPDATE public.app_dat_configuracion_tienda
        SET copias_por_ticket = p_valor, updated_at = now()
        WHERE id_tienda = p_id_tienda;
    END IF;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, p_id_tienda, 'config_tienda', v_actor, v_request, p_id_tienda);
    RETURN jsonb_build_object('success', true, 'idempotent', false);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_m01_actualizar_config_tienda(uuid,bigint,text,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_actualizar_config_tienda(uuid,bigint,text,jsonb) TO authenticated;

COMMIT;
