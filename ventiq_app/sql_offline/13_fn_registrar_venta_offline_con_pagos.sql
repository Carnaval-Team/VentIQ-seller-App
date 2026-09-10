-- ============================================================================
-- 13_fn_registrar_venta_offline_con_pagos.sql
-- ----------------------------------------------------------------------------
-- Extiende fn_registrar_venta_offline para registrar app_dat_pago_venta en
-- la MISMA transacción que la venta.
--
-- Problema: la app llamaba fn_registrar_venta (o el wrapper offline) y luego
-- fn_registrar_pago_venta por separado. Si la segunda llamada fallaba, la
-- orden se marcaba sincronizada y el pago quedaba colgado.
--
-- Comportamiento:
--   1. Venta nueva: fn_registrar_venta + p_pagos. Si el pago falla, se hace
--      RAISE y se revierte también la venta.
--   2. Reintento idempotente: si la operación ya existe y aún no tiene filas
--      en app_dat_pago_venta, se registran los pagos (repara ops colgadas).
--
-- APLICAR MANUALMENTE en Supabase SQL Editor (después de 04 y 07 si existen).
-- ============================================================================

DROP FUNCTION IF EXISTS public.fn_registrar_venta_offline(
  uuid, bigint, uuid, jsonb, text, text, text, smallint, bigint
);
DROP FUNCTION IF EXISTS public.fn_registrar_venta_offline(
  uuid, bigint, uuid, jsonb, text, text, text, smallint, bigint, timestamptz
);
DROP FUNCTION IF EXISTS public.fn_registrar_venta_offline(
  uuid, bigint, uuid, jsonb, text, text, text, smallint, bigint, timestamptz, jsonb
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
    p_fecha_creacion timestamptz DEFAULT NULL,
    p_pagos jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_existing_op bigint;
    v_result jsonb;
    v_op bigint;
    v_ok boolean;
    v_idempotent boolean := false;
BEGIN
    SELECT id_operacion INTO v_existing_op
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid;

    IF v_existing_op IS NOT NULL THEN
        v_op := v_existing_op;
        v_idempotent := true;
        v_result := jsonb_build_object(
            'status', 'success',
            'id_operacion', v_op,
            'idempotent', true,
            'message', 'Operación ya registrada previamente (idempotente)'
        );
    ELSE
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

        IF v_result IS NULL OR (v_result->>'status') IS DISTINCT FROM 'success' THEN
            RETURN v_result;
        END IF;

        v_op := NULLIF(v_result->>'id_operacion', '')::bigint;
        IF v_op IS NULL THEN
            RAISE EXCEPTION 'fn_registrar_venta no devolvió id_operacion: %', v_result;
        END IF;

        INSERT INTO public.app_dat_operacion_offline_idempotencia
            (client_uuid, id_operacion, tipo, uuid_usuario)
        VALUES (p_client_uuid, v_op, 'venta', p_uuid)
        ON CONFLICT (client_uuid) DO NOTHING;

        IF p_fecha_creacion IS NOT NULL THEN
            UPDATE app_dat_operaciones
            SET created_at = p_fecha_creacion
            WHERE id = v_op;

            UPDATE app_dat_operacion_venta
            SET created_at = p_fecha_creacion
            WHERE id_operacion = v_op;
        END IF;

        v_result := v_result || jsonb_build_object(
            'idempotent', false,
            'client_uuid', p_client_uuid
        );
    END IF;

    -- Pagos en la misma transacción (venta nueva) o reparación (reintento).
    IF p_pagos IS NOT NULL
       AND jsonb_typeof(p_pagos) = 'array'
       AND jsonb_array_length(p_pagos) > 0 THEN
        IF NOT EXISTS (
            SELECT 1
            FROM public.app_dat_pago_venta
            WHERE id_operacion_venta = v_op
            LIMIT 1
        ) THEN
            v_ok := public.fn_registrar_pago_venta(
                p_id_operacion_venta := v_op,
                p_pagos := p_pagos
            );
            IF NOT COALESCE(v_ok, false) THEN
                RAISE EXCEPTION
                    'No se pudieron registrar los pagos de la operación %',
                    v_op;
            END IF;
        END IF;
        v_result := v_result || jsonb_build_object('pagos_registrados', true);
    END IF;

    RETURN v_result;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_registrar_venta_offline(
  uuid, bigint, uuid, jsonb, text, text, text, smallint, bigint, timestamptz, jsonb
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_registrar_venta_offline(
  uuid, bigint, uuid, jsonb, text, text, text, smallint, bigint, timestamptz, jsonb
) TO anon;
