-- ============================================================================
-- 06_idempotencia_extra.sql
-- ----------------------------------------------------------------------------
-- Wrappers IDEMPOTENTES adicionales para la sincronización offline:
--   - fn_registrar_egreso_offline        (envuelve registrar_egreso_parcial_v2)
--   - fn_registrar_pago_venta_offline     (envuelve fn_registrar_pago_venta)
--   - fn_registrar_cambio_estado_offline  (envuelve fn_registrar_cambio_estado_operacion)
--
-- Problema que resuelve: al subir datos creados offline, si la conexión se cae
-- DESPUÉS de que el servidor procesó la operación pero ANTES de que el
-- dispositivo la marque como sincronizada, el reintento DUPLICABA egresos,
-- pagos o registros de cambio de estado (esos RPC no eran idempotentes).
--
-- Reusa la tabla de control creada en 04_fn_registrar_venta_offline.sql:
--   public.app_dat_operacion_offline_idempotencia (PK: client_uuid).
-- Como la PK es client_uuid, CADA propósito (venta/pago/estado/egreso) debe
-- enviar su PROPIO client_uuid. El cliente persiste uuids separados por orden:
--   client_uuid (venta), client_uuid_pago, client_uuid_estado.
--
-- Subir 04 (tabla) antes que este 06. El cliente trae fallback a los RPC
-- originales si estos wrappers aún no están desplegados.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Egreso parcial idempotente.
-- Devuelve el mismo jsonb que registrar_egreso_parcial_v2; si el client_uuid ya
-- fue procesado, devuelve idempotent=true sin volver a registrar.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_registrar_egreso_offline(
    p_client_uuid uuid,
    p_id_turno bigint,
    p_monto_entrega numeric,
    p_nombre_recibe character varying,
    p_nombre_autoriza character varying,
    p_motivo_entrega text,
    p_id_medio_pago smallint DEFAULT NULL,
    p_uuid_usuario uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_existing bigint;
    v_result jsonb;
    v_new_id bigint;
BEGIN
    -- 1) ¿Ya se procesó este egreso offline? -> devolver idempotente.
    SELECT id_operacion INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid;

    IF v_existing IS NOT NULL THEN
        RETURN jsonb_build_object(
            'success', true,
            'egreso_id', v_existing,
            'idempotent', true,
            'message', 'Egreso ya registrado previamente (idempotente)'
        );
    END IF;

    -- 2) Registrar usando la función existente.
    v_result := public.registrar_egreso_parcial_v2(
        p_id_turno := p_id_turno,
        p_monto_entrega := p_monto_entrega,
        p_nombre_recibe := p_nombre_recibe,
        p_nombre_autoriza := p_nombre_autoriza,
        p_motivo_entrega := p_motivo_entrega,
        p_id_medio_pago := p_id_medio_pago
    );

    -- 3) Si fue exitoso, persistir el mapeo de idempotencia.
    IF v_result IS NOT NULL AND (v_result->>'success') = 'true' THEN
        v_new_id := NULLIF(v_result->>'egreso_id', '')::bigint;
        IF v_new_id IS NOT NULL THEN
            INSERT INTO public.app_dat_operacion_offline_idempotencia
                (client_uuid, id_operacion, tipo, uuid_usuario)
            VALUES (p_client_uuid, v_new_id, 'egreso', p_uuid_usuario)
            ON CONFLICT (client_uuid) DO NOTHING;
        END IF;

        v_result := v_result || jsonb_build_object(
            'idempotent', false,
            'client_uuid', p_client_uuid
        );
    END IF;

    RETURN v_result;
END;
$function$;

-- ----------------------------------------------------------------------------
-- Registro de pagos de venta idempotente.
-- fn_registrar_pago_venta devuelve boolean; aquí devolvemos jsonb con idempotent.
-- Un client_uuid por operación de venta (el "client_uuid_pago" de la orden).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_registrar_pago_venta_offline(
    p_client_uuid uuid,
    p_id_operacion_venta bigint,
    p_pagos jsonb,
    p_uuid_usuario uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_existing bigint;
    v_ok boolean;
BEGIN
    -- 1) ¿Ya se registraron estos pagos? -> idempotente, no duplicar.
    SELECT id_operacion INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid;

    IF v_existing IS NOT NULL THEN
        RETURN jsonb_build_object(
            'success', true, 'idempotent', true,
            'id_operacion', v_existing,
            'message', 'Pagos ya registrados previamente (idempotente)'
        );
    END IF;

    -- 2) Registrar pagos usando la función existente.
    v_ok := public.fn_registrar_pago_venta(
        p_id_operacion_venta := p_id_operacion_venta,
        p_pagos := p_pagos
    );

    IF v_ok THEN
        INSERT INTO public.app_dat_operacion_offline_idempotencia
            (client_uuid, id_operacion, tipo, uuid_usuario)
        VALUES (p_client_uuid, p_id_operacion_venta, 'pago', p_uuid_usuario)
        ON CONFLICT (client_uuid) DO NOTHING;

        RETURN jsonb_build_object(
            'success', true, 'idempotent', false,
            'id_operacion', p_id_operacion_venta
        );
    END IF;

    RETURN jsonb_build_object(
        'success', false, 'message', 'El servidor rechazó el registro de pagos'
    );
END;
$function$;

-- ----------------------------------------------------------------------------
-- Cambio de estado de operación idempotente.
-- fn_registrar_cambio_estado_operacion devuelve void; aquí devolvemos jsonb.
-- Un client_uuid por cambio de estado (el "client_uuid_estado" de la orden).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_registrar_cambio_estado_offline(
    p_client_uuid uuid,
    p_id_operacion bigint,
    p_nuevo_estado smallint,
    p_uuid_usuario uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_existing bigint;
BEGIN
    -- 1) ¿Ya se aplicó este cambio de estado? -> idempotente.
    SELECT id_operacion INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid;

    IF v_existing IS NOT NULL THEN
        RETURN jsonb_build_object(
            'success', true, 'idempotent', true,
            'message', 'Cambio de estado ya aplicado (idempotente)'
        );
    END IF;

    -- 2) Aplicar el cambio de estado usando la función existente.
    PERFORM public.fn_registrar_cambio_estado_operacion(
        p_id_operacion := p_id_operacion,
        p_nuevo_estado := p_nuevo_estado,
        p_uuid_usuario := p_uuid_usuario
    );

    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario)
    VALUES (p_client_uuid, p_id_operacion, 'estado:' || p_nuevo_estado, p_uuid_usuario)
    ON CONFLICT (client_uuid) DO NOTHING;

    RETURN jsonb_build_object('success', true, 'idempotent', false);
END;
$function$;

-- ----------------------------------------------------------------------------
-- GRANTs (igual que 04/05).
-- ----------------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION public.fn_registrar_egreso_offline(uuid, bigint, numeric, character varying, character varying, text, smallint, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_registrar_egreso_offline(uuid, bigint, numeric, character varying, character varying, text, smallint, uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.fn_registrar_pago_venta_offline(uuid, bigint, jsonb, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_registrar_pago_venta_offline(uuid, bigint, jsonb, uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.fn_registrar_cambio_estado_offline(uuid, bigint, smallint, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_registrar_cambio_estado_offline(uuid, bigint, smallint, uuid) TO anon;
