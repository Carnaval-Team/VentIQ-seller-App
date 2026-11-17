BEGIN;

-- BORRADOR M01-R0i turno, personal y precio. NO EJECUTAR.
-- Recibir una orden anterior, anotar trabajadores del turno y registrar
-- un cambio de precio. El actor es auth.uid(). El replay no repite el efecto.
-- Requiere el predicado de la tienda del script 19. No crea columnas.

SET LOCAL app.m01_r0i_turno_personal_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r0i_turno_personal_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador R0i-turno-personal: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF to_regprocedure('public.fn_m01_puede_operar_tienda(bigint,bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta fn_m01_puede_operar_tienda del script 19';
    END IF;
    IF to_regprocedure('public.fn_m01_recibir_operacion_turno(uuid,bigint)') IS NOT NULL
       OR to_regprocedure('public.fn_m01_registrar_trabajador_turno(uuid,bigint,jsonb,timestamptz)') IS NOT NULL
       OR to_regprocedure('public.fn_m01_registrar_salida_trabajador(uuid,bigint,timestamptz)') IS NOT NULL
       OR to_regprocedure('public.fn_m01_registrar_cambio_precio(uuid,bigint,bigint,numeric,numeric,text,bigint)') IS NOT NULL THEN
        RAISE EXCEPTION 'Una funcion de turno o precio ya existe';
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

CREATE OR REPLACE FUNCTION public.fn_m01_recibir_operacion_turno(
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
    v_apertura timestamptz;
    v_op_store bigint;
    v_creada timestamptz;
    v_estado integer;
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
        IF v_existing.tipo IS DISTINCT FROM 'recibir_operacion'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
           OR v_existing.m01_id_tienda IS NULL
           OR v_existing.id_operacion IS DISTINCT FROM p_id_operacion THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object('success', true, 'idempotent', true);
    END IF;

    SELECT t.id_tienda, ct.id_tpv, ct.fecha_apertura
    INTO v_store, v_tpv, v_apertura
    FROM public.app_dat_caja_turno ct
    JOIN public.app_dat_tpv t ON t.id = ct.id_tpv
    WHERE ct.estado = 1
      AND public.fn_m01_puede_operar_tienda(t.id_tienda, ct.id_tpv)
    ORDER BY ct.fecha_apertura DESC NULLS LAST
    LIMIT 1;
    IF NOT FOUND OR v_store IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    SELECT o.id_tienda, o.created_at INTO v_op_store, v_creada
    FROM public.app_dat_operaciones o
    WHERE o.id = p_id_operacion
    FOR UPDATE;
    IF NOT FOUND OR v_op_store IS DISTINCT FROM v_store OR v_creada IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF v_creada >= v_apertura THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'La operación no es anterior al turno'
        );
    END IF;
    SELECT e.estado INTO v_estado
    FROM public.app_dat_estado_operacion e
    WHERE e.id_operacion = p_id_operacion
    ORDER BY e.id DESC
    LIMIT 1;
    IF v_estado IS NOT NULL AND v_estado IS DISTINCT FROM 1 THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'La operación ya no está pendiente'
        );
    END IF;
    UPDATE public.app_dat_operaciones
    SET created_at = now()
    WHERE id = p_id_operacion;
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, p_id_operacion, 'recibir_operacion', v_actor, v_request, v_store);
    RETURN jsonb_build_object('success', true, 'idempotent', false);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_m01_registrar_trabajador_turno(
    p_client_uuid uuid,
    p_id_turno bigint,
    p_ids jsonb,
    p_hora timestamptz
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
    IF v_actor IS NULL OR p_client_uuid IS NULL OR p_id_turno IS NULL
       OR p_hora IS NULL OR jsonb_typeof(p_ids) <> 'array' THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_request := jsonb_build_object(
        'version', 1, 'id_turno', p_id_turno, 'ids', p_ids, 'hora', p_hora
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));
    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'trabajador_turno'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
           OR v_existing.m01_id_tienda IS NULL
           OR v_existing.id_operacion IS DISTINCT FROM p_id_turno THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object('success', true, 'idempotent', true);
    END IF;
    SELECT t.id_tienda, ct.id_tpv INTO v_store, v_tpv
    FROM public.app_dat_caja_turno ct
    JOIN public.app_dat_tpv t ON t.id = ct.id_tpv
    WHERE ct.id = p_id_turno
    FOR SHARE OF ct;
    IF NOT FOUND OR v_store IS NULL
       OR public.fn_m01_puede_operar_tienda(v_store, v_tpv) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    INSERT INTO public.app_dat_turno_trabajadores (id_turno, id_trabajador, hora_entrada)
    SELECT p_id_turno, w.id, p_hora
    FROM jsonb_array_elements(p_ids) e
    JOIN public.app_dat_trabajadores w ON w.id = (e.value #>> '{}')::bigint
    WHERE w.id_tienda = v_store
      AND w.deleted_at IS NULL
      AND NOT EXISTS (
          SELECT 1 FROM public.app_dat_turno_trabajadores x
          WHERE x.id_turno = p_id_turno AND x.id_trabajador = w.id
      );
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, p_id_turno, 'trabajador_turno', v_actor, v_request, v_store);
    RETURN jsonb_build_object('success', true, 'idempotent', false);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_m01_registrar_salida_trabajador(
    p_client_uuid uuid,
    p_id_registro bigint,
    p_hora timestamptz
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
    IF v_actor IS NULL OR p_client_uuid IS NULL OR p_id_registro IS NULL OR p_hora IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_request := jsonb_build_object(
        'version', 1, 'id_registro', p_id_registro, 'hora', p_hora
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));
    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'salida_trabajador'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
           OR v_existing.m01_id_tienda IS NULL
           OR v_existing.id_operacion IS DISTINCT FROM p_id_registro THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object('success', true, 'idempotent', true);
    END IF;
    SELECT t.id_tienda, ct.id_tpv
    INTO v_store, v_tpv
    FROM public.app_dat_turno_trabajadores r
    JOIN public.app_dat_caja_turno ct ON ct.id = r.id_turno
    JOIN public.app_dat_tpv t ON t.id = ct.id_tpv
    WHERE r.id = p_id_registro
    FOR UPDATE OF r;
    IF NOT FOUND OR v_store IS NULL
       OR public.fn_m01_puede_operar_tienda(v_store, v_tpv) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    UPDATE public.app_dat_turno_trabajadores
    SET hora_salida = p_hora
    WHERE id = p_id_registro AND hora_salida IS NULL;
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, p_id_registro, 'salida_trabajador', v_actor, v_request, v_store);
    RETURN jsonb_build_object('success', true, 'idempotent', false);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_m01_registrar_cambio_precio(
    p_client_uuid uuid,
    p_id_producto bigint,
    p_id_variante bigint,
    p_precio_anterior numeric,
    p_precio_nuevo numeric,
    p_motivo text,
    p_id_tpv bigint
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
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL OR p_id_producto IS NULL
       OR p_id_tpv IS NULL OR p_precio_anterior IS NULL OR p_precio_nuevo IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF p_precio_anterior = p_precio_nuevo THEN
        RETURN jsonb_build_object('success', true, 'idempotent', true);
    END IF;
    v_request := jsonb_build_object(
        'version', 1,
        'id_producto', p_id_producto,
        'id_variante', p_id_variante,
        'precio_anterior', p_precio_anterior,
        'precio_nuevo', p_precio_nuevo,
        'motivo', p_motivo,
        'id_tpv', p_id_tpv
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));
    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'cambio_precio'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
           OR v_existing.m01_id_tienda IS NULL THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object('success', true, 'idempotent', true);
    END IF;
    SELECT t.id_tienda INTO v_store
    FROM public.app_dat_tpv t
    WHERE t.id = p_id_tpv;
    IF NOT FOUND OR v_store IS NULL
       OR public.fn_m01_puede_operar_tienda(v_store, p_id_tpv) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    INSERT INTO public.app_dat_cambio_precio (
        id_producto, id_variante, id_usuario, id_tpv,
        precio_anterior, precio_nuevo, motivo, monto_descontado
    ) VALUES (
        p_id_producto, p_id_variante, v_actor, p_id_tpv,
        p_precio_anterior, p_precio_nuevo, p_motivo,
        p_precio_anterior - p_precio_nuevo
    );
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, p_id_producto, 'cambio_precio', v_actor, v_request, v_store);
    RETURN jsonb_build_object('success', true, 'idempotent', false);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_m01_recibir_operacion_turno(uuid,bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_recibir_operacion_turno(uuid,bigint) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_m01_registrar_trabajador_turno(uuid,bigint,jsonb,timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_registrar_trabajador_turno(uuid,bigint,jsonb,timestamptz) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_m01_registrar_salida_trabajador(uuid,bigint,timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_registrar_salida_trabajador(uuid,bigint,timestamptz) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_m01_registrar_cambio_precio(uuid,bigint,bigint,numeric,numeric,text,bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_registrar_cambio_precio(uuid,bigint,bigint,numeric,numeric,text,bigint) TO authenticated;

COMMIT;
