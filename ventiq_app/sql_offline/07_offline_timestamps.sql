-- ============================================================================
-- 07_offline_timestamps.sql
-- ----------------------------------------------------------------------------
-- Preserva las marcas de tiempo generadas en el dispositivo al sincronizar:
--   - fecha_apertura del turno abierto offline
--   - created_at de ventas offline (fecha_creacion local)
--   - fecha_cierre del turno cerrado offline
--
-- Así las órdenes quedan dentro del intervalo del turno abierto offline,
-- aunque la sincronización ocurra horas después.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Apertura: añade p_fecha_apertura (opcional)
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.fn_apertura_turno_offline(
  uuid, numeric, bigint, bigint, uuid, boolean, jsonb, text
);

CREATE OR REPLACE FUNCTION public.fn_apertura_turno_offline(
    p_client_uuid uuid,
    p_efectivo_inicial numeric,
    p_id_tpv bigint,
    p_id_vendedor bigint,
    p_usuario uuid,
    p_maneja_inventario boolean DEFAULT false,
    p_productos jsonb DEFAULT '[]'::jsonb,
    p_observaciones text DEFAULT NULL,
    p_fecha_apertura timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_existing bigint;
    v_turno_abierto bigint;
    v_new_id bigint;
BEGIN
    SELECT id_operacion INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid AND tipo = 'apertura_turno';

    IF v_existing IS NOT NULL THEN
        RETURN jsonb_build_object(
            'status', 'success', 'id_turno', v_existing, 'idempotent', true
        );
    END IF;

    SELECT id INTO v_turno_abierto
    FROM app_dat_caja_turno
    WHERE id_tpv = p_id_tpv AND id_vendedor = p_id_vendedor AND estado = 1
    ORDER BY fecha_apertura DESC NULLS LAST
    LIMIT 1;

    IF v_turno_abierto IS NOT NULL THEN
        INSERT INTO public.app_dat_operacion_offline_idempotencia
            (client_uuid, id_operacion, tipo, uuid_usuario)
        VALUES (p_client_uuid, v_turno_abierto, 'apertura_turno', p_usuario)
        ON CONFLICT (client_uuid) DO NOTHING;

        RETURN jsonb_build_object(
            'status', 'success', 'id_turno', v_turno_abierto, 'idempotent', true,
            'message', 'Turno ya estaba abierto; reutilizado'
        );
    END IF;

    v_new_id := public.registrar_apertura_turno_v3(
        p_efectivo_inicial := p_efectivo_inicial,
        p_id_tpv := p_id_tpv,
        p_id_vendedor := p_id_vendedor,
        p_usuario := p_usuario,
        p_maneja_inventario := p_maneja_inventario,
        p_productos := p_productos,
        p_observaciones := p_observaciones
    );

    IF v_new_id IS NOT NULL THEN
        INSERT INTO public.app_dat_operacion_offline_idempotencia
            (client_uuid, id_operacion, tipo, uuid_usuario)
        VALUES (p_client_uuid, v_new_id, 'apertura_turno', p_usuario)
        ON CONFLICT (client_uuid) DO NOTHING;

        -- Forzar la hora real de apertura del dispositivo.
        IF p_fecha_apertura IS NOT NULL THEN
            UPDATE app_dat_caja_turno
            SET fecha_apertura = p_fecha_apertura
            WHERE id = v_new_id;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'status', 'success', 'id_turno', v_new_id, 'idempotent', false
    );
END;
$function$;

-- ----------------------------------------------------------------------------
-- Venta offline: añade p_fecha_creacion (opcional)
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.fn_registrar_venta_offline(
  uuid, bigint, uuid, jsonb, text, text, text, smallint, bigint
);

