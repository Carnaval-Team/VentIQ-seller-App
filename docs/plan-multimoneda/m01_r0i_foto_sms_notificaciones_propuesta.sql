BEGIN;

-- BORRADOR M01-R0i foto, SMS y notificaciones. NO EJECUTAR.
-- Quitar la foto, limpiar el SMS de una transferencia y reactivar o borrar
-- una notificación propia. Marcar como leída ya usa
-- fn_marcar_notificacion_leida, que comprueba auth.uid(); no se reemplaza.
-- El replay no repite el efecto. Requiere la evidencia del script 13 y el
-- predicado del script 19.

SET LOCAL app.m01_r0i_foto_sms_notif_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r0i_foto_sms_notif_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador R0i-foto-sms-notif: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF to_regprocedure('public.fn_m01_puede_operar_tienda(bigint,bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta fn_m01_puede_operar_tienda del script 19';
    END IF;
    IF to_regprocedure('public.fn_m01_quitar_foto_operacion(uuid,bigint)') IS NOT NULL
       OR to_regprocedure('public.fn_m01_limpiar_pago_sms(uuid,bigint)') IS NOT NULL
       OR to_regprocedure('public.fn_m01_reactivar_notificaciones_venta(uuid,jsonb)') IS NOT NULL
       OR to_regprocedure('public.fn_m01_eliminar_notificacion(uuid,bigint)') IS NOT NULL THEN
        RAISE EXCEPTION 'Una funcion de foto, SMS o notificacion ya existe';
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

CREATE FUNCTION public.fn_m01_quitar_foto_operacion(
    p_client_uuid uuid,
    p_id_operacion bigint
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
    v_store bigint;
    v_tpv bigint;
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL OR p_id_operacion IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_request := jsonb_build_object('version', 1, 'id_operacion', p_id_operacion);
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));
    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'quitar_foto'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
           OR v_existing.m01_id_tienda IS NULL
           OR v_existing.id_operacion IS DISTINCT FROM p_id_operacion THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object('success', true, 'idempotent', true);
    END IF;
    SELECT o.id_tienda, ov.id_tpv INTO v_store, v_tpv
    FROM public.app_dat_operaciones o
    JOIN public.app_dat_operacion_venta ov ON ov.id_operacion = o.id
    WHERE o.id = p_id_operacion
    FOR UPDATE OF ov;
    IF NOT FOUND OR v_store IS NULL
       OR public.fn_m01_puede_operar_tienda(v_store, v_tpv) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    UPDATE public.app_dat_operacion_venta
       SET foto_operacion_url = NULL
     WHERE id_operacion = p_id_operacion;
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, p_id_operacion, 'quitar_foto', v_actor, v_request, v_store);
    RETURN jsonb_build_object('success', true, 'idempotent', false);
END;
$function$;

CREATE FUNCTION public.fn_m01_limpiar_pago_sms(
    p_client_uuid uuid,
    p_id_operacion bigint
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
    v_store bigint;
    v_tpv bigint;
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL OR p_id_operacion IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_request := jsonb_build_object('version', 1, 'id_operacion', p_id_operacion);
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));
    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'limpiar_pago_sms'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
           OR v_existing.m01_id_tienda IS NULL
           OR v_existing.id_operacion IS DISTINCT FROM p_id_operacion THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object('success', true, 'idempotent', true);
    END IF;
    SELECT o.id_tienda, ov.id_tpv INTO v_store, v_tpv
    FROM public.app_dat_operaciones o
    JOIN public.app_dat_operacion_venta ov ON ov.id_operacion = o.id
    WHERE o.id = p_id_operacion
    FOR UPDATE OF ov;
    IF NOT FOUND OR v_store IS NULL
       OR public.fn_m01_puede_operar_tienda(v_store, v_tpv) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    UPDATE public.app_dat_operacion_venta
       SET pago_sms_json = NULL
     WHERE id_operacion = p_id_operacion;
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, p_id_operacion, 'limpiar_pago_sms', v_actor, v_request, v_store);
    RETURN jsonb_build_object('success', true, 'idempotent', false);
END;
$function$;

CREATE FUNCTION public.fn_m01_reactivar_notificaciones_venta(
    p_client_uuid uuid,
    p_orden_ids jsonb
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
    v_count integer := 0;
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL
       OR jsonb_typeof(p_orden_ids) <> 'array'
       OR jsonb_array_length(p_orden_ids) = 0
       OR jsonb_array_length(p_orden_ids) > 50 THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_request := jsonb_build_object('version', 1, 'ordenes', p_orden_ids);
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));
    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'reactivar_notificacion'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
           OR v_existing.m01_id_tienda IS NULL THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object('success', true, 'idempotent', true, 'count', 0);
    END IF;
    UPDATE public.app_dat_notificaciones n
       SET leida = false, leida_at = NULL
     WHERE n.user_id = v_actor
       AND n.tipo = 'venta'
       AND n.data->>'orden_id' IN (
           SELECT e.value #>> '{}' FROM jsonb_array_elements(p_orden_ids) e
       );
    GET DIAGNOSTICS v_count = ROW_COUNT;
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, v_count, 'reactivar_notificacion', v_actor, v_request, 0);
    RETURN jsonb_build_object('success', true, 'idempotent', false, 'count', v_count);
END;
$function$;

CREATE FUNCTION public.fn_m01_eliminar_notificacion(
    p_client_uuid uuid,
    p_id_notificacion bigint
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
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL OR p_id_notificacion IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_request := jsonb_build_object('version', 1, 'id', p_id_notificacion);
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));
    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'eliminar_notificacion'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
           OR v_existing.m01_id_tienda IS NULL
           OR v_existing.id_operacion IS DISTINCT FROM p_id_notificacion THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object('success', true, 'idempotent', true);
    END IF;
    DELETE FROM public.app_dat_notificaciones
     WHERE id = p_id_notificacion AND user_id = v_actor;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, p_id_notificacion, 'eliminar_notificacion', v_actor, v_request, 0);
    RETURN jsonb_build_object('success', true, 'idempotent', false);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_m01_quitar_foto_operacion(uuid,bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_quitar_foto_operacion(uuid,bigint) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_m01_limpiar_pago_sms(uuid,bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_limpiar_pago_sms(uuid,bigint) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_m01_reactivar_notificaciones_venta(uuid,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_reactivar_notificaciones_venta(uuid,jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_m01_eliminar_notificacion(uuid,bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_eliminar_notificacion(uuid,bigint) TO authenticated;

COMMIT;