CREATE OR REPLACE FUNCTION public.fn_registrar_venta_offline(
    p_client_uuid uuid,
    p_id_tpv bigint,
    p_uuid uuid,
    p_productos jsonb,
    p_codigo_promocion text DEFAULT NULL,
    p_denominacion text DEFAULT NULL,
    p_observaciones text DEFAULT NULL,
    p_estado_inicial smallint DEFAULT 1,
    p_id_cliente bigint DEFAULT NULL,
    p_fecha_creacion timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_existing_op bigint;
    v_result jsonb;
    v_new_op bigint;
BEGIN
    SELECT id_operacion INTO v_existing_op
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid;

    IF v_existing_op IS NOT NULL THEN
        RETURN jsonb_build_object(
            'status', 'success',
            'id_operacion', v_existing_op,
            'idempotent', true,
            'message', 'Operación ya registrada previamente (idempotente)'
        );
    END IF;

    v_result := public.fn_registrar_venta(
        p_id_tpv := p_id_tpv,
        p_uuid := p_uuid,
        p_productos := p_productos,
        p_codigo_promocion := p_codigo_promocion,
        p_denominacion := p_denominacion,
        p_observaciones := p_observaciones,
        p_estado_inicial := p_estado_inicial,
        p_id_cliente := p_id_cliente
    );

    IF v_result IS NOT NULL AND (v_result->>'status') = 'success' THEN
        v_new_op := (v_result->>'id_operacion')::bigint;
        IF v_new_op IS NOT NULL THEN
            INSERT INTO public.app_dat_operacion_offline_idempotencia
                (client_uuid, id_operacion, tipo, uuid_usuario)
            VALUES (p_client_uuid, v_new_op, 'venta', p_uuid)
            ON CONFLICT (client_uuid) DO NOTHING;

            -- Aplicar la hora real de la venta en el dispositivo.
            IF p_fecha_creacion IS NOT NULL THEN
                UPDATE app_dat_operaciones
                SET created_at = p_fecha_creacion
                WHERE id = v_new_op;

                UPDATE app_dat_operacion_venta
                SET created_at = p_fecha_creacion
                WHERE id_operacion = v_new_op;
            END IF;
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
-- Cierre: añade p_fecha_cierre (opcional)
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.fn_cerrar_turno_offline(
  uuid, bigint, numeric, uuid, jsonb, text
);

CREATE OR REPLACE FUNCTION public.fn_cerrar_turno_offline(
    p_client_uuid uuid,
    p_id_tpv bigint,
    p_efectivo_real numeric,
    p_usuario uuid,
    p_productos jsonb DEFAULT '[]'::jsonb,
    p_observaciones text DEFAULT NULL,
    p_fecha_cierre timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_existing bigint;
    v_ok boolean;
    v_turno_abierto bigint;
BEGIN
    SELECT id_operacion INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid AND tipo = 'cierre_turno';

    IF v_existing IS NOT NULL THEN
        RETURN jsonb_build_object(
            'status', 'success', 'idempotent', true,
            'message', 'Cierre ya procesado'
        );
    END IF;

    SELECT id INTO v_turno_abierto
    FROM app_dat_caja_turno
    WHERE id_tpv = p_id_tpv AND estado = 1
    ORDER BY fecha_apertura DESC NULLS LAST
    LIMIT 1;

    IF v_turno_abierto IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'success', 'idempotent', true,
            'message', 'No hay turno abierto; nada que cerrar'
        );
    END IF;

    v_ok := public.fn_cerrar_turno_tpv(
        p_id_tpv := p_id_tpv,
        p_efectivo_real := p_efectivo_real,
        p_usuario := p_usuario,
        p_productos := p_productos,
        p_observaciones := p_observaciones
    );

    IF v_ok THEN
        INSERT INTO public.app_dat_operacion_offline_idempotencia
            (client_uuid, id_operacion, tipo, uuid_usuario)
        VALUES (p_client_uuid, v_turno_abierto, 'cierre_turno', p_usuario)
        ON CONFLICT (client_uuid) DO NOTHING;

        IF p_fecha_cierre IS NOT NULL THEN
            UPDATE app_dat_caja_turno
            SET fecha_cierre = p_fecha_cierre
            WHERE id = v_turno_abierto;
        END IF;

        RETURN jsonb_build_object('status', 'success', 'idempotent', false);
    END IF;

    RETURN jsonb_build_object(
        'status', 'error', 'message', 'El servidor rechazó el cierre del turno'
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_apertura_turno_offline(uuid, numeric, bigint, bigint, uuid, boolean, jsonb, text, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_apertura_turno_offline(uuid, numeric, bigint, bigint, uuid, boolean, jsonb, text, timestamptz) TO anon;
GRANT EXECUTE ON FUNCTION public.fn_registrar_venta_offline(uuid, bigint, uuid, jsonb, text, text, text, smallint, bigint, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_registrar_venta_offline(uuid, bigint, uuid, jsonb, text, text, text, smallint, bigint, timestamptz) TO anon;
GRANT EXECUTE ON FUNCTION public.fn_cerrar_turno_offline(uuid, bigint, numeric, uuid, jsonb, text, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_cerrar_turno_offline(uuid, bigint, numeric, uuid, jsonb, text, timestamptz) TO anon;
